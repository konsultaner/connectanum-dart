@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:fake_async/fake_async.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

class _Session implements WampSession {
  var closes = 0;
  bool stallClose = false;
  Object? closeError;
  final closeResult = Completer<void>();
  final subscription = Completer<WampSubscription>();
  final topics = <String>[];

  @override
  Future<void> close() {
    closes++;
    if (closeError != null) {
      return Future<void>.error(closeError!);
    }
    return stallClose ? closeResult.future : Future<void>.value();
  }

  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    core.SubscribeOptions? options,
  }) {
    topics.add(topic);
    return subscription.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const base =
      'worker=0 transport=websocket serializer=json realm=bench.realm uri=bench.diagnostics';
  for (final (name, mode, log, label) in [
    (
      'authentication open',
      WampMode.authenticate,
      'Authenticate session open timed out $base iteration=0',
      'wamp_auth_open_timeout',
    ),
    (
      'publisher open',
      WampMode.pubsub,
      'PUBSUB publisher session open timed out $base',
      'pubsub_publisher_open_timeout',
    ),
    (
      'subscriber open',
      WampMode.pubsub,
      'PUBSUB subscriber session open timed out $base peer=0',
      'pubsub_subscriber_open_timeout',
    ),
    (
      'authentication close',
      WampMode.authenticate,
      'Authenticate close timed out $base iteration=0',
      'wamp_auth_close_timeout',
    ),
    (
      'subscriber subscribe',
      WampMode.pubsub,
      'PUBSUB subscribe timed out $base peer=0',
      'pubsub_subscribe_timeout',
    ),
    (
      'subscribe cycle',
      WampMode.subscribeCycle,
      'Subscribe-cycle subscribe timed out $base.0.0 iteration=0',
      'subscribe_cycle_subscribe_timeout',
    ),
  ]) {
    test('$name diagnostics preserve actual operation context', () {
      fakeAsync((async) {
        final sessions = <_Session>[];
        final pending = Completer<WampSession>();
        final errors = <Object>[];
        final results = <List<WampSample>>[];
        final records = <LogRecord>[];
        final logger = Logger.detached('diagnostics')..level = Level.ALL;
        final subscription = logger.onRecord.listen(records.add);
        final runner = WampWorkloadRunner(
          logger: logger,
          eventTimeout: const Duration(seconds: 1),
          releaseMessagePayload: (_) => false,
          sessionFactory: (_) {
            if (name == 'authentication open' ||
                name == 'publisher open' ||
                (name == 'subscriber open' && sessions.isNotEmpty)) {
              return pending.future;
            }
            final session = _Session()
              ..stallClose = name == 'authentication close';
            sessions.add(session);
            return Future.value(session);
          },
        );
        unawaited(
          runner
              .run(
                WampScenario(
                  transport: WampTransport.websocket,
                  serializer: WampSerializer.json,
                  realmUri: 'bench.realm',
                  mode: mode,
                  uri: 'bench.diagnostics',
                  iterations: 1,
                  concurrency: 1,
                  peerCount: 1,
                  payloadBytes: 4,
                ),
              )
              .then(results.add, onError: (Object error) => errors.add(error)),
        );
        async.flushMicrotasks();
        expect(errors, isEmpty);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(results, isEmpty);
        expect(errors, hasLength(1));
        expect(
          errors.single,
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            label,
          ),
        );
        final messages = records
            .where((record) => record.level == Level.SEVERE)
            .map((record) => record.message)
            .toList();
        expect(messages.first, '$log timeout=0:00:01.000000');
        for (final session in sessions) {
          expect(session.closes, 1);
        }
        if (name == 'subscribe cycle') {
          expect(sessions.single.topics, ['bench.diagnostics.0.0']);
        }
        unawaited(subscription.cancel());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  }

  for (final cleanup in ['success', 'failure', 'timeout', 'open failure']) {
    test('abandoned session cleanup: $cleanup preserves primary failure', () {
      fakeAsync((async) {
        final pending = Completer<WampSession>();
        final late = _Session()
          ..stallClose = cleanup == 'timeout'
          ..closeError = cleanup == 'failure'
              ? StateError('private-close-detail')
              : null;
        final errors = <Object>[];
        final records = <LogRecord>[];
        final logger = Logger.detached('late_cleanup')..level = Level.ALL;
        final listener = logger.onRecord.listen(records.add);
        final runner = WampWorkloadRunner(
          logger: logger,
          eventTimeout: const Duration(seconds: 1),
          cancelCleanupTimeout: const Duration(seconds: 2),
          sessionFactory: (_) => pending.future,
          releaseMessagePayload: (_) => false,
        );
        unawaited(
          runner
              .run(
                WampScenario(
                  transport: WampTransport.websocket,
                  serializer: WampSerializer.json,
                  mode: WampMode.authenticate,
                  uri: 'bench.late',
                  iterations: 1,
                  concurrency: 1,
                  payloadBytes: 4,
                ),
              )
              .then(
                (_) => fail('abandoned run must not succeed'),
                onError: (Object error) => errors.add(error),
              ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(errors, hasLength(1));
        final original = errors.single;
        expect(original, isA<TimeoutException>());
        if (cleanup == 'open failure') {
          pending.completeError(StateError('private-open-detail'));
        } else {
          pending.complete(late);
        }
        async.flushMicrotasks();
        expect(late.closes, cleanup == 'open failure' ? 0 : 1);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(errors, [same(original)]);
        expect(late.closes, cleanup == 'open failure' ? 0 : 1);
        final warnings = records
            .where((record) => record.level == Level.WARNING)
            .toList();
        if (cleanup == 'failure' || cleanup == 'timeout') {
          expect(warnings, hasLength(1));
          expect(
            warnings.single.message,
            cleanup == 'failure'
                ? 'Authenticate late session cleanup failed'
                : startsWith('Authenticate late session cleanup timed out '),
          );
          expect(warnings.single.error, isNull);
          expect(warnings.single.stackTrace, isNull);
        } else {
          expect(warnings, isEmpty);
        }
        expect(
          records.map((record) => record.message).join(),
          isNot(contains('private-')),
        );
        unawaited(listener.cancel());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  }

  test('successfully acquired session is not closed a second time', () {
    fakeAsync((async) {
      final session = _Session();
      final results = <List<WampSample>>[];
      final errors = <Object>[];
      unawaited(
        WampWorkloadRunner(sessionFactory: (_) async => session)
            .run(
              WampScenario(
                transport: WampTransport.websocket,
                serializer: WampSerializer.json,
                mode: WampMode.authenticate,
                uri: 'bench.success',
                iterations: 1,
                concurrency: 1,
                payloadBytes: 4,
              ),
            )
            .then(results.add, onError: (Object error) => errors.add(error)),
      );
      async.flushMicrotasks();
      expect(results.single, hasLength(1));
      expect(session.closes, 1);
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(session.closes, 1);
      expect(errors, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  for (final openingWins in [true, false]) {
    test('same-instant opening and timeout openingWins=$openingWins', () {
      fakeAsync((async) {
        final session = _Session();
        final opened = Completer<WampSession>();
        final results = <List<WampSample>>[];
        final errors = <Object>[];
        final runner = WampWorkloadRunner(
          eventTimeout: const Duration(seconds: 1),
          sessionFactory: (_) {
            if (openingWins) {
              Timer(const Duration(seconds: 1), () => opened.complete(session));
            }
            return opened.future;
          },
          releaseMessagePayload: (_) => false,
        );
        unawaited(
          runner
              .run(
                WampScenario(
                  transport: WampTransport.websocket,
                  serializer: WampSerializer.json,
                  mode: WampMode.authenticate,
                  uri: 'bench.order',
                  iterations: 1,
                  concurrency: 1,
                  payloadBytes: 4,
                ),
              )
              .then(results.add, onError: (Object error) => errors.add(error)),
        );
        async.flushMicrotasks();
        if (!openingWins) {
          Timer(const Duration(seconds: 1), () => opened.complete(session));
        }
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(session.closes, 1);
        expect(results, hasLength(openingWins ? 1 : 0));
        expect(errors, hasLength(openingWins ? 0 : 1));
        if (!openingWins) {
          expect(errors.single, isA<TimeoutException>());
        }
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(session.closes, 1);
        expect(async.pendingTimers, isEmpty);
      });
    });
  }

  for (final reverseReplies in [false, true]) {
    test(
      'concurrent late sessions remain independent reverse=$reverseReplies',
      () {
        fakeAsync((async) {
          final pending = [Completer<WampSession>(), Completer<WampSession>()];
          final sessions = [_Session(), _Session()];
          var opens = 0;
          final errors = <Object>[];
          final runner = WampWorkloadRunner(
            eventTimeout: const Duration(seconds: 1),
            sessionFactory: (_) => pending[opens++].future,
            releaseMessagePayload: (_) => false,
          );
          unawaited(
            runner
                .run(
                  WampScenario(
                    transport: WampTransport.websocket,
                    serializer: WampSerializer.json,
                    mode: WampMode.authenticate,
                    uri: 'bench.concurrent',
                    iterations: 1,
                    concurrency: 2,
                    payloadBytes: 4,
                  ),
                )
                .then(
                  (_) => fail('both workers timed out'),
                  onError: (Object error) => errors.add(error),
                ),
          );
          async.flushMicrotasks();
          expect(opens, 2);
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(errors, hasLength(1));
          expect(errors.single, isA<TimeoutException>());
          final order = reverseReplies ? [1, 0] : [0, 1];
          pending[order.first].complete(sessions[order.first]);
          async.flushMicrotasks();
          expect(sessions[order.first].closes, 1);
          expect(sessions[order.last].closes, 0);
          pending[order.last].complete(sessions[order.last]);
          async.flushMicrotasks();
          expect(sessions.map((session) => session.closes), [1, 1]);
          expect(errors, hasLength(1));
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  }

  for (final mode in [WampMode.authenticate, WampMode.publishAck]) {
    test('late $mode session is closed after opening timeout', () {
      fakeAsync((async) {
        final pending = Completer<WampSession>();
        final late = _Session();
        final errors = <Object>[];
        final results = <List<WampSample>>[];
        final runner = WampWorkloadRunner(
          eventTimeout: const Duration(seconds: 1),
          sessionFactory: (_) => pending.future,
          releaseMessagePayload: (_) => false,
        );
        unawaited(
          runner
              .run(
                WampScenario(
                  transport: WampTransport.websocket,
                  serializer: WampSerializer.json,
                  mode: mode,
                  uri: 'bench.late',
                  iterations: 1,
                  concurrency: 1,
                  payloadBytes: 4,
                ),
              )
              .then(results.add, onError: (Object error) => errors.add(error)),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(errors, hasLength(1));
        expect(errors.single, isA<TimeoutException>());
        expect(results, isEmpty);
        pending.complete(late);
        async.flushMicrotasks();
        expect(
          late.closes,
          1,
          reason:
              'a session acquired after its owner timed out must be released',
        );
        expect(errors, hasLength(1));
        expect(results, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });
  }
}
