import 'dart:collection';
import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:pinenacl/api.dart' show EncryptedMessage;
import 'package:pinenacl/x25519.dart' show SecretBox;
import 'package:test/test.dart';

import 'support/e2ee_assertions.dart';

// The profile contract is 64 MiB, independent of the provider's guard constant.
const _maximumCiphertextBytes = 64 * 1024 * 1024;
const _runtimeContext = WampE2eeRuntimeContext(
  direction: WampE2eeDirection.outbound,
  messageType: WampE2eeMessageType.publish,
);

void main() {
  _policyCallbackContractCases();
  test('typed WAMP plaintext can select FlatBuffers without CBOR framing', () {
    final options = PublishOptions(
      pptScheme: 'wamp',
      pptSerializer: 'flatbuffers',
      pptCipher: ConnectanumE2eeProfile.aes256Gcm,
      pptKeyId: 'typed',
    );
    expect(options.verifyPPT(), isTrue);
  });

  test('WAMP plaintext selection still rejects an unknown encoding', () {
    final options = PublishOptions(
      pptScheme: 'wamp',
      pptSerializer: 'unknown',
    );
    expect(options.verifyPPT, throwsArgumentError);
  });

  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final cborLike = cbor.Serializer().serializePPT(
    PPTPayload(
      arguments: [
        Uint8List.fromList([1, 2, 3]),
      ],
    ),
  );
  for (final cipher in [
    ConnectanumE2eeProfile.xsalsa20Poly1305,
    ConnectanumE2eeProfile.aes256Gcm,
  ]) {
    WampE2eeProvider provider({
      Uint8List? secret,
      WampE2eeKeySelectionPolicy? policy,
      bool allowDefault = true,
    }) => cipher == ConnectanumE2eeProfile.aes256Gcm
        ? WampFlatBuffersAes256GcmProvider(
            keys: {'typed': secret ?? key, if (!allowDefault) 'other': key},
            defaultKeyId: allowDefault ? 'typed' : null,
            keySelectionPolicy: policy,
          )
        : WampFlatBuffersXsalsa20Poly1305Provider(
            keys: {'typed': secret ?? key, if (!allowDefault) 'other': key},
            defaultKeyId: allowDefault ? 'typed' : null,
            keySelectionPolicy: policy,
          );

    group(cipher, () {
      for (final direction in WampE2eeDirection.values) {
        for (final selection in [
          'explicit',
          'policy',
          'negotiated',
          'default',
        ]) {
          test(
            'selects $selection key for $direction before provider default',
            () {
              var policyCalls = 0;
              final keys = {
                for (final (index, name) in [
                  'explicit',
                  'policy',
                  'outbound',
                  'inbound',
                  'default',
                ].indexed)
                  name: List<int>.filled(32, index + 1),
              };
              String? policy(
                WampE2eeRuntimeContext context,
                PPTOptions options,
              ) {
                policyCalls++;
                expect(context.direction, direction);
                return selection == 'policy' ? 'policy' : null;
              }

              final selectedProvider =
                  cipher == ConnectanumE2eeProfile.aes256Gcm
                  ? WampFlatBuffersAes256GcmProvider(
                      keys: keys,
                      defaultKeyId: 'default',
                      keySelectionPolicy: policy,
                    )
                  : WampFlatBuffersXsalsa20Poly1305Provider(
                      keys: keys,
                      defaultKeyId: 'default',
                      keySelectionPolicy: policy,
                    );
              expect(
                (selectedProvider as WampE2eeNegotiatedKeySelectionProvider)
                    .handlesNegotiatedKeySelection,
                isTrue,
              );
              final expectedKey = selection == 'negotiated'
                  ? direction == WampE2eeDirection.outbound
                        ? 'outbound'
                        : 'inbound'
                  : selection;
              final context = WampE2eeRuntimeContext(
                direction: direction,
                messageType: direction == WampE2eeDirection.outbound
                    ? WampE2eeMessageType.publish
                    : WampE2eeMessageType.event,
                negotiated: selection == 'default'
                    ? {}
                    : {
                        'send_key_id': 'outbound',
                        'receive_key_id': 'inbound',
                      },
              );
              final bytes = Uint8List.fromList([1, 255]);
              final options = PublishOptions(
                pptScheme: 'wamp',
                pptKeyId: selection == 'explicit' ? 'explicit' : null,
              );
              if (direction == WampE2eeDirection.outbound) {
                final encrypted = selectedProvider.packPayload(
                  [bytes],
                  null,
                  options,
                  runtimeContext: context,
                );
                expect(
                  selectedProvider
                      .unpackPayload(
                        encrypted,
                        PublishOptions(
                          pptScheme: 'wamp',
                          pptKeyId: expectedKey,
                        ),
                      )
                      .arguments,
                  [bytes],
                );
              } else {
                final encrypted = selectedProvider.packPayload(
                  [bytes],
                  null,
                  PublishOptions(pptScheme: 'wamp', pptKeyId: expectedKey),
                );
                expect(
                  selectedProvider
                      .unpackPayload(
                        encrypted,
                        options,
                        runtimeContext: context,
                      )
                      .arguments,
                  [bytes],
                );
              }
              expect(options.pptKeyId, expectedKey);
              expect(policyCalls, selection == 'explicit' ? 0 : 1);
            },
          );
        }
      }

      test('declares only the explicit typed version and cipher', () {
        final support = provider() as WampE2eeProfileSupport;
        for (final (version, scheme, serializer, selectedCipher, accepted) in [
          (2, 'wamp', 'flatbuffers', cipher, true),
          (1, 'wamp', 'flatbuffers', cipher, false),
          (2, 'wamp', 'cbor', cipher, false),
          (2, 'x_app', 'flatbuffers', cipher, false),
          (2, 'wamp', 'flatbuffers', 'unknown', false),
        ]) {
          expect(
            support.supportsE2eeProfile(
              version: version,
              scheme: scheme,
              serializer: serializer,
              cipher: selectedCipher,
            ),
            accepted,
          );
        }
      });

      for (final (name, bytes) in [
        ('empty', Uint8List(0)),
        ('CBOR-like envelope', cborLike),
        ('unrecognized schema', Uint8List.fromList([255, 0, 128, 1])),
        (
          'nonzero-offset span',
          Uint8List.sublistView(Uint8List.fromList([99, 4, 3, 2, 1, 99]), 1, 5),
        ),
      ]) {
        test('preserves complete $name plaintext without interpretation', () {
          final before = Uint8List.fromList(bytes);
          final options = PublishOptions();
          final packed = expectE2eeSuccess(
            () => provider().packPayload([bytes], null, options),
          );
          expect(options.pptScheme, 'wamp');
          expect(options.pptSerializer, 'flatbuffers');
          expect(options.pptCipher, cipher);
          expect(options.pptKeyId, 'typed');
          expect(options.verifyPPT(), isTrue);
          expect(packed, hasLength(1));
          expect(packed.single, isA<Uint8List>());
          expect(
            (packed.single as Uint8List).length,
            bytes.length +
                (cipher == ConnectanumE2eeProfile.aes256Gcm ? 28 : 40),
          );
          final decoded = provider().unpackPayload(packed, options);
          expect(decoded.arguments, hasLength(1));
          expect(decoded.arguments!.single, orderedEquals(before));
          expect(decoded.argumentsKeywords, isNull);
          expect(bytes, orderedEquals(before));
          if (cipher == ConnectanumE2eeProfile.xsalsa20Poly1305) {
            expect(
              SecretBox(key).decrypt(EncryptedMessage.fromList(packed.single)),
              orderedEquals(before),
            );
          }
        });
      }

      test('rejects tampering and wrong keys before exposing plaintext', () {
        final options = PublishOptions();
        final packed = provider().packPayload([cborLike], null, options);
        final damaged = Uint8List.fromList(packed.single as Uint8List);
        damaged[damaged.length - 1] ^= 1;
        expect(
          () => provider().unpackPayload([damaged], options),
          throwsA(isA<WampE2eeDecryptionException>()),
        );
        expect(
          () => provider(secret: Uint8List(32)).unpackPayload(packed, options),
          throwsA(isA<WampE2eeDecryptionException>()),
        );
      });

      test('rejects dynamic or multiple arguments and every keyword map', () {
        for (final (arguments, kwargs)
            in <(List<dynamic>?, Map<String, dynamic>?)>[
              (null, null),
              ([], null),
              (
                [
                  [1, 2],
                ],
                null,
              ),
              ([Uint8List(0), Uint8List(0)], null),
              ([Uint8List(0)], {}),
              ([Uint8List(0)], {'value': 1}),
            ]) {
          final options = PublishOptions();
          expect(
            () => provider().packPayload(arguments, kwargs, options),
            throwsUnsupportedError,
          );
          expect(options.pptKeyId, isNull);
          expect(options.pptSerializer, isNull);
        }
      });

      test('cannot select CBOR plaintext through a typed provider', () {
        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        expect(
          () => provider().packPayload([cborLike], null, options),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'option', 'pptSerializer')
                .having(
                  (error) => error.message,
                  'supported serializer',
                  contains('"flatbuffers"'),
                ),
          ),
        );
        expect(
          () => provider().unpackPayload([cborLike], options),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'supported serializer',
              contains('"flatbuffers"'),
            ),
          ),
        );
      });

      test(
        'rejects oversized ciphertext before key defaults or decryption',
        () {
          final bytes = _LengthOnlyBytes(_maximumCiphertextBytes + 1, Object());
          final options = PublishOptions();
          expect(
            () => provider(allowDefault: false).unpackPayload([bytes], options),
            throwsA(
              isA<WampE2eeInvalidPayloadException>().having(
                (error) => error.reason,
                'reason',
                contains('exceeds the byte limit'),
              ),
            ),
          );
          expect(bytes.reads, 0);
          expect(options.pptKeyId, isNull);
          expect(options.pptCipher, isNull);
          expect(options.pptSerializer, isNull);
        },
      );

      test(
        'accounts for ciphertext overhead before encrypting or setting defaults',
        () {
          final overhead = cipher == ConnectanumE2eeProfile.aes256Gcm ? 28 : 40;
          final bytes = Uint8List(_maximumCiphertextBytes - overhead + 1);
          final options = PublishOptions();
          final policySentinel = Object();
          expect(
            () =>
                provider(
                  allowDefault: false,
                  policy: (_, _) => throw policySentinel,
                ).packPayload(
                  [bytes],
                  null,
                  options,
                  runtimeContext: _runtimeContext,
                ),
            throwsArgumentError,
          );
          expect(options.pptKeyId, isNull);
          expect(options.pptCipher, isNull);
          expect(options.pptSerializer, isNull);
        },
      );

      test('accepts the exact plaintext limit before resolving a key', () {
        final overhead = cipher == ConnectanumE2eeProfile.aes256Gcm ? 28 : 40;
        final bytes = Uint8List(_maximumCiphertextBytes - overhead);
        final options = PublishOptions();
        final policySentinel = Object();
        expect(
          () =>
              provider(
                allowDefault: false,
                policy: (_, _) => throw policySentinel,
              ).packPayload(
                [bytes],
                null,
                options,
                runtimeContext: _runtimeContext,
              ),
          throwsA(same(policySentinel)),
        );
        expect(options.pptKeyId, isNull);
        expect(options.pptSerializer, isNull);
      });

      test('allows the exact ciphertext length before reading list bytes', () {
        final readSentinel = Object();
        final policySentinel = Object();
        final bytes = _LengthOnlyBytes(_maximumCiphertextBytes, readSentinel);
        final options = PublishOptions();
        var policyCalls = 0;
        expect(
          () => provider(
            allowDefault: false,
            policy: (_, _) {
              policyCalls++;
              throw policySentinel;
            },
          ).unpackPayload([bytes], options, runtimeContext: _runtimeContext),
          throwsA(same(readSentinel)),
        );
        expect(bytes.reads, 1);
        expect(policyCalls, 0);
        expect(options.pptKeyId, isNull);
      });

      test('validates typed bytes before invoking key selection', () {
        final policySentinel = Object();
        final options = PublishOptions();
        expect(
          () =>
              provider(
                allowDefault: false,
                policy: (_, _) => throw policySentinel,
              ).unpackPayload(
                ['invalid binary'],
                options,
                runtimeContext: _runtimeContext,
              ),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
        expect(options.pptKeyId, isNull);
      });

      test('legacy CBOR keeps key selection ahead of byte validation', () {
        final policySentinel = Object();
        final legacy = cipher == ConnectanumE2eeProfile.aes256Gcm
            ? WampCborAes256GcmProvider(
                keys: {'typed': key, 'other': key},
                keySelectionPolicy: (_, _) => throw policySentinel,
              )
            : WampCborXsalsa20Poly1305Provider(
                keys: {'typed': key, 'other': key},
                keySelectionPolicy: (_, _) => throw policySentinel,
              );
        expect(
          () => legacy.unpackPayload(
            ['invalid binary'],
            PublishOptions(),
            runtimeContext: _runtimeContext,
          ),
          throwsA(same(policySentinel)),
        );
        expect(
          () => legacy.packPayload(
            [Uint8List(_maximumCiphertextBytes)],
            null,
            PublishOptions(),
            runtimeContext: _runtimeContext,
          ),
          throwsA(same(policySentinel)),
        );
        expect(
          () => legacy.packPayload(
            [Uint8List(0)],
            null,
            PublishOptions(pptSerializer: 'flatbuffers'),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'supported serializer',
              contains('"cbor"'),
            ),
          ),
        );
      });
    });
  }

  test('legacy malformed CBOR reports its own envelope failure', () {
    final legacy = WampCborXsalsa20Poly1305Provider.single(
      keyId: 'typed',
      key: key,
    );
    for (final plaintext in [
      <int>[0x01],
      <int>[0x81],
    ]) {
      final ciphertext = SecretBox(key).encrypt(
        Uint8List.fromList(plaintext),
        nonce: Uint8List(24),
      );
      expect(
        () => legacy.unpackPayload([ciphertext], PublishOptions()),
        throwsA(
          isA<WampE2eeInvalidPayloadException>().having(
            (error) => error.reason,
            'envelope failure',
            'Decrypted payload is not a valid CBOR PPT envelope',
          ),
        ),
      );
    }
  });
}

