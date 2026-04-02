@TestOn('vm')
library;

import 'dart:io';
import 'dart:async';

import 'package:connectanum_bench/src/native_wamp_worker.dart';
import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport first.'
      : null;

  group('live WAMP transport workloads', () {
    _WampTransportHarness? harness;

    setUpAll(() async {
      if (nativeLib == null) {
        return;
      }
      harness = await _WampTransportHarness.start(nativeLib);
    });

    tearDownAll(() async {
      await harness?.close();
    });

    test('Dart RawSocket RPC workload runs against a real router', () async {
      final samples = await harness!.runDart(
        WampScenario(
          transport: WampTransport.rawsocket,
          clientImplementation: WampClientImplementation.dart,
          serializer: WampSerializer.json,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 2,
          concurrency: 1,
          payloadBytes: 32,
        ),
      );

      expect(samples, hasLength(2));
    }, skip: skipReason);

    test(
      'Dart WebSocket pubsub workload runs against a real router',
      () async {
        final samples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
    );

    test(
      'Dart RawSocket PPT pubsub workload runs against a real router',
      () async {
        final samples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native RawSocket RPC workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.json,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native WebSocket RPC workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.json,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native RawSocket PPT pubsub workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'Dart mixed-serializer RawSocket and WebSocket workloads run against a real router',
      () async {
        final rawSocketRpcSamples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.json,
            peerSerializer: WampSerializer.msgpack,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 256,
          ),
        );
        final webSocketPubSubSamples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.json,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 256,
          ),
        );

        expect(rawSocketRpcSamples, hasLength(2));
        expect(webSocketPubSubSamples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native mixed-serializer RawSocket and WebSocket workloads run against a real router',
      () async {
        final rawSocketRpcSamples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.json,
            peerSerializer: WampSerializer.msgpack,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 256,
          ),
        );
        final webSocketPubSubSamples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.json,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 256,
          ),
        );

        expect(rawSocketRpcSamples, hasLength(2));
        expect(webSocketPubSubSamples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'Dart RawSocket PPT pubsub exposes unpacked kwargs on a real router',
      () async {
        final port = harness!.binding.listeners
            .firstWhere(
              (listener) =>
                  listener.settings?.protocols.contains(
                    ListenerProtocol.rawsocket,
                  ) ??
                  false,
            )
            .port;
        final subscriber = await RawSocketWampSessionFactory(
          host: '127.0.0.1',
          port: port,
          realmUri: 'bench.control',
          serializer: WampSerializer.cbor,
          clientImplementation: WampClientImplementation.dart,
          nativeLibraryPath: nativeLib!,
        ).call();
        final publisher = await RawSocketWampSessionFactory(
          host: '127.0.0.1',
          port: port,
          realmUri: 'bench.control',
          serializer: WampSerializer.cbor,
          clientImplementation: WampClientImplementation.dart,
          nativeLibraryPath: nativeLib,
        ).call();
        final eventCompleter = Completer<dynamic>();
        final subscription = await subscriber.subscribeLazyPayload(
          'bench.topic',
        );
        subscription.onEvent((event) {
          if (!eventCompleter.isCompleted) {
            eventCompleter.complete(event);
          }
        });

        try {
          await publisher.publish(
            'bench.topic',
            arguments: const ['ppt-event'],
            argumentsKeywords: const {'worker': 7, 'iteration': 1},
            options: wamp_core.PublishOptions(
              acknowledge: true,
              pptScheme: 'x_custom_scheme',
              pptSerializer: 'cbor',
            ),
          );
          final event = await eventCompleter.future.timeout(
            const Duration(seconds: 5),
          );
          expect(event.arguments, equals(const ['ppt-event']));
          expect(
            event.argumentsKeywords,
            equals(const {'worker': 7, 'iteration': 1}),
          );
        } finally {
          await subscription.cancel();
          await subscriber.close();
          await publisher.close();
        }
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'Dart large-payload CBOR RPC workloads cover RawSocket and WebSocket',
      () async {
        final rawSocketSamples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 4,
            concurrency: 2,
            inFlightPerSession: 2,
            payloadBytes: 16384,
          ),
        );
        final webSocketSamples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 4,
            concurrency: 2,
            inFlightPerSession: 2,
            payloadBytes: 16384,
          ),
        );

        expect(rawSocketSamples, hasLength(8));
        expect(webSocketSamples, hasLength(8));
      },
      skip: skipReason,
    );

    test(
      'native large-payload CBOR RPC workloads cover RawSocket and WebSocket',
      () async {
        final rawSocketSamples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 4,
            concurrency: 2,
            inFlightPerSession: 2,
            payloadBytes: 16384,
          ),
        );
        final webSocketSamples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 4,
            concurrency: 2,
            inFlightPerSession: 2,
            payloadBytes: 16384,
          ),
        );

        expect(rawSocketSamples, hasLength(8));
        expect(webSocketSamples, hasLength(8));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );
  });
}

