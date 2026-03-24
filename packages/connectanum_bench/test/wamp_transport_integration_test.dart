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

      const iterations = 4;
      const concurrency = 2;
      final scenarios = <WampScenario>[
        for (final transport in WampTransport.values)
          for (final mode in WampMode.values)
            for (final serializer in WampSerializer.values)
              WampScenario(
                transport: transport,
                serializer: serializer,
                mode: mode,
                uri: mode == WampMode.pubsub ? 'bench.topic' : 'bench.rpc.echo',
                iterations: iterations,
                concurrency: concurrency,
                payloadBytes: 32,
              ),
      ];
      for (final scenario in scenarios) {
        final samples = await runner.run(scenario);
        expect(
          samples,
          hasLength(iterations * concurrency),
          reason:
              '${scenario.transport.name}/${scenario.mode.name}/${scenario.serializer.name}',
        );
      }

      final rawRpcCborLarge = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 8,
          concurrency: 4,
          inFlightPerSession: 2,
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
          inFlightPerSession: 2,
          payloadBytes: 16384,
        ),
      );

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
