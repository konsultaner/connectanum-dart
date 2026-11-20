@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/websocket/native_websocket_frames_io.dart';
import 'package:test/test.dart';

Uint8List _frame(int opcode, bool fin, List<int> payload) {
  final bytes = BytesBuilder(copy: false)..addByte((fin ? 128 : 0) | opcode);
  if (payload.length < 126) {
    bytes.addByte(payload.length);
  } else if (payload.length < 65536) {
    bytes.addByte(126);
    bytes.add((ByteData(2)..setUint16(0, payload.length)).buffer.asUint8List());
  } else {
    bytes.addByte(127);
    bytes.add((ByteData(8)..setUint64(0, payload.length)).buffer.asUint8List());
  }
  bytes.add(payload);
  return bytes.takeBytes();
}

Uint8List _join(Iterable<Uint8List> parts) =>
    (BytesBuilder(copy: false)..addStreamParts(parts)).takeBytes();

extension on BytesBuilder {
  void addStreamParts(Iterable<Uint8List> parts) {
    for (final part in parts) {
      add(part);
    }
  }
}

Future<List<Uint8List>> _transform(
  List<Uint8List> chunks, {
  int maximum = 1024 * 1024,
  int minimum = 8,
}) => coalesceNativeWebSocketFrames(
  Stream.fromIterable(chunks),
  maximumPayloadBytes: maximum,
  minimumPayloadBytes: minimum,
).toList();

