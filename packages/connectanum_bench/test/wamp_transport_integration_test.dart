@TestOn('vm')
library;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:connectanum_bench/src/native_wamp_worker.dart';
import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final nativeLib = _resolveNativeLib();
  final workerScriptPath = _resolveBenchTool('wamp_client_main.dart');
  final workerPackageDirectory = File(workerScriptPath).absolute.parent.parent;
  final skipReason = nativeLib == null
      ? 'Native transport library missing; build native transport first.'
      : null;

  group('live WAMP transport workloads', () {
    _WampTransportHarness? harness;

    setUpAll(() async {
      if (skipReason != null || nativeLib == null) {
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
      'ticket-authenticated WAMP workloads run against the secure realm',
      () async {
        final rpcSamples = await harness!.runNative(
          WampScenario(
            realmUri: 'bench.secure',
            authMethod: 'ticket',
            authId: 'bench-user',
            authSecret: 'bench-ticket',
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
          ),
        );
        final pubsubSamples = await harness!.runNative(
          WampScenario(
            realmUri: 'bench.secure',
            authMethod: 'ticket',
            authId: 'bench-user',
            authSecret: 'bench-ticket',
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 32,
          ),
        );

        expect(rpcSamples, hasLength(2));
        expect(pubsubSamples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'WAMP authenticate workloads measure session setup for anonymous and ticket clients',
      () async {
        final anonymousSamples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.json,
            mode: WampMode.authenticate,
            uri: 'bench.auth',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );
        final ticketSamples = await harness!.runNative(
          WampScenario(
            realmUri: 'bench.secure',
            authMethod: 'ticket',
            authId: 'bench-user',
            authSecret: 'bench-ticket',
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.msgpack,
            mode: WampMode.authenticate,
            uri: 'bench.auth',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );

        expect(anonymousSamples, hasLength(2));
        expect(ticketSamples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native publish-ack control workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.msgpack,
            mode: WampMode.publishAck,
            uri: 'bench.control.topic',
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
      'native subscribe-cycle control workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.subscribeCycle,
            uri: 'bench.control.topic',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native register-cycle control workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.json,
            mode: WampMode.registerCycle,
            uri: 'bench.control.proc',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native RawSocket JSON cancel-cycle control workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.json,
            mode: WampMode.cancelCycle,
            uri: 'bench.control.cancel',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native WebSocket MsgPack cancel-cycle control workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.msgpack,
            mode: WampMode.cancelCycle,
            uri: 'bench.control.cancel',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native RawSocket MsgPack cancel-cycle control workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.msgpack,
            mode: WampMode.cancelCycle,
            uri: 'bench.control.cancel',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native WAMP worker process exits cleanly after STOP following a native cancel workload',
      () async {
        final rawSocketListener = harness!.binding.listeners.firstWhere(
          (listener) =>
              listener.settings?.protocols.contains(
                ListenerProtocol.rawsocket,
              ) ??
              false,
        );
        final webSocketListener = harness!.binding.listeners.firstWhere(
          (listener) =>
              listener.settings?.protocols.contains(
                ListenerProtocol.websocket,
              ) ??
              false,
        );
        final process = await Process.start(
          Platform.resolvedExecutable,
          [
            workerScriptPath,
            '--realm',
            'bench.control',
            '--targets-json',
            jsonEncode({
              'rawsocket': WampTransportTarget(
                transport: WampTransport.rawsocket,
                host: '127.0.0.1',
                port: rawSocketListener.port,
                secure: false,
              ).toJson(),
              'websocket': WampTransportTarget(
                transport: WampTransport.websocket,
                host: '127.0.0.1',
                port: webSocketListener.port,
                secure: false,
                webSocketPath: '/wamp',
              ).toJson(),
            }),
            '--native-lib',
            nativeLib!,
          ],
          workingDirectory: workerPackageDirectory.path,
        );
        final stdoutLines = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();
        final stderrLines = <String>[];
        final stderrSub = process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(stderrLines.add);
        try {
          final ready = await stdoutLines.first.timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              fail(
                'native WAMP worker did not become ready; stderr:\n'
                '${stderrLines.join('\n')}',
              );
            },
          );
          expect(ready, 'READY');

          process.stdin.writeln(
            jsonEncode(
              WampScenario(
                transport: WampTransport.rawsocket,
                clientImplementation: WampClientImplementation.native,
                serializer: WampSerializer.json,
                mode: WampMode.cancelCycle,
                uri: 'bench.control.cancel',
                iterations: 1,
                concurrency: 1,
                payloadBytes: 0,
              ).toJson(),
            ),
          );
          await process.stdin.flush();

          final responseLine = await stdoutLines
              .firstWhere((line) => line != 'READY')
              .timeout(const Duration(seconds: 20));
          final response = jsonDecode(responseLine) as Map<String, Object?>;
          expect(response['error'], isNull, reason: stderrLines.join('\n'));
          expect(response['samples'], isA<List<Object?>>());

          process.stdin.writeln('STOP');
          await process.stdin.flush();
          await process.stdin.close();

          final exitCode = await process.exitCode.timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              fail('worker did not exit; stderr:\n${stderrLines.join('\n')}');
            },
          );
          expect(exitCode, 0, reason: stderrLines.join('\n'));
        } finally {
          await stderrSub.cancel();
          if (process.kill()) {
            await process.exitCode.timeout(
              const Duration(seconds: 5),
              onTimeout: () => -1,
            );
          }
        }
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 75)),
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
    required this.protectedSession,
    required this.runner,
    required this.nativeWorker,
  });

  final NativeTransportRuntime runtime;
  final RouterBinding binding;
  final RouterSession internalSession;
  final RouterSession protectedSession;
  final WampWorkloadRunner runner;
  final NativeWampWorker nativeWorker;

  static Future<_WampTransportHarness> start(String nativeLib) async {
    final workerScriptPath = _resolveBenchTool('wamp_client_main.dart');
    final rawSocketPort = await _reservePort();
    final webSocketPort = await _reservePort();
    final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
    final settings = RouterSettingsBuilder()
        .addRealmFromBuilder(
          RealmSettingsBuilder('bench.control')
            ..addAuthMethod('anonymous')
            ..addRole(const RoleSettings(name: 'anonymous', permissions: []))
            ..addRole(const RoleSettings(name: 'bench', permissions: [])),
        )
        .addRealmFromBuilder(
          RealmSettingsBuilder('bench.secure')
            ..addAuthMethod(
              'ticket',
              options: const {'authenticator': 'ticket-basic'},
            )
            ..addRoleFromBuilder(
              RoleSettingsBuilder('member')..addPermissionFromBuilder(
                PermissionSettingsBuilder('bench.')
                  ..setMatchPolicy(PermissionMatchPolicy.prefix)
                  ..allowOperations(const [
                    'register',
                    'unregister',
                    'subscribe',
                    'unsubscribe',
                    'publish',
                    'call',
                  ]),
              ),
            )
            ..addRoleFromBuilder(
              RoleSettingsBuilder('internal')..addPermissionFromBuilder(
                PermissionSettingsBuilder('bench.')
                  ..setMatchPolicy(PermissionMatchPolicy.prefix)
                  ..allowOperations(const [
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
            ..addAuthMethod('ticket')
            ..addProtocol(ListenerProtocol.rawsocket)
            ..setRawSocketOptions(
              const RawSocketListenerSettings(maxFrameExponent: 18),
            ),
        )
        .addListenerFromBuilder(
          ListenerSettingsBuilder('websocket-only', '127.0.0.1:$webSocketPort')
            ..addAuthMethod('anonymous')
            ..addAuthMethod('ticket')
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
        .addAuthenticator(
          'ticket-basic',
          const AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                'bench-user': {
                  'ticket': 'bench-ticket',
                  'role': 'member',
                  'provider': 'bench-ticket-store',
                },
              },
            },
          ),
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
    final protectedSession = await binding.createInternalSession(
      realmUri: 'bench.secure',
      authId: 'bench-secure',
      authRole: 'internal',
    );
    for (final session in [internalSession, protectedSession]) {
      final registration = await session.register('bench.rpc.echo');
      registration.onInvoke((invocation) async {
        invocation.respondWith(
          arguments: invocation.arguments,
          argumentsKeywords: invocation.argumentsKeywords,
        );
      });
    }

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
              realmUri: scenario.realmUri,
              authId: scenario.authId,
              authenticationMethods: authenticationMethodsForScenario(scenario),
              serializer: scenario.serializer,
              clientImplementation: scenario.clientImplementation,
              nativeLibraryPath: nativeLib,
            ).call();
          case WampTransport.websocket:
            return WebSocketWampSessionFactory(
              url: 'ws://127.0.0.1:${webSocketListener.port}/wamp',
              realmUri: scenario.realmUri,
              authId: scenario.authId,
              authenticationMethods: authenticationMethodsForScenario(scenario),
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
      workerScriptPath: workerScriptPath,
      logger: Logger.detached('native_wamp_worker_test'),
    );

    return _WampTransportHarness._(
      runtime: runtime,
      binding: binding,
      internalSession: internalSession,
      protectedSession: protectedSession,
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
    await protectedSession.close();
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
  final fileName = switch (Platform.operatingSystem) {
    'macos' => 'libct_ffi.dylib',
    'linux' => 'libct_ffi.so',
    'windows' => 'ct_ffi.dll',
    _ => null,
  };
  if (fileName == null) {
    return null;
  }
  final candidates = [
    '../../native/transport/target/ffi-test/release/$fileName',
    '../../native/transport/target/release/$fileName',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}

String _resolveBenchTool(String fileName) {
  final candidates = [
    File('tool/$fileName'),
    File('packages/connectanum_bench/tool/$fileName'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  throw StateError(
    'Failed to locate bench tool $fileName from ${Directory.current.path}.',
  );
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}
