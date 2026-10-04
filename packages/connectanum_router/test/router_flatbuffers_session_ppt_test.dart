@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/src/transport/native/message_binding.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:test/test.dart';

import 'support/native_lib.dart';

const _deadline = Duration(seconds: 5);
const _pairs = [
  ('flatbuffers', 'flatbuffers'),
  ('flatbuffers', 'cbor'),
  ('cbor', 'flatbuffers'),
  ('flatbuffers', 'msgpack'),
  ('msgpack', 'flatbuffers'),
  ('flatbuffers', 'json'),
  ('json', 'flatbuffers'),
];

// A real application FlatBuffer with an int64 and a byte vector. Its schema is
// local to this test; the WAMP router needs neither it nor an application decoder.
Uint8List _application(int id) {
  final builder = fb.Builder();
  final vector = builder.writeListUint8(
    List<int>.generate(4096, (index) => (index + id) % 251),
  );
  builder.startTable(2);
  builder.addInt64(0, id);
  builder.addOffset(1, vector);
  builder.finish(builder.endTable());
  return builder.buffer;
}

int _applicationId(Uint8List bytes) {
  final context = fb.BufferContext.fromBytes(bytes);
  final root = const fb.Uint32Reader().read(context, 0);
  return const fb.Int64Reader().vTableGet(context, root, 4, 0);
}

class _Mode {
  const _Mode(this.name, this.scheme, this.serializer, [this.cipher]);
  final String name;
  final String scheme;
  final String serializer;
  final String? cipher;
  bool get encrypted => cipher != null;
  String? get keyId => encrypted ? 'fixture-key' : null;

  core.CallOptions callOptions() => core.CallOptions(
    receiveProgress: true,
    pptScheme: scheme,
    pptSerializer: serializer,
    pptCipher: cipher,
    pptKeyId: keyId,
  );

  core.YieldOptions replyOptions({bool progress = false}) => core.YieldOptions(
    progress: progress,
    pptScheme: scheme,
    pptSerializer: serializer,
    pptCipher: cipher,
    pptKeyId: keyId,
  );

  core.PublishOptions publishOptions() => core.PublishOptions(
    acknowledge: true,
    pptScheme: scheme,
    pptSerializer: serializer,
    pptCipher: cipher,
    pptKeyId: keyId,
  );

  core.WampE2eeProvider? provider() {
    if (!encrypted) return null;
    final key = List<int>.generate(32, (index) => index + 1);
    return cipher == 'aes256gcm'
        ? core.WampCborAes256GcmProvider.single(keyId: keyId!, key: key)
        : core.WampCborXsalsa20Poly1305Provider.single(keyId: keyId!, key: key);
  }

  Map<String, dynamic>? get keywords => encrypted ? {'n': 42} : null;

  void expectMetadata(core.PPTOptions options) {
    expect(options.pptScheme, scheme);
    expect(options.pptSerializer, serializer);
    expect(options.pptCipher, cipher);
    expect(options.pptKeyId, keyId);
  }

  void expectFields({
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
  }) {
    expect(pptScheme, scheme);
    expect(pptSerializer, serializer);
    expect(pptCipher, cipher);
    expect(pptKeyId, keyId);
  }

  void expectApplication(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    Uint8List expected,
    int id,
  ) {
    expect(arguments, hasLength(1));
    expect(arguments!.single, isA<Uint8List>());
    final actual = arguments.single as Uint8List;
    expect(actual, expected);
    expect(_applicationId(actual), id);
    expect(argumentsKeywords, keywords);
  }
}

const _modes = [
  _Mode('typed PPT', 'x_connectanum_test', 'flatbuffers'),
  _Mode('CBOR XSalsa20 E2EE', 'wamp', 'cbor', 'xsalsa20poly1305'),
  _Mode('CBOR AES256 E2EE', 'wamp', 'cbor', 'aes256gcm'),
];

