import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

import 'support/e2ee_assertions.dart';

void main() {
  test('E2EE success assertion evaluates once and preserves identity', () {
    final value = Object();
    var calls = 0;
    expect(
      expectE2eeSuccess(() {
        calls++;
        return value;
      }),
      same(value),
    );
    expect(calls, 1);
    expect(expectE2eeSuccess<Object?>(() => null), isNull);
  });
  test('E2EE success assertion preserves timeouts', () {
    final failure = TimeoutException('fixture timeout');
    expect(
      () => expectE2eeSuccess(() => throw failure),
      throwsA(same(failure)),
    );
  });
  test('E2EE success assertion rejects unexpected errors', () {
    expect(
      () => expectE2eeSuccess(() => throw StateError('fixture failure')),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'diagnostic',
          contains('fixture failure'),
        ),
      ),
    );
  });
  group('WampCborXsalsa20Poly1305Provider', () {
    test('round-trips payloads and populates outbound ppt metadata', () {
      final provider = _testProvider();
      final options = PublishOptions(pptScheme: 'wamp');

      final packed = expectE2eeSuccess(
        () => provider.packPayload(
          const ['wrapped'],
          const {'worker': 7},
          options,
        ),
      );
      final unpacked = expectE2eeSuccess(
        () => provider.unpackPayload(packed, options),
      );

      expect(options.pptSerializer, equals('cbor'));
      expect(
        options.pptCipher,
        equals(WampCborXsalsa20Poly1305Provider.supportedCipher),
      );
      expect(options.pptKeyId, equals('test-key'));
      expect(packed, hasLength(1));
      expect(packed.single, isA<Uint8List>());
      expect(unpacked.arguments, equals(const ['wrapped']));
      expect(unpacked.argumentsKeywords, equals(const {'worker': 7}));
    });

    test('selects a key id from runtime context when options omit it', () {
      final provider = expectE2eeSuccess(
        () => WampCborXsalsa20Poly1305Provider(
          keys: {'kid-alpha': _testKey(), 'kid-beta': _testKey(seed: 32)},
          keySelectionPolicy: (runtimeContext, _) =>
              runtimeContext.uri == 'policy.topic.beta'
              ? 'kid-beta'
              : 'kid-alpha',
        ),
      );
      final runtimeContext = const WampE2eeRuntimeContext(
        direction: WampE2eeDirection.outbound,
        messageType: WampE2eeMessageType.publish,
        uri: 'policy.topic.beta',
      );
      final packOptions = PublishOptions(
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
      );

      final packed = expectE2eeSuccess(
        () => provider.packPayload(
          const ['wrapped'],
          const {'worker': 7},
          packOptions,
          runtimeContext: runtimeContext,
        ),
      );

      expect(packOptions.pptKeyId, equals('kid-beta'));

      final unpackOptions = PublishOptions(
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
      );
      final unpacked = expectE2eeSuccess(
        () => provider.unpackPayload(
          packed,
          unpackOptions,
          runtimeContext: runtimeContext.copyWith(
            direction: WampE2eeDirection.inbound,
          ),
        ),
      );

      expect(unpackOptions.pptKeyId, equals('kid-beta'));
      expect(unpacked.arguments, equals(const ['wrapped']));
      expect(unpacked.argumentsKeywords, equals(const {'worker': 7}));
    });

    test('throws explicit key errors when no default key id is available', () {
      final provider = expectE2eeSuccess(
        () => WampCborXsalsa20Poly1305Provider(
          keys: {'first': _testKey(), 'second': _testKey(seed: 32)},
        ),
      );

      expect(
        () => provider.packPayload(
          const ['wrapped'],
          null,
          PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
        ),
        throwsA(isA<WampE2eeKeyNotFoundException>()),
      );
    });

    test('throws explicit cipher errors for unsupported ciphers', () {
      final provider = _testProvider();

      expect(
        () => provider.packPayload(
          const ['wrapped'],
          null,
          PublishOptions(
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
            pptCipher: 'aes256gcm',
          ),
        ),
        throwsA(isA<WampE2eeUnsupportedCipherException>()),
      );
    });

    test('throws explicit decryption errors for tampered ciphertext', () {
      final provider = _testProvider();
      final options = PublishOptions(pptScheme: 'wamp');
      final packed = expectE2eeSuccess(
        () => provider.packPayload(
          const ['wrapped'],
          const {'worker': 7},
          options,
        ),
      );
      final tampered = Uint8List.fromList((packed.single as Uint8List));
      tampered[tampered.length - 1] ^= 1;

      expect(
        () => provider.unpackPayload(List<dynamic>.from(tampered), options),
        throwsA(isA<WampE2eeInvalidPayloadException>()),
      );
      expect(
        () => provider.unpackPayload(<dynamic>[tampered], options),
        throwsA(isA<WampE2eeDecryptionException>()),
      );
    });
  });

  group('WampCborAes256GcmProvider', () {
    test('round-trips payloads and populates outbound ppt metadata', () {
      final provider = expectE2eeSuccess(
        () => WampCborAes256GcmProvider.single(
          keyId: 'kid-current',
          key: _testKey(),
        ),
      );
      final options = PublishOptions(pptScheme: 'wamp');

      final packed = expectE2eeSuccess(
        () => provider.packPayload(
          const ['wrapped'],
          const {'worker': 7},
          options,
        ),
      );
      final unpacked = expectE2eeSuccess(
        () => provider.unpackPayload(packed, options),
      );

      expect(options.pptSerializer, equals('cbor'));
      expect(
        options.pptCipher,
        equals(WampCborAes256GcmProvider.supportedCipher),
      );
      expect(options.pptKeyId, equals('kid-current'));
      expect((packed.single as Uint8List).length, greaterThan(28));
      expect(unpacked.arguments, equals(const ['wrapped']));
      expect(unpacked.argumentsKeywords, equals(const {'worker': 7}));
    });

    test('uses the selected rotation key and rejects tampering', () {
      final provider = expectE2eeSuccess(
        () => WampCborAes256GcmProvider(
          keys: {'kid-old': _testKey(), 'kid-current': _testKey(seed: 32)},
          keySelectionPolicy: (_, _) => 'kid-current',
        ),
      );
      final options = PublishOptions(pptScheme: 'wamp');

      final packed = expectE2eeSuccess(
        () => provider.packPayload(
          const ['rotated'],
          null,
          options,
          runtimeContext: const WampE2eeRuntimeContext(
            direction: WampE2eeDirection.outbound,
            messageType: WampE2eeMessageType.publish,
          ),
        ),
      );
      expect(options.pptKeyId, equals('kid-current'));

      final tampered = Uint8List.fromList(packed.single as Uint8List);
      tampered[tampered.length - 1] ^= 1;
      expect(
        () => provider.unpackPayload(<dynamic>[tampered], options),
        throwsA(isA<WampE2eeDecryptionException>()),
      );
    });
  });

  group('WampE2eeKeySelectionPolicies', () {
    test(
      'uses negotiated session key ids for outbound and inbound fallback',
      () {
        final policy = WampE2eeKeySelectionPolicies.negotiated();
        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );

        expect(
          policy(
            const WampE2eeRuntimeContext(
              direction: WampE2eeDirection.outbound,
              messageType: WampE2eeMessageType.publish,
              negotiated: {
                'peer_key_id': 'kid-peer',
                'accepted_key_id': 'kid-accepted',
              },
            ),
            options,
          ),
          equals('kid-peer'),
        );
        expect(
          policy(
            const WampE2eeRuntimeContext(
              direction: WampE2eeDirection.inbound,
              messageType: WampE2eeMessageType.result,
              negotiated: {
                'accepted_key_id': 'kid-accepted',
                'peer_key_id': 'kid-peer',
              },
            ),
            options,
          ),
          equals('kid-accepted'),
        );
      },
    );

    test('composes peer rules ahead of negotiated fallback', () {
      final policy = WampE2eeKeySelectionPolicies.firstDefined([
        WampE2eeKeySelectionPolicies.rules([
          const WampE2eeKeySelectionRule(
            keyId: 'kid-trusted-peer',
            directions: [WampE2eeDirection.inbound],
            messageTypes: [WampE2eeMessageType.event],
            uriPrefixes: ['bench.secure.'],
            peerAuthProviders: ['remote-auth'],
            minPeerTrustLevel: 50,
          ),
        ]),
        WampE2eeKeySelectionPolicies.negotiated(),
      ]);
      final options = PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor');
      final baseContext = const WampE2eeRuntimeContext(
        direction: WampE2eeDirection.inbound,
        messageType: WampE2eeMessageType.event,
        uri: 'bench.secure.topic',
        peer: WampE2eePartyContext(authProvider: 'remote-auth', trustLevel: 80),
        negotiated: {'receive_key_id': 'kid-negotiated'},
      );

      expect(policy(baseContext, options), equals('kid-trusted-peer'));
      expect(
        policy(
          expectE2eeSuccess(
            () => baseContext.copyWith(
              peer: const WampE2eePartyContext(
                authProvider: 'remote-auth',
                trustLevel: 10,
              ),
            ),
          ),
          options,
        ),
        equals('kid-negotiated'),
      );
    });
  });
}

WampCborXsalsa20Poly1305Provider _testProvider() {
  return expectE2eeSuccess(
    () => WampCborXsalsa20Poly1305Provider.single(
      keyId: 'test-key',
      key: _testKey(),
    ),
  );
}

Uint8List _testKey({int seed = 0}) {
  return Uint8List.fromList(
    List<int>.generate(32, (index) => (seed + index + 1) & 0xff),
  );
}
