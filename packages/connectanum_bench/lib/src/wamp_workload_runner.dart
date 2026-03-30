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
    final subscription = await subscriber.subscribeLazyPayload(scenario.uri);
    final eventBuffer = WampEventBuffer();
    subscription.onEvent((event) {
      _logger.finer(
        'PUBSUB event received worker=$workerId '
        'args=${event.arguments} kwargs=${event.argumentsKeywords}',
      );
      eventBuffer.add(event);
    });
    final onRevoke = subscription.onRevoke;
    if (onRevoke != null) {
      unawaited(onRevoke.then((_) => eventBuffer.close()));
    }
    unawaited(
      subscriber.onDisconnect.then(
        (_) => eventBuffer.close(),
        onError: (error, stackTrace) =>
            eventBuffer.closeWithError(error, stackTrace),
      ),
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
      options: _buildPublishOptions(scenario),
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

  bool _matches(wamp_core.LazyEventPayload event, int workerId, int iteration) {
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
    final result = await session
        .callSingleLazyPayload(
          scenario.uri,
          arguments: [payload],
          options: _buildCallOptions(scenario),
        )
        .timeout(
          _eventTimeout,
          onTimeout: () {
            _logger.severe(
              'RPC call timed out waiting for final result '
              'worker=$workerId iteration=$iteration uri=${scenario.uri}',
            );
            throw TimeoutException('rpc_call_timeout');
          },
        );
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    _logger.fine(
      'RPC call done worker=$workerId iteration=$iteration uri=${scenario.uri} '
      'latency_ms=$latencyMs args=${result.arguments}',
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

  wamp_core.PublishOptions _buildPublishOptions(WampScenario scenario) {
    return wamp_core.PublishOptions(
      acknowledge: true,
      pptScheme: scenario.pptScheme,
      pptSerializer: _resolvePptSerializer(scenario),
    );
  }

  wamp_core.CallOptions? _buildCallOptions(WampScenario scenario) {
    if (scenario.pptScheme == null) {
      return null;
    }
    return wamp_core.CallOptions(
      pptScheme: scenario.pptScheme,
      pptSerializer: _resolvePptSerializer(scenario),
    );
  }

  String? _resolvePptSerializer(WampScenario scenario) {
    if (scenario.pptScheme == null) {
      return null;
    }
    return scenario.pptSerializer ?? scenario.serializer.name;
  }
}

class WampSubscription {
  WampSubscription({
    Stream<wamp_core.LazyEventPayload> Function()? eventStreamFactory,
    void Function(void Function(wamp_core.LazyEventPayload event) onEvent)?
    attachEventHandler,
    Future<void> Function()? onRevoke,
    required Future<void> Function() cancel,
  }) : _eventStreamFactory = eventStreamFactory,
       _attachEventHandler = attachEventHandler,
       _onRevoke = onRevoke,
       _onCancel = cancel;

  final Stream<wamp_core.LazyEventPayload> Function()? _eventStreamFactory;
  final void Function(void Function(wamp_core.LazyEventPayload event) onEvent)?
  _attachEventHandler;
  final Future<void> Function()? _onRevoke;
  final Future<void> Function() _onCancel;
  Stream<wamp_core.LazyEventPayload>? _events;

  Stream<wamp_core.LazyEventPayload> get events {
    return _events ??=
        _eventStreamFactory?.call() ??
        const Stream<wamp_core.LazyEventPayload>.empty();
  }

  Future<void>? get onRevoke => _onRevoke?.call();

  void onEvent(void Function(wamp_core.LazyEventPayload event) onEvent) {
    final attachEventHandler = _attachEventHandler;
    if (attachEventHandler != null) {
      attachEventHandler(onEvent);
      return;
    }
    events.listen(onEvent);
  }

  Future<void> cancel() => _onCancel();
}

class WampEventBuffer {
  final Queue<wamp_core.LazyEventPayload> _buffer =
      Queue<wamp_core.LazyEventPayload>();
  final Queue<_PendingWampEvent> _pending = Queue<_PendingWampEvent>();
  bool _closed = false;
  Object? _error;
  StackTrace? _stackTrace;

  void add(wamp_core.LazyEventPayload event) {
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

  Future<wamp_core.LazyEventPayload> nextWhere(
    bool Function(wamp_core.LazyEventPayload) matcher,
  ) {
    final replayBuffer = Queue<wamp_core.LazyEventPayload>();
    wamp_core.LazyEventPayload? matchedEvent;
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
      return Future<wamp_core.LazyEventPayload>.value(matchedEvent);
    }
    if (_error != null) {
      return Future<wamp_core.LazyEventPayload>.error(_error!, _stackTrace);
    }
    if (_closed) {
      return Future<wamp_core.LazyEventPayload>.error(StateError('No element'));
    }
    final completer = Completer<wamp_core.LazyEventPayload>();
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

  final bool Function(wamp_core.LazyEventPayload event) matcher;
  final Completer<wamp_core.LazyEventPayload> completer;
}

abstract class WampSession {
  Future<dynamic> get onDisconnect;

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

  Future<WampSubscription> subscribePayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  });

  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  });

  Future<Stream<dynamic>> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  });

  Future<dynamic> callSingle(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  });

  Future<wamp_core.ResultPayload> callSinglePayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  });

  Future<wamp_core.LazyResultPayload> callSingleLazyPayload(
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
    this.clientImplementation = WampClientImplementation.dart,
    this.ssl = false,
    this.allowInsecureCertificates = false,
    this.nativeLibraryPath,
  });

  final String host;
  final int port;
  final String realmUri;
  final WampSerializer serializer;
  final WampClientImplementation clientImplementation;
  final bool ssl;
  final bool allowInsecureCertificates;
  final String? nativeLibraryPath;

  Future<WampSession> call() async {
    final transport = switch (clientImplementation) {
      WampClientImplementation.dart => _buildDartTransport(),
      WampClientImplementation.native => _buildNativeTransport(),
    };
    final client = wamp_client.Client(realm: realmUri, transport: transport);
    final session = await client.connect().first;
    return _ClientBackedWampSession(client, session);
  }

  wamp_client.AbstractTransport _buildDartTransport() {
    final (transportSerializer, serializerType) = _rawSocketSerializerConfig(
      serializer,
    );
    return wamp_socket.SocketTransport(
      host,
      port,
      transportSerializer,
      serializerType,
      ssl: ssl,
      allowInsecureCertificates: allowInsecureCertificates,
    );
  }

  wamp_client.AbstractTransport _buildNativeTransport() {
    return switch (serializer) {
      WampSerializer.json =>
        wamp_client.NativeRawSocketTransport.withJsonSerializer(
          host,
          port,
          ssl: ssl,
          allowInsecureCertificates: allowInsecureCertificates,
          libraryPath: nativeLibraryPath,
        ),
      WampSerializer.msgpack =>
        wamp_client.NativeRawSocketTransport.withMsgpackSerializer(
          host,
          port,
          ssl: ssl,
          allowInsecureCertificates: allowInsecureCertificates,
          libraryPath: nativeLibraryPath,
        ),
      WampSerializer.cbor =>
        wamp_client.NativeRawSocketTransport.withCborSerializer(
          host,
          port,
          ssl: ssl,
          allowInsecureCertificates: allowInsecureCertificates,
          libraryPath: nativeLibraryPath,
        ),
    };
  }
}

