import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/message_binding.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_client/src/transport/native/e2ee_file_segment.dart';
import 'package:connectanum_client/src/transport/native/e2ee_provider_none.dart'
    as unavailable_native;
import 'package:test/test.dart';

import 'test_support/native_runtime_support.dart';

void main() {
  test(
    'metadata welcome establishes the exact typed Session provider',
    () async {
      final configured = _provider('aes256gcm', (_, _) => null);
      final resolved = WampFlatBuffersAes256GcmProvider(
        keys: {'outbound': List<int>.filled(32, 9)},
        defaultKeyId: 'outbound',
      );
      final peer = _MetadataPeer('aes256gcm');
      SessionE2eeProviderContext? observed;
      final client = Client(
        realm: 'app.realm',
        transport: peer,
        e2eeProvider: configured,
        e2eeProviderResolver: (context) async {
          observed = context;
          return resolved;
        },
      );
      addTearDown(client.disconnect);
      final session = await client.connect().first;
      expect(session.id, 42);
      expect(observed!.configuredProvider, same(configured));
      expect(observed!.negotiatedE2ee!.serializer, 'flatbuffers');
      expect(observed!.negotiatedE2ee!.outboundKeyId, 'outbound');
      await session.publishLazyPayload(
        'app.topic',
        payload: LazyMessagePayload.materialized(
          arguments: [
            Uint8List.fromList([3, 255]),
          ],
        ),
        options: PublishOptions(pptScheme: 'wamp'),
      );
      final publish = peer.sent.whereType<Publish>().single;
      expect(publish.options!.pptKeyId, 'outbound');
      expect(
        resolved.unpackPayload(publish.arguments, publish.options!).arguments,
        [
          Uint8List.fromList([3, 255]),
        ],
      );
      expect(
        () => configured.unpackPayload(publish.arguments, publish.options!),
        throwsA(isA<WampE2eeDecryptionException>()),
      );
    },
  );
  for (final alreadyDecoded in [false, true]) {
    test(
      'plain publish unwraps packed application values decoded=$alreadyDecoded',
      () async {
        final peer = _Peer('aes256gcm');
        final session = await _connect(
          peer,
          _provider('aes256gcm', (_, _) => null),
        );
        final bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              ['packed'],
              {'state': 'ready'},
            ]),
          ),
        );
        final before = bytes.toList();
        var decodes = 0;
        final payload = LazyMessagePayload.packed(
          encoding: LazyPayloadEncoding.json,
          packedPayloadBytes: bytes,
          pptDecoded: alreadyDecoded,
          packedPayloadDecoder: (buffer) {
            decodes++;
            final values = jsonDecode(utf8.decode(buffer)) as List;
            return (
              arguments: List<dynamic>.from(values[0] as List),
              argumentsKeywords: Map<String, dynamic>.from(values[1] as Map),
            );
          },
        );
        await session.publishLazyPayload(
          'app.topic',
          payload: payload,
          options: PublishOptions(),
        );
        final published = peer.sent.whereType<Publish>().single;
        expect(published.arguments, ['packed']);
        expect(published.argumentsKeywords, {'state': 'ready'});
        expect(published.hasDecodedPptPayload, alreadyDecoded);
        expect(decodes, 1);
        expect(bytes, before);
      },
    );
  }
  for (final (name, normal, single)
      in <(String, void Function(), void Function())>[
        (
          'xsalsa20poly1305',
          () => unavailable_native.NativeWampCborXsalsa20Poly1305Provider(
            keys: {'kid': List<int>.filled(32, 1)},
          ),
          () =>
              unavailable_native.NativeWampCborXsalsa20Poly1305Provider.single(
                keyId: 'kid',
                key: List<int>.filled(32, 1),
              ),
        ),
        (
          'aes256gcm',
          () => unavailable_native.NativeWampCborAes256GcmProvider(
            keys: {'kid': List<int>.filled(32, 1)},
          ),
          () => unavailable_native.NativeWampCborAes256GcmProvider.single(
            keyId: 'kid',
            key: List<int>.filled(32, 1),
          ),
        ),
      ]) {
    test('unavailable native CBOR $name constructors reject explicitly', () {
      expect(normal, throwsUnsupportedError);
      expect(single, throwsUnsupportedError);
    });
  }
  for (final key in ['explicit', 'policy', 'outbound']) {
    for (final withContext in [false, true]) {
      test(
        'negotiated file delegate selects $key withContext=$withContext',
        () async {
          var policyCalls = 0;
          final provider = _FileProbe(
            _provider('aes256gcm', (_, _) {
              policyCalls++;
              return key == 'policy' ? 'policy' : null;
            }, typed: false),
          );
          final peer = _Peer('aes256gcm', typed: false);
          final session = await _connect(peer, provider);
          await session.publishLazyPayload(
            'app.topic',
            payload: LazyMessagePayload.materialized(arguments: [Uint8List(0)]),
            options: PublishOptions(pptScheme: 'wamp', pptKeyId: 'explicit'),
          );
          policyCalls = 0;
          final wrapped =
              peer.sent.whereType<Publish>().single.e2eeProvider!
                  as NativeE2eeFileSegmentProvider;
          expect(wrapped.supportsNativeE2eeFileSegments, isTrue);
          final anchor = Object();
          final context = withContext
              ? WampE2eeRuntimeContext(
                  direction: WampE2eeDirection.outbound,
                  messageType: WampE2eeMessageType.publish,
                  uri: 'app.file',
                  payloadAnchor: anchor,
                )
              : null;
          final options = PublishOptions(
            pptScheme: 'wamp',
            pptKeyId: key == 'explicit' ? 'explicit' : null,
          );
          final result = wrapped.prepareNativeE2eeFileSegment(
            options,
            runtimeContext: context,
          );
          final expectedKey = key == 'explicit'
              ? 'explicit'
              : key == 'policy' && withContext
              ? 'policy'
              : 'outbound';
          expect(result.runtimeIdentity, same(provider.identity));
          expect(result.sessionHandle, 73);
          expect(result.keyId, expectedKey);
          expect(result.cipher, 'aes256gcm');
          expect(provider.preparedOptions, same(options));
          expect(options.pptSerializer, 'cbor');
          expect(options.pptKeyId, expectedKey);
          expect(policyCalls, withContext && key != 'explicit' ? 1 : 0);
          expect(provider.prepareCalls, 1);
          if (withContext) {
            expect(provider.preparedContext!.payloadAnchor, same(anchor));
            expect(provider.preparedContext!.direction, context!.direction);
            expect(provider.preparedContext!.uri, 'app.file');
            expect(provider.preparedContext!.realm, 'app.realm');
            expect(provider.preparedContext!.local!.sessionId, 42);
            expect(
              provider.preparedContext!.negotiated!['send_key_id'],
              'outbound',
            );
          } else {
            expect(provider.preparedContext, isNull);
          }
        },
      );
    }
  }
  for (final implementsFiles in [false, true]) {
    test(
      'negotiated file delegate rejects unsupported implementsFiles=$implementsFiles',
      () async {
        final delegate = _provider('aes256gcm', (_, _) => null, typed: false);
        final provider = implementsFiles
            ? (_FileProbe(delegate)..filesAllowed = false)
            : _RuntimeProbe(delegate);
        final peer = _Peer('aes256gcm', typed: false);
        final session = await _connect(peer, provider);
        await session.publishLazyPayload(
          'app.topic',
          payload: LazyMessagePayload.materialized(arguments: [Uint8List(0)]),
          options: PublishOptions(pptScheme: 'wamp', pptKeyId: 'explicit'),
        );
        final wrapped =
            peer.sent.whereType<Publish>().single.e2eeProvider!
                as NativeE2eeFileSegmentProvider;
        expect(wrapped.supportsNativeE2eeFileSegments, isFalse);
        final options = PublishOptions(pptScheme: 'wamp');
        expect(
          () => wrapped.prepareNativeE2eeFileSegment(options),
          throwsUnsupportedError,
        );
        expect(options.pptKeyId, isNull);
        expect(options.pptSerializer, isNull);
        if (provider is _FileProbe) expect(provider.prepareCalls, 0);
      },
    );
  }
  test('negotiated file delegate preserves non-wamp metadata', () async {
    var policyCalls = 0;
    final provider = _FileProbe(
      _provider('aes256gcm', (_, _) {
        policyCalls++;
        return 'policy';
      }, typed: false),
    );
    final peer = _Peer('aes256gcm', typed: false);
    final session = await _connect(peer, provider);
    await session.publishLazyPayload(
      'app.topic',
      payload: LazyMessagePayload.materialized(arguments: [Uint8List(0)]),
      options: PublishOptions(pptScheme: 'wamp', pptKeyId: 'explicit'),
    );
    policyCalls = 0;
    final wrapped =
        peer.sent.whereType<Publish>().single.e2eeProvider!
            as NativeE2eeFileSegmentProvider;
    final options = PublishOptions(
      pptScheme: 'application',
      pptSerializer: 'application',
      pptCipher: 'aes256gcm',
      pptKeyId: 'explicit',
    );
    final result = wrapped.prepareNativeE2eeFileSegment(options);
    expect(result.keyId, 'explicit');
    expect(provider.preparedOptions, same(options));
    expect(options.pptScheme, 'application');
    expect(options.pptSerializer, 'application');
    expect(options.pptCipher, 'aes256gcm');
    expect(policyCalls, 0);
  });
  for (final native in [false, true]) {
    group(native ? 'native' : 'portable', () {
      for (final typed in [false, true]) {
        for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
          if (typed) {
            test(
              'negotiated typed $cipher retains context-free directional defaults',
              () async {
                var policyCalls = 0;
                final provider = _provider(cipher, (_, _) {
                  policyCalls++;
                  return null;
                }, native: native);
                final peer = _Peer(cipher);
                final session = await _connect(peer, provider);
                await session.publishLazyPayload(
                  'app.topic',
                  payload: LazyMessagePayload.materialized(
                    arguments: [Uint8List(0)],
                  ),
                  options: PublishOptions(pptScheme: 'wamp'),
                );
                final wrapped = peer.sent
                    .whereType<Publish>()
                    .single
                    .e2eeProvider!;
                policyCalls = 0;
                final outbound = PublishOptions(pptScheme: 'wamp');
                wrapped.packPayload([Uint8List(0)], null, outbound);
                expect(outbound.pptKeyId, 'outbound');
                final ciphertext = provider.packPayload(
                  [Uint8List(0)],
                  null,
                  PublishOptions(pptScheme: 'wamp', pptKeyId: 'inbound'),
                );
                final inbound = PublishOptions(pptScheme: 'wamp');
                expect(wrapped.unpackPayload(ciphertext, inbound).arguments, [
                  Uint8List(0),
                ]);
                expect(inbound.pptKeyId, 'inbound');
                expect(policyCalls, 0);
              },
            );
            test(
              'negotiated typed $cipher validates before key policy',
              () async {
                var policyCalls = 0;
                final provider = _provider(cipher, (_, _) {
                  policyCalls++;
                  return 'policy';
                }, native: native);
                final peer = _Peer(cipher);
                final session = await _connect(peer, provider);
                expect(
                  () => session.publishLazyPayload(
                    'app.topic',
                    payload: LazyMessagePayload.materialized(
                      arguments: ['invalid'],
                    ),
                    options: PublishOptions(pptScheme: 'wamp'),
                  ),
                  throwsUnsupportedError,
                );
                expect(policyCalls, 0);
                expect(peer.sent.whereType<Publish>(), isEmpty);
              },
            );
          }

          for (final selected in ['explicit', 'policy', 'outbound']) {
            test(
              'negotiated ${typed ? "typed" : "CBOR"} $cipher selects $selected key',
              () async {
                var policyCalls = 0;
                WampE2eeRuntimeContext? observed;
                final provider = _provider(
                  cipher,
                  (context, _) {
                    policyCalls++;
                    observed = context;
                    return selected == 'policy' ? 'policy' : null;
                  },
                  native: native,
                  typed: typed,
                );
                final peer = _Peer(cipher, typed: typed);
                final session = await _connect(peer, provider);
                await session.publishLazyPayload(
                  'app.topic',
                  payload: LazyMessagePayload.materialized(
                    arguments: [
                      Uint8List.fromList([1, 255]),
                    ],
                  ),
                  options: PublishOptions(
                    pptScheme: 'wamp',
                    pptKeyId: selected == 'explicit' ? 'explicit' : null,
                  ),
                );
                final publish = peer.sent.whereType<Publish>().single;
                expect(publish.options!.pptKeyId, selected);
                expect(policyCalls, selected == 'explicit' ? 0 : 1);
                if (selected != 'explicit') {
                  expect(observed!.direction, WampE2eeDirection.outbound);
                  expect(observed!.uri, 'app.topic');
                  expect(observed!.realm, 'app.realm');
                  expect(observed!.negotiated!['send_key_id'], 'outbound');
                }
                final decoded = provider.unpackPayload(
                  publish.arguments,
                  publish.options!,
                );
                expect(decoded.arguments, [
                  Uint8List.fromList([1, 255]),
                ]);
              },
            );
          }
          if (typed) {
            test(
              'negotiated typed $cipher validates inbound before key policy',
              () async {
                var policyCalls = 0;
                final provider = _provider(cipher, (_, _) {
                  policyCalls++;
                  return null;
                }, native: native);
                final peer = _Peer(cipher);
                final session = await _connect(peer, provider);
                await session.publishLazyPayload(
                  'app.topic',
                  payload: LazyMessagePayload.materialized(
                    arguments: [Uint8List(0)],
                  ),
                  options: PublishOptions(pptScheme: 'wamp'),
                );
                final wrapped = peer.sent
                    .whereType<Publish>()
                    .single
                    .e2eeProvider!;
                policyCalls = 0;
                expect(
                  () => wrapped.unpackPayload(
                    [
                      <int>[300],
                    ],
                    PublishOptions(pptScheme: 'wamp'),
                    runtimeContext: const WampE2eeRuntimeContext(
                      direction: WampE2eeDirection.inbound,
                      messageType: WampE2eeMessageType.event,
                      uri: 'app.topic',
                    ),
                  ),
                  throwsA(isA<WampE2eeInvalidPayloadException>()),
                );
                expect(policyCalls, 0);
              },
            );

            test(
              'negotiated typed $cipher selects directional inbound fallback',
              () async {
                var policyCalls = 0;
                final provider = _provider(cipher, (_, _) {
                  policyCalls++;
                  return null;
                }, native: native);
                final peer = _Peer(cipher);
                final session = await _connect(peer, provider);
                await session.publishLazyPayload(
                  'app.topic',
                  payload: LazyMessagePayload.materialized(
                    arguments: [Uint8List(0)],
                  ),
                  options: PublishOptions(pptScheme: 'wamp'),
                );
                final wrapped = peer.sent
                    .whereType<Publish>()
                    .single
                    .e2eeProvider!;
                final encrypted = provider.packPayload(
                  [
                    Uint8List.fromList([1, 255]),
                  ],
                  null,
                  PublishOptions(pptScheme: 'wamp', pptKeyId: 'inbound'),
                );
                policyCalls = 0;
                final options = PublishOptions(pptScheme: 'wamp');
                final decoded = wrapped.unpackPayload(
                  encrypted,
                  options,
                  runtimeContext: const WampE2eeRuntimeContext(
                    direction: WampE2eeDirection.inbound,
                    messageType: WampE2eeMessageType.event,
                    uri: 'app.topic',
                  ),
                );
                expect(decoded.arguments, [
                  Uint8List.fromList([1, 255]),
                ]);
                expect(options.pptKeyId, 'inbound');
                expect(policyCalls, 1);
              },
            );
          }
        }
      }
    }, skip: native ? nativeClientRuntimeSkipReason() : false);
  }

  test(
    'negotiated wrapper preserves runtime-payload capability and context',
    () async {
      final provider = _RuntimeProbe(_provider('aes256gcm', (_, _) => null));
      final peer = _Peer('aes256gcm');
      final session = await _connect(peer, provider);
      await session.publishLazyPayload(
        'app.topic',
        payload: LazyMessagePayload.materialized(arguments: [Uint8List(0)]),
        options: PublishOptions(pptScheme: 'wamp'),
      );
      final wrapped = peer.sent.whereType<Publish>().single.e2eeProvider!;
      expect(wrapped, isA<WampE2eeRuntimePayloadProvider>());
      final runtimeProvider = wrapped as WampE2eeRuntimePayloadProvider;
      final anchor = Object();
      final context = WampE2eeRuntimeContext(
        direction: WampE2eeDirection.inbound,
        messageType: WampE2eeMessageType.event,
        uri: 'app.topic',
        payloadAnchor: anchor,
      );
      expect(runtimeProvider.canUnpackFromRuntimeContext(context), isTrue);
      expect(provider.observed!.payloadAnchor, same(anchor));
      expect(provider.observed!.direction, WampE2eeDirection.inbound);
      expect(provider.observed!.uri, 'app.topic');
      expect(provider.observed!.realm, 'app.realm');
      expect(provider.observed!.local!.sessionId, 42);
      expect(provider.observed!.negotiated!['receive_key_id'], 'inbound');
      final encrypted = provider.delegate.packPayload(
        [
          Uint8List.fromList([1, 255]),
        ],
        null,
        PublishOptions(pptScheme: 'wamp', pptKeyId: 'inbound'),
      );
      final decoded = wrapped.unpackPayload(
        encrypted,
        PublishOptions(pptScheme: 'wamp'),
        runtimeContext: context,
      );
      expect(decoded.arguments, [
        Uint8List.fromList([1, 255]),
      ]);
      expect(provider.observed!.payloadAnchor, same(anchor));
      expect(provider.observed!.realm, 'app.realm');
      expect(provider.observed!.local!.sessionId, 42);
      expect(provider.observed!.negotiated!['receive_key_id'], 'inbound');
      provider.allowed = false;
      expect(runtimeProvider.canUnpackFromRuntimeContext(context), isFalse);
      expect(runtimeProvider.canUnpackFromRuntimeContext(null), isFalse);
      expect(provider.observed, isNull);
    },
  );

  test('custom opt-out provider retains wrapper policy and fallback', () async {
    var policyCalls = 0;
    final provider = _RuntimeProbe(
      _provider('aes256gcm', (_, _) {
        policyCalls++;
        return null;
      }),
    );
    final peer = _Peer('aes256gcm');
    final session = await _connect(peer, provider);
    await session.publishLazyPayload(
      'app.topic',
      payload: LazyMessagePayload.materialized(arguments: [Uint8List(0)]),
      options: PublishOptions(pptScheme: 'wamp'),
    );
    expect(peer.sent.whereType<Publish>().single.options!.pptKeyId, 'outbound');
    expect(policyCalls, 1);
    expect(
      () => session.publishLazyPayload(
        'app.topic',
        payload: LazyMessagePayload.materialized(arguments: ['invalid']),
        options: PublishOptions(pptScheme: 'wamp'),
      ),
      throwsUnsupportedError,
    );
    // The custom provider has not opted into validation before key selection.
    expect(policyCalls, 2);
  });
}

