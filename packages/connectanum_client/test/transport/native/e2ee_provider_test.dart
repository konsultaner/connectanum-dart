import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';

import '../../test_support/native_runtime_support.dart';

void main() {
  final nativeClientRuntimeUnavailableReason = nativeClientRuntimeSkipReason();

  group(
    'NativeWampCborXsalsa20Poly1305Provider',
    () {
      tearDown(NativeClientRuntime.shutdownShared);

      test('round-trips payloads and populates PPT metadata', () {
        final provider = NativeWampCborXsalsa20Poly1305Provider.single(
          keyId: 'kid-1',
          key: List<int>.generate(32, (index) => index + 1),
        );
        addTearDown(provider.release);

        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
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

      test('selects a key id from runtime context when options omit it', () {
        final provider = NativeWampCborXsalsa20Poly1305Provider(
          keys: {
            'kid-alpha': List<int>.generate(32, (index) => index + 1),
            'kid-beta': List<int>.generate(32, (index) => index + 65),
          },
          keySelectionPolicy: (runtimeContext, _) =>
              runtimeContext.uri == 'policy.topic.beta'
              ? 'kid-beta'
              : 'kid-alpha',
        );
        addTearDown(provider.release);

        final runtimeContext = const WampE2eeRuntimeContext(
          direction: WampE2eeDirection.outbound,
          messageType: WampE2eeMessageType.publish,
          uri: 'policy.topic.beta',
        );
        final packOptions = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );

        final packed = provider.packPayload(
          const ['wrapped'],
          const {'worker': 4},
          packOptions,
          runtimeContext: runtimeContext,
        );

        expect(packOptions.pptKeyId, equals('kid-beta'));

        final unpackOptions = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        final decoded = provider.unpackPayload(
          packed,
          unpackOptions,
          runtimeContext: runtimeContext.copyWith(
            direction: WampE2eeDirection.inbound,
          ),
        );

        expect(unpackOptions.pptKeyId, equals('kid-beta'));
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
        expect(
          nativeDecoded.argumentsKeywords,
          equals(const {'path': 'native'}),
        );
      });

      test('maps wrong-key decrypts to the core decryption exception', () {
        final encryptingProvider =
            NativeWampCborXsalsa20Poly1305Provider.single(
              keyId: 'kid-1',
              key: List<int>.generate(32, (index) => index + 1),
            );
        final decryptingProvider =
            NativeWampCborXsalsa20Poly1305Provider.single(
              keyId: 'kid-1',
              key: List<int>.generate(32, (index) => index + 33),
            );
        addTearDown(encryptingProvider.release);
        addTearDown(decryptingProvider.release);

        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
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
    },
    skip: nativeClientRuntimeUnavailableReason,
  );

  group('NativeWampCborAes256GcmProvider', () {
    tearDown(NativeClientRuntime.shutdownShared);

    test('interoperates between independent native providers', () {
      final key = List<int>.generate(32, (index) => index + 1);
      final encryptingProvider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );
      final decryptingProvider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );
      addTearDown(encryptingProvider.release);
      addTearDown(decryptingProvider.release);
      final options = PublishOptions(pptScheme: 'wamp');

      final packed = encryptingProvider.packPayload(
        const ['native-to-native'],
        const {'path': 'independent'},
        options,
      );
      final decoded = decryptingProvider.unpackPayload(packed, options);

      expect(decoded.arguments, equals(const ['native-to-native']));
      expect(decoded.argumentsKeywords, equals(const {'path': 'independent'}));
    });

    test('interoperates with the pure Dart provider in both directions', () {
      final key = List<int>.generate(32, (index) => index + 1);
      final nativeProvider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );
      addTearDown(nativeProvider.release);
      final dartProvider = WampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );

      final nativeOptions = PublishOptions(pptScheme: 'wamp');
      final nativePacked = nativeProvider.packPayload(
        const ['native'],
        const {'path': 'dart'},
        nativeOptions,
      );
      expect(nativeOptions.pptCipher, equals('aes256gcm'));
      final dartDecoded = dartProvider.unpackPayload(
        nativePacked,
        nativeOptions,
      );
      expect(dartDecoded.arguments, equals(const ['native']));
      expect(dartDecoded.argumentsKeywords, equals(const {'path': 'dart'}));

      final dartOptions = PublishOptions(pptScheme: 'wamp');
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

    test('maps authenticated decrypt failures to the core exception', () {
      final provider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: List<int>.generate(32, (index) => index + 1),
      );
      addTearDown(provider.release);
      final options = PublishOptions(pptScheme: 'wamp');
      final packed = provider.packPayload(const ['wrapped'], null, options);
      final tampered = Uint8List.fromList(packed.single as Uint8List);
      tampered[tampered.length - 1] ^= 1;

      expect(
        () => provider.unpackPayload(<dynamic>[tampered], options),
        throwsA(isA<WampE2eeDecryptionException>()),
      );
    });
  }, skip: nativeClientRuntimeUnavailableReason);
}
