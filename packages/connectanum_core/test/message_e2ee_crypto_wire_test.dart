import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:pinenacl/api.dart' show EncryptedMessage;
import 'package:pinenacl/x25519.dart' show SecretBox;
import 'package:pointycastle/export.dart'
    show AEADParameters, AESEngine, GCMBlockCipher, KeyParameter;
import 'package:test/test.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
  for (final typed in [false, true]) {
    for (final aes in [false, true]) {
      for (final length in [0, 1, 15, 16, 17, 31, 32, 65536]) {
        test('${typed ? 'typed' : 'CBOR'} ${aes ? 'AES' : 'XSalsa'} '
            '$length bytes match allocating crypto APIs', () {
          final storage = Uint8List(length + 9)..fillRange(0, length + 9, 0xab);
          final input = Uint8List.sublistView(storage, 3, 3 + length);
          for (var i = 0; i < input.length; i++) {
            input[i] = (i * 29) & 0xff;
          }
          final original = Uint8List.fromList(storage);
          final plaintext = typed
              ? input
              : cbor.Serializer().serializePPT(PPTPayload(arguments: [input]));
          final provider = _provider(typed, aes, key);
          final options = PublishOptions(pptScheme: 'wamp');
          final packed = provider.packPayload([input], null, options);
          final encrypted = packed.single as Uint8List;
          final nonceLength = aes ? 12 : 24;
          final nonce = Uint8List.sublistView(encrypted, 0, nonceLength);
          expect(encrypted.length, plaintext.length + nonceLength + 16);
          expect(encrypted, _encrypt(aes, plaintext, key, nonce));
          expect(_decrypt(aes, encrypted, key), plaintext);
          expect(storage, original, reason: 'encryption must not mutate input');

          // Exercise the receive API with a span rather than the start of an
          // allocation, including the oracle's independent encrypted output.
          final oracleBytes = _encrypt(aes, plaintext, key, nonce);
          final receiveStorage = Uint8List(oracleBytes.length + 11)
            ..fillRange(0, oracleBytes.length + 11, 0xcd)
            ..setRange(5, 5 + oracleBytes.length, oracleBytes);
          final receiveOriginal = Uint8List.fromList(receiveStorage);
          final received = provider.unpackPayload([
            Uint8List.sublistView(receiveStorage, 5, 5 + oracleBytes.length),
          ], options);
          expect(received.arguments, [input]);
          expect(received.argumentsKeywords, isNull);
          expect(receiveStorage, receiveOriginal);
          // Outbound ciphertext keeps the existing mutable Uint8List contract.
          encrypted[encrypted.length - 1] ^= 1;
          expect(
            () => provider.unpackPayload(packed, options),
            throwsA(isA<WampE2eeDecryptionException>()),
          );
        });
      }
    }
  }
}

WampE2eeProvider _provider(bool typed, bool aes, Uint8List key) {
  final keys = {'key': key};
  if (typed) {
    return aes
        ? WampFlatBuffersAes256GcmProvider(keys: keys, defaultKeyId: 'key')
        : WampFlatBuffersXsalsa20Poly1305Provider(
            keys: keys,
            defaultKeyId: 'key',
          );
  }
  return aes
      ? WampCborAes256GcmProvider(keys: keys, defaultKeyId: 'key')
      : WampCborXsalsa20Poly1305Provider(keys: keys, defaultKeyId: 'key');
}

GCMBlockCipher _aes(bool encrypt, Uint8List key, Uint8List nonce) =>
    GCMBlockCipher(AESEngine())..init(
      encrypt,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );

Uint8List _encrypt(
  bool aes,
  Uint8List plaintext,
  Uint8List key,
  Uint8List nonce,
) {
  if (!aes) {
    return Uint8List.fromList(SecretBox(key).encrypt(plaintext, nonce: nonce));
  }
  final body = _aes(true, key, nonce).process(plaintext);
  return Uint8List(nonce.length + body.length)
    ..setRange(0, nonce.length, nonce)
    ..setRange(nonce.length, nonce.length + body.length, body);
}

Uint8List _decrypt(bool aes, Uint8List encrypted, Uint8List key) => aes
    ? _aes(
        false,
        key,
        Uint8List.sublistView(encrypted, 0, 12),
      ).process(Uint8List.sublistView(encrypted, 12))
    : SecretBox(key).decrypt(EncryptedMessage.fromList(encrypted));
