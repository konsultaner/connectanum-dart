@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart'
    show NativeClientRuntime;
import 'package:connectanum_core/authentication.dart' as auth;
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  final nativeLibrary = _nativeLibrary();
  tearDownAll(NativeClientRuntime.shutdownShared);
  test(
    'factory defaults do not silently enable TLS or disable verification',
    () {
      final raw = RawSocketWampSessionFactory(
        host: '127.0.0.1',
        port: 1,
        realmUri: 'test',
      );
      final web = WebSocketWampSessionFactory(
        url: 'ws://127.0.0.1:1',
        realmUri: 'test',
      );
      expect(raw.ssl, isFalse);
      expect(raw.allowInsecureCertificates, isFalse);
      expect(web.allowInsecureCertificates, isFalse);
      expect(web.headers, isEmpty);
      expect(web.websocketFragmentSize, isNull);
    },
  );
  for (final implementation in WampClientImplementation.values) {
    for (final transport in WampTransport.values) {
      for (final serializer in WampSerializer.values) {
        final label =
            '${implementation.name}/${transport.name}/${serializer.name}';
        final skip =
            implementation == WampClientImplementation.native &&
                nativeLibrary == null
            ? 'Native transport artifact unavailable'
            : false;
        for (final secure in [false, true]) {
          test(
            'factory $label secure=$secure preserves wire and ownership',
            () async {
              final peer = await _FactoryPeer.start(
                transport,
                serializer,
                secure: secure,
              );
              addTearDown(peer.close);
              final provider = _OwnedProvider();
              final session = await peer.connect(
                implementation,
                nativeLibrary,
                provider,
              );
              addTearDown(session.close);
              await _expectHandshake(peer, transport, serializer);
              expect(session.id, 4321);
              expect(provider.releases, 0);
              final payload = List.filled(80, 'fragmented payload').join('/');
              final response = session.callSingle(
                'bench.factory.echo',
                arguments: [17, payload],
                argumentsKeywords: {'value': null, 'unicode': '\u00e4'},
                options: wamp.CallOptions(timeout: 1234),
              );
              final call = await peer.next();
              expect(call, [
                48,
                isA<int>(),
                {'timeout': 1234},
                'bench.factory.echo',
                [17, payload],
                {'value': null, 'unicode': '\u00e4'},
              ]);
              final result = await response;
              expect(result.callRequestId, call[1]);
              expect(result.arguments, [17, payload]);
              expect(result.argumentsKeywords, {
                'value': null,
                'unicode': '\u00e4',
              });
              await session.close();
              expect(await peer.next(), ['closed']);
              expect(provider.releases, 1);
              await session.close();
              expect(provider.releases, 1);
            },
            skip: skip,
          );
        }
        test('factory $label rejects auth and releases its provider', () async {
          final peer = await _FactoryPeer.start(
            transport,
            serializer,
            reject: true,
          );
          addTearDown(peer.close);
          final provider = _OwnedProvider();
          await expectLater(
            peer.connect(implementation, nativeLibrary, provider).then((
              session,
            ) {
              addTearDown(session.close);
              return session;
            }),
            throwsA(
              isA<wamp.Abort>().having(
                (e) => e.reason,
                'reason',
                'wamp.error.not_authorized',
              ),
            ),
          );
          await _expectHandshake(peer, transport, serializer);
          expect(await peer.next(), ['closed']);
          expect(provider.releases, 1);
        }, skip: skip);
      }
    }
  }

  for (final method in ['ticket', 'cra', 'wampcra', 'scram', 'wamp-scram']) {
    for (final secret in [null, '']) {
      test('auth factory rejects $method secret=$secret', () {
        expect(
          () => authenticationMethodsForScenario(
            _scenario(authMethod: method, authSecret: secret),
          ),
          throwsStateError,
        );
      });
    }
    test('auth factory creates fresh case-insensitive $method methods', () {
      final scenario = _scenario(
        authMethod: method.toUpperCase(),
        authSecret: 'test-secret',
      );
      late List<auth.AbstractAuthentication>? first;
      late List<auth.AbstractAuthentication>? second;
      expect(() {
        first = authenticationMethodsForScenario(scenario);
      }, returnsNormally);
      expect(() {
        second = authenticationMethodsForScenario(scenario);
      }, returnsNormally);
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(second!.single, isNot(same(first!.single)));
      expect(first!.single.getName(), switch (method) {
        'cra' || 'wampcra' => 'wampcra',
        'scram' || 'wamp-scram' => 'wamp-scram',
        _ => 'ticket',
      });
    });
  }
  for (final method in ['', 'anonymous', 'ANONYMOUS']) {
    test('auth factory omits $method authentication', () {
      expect(
        authenticationMethodsForScenario(_scenario(authMethod: method)),
        isNull,
      );
    });
  }
  test('auth factory rejects unknown methods', () {
    expect(
      () => authenticationMethodsForScenario(_scenario(authMethod: 'unknown')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Unsupported WAMP auth method unknown',
        ),
      ),
    );
  });

  test('ordinary scenarios do not create an E2EE provider', () {
    expect(e2eeProviderFactoryForScenario(_scenario()), isNull);
  });
  for (final invalid in [
    (null, 'key'),
    ('', 'key'),
    ('aes256gcm', null),
    ('aes256gcm', ''),
    ('unknown', 'key'),
  ]) {
    test('E2EE factory rejects incomplete or unknown profile $invalid', () {
      final scenario = _scenario().copyWith(
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
        pptCipher: invalid.$1,
        pptKeyId: invalid.$2,
      );
      expect(() => e2eeProviderFactoryForScenario(scenario), throwsStateError);
    });
  }
  for (final implementation in WampClientImplementation.values) {
    for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
      test(
        'E2EE factory ${implementation.name}/$cipher uses the benchmark key',
        () {
          final scenario = _scenario().copyWith(
            clientImplementation: implementation,
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
            pptCipher: cipher,
            pptKeyId: 'factory-key',
          );
          late WampE2eeProviderFactory? factory;
          expect(() {
            factory = e2eeProviderFactoryForScenario(
              scenario,
              nativeLibraryPath: nativeLibrary,
            );
          }, returnsNormally);
          expect(factory, isNotNull);
          final provider = factory!();
          final other = factory!();
          expect(other, isNot(same(provider)));
          for (final owned in [provider, other]) {
            if (owned is wamp.DisposableWampE2eeProvider) {
              addTearDown(owned.release);
            }
          }
          final key = utf8.encode('connectanum-e2ee-bench-key-v0001');
          final reference = cipher == 'aes256gcm'
              ? wamp.WampCborAes256GcmProvider.single(
                  keyId: 'factory-key',
                  key: key,
                )
              : wamp.WampCborXsalsa20Poly1305Provider.single(
                  keyId: 'factory-key',
                  key: key,
                );
          final options = wamp.PublishOptions(pptScheme: 'wamp');
          final packed = provider.packPayload(
            [17, 'test payload'],
            {'null': null},
            options,
          );
          expect(options.pptCipher, cipher);
          expect(options.pptSerializer, 'cbor');
          expect(options.pptKeyId, 'factory-key');
          late wamp.E2EEPayloadView decoded;
          expect(() {
            decoded = reference.unpackPayload(packed, options);
          }, returnsNormally);
          expect(decoded.arguments, [17, 'test payload']);
          expect(decoded.argumentsKeywords, {'null': null});
          final reply = reference.packPayload([23], {'reply': true}, options);
          expect(() {
            decoded = other.unpackPayload(reply, options);
          }, returnsNormally);
          expect(decoded.arguments, [23]);
          expect(decoded.argumentsKeywords, {'reply': true});
        },
        skip:
            implementation == WampClientImplementation.native &&
                nativeLibrary == null
            ? 'Native transport artifact unavailable'
            : false,
      );
    }
  }
}

