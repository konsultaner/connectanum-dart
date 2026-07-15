@TestOn('vm')
library;

import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_bench/connectanum_bench.dart';
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
      'Dart same-serializer CBOR E2EE RPC runs against a real router',
      () async {
        harness!.e2eeTrace.reset(strict: true);
        late final List<WampSample> samples;
        try {
          samples = await harness!.runDart(
            WampScenario(
              transport: WampTransport.rawsocket,
              clientImplementation: WampClientImplementation.dart,
              serializer: WampSerializer.cbor,
              peerSerializer: WampSerializer.cbor,
              mode: WampMode.rpc,
              uri: 'bench.rpc.echo',
              iterations: 1,
              concurrency: 1,
              payloadBytes: 1024,
              pptScheme: 'wamp',
              pptSerializer: 'cbor',
              pptCipher: 'aes256gcm',
              pptKeyId: 'benchmark-key',
            ),
          );
        } finally {
          harness!.e2eeTrace.strict = false;
        }

        expect(samples, hasLength(1));
        expect(harness!.e2eeTrace.pendingCiphertexts, isZero);
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'Dart progressive RPC workload runs against a real router',
      () async {
        final samples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.cbor,
            mode: WampMode.progressiveRpc,
            uri: 'bench.progressive',
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
      'native CBOR progressive RPC preserves all chunks against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.json,
            mode: WampMode.progressiveRpc,
            uri: 'bench.progressive.native',
            iterations: 1,
            concurrency: 1,
            inFlightPerSession: 1,
            payloadBytes: 32,
          ),
        );

        expect(samples, hasLength(1));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native timeout RPC workload runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.json,
            mode: WampMode.timeoutRpc,
            uri: 'bench.timeout',
            iterations: 2,
            concurrency: 1,
            payloadBytes: 0,
            callTimeoutMs: 40,
          ),
        );

        expect(samples, hasLength(2));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'Dart statistics Meta API workload runs against a real router',
      () async {
        final samples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.msgpack,
            mode: WampMode.metaApi,
            uri: 'bench.meta',
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
            const Duration(seconds: 60),
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

  group('BenchmarkRunner WAMP scenarios', () {
    test(
      'runs RawSocket RPC workload from YAML benchmark scenario',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'connectanum-benchmark-runner-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final rawSocketPort = await _reservePort();
        final routerConfig = File('${tempDir.path}/router.yaml');
        await routerConfig.writeAsString(
          _benchmarkRunnerRouterConfig(rawSocketPort),
        );
        final scenarioFile = File('${tempDir.path}/benchmarks.yaml');
        await scenarioFile.writeAsString(_benchmarkRunnerScenario());

        final records = <LogRecord>[];
        final previousRootLevel = Logger.root.level;
        Logger.root.level = Level.ALL;
        final subscription = Logger(
          'BenchmarkRunner',
        ).onRecord.listen(records.add);
        addTearDown(() async {
          await subscription.cancel();
          Logger.root.level = previousRootLevel;
        });

        await BenchmarkRunner(
          nativeLibraryPath: nativeLib!,
          routerConfigPath: routerConfig.path,
          config: BenchmarkConfig.fromYaml(await scenarioFile.readAsString()),
        ).run();

        expect(
          records.any((record) => record.message.contains('WAMP samples: 1')),
          isTrue,
        );
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );
  });
}

String _benchmarkRunnerRouterConfig(int rawSocketPort) =>
    '''
router:
  realms:
    - name: bench.control
      auth:
        authmethods: [anonymous]
      roles:
        - name: anonymous
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]
        - name: bench
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]

  listeners:
    - endpoint: 127.0.0.1:$rawSocketPort
      authmethods: [anonymous]
      protocols: [rawsocket]
      tls:
        mode: disabled
      rawsocket:
        max_rawsocket_size_exponent: 16

  worker_pool:
    min_workers: 1

  authenticators:
    anonymous:
      type: anonymous
''';

String _benchmarkRunnerScenario() => '''
benchmarks:
  - name: rawsocket_rpc_package_runner
    type: wamp_rawsocket_rpc
    duration: 1ms
    extra:
      serializer: json
      path: bench.rpc.echo
      iterations: 1
      request_bytes: 16
''';

class _WampTransportHarness {
  _WampTransportHarness._({
    required this.runtime,
    required this.binding,
    required this.internalSession,
    required this.protectedSession,
    required this.runner,
    required this.nativeWorker,
    required this.e2eeTrace,
  });

