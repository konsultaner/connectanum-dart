import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('WampCborXsalsa20Poly1305Provider', () {
    test('round-trips payloads and populates outbound ppt metadata', () {
      final provider = _testProvider();
      final options = PublishOptions(pptScheme: 'wamp');

      final packed = provider.packPayload(
        const ['wrapped'],
        const {'worker': 7},
        options,
      );
      final unpacked = provider.unpackPayload(packed, options);

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

    test('throws explicit key errors when no default key id is available', () {
      final provider = WampCborXsalsa20Poly1305Provider(
        keys: {'first': _testKey(), 'second': _testKey(seed: 32)},
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
      final packed = provider.packPayload(
        const ['wrapped'],
        const {'worker': 7},
        options,
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
}

WampCborXsalsa20Poly1305Provider _testProvider() {
  return WampCborXsalsa20Poly1305Provider.single(
    keyId: 'test-key',
    key: _testKey(),
  );
}

Uint8List _testKey({int seed = 0}) {
  return Uint8List.fromList(
    List<int>.generate(32, (index) => (seed + index + 1) & 0xff),
  );
}
