@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_router/src/router/router_instance/internal_reply_forwarder.dart';
import 'package:test/test.dart';

void _echoReply(SendPort output) async {
  final input = ReceivePort();
  output.send(input.sendPort);
  final message = await input.first;
  input.close();
  output.send(message);
}

void main() {
  test(
    'same-isolate send preserves payload and controls before retirement',
    () async {
      final input = ReceivePort();
      addTearDown(input.close);
      final payload = <String, Object?>{
        'argumentsBytes': Uint8List.fromList([0x81, 0x01]),
        'argumentsKeywords': {
          'body': [1, 2, 3],
        },
        'nativeHandle': 9007199254740992,
      };
      final envelope = <String, Object?>{
        'type': 'result',
        'progress': true,
        'pptScheme': 'opaque',
        'pptSerializer': 'flatbuffers',
        'pptCipher': null,
        'details': {'custom': true},
        internalSessionLazyPayloadKey: payload,
        'arguments': [7],
        'argumentsKeywords': {'legacy': 8},
      };
      final snapshot = Map<String, Object?>.from(envelope);
      final received = input.first;
      expect(forwardInternalSessionReply(input.sendPort, envelope), isFalse);
      expect(await received, snapshot);
      expect(envelope.keys, isNot(contains(internalSessionLazyPayloadKey)));
      expect(envelope.keys, isNot(contains('arguments')));
      expect(envelope.keys, isNot(contains('argumentsKeywords')));
      expect(envelope['details'], {'custom': true});
      expect(payload['argumentsKeywords'], {
        'body': [1, 2, 3],
      });
    },
  );

  test('cross-isolate send keeps the complete detached reply', () async {
    final input = ReceivePort();
    final iterator = StreamIterator<Object?>(input);
    final worker = await Isolate.spawn(_echoReply, input.sendPort);
    addTearDown(() async {
      await iterator.cancel();
      input.close();
      worker.kill(priority: Isolate.immediate);
    });
    expect(await iterator.moveNext(), isTrue);
    final port = iterator.current as SendPort;
    final bytes = Uint8List.fromList([0, 128, 255]);
    final envelope = <String, Object?>{
      'type': 'result',
      'progress': false,
      internalSessionLazyPayloadKey: {'bytes': bytes},
      'pptSerializer': 'flatbuffers',
    };
    expect(forwardInternalSessionReply(port, envelope), isTrue);
    bytes[0] = 99;
    expect(await iterator.moveNext(), isTrue);
    final reply = iterator.current as Map;
    expect(reply['type'], 'result');
    expect(reply['pptSerializer'], 'flatbuffers');
    expect((reply[internalSessionLazyPayloadKey] as Map)['bytes'], [
      0,
      128,
      255,
    ]);
    expect(envelope, isNot(contains(internalSessionLazyPayloadKey)));
  });

  test(
    'progressive, final and error replies retain their independent contents',
    () async {
      final input = ReceivePort();
      addTearDown(input.close);
      final replies = input.take(3).toList();
      for (final (type, progress, terminal) in [
        ('result', true, false),
        ('result', false, true),
        ('error', false, true),
      ]) {
        final reply = <String, Object?>{
          'type': type,
          'progress': progress,
          'error': type == 'error' ? 'app.error' : null,
          'details': {'marker': type},
          'pptScheme': 'wamp',
          'pptCipher': 'aes256gcm',
          'pptKeyId': 'key',
          internalSessionLazyPayloadKey: {
            'arguments': [type, progress],
          },
        };
        expect(forwardInternalSessionReply(input.sendPort, reply), terminal);
      }
      final result = await replies;
      expect(result.map((reply) => (reply as Map)['progress']), [
        true,
        false,
        false,
      ]);
      expect((result[2] as Map)['error'], 'app.error');
      for (final item in result.cast<Map>()) {
        expect(item['details'], {'marker': item['type']});
        expect(item['pptCipher'], 'aes256gcm');
        expect(item['pptKeyId'], 'key');
        expect((item[internalSessionLazyPayloadKey] as Map)['arguments'], [
          item['type'],
          item['progress'],
        ]);
      }
    },
  );

  test('immutable envelopes forward without a new mutation failure', () async {
    final input = ReceivePort();
    addTearDown(input.close);
    final reply = Map<String, Object?>.unmodifiable({
      'type': 'result',
      internalSessionLazyPayloadKey: {
        'arguments': [42],
      },
    });
    final received = input.first;
    expect(forwardInternalSessionReply(input.sendPort, reply), isTrue);
    expect(await received, reply);
    expect(reply, contains(internalSessionLazyPayloadKey));
  });

  test(
    'missing flags and unknown reply types preserve continuation semantics',
    () async {
      final input = ReceivePort();
      addTearDown(input.close);
      final cases = <(Map<String, Object?>, bool)>[
        ({'type': 'result'}, true),
        ({'type': 'result', 'progress': null}, true),
        ({'type': 'event', 'progress': 'ignored'}, false),
        ({}, false),
        ({'type': 'error', 'progress': 'ignored', 'error': 'app.error'}, true),
      ];
      final received = input.take(cases.length).toList();
      final expected = <Map<String, Object?>>[];
      final payload = Map<String, Object?>.unmodifiable({
        'arguments': [11, 13],
      });
      for (final (fields, terminal) in cases) {
        final reply = {...fields, internalSessionLazyPayloadKey: payload};
        expected.add(Map<String, Object?>.from(reply));
        expect(forwardInternalSessionReply(input.sendPort, reply), terminal);
        expect(reply, isNot(contains(internalSessionLazyPayloadKey)));
      }
      expect(await received, expected);
      expect(payload, {
        'arguments': [11, 13],
      });
    },
  );

  test('transferable byte ownership survives envelope retirement', () async {
    final input = ReceivePort();
    addTearDown(input.close);
    final bytes = TransferableTypedData.fromList([
      Uint8List.fromList([3, 5, 8]),
    ]);
    final reply = <String, Object?>{
      'type': 'result',
      internalSessionLazyPayloadKey: {'argumentsBytes': bytes},
    };
    final received = input.first;
    expect(forwardInternalSessionReply(input.sendPort, reply), isTrue);
    final payload =
        ((await received as Map)[internalSessionLazyPayloadKey] as Map);
    expect(
      (payload['argumentsBytes'] as TransferableTypedData)
          .materialize()
          .asUint8List(),
      [3, 5, 8],
    );
    expect(bytes.materialize, throwsArgumentError);
  });

  test('send failure leaves the envelope available to its caller', () {
    final input = ReceivePort();
    final unsendable = ReceivePort();
    addTearDown(input.close);
    addTearDown(unsendable.close);
    final payload = {'port': unsendable};
    final reply = <String, Object?>{
      'type': 'result',
      internalSessionLazyPayloadKey: payload,
    };
    expect(
      () => forwardInternalSessionReply(input.sendPort, reply),
      throwsArgumentError,
    );
    expect(identical(reply[internalSessionLazyPayloadKey], payload), isTrue);
  });

  test('closed ports retain the SDK drop semantics without retaining data', () {
    final input = ReceivePort();
    final port = input.sendPort;
    input.close();
    final reply = <String, Object?>{
      'type': 'result',
      internalSessionLazyPayloadKey: {
        'arguments': [1, 2],
      },
    };
    expect(forwardInternalSessionReply(port, reply), isTrue);
    expect(reply, isNot(contains(internalSessionLazyPayloadKey)));
  });

  test(
    'malformed progress keeps the existing forward-before-validation behavior',
    () async {
      final input = ReceivePort();
      addTearDown(input.close);
      final reply = <String, Object?>{
        'type': 'result',
        'progress': 'invalid',
        internalSessionLazyPayloadKey: {
          'arguments': [1],
        },
      };
      final received = input.first;
      expect(
        () => forwardInternalSessionReply(input.sendPort, reply),
        throwsA(isA<TypeError>()),
      );
      expect(await received, reply);
      expect(reply, contains(internalSessionLazyPayloadKey));
    },
  );
}
