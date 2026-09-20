import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:test/test.dart';

void main() {
  test(
    'a delivered payload is released once when publish subsequently fails',
    () async {
      final result = await _capture((unhandled) async {
        final fixture = _Fixture(peerCount: 2);
        final failure = StateError('ACK rejected after first delivery');
        final run = fixture.run();
        await fixture.publisher.publishStarted.future;
        fixture.subscribers.first.emit({'worker': 0, 'iteration': 0});
        await Future<void>.delayed(Duration.zero);
        final releasedBeforeFailure = fixture.releasedPayloads;
        fixture.publisher.ack.completeError(failure);
        await run.future;
        await Future<void>.delayed(Duration.zero);
        return (
          fixture: fixture,
          unhandled: unhandled,
          expectedError: failure,
          releasedBeforeFailure: releasedBeforeFailure,
        );
      });
      expect(result.unhandled, isEmpty);
      expect(result.releasedBeforeFailure, 1);
      expect(result.fixture.failure, same(result.expectedError));
      _expectCleaned(result.fixture, expectedReleases: 1);
    },
  );

  for (final ackFirst in [false, true]) {
    for (final representation in ['int', 'double', 'string']) {
      test(
        'success needs ACK and all peers ($ackFirst, $representation)',
        () async {
          final result = await _capture((unhandled) async {
            final fixture = _Fixture(peerCount: 2);
            final run = fixture.run();
            await fixture.publisher.publishStarted.future;
            if (ackFirst) fixture.publisher.ack.complete();
            fixture.subscribers[0].emit({'worker': 'invalid', 'iteration': 0});
            fixture.subscribers[1].emit({'worker': 99, 'iteration': 0});
            await Future<void>.delayed(Duration.zero);
            final settledOnUnrelated = run.isCompleted;
            final Object zero = switch (representation) {
              'double' => 0.0,
              'string' => '0',
              _ => 0,
            };
            fixture.subscribers[0].emit({'worker': zero, 'iteration': zero});
            await Future<void>.delayed(Duration.zero);
            final settledOnFirstPeer = run.isCompleted;
            fixture.subscribers[1].emit({'worker': zero, 'iteration': zero});
            await Future<void>.delayed(Duration.zero);
            final settledAfterPeers = run.isCompleted;
            if (!ackFirst) fixture.publisher.ack.complete();
            await run.future;
            return (
              fixture: fixture,
              unhandled: unhandled,
              unrelated: settledOnUnrelated,
              firstPeer: settledOnFirstPeer,
              allPeers: settledAfterPeers,
            );
          });
          expect(result.unhandled, isEmpty);
          expect(result.unrelated, isFalse);
          expect(result.firstPeer, isFalse);
          expect(result.allPeers, ackFirst);
          expect(result.fixture.failure, isNull);
          final samples = result.fixture.samples!;
          expect(samples, hasLength(1));
          expect(samples.single.worker, 0);
          expect(samples.single.iteration, 0);
          expect(samples.single.requestBytes, 32);
          expect(samples.single.responseBytes, 64);
          expect(result.fixture.releasedPayloads, 2);
          expect(result.fixture.publisher.closeCount, 1);
          expect(result.fixture.publisher.publishedTopic, 'bench.events');
          expect(result.fixture.publisher.publishOptions!.acknowledge, isTrue);
          for (final subscriber in result.fixture.subscribers) {
            expect(subscriber.closeCount, 1);
            expect(subscriber.cancelCount, 1);
          }
        },
      );
    }
  }

  test(
    'first subscriber failure owns secondary disconnect and ACK failures',
    () async {
      final result = await _capture((unhandled) async {
        final fixture = _Fixture(peerCount: 2);
        final failure = StateError('first subscriber failed');
        final run = fixture.run();
        await fixture.publisher.publishStarted.future;
        fixture.subscribers[0].disconnected.completeError(failure);
        fixture.subscribers[1].disconnected.completeError(
          StateError('second failure'),
        );
        await Future<void>.delayed(Duration.zero);
        fixture.publisher.ack.completeError(StateError('late ACK failure'));
        await run.future;
        await Future<void>.delayed(Duration.zero);
        return (fixture: fixture, expectedError: failure, unhandled: unhandled);
      });
      expect(result.unhandled, isEmpty);
      expect(result.fixture.failure, same(result.expectedError));
      _expectCleaned(result.fixture);
    },
  );

  for (final disconnectError in [false, true]) {
    test(
      'subscriber disconnect (error=$disconnectError) before publish ACK',
      () async {
        final result = await _capture((unhandled) async {
          final fixture = _Fixture();
          final failure = StateError('subscriber disconnected');
          final stack = StackTrace.fromString('subscriber-disconnect-origin');
          final run = fixture.run();
          await fixture.publisher.publishStarted.future;
          if (disconnectError) {
            fixture.subscriber.disconnected.completeError(failure, stack);
          } else {
            fixture.subscriber.disconnected.complete();
          }
          await Future<void>.delayed(Duration.zero);
          final settledBeforeAck = run.isCompleted;
          fixture.publisher.ack.complete();
          await run.future;
          await Future<void>.delayed(Duration.zero);
          return (
            fixture: fixture,
            expectedError: failure,
            expectedStack: stack,
            early: settledBeforeAck,
            unhandled: unhandled,
          );
        });
        expect(result.unhandled, isEmpty);
        expect(
          result.early,
          isTrue,
          reason: 'Disconnect must not wait for ACK.',
        );
        if (disconnectError) {
          expect(result.fixture.failure, same(result.expectedError));
          expect(
            result.fixture.stack.toString(),
            result.expectedStack.toString(),
          );
        } else {
          expect(
            result.fixture.failure,
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'No element',
            ),
          );
        }
        _expectCleaned(result.fixture);
      },
    );
  }

  for (final synchronous in [false, true]) {
    test(
      'publish failure (synchronous=$synchronous) owns event waiter errors',
      () async {
        final result = await _capture((unhandled) async {
          final failure = StateError('publisher rejected');
          final fixture = _Fixture(
            synchronousPublishError: synchronous ? failure : null,
          );
          final run = fixture.run();
          await fixture.publisher.publishStarted.future;
          if (!synchronous) fixture.publisher.ack.completeError(failure);
          await run.future;
          await Future<void>.delayed(Duration.zero);
          return (
            fixture: fixture,
            expectedError: failure,
            unhandled: unhandled,
          );
        });
        expect(result.unhandled, isEmpty);
        expect(result.fixture.failure, same(result.expectedError));
        _expectCleaned(result.fixture);
      },
    );
  }
}

