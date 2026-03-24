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
        sessionFactory: (_) async => _FakeWampSession(broker),
        logger: Logger.detached('pubsub_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        transport: WampTransport.rawsocket,
        serializer: WampSerializer.json,
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
        sessionFactory: (_) async => _FakeWampSession(broker),
        logger: Logger.detached('timeout_test'),
        eventTimeout: const Duration(milliseconds: 50),
      );
      final scenario = WampScenario(
        transport: WampTransport.rawsocket,
        serializer: WampSerializer.json,
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
      final broker = _FakeWampBroker(
        callDelay: const Duration(milliseconds: 10),
      );
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async => _FakeWampSession(broker),
        logger: Logger.detached('rpc_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        transport: WampTransport.rawsocket,
        serializer: WampSerializer.json,
        mode: WampMode.rpc,
        uri: 'bench.rpc.echo',
        iterations: 2,
        concurrency: 3,
        inFlightPerSession: 2,
        payloadBytes: 16,
      );

      final samples = await runner.run(scenario);

      expect(samples, hasLength(6));
      expect(broker.callCounts['bench.rpc.echo'], 6);
      expect(broker.maxConcurrentCalls, greaterThanOrEqualTo(2));
    });

    test(
      'executes pubsub scenario with multiple in-flight publishes per worker',
      () async {
        final broker = _FakeWampBroker(
          publishDelay: const Duration(milliseconds: 10),
        );
        final runner = WampWorkloadRunner(
          sessionFactory: (_) async => _FakeWampSession(broker),
          logger: Logger.detached('pubsub_inflight_test'),
          eventTimeout: const Duration(seconds: 1),
        );
        final scenario = WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.json,
          mode: WampMode.pubsub,
          uri: 'bench.topic',
          iterations: 4,
          concurrency: 1,
          inFlightPerSession: 2,
          payloadBytes: 16,
        );

        final samples = await runner.run(scenario);

        expect(samples, hasLength(4));
        expect(broker.maxConcurrentPublishes, greaterThanOrEqualTo(2));
      },
    );

    test('supports multiple concurrent event waiters', () async {
      final buffer = WampEventBuffer();
      final waiterOne = buffer.nextWhere(
        (event) => event.argumentsKeywords?['worker'] == 1,
      );
      final waiterTwo = buffer.nextWhere(
        (event) => event.argumentsKeywords?['worker'] == 2,
      );

      buffer.add(WampEvent(argumentsKeywords: const {'worker': 2}));
      buffer.add(WampEvent(argumentsKeywords: const {'worker': 1}));

      final eventOne = await waiterOne;
      final eventTwo = await waiterTwo;

      expect(eventOne.argumentsKeywords?['worker'], 1);
      expect(eventTwo.argumentsKeywords?['worker'], 2);
    });

    test('RPC scenario times out when call never yields', () async {
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async => _HangingRpcSession(),
        logger: Logger.detached('rpc_hang_test'),
        eventTimeout: const Duration(milliseconds: 50),
      );
      final scenario = WampScenario(
        transport: WampTransport.rawsocket,
        serializer: WampSerializer.json,
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

    test('passes scenario transport into the session factory', () async {
      final broker = _FakeWampBroker();
      final seenTransports = <WampTransport>[];
      final seenSerializers = <WampSerializer>[];
      final runner = WampWorkloadRunner(
        sessionFactory: (scenario) async {
          seenTransports.add(scenario.transport);
          seenSerializers.add(scenario.serializer);
          return _FakeWampSession(broker);
        },
        logger: Logger.detached('transport_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        transport: WampTransport.websocket,
        serializer: WampSerializer.msgpack,
        mode: WampMode.rpc,
        uri: 'bench.rpc.echo',
        iterations: 1,
        concurrency: 2,
        payloadBytes: 8,
      );

      final samples = await runner.run(scenario);

      expect(samples, hasLength(2));
      expect(seenTransports, everyElement(equals(WampTransport.websocket)));
      expect(seenSerializers, everyElement(equals(WampSerializer.msgpack)));
    });
  });

  group('WampScenario', () {
    test('defaults transport to rawsocket when omitted', () {
      final scenario = WampScenario.fromJson({
        'mode': 'pubsub',
        'uri': 'bench.topic',
      });

      expect(scenario.transport, WampTransport.rawsocket);
      expect(scenario.serializer, WampSerializer.json);
      expect(scenario.mode, WampMode.pubsub);
    });

    test('parses websocket transport aliases', () {
      final scenario = WampScenario.fromJson({
        'transport': 'ws',
        'mode': 'rpc',
        'uri': 'bench.rpc.echo',
      });

      expect(scenario.transport, WampTransport.websocket);
      expect(scenario.mode, WampMode.rpc);
    });

    test('parses msgpack serializer aliases', () {
      final scenario = WampScenario.fromJson({
        'transport': 'rawsocket',
        'serializer': 'messagepack',
        'mode': 'rpc',
        'uri': 'bench.rpc.echo',
      });

      expect(scenario.serializer, WampSerializer.msgpack);
    });

    test('parses cbor serializer', () {
      final scenario = WampScenario.fromJson({
        'transport': 'ws',
        'serializer': 'cbor',
        'mode': 'pubsub',
        'uri': 'bench.topic',
      });

      expect(scenario.serializer, WampSerializer.cbor);
    });

    test('parses in-flight-per-session overrides', () {
      final scenario = WampScenario.fromJson({
        'transport': 'rawsocket',
        'mode': 'rpc',
        'uri': 'bench.rpc.echo',
        'in_flight_per_session': 4,
      });

      expect(scenario.inFlightPerSession, 4);
    });
  });

  group('WampEventBuffer', () {
    test('replays buffered matching events to later waiters', () async {
      final buffer = WampEventBuffer();
      buffer.add(
        WampEvent(argumentsKeywords: const {'worker': 1, 'iteration': 2}),
      );

      final event = await buffer.nextWhere(
        (event) =>
            event.argumentsKeywords?['worker'] == 1 &&
            event.argumentsKeywords?['iteration'] == 2,
      );

      expect(event.argumentsKeywords?['worker'], 1);
      expect(event.argumentsKeywords?['iteration'], 2);
    });

    test(
      'completes pending waiter when matching event arrives later',
      () async {
        final buffer = WampEventBuffer();
        final future = buffer.nextWhere(
          (event) => event.argumentsKeywords?['worker'] == 7,
        );

        buffer.add(WampEvent(argumentsKeywords: const {'worker': 3}));
        buffer.add(WampEvent(argumentsKeywords: const {'worker': 7}));

        final event = await future;
        expect(event.argumentsKeywords?['worker'], 7);
      },
    );
  });
}

