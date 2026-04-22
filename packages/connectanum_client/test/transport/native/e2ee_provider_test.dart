import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  group('NativeWampCborXsalsa20Poly1305Provider', () {
    tearDown(NativeClientRuntime.shutdownShared);

    test('round-trips payloads and populates PPT metadata', () {
      final provider = NativeWampCborXsalsa20Poly1305Provider.single(
        keyId: 'kid-1',
        key: List<int>.generate(32, (index) => index + 1),
      );
      addTearDown(provider.release);

      final options = PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor');
      final packed = provider.packPayload(
        const ['wrapped'],
        const {'worker': 4},
        options,
      );

      expect(options.pptCipher, equals('xsalsa20poly1305'));
      expect(options.pptKeyId, equals('kid-1'));
      expect(packed, hasLength(1));
      expect(packed.single, isA<Uint8List>());

      final decoded = provider.unpackPayload(packed, options);
      expect(decoded.arguments, equals(const ['wrapped']));
      expect(decoded.argumentsKeywords, equals(const {'worker': 4}));
    });

    test('interoperates with the pure Dart provider', () {
      final key = List<int>.generate(32, (index) => index + 1);
      final nativeProvider = NativeWampCborXsalsa20Poly1305Provider.single(
        keyId: 'kid-1',
        key: key,
      );
      addTearDown(nativeProvider.release);
      final dartProvider = WampCborXsalsa20Poly1305Provider.single(
        keyId: 'kid-1',
        key: key,
      );

      final nativeOptions = PublishOptions(
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
      );
      final nativePacked = nativeProvider.packPayload(
        const ['native'],
        const {'path': 'dart'},
        nativeOptions,
      );
      final dartDecoded = dartProvider.unpackPayload(
        nativePacked,
        nativeOptions,
      );
      expect(dartDecoded.arguments, equals(const ['native']));
      expect(dartDecoded.argumentsKeywords, equals(const {'path': 'dart'}));

      final dartOptions = PublishOptions(
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
      );
      final dartPacked = dartProvider.packPayload(
        const ['dart'],
        const {'path': 'native'},
        dartOptions,
      );
      final nativeDecoded = nativeProvider.unpackPayload(
        dartPacked,
        dartOptions,
      );
      expect(nativeDecoded.arguments, equals(const ['dart']));
      expect(nativeDecoded.argumentsKeywords, equals(const {'path': 'native'}));
    });

    test('maps wrong-key decrypts to the core decryption exception', () {
      final encryptingProvider = NativeWampCborXsalsa20Poly1305Provider.single(
        keyId: 'kid-1',
        key: List<int>.generate(32, (index) => index + 1),
      );
      final decryptingProvider = NativeWampCborXsalsa20Poly1305Provider.single(
        keyId: 'kid-1',
        key: List<int>.generate(32, (index) => index + 33),
      );
      addTearDown(encryptingProvider.release);
      addTearDown(decryptingProvider.release);

      final options = PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor');
      final packed = encryptingProvider.packPayload(
        const ['wrapped'],
        null,
        options,
      );

      expect(
        () => decryptingProvider.unpackPayload(packed, options),
        throwsA(isA<WampE2eeDecryptionException>()),
      );
    });
  });
}
