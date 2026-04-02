@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:convert';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_router/src/native/message_binding.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  group('bindMessage', () {
    test('decodes CBOR payloads with lazy args and kwargs', () {
      final frameBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codePublish,
            42,
            <String, Object?>{},
            'bench.topic',
          ]),
        ),
      );
      final argsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue(['payload'])),
      );
      final kwargsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'flag': true})),
      );

      final message = bindMessage(
        NativeMessageSerializer.cbor,
        frameBytes,
        argsBytes: argsBytes,
        kwargsBytes: kwargsBytes,
      );

      expect(message, isA<Publish>());
      final publish = message as Publish;
      expect(publish.topic, 'bench.topic');
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      expect(publish.arguments, ['payload']);
      expect(publish.argumentsKeywords, {'flag': true});
    });

    test('preserves custom option fields on inbound control messages', () {
      final publishBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codePublish,
            42,
            <String, Object?>{
              'acknowledge': true,
              'trace_id': 'pub-1',
              'blob': Uint8List.fromList(const [1, 2, 3]),
            },
            'bench.topic',
          ]),
        ),
      );
      final callBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codeCall,
            44,
            <String, Object?>{
              'receive_progress': true,
              'trace_id': 'call-1',
              'nested': {'flag': true},
            },
            'bench.proc',
          ]),
        ),
      );
      final yieldBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codeYield,
            45,
            <String, Object?>{
              'progress': false,
              'trace_id': 'yield-1',
              'nested': {
                'blob': Uint8List.fromList(const [4, 5]),
              },
            },
          ]),
        ),
      );

      final publish =
          bindMessage(NativeMessageSerializer.cbor, publishBytes) as Publish;
      final call = bindMessage(NativeMessageSerializer.cbor, callBytes) as Call;
      final yield =
          bindMessage(NativeMessageSerializer.cbor, yieldBytes) as Yield;

      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.custom['trace_id'], equals('pub-1'));
      expect(
        publish.options?.custom['blob'],
        orderedEquals(Uint8List.fromList(const [1, 2, 3])),
      );

      expect(call.options?.receiveProgress, isTrue);
      expect(call.options?.custom['trace_id'], equals('call-1'));
      expect(call.options?.custom['nested'], equals(const {'flag': true}));

      expect(yield.options?.progress, isFalse);
      expect(yield.options?.custom['trace_id'], equals('yield-1'));
      expect(
        (yield.options?.custom['nested'] as Map)['blob'],
        orderedEquals(Uint8List.fromList(const [4, 5])),
      );
    });

    test('normalizes JSON binary sentinels inside custom option fields', () {
      final frameBytes = Uint8List.fromList(
        utf8.encode(
          '[48,44,{"trace_id":"call-1","blob":"\\\\u0000AQID","nested":{"payload":"\\\\u0000BAUG"}},"bench.proc"]',
        ),
      );

      final call =
          bindMessage(NativeMessageSerializer.json, frameBytes) as Call;

      expect(call.options?.custom['trace_id'], equals('call-1'));
      expect(
        call.options?.custom['blob'],
        orderedEquals(Uint8List.fromList(const [1, 2, 3])),
      );
      expect(
        (call.options?.custom['nested'] as Map)['payload'],
        orderedEquals(Uint8List.fromList(const [4, 5, 6])),
      );
    });
  });
}
