@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport first.'
      : null;

  test(
    'rawsocket and websocket WAMP workloads run against a real router',
    () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib!)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });

      final settings = RouterSettingsBuilder()
          .addRealmFromBuilder(
            RealmSettingsBuilder('bench.control')
              ..addAuthMethod('anonymous')
              ..addRoleFromBuilder(
                RoleSettingsBuilder('bench')..addPermissionFromBuilder(
                  PermissionSettingsBuilder('')..allowOperations(const [
                    'register',
                    'unregister',
                    'subscribe',
                    'unsubscribe',
                    'publish',
                    'call',
                  ]),
                ),
              ),
          )
          .addListenerFromBuilder(
            ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
              ..addAuthMethod('anonymous')
              ..addProtocol(ListenerProtocol.rawsocket)
              ..addProtocol(ListenerProtocol.websocket)
              ..setPath('/wamp')
              ..setRawSocketOptions(
                const RawSocketListenerSettings(maxFrameExponent: 18),
              )
              ..setWebSocketOptions(
                const WebSocketListenerSettings(
                  path: '/wamp',
                  subprotocols: [
                    'wamp.2.json',
                    'wamp.2.msgpack',
                    'wamp.2.cbor',
                  ],
                ),
              ),
          )
          .addAuthenticator(
            'anonymous',
            const AuthenticatorDefinition(type: 'anonymous'),
          )
          .setWorkerPool(const WorkerPoolSettings(minWorkers: 1))
          .build();

      final config = RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.disabled,
            maxRawSocketSizeExponent: 18,
            webSocketPath: '/wamp',
          ),
        ],
      );

      final binding = Router(config, settings: settings).start(runtime);
      addTearDown(binding.dispose);

      final internalSession = await binding.createInternalSession(
        realmUri: 'bench.control',
        authId: 'bench-control',
        authRole: 'bench',
      );
      addTearDown(internalSession.close);

      final registration = await internalSession.register('bench.rpc.echo');
      registration.onInvoke((invocation) async {
        invocation.respondWith(
          arguments: invocation.arguments,
          argumentsKeywords: invocation.argumentsKeywords,
        );
      });

      final listener = binding.listeners.single;
      final runner = WampWorkloadRunner(
        sessionFactory: (scenario) {
          switch (scenario.transport) {
            case WampTransport.rawsocket:
              return RawSocketWampSessionFactory(
                host: '127.0.0.1',
                port: listener.port,
                realmUri: 'bench.control',
                serializer: scenario.serializer,
              ).call();
            case WampTransport.websocket:
              return WebSocketWampSessionFactory(
                url: 'ws://127.0.0.1:${listener.port}/wamp',
                realmUri: 'bench.control',
                serializer: scenario.serializer,
              ).call();
          }
        },
        logger: Logger.detached('wamp_transport_integration'),
        eventTimeout: const Duration(seconds: 5),
      );

      final rawPubSub = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.json,
          mode: WampMode.pubsub,
          uri: 'bench.topic',
          iterations: 4,
          concurrency: 2,
          payloadBytes: 32,
        ),
      );
      final rawRpc = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.msgpack,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 4,
          concurrency: 2,
          payloadBytes: 32,
        ),
      );
      final rawRpcCbor = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 4,
          concurrency: 2,
          payloadBytes: 32,
        ),
      );
      final webSocketPubSub = await runner.run(
        WampScenario(
          transport: WampTransport.websocket,
          serializer: WampSerializer.json,
          mode: WampMode.pubsub,
          uri: 'bench.topic',
          iterations: 4,
          concurrency: 2,
          payloadBytes: 32,
        ),
      );
      final webSocketRpcMsgPack = await runner.run(
        WampScenario(
          transport: WampTransport.websocket,
          serializer: WampSerializer.msgpack,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 4,
          concurrency: 2,
          payloadBytes: 32,
        ),
      );
      final webSocketRpc = await runner.run(
        WampScenario(
          transport: WampTransport.websocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 4,
          concurrency: 2,
          payloadBytes: 32,
        ),
      );
      final rawRpcCborLarge = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 8,
          concurrency: 4,
          payloadBytes: 16384,
        ),
      );
      final webSocketRpcCborLarge = await runner.run(
        WampScenario(
          transport: WampTransport.websocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 8,
          concurrency: 4,
          payloadBytes: 16384,
        ),
      );

      expect(rawPubSub, hasLength(8));
      expect(rawRpc, hasLength(8));
      expect(rawRpcCbor, hasLength(8));
      expect(webSocketPubSub, hasLength(8));
      expect(webSocketRpcMsgPack, hasLength(8));
      expect(webSocketRpc, hasLength(8));
      expect(rawRpcCborLarge, hasLength(32));
      expect(webSocketRpcCborLarge, hasLength(32));
    },
    skip: skipReason,
  );
}

String? _resolveNativeLib() {
  final envPath = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (envPath != null && File(envPath).existsSync()) {
    return envPath;
  }
  const candidates = [
    '../../native/transport/target/ffi-test/release/libct_ffi.so',
    '../../native/transport/target/release/libct_ffi.so',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}