WampE2eeProvider _policyCallbackProvider(
  bool typed,
  bool aes,
  Map<String, List<int>> keys, {
  WampE2eeKeySelectionPolicy? policy,
}) {
  if (typed) {
    return aes
        ? WampFlatBuffersAes256GcmProvider(
            keys: keys,
            defaultKeyId: 'first',
            keySelectionPolicy: policy,
          )
        : WampFlatBuffersXsalsa20Poly1305Provider(
            keys: keys,
            defaultKeyId: 'first',
            keySelectionPolicy: policy,
          );
  }
  return aes
      ? WampCborAes256GcmProvider(
          keys: keys,
          defaultKeyId: 'first',
          keySelectionPolicy: policy,
        )
      : WampCborXsalsa20Poly1305Provider(
          keys: keys,
          defaultKeyId: 'first',
          keySelectionPolicy: policy,
        );
}

void _policyCallbackContractCases() {
  final keys = <String, List<int>>{
    'first': List<int>.generate(32, (index) => index + 1),
    'second': List<int>.generate(32, (index) => index + 65),
  };
  final body = <dynamic>[
    Uint8List.fromList([1, 2, 3]),
  ];
  for (final typed in [false, true]) {
    for (final aes in [false, true]) {
      test(
        'portable key policy revalidation preserves reused options typed=$typed aes=$aes',
        () {
          var selection = 'first';
          var calls = 0;
          final provider = _policyCallbackProvider(
            typed,
            aes,
            keys,
            policy: (_, _) {
              calls++;
              return selection;
            },
          );
          final reference = _policyCallbackProvider(typed, aes, keys);
          final options = PublishOptions();
          void verifyPacked(String expectedKey) {
            final packed = provider.packPayload(
              body,
              null,
              options,
              runtimeContext: _runtimeContext,
            );
            expect(options.pptKeyId, expectedKey);
            E2EEPayloadView? decoded;
            expect(
              () => decoded = reference.unpackPayload(packed, options),
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
        },
      );
      for (final unpack in [false, true]) {
        final context = WampE2eeRuntimeContext(
          direction: unpack
              ? WampE2eeDirection.inbound
              : WampE2eeDirection.outbound,
          messageType: WampE2eeMessageType.publish,
        );
        for (final field in ['scheme', 'serializer', 'cipher', 'unknown-key']) {
          test(
            'portable key policy revalidation typed=$typed aes=$aes unpack=$unpack field=$field',
            () {
              var calls = 0;
              final provider = _policyCallbackProvider(
                typed,
                aes,
                keys,
                policy: (_, options) {
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
              final reference = _policyCallbackProvider(typed, aes, keys);
              final packed = reference.packPayload(
                body,
                null,
                PublishOptions(),
              );
              final options = PublishOptions();
              final failure = switch (field) {
                'cipher' => throwsA(isA<WampE2eeUnsupportedCipherException>()),
                'unknown-key' => throwsA(isA<WampE2eeKeyNotFoundException>()),
                _ => throwsArgumentError,
              };
              expect(
                () => unpack
                    ? provider.unpackPayload(
                        packed,
                        options,
                        runtimeContext: context,
                      )
                    : provider.packPayload(
                        body,
                        null,
                        options,
                        runtimeContext: context,
                      ),
                failure,
              );
              expect(calls, 1);
            },
          );
        }
        test(
          'portable key policy revalidation uses current known key typed=$typed aes=$aes unpack=$unpack',
          () {
            var calls = 0;
            final provider = _policyCallbackProvider(
              typed,
              aes,
              keys,
              policy: (_, options) {
                calls++;
                options.pptKeyId = 'second';
                return 'first';
              },
            );
            final reference = _policyCallbackProvider(typed, aes, keys);
            final options = PublishOptions();
            E2EEPayloadView? decoded;
            if (unpack) {
              final packed = reference.packPayload(
                body,
                null,
                PublishOptions(pptKeyId: 'second'),
              );
              expect(
                () => decoded = provider.unpackPayload(
                  packed,
                  options,
                  runtimeContext: context,
                ),
                returnsNormally,
              );
            } else {
              final packed = provider.packPayload(
                body,
                null,
                options,
                runtimeContext: context,
              );
              expect(
                () => decoded = reference.unpackPayload(packed, options),
                returnsNormally,
              );
            }
            expect(options.pptKeyId, 'second');
            expect(decoded?.arguments, body);
            expect(decoded?.argumentsKeywords, isNull);
            expect(calls, 1);
          },
        );
      }
    }
  }
}

// Logical lengths exercise the guard without copying 64 MiB under a mutant.
// The exact boundary must reach the first element; an overflow must not read it.
class _LengthOnlyBytes extends ListBase<int> {
  _LengthOnlyBytes(this._length, this.readSentinel);
  final int _length;
  final Object readSentinel;
  int reads = 0;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Fixed logical length');

  @override
  int operator [](int index) {
    reads++;
    throw readSentinel;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read only');
}
