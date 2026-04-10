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

    test('binds request metadata without a full frame', () {
      final helloDetailsBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue({
            'roles': {'dealer': {}},
            'authid': 'bench-user',
          }),
        ),
      );
      final authenticateExtraBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'nonce': 'abc123'})),
      );
      final publishDetailsBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue({'acknowledge': true, 'trace_id': 'pub-1'}),
        ),
      );
      final argsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue(['payload'])),
      );
      final kwargsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'flag': true})),
      );

      final hello =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeHello,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: helloDetailsBytes,
                stringA: 'bench.realm',
              )
              as Hello;
      final authenticate =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeAuthenticate,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: authenticateExtraBytes,
                stringA: 'sig',
              )
              as Authenticate;
      final publish =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codePublish,
                primaryId: 42,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: publishDetailsBytes,
                stringA: 'bench.topic',
                argsBytes: argsBytes,
                kwargsBytes: kwargsBytes,
              )
              as Publish;

      expect(hello.realm, 'bench.realm');
      expect(hello.details.authid, 'bench-user');
      expect(hello.details.roles?.dealer, isNotNull);

      expect(authenticate.signature, 'sig');
      expect(authenticate.extra, {'nonce': 'abc123'});

      expect(publish.topic, 'bench.topic');
      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.custom['trace_id'], 'pub-1');
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      expect(publish.arguments, ['payload']);
      expect(publish.argumentsKeywords, {'flag': true});
    });

    test('binds unsubscribe metadata without a full frame', () {
      final message =
          bindMessageFromMetadata(
                NativeMessageSerializer.json,
                messageCode: MessageTypes.codeUnsubscribe,
                primaryId: 7,
                secondaryId: 9,
                detailNumberA: 0,
                flags: 1 << 4,
              )
              as Unsubscribe;

      expect(message.requestId, 7);
      expect(message.subscriptionId, 9);
    });

    test('binds direct control metadata without decoding details maps', () {
      final publish =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codePublish,
                primaryId: 7,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3) | (1 << 6),
                stringA: 'bench.topic',
                stringB: 'wamp',
                stringC: 'cbor',
              )
              as Publish;
      final subscribe =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeSubscribe,
                primaryId: 8,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'bench.topic',
                stringB: 'prefix',
                stringC: 'meta.topic',
              )
              as Subscribe;
      final call =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeCall,
                primaryId: 9,
                secondaryId: 0,
                detailNumberA: 1500,
                flags: (1 << 4) | (1 << 0) | (1 << 1) | (1 << 3) | (1 << 5),
                stringA: 'bench.proc',
                stringB: 'wamp',
                stringC: 'cbor',
              )
              as Call;
      final cancel =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeCancel,
                primaryId: 10,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0),
                stringA: 'killnowait',
              )
              as Cancel;
      final register =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeRegister,
                primaryId: 11,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'bench.proc',
                stringB: 'prefix',
                stringC: 'roundrobin',
              )
              as Register;
      final yield =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeYield,
                primaryId: 12,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'wamp',
                stringB: 'cbor',
                stringC: 'aes',
                stringD: 'key-1',
              )
              as Yield;
      final unsubscribed =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeUnsubscribed,
                primaryId: 13,
                secondaryId: 0,
                detailNumberA: 99,
                flags: (1 << 4) | (1 << 0) | (1 << 1),
                stringA: 'wamp.close.normal',
              )
              as Unsubscribed;

      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.discloseMe, isTrue);
      expect(publish.options?.pptScheme, 'wamp');
      expect(publish.options?.pptSerializer, 'cbor');

      expect(subscribe.options?.match, 'prefix');
      expect(subscribe.options?.metaTopic, 'meta.topic');
      expect(subscribe.options?.getRetained, isTrue);

      expect(call.options?.receiveProgress, isTrue);
      expect(call.options?.discloseMe, isTrue);
      expect(call.options?.timeout, 1500);
      expect(call.options?.pptScheme, 'wamp');
      expect(call.options?.pptSerializer, 'cbor');

      expect(cancel.options?.mode, 'killnowait');

      expect(register.options?.discloseCaller, isTrue);
      expect(register.options?.match, 'prefix');
      expect(register.options?.invoke, 'roundrobin');

      expect(yield.options?.progress, isTrue);
      expect(yield.options?.pptScheme, 'wamp');
      expect(yield.options?.pptSerializer, 'cbor');
      expect(yield.options?.pptCipher, 'aes');
      expect(yield.options?.pptKeyId, 'key-1');

      expect(unsubscribed.unsubscribeRequestId, 13);
      expect(unsubscribed.details?.subscription, 99);
      expect(unsubscribed.details?.reason, 'wamp.close.normal');
    });
  });
}