  final NativeTransportRuntime runtime;
  final RouterBinding binding;
  final RouterSession internalSession;
  final RouterSession protectedSession;
  final WampWorkloadRunner runner;
  final NativeWampWorker nativeWorker;
  final _E2eeTrace e2eeTrace;

  static Future<_WampTransportHarness> start(String nativeLib) async {
    final workerScriptPath = _resolveBenchTool('wamp_client_main.dart');
    final rawSocketPort = await _reservePort();
    final webSocketPort = await _reservePort();
    final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
    final e2eeTrace = _E2eeTrace();
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
        final e2eeProviderFactory = e2eeTrace.wrapFactory(
          e2eeProviderFactoryForScenario(scenario),
        );
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
              e2eeProviderFactory: e2eeProviderFactory,
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
              e2eeProviderFactory: e2eeProviderFactory,
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
      e2eeTrace: e2eeTrace,
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

final class _E2eeTrace {
  final Queue<Uint8List> _pendingCiphertexts = Queue<Uint8List>();
  var _nextProviderId = 0;
  bool strict = false;

  int get pendingCiphertexts => _pendingCiphertexts.length;

  void reset({required bool strict}) {
    _pendingCiphertexts.clear();
    _nextProviderId = 0;
    this.strict = strict;
  }

  WampE2eeProviderFactory? wrapFactory(WampE2eeProviderFactory? factory) {
    if (factory == null) {
      return null;
    }
    return () => _TracingE2eeProvider(
      delegate: factory(),
      providerId: _nextProviderId++,
      trace: this,
    );
  }

  void recordPack(int providerId, List<dynamic> arguments) {
    if (!strict) {
      return;
    }
    _pendingCiphertexts.add(_ciphertext(arguments, providerId, 'pack'));
  }

  void recordUnpack(int providerId, List<dynamic>? arguments) {
    if (!strict) {
      return;
    }
    final actual = _ciphertext(arguments, providerId, 'unpack');
    if (_pendingCiphertexts.isEmpty) {
      throw StateError(
        'E2EE provider $providerId unpacked without a prior pack',
      );
    }
    final expected = _pendingCiphertexts.removeFirst();
    if (_bytesEqual(expected, actual)) {
      return;
    }
    final comparedLength = expected.length < actual.length
        ? expected.length
        : actual.length;
    var firstDifference = comparedLength;
    for (var index = 0; index < comparedLength; index++) {
      if (expected[index] != actual[index]) {
        firstDifference = index;
        break;
      }
    }
    throw StateError(
      'E2EE ciphertext changed before provider $providerId unpack: '
      'expected_length=${expected.length} actual_length=${actual.length} '
      'first_difference=$firstDifference',
    );
  }

  Uint8List _ciphertext(
    List<dynamic>? arguments,
    int providerId,
    String operation,
  ) {
    if (arguments == null || arguments.length != 1) {
      throw StateError(
        'E2EE provider $providerId $operation received an invalid payload shape',
      );
    }
    final ciphertext = arguments.single;
    if (ciphertext is Uint8List) {
      return Uint8List.fromList(ciphertext);
    }
    if (ciphertext is List) {
      return Uint8List.fromList(ciphertext.cast<int>());
    }
    throw StateError(
      'E2EE provider $providerId $operation received '
      '${ciphertext.runtimeType} instead of bytes',
    );
  }

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

final class _TracingE2eeProvider extends wamp_core.DisposableWampE2eeProvider
    implements wamp_core.WampE2eeProfileSupport {
  _TracingE2eeProvider({
    required this.delegate,
    required this.providerId,
    required this.trace,
  });

  final wamp_core.WampE2eeProvider delegate;
  final int providerId;
  final _E2eeTrace trace;

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    wamp_core.PPTOptions options, {
    wamp_core.WampE2eeRuntimeContext? runtimeContext,
  }) {
    final packed = delegate.packPayload(
      arguments,
      argumentsKeywords,
      options,
      runtimeContext: runtimeContext,
    );
    trace.recordPack(providerId, packed);
    return packed;
  }

  @override
  wamp_core.E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    wamp_core.PPTOptions options, {
    wamp_core.WampE2eeRuntimeContext? runtimeContext,
  }) {
    trace.recordUnpack(providerId, arguments);
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
  }) {
    if (delegate is! wamp_core.WampE2eeProfileSupport) {
      return false;
    }
    return (delegate as wamp_core.WampE2eeProfileSupport).supportsE2eeProfile(
      version: version,
      scheme: scheme,
      serializer: serializer,
      cipher: cipher,
    );
  }

  @override
  void release() {
    final disposable = delegate;
    if (disposable is wamp_core.DisposableWampE2eeProvider) {
      disposable.release();
    }
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
