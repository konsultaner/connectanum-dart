@TestOn('vm')
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/event.dart';
import 'package:connectanum_core/connectanum_core.dart'
    show LazyPayloadEncoding;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

const _frameSizes = [
  0,
  64,
  16370,
  16371,
  16372,
  16373,
  16383,
  16384,
  65536,
  131072,
];

void _sendFrames(List<Object> input) {
  final target = input[0] as SendPort;
  final serializer = NativeMessageSerializer.values[input[1] as int];
  for (final size in _frameSizes) {
    final storage = Uint8List.fromList(List.generate(size + 8, (i) => i % 251));
    final body = Uint8List.sublistView(storage, 3, size + 3);
    sendWorkerMessagePayload(
      target,
      serializer,
      Event(1, size + 1, EventDetails(), arguments: [body]),
      {'connectionId': 7, 'bodyLength': size},
    );
    storage.fillRange(0, storage.length, 0);
  }
}

void main() {
  for (final serializer in [
    NativeMessageSerializer.json,
    NativeMessageSerializer.messagePack,
    NativeMessageSerializer.cbor,
    NativeMessageSerializer.flatbuffers,
  ]) {
    test(
      'large ${serializer.name} frames cross isolates with transferred ownership',
      () async {
        final port = ReceivePort();
        addTearDown(port.close);
        final received = port.take(_frameSizes.length).toList();
        await Isolate.spawn(_sendFrames, <Object>[
          port.sendPort,
          serializer.index,
        ]);
        final frames = await received.timeout(const Duration(seconds: 10));
        for (final value in frames) {
          final frame = value as Map;
          final size = frame['bodyLength'] as int;
          expect(frame['connectionId'], 7);
          final expected = encodeMessage(
            serializer,
            Event(
              1,
              size + 1,
              EventDetails(),
              arguments: [
                Uint8List.fromList(List.generate(size, (i) => (i + 3) % 251)),
              ],
            ),
          );
          final payload = frame['payload'];
          expect(
            payload,
            expected.length >= 16384
                ? isA<TransferableTypedData>()
                : isA<Uint8List>(),
          );
          final bytes = payload is TransferableTypedData
              ? payload.materialize().asUint8List()
              : payload as Uint8List;
          expect(bytes, expected);
        }
      },
    );
  }
  test(
    'transferred MessagePack frames preserve keywords, PPT and lazy bytes',
    () async {
      final port = ReceivePort();
      addTearDown(port.close);
      final received = port.take(3).toList();
      final expected = <Uint8List>[];
      for (final kind in ['keywords', 'ppt', 'lazy']) {
        final body = Uint8List.fromList(List.generate(65536, (i) => i % 251));
        final lazyBytes = Uint8List.fromList([0x91, 0xc6, 0, 1, 0, 0, ...body]);
        final message = switch (kind) {
          'keywords' => Event(
            1,
            2,
            EventDetails(),
            arguments: [body],
            argumentsKeywords: {'topic': 'α'},
          ),
          'ppt' => Event(
            1,
            2,
            EventDetails(pptScheme: 'mqtt', pptSerializer: 'msgpack'),
          )..transparentBinaryPayload = body,
          _ =>
            Event(1, 2, EventDetails())..setLazyPayload(
              argumentsBytes: lazyBytes,
              argumentsDecoder: (_) =>
                  throw StateError('Unexpected lazy decoding'),
              encoding: LazyPayloadEncoding.messagePack,
            ),
        };
        expected.add(
          encodeMessage(NativeMessageSerializer.messagePack, message),
        );
        sendWorkerMessagePayload(
          port.sendPort,
          NativeMessageSerializer.messagePack,
          message,
          {'kind': kind},
        );
        body.fillRange(0, body.length, 0);
        lazyBytes.fillRange(0, lazyBytes.length, 0);
      }
      final frames = await received.timeout(const Duration(seconds: 10));
      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i] as Map;
        expect(frame['kind'], ['keywords', 'ppt', 'lazy'][i]);
        expect(frame['payload'], isA<TransferableTypedData>());
        expect(
          (frame['payload'] as TransferableTypedData)
              .materialize()
              .asUint8List(),
          expected[i],
        );
      }
    },
  );
}
