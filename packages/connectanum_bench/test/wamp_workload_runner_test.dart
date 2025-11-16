import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('WampWorkloadRunner', () {
    test('completes pubsub scenario after receiving matching events', () async {
      final broker = _FakeWampBroker();
      final runner = WampWorkloadRunner(
        sessionFactory: () async => _FakeWampSession(broker),
        logger: Logger.detached('pubsub_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        mode: WampMode.pubsub,
        uri: 'bench.topic',
        iterations: 3,
        concurrency: 2,
        payloadBytes: 8,
      );

      final samples = await runner.run(scenario);

      expect(samples, hasLength(6));
      expect(samples.where((sample) => sample.worker == 0), hasLength(3));
      expect(samples.where((sample) => sample.worker == 1), hasLength(3));
      expect(samples.every((sample) => sample.latencyMs >= 0), isTrue);
    });

    test('throws when matching events do not arrive before timeout', () async {
      final broker = _FakeWampBroker(dropMetadata: true);
      final runner = WampWorkloadRunner(
        sessionFactory: () async => _FakeWampSession(broker),
        logger: Logger.detached('timeout_test'),
        eventTimeout: const Duration(milliseconds: 50),
      );
      final scenario = WampScenario(
        mode: WampMode.pubsub,
        uri: 'bench.topic',
        iterations: 1,
        concurrency: 1,
        payloadBytes: 4,
      );

      await expectLater(
        () => runner.run(scenario),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('executes RPC scenario via session.call', () async {
      final broker = _FakeWampBroker();
      final runner = WampWorkloadRunner(
        sessionFactory: () async => _FakeWampSession(broker),
        logger: Logger.detached('rpc_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        mode: WampMode.rpc,
        uri: 'bench.rpc.echo',
        iterations: 2,
        concurrency: 3,
        payloadBytes: 16,
      );

      final samples = await runner.run(scenario);

      expect(samples, hasLength(6));
      expect(broker.callCounts['bench.rpc.echo'], 6);
    });

    test('RPC scenario times out when call never yields', () async {
      final runner = WampWorkloadRunner(
        sessionFactory: () async => _HangingRpcSession(),
        logger: Logger.detached('rpc_hang_test'),
        eventTimeout: const Duration(milliseconds: 50),
      );
      final scenario = WampScenario(
        mode: WampMode.rpc,
        uri: 'bench.rpc.echo',
        iterations: 1,
        concurrency: 1,
        payloadBytes: 8,
      );

      await expectLater(
        () => runner.run(scenario),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

class _FakeWampBroker {
  _FakeWampBroker({this.dropMetadata = false});

  final Map<String, List<StreamController<WampEvent>>> _subscribers = {};
  final Map<String, int> callCounts = {};
  final bool dropMetadata;

  void addSubscriber(String topic, StreamController<WampEvent> controller) {
    final list = _subscribers.putIfAbsent(topic, () => []);
    list.add(controller);
  }

  void removeSubscriber(String topic, StreamController<WampEvent> controller) {
    final list = _subscribers[topic];
    if (list == null) {
      return;
    }
    list.remove(controller);
    if (list.isEmpty) {
      _subscribers.remove(topic);
    }
  }

  void publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
  }) {
    final event = WampEvent(
      arguments: arguments,
      argumentsKeywords: dropMetadata ? null : argumentsKeywords,
    );
    final subscribers = _subscribers[topic];
    if (subscribers == null) {
      return;
    }
    for (final controller in subscribers) {
      controller.add(event);
    }
  }

  void recordCall(String procedure) {
    callCounts[procedure] = (callCounts[procedure] ?? 0) + 1;
  }
}

class _FakeWampSession implements WampSession {
  _FakeWampSession(this._broker);

  final _FakeWampBroker _broker;
  final List<WampSubscription> _subscriptions = [];

  @override
  Future<void> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.PublishOptions? options,
  }) async {
    _broker.publish(
      topic,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
    );
  }

  @override
  Future<WampSubscription> subscribe(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) async {
    final controller = StreamController<WampEvent>.broadcast();
    _broker.addSubscriber(topic, controller);
    final subscription = WampSubscription(
      events: controller.stream,
      cancel: () async {
        _broker.removeSubscriber(topic, controller);
        await controller.close();
      },
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  Future<Stream<dynamic>> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    _broker.recordCall(procedure);
    return Stream.value(null);
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

class _HangingRpcSession implements WampSession {
  @override
  Future<void> close() async {}

  @override
  Future<void> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.PublishOptions? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Stream<dynamic>> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    // Never emits or completes to simulate a stuck RPC.
    final controller = StreamController<dynamic>();
    return controller.stream;
  }

  @override
  Future<WampSubscription> subscribe(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) {
    throw UnimplementedError();
  }
}
