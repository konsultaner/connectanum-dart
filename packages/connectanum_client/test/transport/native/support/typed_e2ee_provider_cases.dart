part of '../e2ee_provider_test.dart';

NativeWampFlatBuffersXsalsa20Poly1305Provider _nativeTypedProvider(
  bool aes, {
  required Map<String, List<int>> keys,
  String? defaultKeyId,
  WampE2eeKeySelectionPolicy? policy,
}) => aes
    ? NativeWampFlatBuffersAes256GcmProvider(
        keys: keys,
        defaultKeyId: defaultKeyId,
        keySelectionPolicy: policy,
      )
    : NativeWampFlatBuffersXsalsa20Poly1305Provider(
        keys: keys,
        defaultKeyId: defaultKeyId,
        keySelectionPolicy: policy,
      );

void _nativeTypedProviderCases(String? unavailable) {
  for (final aes in [false, true]) {
    final cipher = aes ? 'aes256gcm' : 'xsalsa20poly1305';
    group('native typed $cipher', () {
      tearDown(NativeClientRuntime.shutdownShared);
      final key = List<int>.generate(32, (index) => index + 1);

      test('preserves whole application spans in both portable directions', () {
        final native = aes
            ? NativeWampFlatBuffersAes256GcmProvider.single(
                keyId: 'kid',
                key: key,
              )
            : NativeWampFlatBuffersXsalsa20Poly1305Provider.single(
                keyId: 'kid',
                key: key,
              );
        addTearDown(native.release);
        final portable = aes
            ? WampFlatBuffersAes256GcmProvider.single(keyId: 'kid', key: key)
            : WampFlatBuffersXsalsa20Poly1305Provider.single(
                keyId: 'kid',
                key: key,
              );
        final root = Uint8List.fromList([99, 98, 255, 0, 129, 37, 97]);
        for (final app in [
          Uint8List(0),
          Uint8List.sublistView(root, 2, 6),
          cbor.Serializer().serializePPT(
            PPTPayload(
              arguments: [
                Uint8List.fromList([1, 2, 3]),
              ],
            ),
          ),
        ]) {
          final options = PublishOptions();
          final nativePacked = native.packPayload([app], null, options);
          expect(options.pptScheme, 'wamp');
          expect(options.pptSerializer, 'flatbuffers');
          expect(options.pptCipher, cipher);
          expect(options.pptKeyId, 'kid');
          expect(
            portable.unpackPayload(nativePacked, options).arguments!.single,
            orderedEquals(app),
          );
          final portablePacked = portable.packPayload(
            [app],
            null,
            PublishOptions(),
          );
          final result = native.unpackPayload(portablePacked, options);
          expect(result.argumentsKeywords, isNull);
          final bytes = result.arguments!.single as Uint8List;
          expect(bytes, orderedEquals(app));
          expect(ByteData.sublistView(bytes).lengthInBytes, app.length);
          if (bytes.isNotEmpty) {
            expect(() => bytes[0] = 0, throwsUnsupportedError);
          }
        }
      });

      test('supports only the exact typed profile', () {
        final provider = _nativeTypedProvider(aes, keys: {'kid': key});
        addTearDown(provider.release);
        for (final (version, scheme, serializer, selectedCipher, accepted) in [
          (2, 'wamp', 'flatbuffers', cipher, true),
          (1, 'wamp', 'cbor', cipher, false),
          (1, 'wamp', 'flatbuffers', cipher, false),
          (2, 'other', 'flatbuffers', cipher, false),
          (2, 'wamp', 'cbor', cipher, false),
          (
            2,
            'wamp',
            'flatbuffers',
            aes ? 'xsalsa20poly1305' : 'aes256gcm',
            false,
          ),
        ]) {
          expect(
            provider.supportsE2eeProfile(
              version: version,
              scheme: scheme,
              serializer: serializer,
              cipher: selectedCipher,
            ),
            accepted,
          );
        }
      });

      test('rejects file framing before metadata or policy side effects', () {
        var policyCalls = 0;
        final provider = _nativeTypedProvider(
          aes,
          keys: {'kid': key},
          policy: (_, _) {
            policyCalls++;
            return 'kid';
          },
        );
        addTearDown(provider.release);
        final options = PublishOptions();
        expect(provider.supportsNativeE2eeFileSegments, isFalse);
        expect(
          () => provider.prepareNativeE2eeFileSegment(
            options,
            runtimeContext: const WampE2eeRuntimeContext(
              direction: WampE2eeDirection.outbound,
              messageType: WampE2eeMessageType.publish,
            ),
          ),
          throwsUnsupportedError,
        );
        expect(policyCalls, 0);
        expect(options.pptScheme, isNull);
        expect(options.pptSerializer, isNull);
        expect(options.pptCipher, isNull);
        expect(options.pptKeyId, isNull);
      });

      test('rejects dynamic arguments and keywords before choosing keys', () {
        var policyCalls = 0;
        final provider = _nativeTypedProvider(
          aes,
          keys: {'kid': key},
          policy: (_, _) {
            policyCalls++;
            return 'kid';
          },
        );
        addTearDown(provider.release);
        for (final (args, kwargs) in <(List<dynamic>?, Map<String, dynamic>?)>[
          (null, null),
          ([], null),
          (['value'], null),
          (
            [
              <int>[1, 2],
            ],
            null,
          ),
          ([Uint8List(0)], {}),
          ([Uint8List(0), Uint8List(0)], null),
        ]) {
          final options = PublishOptions();
          expect(
            () => provider.packPayload(
              args,
              kwargs,
              options,
              runtimeContext: const WampE2eeRuntimeContext(
                direction: WampE2eeDirection.outbound,
                messageType: WampE2eeMessageType.publish,
              ),
            ),
            throwsUnsupportedError,
          );
          expect(options.pptKeyId, isNull);
          expect(options.pptSerializer, isNull);
        }
        expect(policyCalls, 0);
      });

      test('bounds plaintext and ciphertext before policy and defaults', () {
        var policyCalls = 0;
        final provider = _nativeTypedProvider(
          aes,
          keys: {'kid': key},
          policy: (_, _) {
            policyCalls++;
            return 'kid';
          },
        );
        addTearDown(provider.release);
        final context = const WampE2eeRuntimeContext(
          direction: WampE2eeDirection.outbound,
          messageType: WampE2eeMessageType.publish,
        );
        final options = PublishOptions();
        final oversizedPlain = Uint8List(
          ConnectanumFlatBuffersE2eeProfile.maximumCiphertextBytes -
              (aes ? 28 : 40) +
              1,
        );
        expect(
          () => provider.packPayload(
            [oversizedPlain],
            null,
            options,
            runtimeContext: context,
          ),
          throwsArgumentError,
        );
        final oversizedCipher = Uint8List(
          ConnectanumFlatBuffersE2eeProfile.maximumCiphertextBytes + 1,
        );
        expect(
          () => provider.unpackPayload(
            [oversizedCipher],
            options,
            runtimeContext: context,
          ),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        expect(policyCalls, 0);
        expect(options.pptKeyId, isNull);
        expect(options.pptSerializer, isNull);
      });

      test('explicit key takes precedence over policy and default', () {
        final second = List<int>.filled(32, 29);
        var policyCalls = 0;
        final provider = _nativeTypedProvider(
          aes,
          keys: {'default': key, 'policy': second},
          defaultKeyId: 'default',
          policy: (_, _) {
            policyCalls++;
            return 'policy';
          },
        );
        addTearDown(provider.release);
        final context = const WampE2eeRuntimeContext(
          direction: WampE2eeDirection.outbound,
          messageType: WampE2eeMessageType.publish,
        );
        final portable = aes
            ? WampFlatBuffersAes256GcmProvider(
                keys: {'default': key, 'policy': second},
              )
            : WampFlatBuffersXsalsa20Poly1305Provider(
                keys: {'default': key, 'policy': second},
              );
        final app = Uint8List.fromList([8, 7, 6]);
        final policyOptions = PublishOptions();
        final packed = provider.packPayload(
          [app],
          null,
          policyOptions,
          runtimeContext: context,
        );
        expect(policyCalls, 1);
        expect(policyOptions.pptKeyId, 'policy');
        expect(
          portable.unpackPayload(packed, policyOptions).arguments!.single,
          orderedEquals(app),
        );
        final explicit = PublishOptions(pptKeyId: 'default');
        final explicitPacked = provider.packPayload(
          [app],
          null,
          explicit,
          runtimeContext: context,
        );
        expect(policyCalls, 1);
        expect(explicit.pptKeyId, 'default');
        expect(
          portable.unpackPayload(explicitPacked, explicit).arguments!.single,
          orderedEquals(app),
        );
      });

      test('maps authentication failures and rejects malformed ciphertext', () {
        final provider = _nativeTypedProvider(aes, keys: {'kid': key});
        addTearDown(provider.release);
        final options = PublishOptions();
        final packed = provider.packPayload(
          [
            Uint8List.fromList([7, 8, 9]),
          ],
          null,
          options,
        );
        final tampered = Uint8List.fromList(packed.single as Uint8List);
        tampered[tampered.length - 1] ^= 1;
        expect(
          () => provider.unpackPayload([tampered], options),
          throwsA(isA<WampE2eeDecryptionException>()),
        );
        expect(
          () => provider.unpackPayload([
            [-1],
          ], PublishOptions()),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        expect(
          () => provider.unpackPayload([
            [256],
          ], PublishOptions()),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        expect(
          () => provider.unpackPayload([
            ['not a byte'],
          ], PublishOptions()),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        expect(
          () => provider.unpackPayload([], PublishOptions()),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        expect(
          () => provider.unpackPayload(
            packed,
            PublishOptions(pptSerializer: 'cbor'),
          ),
          throwsArgumentError,
        );
        expect(
          () => provider.unpackPayload(
            packed,
            PublishOptions(pptCipher: aes ? 'xsalsa20poly1305' : 'aes256gcm'),
          ),
          throwsA(isA<WampE2eeUnsupportedCipherException>()),
        );
        expect(
          () => provider.unpackPayload(
            packed,
            PublishOptions(pptKeyId: 'missing'),
          ),
          throwsA(isA<WampE2eeKeyNotFoundException>()),
        );
      });

      test(
        'release is idempotent and later operations reject closed state',
        () {
          final provider = _nativeTypedProvider(aes, keys: {'kid': key});
          final options = PublishOptions();
          final packed = provider.packPayload([Uint8List(0)], null, options);
          provider.release();
          provider.release();
          expect(
            () => provider.packPayload([Uint8List(0)], null, PublishOptions()),
            throwsStateError,
          );
          expect(
            () => provider.unpackPayload(packed, options),
            throwsStateError,
          );
        },
      );
    }, skip: unavailable);
  }
}
