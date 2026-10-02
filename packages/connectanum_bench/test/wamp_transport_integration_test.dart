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
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/src/transport/native/e2ee_file_segment.dart'
    as native_e2ee;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'support/native_reply_callee.dart';

void main() {
  final nativeLib = _resolveNativeLib();
  final workerScriptPath = _resolveBenchTool('wamp_client_main.dart');
  final workerPackageDirectory = File(workerScriptPath).absolute.parent.parent;
  final skipReason = nativeLib == null
      ? 'Native transport library missing; build native transport first.'
      : null;

  test('listener reservation keeps WAMP ports distinct', () async {
    final ports = await _reserveDistinctWampPorts();
    expect(ports.rawSocketPort, isNot(ports.webSocketPort));
  });

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

    for (final webSocket in [false, true]) {
      for (final wireSerializer in ['json', 'msgpack', 'cbor']) {
        test(
          'native lazy replies ${webSocket ? 'WebSocket' : 'RawSocket'} '
          '$wireSerializer preserve PPT and encrypted payloads',
          () async {
            final binding = harness!.binding;
            final rawPort = binding.listeners
                .firstWhere(
                  (listener) =>
                      listener.settings?.protocols.contains(
                        ListenerProtocol.rawsocket,
                      ) ??
                      false,
                )
                .port;
            final webPort = binding.listeners
                .firstWhere(
                  (listener) =>
                      listener.settings?.protocols.contains(
                        ListenerProtocol.websocket,
                      ) ??
                      false,
                )
                .port;
            final webUrl = 'ws://127.0.0.1:$webPort/wamp';
            final callee = await NativeReplyCallee.start(
              webSocket: webSocket,
              wireSerializer: wireSerializer,
              rawPort: rawPort,
              webUrl: webUrl,
              nativeLib: nativeLib!,
            );
            addTearDown(() async {
              await callee.close();
            });
            final caller = client.Client(
              realm: 'bench.secure',
              authId: 'bench-user',
              authenticationMethods: [
                client.TicketAuthentication('bench-ticket'),
              ],
              transport: client.WebSocketTransport.withJsonSerializer(webUrl),
              e2eeProvider: client.WampCborXsalsa20Poly1305Provider.single(
                keyId: 'native-reply',
                key: Uint8List.fromList(
                  List.generate(32, (index) => index + 1),
                ),
              ),
            );
            addTearDown(caller.disconnect);
            final callerSession = await caller.connect().first.timeout(
              const Duration(seconds: 10),
            );
            var expectedReplies = 0;
            for (final shape in ['explicit', 'materialized', 'encoded']) {
              for (final mode in ['json', 'msgpack', 'cbor', 'wamp']) {
                final result = await callerSession
                    .callSingle(
                      'bench.rpc.native_lazy',
                      arguments: [shape, mode],
                    )
                    .timeout(const Duration(seconds: 10));
                expectedReplies++;
                expect(result.arguments, ['reply', expectedReplies]);
                expect(result.argumentsKeywords, {'shape': shape});
              }
            }
            expect(await callee.close(), 12);
          },
          skip: skipReason,
        );
      }
    }

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
      'native same-serializer CBOR E2EE RPC uses the selected FFI library',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
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

        expect(samples, hasLength(1));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native mixed-serializer XSalsa E2EE pubsub runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.msgpack,
            peerSerializer: WampSerializer.json,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 1,
            concurrency: 1,
            payloadBytes: 1024,
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
            pptCipher: 'xsalsa20poly1305',
            pptKeyId: 'benchmark-key',
          ),
        );

        expect(samples, hasLength(1));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native mixed-serializer AES-GCM E2EE pubsub runs against a real router',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.websocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.json,
            mode: WampMode.pubsub,
            uri: 'bench.topic',
            iterations: 1,
            concurrency: 1,
            payloadBytes: 1024,
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
            pptCipher: 'aes256gcm',
            pptKeyId: 'benchmark-key',
          ),
        );

        expect(samples, hasLength(1));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'native CBOR E2EE file transfer uses native file segments',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.cbor,
            mode: WampMode.fileTransfer,
            uri: 'bench.file.receive',
            iterations: 1,
            concurrency: 1,
            payloadBytes: 2 * 1024 * 1024,
            fileChunkBytes: 256 * 1024,
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
            pptCipher: 'aes256gcm',
            pptKeyId: 'benchmark-key',
          ),
        );

        expect(samples, hasLength(1));
        expect(samples.single.requestBytes, 2 * 1024 * 1024);
      },
      skip: skipReason,
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'Dart CBOR file transfer uses native progressive invocation forwarding',
      () async {
        final samples = await harness!.runDart(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.dart,
            serializer: WampSerializer.cbor,
            peerSerializer: WampSerializer.cbor,
            mode: WampMode.fileTransfer,
            uri: 'bench.file.native_progressive',
            iterations: 1,
            concurrency: 1,
            payloadBytes: 2 * 1024 * 1024,
            fileChunkBytes: 256 * 1024,
          ),
        );

        expect(samples, hasLength(1));
        expect(samples.single.requestBytes, 2 * 1024 * 1024);
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
      'native CBOR RPC opens concurrent standard peers on an extended endpoint',
      () async {
        final samples = await harness!.runNative(
          WampScenario(
            transport: WampTransport.rawsocket,
            clientImplementation: WampClientImplementation.native,
            serializer: WampSerializer.cbor,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 2,
            concurrency: 6,
            inFlightPerSession: 2,
            payloadBytes: 64 * 1024,
          ),
        );

        expect(samples, hasLength(12));
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

  benchmarkRunnerRegressionTests();
}