class _Peer {
  _Peer(this.clientInstance, this.session, this.observer, this.nativeCodes);
  final client.Client clientInstance;
  final client.Session session;
  final StreamSubscription<Object?> observer;
  final Set<int> nativeCodes;

  static Future<_Peer> connect(
    int port,
    String serializer,
    String library,
    _Mode mode,
  ) async {
    final transport = switch (serializer) {
      'flatbuffers' =>
        client.NativeRawSocketTransport.withFlatBuffersSerializer(
          '127.0.0.1',
          port,
          libraryPath: library,
          messageLengthExponent: 20,
        ),
      'cbor' => client.NativeRawSocketTransport.withCborSerializer(
        '127.0.0.1',
        port,
        libraryPath: library,
        messageLengthExponent: 20,
      ),
      'msgpack' => client.NativeRawSocketTransport.withMsgpackSerializer(
        '127.0.0.1',
        port,
        libraryPath: library,
        messageLengthExponent: 20,
      ),
      'json' => client.NativeRawSocketTransport.withJsonSerializer(
        '127.0.0.1',
        port,
        libraryPath: library,
        messageLengthExponent: 20,
      ),
      _ => throw ArgumentError.value(serializer),
    };
    final instance = client.Client(
      transport: transport,
      realm: 'realm1',
      e2eeProvider: mode.provider(),
    );
    try {
      final session = await instance
          .connect(options: client.ClientConnectOptions(reconnectCount: 0))
          .first
          .timeout(_deadline);
      final nativeCodes = <int>{};
      final observer = (transport as SessionOptimizedTransport)
          .receiveSessionMessages()
          .listen((message) {
            if (message is NativeSessionMessage) {
              nativeCodes.add(message.metadata.messageCode);
            }
          });
      return _Peer(instance, session, observer, nativeCodes);
    } catch (_) {
      await instance.disconnect().timeout(_deadline);
      rethrow;
    }
  }

  Future<void> close() async {
    await observer.cancel();
    await clientInstance.disconnect().timeout(_deadline);
  }
}

class _Harness {
  _Harness(this.runtime, this.binding, this.errors);
  final NativeTransportRuntime runtime;
  final RouterBinding binding;
  final List<Object> errors;
  final peers = <_Peer>[];
  int get port => binding.listeners.single.port;

  static _Harness start(String library) {
    final settings =
        (RouterSettingsBuilder()
              ..addRealmFromBuilder(
                RealmSettingsBuilder('realm1')
                  ..addAuthMethod('anonymous')
                  ..addRoleFromBuilder(
                    RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
                      PermissionSettingsBuilder('')
                        ..setMatchPolicy(PermissionMatchPolicy.prefix)
                        ..allowOperations([
                          'call',
                          'register',
                          'subscribe',
                          'publish',
                        ]),
                    ),
                  ),
              )
              ..addListenerFromBuilder(
                ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
                  ..addAuthMethod('anonymous')
                  ..setOptions({'max_rawsocket_size_exponent': 20}),
              ))
            .build();
    final runtime = NativeTransportRuntime(libraryPath: library)..start();
    final errors = <Object>[];
    final binding =
        Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.disabled,
                maxRawSocketSizeExponent: 20,
              ),
            ],
          ),
          settings: settings,
        ).start(
          runtime,
          onEvent: (event) {
            if (event is Map && event['type'] == 'worker_error') {
              errors.add(event);
            }
          },
        );
    return _Harness(runtime, binding, errors);
  }

  Future<_Peer> connect(String serializer, String library, _Mode mode) async {
    final peer = await _Peer.connect(port, serializer, library, mode);
    peers.add(peer);
    return peer;
  }

  Future<void> close() async {
    try {
      for (final peer in peers.reversed) {
        await peer.close();
      }
    } finally {
      await binding.dispose();
      runtime.shutdown();
      runtime.dispose();
    }
  }
}

