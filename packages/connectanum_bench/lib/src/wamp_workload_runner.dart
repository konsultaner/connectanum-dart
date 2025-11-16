import 'dart:async';

import 'package:connectanum_client/connectanum.dart' as wamp_client;
import 'package:connectanum_client/socket.dart' as wamp_socket;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/json_serializer.dart' as wamp_json;
import 'package:logging/logging.dart';

typedef WampSessionFactory = Future<WampSession> Function();

class WampWorkloadRunner {
  WampWorkloadRunner({
    required WampSessionFactory sessionFactory,
    Logger? logger,
    Duration eventTimeout = const Duration(seconds: 30),
  }) : _sessionFactory = sessionFactory,
       _logger = logger ?? Logger('WampWorkloadRunner'),
       _eventTimeout = eventTimeout;

  final WampSessionFactory _sessionFactory;
  final Logger _logger;
  final Duration _eventTimeout;

  Future<List<WampSample>> run(WampScenario scenario) async {
    _logger.fine(
      'Running ${scenario.mode} workload '
      'uri=${scenario.uri} concurrency=${scenario.concurrency} '
      'iterations=${scenario.iterations}',
    );
    switch (scenario.mode) {
      case WampMode.pubsub:
        return _runPubSubScenario(scenario);
      case WampMode.rpc:
        return _runRpcScenario(scenario);
    }
  }

  Future<List<WampSample>> _runPubSubScenario(WampScenario scenario) async {
    final payload = _buildPayloadString(scenario.payloadBytes);
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runPubSubWorker(workerId, scenario, payload),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runPubSubWorker(
    int workerId,
    WampScenario scenario,
    String payload,
  ) async {
    final publisher = await _sessionFactory();
    final subscriber = await _sessionFactory();
    final subscription = await subscriber.subscribe(scenario.uri);
    final events = subscription.events.asBroadcastStream();
    final eventLogSub = events.listen(
      (event) => _logger.finer(
        'PUBSUB event received worker=$workerId '
        'args=${event.arguments} kwargs=${event.argumentsKeywords}',
      ),
    );
    final samples = <WampSample>[];
    try {
      for (var iteration = 0; iteration < scenario.iterations; iteration++) {
        final metadata = <String, Object?>{
          'worker': workerId,
          'iteration': iteration,
        };
        _logger.fine(
          'PUBSUB publish start worker=$workerId iteration=$iteration uri=${scenario.uri}',
        );
        final eventFuture = events
            .firstWhere((event) => _matches(event, workerId, iteration))
            .timeout(_eventTimeout);
        final start = DateTime.now();
        await publisher.publish(
          scenario.uri,
          arguments: [payload],
          argumentsKeywords: metadata,
          options: wamp_core.PublishOptions(acknowledge: true),
        );
        _logger.fine(
          'PUBSUB publish acked worker=$workerId iteration=$iteration uri=${scenario.uri}',
        );
        final event = await eventFuture;
        final latencyMs =
            DateTime.now().difference(start).inMicroseconds / 1000.0;
        samples.add(
          WampSample(
            worker: workerId,
            iteration: iteration,
            latencyMs: latencyMs,
            requestBytes: scenario.payloadBytes,
            responseBytes: scenario.payloadBytes,
          ),
        );
        _logger.fine(
          'PUBSUB publish done worker=$workerId iteration=$iteration uri=${scenario.uri} '
          'latency_ms=$latencyMs argsKeywords=${event.argumentsKeywords}',
        );
      }
    } on TimeoutException catch (error) {
      _logger.severe(
        'PUBSUB timed out waiting for event '
        'worker=$workerId iteration=${samples.length}/${scenario.iterations} '
        'uri=${scenario.uri} timeout=$_eventTimeout',
        error,
      );
      rethrow;
    } finally {
      await eventLogSub.cancel();
      await subscription.cancel();
      await subscriber.close();
      await publisher.close();
    }
    return samples;
  }

  bool _matches(WampEvent event, int workerId, int iteration) {
    final keywords = event.argumentsKeywords;
    if (keywords == null) {
      return false;
    }
    final worker = _asInt(keywords['worker']);
    final iter = _asInt(keywords['iteration']);
    return worker == workerId && iter == iteration;
  }

  int? _asInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final parsed = int.tryParse(value.toString());
    return parsed;
  }