class _FileProbe extends _RuntimeProbe
    implements NativeE2eeFileSegmentProvider {
  _FileProbe(super.delegate);
  final identity = Object();
  bool filesAllowed = true;
  int prepareCalls = 0;
  PPTOptions? preparedOptions;
  WampE2eeRuntimeContext? preparedContext;
  @override
  bool get supportsNativeE2eeFileSegments => filesAllowed;
  @override
  NativeE2eeFileSegmentContext prepareNativeE2eeFileSegment(
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    prepareCalls++;
    preparedOptions = options;
    preparedContext = runtimeContext;
    return NativeE2eeFileSegmentContext(
      runtimeIdentity: identity,
      sessionHandle: 73,
      keyId: options.pptKeyId!,
      cipher: options.pptCipher!,
    );
  }
}

class _RuntimeProbe
    implements
        WampE2eeProvider,
        WampE2eePolicyAwareProvider,
        WampE2eeProfileSupport,
        WampE2eeRuntimePayloadProvider,
        WampE2eeNegotiatedKeySelectionProvider {
  _RuntimeProbe(this.delegate);
  final WampE2eeProvider delegate;
  WampE2eeRuntimeContext? observed;
  bool allowed = true;

  @override
  bool get handlesNegotiatedKeySelection => false;
  @override
  WampE2eeKeySelectionPolicy? get keySelectionPolicy =>
      (delegate as WampE2eePolicyAwareProvider).keySelectionPolicy;
  @override
  bool canUnpackFromRuntimeContext(WampE2eeRuntimeContext? context) {
    observed = context;
    return allowed && context?.payloadAnchor != null;
  }

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? keywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => delegate.packPayload(
    arguments,
    keywords,
    options,
    runtimeContext: runtimeContext,
  );
  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    observed = runtimeContext;
    return delegate.unpackPayload(
      arguments,
      options,
      runtimeContext: runtimeContext,
    );
  }

  @override
  bool supportsE2eeProfile({
    required int version,
    required String scheme,
    required String serializer,
    required String cipher,
  }) => (delegate as WampE2eeProfileSupport).supportsE2eeProfile(
    version: version,
    scheme: scheme,
    serializer: serializer,
    cipher: cipher,
  );
}