void main() {
  final library = resolveOrBuildNativeLib();
  for (final mode in _modes.where((mode) => mode.encrypted)) {
    for (final encryptedSource in [false, true]) {
      test(
        'public packed CBOR ${mode.name} sourceEncrypted=$encryptedSource applies outbound key',
        () async {
          final harness = _Harness.start(library!);
          try {
            final caller = await harness.connect('flatbuffers', library, mode);
            final callee = await harness.connect('cbor', library, mode);
            final application = _application(121);
            final sourceKey = List<int>.generate(32, (index) => 255 - index);
            final core.WampE2eeProvider sourceProvider =
                mode.cipher == 'aes256gcm'
                ? core.WampCborAes256GcmProvider.single(
                    keyId: 'source-key',
                    key: sourceKey,
                  )
                : core.WampCborXsalsa20Poly1305Provider.single(
                    keyId: 'source-key',
                    key: sourceKey,
                  );
            final sourceOptions = core.YieldOptions(
              pptScheme: 'wamp',
              pptSerializer: 'cbor',
            );
            final packed = encryptedSource
                ? sourceProvider
                          .packPayload(
                            [application],
                            mode.keywords,
                            sourceOptions,
                          )
                          .single
                      as Uint8List
                : Uint8List.fromList(
                    cbor.Serializer().serializePPT(
                      core.PPTPayload(
                        arguments: [application],
                        argumentsKeywords: mode.keywords,
                      ),
                    ),
                  );
            var decodes = 0;
            final payload = core.LazyMessagePayload.packed(
              encoding: core.LazyPayloadEncoding.cbor,
              packedPayloadBytes: packed,
              packedPayloadDecoder: (bytes) {
                decodes++;
                if (encryptedSource) {
                  final decoded = sourceProvider.unpackPayload([
                    bytes,
                  ], sourceOptions);
                  return (
                    arguments: decoded.arguments,
                    argumentsKeywords: decoded.argumentsKeywords,
                  );
                }
                final decoded = cbor.Serializer().deserializePPT(bytes)!;
                return (
                  arguments: decoded.arguments,
                  argumentsKeywords: decoded.argumentsKeywords,
                );
              },
            );
            await callee.session
                .registerLazyPayloadHandler('com.ppt.rekey', (invocation) {
                  mode.expectFields(
                    pptScheme: invocation.pptScheme,
                    pptSerializer: invocation.pptSerializer,
                    pptCipher: invocation.pptCipher,
                    pptKeyId: invocation.pptKeyId,
                  );
                  mode.expectApplication(
                    invocation.arguments,
                    invocation.argumentsKeywords,
                    application,
                    121,
                  );
                  invocation.respondWith(
                    lazyPayload: invocation.payload,
                    options: mode.replyOptions(),
                  );
                })
                .timeout(_deadline);
            final result = await caller.session
                .callSingleLazyPayloadView(
                  'com.ppt.rekey',
                  payload: payload,
                  options: mode.callOptions(),
                )
                .timeout(_deadline);
            mode.expectApplication(
              result.arguments,
              result.argumentsKeywords,
              application,
              121,
            );
            final event = Completer<core.LazyEventPayload>();
            await callee.session
                .subscribeLazyPayloadHandler(
                  'com.ppt.rekey.topic',
                  event.complete,
                )
                .timeout(_deadline);
            await caller.session
                .publishLazyPayload(
                  'com.ppt.rekey.topic',
                  payload: payload,
                  options: mode.publishOptions(),
                )
                .timeout(_deadline);
            final received = await event.future.timeout(_deadline);
            mode.expectFields(
              pptScheme: received.pptScheme,
              pptSerializer: received.pptSerializer,
              pptCipher: received.pptCipher,
              pptKeyId: received.pptKeyId,
            );
            mode.expectApplication(
              received.arguments,
              received.argumentsKeywords,
              application,
              121,
            );
            expect(decodes, 1);
            expect(harness.errors, isEmpty);
          } finally {
            await harness.close();
          }
        },
        skip: library == null ? 'native library unavailable' : false,
      );
    }
  }
  for (final pair in _pairs) {
    test(
      'public lazy ${pair.$1} -> ${pair.$2} preserves custom details',
      () async {
        final harness = _Harness.start(library!);
        final mode = _modes.first;
        try {
          final caller = await harness.connect(pair.$1, library, mode);
          final callee = await harness.connect(pair.$2, library, mode);
          final application = _application(101);
          await callee.session
              .registerLazyPayloadHandler('com.ppt.custom', (invocation) {
                expect(invocation.customDetails?['_call_trace'], 'call');
                expect(
                  invocation.customDetails?.containsKey('ppt_scheme'),
                  isFalse,
                );
                mode.expectApplication(
                  invocation.arguments,
                  invocation.argumentsKeywords,
                  application,
                  101,
                );
                invocation.respondWith(
                  lazyPayload: invocation.payload,
                  options: mode.replyOptions()
                    ..custom['_reply_trace'] = 'reply',
                );
              })
              .timeout(_deadline);
          final result = await caller.session
              .callSingleLazyPayload(
                'com.ppt.custom',
                arguments: [application],
                options: mode.callOptions()..custom['_call_trace'] = 'call',
              )
              .timeout(_deadline)
              .catchError((Object error) {
                if (error is core.Error) {
                  fail(
                    'Custom-details RPC ERROR ${error.error}: ${error.arguments}',
                  );
                }
                throw error;
              });
          expect(result.customDetails?['_reply_trace'], 'reply');
          expect(result.customDetails?.containsKey('ppt_scheme'), isFalse);
          mode.expectApplication(
            result.arguments,
            result.argumentsKeywords,
            application,
            101,
          );
          final event = Completer<core.LazyEventPayload>();
          await caller.session
              .subscribeLazyPayloadHandler(
                'com.ppt.custom.topic',
                event.complete,
              )
              .timeout(_deadline);
          await callee.session
              .publish(
                'com.ppt.custom.topic',
                arguments: [application],
                options: mode.publishOptions()
                  ..custom['_event_trace'] = 'event',
              )
              .timeout(_deadline);
          final received = await event.future.timeout(_deadline);
          expect(received.customDetails?['_event_trace'], 'event');
          expect(received.customDetails?.containsKey('ppt_scheme'), isFalse);
          mode.expectApplication(
            received.arguments,
            received.argumentsKeywords,
            application,
            101,
          );
          expect(harness.errors, isEmpty);
        } finally {
          await harness.close();
        }
      },
      skip: library == null ? 'native library unavailable' : false,
    );
  }
  for (final pair in _pairs) {
    for (final mode in _modes) {
      for (final isError in [false, true]) {
        test(
          'public lazy ${pair.$1} -> ${pair.$2} ${mode.name} error=$isError',
          () async {
            final harness = _Harness.start(library!);
            try {
              final caller = await harness.connect(pair.$1, library, mode);
              final callee = await harness.connect(pair.$2, library, mode);
              final application = _application(91);
              await callee.session
                  .registerLazyPayloadHandler('com.ppt.lazy', (invocation) {
                    mode.expectFields(
                      pptScheme: invocation.pptScheme,
                      pptSerializer: invocation.pptSerializer,
                      pptCipher: invocation.pptCipher,
                      pptKeyId: invocation.pptKeyId,
                    );
                    mode.expectApplication(
                      invocation.arguments,
                      invocation.argumentsKeywords,
                      application,
                      91,
                    );
                    if (!mode.encrypted) {
                      expect(
                        invocation.payload.encoding,
                        core.LazyPayloadEncoding.flatbuffers,
                      );
                      expect(invocation.packedPayloadBytes, application);
                    }
                    invocation.respondWith(
                      isError: isError,
                      errorUri: isError ? 'com.ppt.lazy.failure' : null,
                      lazyPayload: invocation.payload,
                      options: mode.replyOptions(),
                    );
                    expect(invocation.isResponseClosed(), isTrue);
                  })
                  .timeout(_deadline);
              final outbound = mode.encrypted
                  ? core.LazyMessagePayload.materialized(
                      arguments: [application],
                      argumentsKeywords: mode.keywords,
                    )
                  : core.LazyMessagePayload.packed(
                      encoding: core.LazyPayloadEncoding.flatbuffers,
                      packedPayloadBytes: application,
                      packedPayloadDecoder: (_) => throw StateError(
                        'outbound typed payload must stay opaque',
                      ),
                      anchor: application,
                    );
              try {
                final result = await caller.session
                    .callSingleLazyPayloadView(
                      'com.ppt.lazy',
                      payload: outbound,
                      options: mode.callOptions(),
                    )
                    .timeout(_deadline);
                expect(isError, isFalse, reason: 'Expected an ERROR response');
                mode.expectFields(
                  pptScheme: result.pptScheme,
                  pptSerializer: result.pptSerializer,
                  pptCipher: result.pptCipher,
                  pptKeyId: result.pptKeyId,
                );
                mode.expectApplication(
                  result.arguments,
                  result.argumentsKeywords,
                  application,
                  91,
                );
                if (!mode.encrypted) {
                  expect(
                    result.payload.encoding,
                    core.LazyPayloadEncoding.flatbuffers,
                  );
                  expect(result.packedPayloadBytes, application);
                }
              } on core.Error catch (error) {
                expect(
                  isError,
                  isTrue,
                  reason: 'Unexpected ERROR ${error.error}: ${error.arguments}',
                );
                expect(error.error, 'com.ppt.lazy.failure');
                mode.expectFields(
                  pptScheme: error.details['ppt_scheme'] as String?,
                  pptSerializer: error.details['ppt_serializer'] as String?,
                  pptCipher: error.details['ppt_cipher'] as String?,
                  pptKeyId: error.details['ppt_keyid'] as String?,
                );
                final decoded = core.decodeLazyPayloadView(
                  error.toLazyPayload(),
                  pptScheme: mode.scheme,
                  pptSerializer: mode.serializer,
                  pptCipher: mode.cipher,
                  pptKeyId: mode.keyId,
                );
                mode.expectApplication(
                  decoded.arguments,
                  decoded.argumentsKeywords,
                  application,
                  91,
                );
              }
              expect(
                callee.nativeCodes,
                contains(core.MessageTypes.codeInvocation),
              );
              expect(
                caller.nativeCodes,
                contains(
                  isError
                      ? core.MessageTypes.codeError
                      : core.MessageTypes.codeResult,
                ),
              );
              if (!isError) {
                final event = Completer<core.LazyEventPayload>();
                await caller.session
                    .subscribeLazyPayloadHandler(
                      'com.ppt.lazy.topic',
                      event.complete,
                    )
                    .timeout(_deadline);
                await callee.session.publishLazyPayload(
                  'com.ppt.lazy.topic',
                  payload: outbound,
                  options: mode.publishOptions(),
                );
                final received = await event.future.timeout(_deadline);
                mode.expectFields(
                  pptScheme: received.pptScheme,
                  pptSerializer: received.pptSerializer,
                  pptCipher: received.pptCipher,
                  pptKeyId: received.pptKeyId,
                );
                mode.expectApplication(
                  received.arguments,
                  received.argumentsKeywords,
                  application,
                  91,
                );
                if (!mode.encrypted) {
                  expect(received.packedPayloadBytes, application);
                }
                expect(
                  caller.nativeCodes,
                  contains(core.MessageTypes.codeEvent),
                );
              }
              expect(harness.errors, isEmpty);
            } finally {
              await harness.close();
            }
          },
          skip: library == null ? 'native library unavailable' : false,
        );
      }
    }
  }
  for (final pair in _pairs) {
    for (final mode in _modes) {
      test(
        'public ${pair.$1} -> ${pair.$2} ${mode.name} RPC/progress/pubsub',
        () async {
          final harness = _Harness.start(library!);
          try {
            final caller = await harness.connect(pair.$1, library, mode);
            final callee = await harness.connect(pair.$2, library, mode);
            final first = _application(71);
            final last = _application(72);
            final registered = await callee.session
                .register('com.ppt.echo')
                .timeout(_deadline);
            registered.onInvoke((invocation) {
              mode.expectMetadata(invocation.details);
              mode.expectApplication(
                invocation.arguments,
                invocation.argumentsKeywords,
                first,
                71,
              );
              invocation.respondWith(
                arguments: [first],
                argumentsKeywords: mode.keywords,
                options: mode.replyOptions(progress: true),
              );
              invocation.respondWith(
                arguments: [last],
                argumentsKeywords: mode.keywords,
                options: mode.replyOptions(),
              );
            });
            final results = await caller.session
                .call(
                  'com.ppt.echo',
                  arguments: [first],
                  argumentsKeywords: mode.keywords,
                  options: mode.callOptions(),
                )
                .toList()
                .timeout(_deadline);
            expect(results, hasLength(2));
            for (var i = 0; i < results.length; i++) {
              final result = results[i];
              mode.expectMetadata(result.details);
              expect(result.isProgressive(), i == 0);
              mode.expectApplication(
                result.arguments,
                result.argumentsKeywords,
                i == 0 ? first : last,
                i == 0 ? 71 : 72,
              );
            }
            final subscribed = await callee.session
                .subscribe('com.ppt.topic')
                .timeout(_deadline);
            final eventFuture = subscribed.eventStream!.first.timeout(
              _deadline,
            );
            final published = await caller.session
                .publish(
                  'com.ppt.topic',
                  arguments: [first],
                  argumentsKeywords: mode.keywords,
                  options: mode.publishOptions(),
                )
                .timeout(_deadline);
            expect(published, isNotNull);
            final event = await eventFuture;
            mode.expectMetadata(event.details);
            mode.expectApplication(
              event.arguments,
              event.argumentsKeywords,
              first,
              71,
            );
            expect(harness.errors, isEmpty);
          } on core.Error catch (error) {
            fail(
              'Router ERROR ${error.error}: ${error.details}; ${error.arguments}',
            );
          } finally {
            await harness.close();
          }
        },
        skip: library == null ? 'native library unavailable' : false,
      );
    }
  }

  test(
    'public FlatBuffers typed PPT ERROR retains payload and metadata',
    () async {
      final harness = _Harness.start(library!);
      final mode = _modes.first;
      try {
        final caller = await harness.connect('flatbuffers', library, mode);
        final callee = await harness.connect('flatbuffers', library, mode);
        final application = _application(81);
        final registration = await callee.session
            .register('com.ppt.error')
            .timeout(_deadline);
        registration.onInvoke((invocation) {
          mode.expectMetadata(invocation.details);
          invocation.respondWith(
            isError: true,
            errorUri: 'com.ppt.failure',
            arguments: [application],
            options: mode.replyOptions(),
          );
        });
        core.Error? observed;
        try {
          await caller.session
              .call(
                'com.ppt.error',
                arguments: [application],
                options: mode.callOptions(),
              )
              .toList()
              .timeout(_deadline);
          fail('Expected an ERROR response');
        } on core.Error catch (error) {
          observed = error;
        }
        expect(observed, isNotNull);
        expect(observed.error, 'com.ppt.failure');
        expect(observed.details['ppt_scheme'], mode.scheme);
        expect(observed.details['ppt_serializer'], mode.serializer);
        final payload = core.decodePayloadView(
          observed.arguments,
          observed.argumentsKeywords,
          pptScheme: mode.scheme,
          pptSerializer: mode.serializer,
          pptCipher: null,
          pptKeyId: null,
        );
        mode.expectApplication(
          payload.arguments,
          payload.argumentsKeywords,
          application,
          81,
        );
        expect(harness.errors, isEmpty);
      } finally {
        await harness.close();
      }
    },
    skip: library == null ? 'native library unavailable' : false,
  );
}
