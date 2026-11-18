@TestOn('vm')
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/message/event.dart' as event_msg;
import 'package:connectanum_core/src/message/goodbye.dart' as goodbye_msg;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

event_msg.Event _event(int index, Uint8List bytes) => event_msg.Event(
  index + 1,
  index + 101,
  event_msg.EventDetails(publisher: 7, topic: 'sensors/µ')
    ..custom['mqtt_topic'] = 'sensors/µ',
  arguments: List<dynamic>.filled(1, bytes, growable: false),
);

void _sendEvents(List<SendPort> targets) {
  final storage = Uint8List.fromList(List.generate(65544, (i) => i % 251));
  final bytes = Uint8List.sublistView(storage, 3, 65539);
  final events = [_event(0, bytes), _event(1, bytes)];
  for (final target in targets) {
    // A transferable belongs to one send graph, including shared recipients.
    final batch = WorkerBinaryTransferBatch();
    target.send([for (final event in events) batch.prepare(event)]);
  }
  storage.fillRange(0, storage.length, 0);
  for (final event in events) {
    event.details.custom['mqtt_topic'] = 'changed after send';
  }
}

void main() {
  test(
    'binary EVENT bodies materialize once in the receiving isolate',
    () async {
      final port = ReceivePort();
      addTearDown(port.close);
      final received = port.first;
      await Isolate.spawn(_sendEvents, [port.sendPort]);
      final events =
          (await received.timeout(const Duration(seconds: 10)) as List)
              .cast<event_msg.Event>();
      expect(
        events.map(WorkerBinaryTransferBatch.hasPendingArguments),
        everyElement(isTrue),
      );
      final body = events.first.arguments!.single as Uint8List;
      expect(identical(body, events.last.arguments!.single), isTrue);
      expect(
        events.map(WorkerBinaryTransferBatch.hasPendingArguments),
        everyElement(isFalse),
      );
      final expected = Uint8List.fromList(
        List.generate(65536, (i) => (i + 3) % 251),
      );
      expect(body, expected);
      for (var index = 0; index < events.length; index++) {
        for (final codec in [
          NativeMessageSerializer.json,
          NativeMessageSerializer.messagePack,
          NativeMessageSerializer.cbor,
          NativeMessageSerializer.flatbuffers,
        ]) {
          expect(
            encodeMessage(codec, events[index]),
            encodeMessage(codec, _event(index, expected)),
          );
        }
      }
      // The existing fixed-length argument list remains mutable by element.
      expect(() => events.first.arguments!.length = 2, throwsUnsupportedError);
      events.first.arguments![0] = Uint8List.fromList([9]);
      expect(events.first.arguments!.single, [9]);
      expect(events.last.arguments!.single, expected);
    },
  );

  test('independent worker graphs own independent binary transfers', () async {
    final ports = [ReceivePort(), ReceivePort()];
    addTearDown(() {
      for (final port in ports) {
        port.close();
      }
    });
    final pending = [for (final port in ports) port.first];
    await Isolate.spawn(_sendEvents, [for (final port in ports) port.sendPort]);
    final replies = await Future.wait(
      pending,
    ).timeout(const Duration(seconds: 10));
    final bodies = <Uint8List>[];
    for (final reply in replies) {
      final events = (reply as List).cast<event_msg.Event>();
      expect(
        WorkerBinaryTransferBatch.hasPendingArguments(events.first),
        isTrue,
      );
      bodies.add(events.first.arguments!.single as Uint8List);
      expect(identical(events.last.arguments!.single, bodies.last), isTrue);
    }
    expect(identical(bodies.first, bodies.last), isFalse);
    bodies.first[0] = 0;
    expect(bodies.last[0], 3);
  });

  test('special payloads and small events keep their original message', () {
    final bytes = Uint8List(65536);
    final lazy = _event(0, bytes)
      ..setLazyPayload(
        argumentsBytes: Uint8List.fromList([0x91, 0xc6, 0, 1, 0, 0, ...bytes]),
        argumentsDecoder: (_) => throw StateError('unexpected lazy decoding'),
        encoding: LazyPayloadEncoding.messagePack,
      );
    final messages = <AbstractMessage>[
      goodbye_msg.Goodbye(null, 'wamp.close.normal'),
      _event(0, Uint8List(16383)),
      _event(0, bytes)..argumentsKeywords = {},
      _event(0, bytes)..details.pptScheme = 'mqtt',
      _event(0, bytes)..details.pptSerializer = 'cbor',
      _event(0, bytes)..details.pptCipher = 'cipher',
      _event(0, bytes)..details.pptKeyId = 'key',
      _event(0, bytes)..transparentBinaryPayload = bytes,
      lazy,
    ];
    final batch = WorkerBinaryTransferBatch();
    for (final message in messages) {
      expect(batch.prepare(message), same(message));
    }
  });
}