class _FakeWampBroker {
  _FakeWampBroker({
    this.dropMetadata = false,
    this.callDelay = Duration.zero,
    this.publishDelay = Duration.zero,
  });

  final Map<String, List<StreamController<WampEvent>>> _subscribers = {};
  final Map<String, int> callCounts = {};
  final bool dropMetadata;
  final Duration callDelay;
  final Duration publishDelay;
  int _activeCalls = 0;
  int maxConcurrentCalls = 0;
  int _activePublishes = 0;
  int maxConcurrentPublishes = 0;

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

  void beginCall() {
    _activeCalls += 1;
    if (_activeCalls > maxConcurrentCalls) {
      maxConcurrentCalls = _activeCalls;
    }
  }

  void endCall() {
    _activeCalls -= 1;
  }

  void beginPublish() {
    _activePublishes += 1;
    if (_activePublishes > maxConcurrentPublishes) {
      maxConcurrentPublishes = _activePublishes;
    }
  }

  void endPublish() {
    _activePublishes -= 1;
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
    _broker.beginPublish();
    try {
      if (_broker.publishDelay > Duration.zero) {
        await Future<void>.delayed(_broker.publishDelay);
      }
      _broker.publish(
        topic,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
    } finally {
      _broker.endPublish();
    }
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
    _broker.beginCall();
    final response = Future<dynamic>.delayed(
      _broker.callDelay,
    ).whenComplete(_broker.endCall);
    return Stream.fromFuture(response);
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