void main() {
  test(
    'invalid first header bytes flush before any further input arrives',
    () async {
      final source = StreamController<Uint8List>(sync: true);
      final result = <Uint8List>[];
      final subscription = coalesceNativeWebSocketFrames(
        source.stream,
      ).listen(result.add);
      final prefix = _frame(1, false, List.filled(31, 65));
      source.add(prefix);
      expect(result, isEmpty);
      source.add(Uint8List.fromList([0xc0]));
      expect(_join(result), [...prefix, 0xc0]);
      await subscription.cancel();
      await source.close();
    },
  );

  test(
    'complete text and binary fragments retain all bytes at every split',
    () async {
      final payload = Uint8List.fromList(List.generate(257, (i) => i & 255));
      for (final opcode in [1, 2]) {
        final wire = _join([
          _frame(opcode, false, payload.sublist(0, 11)),
          _frame(0, false, payload.sublist(11, 199)),
          _frame(0, true, payload.sublist(199)),
        ]);
        for (var split = 0; split <= wire.length; split++) {
          final result = await _transform([
            Uint8List.sublistView(wire, 0, split),
            Uint8List.sublistView(wire, split),
          ]);
          expect(result, hasLength(1));
          final info = nativeWebSocketFrame(result.single)!;
          expect(info.text, opcode == 1);
          expect(result.single[0], 128 | opcode);
          expect(
            Uint8List.sublistView(result.single, info.headerLength),
            payload,
          );
        }
      }
    },
  );

  test(
    'native storage is private and a retained payload view owns its buffer',
    () async {
      final payload = Uint8List.fromList(List.generate(65537, (i) => i % 251));
      final wire = _frame(2, true, payload);
      var roots = await _transform([
        Uint8List.sublistView(wire, 0, 100),
        Uint8List.sublistView(wire, 100),
      ]);
      final info = nativeWebSocketFrame(roots.single)!;
      final view = Uint8List.sublistView(roots.single, info.headerLength);
      wire.fillRange(0, wire.length, 0xee);
      expect(view, payload);
      final builder = BytesBuilder(copy: false)..add(view);
      final sdkPayload = builder.takeBytes();
      sdkPayload[0] = 0x91;
      expect(
        view[0],
        0x91,
        reason: 'single-part SDK payload must retain the native view',
      );
      roots = [];
      await Future<void>.delayed(Duration.zero);
      expect(view.sublist(1), payload.sublist(1));
    },
  );

  test('each completed message has independent storage', () async {
    final first = List<int>.filled(64, 7), second = List<int>.filled(64, 9);
    final firstWire = _frame(2, true, first);
    final secondWire = _frame(2, true, second);
    final result = await _transform([
      Uint8List.sublistView(firstWire, 0, 32),
      Uint8List.sublistView(firstWire, 32),
      Uint8List.sublistView(secondWire, 0, 32),
      Uint8List.sublistView(secondWire, 32),
    ]);
    expect(result, hasLength(2));
    result.first[nativeWebSocketFrame(result.first)!.headerLength] = 0;
    expect(
      result.last.sublist(nativeWebSocketFrame(result.last)!.headerLength),
      second,
    );
  });

  test(
    'an already contiguous binary payload needs no additional native copy',
    () async {
      final wire = _frame(2, true, List.filled(65537, 7));
      final result = await _transform([wire]);
      expect(_join(result), wire);
      expect(
        result.every((part) => nativeWebSocketFrame(part) == null),
        isTrue,
      );
      expect(result.last.buffer, wire.buffer);
    },
  );

  test(
    'small messages and capacity overflow preserve exact original wire',
    () async {
      for (final maximum in [0, 31, 63]) {
        final wire = _join([
          _frame(2, false, List.filled(32, 1)),
          _frame(0, true, List.filled(32, 2)),
        ]);
        final result = await _transform([wire], maximum: maximum);
        expect(_join(result), wire);
        expect(
          result.every((part) => nativeWebSocketFrame(part) == null),
          isTrue,
        );
      }
      final tiny = _frame(1, true, [65]);
      expect(_join(await _transform([tiny])), tiny);
    },
  );

  test(
    'control interruptions preserve data and control ordering byte-for-byte',
    () async {
      for (final control in [8, 9, 10]) {
        final wire = _join([
          _frame(1, false, List.filled(31, 65)),
          _frame(control, true, control == 8 ? [3, 232] : [80]),
          _frame(0, true, List.filled(31, 66)),
        ]);
        for (var split = 0; split <= wire.length; split++) {
          final result = await _transform([
            Uint8List.sublistView(wire, 0, split),
            Uint8List.sublistView(wire, split),
          ]);
          expect(_join(result), wire);
        }
      }
    },
  );

  test('invalid headers keep the original SDK rejection stream', () async {
    final invalid = <List<int>>[
      [0xc0, 0],
      [0x83, 0],
      [0x09, 0],
      [0x82, 0],
      [0x80, 0x80, 1, 2, 3, 4],
      [0x89, 126, 0, 1, 65],
      [0x80, 126, 0, 1, 65],
      [0x80, 127, 128, 0, 0, 0, 0, 0, 0, 0],
      [0x80, 127, 0, 0, 0, 0, 0, 0, 0, 1, 65],
    ];
    for (final malformed in invalid) {
      final wire = _join([
        _frame(1, false, List.filled(31, 65)),
        Uint8List.fromList(malformed),
      ]);
      final result = await _transform([wire]);
      expect(_join(result), wire, reason: '$malformed');
    }
  });

  test(
    'EOF at every partial header or body retains exact pending bytes',
    () async {
      final wire = _join([
        _frame(1, false, List.filled(17, 65)),
        _frame(0, true, List.filled(257, 66)),
      ]);
      for (var end = 0; end < wire.length; end++) {
        final partial = Uint8List.sublistView(wire, 0, end);
        final result = await _transform([partial]);
        expect(_join(result), partial, reason: 'end=$end');
      }
    },
  );

  test(
    'I/O errors retain identity after exact original pending data',
    () async {
      final error = StateError('source failed');
      final partial = _frame(1, false, List.filled(19, 65));
      Stream<Uint8List> input() async* {
        yield partial;
        throw error;
      }

      final events = <Object>[];
      final done = Completer<void>();
      coalesceNativeWebSocketFrames(input(), minimumPayloadBytes: 8).listen(
        events.add,
        onError: (Object value) => events.add(value),
        onDone: done.complete,
      );
      await done.future;
      expect(events.last, same(error));
      expect(_join(events.whereType<Uint8List>()), partial);
    },
  );

  test(
    'header and source-fragment bookkeeping limits fall back without loss',
    () async {
      final fragmented = _join([
        _frame(2, false, List.filled(16, 7)),
        for (var i = 0; i < 2050; i++) _frame(0, false, []),
        _frame(0, true, []),
      ]);
      expect(_join(await _transform([fragmented])), fragmented);
      final wire = _frame(2, true, List.filled(5000, 9));
      expect(
        _join(
          await _transform([
            for (final byte in wire) Uint8List.fromList([byte]),
          ]),
        ),
        wire,
      );
    },
  );

  test('pause and cancellation propagate while a message is staged', () async {
    var paused = false, canceled = false;
    final source = StreamController<Uint8List>(
      sync: true,
      onPause: () => paused = true,
      onResume: () => paused = false,
      onCancel: () => canceled = true,
    );
    final result = <Uint8List>[];
    final subscription = coalesceNativeWebSocketFrames(
      source.stream,
    ).listen(result.add);
    source.add(_frame(2, false, List.filled(31, 7)));
    subscription.pause();
    expect(paused, isTrue);
    subscription.resume();
    expect(paused, isFalse);
    await subscription.cancel();
    expect(canceled, isTrue);
    expect(result, isEmpty);
    await source.close();
  });
}