class WebSocketWampSessionFactory {
  WebSocketWampSessionFactory({
    required this.url,
    required this.realmUri,
    this.serializer = WampSerializer.json,
    this.clientImplementation = WampClientImplementation.dart,
    this.headers = const <String, Object?>{},
    this.allowInsecureCertificates = false,
    this.nativeLibraryPath,
  });

  final String url;
  final String realmUri;
  final WampSerializer serializer;
  final WampClientImplementation clientImplementation;
  final Map<String, Object?> headers;
  final bool allowInsecureCertificates;
  final String? nativeLibraryPath;

  Future<WampSession> call() async {
    final transport = switch (clientImplementation) {
      WampClientImplementation.dart => _buildDartTransport(),
      WampClientImplementation.native => _buildNativeTransport(),
    };
    final client = wamp_client.Client(realm: realmUri, transport: transport);
    final session = await client.connect().first;
    return _ClientBackedWampSession(client, session);
  }

  wamp_client.AbstractTransport _buildDartTransport() {
    return switch (serializer) {
      WampSerializer.json => wamp_client.WebSocketTransport.withJsonSerializer(
        url,
        headers,
      ),
      WampSerializer.msgpack =>
        wamp_client.WebSocketTransport.withMsgpackSerializer(url, headers),
      WampSerializer.cbor => wamp_client.WebSocketTransport.withCborSerializer(
        url,
        headers,
      ),
    };
  }

  wamp_client.AbstractTransport _buildNativeTransport() {
    return switch (serializer) {
      WampSerializer.json =>
        wamp_client.NativeWebSocketTransport.withJsonSerializer(
          url,
          headers.cast<String, dynamic>(),
          allowInsecureCertificates,
          nativeLibraryPath,
        ),
      WampSerializer.msgpack =>
        wamp_client.NativeWebSocketTransport.withMsgpackSerializer(
          url,
          headers.cast<String, dynamic>(),
          allowInsecureCertificates,
          nativeLibraryPath,
        ),
      WampSerializer.cbor =>
        wamp_client.NativeWebSocketTransport.withCborSerializer(
          url,
          headers.cast<String, dynamic>(),
          allowInsecureCertificates,
          nativeLibraryPath,
        ),
    };
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
  Future<dynamic> get onDisconnect => _session.onDisconnect;

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
    return WampSubscription(
      eventStreamFactory: () =>
          (subscribed.eventStream ?? const Stream<wamp_core.Event>.empty()).map(
            (event) => event.toLazyEventPayload(anchor: event),
          ),
      attachEventHandler: (onEvent) {
        subscribed.onEvent(
          (event) => onEvent(event.toLazyEventPayload(anchor: event)),
        );
      },
      onRevoke: () => subscribed.onRevoke.then((_) {}),
      cancel: () => _session.unsubscribe(subscribed.subscriptionId),
    );
  }