void _expectCleaned(_Fixture fixture, {int expectedReleases = 0}) {
  expect(fixture.samples, isNull);
  expect(fixture.publisher.closeCount, 1);
  for (final subscriber in fixture.subscribers) {
    expect(subscriber.closeCount, 1);
    expect(subscriber.cancelCount, 1);
  }
  expect(fixture.releasedPayloads, expectedReleases);
}

Future<T> _capture<T>(Future<T> Function(List<Object>) body) {
  final completed = Completer<T>();
  final unhandled = <Object>[];
  runZonedGuarded(
    () => body(
      unhandled,
    ).then(completed.complete, onError: completed.completeError),
    (error, stack) => unhandled.add(error),
  );
  return completed.future;
}

class _Fixture {
  _Fixture({Object? synchronousPublishError, int peerCount = 1})
    : publisher = _Session(synchronousPublishError: synchronousPublishError),
      subscribers = List.generate(peerCount, (_) => _Session());

  final _Session publisher;
  final List<_Session> subscribers;
  _Session get subscriber => subscribers.first;
  Object? failure;
  StackTrace? stack;
  List<WampSample>? samples;
  var releasedPayloads = 0;

  Completer<void> run() {
    final completed = Completer<void>();
    var opened = 0;
    final runner = WampWorkloadRunner(
      sessionFactory: (_) async =>
          opened++ == 0 ? publisher : subscribers[opened - 2],
      releaseMessagePayload: (_) {
        releasedPayloads += 1;
        return true;
      },
      eventTimeout: const Duration(seconds: 2),
    );
    runner
        .run(
          WampScenario.fromJson({
            'mode': 'pubsub',
            'uri': 'bench.events',
            'iterations': 1,
            'peer_count': subscribers.length,
            'payload_bytes': 32,
          }),
        )
        .then(
          (value) {
            samples = value;
            completed.complete();
          },
          onError: (Object error, StackTrace trace) {
            failure = error;
            stack = trace;
            completed.complete();
          },
        );
    return completed;
  }
}

class _Session implements WampSession {
  _Session({this.synchronousPublishError});

  final Object? synchronousPublishError;
  final disconnected = Completer<void>();
  final publishStarted = Completer<void>();
  final ack = Completer<void>();
  var closeCount = 0;
  var cancelCount = 0;
  void Function(wamp.LazyEventPayload)? _onEvent;
  String? publishedTopic;
  wamp.PublishOptions? publishOptions;

  void emit(Map<String, Object?> metadata) {
    _onEvent!(
      wamp.Event(
        2,
        3,
        wamp.EventDetails(),
        argumentsKeywords: metadata,
      ).toLazyEventPayload(),
    );
  }

  @override
  int get id => 1;

  @override
  Future<void> get onDisconnect => disconnected.future;

  @override
  Future<void> publishLazyPayload(
    String topic, {
    required wamp.LazyMessagePayload payload,
    wamp.PublishOptions? options,
  }) {
    publishedTopic = topic;
    publishOptions = options;
    publishStarted.complete();
    final error = synchronousPublishError;
    if (error != null) throw error;
    return ack.future;
  }

  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    wamp.SubscribeOptions? options,
  }) async => WampSubscription(
    id: 2,
    attachEventHandler: (handler) => _onEvent = handler,
    cancel: () async {
      cancelCount += 1;
    },
  );

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
