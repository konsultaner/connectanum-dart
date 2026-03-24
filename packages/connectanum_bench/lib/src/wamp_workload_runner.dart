import 'dart:async';
import 'dart:collection';

import 'package:connectanum_client/connectanum.dart' as wamp_client;
import 'package:connectanum_client/socket.dart' as wamp_socket;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/cbor_serializer.dart' as wamp_cbor;
import 'package:connectanum_core/json_serializer.dart' as wamp_json;
import 'package:connectanum_core/msgpack_serializer.dart' as wamp_msgpack;
import 'package:logging/logging.dart';

typedef WampSessionFactory =
    Future<WampSession> Function(WampScenario scenario);

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
    final publisher = await _sessionFactory(scenario);
    final subscriber = await _sessionFactory(scenario);
    final subscription = await subscriber.subscribe(scenario.uri);
    final eventBuffer = WampEventBuffer();
    final eventSub = subscription.events.listen(
      (event) {
        _logger.finer(
          'PUBSUB event received worker=$workerId '
          'args=${event.arguments} kwargs=${event.argumentsKeywords}',
        );
        eventBuffer.add(event);
      },
      onError: eventBuffer.closeWithError,
      onDone: eventBuffer.close,
    );
    final samples = <WampSample>[];
    try {
      samples.addAll(
        await _runWithInFlightLimit(
          iterations: scenario.iterations,
          maxInFlight: scenario.inFlightPerSession,
          launch: (iteration) => _runPubSubIteration(
            workerId,
            iteration,
            scenario,
            payload,
            eventBuffer,
            publisher,
          ),
        ),
      );
    } on TimeoutException catch (error) {
      _logger.severe(
        'PUBSUB timed out waiting for event '
        'worker=$workerId iteration=${samples.length}/${scenario.iterations} '
        'uri=${scenario.uri} timeout=$_eventTimeout',
        error,
      );
      rethrow;
    } finally {
      eventBuffer.close();
      await eventSub.cancel();
      await subscription.cancel();
      await subscriber.close();
      await publisher.close();
    }
    return samples;
  }

  Future<WampSample> _runPubSubIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String payload,
    WampEventBuffer eventBuffer,
    WampSession publisher,
  ) async {
    final metadata = <String, Object?>{
      'worker': workerId,
      'iteration': iteration,
    };
    _logger.fine(
      'PUBSUB publish start worker=$workerId iteration=$iteration uri=${scenario.uri}',
    );
    final eventFuture = eventBuffer
        .nextWhere((event) => _matches(event, workerId, iteration))
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
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    _logger.fine(
      'PUBSUB publish done worker=$workerId iteration=$iteration uri=${scenario.uri} '
      'latency_ms=$latencyMs argsKeywords=${event.argumentsKeywords}',
    );
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: scenario.payloadBytes,
      responseBytes: scenario.payloadBytes,
    );
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
    final session = await _sessionFactory(scenario);
    final samples = <WampSample>[];
    try {
      samples.addAll(
        await _runWithInFlightLimit(
          iterations: scenario.iterations,
          maxInFlight: scenario.inFlightPerSession,
          launch: (iteration) =>
              _runRpcIteration(workerId, iteration, scenario, payload, session),
        ),
      );
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

  Future<WampSample> _runRpcIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String payload,
    WampSession session,
  ) async {
    _logger.fine(
      'RPC call start worker=$workerId iteration=$iteration uri=${scenario.uri}',
    );
    final start = DateTime.now();
    final resultStream = await session.call(scenario.uri, arguments: [payload]);
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
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    _logger.fine(
      'RPC call done worker=$workerId iteration=$iteration uri=${scenario.uri} '
      'latency_ms=$latencyMs',
    );
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: scenario.payloadBytes,
      responseBytes: scenario.payloadBytes,
    );
  }

  Future<List<WampSample>> _runWithInFlightLimit({
    required int iterations,
    required int maxInFlight,
    required Future<WampSample> Function(int iteration) launch,
  }) async {
    final samples = <WampSample>[];
    final pending = <_PendingWampSample>[];
    final boundedInFlight = maxInFlight.clamp(1, iterations);
    var nextIteration = 0;
    while (nextIteration < iterations || pending.isNotEmpty) {
      while (nextIteration < iterations && pending.length < boundedInFlight) {
        final iteration = nextIteration;
        pending.add(
          _PendingWampSample(
            iteration: iteration,
            future: launch(iteration).then(
              (sample) =>
                  _CompletedWampSample(iteration: iteration, sample: sample),
            ),
          ),
        );
        nextIteration += 1;
      }
      final completed = await Future.any(pending.map((entry) => entry.future));
      pending.removeWhere((entry) => entry.iteration == completed.iteration);
      samples.add(completed.sample);
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

class WampEventBuffer {
  final Queue<WampEvent> _buffer = Queue<WampEvent>();
  final Queue<_PendingWampEvent> _pending = Queue<_PendingWampEvent>();
  bool _closed = false;
  Object? _error;
  StackTrace? _stackTrace;

  void add(WampEvent event) {
    for (final pending in _pending.toList(growable: false)) {
      if (pending.completer.isCompleted) {
        _pending.remove(pending);
        continue;
      }
      if (pending.matcher(event)) {
        _pending.remove(pending);
        pending.completer.complete(event);
        return;
      }
    }
    _buffer.addLast(event);
  }

  Future<WampEvent> nextWhere(bool Function(WampEvent) matcher) {
    final replayBuffer = Queue<WampEvent>();
    WampEvent? matchedEvent;
    while (_buffer.isNotEmpty) {
      final event = _buffer.removeFirst();
      if (matchedEvent == null && matcher(event)) {
        matchedEvent = event;
        continue;
      }
      replayBuffer.addLast(event);
    }
    _buffer.addAll(replayBuffer);
    if (matchedEvent != null) {
      return Future<WampEvent>.value(matchedEvent);
    }
    if (_error != null) {
      return Future<WampEvent>.error(_error!, _stackTrace);
    }
    if (_closed) {
      return Future<WampEvent>.error(StateError('No element'));
    }
    final completer = Completer<WampEvent>();
    _pending.addLast(_PendingWampEvent(matcher: matcher, completer: completer));
    return completer.future;
  }

  void close() {
    _closed = true;
    while (_pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('No element'));
      }
    }
  }

  void closeWithError(Object error, [StackTrace? stackTrace]) {
    _error = error;
    _stackTrace = stackTrace;
    _closed = true;
    while (_pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
  }
}

class _PendingWampEvent {
  _PendingWampEvent({required this.matcher, required this.completer});

  final bool Function(WampEvent event) matcher;
  final Completer<WampEvent> completer;
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
    this.serializer = WampSerializer.json,
    this.ssl = false,
    this.allowInsecureCertificates = false,
  });

  final String host;
  final int port;
  final String realmUri;
  final WampSerializer serializer;
  final bool ssl;
  final bool allowInsecureCertificates;

  Future<WampSession> call() async {
    final (transportSerializer, serializerType) = _rawSocketSerializerConfig(
      serializer,
    );
    final transport = wamp_socket.SocketTransport(
      host,
      port,
      transportSerializer,
      serializerType,
      ssl: ssl,
      allowInsecureCertificates: allowInsecureCertificates,
    );
    final client = wamp_client.Client(realm: realmUri, transport: transport);
    final session = await client.connect().first;
    return _ClientBackedWampSession(client, session);
  }
}

