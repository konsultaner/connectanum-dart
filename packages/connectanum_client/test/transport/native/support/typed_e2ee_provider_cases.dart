part of '../e2ee_provider_test.dart';

({WampE2eeProvider provider, void Function() release}) _nativeCallbackProvider(
  bool typed,
  bool aes,
  Map<String, List<int>> keys,
  WampE2eeKeySelectionPolicy? policy,
) {
  final provider = typed
      ? _nativeTypedProvider(aes, keys: keys, policy: policy)
      : aes
      ? NativeWampCborAes256GcmProvider(
          keys: keys,
          defaultKeyId: 'first',
          keySelectionPolicy: policy,
        )
      : NativeWampCborXsalsa20Poly1305Provider(
          keys: keys,
          defaultKeyId: 'first',
          keySelectionPolicy: policy,
        );
  return (provider: provider, release: provider.release);
}

void _nativePolicyCallbackContractCases(String? unavailable) {
  final keys = <String, List<int>>{
    'first': List<int>.generate(32, (index) => index + 1),
    'second': List<int>.generate(32, (index) => index + 65),
  };
  final body = <dynamic>[
    Uint8List.fromList([1, 2, 3]),
  ];
  group('native key policy revalidation', () {
    tearDown(NativeClientRuntime.shutdownShared);
    for (final typed in [false, true]) {
      for (final aes in [false, true]) {
        test('preserves reused options typed=$typed aes=$aes', () {
          var selection = 'first';
          var calls = 0;
          final receiver = _nativeCallbackProvider(typed, aes, keys, (_, _) {
            calls++;
            return selection;
          });
          final reference = _nativeCallbackProvider(typed, aes, keys, null);
          addTearDown(receiver.release);
          addTearDown(reference.release);
          final options = PublishOptions();
          void verifyPacked(String expectedKey) {
            final packed = receiver.provider.packPayload(
              body,
              null,
              options,
              runtimeContext: const WampE2eeRuntimeContext(
                direction: WampE2eeDirection.outbound,
                messageType: WampE2eeMessageType.publish,
              ),
            );
            expect(options.pptKeyId, expectedKey);
            E2EEPayloadView? decoded;
            expect(
              () => decoded = reference.provider.unpackPayload(packed, options),
              returnsNormally,
            );
            expect(decoded?.arguments, body);
          }

          verifyPacked('first');
          selection = 'second';
          verifyPacked('first');
          expect(calls, 1);
          options.pptKeyId = null;
          verifyPacked('second');
          expect(calls, 2);
        });
        for (final unpack in [false, true]) {
          final context = WampE2eeRuntimeContext(
            direction: unpack
                ? WampE2eeDirection.inbound
                : WampE2eeDirection.outbound,
            messageType: WampE2eeMessageType.publish,
          );
          for (final field in [
            'scheme',
            'serializer',
            'cipher',
            'unknown-key',
          ]) {
            test('typed=$typed aes=$aes unpack=$unpack field=$field', () {
              var calls = 0;
              final receiver = _nativeCallbackProvider(
                typed,
                aes,
                keys,
                (_, options) {
                  calls++;
                  switch (field) {
                    case 'scheme':
                      options.pptScheme = 'json';
                    case 'serializer':
                      options.pptSerializer = typed ? 'cbor' : 'flatbuffers';
                    case 'cipher':
                      options.pptCipher = aes
                          ? 'xsalsa20poly1305'
                          : 'aes256gcm';
                    case 'unknown-key':
                      options.pptKeyId = 'missing';
                  }
                  return 'first';
                },
              );
              final reference = _nativeCallbackProvider(typed, aes, keys, null);
              addTearDown(receiver.release);
              addTearDown(reference.release);
              final packed = reference.provider.packPayload(
                body,
                null,
                PublishOptions(pptKeyId: 'first'),
              );
              final options = PublishOptions();
              final failure = switch (field) {
                'cipher' => throwsA(isA<WampE2eeUnsupportedCipherException>()),
                'unknown-key' => throwsA(isA<WampE2eeKeyNotFoundException>()),
                _ => throwsArgumentError,
              };
              expect(
                () => unpack
                    ? receiver.provider.unpackPayload(
                        packed,
                        options,
                        runtimeContext: context,
                      )
                    : receiver.provider.packPayload(
                        body,
                        null,
                        options,
                        runtimeContext: context,
                      ),
                failure,
              );
              expect(calls, 1);
            });
          }
          test(
            'uses current known key typed=$typed aes=$aes unpack=$unpack',
            () {
              var calls = 0;
              final receiver = _nativeCallbackProvider(
                typed,
                aes,
                keys,
                (_, options) {
                  calls++;
                  options.pptKeyId = 'second';
                  return 'first';
                },
              );
              final reference = _nativeCallbackProvider(typed, aes, keys, null);
              addTearDown(receiver.release);
              addTearDown(reference.release);
              final options = PublishOptions();
              E2EEPayloadView? decoded;
              if (unpack) {
                final packed = reference.provider.packPayload(
                  body,
                  null,
                  PublishOptions(pptKeyId: 'second'),
                );
                expect(
                  () => decoded = receiver.provider.unpackPayload(
                    packed,
                    options,
                    runtimeContext: context,
                  ),
                  returnsNormally,
                );
              } else {
                final packed = receiver.provider.packPayload(
                  body,
                  null,
                  options,
                  runtimeContext: context,
                );
                expect(
                  () => decoded = reference.provider.unpackPayload(
                    packed,
                    options,
                  ),
                  returnsNormally,
                );
              }
              expect(options.pptKeyId, 'second');
              expect(decoded?.arguments, body);
              expect(decoded?.argumentsKeywords, isNull);
              expect(calls, 1);
            },
          );
          test('policy release typed=$typed aes=$aes unpack=$unpack', () {
            var calls = 0;
            late final void Function() release;
            final receiver = _nativeCallbackProvider(
              typed,
              aes,
              keys,
              (_, _) {
                calls++;
                release();
                return 'first';
              },
            );
            release = receiver.release;
            final reference = _nativeCallbackProvider(typed, aes, keys, null);
            addTearDown(receiver.release);
            addTearDown(reference.release);
            final packed = reference.provider.packPayload(
              body,
              null,
              PublishOptions(pptKeyId: 'first'),
            );
            expect(
              () => unpack
                  ? receiver.provider.unpackPayload(
                      packed,
                      PublishOptions(),
                      runtimeContext: context,
                    )
                  : receiver.provider.packPayload(
                      body,
                      null,
                      PublishOptions(),
                      runtimeContext: context,
                    ),
              throwsStateError,
            );
            expect(calls, 1);
          });
        }
      }
    }
  }, skip: unavailable);
}

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
          Uint8List(2 * 1024 * 1024)
            ..[0] = 129
            ..[2 * 1024 * 1024 - 1] = 37,
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