WampScenario _scenario({
  String authMethod = 'ticket',
  String? authSecret = 'test-ticket',
}) => WampScenario(
  mode: WampMode.rpc,
  uri: 'bench.factory.echo',
  realmUri: 'bench.factory',
  transport: WampTransport.rawsocket,
  serializer: WampSerializer.json,
  iterations: 1,
  concurrency: 1,
  payloadBytes: 1,
  authId: 'factory-user',
  authMethod: authMethod,
  authSecret: authSecret,
);

Future<void> _expectHandshake(
  _FactoryPeer peer,
  WampTransport transport,
  WampSerializer serializer,
) async {
  if (transport == WampTransport.rawsocket) {
    expect(await peer.next(), [
      'negotiated',
      [0x7f, (8 << 4) | (serializer.index + 1), 0, 0],
    ]);
  } else {
    expect(await peer.next(), [
      'negotiated',
      'wamp.2.${serializer.name}',
      '/factory?case=wire',
      'bench-wire-test',
    ]);
  }
  final hello = await peer.next();
  expect(hello.take(2), [1, 'bench.factory']);
  expect(hello[2], containsPair('authid', 'factory-user'));
  expect(hello[2], containsPair('authmethods', ['ticket']));
  expect(await peer.next(), [5, 'test-ticket', {}]);
}

