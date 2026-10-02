@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final chunks in [1, 2, 3, 4]) {
    test(
      'progressive handler validates exactly three chunks ($chunks)',
      () async {
        final session = _ChunkSession(chunks);
        final result = WampWorkloadRunner(sessionFactory: (_) async => session)
            .run(
              WampScenario(
                transport: WampTransport.rawsocket,
                serializer: WampSerializer.json,
                mode: WampMode.progressiveRpc,
                uri: 'bench.chunks',
                iterations: 1,
                concurrency: 1,
                payloadBytes: 4,
              ),
            );
        if (chunks == 3) {
          expect(await result, hasLength(1));
          expect(session.rejections, isEmpty);
          expect(
            session.responses,
            2,
          ); // warmup plus measured call, same request ID
        } else {
          await expectLater(
            result,
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'malformed progressive invocation',
                contains('expected 3 progressive chunks, got $chunks'),
              ),
            ),
          );
          expect(session.rejections, [core.Error.invalidArgument]);
          expect(session.responses, 1);
        }
        expect(session.closeCount, 2);
        expect(session.registrationCancelCount, 1);
      },
    );
  }
  for (final outcome in ['success', 'wrong error', 'early timeout']) {
    test(
      'timeout workload rejects $outcome and cleans up both sessions',
      () async {
        final error = outcome == 'success'
            ? null
            : core.Error(
                core.MessageTypes.codeCall,
                1,
                const {},
                outcome == 'early timeout'
                    ? core.Error.timeout
                    : 'wamp.error.not_authorized',
              );
        final session = _Session(callError: error);
        final runner = WampWorkloadRunner(sessionFactory: (_) async => session);
        final result = runner.run(
          WampScenario(
            transport: WampTransport.rawsocket,
            serializer: WampSerializer.json,
            concurrency: 1,
            payloadBytes: 4,
            mode: WampMode.timeoutRpc,
            uri: 'bench.timeout',
            iterations: 1,
            callTimeoutMs: 60000,
          ),
        );
        final matcher = outcome == 'wrong error'
            ? same(error)
            : isA<StateError>().having(
                (e) => e.message,
                'specific rejection',
                contains(
                  outcome == 'success'
                      ? 'completed without'
                      : 'fired too early',
                ),
              );
        await expectLater(result, throwsA(matcher));
        expect(session.callTimeouts, [60000]);
        expect(session.closeCount, 2);
        expect(session.registrationCancelCount, 1);
      },
    );
  }
  for (final missing in ['session', 'registration', 'subscription', 'all']) {
    test(
      'meta workload rejects missing $missing identifiers and releases entities',
      () async {
        final session = _Session(
          id: missing == 'session' || missing == 'all' ? null : 11,
          registrationId: missing == 'registration' || missing == 'all'
              ? null
              : 22,
          subscriptionId: missing == 'subscription' || missing == 'all'
              ? null
              : 33,
        );
        await expectLater(
          WampWorkloadRunner(sessionFactory: (_) async => session).run(
            WampScenario(
              transport: WampTransport.rawsocket,
              serializer: WampSerializer.json,
              concurrency: 1,
              payloadBytes: 4,
              mode: WampMode.metaApi,
              uri: 'bench.meta',
              iterations: 1,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'identifier validation',
              'Meta API workload requires live entity identifiers',
            ),
          ),
        );
        expect(session.callTimeouts, isEmpty);
        expect(session.closeCount, 1);
        expect(session.registrationCancelCount, 1);
        expect(session.subscriptionCancelCount, 1);
      },
    );
  }
  test(
    'progressive WAMP rejection retains diagnostics and cleans up',
    () async {
      final error = core.Error(
        core.MessageTypes.codeCall,
        1,
        const {},
        'wamp.error.invalid_argument',
        arguments: ['bad chunks'],
        argumentsKeywords: {'count': 2},
      );
      final session = _Session(progressiveResults: Stream.error(error));
      await expectLater(
        WampWorkloadRunner(sessionFactory: (_) async => session).run(
          WampScenario(
            transport: WampTransport.rawsocket,
            serializer: WampSerializer.json,
            concurrency: 1,
            payloadBytes: 4,
            mode: WampMode.progressiveRpc,
            uri: 'bench.progressive',
            iterations: 1,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'WAMP diagnostics',
            allOf(
              contains('wamp.error.invalid_argument'),
              contains('bad chunks'),
              contains('count: 2'),
            ),
          ),
        ),
      );
      expect(session.progressiveChunks, [
        ['ABCD'],
        ['ABCD'],
      ]);
      expect(session.closeCount, 2);
      expect(session.registrationCancelCount, 1);
    },
  );
  test(
    'progressive missing reply uses typed timeout and releases registrations',
    () async {
      final controller = StreamController<core.Result>();
      addTearDown(controller.close);
      final session = _Session(progressiveResults: controller.stream);
      await expectLater(
        WampWorkloadRunner(
          sessionFactory: (_) async => session,
          eventTimeout: const Duration(milliseconds: 20),
        ).run(
          WampScenario(
            transport: WampTransport.rawsocket,
            serializer: WampSerializer.json,
            concurrency: 1,
            payloadBytes: 4,
            mode: WampMode.progressiveRpc,
            uri: 'bench.progressive',
            iterations: 1,
          ),
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'deadline',
            'progressive_rpc_timeout',
          ),
        ),
      );
      expect(session.closeCount, 2);
      expect(session.registrationCancelCount, 1);
    },
  );
}