  Future<List<WampSample>> _runRpcScenario(WampScenario scenario) async {
    final payload = _buildPayloadString(scenario.payloadBytes);
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runRpcWorker(workerId, scenario, payload),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runRpcWorker(
    int workerId,
    WampScenario scenario,
    String payload,
  ) async {
    final session = await _sessionFactory();
    final samples = <WampSample>[];
    try {
      for (var iteration = 0; iteration < scenario.iterations; iteration++) {
        _logger.fine(
          'RPC call start worker=$workerId iteration=$iteration uri=${scenario.uri}',
        );
        final start = DateTime.now();
        final resultStream = await session.call(
          scenario.uri,
          arguments: [payload],
        );
        await resultStream.first.timeout(
          _eventTimeout,
          onTimeout: () {
            _logger.severe(
              'RPC call timed out waiting for first result '
              'worker=$workerId iteration=$iteration uri=${scenario.uri}',
            );
            throw TimeoutException('rpc_call_timeout');
          },
        );
        final latencyMs =
            DateTime.now().difference(start).inMicroseconds / 1000.0;
        samples.add(
          WampSample(
            worker: workerId,
            iteration: iteration,
            latencyMs: latencyMs,
            requestBytes: scenario.payloadBytes,
            responseBytes: scenario.payloadBytes,
          ),
        );
        _logger.fine(
          'RPC call done worker=$workerId iteration=$iteration uri=${scenario.uri} '
          'latency_ms=$latencyMs',
        );
      }
    } on TimeoutException catch (error) {
      _logger.severe(
        'RPC call timed out worker=$workerId uri=${scenario.uri} '
        'iteration=${samples.length}/${scenario.iterations}',
        error,
      );
      rethrow;
    } finally {
      await session.close();
    }
    return samples;
  }

  String _buildPayloadString(int length) {
    if (length <= 0) {
      return '';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(65 + (i % 26));
    }
    return buffer.toString();
  }
}

class WampSubscription {
  WampSubscription({
    required Stream<WampEvent> events,
    required Future<void> Function() cancel,
  }) : _events = events,
       _onCancel = cancel;

  final Stream<WampEvent> _events;
  final Future<void> Function() _onCancel;

  Stream<WampEvent> get events => _events;

  Future<void> cancel() => _onCancel();
}

class WampEvent {
  WampEvent({this.arguments, this.argumentsKeywords});

  final List<dynamic>? arguments;
  final Map<String, Object?>? argumentsKeywords;
}

abstract class WampSession {
  Future<void> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.PublishOptions? options,
  });

  Future<WampSubscription> subscribe(
    String topic, {
    wamp_core.SubscribeOptions? options,
  });

  Future<Stream<dynamic>> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  });

  Future<void> close();
}

class RawSocketWampSessionFactory {
  RawSocketWampSessionFactory({
    required this.host,
    required this.port,
    required this.realmUri,
  });

  final String host;
  final int port;
  final String realmUri;

  Future<WampSession> call() async {
    final serializer = wamp_json.Serializer();
    final transport = wamp_socket.SocketTransport(
      host,
      port,
      serializer,
      wamp_socket.SocketHelper.serializationJson,
    );
    final client = wamp_client.Client(realm: realmUri, transport: transport);
    final session = await client.connect().first;
    return _ClientBackedWampSession(client, session);
  }
}

class _ClientBackedWampSession implements WampSession {
  _ClientBackedWampSession(this._client, this._session);

  final wamp_client.Client _client;
  final wamp_client.Session _session;

  @override
  Future<void> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.PublishOptions? options,
  }) async {
    await _session.publish(
      topic,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
    );
  }

  @override
  Future<WampSubscription> subscribe(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) async {
    final subscribed = await _session.subscribe(topic, options: options);
    final stream = subscribed.eventStream ?? const Stream.empty();
    return WampSubscription(
      events: stream.map(
        (event) => WampEvent(
          arguments: event.arguments,
          argumentsKeywords: event.argumentsKeywords,
        ),
      ),
      cancel: () => _session.unsubscribe(subscribed.subscriptionId),
    );
  }

  @override
  Future<Stream<dynamic>> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) async {
    final resultStream = _session.call(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
    );
    return resultStream;
  }

  @override
  Future<void> close() async {
    await _client.disconnect();
  }
}

class WampScenario {
  WampScenario({
    required this.mode,
    required this.uri,
    required this.iterations,
    required this.concurrency,
    required this.payloadBytes,
  });

  final WampMode mode;
  final String uri;
  final int iterations;
  final int concurrency;
  final int payloadBytes;

  factory WampScenario.fromJson(Map<String, Object?> json) {
    final rawMode = json['mode'];
    final uri = json['uri'];
    if (rawMode is! String || uri is! String || uri.trim().isEmpty) {
      throw FormatException('WAMP workload requires mode and uri');
    }
    final iterations = _readPositiveInt(json['iterations'], fallback: 1);
    final concurrency = _readPositiveInt(json['concurrency'], fallback: 1);
    final payloadBytes = _readPositiveInt(json['payload_bytes'], fallback: 0);
    return WampScenario(
      mode: WampMode.parse(rawMode),
      uri: uri,
      iterations: iterations,
      concurrency: concurrency,
      payloadBytes: payloadBytes,
    );
  }

  static int _readPositiveInt(Object? value, {required int fallback}) {
    if (value == null) {
      return fallback;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    throw FormatException('Expected integer, got $value');
  }
}

enum WampMode {
  pubsub,
  rpc;

  static WampMode parse(String raw) {
    switch (raw.toLowerCase()) {
      case 'pubsub':
      case 'wamp_pubsub':
        return WampMode.pubsub;
      case 'rpc':
      case 'wamp_rpc':
        return WampMode.rpc;
      default:
        throw FormatException('Unsupported WAMP mode "$raw"');
    }
  }
}

class WampSample {
  WampSample({
    required this.worker,
    required this.iteration,
    required this.latencyMs,
    required this.requestBytes,
    required this.responseBytes,
  });

  final int worker;
  final int iteration;
  final double latencyMs;
  final int requestBytes;
  final int responseBytes;

  Map<String, Object?> toJson() => {
    'worker': worker,
    'iteration': iteration,
    'latency_ms': latencyMs,
    'request_bytes': requestBytes,
    'response_bytes': responseBytes,
  };
}
