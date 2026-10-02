@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final (mode, payloadBytes) in [
    (WampMode.authenticate, 0),
    (WampMode.rpc, 7),
    (WampMode.publishAck, 0),
    (WampMode.publishAck, 7),
    (WampMode.subscribeCycle, 0),
    (WampMode.registerCycle, 0),
  ]) {
    test(
      '$mode preserves millisecond units and byte counts ($payloadBytes)',
      () async {
        final sessions = <_TimedSession>[];
        var releases = 0;
        final start = DateTime.now();
        final samples =
            await WampWorkloadRunner(
              sessionFactory: (_) async {
                final session = _TimedSession();
                sessions.add(session);
                return session;
              },
              releaseMessagePayload: (_) {
                releases++;
                return true;
              },
            ).run(
              WampScenario(
                transport: WampTransport.rawsocket,
                serializer: WampSerializer.cbor,
                mode: mode,
                uri: 'bench.units',
                iterations: 2,
                concurrency: 2,
                payloadBytes: payloadBytes,
              ),
            );
        final outerMs = DateTime.now().difference(start).inMicroseconds / 1000;
        final durations =
            sessions.expand((session) => session.durations).toList()..sort();
        expect(durations, isNotEmpty);
        final innerMs = durations.first;
        expect(innerMs, greaterThan(0));
        expect(samples, hasLength(4));
        expect(
          samples.map((sample) => (sample.worker, sample.iteration)),
          unorderedEquals([(0, 0), (0, 1), (1, 0), (1, 1)]),
        );
        for (final sample in samples) {
          expect(sample.latencyMs, greaterThanOrEqualTo(innerMs));
          expect(sample.latencyMs, lessThanOrEqualTo(outerMs));
          expect(sample.requestBytes, payloadBytes);
          expect(sample.responseBytes, mode == WampMode.rpc ? payloadBytes : 0);
        }
        expect(sessions, hasLength(mode == WampMode.authenticate ? 4 : 2));
        expect(sessions.map((session) => session.closes), everyElement(1));
        expect(releases, mode == WampMode.rpc ? 4 : 0);
        if (mode == WampMode.publishAck || mode == WampMode.rpc) {
          final requests = sessions
              .expand((session) => session.arguments)
              .toList();
          expect(requests, hasLength(4));
          for (final arguments in requests) {
            if (payloadBytes == 0) {
              expect(arguments, isNull);
            } else {
              expect(arguments, hasLength(1));
              expect(
                arguments!.single,
                isA<String>().having(
                  (value) => value.length,
                  'length',
                  payloadBytes,
                ),
              );
            }
          }
        }
        if (mode == WampMode.subscribeCycle || mode == WampMode.registerCycle) {
          expect(sessions.map((session) => session.cancels), everyElement(2));
        }
      },
    );
  }
}

class _TimedSession implements WampSession {
  final durations = <double>[];
  final arguments = <List<dynamic>?>[];
  var closes = 0;
  var cancels = 0;

  Future<void> _work() async {
    final start = DateTime.now();
    // This is the measured synthetic work, not a synchronization delay.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    durations.add(DateTime.now().difference(start).inMicroseconds / 1000);
  }

  @override
  int get id => 1;

  @override
  Future<dynamic> get onDisconnect => Completer<void>().future;

  @override
  Future<void> close() async {
    closes++;
    await _work();
  }

  @override
  Future<void> publishLazyPayload(
    String topic, {
    required core.LazyMessagePayload payload,
    core.PublishOptions? options,
  }) async {
    expect(options?.acknowledge, isTrue);
    arguments.add(payload.arguments);
    await _work();
  }

  @override
  Future<core.LazyResultPayload> callSingleWithLazyPayload(
    String procedure, {
    required core.LazyMessagePayload payload,
    core.CallOptions? options,
  }) async {
    arguments.add(payload.arguments);
    await _work();
    return core.Result(
      1,
      core.ResultDetails(),
      arguments: payload.arguments,
    ).toLazyResultPayload();
  }

  Future<void> _cancel() async {
    cancels++;
    await _work();
  }

  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    core.SubscribeOptions? options,
  }) async {
    await _work();
    return WampSubscription(id: 2, cancel: _cancel);
  }

  @override
  Future<WampRegistration> registerLazyPayloadHandler(
    String procedure,
    FutureOr<void> Function(core.LazyInvocationPayload) onInvoke, {
    core.RegisterOptions? options,
  }) async {
    await _work();
    return WampRegistration(id: 3, cancel: _cancel);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