  @override
  Future<WampSubscription> subscribePayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) async {
    final subscribed = await _session.subscribeLazyPayloadHandler(
      topic,
      (_) {},
      options: options,
    );
    return WampSubscription(
      attachEventHandler: subscribed.onLazyEventPayload,
      onRevoke: () => subscribed.onRevoke.then((_) {}),
      cancel: () => _session.unsubscribe(subscribed.subscriptionId),
    );
  }

  @override
  Future<WampSubscription> subscribeLazyPayload(
    String topic, {
    wamp_core.SubscribeOptions? options,
  }) async {
    final subscribed = await _session.subscribeLazyPayloadHandler(
      topic,
      (_) {},
      options: options,
    );
    return WampSubscription(
      attachEventHandler: subscribed.onLazyEventPayload,
      onRevoke: () => subscribed.onRevoke.then((_) {}),
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
  Future<dynamic> callSingle(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    return _session.callSingle(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
    );
  }

  @override
  Future<wamp_core.ResultPayload> callSinglePayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    return _session.callSinglePayload(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
    );
  }

  @override
  Future<wamp_core.LazyResultPayload> callSingleLazyPayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    return _session.callSingleLazyPayload(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
    );
  }

  @override
  Future<void> close() async {
    await _client.disconnect();
  }
}

class WampScenario {
  WampScenario({
    required this.transport,
    this.clientImplementation = WampClientImplementation.dart,
    required this.serializer,
    required this.mode,
    required this.uri,
    required this.iterations,
    required this.concurrency,
    this.inFlightPerSession = 1,
    required this.payloadBytes,
    this.pptScheme,
    this.pptSerializer,
  });

  final WampTransport transport;
  final WampClientImplementation clientImplementation;
  final WampSerializer serializer;
  final WampMode mode;
  final String uri;
  final int iterations;
  final int concurrency;
  final int inFlightPerSession;
  final int payloadBytes;
  final String? pptScheme;
  final String? pptSerializer;

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
      clientImplementation: WampClientImplementation.parse(json['client_impl']),
      serializer: WampSerializer.parse(rawSerializer),
      mode: WampMode.parse(rawMode),
      uri: uri,
      iterations: iterations,
      concurrency: concurrency,
      inFlightPerSession: inFlightPerSession,
      payloadBytes: payloadBytes,
      pptScheme: json['ppt_scheme'] as String?,
      pptSerializer: json['ppt_serializer'] as String?,
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

  Map<String, Object?> toJson() => {
    'transport': transport.name,
    'client_impl': clientImplementation.name,
    'serializer': serializer.name,
    'mode': mode.name,
    'uri': uri,
    'iterations': iterations,
    'concurrency': concurrency,
    'in_flight_per_session': inFlightPerSession,
    'payload_bytes': payloadBytes,
    if (pptScheme != null) 'ppt_scheme': pptScheme,
    if (pptSerializer != null) 'ppt_serializer': pptSerializer,
  };
}

enum WampClientImplementation {
  dart,
  native;

  static WampClientImplementation parse(Object? raw) {
    if (raw == null) {
      return WampClientImplementation.dart;
    }
    if (raw is! String) {
      throw FormatException('Unsupported WAMP client implementation "$raw"');
    }
    switch (raw.toLowerCase()) {
      case 'dart':
      case 'vm':
        return WampClientImplementation.dart;
      case 'native':
      case 'rust':
        return WampClientImplementation.native;
      default:
        throw FormatException('Unsupported WAMP client implementation "$raw"');
    }
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

  factory WampSample.fromJson(Map<String, Object?> json) {
    return WampSample(
      worker: _readJsonInt(json['worker']),
      iteration: _readJsonInt(json['iteration']),
      latencyMs: _readJsonDouble(json['latency_ms']),
      requestBytes: _readJsonInt(json['request_bytes']),
      responseBytes: _readJsonInt(json['response_bytes']),
    );
  }

  Map<String, Object?> toJson() => {
    'worker': worker,
    'iteration': iteration,
    'latency_ms': latencyMs,
    'request_bytes': requestBytes,
    'response_bytes': responseBytes,
  };
}

int _readJsonInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected integer, got $value');
}

double _readJsonDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected number, got $value');
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