void benchmarkRunnerRegressionTests() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'Native transport library missing; build native transport first.'
      : null;
  group('BenchmarkRunner WAMP scenarios', () {
    test(
      'runner defaults execute load without rebuilding the native library',
      () {
        final runner = BenchmarkRunner(
          nativeLibraryPath: 'unused',
          routerConfigPath: 'unused',
          config: BenchmarkConfig(scenarios: []),
        );
        expect(runner.buildNative, isFalse);
        expect(runner.dryRun, isFalse);
      },
    );
    test('CLI defaults require explicit router and native library paths', () {
      for (final arguments in [
        <String>[],
        ['-c', 'router.yaml'],
        ['-n', 'native.so'],
      ]) {
        final options = buildArgParser().parse(arguments);
        if (!arguments.contains('-c')) {
          expect(() => options['config'], throwsArgumentError);
        }
        if (!arguments.contains('-n')) {
          expect(() => options['native-lib'], throwsArgumentError);
        }
      }
      final options = buildArgParser().parse([
        '-c',
        'router.yaml',
        '-n',
        'native.so',
      ]);
      expect(options['config'], 'router.yaml');
      expect(options['native-lib'], 'native.so');
      expect(options['scenario'], 'benchmarks.yaml');
      expect(options['help'], isFalse);
      expect(options['build-native'], isFalse);
      expect(options['dry-run'], isFalse);
    });
    for (final enabled in [false, true]) {
      test('CLI flags can explicitly select enabled=$enabled', () {
        final options = buildArgParser().parse([
          '-c',
          'custom.yaml',
          '-n',
          'custom.so',
          '-s',
          'custom-bench.yaml',
          '-h',
          enabled ? '--build-native' : '--no-build-native',
          enabled ? '--dry-run' : '--no-dry-run',
        ]);
        expect(options['config'], 'custom.yaml');
        expect(options['native-lib'], 'custom.so');
        expect(options['scenario'], 'custom-bench.yaml');
        expect(options['help'], isTrue);
        expect(options['build-native'], enabled);
        expect(options['dry-run'], enabled);
        expect(
          () => buildArgParser().parse(['--no-help']),
          throwsFormatException,
        );
      });
    }
    for (final transport in WampTransport.values) {
      for (final serializer in WampSerializer.values) {
        for (final dryRun in [false, true]) {
          test(
            'runs ${transport.name}/${serializer.name} RPC from YAML dryRun=$dryRun with exact accounting',
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
                _benchmarkRunnerRouterConfig(
                  rawSocketPort,
                  transport: transport,
                ),
              );
              final scenarioFile = File('${tempDir.path}/benchmarks.yaml');
              await scenarioFile.writeAsString(
                _benchmarkRunnerScenario(
                  transport: transport,
                  serializer: serializer,
                ),
              );

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

              await expectLater(
                BenchmarkRunner(
                  nativeLibraryPath: nativeLib!,
                  routerConfigPath: routerConfig.path,
                  dryRun: dryRun,
                  config: BenchmarkConfig.fromYaml(
                    await scenarioFile.readAsString(),
                  ),
                ).run(),
                completes,
              );

              final messages = records.map((record) => record.message).toList();
              expect(
                messages.where(
                  (message) => message.startsWith(' WAMP samples:'),
                ),
                dryRun ? isEmpty : [' WAMP samples: 6'],
              );
              expect(
                messages.where(
                  (message) => message.startsWith(' WAMP request bytes:'),
                ),
                dryRun ? isEmpty : [' WAMP request bytes: 102'],
              );
              expect(
                messages.where(
                  (message) => message.startsWith(' WAMP response bytes:'),
                ),
                dryRun ? isEmpty : [' WAMP response bytes: 102'],
              );
              expect(messages, contains(' Pending invocations: 0'));
              expect(
                messages,
                contains(' Total invocations dispatched: ${dryRun ? 0 : 6}'),
              );
              expect(
                records.where((record) => record.level >= Level.WARNING),
                isEmpty,
              );
            },
            skip: skipReason,
            timeout: const Timeout(Duration(seconds: 45)),
          );
        }
      }
    }
    for (final dryRun in [false, true]) {
      test(
        'non-WAMP scenario dryRun=$dryRun does not claim generated load',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'connectanum-runner-no-load-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final configFile = File('${directory.path}/router.yaml');
          await configFile.writeAsString(
            _benchmarkRunnerRouterConfig(await _reservePort()),
          );
          final previousRootLevel = Logger.root.level;
          Logger.root.level = Level.ALL;
          final records = <LogRecord>[];
          final subscription = Logger(
            'BenchmarkRunner',
          ).onRecord.listen(records.add);
          addTearDown(() async {
            await subscription.cancel();
            Logger.root.level = previousRootLevel;
          });
          await expectLater(
            BenchmarkRunner(
              nativeLibraryPath: nativeLib!,
              routerConfigPath: configFile.path,
              config: BenchmarkConfig.fromYaml('''
benchmarks:
  - name: no_load
    type: http
    warmup: 1ms
    duration: 1ms
'''),
              dryRun: dryRun,
            ).run(),
            completes,
          );
          final messages = records.map((record) => record.message).toList();
          expect(messages, contains('Scenario "no_load" complete.'));
          expect(messages, contains(' Warm-up for 0s'));
          expect(messages, contains(' Total invocations dispatched: 0'));
          expect(messages, contains(' Total publications routed: 0'));
          expect(
            messages.where((message) => message.startsWith(' WAMP ')),
            isEmpty,
          );
          expect(
            records
                .where((record) => record.level == Level.WARNING)
                .map((record) => record.message),
            dryRun
                ? isEmpty
                : [
                    ' No load generators are configured yet. Sleeping for scenario duration.',
                  ],
          );
        },
        skip: skipReason,
      );
    }
  });
}