class _OwnedProvider extends wamp.DisposableWampE2eeProvider {
  int releases = 0;
  @override
  void release() => releases++;
  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    wamp.PPTOptions options, {
    wamp.WampE2eeRuntimeContext? runtimeContext,
  }) => throw StateError('Unencrypted factory traffic must not invoke E2EE');
  @override
  wamp.E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    wamp.PPTOptions options, {
    wamp.WampE2eeRuntimeContext? runtimeContext,
  }) => throw StateError('Unencrypted factory traffic must not invoke E2EE');
}

// Native connect waits synchronously for negotiation, so the independent peer
// lives on another isolate. It decodes wire values, not Connectanum messages.
class _FactoryPeer {
  _FactoryPeer(
    this.isolate,
    this.port,
    this.events,
    this.control,
    this.transport,
    this.serializer,
    this.secure,
    this.listener,
    this.exited,
  );
  final Isolate isolate;
  final ReceivePort port;
  final StreamIterator<dynamic> events;
  final SendPort control;
  final WampTransport transport;
  final WampSerializer serializer;
  final bool secure;
  final int listener;
  final Future<dynamic> exited;

  static Future<_FactoryPeer> start(
    WampTransport transport,
    WampSerializer serializer, {
    bool secure = false,
    bool reject = false,
  }) async {
    final port = ReceivePort();
    final events = StreamIterator<dynamic>(port);
    final exitPort = ReceivePort();
    final exited = exitPort.first;
    final isolate = await Isolate.spawn(
      _peerMain,
      {
        'events': port.sendPort,
        'transport': transport.name,
        'serializer': serializer.name,
        'secure': secure,
        'reject': reject,
        if (secure) 'cert': _fixture('bench_tls.crt'),
        if (secure) 'key': _fixture('bench_tls.key'),
      },
      onError: port.sendPort,
      onExit: exitPort.sendPort,
    );
    try {
      if (!await events.moveNext().timeout(const Duration(seconds: 5))) {
        throw StateError('Factory peer did not start');
      }
      final ready = events.current as List;
      if (ready.first != 'ready') {
        throw StateError('Factory peer startup failed: $ready');
      }
      return _FactoryPeer(
        isolate,
        port,
        events,
        ready[1] as SendPort,
        transport,
        serializer,
        secure,
        ready[2] as int,
        exited,
      );
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      await events.cancel();
      port.close();
      exitPort.close();
      rethrow;
    }
  }

  Future<WampSession> connect(
    WampClientImplementation implementation,
    String? library,
    _OwnedProvider provider,
  ) {
    final auth = authenticationMethodsForScenario(_scenario());
    return transport == WampTransport.rawsocket
        ? RawSocketWampSessionFactory(
            host: '127.0.0.1',
            port: listener,
            realmUri: 'bench.factory',
            authId: 'factory-user',
            authenticationMethods: auth,
            serializer: serializer,
            clientImplementation: implementation,
            ssl: secure,
            allowInsecureCertificates: secure,
            messageLengthExponent: 17,
            nativeLibraryPath: library,
            e2eeProviderFactory: () => provider,
          ).call()
        : WebSocketWampSessionFactory(
            url:
                '${secure ? 'wss' : 'ws'}://127.0.0.1:$listener/factory?case=wire',
            realmUri: 'bench.factory',
            authId: 'factory-user',
            authenticationMethods: auth,
            serializer: serializer,
            clientImplementation: implementation,
            headers: {'X-Benchmark-Case': 'bench-wire-test'},
            websocketFragmentSize: 37,
            allowInsecureCertificates: secure,
            nativeLibraryPath: library,
            e2eeProviderFactory: () => provider,
          ).call();
  }

  Future<List<dynamic>> next() async {
    if (!await events.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('Peer ended before the expected observation');
    }
    return (events.current as List).cast<dynamic>();
  }