WampE2eeProvider _provider(
  String cipher,
  WampE2eeKeySelectionPolicy policy, {
  bool native = false,
  bool typed = true,
}) {
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
  if (native) {
    final DisposableWampE2eeProvider provider = switch ((cipher, typed)) {
      ('aes256gcm', true) => NativeWampFlatBuffersAes256GcmProvider(
        keys: keys,
        defaultKeyId: 'default',
        keySelectionPolicy: policy,
      ),
      ('aes256gcm', false) => NativeWampCborAes256GcmProvider(
        keys: keys,
        defaultKeyId: 'default',
        keySelectionPolicy: policy,
      ),
      (_, true) => NativeWampFlatBuffersXsalsa20Poly1305Provider(
        keys: keys,
        defaultKeyId: 'default',
        keySelectionPolicy: policy,
      ),
      (_, false) => NativeWampCborXsalsa20Poly1305Provider(
        keys: keys,
        defaultKeyId: 'default',
        keySelectionPolicy: policy,
      ),
    };
    addTearDown(provider.release);
    return provider;
  }
  if (!typed) {
    return cipher == 'aes256gcm'
        ? WampCborAes256GcmProvider(
            keys: keys,
            defaultKeyId: 'default',
            keySelectionPolicy: policy,
          )
        : WampCborXsalsa20Poly1305Provider(
            keys: keys,
            defaultKeyId: 'default',
            keySelectionPolicy: policy,
          );
  }
  return cipher == 'aes256gcm'
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
}