String _benchmarkRunnerRouterConfig(
  int rawSocketPort, {
  WampTransport transport = WampTransport.rawsocket,
}) =>
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
      protocols: [${transport.name}]
      tls:
        mode: disabled
      rawsocket:
        max_rawsocket_size_exponent: 16
      websocket:
        path: /wamp
        subprotocols: [wamp.2.json, wamp.2.msgpack, wamp.2.cbor]

  worker_pool:
    min_workers: 1

  authenticators:
    anonymous:
      type: anonymous
''';

String _benchmarkRunnerScenario({
  required WampTransport transport,
  required WampSerializer serializer,
}) =>
    '''
benchmarks:
  - name: rpc_package_runner
    type: benchmark_fixture
    duration: 1ms
    concurrency: 2
    extra:
      protocol: WAMP_${transport.name.toUpperCase()}_RPC
      serializer: ${serializer.name}
      path: bench.rpc.echo
      iterations: 3
      request_bytes: 17
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
    final (:rawSocketPort, :webSocketPort) = await _reserveDistinctWampPorts();
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
              const RawSocketListenerSettings(maxFrameExponent: 30),
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
          maxRawSocketSizeExponent: 30,
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
          e2eeProviderFactoryForScenario(
            scenario,
            nativeLibraryPath: nativeLib,
          ),
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
    implements
        wamp_core.WampE2eeProfileSupport,
        native_e2ee.NativeE2eeFileSegmentProvider {
  _TracingE2eeProvider({
    required this.delegate,
    required this.providerId,
    required this.trace,
  });

  final wamp_core.WampE2eeProvider delegate;
  final int providerId;
  final _E2eeTrace trace;

  @override
  bool get supportsNativeE2eeFileSegments {
    final nativeDelegate = delegate as Object;
    return nativeDelegate is native_e2ee.NativeE2eeFileSegmentProvider &&
        nativeDelegate.supportsNativeE2eeFileSegments;
  }

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
  native_e2ee.NativeE2eeFileSegmentContext prepareNativeE2eeFileSegment(
    wamp_core.PPTOptions options, {
    wamp_core.WampE2eeRuntimeContext? runtimeContext,
  }) {
    final nativeDelegate = delegate as Object;
    if (nativeDelegate is! native_e2ee.NativeE2eeFileSegmentProvider ||
        !nativeDelegate.supportsNativeE2eeFileSegments) {
      throw UnsupportedError('The traced E2EE provider is not native');
    }
    return nativeDelegate.prepareNativeE2eeFileSegment(
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

Future<({int rawSocketPort, int webSocketPort})>
_reserveDistinctWampPorts() async {
  final rawSocket = await ServerSocket.bind('127.0.0.1', 0);
  try {
    final webSocket = await ServerSocket.bind('127.0.0.1', 0);
    try {
      return (
        rawSocketPort: rawSocket.port,
        webSocketPort: webSocket.port,
      );
    } finally {
      await webSocket.close();
    }
  } finally {
    await rawSocket.close();
  }
}