class _Session implements WampSession {
  @override
  final int? id;
  final int? registrationId;
  final int? subscriptionId;
  final Object? callError;
  final Stream<core.Result> progressiveResults;
  int closeCount = 0;
  int registrationCancelCount = 0;
  int subscriptionCancelCount = 0;
  final callTimeouts = <int?>[];
  final progressiveChunks = <List<dynamic>?>[];
  _Session({
    this.id = 11,
    this.registrationId = 22,
    this.subscriptionId = 33,
    this.callError,
    this.progressiveResults = const Stream.empty(),
  });

  @override
  Future<dynamic> get onDisconnect => Completer<void>().future;
  @override
  Future<void> close() async {
    closeCount++;
  }

  @override
  Future<WampRegistration> registerLazyPayloadHandler(
    String procedure,
    FutureOr<void> Function(core.LazyInvocationPayload) onInvoke, {
    core.RegisterOptions? options,
  }) async => WampRegistration(
    id: registrationId,
    cancel: () async {
      registrationCancelCount++;
    },
  );
  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    core.SubscribeOptions? options,
  }) async => WampSubscription(
    id: subscriptionId,
    cancel: () async {
      subscriptionCancelCount++;
    },
  );
  @override
  Future<core.ResultPayload> callSinglePayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    core.CallOptions? options,
  }) async {
    callTimeouts.add(options?.timeout);
    if (callError != null) throw callError!;
    return (
      callRequestId: 1,
      progress: false,
      pptScheme: null,
      pptSerializer: null,
      pptCipher: null,
      pptKeyId: null,
      customDetails: null,
      arguments: null,
      argumentsKeywords: null,
    );
  }

  @override
  WampProgressiveCall startProgressiveCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    core.CallOptions? options,
  }) => WampProgressiveCall(
    results: progressiveResults,
    sendChunk: ({arguments}) {
      progressiveChunks.add(arguments);
    },
    finish: ({arguments}) {
      progressiveChunks.add(arguments);
    },
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChunkSession extends _Session {
  _ChunkSession(this.chunks);
  final int chunks;
  late FutureOr<void> Function(core.LazyInvocationPayload) handler;
  int responses = 0;
  final rejections = <String?>[];

  @override
  Future<WampRegistration> registerLazyPayloadHandler(
    String procedure,
    FutureOr<void> Function(core.LazyInvocationPayload) onInvoke, {
    core.RegisterOptions? options,
  }) {
    handler = onInvoke;
    return super.registerLazyPayloadHandler(
      procedure,
      onInvoke,
      options: options,
    );
  }

  @override
  WampProgressiveCall startProgressiveCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    core.CallOptions? options,
  }) {
    final controller = StreamController<core.Result>();
    var closed = false;
    return WampProgressiveCall(
      results: controller.stream,
      sendChunk: ({arguments}) {},
      finish: ({arguments}) {
        for (var index = 0; index < chunks; index++) {
          handler(
            core.LazyInvocationPayload(
              requestId: 10,
              registrationId: 22,
              progress: index < chunks - 1,
              receiveProgress: false,
              payload: core.LazyMessagePayload.materialized(
                arguments: arguments,
              ),
              isResponseClosed: () => closed,
              respondWith:
                  ({
                    core.LazyMessagePayload? lazyPayload,
                    List<dynamic>? arguments,
                    Map<String, dynamic>? argumentsKeywords,
                    bool isError = false,
                    String? errorUri,
                    core.YieldOptions? options,
                  }) {
                    closed = true;
                    responses++;
                    if (isError) {
                      rejections.add(errorUri);
                      controller.addError(
                        core.Error(
                          core.MessageTypes.codeCall,
                          10,
                          const {},
                          errorUri!,
                          arguments: arguments,
                          argumentsKeywords: argumentsKeywords,
                        ),
                      );
                    } else {
                      controller.add(
                        core.Result(
                          10,
                          core.ResultDetails(),
                          arguments: lazyPayload?.arguments ?? arguments,
                        ),
                      );
                    }
                    unawaited(controller.close());
                  },
            ),
          );
        }
      },
    );
  }
}
