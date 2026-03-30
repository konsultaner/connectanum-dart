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

    test('supports pubsub workloads through direct event callbacks', () async {
      final broker = _FakeWampBroker();
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async =>
            _FakeWampSession(broker, useDirectEventHandler: true),
        logger: Logger.detached('pubsub_direct_callback_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        transport: WampTransport.rawsocket,
        serializer: WampSerializer.json,
        mode: WampMode.pubsub,
        uri: 'bench.topic',
        iterations: 2,
        concurrency: 2,
        payloadBytes: 8,
      );

      final samples = await runner.run(scenario);

      expect(samples, hasLength(4));
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

    test('executes RPC scenario via the single-result call path', () async {
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

    test('passes PPT options through pubsub and rpc workloads', () async {
      final broker = _FakeWampBroker();
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async => _FakeWampSession(broker),
        logger: Logger.detached('ppt_options_test'),
        eventTimeout: const Duration(seconds: 1),
      );

      await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.pubsub,
          uri: 'bench.topic',
          iterations: 1,
          concurrency: 1,
          payloadBytes: 8,
          pptScheme: 'x_custom_scheme',
        ),
      );
      expect(broker.lastPublishOptions?.pptScheme, 'x_custom_scheme');
      expect(broker.lastPublishOptions?.pptSerializer, 'cbor');

      await runner.run(
        WampScenario(
          transport: WampTransport.websocket,
          serializer: WampSerializer.msgpack,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 1,
          concurrency: 1,
          payloadBytes: 8,
          pptScheme: 'x_custom_scheme',
          pptSerializer: 'json',
        ),
      );
      expect(broker.lastCallOptions?.pptScheme, 'x_custom_scheme');
      expect(broker.lastCallOptions?.pptSerializer, 'json');
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

      buffer.add(
        wamp_core.Event(
          1,
          2,
          wamp_core.EventDetails(),
          argumentsKeywords: const {'worker': 2},
        ).toLazyEventPayload(),
      );
      buffer.add(
        wamp_core.Event(
          1,
          1,
          wamp_core.EventDetails(),
          argumentsKeywords: const {'worker': 1},
        ).toLazyEventPayload(),
      );

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
      final seenClientImplementations = <WampClientImplementation>[];
      final seenSerializers = <WampSerializer>[];
      final runner = WampWorkloadRunner(
        sessionFactory: (scenario) async {
          seenTransports.add(scenario.transport);
          seenClientImplementations.add(scenario.clientImplementation);
          seenSerializers.add(scenario.serializer);
          return _FakeWampSession(broker);
        },
        logger: Logger.detached('transport_test'),
        eventTimeout: const Duration(seconds: 1),
      );
      final scenario = WampScenario(
        transport: WampTransport.websocket,
        clientImplementation: WampClientImplementation.native,
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
      expect(
        seenClientImplementations,
        everyElement(equals(WampClientImplementation.native)),
      );
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
      expect(scenario.clientImplementation, WampClientImplementation.dart);
      expect(scenario.serializer, WampSerializer.json);
      expect(scenario.mode, WampMode.pubsub);
    });

    test('parses native client implementation aliases', () {
      final scenario = WampScenario.fromJson({
        'transport': 'rawsocket',
        'client_impl': 'rust',
        'mode': 'rpc',
        'uri': 'bench.rpc.echo',
      });

      expect(scenario.clientImplementation, WampClientImplementation.native);
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

    test('parses PPT overrides', () {
      final scenario = WampScenario.fromJson({
        'transport': 'ws',
        'serializer': 'cbor',
        'mode': 'rpc',
        'uri': 'bench.rpc.echo',
        'ppt_scheme': 'x_custom_scheme',
        'ppt_serializer': 'msgpack',
      });

      expect(scenario.pptScheme, 'x_custom_scheme');
      expect(scenario.pptSerializer, 'msgpack');
    });
  });

  group('WampEventBuffer', () {
    test('replays buffered matching events to later waiters', () async {
      final buffer = WampEventBuffer();
      buffer.add(
        wamp_core.Event(
          1,
          2,
          wamp_core.EventDetails(),
          argumentsKeywords: const {'worker': 1, 'iteration': 2},
        ).toLazyEventPayload(),
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

        buffer.add(
          wamp_core.Event(
            1,
            3,
            wamp_core.EventDetails(),
            argumentsKeywords: const {'worker': 3},
          ).toLazyEventPayload(),
        );
        buffer.add(
          wamp_core.Event(
            1,
            7,
            wamp_core.EventDetails(),
            argumentsKeywords: const {'worker': 7},
          ).toLazyEventPayload(),
        );

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

  final Map<String, List<StreamController<wamp_core.Event>>> _subscribers = {};
  final Map<String, List<StreamController<wamp_core.LazyEventPayload>>>
  _payloadSubscribers = {};
  final Map<String, List<void Function(wamp_core.Event event)>>
  _callbackSubscribers = {};
  final Map<String, List<void Function(wamp_core.LazyEventPayload event)>>
  _payloadCallbackSubscribers = {};
  final Map<String, int> callCounts = {};
  final bool dropMetadata;
  final Duration callDelay;
  final Duration publishDelay;
  wamp_core.CallOptions? lastCallOptions;
  wamp_core.PublishOptions? lastPublishOptions;
  int _activeCalls = 0;
  int maxConcurrentCalls = 0;
  int _activePublishes = 0;
  int maxConcurrentPublishes = 0;

  void addSubscriber(
    String topic,
    StreamController<wamp_core.Event> controller,
  ) {
    final list = _subscribers.putIfAbsent(topic, () => []);
    list.add(controller);
  }

  void removeSubscriber(
    String topic,
    StreamController<wamp_core.Event> controller,
  ) {
    final list = _subscribers[topic];
    if (list == null) {
      return;
    }
    list.remove(controller);
    if (list.isEmpty) {
      _subscribers.remove(topic);
    }
  }

  void addCallbackSubscriber(
    String topic,
    void Function(wamp_core.Event event) onEvent,
  ) {
    final list = _callbackSubscribers.putIfAbsent(topic, () => []);
    list.add(onEvent);
  }

  void removeCallbackSubscriber(
    String topic,
    void Function(wamp_core.Event event) onEvent,
  ) {
    final list = _callbackSubscribers[topic];
    if (list == null) {
      return;
    }
    list.remove(onEvent);
    if (list.isEmpty) {
      _callbackSubscribers.remove(topic);
    }
  }

  void addPayloadSubscriber(
    String topic,
    StreamController<wamp_core.LazyEventPayload> controller,
  ) {
    final list = _payloadSubscribers.putIfAbsent(topic, () => []);
    list.add(controller);
  }

  void removePayloadSubscriber(
    String topic,
    StreamController<wamp_core.LazyEventPayload> controller,
  ) {
    final list = _payloadSubscribers[topic];
    if (list == null) {
      return;
    }
    list.remove(controller);
    if (list.isEmpty) {
      _payloadSubscribers.remove(topic);
    }
  }

  void addPayloadCallbackSubscriber(
    String topic,
    void Function(wamp_core.LazyEventPayload event) onEvent,
  ) {
    final list = _payloadCallbackSubscribers.putIfAbsent(topic, () => []);
    list.add(onEvent);
  }

  void removePayloadCallbackSubscriber(
    String topic,
    void Function(wamp_core.LazyEventPayload event) onEvent,
  ) {
    final list = _payloadCallbackSubscribers[topic];
    if (list == null) {
      return;
    }
    list.remove(onEvent);
    if (list.isEmpty) {
      _payloadCallbackSubscribers.remove(topic);
    }
  }

  void publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
  }) {
    final event = wamp_core.Event(
      1,
      1,
      wamp_core.EventDetails(),
      arguments: arguments,
      argumentsKeywords: dropMetadata ? null : argumentsKeywords,
    );
    final subscribers = _subscribers[topic];
    if (subscribers != null) {
      for (final controller in subscribers) {
        controller.add(event);
      }
    }
    final payload = event.toLazyEventPayload(anchor: event);
    final payloadSubscribers = _payloadSubscribers[topic];
    if (payloadSubscribers != null) {
      for (final controller in payloadSubscribers) {
        controller.add(payload);
      }
    }
    final callbackSubscribers = _callbackSubscribers[topic];
    if (callbackSubscribers != null) {
      for (final callback in callbackSubscribers) {
        callback(event);
      }
    }
    final payloadCallbacks = _payloadCallbackSubscribers[topic];
    if (payloadCallbacks == null) {
      return;
    }
    for (final callback in payloadCallbacks) {
      callback(payload);
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
  _FakeWampSession(this._broker, {this.useDirectEventHandler = false});

  final _FakeWampBroker _broker;
  final bool useDirectEventHandler;
  final List<WampSubscription> _subscriptions = [];
  final _disconnectCompleter = Completer<void>();

  @override
  Future<dynamic> get onDisconnect => _disconnectCompleter.future;

  @override
  Future<void> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.PublishOptions? options,
  }) async {
    _broker.lastPublishOptions = options;
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
  Future<void> publishLazyPayload(
    String topic, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.PublishOptions? options,
  }) {
    return publish(
      topic,
      arguments: payload.arguments,
      argumentsKeywords: payload.argumentsKeywords,
      options: options,
    );
  }

  @override
  Future<WampSubscription> subscribe(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) async {
    WampSubscription subscription;
    if (useDirectEventHandler) {
      void Function(wamp_core.LazyEventPayload event)? callback;
      subscription = WampSubscription(
        attachEventHandler: (onEvent) {
          callback = onEvent;
          _broker.addPayloadCallbackSubscriber(topic, onEvent);
        },
        cancel: () async {
          final activeCallback = callback;
          if (activeCallback != null) {
            _broker.removePayloadCallbackSubscriber(topic, activeCallback);
            callback = null;
          }
        },
      );
    } else {
      final controller =
          StreamController<wamp_core.LazyEventPayload>.broadcast();
      _broker.addPayloadSubscriber(topic, controller);
      subscription = WampSubscription(
        eventStreamFactory: () => controller.stream,
        cancel: () async {
          _broker.removePayloadSubscriber(topic, controller);
          await controller.close();
        },
      );
    }
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  Future<WampSubscription> subscribePayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) async {
    WampSubscription subscription;
    if (useDirectEventHandler) {
      void Function(wamp_core.LazyEventPayload event)? callback;
      subscription = WampSubscription(
        attachEventHandler: (onEvent) {
          callback = onEvent;
          _broker.addPayloadCallbackSubscriber(topic, onEvent);
        },
        cancel: () async {
          final activeCallback = callback;
          if (activeCallback != null) {
            _broker.removePayloadCallbackSubscriber(topic, activeCallback);
            callback = null;
          }
        },
      );
    } else {
      final controller =
          StreamController<wamp_core.LazyEventPayload>.broadcast();
      _broker.addPayloadSubscriber(topic, controller);
      subscription = WampSubscription(
        eventStreamFactory: () => controller.stream,
        cancel: () async {
          _broker.removePayloadSubscriber(topic, controller);
          await controller.close();
        },
      );
    }
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) {
    return subscribePayload(topic, options: options);
  }

  @override
  Future<Stream<dynamic>> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    _broker.lastCallOptions = options;
    _broker.recordCall(procedure);
    _broker.beginCall();
    final response = Future<dynamic>.delayed(
      _broker.callDelay,
    ).whenComplete(_broker.endCall);
    return Stream.fromFuture(response);
  }

  @override
  Future<dynamic> callSingle(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    _broker.recordCall(procedure);
    _broker.beginCall();
    try {
      if (_broker.callDelay > Duration.zero) {
        await Future<void>.delayed(_broker.callDelay);
      }
      return null;
    } finally {
      _broker.endCall();
    }
  }

  @override
  Future<wamp_core.ResultPayload> callSinglePayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    _broker.recordCall(procedure);
    _broker.beginCall();
    try {
      if (_broker.callDelay > Duration.zero) {
        await Future<void>.delayed(_broker.callDelay);
      }
      final decodedPayload = options?.pptScheme == null
          ? (
              arguments: arguments == null
                  ? null
                  : List<dynamic>.from(arguments),
              argumentsKeywords: argumentsKeywords == null
                  ? null
                  : Map<String, dynamic>.from(argumentsKeywords),
            )
          : (() {
              final pptOptions = options!;
              final unpacked = wamp_core.PPTPayload.unpackPPTPayload(
                wamp_core.PPTPayload.packPPTPayload(
                  arguments,
                  argumentsKeywords?.cast<String, dynamic>(),
                  pptOptions,
                ),
                pptOptions,
              );
              return (
                arguments: unpacked.arguments,
                argumentsKeywords: unpacked.argumentsKeywords,
              );
            })();
      return (
        callRequestId: 1,
        progress: false,
        pptScheme: options?.pptScheme,
        pptSerializer: options?.pptSerializer,
        pptCipher: null,
        pptKeyId: null,
        customDetails: null,
        arguments: decodedPayload.arguments,
        argumentsKeywords: decodedPayload.argumentsKeywords,
      );
    } finally {
      _broker.endCall();
    }
  }

  @override
  Future<wamp_core.LazyResultPayload> callSingleLazyPayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    _broker.lastCallOptions = options;
    _broker.recordCall(procedure);
    _broker.beginCall();
    try {
      if (_broker.callDelay > Duration.zero) {
        await Future<void>.delayed(_broker.callDelay);
      }
      final payloadArguments = options?.pptScheme == null
          ? (arguments == null ? null : List<dynamic>.from(arguments))
          : wamp_core.PPTPayload.packPPTPayload(
              arguments,
              argumentsKeywords?.cast<String, dynamic>(),
              options!,
            );
      return wamp_core.Result(
        1,
        wamp_core.ResultDetails(
          progress: false,
          pptScheme: options?.pptScheme,
          pptSerializer: options?.pptSerializer,
        ),
        arguments: payloadArguments,
        argumentsKeywords: options?.pptScheme == null
            ? argumentsKeywords == null
                  ? null
                  : Map<String, dynamic>.from(argumentsKeywords)
            : null,
      ).toLazyResultPayload();
    } finally {
      _broker.endCall();
    }
  }

  @override
  Future<wamp_core.LazyResultPayload> callSingleWithLazyPayload(
    String procedure, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.CallOptions? options,
  }) {
    return callSingleLazyPayload(
      procedure,
      arguments: payload.arguments,
      argumentsKeywords: payload.argumentsKeywords,
      options: options,
    );
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    if (!_disconnectCompleter.isCompleted) {
      _disconnectCompleter.complete();
    }
  }
}

class _HangingRpcSession implements WampSession {
  final _disconnectCompleter = Completer<void>();

  @override
  Future<dynamic> get onDisconnect => _disconnectCompleter.future;

  @override
  Future<void> close() async {
    if (!_disconnectCompleter.isCompleted) {
      _disconnectCompleter.complete();
    }
  }

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
  Future<void> publishLazyPayload(
    String topic, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.PublishOptions? options,
  }) {
    return Completer<void>().future;
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
  Future<dynamic> callSingle(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    return Completer<dynamic>().future;
  }

  @override
  Future<wamp_core.ResultPayload> callSinglePayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    return Completer<wamp_core.ResultPayload>().future;
  }

  @override
  Future<wamp_core.LazyResultPayload> callSingleLazyPayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    return Completer<wamp_core.LazyResultPayload>().future;
  }

  @override
  Future<wamp_core.LazyResultPayload> callSingleWithLazyPayload(
    String procedure, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.CallOptions? options,
  }) {
    return Completer<wamp_core.LazyResultPayload>().future;
  }

  @override
  Future<WampSubscription> subscribe(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WampSubscription> subscribePayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) {
    throw UnimplementedError();
  }
}
