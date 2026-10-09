import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:pinenacl/x25519.dart' show SecretBox;
import 'package:test/test.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final nonce = Uint8List.fromList(List.generate(24, (i) => i));
  test('typed XSalsa rejects every truncated nonce/tag frame', () {
    final provider = WampFlatBuffersXsalsa20Poly1305Provider.single(
      keyId: 'key',
      key: key,
    );
    for (var length = 0; length < 40; length++) {
      expect(
        () => provider.unpackPayload([Uint8List(length)], PublishOptions()),
        throwsA(isA<WampE2eeDecryptionException>()),
        reason: '$length bytes',
      );
    }
  });
  for (final length in [1024 * 1024 - 40, 1024 * 1024 - 39, 2 * 1024 * 1024]) {
    test(
      'typed XSalsa receives $length bytes across the legacy wrapper limit',
      () {
        final input = Uint8List(length);
        input[0] = 129;
        input[length - 1] = 37;
        // Encrypt through the independent library API. Its explicit constructor
        // supports this size; only its default fromList receive wrapper is capped.
        final encrypted = Uint8List.fromList(
          SecretBox(key).encrypt(input, nonce: nonce),
        );
        final storage = Uint8List(encrypted.length + 7)
          ..setRange(3, 3 + encrypted.length, encrypted);
        final provider = WampFlatBuffersXsalsa20Poly1305Provider.single(
          keyId: 'key',
          key: key,
        );
        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'flatbuffers',
          pptKeyId: 'key',
        );
        final result = provider.unpackPayload([
          Uint8List.sublistView(storage, 3, 3 + encrypted.length),
        ], options);
        expect(result.arguments, [input]);
        expect(result.argumentsKeywords, isNull);
        expect(
          Uint8List.sublistView(storage, 3, 3 + encrypted.length),
          encrypted,
        );
        storage[3 + encrypted.length - 1] ^= 1;
        expect(
          () => provider.unpackPayload([
            Uint8List.sublistView(storage, 3, 3 + encrypted.length),
          ], options),
          throwsA(isA<WampE2eeDecryptionException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test('legacy CBOR XSalsa keeps its existing receive-size behavior', () {
    final provider = WampCborXsalsa20Poly1305Provider.single(
      keyId: 'key',
      key: key,
    );
    final options = PublishOptions(pptScheme: 'wamp');
    final packed = provider.packPayload(
      [Uint8List(2 * 1024 * 1024)],
      null,
      options,
    );
    expect(
      () => provider.unpackPayload(packed, options),
      throwsA(isA<WampE2eeDecryptionException>()),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