class WebSocketWampSessionFactory {
  WebSocketWampSessionFactory({
    required this.url,
    required this.realmUri,
    this.serializer = WampSerializer.json,
  });

  final String url;
  final String realmUri;
  final WampSerializer serializer;

  Future<WampSession> call() async {
    final transport = switch (serializer) {
      WampSerializer.json => wamp_client.WebSocketTransport.withJsonSerializer(
        url,
      ),
      WampSerializer.msgpack =>
        wamp_client.WebSocketTransport.withMsgpackSerializer(url),
      WampSerializer.cbor => wamp_client.WebSocketTransport.withCborSerializer(
        url,
      ),
    };
    final client = wamp_client.Client(realm: realmUri, transport: transport);
    final session = await client.connect().first;
    return _ClientBackedWampSession(client, session);
  }
}

(dynamic, int) _rawSocketSerializerConfig(WampSerializer serializer) {
  switch (serializer) {
    case WampSerializer.json:
      return (
        wamp_json.Serializer(),
        wamp_socket.SocketHelper.serializationJson,
      );
    case WampSerializer.msgpack:
      return (
        wamp_msgpack.Serializer(),
        wamp_socket.SocketHelper.serializationMsgpack,
      );
    case WampSerializer.cbor:
      return (
        wamp_cbor.Serializer(),
        wamp_socket.SocketHelper.serializationCbor,
      );
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
    required this.transport,
    required this.serializer,
    required this.mode,
    required this.uri,
    required this.iterations,
    required this.concurrency,
    this.inFlightPerSession = 1,
    required this.payloadBytes,
  });

  final WampTransport transport;
  final WampSerializer serializer;
  final WampMode mode;
  final String uri;
  final int iterations;
  final int concurrency;
  final int inFlightPerSession;
  final int payloadBytes;

  factory WampScenario.fromJson(Map<String, Object?> json) {
    final rawMode = json['mode'];
    final uri = json['uri'];
    if (rawMode is! String || uri is! String || uri.trim().isEmpty) {
      throw FormatException('WAMP workload requires mode and uri');
    }
    final rawTransport = json['transport'];
    final rawSerializer = json['serializer'];
    final iterations = _readPositiveInt(json['iterations'], fallback: 1);
    final concurrency = _readPositiveInt(json['concurrency'], fallback: 1);
    final inFlightPerSession = _readPositiveInt(
      json['in_flight_per_session'],
      fallback: 1,
    );
    final payloadBytes = _readPositiveInt(json['payload_bytes'], fallback: 0);
    return WampScenario(
      transport: WampTransport.parse(rawTransport),
      serializer: WampSerializer.parse(rawSerializer),
      mode: WampMode.parse(rawMode),
      uri: uri,
      iterations: iterations,
      concurrency: concurrency,
      inFlightPerSession: inFlightPerSession,
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

enum WampTransport {
  rawsocket,
  websocket;

  static WampTransport parse(Object? raw) {
    if (raw == null) {
      return WampTransport.rawsocket;
    }
    if (raw is! String) {
      throw FormatException('Unsupported WAMP transport "$raw"');
    }
    switch (raw.toLowerCase()) {
      case 'rawsocket':
      case 'raw':
      case 'socket':
        return WampTransport.rawsocket;
      case 'websocket':
      case 'ws':
        return WampTransport.websocket;
      default:
        throw FormatException('Unsupported WAMP transport "$raw"');
    }
  }
}

enum WampSerializer {
  json,
  msgpack,
  cbor;

  static WampSerializer parse(Object? raw) {
    if (raw == null) {
      return WampSerializer.json;
    }
    if (raw is! String) {
      throw FormatException('Unsupported WAMP serializer "$raw"');
    }
    switch (raw.toLowerCase()) {
      case 'json':
        return WampSerializer.json;
      case 'msgpack':
      case 'messagepack':
        return WampSerializer.msgpack;
      case 'cbor':
        return WampSerializer.cbor;
      default:
        throw FormatException('Unsupported WAMP serializer "$raw"');
    }
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

class _PendingWampSample {
  _PendingWampSample({required this.iteration, required this.future});

  final int iteration;
  final Future<_CompletedWampSample> future;
}

class _CompletedWampSample {
  _CompletedWampSample({required this.iteration, required this.sample});

  final int iteration;
  final WampSample sample;
}