class _WampTransportHarness {
  _WampTransportHarness._({
    required this.runtime,
    required this.binding,
    required this.internalSession,
    required this.runner,
    required this.nativeWorker,
  });

  final NativeTransportRuntime runtime;
  final RouterBinding binding;
  final RouterSession internalSession;
  final WampWorkloadRunner runner;
  final NativeWampWorker nativeWorker;

  static Future<_WampTransportHarness> start(String nativeLib) async {
    final rawSocketPort = await _reservePort();
    final webSocketPort = await _reservePort();
    final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
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
          ListenerSettingsBuilder('rawsocket-only', '127.0.0.1:$rawSocketPort')
            ..addAuthMethod('anonymous')
            ..addProtocol(ListenerProtocol.rawsocket)
            ..setRawSocketOptions(
              const RawSocketListenerSettings(maxFrameExponent: 18),
            ),
        )
        .addListenerFromBuilder(
          ListenerSettingsBuilder('websocket-only', '127.0.0.1:$webSocketPort')
            ..addAuthMethod('anonymous')
            ..addProtocol(ListenerProtocol.websocket)
            ..setPath('/wamp')
            ..setWebSocketOptions(
              const WebSocketListenerSettings(
                path: '/wamp',
                subprotocols: ['wamp.2.json', 'wamp.2.msgpack', 'wamp.2.cbor'],
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
          port: rawSocketPort,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 18,
        ),
        Endpoint(
          host: '127.0.0.1',
          port: webSocketPort,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 18,
          webSocketPath: '/wamp',
        ),
      ],
    );

    final binding = Router(config, settings: settings).start(runtime);
    final internalSession = await binding.createInternalSession(
      realmUri: 'bench.control',
      authId: 'bench-control',
      authRole: 'bench',
    );
    final registration = await internalSession.register('bench.rpc.echo');
    registration.onInvoke((invocation) async {
      invocation.respondWith(
        arguments: invocation.arguments,
        argumentsKeywords: invocation.argumentsKeywords,
      );
    });

    final rawSocketListener = binding.listeners.firstWhere(
      (listener) =>
          listener.settings?.protocols.contains(ListenerProtocol.rawsocket) ??
          false,
    );
    final webSocketListener = binding.listeners.firstWhere(
      (listener) =>
          listener.settings?.protocols.contains(ListenerProtocol.websocket) ??
          false,
    );

    final runner = WampWorkloadRunner(
      sessionFactory: (scenario) {
        switch (scenario.transport) {
          case WampTransport.rawsocket:
            return RawSocketWampSessionFactory(
              host: '127.0.0.1',
              port: rawSocketListener.port,
              realmUri: 'bench.control',
              serializer: scenario.serializer,
              clientImplementation: scenario.clientImplementation,
              nativeLibraryPath: nativeLib,
            ).call();
          case WampTransport.websocket:
            return WebSocketWampSessionFactory(
              url: 'ws://127.0.0.1:${webSocketListener.port}/wamp',
              realmUri: 'bench.control',
              serializer: scenario.serializer,
              clientImplementation: scenario.clientImplementation,
              headers: const {'x-connectanum-bench': '1'},
              nativeLibraryPath: nativeLib,
            ).call();
        }
      },
      logger: Logger.detached('wamp_transport_integration'),
      eventTimeout: const Duration(seconds: 5),
    );

    final nativeWorker = NativeWampWorker(
      realmUri: 'bench.control',
      wampTargets: {
        WampTransport.rawsocket: WampTransportTarget(
          transport: WampTransport.rawsocket,
          host: '127.0.0.1',
          port: rawSocketListener.port,
          secure: false,
        ),
        WampTransport.websocket: WampTransportTarget(
          transport: WampTransport.websocket,
          host: '127.0.0.1',
          port: webSocketListener.port,
          secure: false,
          webSocketPath: '/wamp',
        ),
      },
      nativeLibraryPath: nativeLib,
      workerScriptPath: File('tool/wamp_client_main.dart').absolute.path,
      logger: Logger.detached('native_wamp_worker_test'),
    );

    return _WampTransportHarness._(
      runtime: runtime,
      binding: binding,
      internalSession: internalSession,
      runner: runner,
      nativeWorker: nativeWorker,
    );
  }

  Future<List<WampSample>> runDart(WampScenario scenario) =>
      runner.run(scenario);

  Future<List<WampSample>> runNative(WampScenario scenario) =>
      nativeWorker.run(scenario);

  Future<void> close() async {
    await nativeWorker.close();
    await internalSession.close();
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
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

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}