Future<Session> _connect(_Peer peer, WampE2eeProvider provider) async {
  final client = Client(
    realm: 'app.realm',
    transport: peer,
    e2eeProvider: provider,
  );
  addTearDown(client.disconnect);
  return client.connect().first;
}

class _MetadataPeer extends _Peer implements SessionOptimizedTransport {
  _MetadataPeer(super.cipher);
  @override
  Stream<Object?> receiveSessionMessages() => inbound.stream.expand((
    message,
  ) sync* {
    yield null;
    if (message is Welcome) {
      final wire = jsonDecode(json.Serializer().serialize(message)) as List;
      yield NativeSessionMessage(
        serializer: NativeMessageSerializer.json,
        metadata: NativeMessageMetadata(
          messageCode: MessageTypes.codeWelcome,
          primaryId: message.sessionId,
          secondaryId: 0,
          detailNumberA: 0,
          detailNumberB: 0,
          flags: NativeMessageMetadata.flagMetadataBind,
          detailsBytes: Uint8List.fromList(utf8.encode(jsonEncode(wire[2]))),
        ),
      );
    } else {
      yield message;
    }
  });
}

class _Peer extends AbstractTransport {
  _Peer(this.cipher, {this.typed = true});
  final String cipher;
  final bool typed;
  final inbound = StreamController<AbstractMessage>.broadcast(sync: true);
  final sent = <AbstractMessage>[];
  bool _open = false;
  @override
  final onDisconnect = Completer<void>();
  @override
  final onConnectionLost = Completer<void>();
  @override
  bool get isOpen => _open;
  @override
  bool get isReady => _open;
  @override
  Future<void> get onReady => Future.value();
  @override
  Future<void> open({Duration? pingInterval}) async => _open = true;
  @override
  Future<void> close({dynamic error}) async {
    if (!_open) return;
    _open = false;
    onDisconnect!.complete();
    await inbound.close();
  }

  @override
  Stream<AbstractMessage> receive() => inbound.stream;
  @override
  void send(AbstractMessage message) {
    sent.add(message);
    if (message is Hello) {
      inbound.add(
        Welcome(
          42,
          Details.forWelcome(
            authExtra: {
              'e2ee': {
                'version': typed ? 2 : 1,
                'required': true,
                'established': true,
                'scheme': 'wamp',
                'serializer': typed ? 'flatbuffers' : 'cbor',
                'cipher': cipher,
                'send_key_id': 'outbound',
                'receive_key_id': 'inbound',
              },
            },
          ),
        ),
      );
    }
  }
}