  Future<void> close() async {
    control.send('stop');
    try {
      await exited.timeout(const Duration(seconds: 5));
    } finally {
      await events.cancel();
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }
}

Future<void> _peerMain(Map<String, Object?> config) async {
  final events = config['events'] as SendPort;
  final commands = ReceivePort();
  final serializer = config['serializer'] as String;
  final secure = config['secure'] as bool;
  final context = secure
      ? (SecurityContext()
          ..useCertificateChain(config['cert'] as String)
          ..usePrivateKey(config['key'] as String))
      : null;
  Socket? raw;
  WebSocket? web;
  late Future<void> Function() closeServer;

  Uint8List encode(List<dynamic> value) => switch (serializer) {
    'json' => Uint8List.fromList(utf8.encode(jsonEncode(value))),
    'msgpack' => msgpack.serialize(value),
    _ => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value))),
  };
  List<dynamic> decode(List<int> bytes) =>
      (switch (serializer) {
                'json' => jsonDecode(utf8.decode(bytes)),
                'msgpack' => msgpack.deserialize(Uint8List.fromList(bytes)),
                _ => cbor.cbor.decode(bytes).toObject(),
              }
              as List)
          .cast<dynamic>();

  void send(List<dynamic> frame) {
    final bytes = encode(frame);
    if (web != null) {
      web!.add(serializer == 'json' ? utf8.decode(bytes) : bytes);
    } else {
      raw!.add([
        0,
        (bytes.length >> 16) & 255,
        (bytes.length >> 8) & 255,
        bytes.length & 255,
        ...bytes,
      ]);
    }
  }

  void handle(List<dynamic> frame) {
    events.send(frame);
    switch (frame[0]) {
      case 1:
        send([4, 'ticket', {}]);
      case 5:
        send(
          config['reject'] == true
              ? [
                  3,
                  {'message': 'test rejection'},
                  'wamp.error.not_authorized',
                ]
              : [
                  2,
                  4321,
                  {
                    'roles': {
                      'dealer': {
                        'features': {'call_timeout': true},
                      },
                    },
                  },
                ],
        );
      case 48:
        send([50, frame[1], {}, frame[4], frame[5]]);
      case 6:
        send([6, {}, 'wamp.close.goodbye_and_out']);
    }
  }

  if (config['transport'] == 'rawsocket') {
    final Stream<Socket> connections;
    final int port;
    if (context == null) {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      connections = server;
      port = server.port;
      closeServer = () async {
        await server.close();
      };
    } else {
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      connections = server;
      port = server.port;
      closeServer = () async {
        await server.close();
      };
    }
    connections.listen((socket) {
      raw = socket;
      var buffer = <int>[];
      var negotiated = false;
      socket.listen(
        (data) {
          buffer.addAll(data);
          if (!negotiated && buffer.length >= 4) {
            final handshake = buffer.sublist(0, 4);
            events.send(['negotiated', handshake]);
            raw!.add(handshake);
            buffer = buffer.sublist(4);
            negotiated = true;
          }
          while (negotiated && buffer.length >= 4) {
            final length = (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];
            if (buffer.length < length + 4) break;
            if (buffer[0] != 0) {
              throw StateError('Unexpected RawSocket frame type ${buffer[0]}');
            }
            handle(decode(buffer.sublist(4, 4 + length)));
            buffer = buffer.sublist(4 + length);
          }
        },
        onDone: () {
          events.send(['closed']);
          raw!.destroy();
        },
        onError: (Object e) => events.send(['peer error', e.toString()]),
      );
    });
    events.send(['ready', commands.sendPort, port]);
  } else {
    final server = context == null
        ? await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        : await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    closeServer = () async {
      await server.close(force: true);
    };
    server.listen((request) async {
      web = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) {
          final expected = 'wamp.2.$serializer';
          events.send([
            'negotiated',
            protocols.single,
            request.uri.toString(),
            request.headers.value('X-Benchmark-Case'),
          ]);
          return protocols.contains(expected) ? expected : null;
        },
      );
      web!.listen(
        (data) {
          handle(
            decode(data is String ? utf8.encode(data) : data as List<int>),
          );
        },
        onDone: () => events.send(['closed']),
        onError: (Object e) => events.send(['peer error', e.toString()]),
      );
    });
    events.send(['ready', commands.sendPort, server.port]);
  }
  await commands.first;
  raw?.destroy();
  await web?.close();
  await closeServer();
  commands.close();
}

String _fixture(String name) {
  for (final prefix in ['native/bench', '../../native/bench']) {
    final file = File('$prefix/$name');
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError('Missing benchmark TLS fixture $name');
}

String? _nativeLibrary() {
  final override = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (override != null) return override;
  final name = Platform.isMacOS ? 'libct_ffi.dylib' : 'libct_ffi.so';
  for (final prefix in ['native/transport', '../../native/transport']) {
    final file = File('$prefix/target/ffi-test/release/$name');
    if (file.existsSync()) return file.absolute.path;
  }
  return null;
}
