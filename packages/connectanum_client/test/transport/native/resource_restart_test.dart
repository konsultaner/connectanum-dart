import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';

import '../../test_support/native_runtime_support.dart';

void main() {
  final unavailableReason = nativeClientRuntimeSkipReason();

  for (final aes in [false, true]) {
    final cipher = aes ? 'aes256gcm' : 'xsalsa20poly1305';
    NativeWampCborXsalsa20Poly1305Provider provider(int keyByte) => aes
        ? NativeWampCborAes256GcmProvider.single(
            keyId: 'restart-key',
            key: List<int>.filled(32, keyByte),
          )
        : NativeWampCborXsalsa20Poly1305Provider.single(
            keyId: 'restart-key',
            key: List<int>.filled(32, keyByte),
          );

    group('native resource restart $cipher', () {
      setUp(NativeClientRuntime.shutdownShared);
      tearDown(NativeClientRuntime.shutdownShared);

      test('stale provider cannot decrypt replacement ciphertext', () {
        final stale = provider(11);
        addTearDown(stale.release);
        final oldOptions = PublishOptions(pptScheme: 'wamp');
        final oldCiphertext = stale.packPayload(
          const ['old identity'],
          null,
          oldOptions,
        );
        NativeClientRuntime.shutdownShared();
        final replacement = provider(22);
        addTearDown(replacement.release);
        final options = PublishOptions(pptScheme: 'wamp');
        final ciphertext = replacement.packPayload(
          const ['replacement identity'],
          null,
          options,
        );

        expect(
          replacement.unpackPayload(ciphertext, options).arguments,
          ['replacement identity'],
        );
        expect(
          () => replacement.unpackPayload(oldCiphertext, oldOptions),
          throwsA(isA<WampE2eeDecryptionException>()),
        );
        expect(
          () => stale.unpackPayload(ciphertext, options),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
      });

      test('stale provider cannot encrypt with the replacement key', () {
        final stale = provider(11);
        addTearDown(stale.release);
        NativeClientRuntime.shutdownShared();
        final replacement = provider(22);
        addTearDown(replacement.release);

        expect(
          () {
            final options = PublishOptions(pptScheme: 'wamp');
            final ciphertext = stale.packPayload(
              const ['stale callback'],
              null,
              options,
            );
            // On the broken implementation this proves the new key was used,
            // not merely that the stale provider retained its original key.
            expect(
              replacement.unpackPayload(ciphertext, options).arguments,
              ['stale callback'],
            );
          },
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        final options = PublishOptions(pptScheme: 'wamp');
        final ciphertext = replacement.packPayload(
          const ['replacement identity'],
          null,
          options,
        );
        expect(
          replacement.unpackPayload(ciphertext, options).arguments,
          ['replacement identity'],
        );
      });

      test('releasing a stale provider leaves the replacement usable', () {
        final stale = provider(11);
        addTearDown(stale.release);
        NativeClientRuntime.shutdownShared();
        final replacement = provider(22);
        addTearDown(replacement.release);

        stale.release();
        final options = PublishOptions(pptScheme: 'wamp');
        final ciphertext = replacement.packPayload(
          const ['replacement survives'],
          null,
          options,
        );
        expect(
          replacement.unpackPayload(ciphertext, options).arguments,
          ['replacement survives'],
        );
      });
    }, skip: unavailableReason);
  }
}
