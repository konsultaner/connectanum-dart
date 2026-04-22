import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/connectanum.dart' as wamp_client;
import 'package:connectanum_client/socket.dart' as wamp_socket;
import 'package:connectanum_core/authentication.dart' as wamp_auth;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/cbor_serializer.dart' as wamp_cbor;
import 'package:connectanum_core/json_serializer.dart' as wamp_json;
import 'package:connectanum_core/msgpack_serializer.dart' as wamp_msgpack;
import 'package:logging/logging.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;

import 'wamp_echo_handler.dart';

typedef WampSessionFactory =
    Future<WampSession> Function(WampScenario scenario);

class WampWorkloadRunner {
  WampWorkloadRunner({
    required WampSessionFactory sessionFactory,
    Logger? logger,
    Duration eventTimeout = const Duration(seconds: 30),
    Duration cancelCleanupTimeout = const Duration(seconds: 2),
  }) : _sessionFactory = sessionFactory,
       _logger = logger ?? Logger('WampWorkloadRunner'),
       _eventTimeout = eventTimeout,
       _cancelCleanupTimeout = cancelCleanupTimeout;

  final WampSessionFactory _sessionFactory;
  final Logger _logger;
  final Duration _eventTimeout;
  final Duration _cancelCleanupTimeout;

  Future<List<WampSample>> run(WampScenario scenario) async {
    _logger.fine(
      'Running ${scenario.mode} workload '
      'uri=${scenario.uri} concurrency=${scenario.concurrency} '
      'iterations=${scenario.iterations}',
    );
    switch (scenario.mode) {
      case WampMode.authenticate:
        return _runAuthenticateScenario(scenario);
      case WampMode.pubsub:
        return _runPubSubScenario(scenario);
      case WampMode.rpc:
        return _runRpcScenario(scenario);
      case WampMode.publishAck:
        return _runPublishAckScenario(scenario);
      case WampMode.subscribeCycle:
        return _runSubscribeCycleScenario(scenario);
      case WampMode.registerCycle:
        return _runRegisterCycleScenario(scenario);
      case WampMode.cancelCycle:
        return _runCancelCycleScenario(scenario);
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

  Future<List<WampSample>> _runAuthenticateScenario(
    WampScenario scenario,
  ) async {
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runAuthenticateWorker(workerId, scenario),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runAuthenticateWorker(
    int workerId,
    WampScenario scenario,
  ) async {
    return _runWithInFlightLimit(
      iterations: scenario.iterations,
      maxInFlight: 1,
      launch: (iteration) =>
          _runAuthenticateIteration(workerId, iteration, scenario),
    );
  }

  Future<WampSample> _runAuthenticateIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
  ) async {
    final start = DateTime.now();
    final session = await _sessionFactory(scenario).timeout(
      _eventTimeout,
      onTimeout: () {
        _logger.severe(
          'Authenticate session open timed out '
          'worker=$workerId iteration=$iteration '
          'transport=${scenario.transport.name} realm=${scenario.realmUri}',
        );
        throw TimeoutException('wamp_auth_timeout');
      },
    );
    await session.close();
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: 0,
      responseBytes: 0,
    );
  }

  Future<List<WampSample>> _runPubSubWorker(
    int workerId,
    WampScenario scenario,
    String payload,
  ) async {
    final publisher = await _sessionFactory(scenario);
    final subscribers = <WampSession>[];
    final subscriptions = <WampSubscription>[];
    final eventBuffers = <WampEventBuffer>[];
    for (var peerIndex = 0; peerIndex < scenario.peerCount; peerIndex += 1) {
      final subscriber = await _sessionFactory(_peerScenario(scenario));
      final subscription = await subscriber.subscribeLazyPayload(scenario.uri);
      final eventBuffer = WampEventBuffer();
      subscription.onEvent((event) {
        _logger.finer(
          'PUBSUB event received worker=$workerId peer=$peerIndex '
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
      subscribers.add(subscriber);
      subscriptions.add(subscription);
      eventBuffers.add(eventBuffer);
    }
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
            eventBuffers,
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
      for (final eventBuffer in eventBuffers) {
        eventBuffer.close();
      }
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      for (final subscriber in subscribers) {
        await subscriber.close();
      }
      await publisher.close();
    }
    return samples;
  }

  Future<WampSample> _runPubSubIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String payload,
    List<WampEventBuffer> eventBuffers,
    WampSession publisher,
  ) async {
    final metadata = <String, Object?>{
      'worker': workerId,
      'iteration': iteration,
    };
    _logger.fine(
      'PUBSUB publish start worker=$workerId iteration=$iteration uri=${scenario.uri}',
    );
    final eventFutures = [
      for (final eventBuffer in eventBuffers)
        eventBuffer
            .nextWhere((event) => _matches(event, workerId, iteration))
            .timeout(_eventTimeout),
    ];
    final start = DateTime.now();
    await publisher.publishLazyPayload(
      scenario.uri,
      payload: _buildLazyPayload(
        scenario,
        arguments: [payload],
        argumentsKeywords: metadata,
      ),
      options: _buildPublishOptions(scenario),
    );
    _logger.fine(
      'PUBSUB publish acked worker=$workerId iteration=$iteration uri=${scenario.uri}',
    );
    await Future.wait(eventFutures);
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    _logger.fine(
      'PUBSUB publish done worker=$workerId iteration=$iteration uri=${scenario.uri} '
      'latency_ms=$latencyMs fanout=${scenario.peerCount}',
    );
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: scenario.payloadBytes,
      responseBytes: scenario.payloadBytes * scenario.peerCount,
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
    WampSession? calleeSession;
    WampRegistration? registration;
    var procedure = scenario.uri;
    if (scenario.peerSerializer != null) {
      procedure = _externalProcedureUri(scenario.uri, workerId);
      calleeSession = await _sessionFactory(_peerScenario(scenario));
      registration = await calleeSession.registerLazyPayloadHandler(
        procedure,
        (invocation) => respondEchoLazyInvocation(invocation, logger: _logger),
      );
    }
    final samples = <WampSample>[];
    try {
      samples.addAll(
        await _runWithInFlightLimit(
          iterations: scenario.iterations,
          maxInFlight: scenario.inFlightPerSession,
          launch: (iteration) => _runRpcIteration(
            workerId,
            iteration,
            scenario,
            procedure,
            payload,
            session,
          ),
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
      await registration?.cancel();
      await calleeSession?.close();
      await session.close();
    }
    return samples;
  }

  Future<WampSample> _runRpcIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String procedure,
    String payload,
    WampSession session,
  ) async {
    _logger.fine(
      'RPC call start worker=$workerId iteration=$iteration uri=$procedure',
    );
    final start = DateTime.now();
    final result = await session
        .callSingleWithLazyPayload(
          procedure,
          payload: _buildLazyPayload(scenario, arguments: [payload]),
          options: _buildCallOptions(scenario),
        )
        .timeout(
          _eventTimeout,
          onTimeout: () {
            _logger.severe(
              'RPC call timed out waiting for final result '
              'worker=$workerId iteration=$iteration uri=$procedure',
            );
            throw TimeoutException('rpc_call_timeout');
          },
        );
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    _logger.fine(
      'RPC call done worker=$workerId iteration=$iteration uri=$procedure '
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

  Future<List<WampSample>> _runPublishAckScenario(WampScenario scenario) async {
    final payload = _buildPayloadString(scenario.payloadBytes);
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runPublishAckWorker(workerId, scenario, payload),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runPublishAckWorker(
    int workerId,
    WampScenario scenario,
    String payload,
  ) async {
    final publisher = await _sessionFactory(scenario);
    try {
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) => _runPublishAckIteration(
          workerId,
          iteration,
          scenario,
          payload,
          publisher,
        ),
      );
    } finally {
      await publisher.close();
    }
  }

  Future<WampSample> _runPublishAckIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String payload,
    WampSession publisher,
  ) async {
    final topic = _iterationUri(scenario.uri, workerId, iteration);
    final start = DateTime.now();
    await publisher.publishLazyPayload(
      topic,
      payload: _buildLazyPayload(
        scenario,
        arguments: payload.isEmpty ? null : [payload],
      ),
      options: _buildControlPublishOptions(scenario),
    );
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: scenario.payloadBytes,
      responseBytes: 0,
    );
  }

  Future<List<WampSample>> _runSubscribeCycleScenario(
    WampScenario scenario,
  ) async {
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runSubscribeCycleWorker(workerId, scenario),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runSubscribeCycleWorker(
    int workerId,
    WampScenario scenario,
  ) async {
    final session = await _sessionFactory(scenario);
    try {
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) =>
            _runSubscribeCycleIteration(workerId, iteration, scenario, session),
      );
    } finally {
      await session.close();
    }
  }

  Future<WampSample> _runSubscribeCycleIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    WampSession session,
  ) async {
    final topic = _iterationUri(scenario.uri, workerId, iteration);
    final start = DateTime.now();
    final subscription = await session.subscribeLazyPayload(
      topic,
      options: _buildControlSubscribeOptions(scenario),
    );
    await subscription.cancel();
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: 0,
      responseBytes: 0,
    );
  }

  Future<List<WampSample>> _runRegisterCycleScenario(
    WampScenario scenario,
  ) async {
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runRegisterCycleWorker(workerId, scenario),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runRegisterCycleWorker(
    int workerId,
    WampScenario scenario,
  ) async {
    final session = await _sessionFactory(scenario);
    try {
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) =>
            _runRegisterCycleIteration(workerId, iteration, scenario, session),
      );
    } finally {
      await session.close();
    }
  }

  Future<WampSample> _runRegisterCycleIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    WampSession session,
  ) async {
    final procedure = _iterationUri(scenario.uri, workerId, iteration);
    final start = DateTime.now();
    final registration = await session.registerLazyPayloadHandler(
      procedure,
      (_) {},
      options: _buildControlRegisterOptions(scenario),
    );
    await registration.cancel();
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: 0,
      responseBytes: 0,
    );
  }

  Future<List<WampSample>> _runCancelCycleScenario(
    WampScenario scenario,
  ) async {
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runCancelCycleWorker(workerId, scenario),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runCancelCycleWorker(
    int workerId,
    WampScenario scenario,
  ) async {
    final caller = await _sessionFactory(scenario).timeout(
      _eventTimeout,
      onTimeout: () {
        _logger.severe(
          'Cancel-cycle caller session open timed out '
          'worker=$workerId transport=${scenario.transport.name} '
          'serializer=${scenario.serializer.name}',
        );
        throw TimeoutException('cancel_caller_open_timeout');
      },
    );
    final callee = await _sessionFactory(_peerScenario(scenario)).timeout(
      _eventTimeout,
      onTimeout: () {
        _logger.severe(
          'Cancel-cycle callee session open timed out '
          'worker=$workerId transport=${scenario.transport.name} '
          'serializer=${_peerScenario(scenario).serializer.name}',
        );
        throw TimeoutException('cancel_callee_open_timeout');
      },
    );
    final procedure = _externalProcedureUri(scenario.uri, workerId);
    final registration = await callee
        .registerLazyPayloadHandler(
          procedure,
          (_) {},
          options: _buildControlRegisterOptions(scenario),
        )
        .timeout(
          _eventTimeout,
          onTimeout: () {
            _logger.severe(
              'Cancel-cycle registration timed out '
              'worker=$workerId uri=$procedure',
            );
            throw TimeoutException('cancel_register_timeout');
          },
        );
    try {
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) =>
            _runCancelCycleIteration(workerId, iteration, procedure, caller),
      );
    } finally {
      try {
        await registration.cancel().timeout(_cancelCleanupTimeout);
      } on TimeoutException {
        _logger.warning(
          'Cancel-cycle registration cleanup timed out for $procedure; '
          'closing sessions to force teardown of interrupted invocations.',
        );
      }
      await callee.close();
      await caller.close();
    }
  }

  Future<WampSample> _runCancelCycleIteration(
    int workerId,
    int iteration,
    String procedure,
    WampSession caller,
  ) async {
    final start = DateTime.now();
    await caller
        .cancelingCall(
          procedure,
          argumentsKeywords: <String, Object?>{
            'worker': workerId,
            'iteration': iteration,
          },
          cancelMode: wamp_core.CancelOptions.modeKillNoWait,
        )
        .timeout(
          _eventTimeout,
          onTimeout: () {
            _logger.severe(
              'Cancel-cycle call timed out waiting for cancellation '
              'worker=$workerId iteration=$iteration uri=$procedure',
            );
            throw TimeoutException('cancel_call_timeout');
          },
        );
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: 0,
      responseBytes: 0,
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

  wamp_core.PublishOptions _buildControlPublishOptions(WampScenario scenario) {
    final options = wamp_core.PublishOptions(
      acknowledge: true,
      excludeMe: true,
      discloseMe: true,
      pptScheme: scenario.pptScheme,
      pptSerializer: _resolvePptSerializer(scenario),
    );
    _applyControlCustomFields(options, scenario);
    return options;
  }

  wamp_core.SubscribeOptions _buildControlSubscribeOptions(
    WampScenario scenario,
  ) {
    final options = wamp_core.SubscribeOptions(
      match: wamp_core.SubscribeOptions.matchPrefix,
      metaTopic: 'bench.control.meta',
      getRetained: true,
    );
    _applyControlCustomFields(options, scenario);
    return options;
  }

  wamp_core.RegisterOptions _buildControlRegisterOptions(
    WampScenario scenario,
  ) {
    final options = wamp_core.RegisterOptions(
      discloseCaller: true,
      match: wamp_core.RegisterOptions.matchPrefix,
      invoke: wamp_core.RegisterOptions.invocationPolicyRoundRobin,
    );
    _applyControlCustomFields(options, scenario);
    return options;
  }

  void _applyControlCustomFields(
    wamp_core.CustomFieldContainer options,
    WampScenario scenario,
  ) {
    if (!scenario.controlCustomFields) {
      return;
    }
    options.setCustomField('_trace', 'bench.control.${scenario.mode.wireName}');
    options.setCustomField('_serializer', scenario.serializer.name);
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

  wamp_core.LazyMessagePayload _buildLazyPayload(
    WampScenario scenario, {
    required List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
  }) {
    final encoding = switch (scenario.serializer) {
      WampSerializer.json => wamp_core.LazyPayloadEncoding.json,
      WampSerializer.msgpack => wamp_core.LazyPayloadEncoding.messagePack,
      WampSerializer.cbor => wamp_core.LazyPayloadEncoding.cbor,
    };
    final argsBytes = arguments == null
        ? null
        : _encodePayloadFragment(scenario.serializer, arguments);
    final kwargsMap = argumentsKeywords?.cast<String, dynamic>();
    final kwargsBytes = kwargsMap == null
        ? null
        : _encodePayloadFragment(scenario.serializer, kwargsMap);
    return wamp_core.LazyMessagePayload.encoded(
      encoding: encoding,
      argumentsBytes: argsBytes,
      argumentsKeywordsBytes: kwargsBytes,
      argumentsDecoder: argsBytes == null ? null : (_) => arguments!,
      argumentsKeywordsDecoder: kwargsBytes == null ? null : (_) => kwargsMap!,
      arguments: argsBytes == null ? arguments : null,
      argumentsKeywords: kwargsBytes == null ? kwargsMap : null,
    );
  }

  Uint8List _encodePayloadFragment(WampSerializer serializer, Object? value) {
    return switch (serializer) {
      WampSerializer.json => Uint8List.fromList(utf8.encode(jsonEncode(value))),
      WampSerializer.msgpack => msgpack_dart.serialize(value),
      WampSerializer.cbor => Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue(value)),
      ),
    };
  }

  WampScenario _peerScenario(WampScenario scenario) {
    final peerSerializer = scenario.peerSerializer;
    if (peerSerializer == null) {
      return scenario;
    }
    return scenario.copyWith(serializer: peerSerializer, peerSerializer: null);
  }

  String _externalProcedureUri(String baseUri, int workerId) {
    return '$baseUri.worker.$workerId';
  }

  String _iterationUri(String baseUri, int workerId, int iteration) {
    return '$baseUri.$workerId.$iteration';
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

  Future<WampRegistration> registerLazyPayloadHandler(
    String procedure,
    FutureOr<void> Function(wamp_core.LazyInvocationPayload invocation)
    onInvoke, {
    wamp_core.RegisterOptions? options,
  });

  Future<void> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.PublishOptions? options,
  });

  Future<void> publishLazyPayload(
    String topic, {
    required wamp_core.LazyMessagePayload payload,
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

  Future<wamp_core.LazyResultPayload> callSingleWithLazyPayload(
    String procedure, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.CallOptions? options,
  });

  Future<void> cancelingCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    required String cancelMode,
    wamp_core.CallOptions? options,
  });

  Future<void> close();
}

class WampRegistration {
  WampRegistration({required Future<void> Function() cancel})
    : _cancel = cancel;

  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

class RawSocketWampSessionFactory {
  RawSocketWampSessionFactory({
    required this.host,
    required this.port,
    required this.realmUri,
    this.authId,
    this.authenticationMethods,
    this.serializer = WampSerializer.json,
    this.clientImplementation = WampClientImplementation.dart,
    this.ssl = false,
    this.allowInsecureCertificates = false,
    this.nativeLibraryPath,
  });

  final String host;
  final int port;
  final String realmUri;
  final String? authId;
  final List<wamp_auth.AbstractAuthentication>? authenticationMethods;
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
    final client = wamp_client.Client(
      realm: realmUri,
      transport: transport,
      authId: authId,
      authenticationMethods: authenticationMethods,
    );
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
    this.authId,
    this.authenticationMethods,
    this.serializer = WampSerializer.json,
    this.clientImplementation = WampClientImplementation.dart,
    this.headers = const <String, Object?>{},
    this.allowInsecureCertificates = false,
    this.websocketFragmentSize,
    this.nativeLibraryPath,
  });

  final String url;
  final String realmUri;
  final String? authId;
  final List<wamp_auth.AbstractAuthentication>? authenticationMethods;
  final WampSerializer serializer;
  final WampClientImplementation clientImplementation;
  final Map<String, Object?> headers;
  final bool allowInsecureCertificates;
  final int? websocketFragmentSize;
  final String? nativeLibraryPath;

  Future<WampSession> call() async {
    final transport = switch (clientImplementation) {
      WampClientImplementation.dart => _buildDartTransport(),
      WampClientImplementation.native => _buildNativeTransport(),
    };
    final client = wamp_client.Client(
      realm: realmUri,
      transport: transport,
      authId: authId,
      authenticationMethods: authenticationMethods,
    );
    final session = await client.connect().first;
    return _ClientBackedWampSession(client, session);
  }

  wamp_client.AbstractTransport _buildDartTransport() {
    return switch (serializer) {
      WampSerializer.json => wamp_client.WebSocketTransport.withJsonSerializer(
        url,
        headers,
        allowInsecureCertificates,
      ),
      WampSerializer.msgpack =>
        wamp_client.WebSocketTransport.withMsgpackSerializer(
          url,
          headers,
          allowInsecureCertificates,
        ),
      WampSerializer.cbor => wamp_client.WebSocketTransport.withCborSerializer(
        url,
        headers,
        allowInsecureCertificates,
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
          websocketFragmentSize,
        ),
      WampSerializer.msgpack =>
        wamp_client.NativeWebSocketTransport.withMsgpackSerializer(
          url,
          headers.cast<String, dynamic>(),
          allowInsecureCertificates,
          nativeLibraryPath,
          websocketFragmentSize,
        ),
      WampSerializer.cbor =>
        wamp_client.NativeWebSocketTransport.withCborSerializer(
          url,
          headers.cast<String, dynamic>(),
          allowInsecureCertificates,
          nativeLibraryPath,
          websocketFragmentSize,
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

List<wamp_auth.AbstractAuthentication>? authenticationMethodsForScenario(
  WampScenario scenario,
) {
  switch (scenario.authMethod.toLowerCase()) {
    case '':
    case 'anonymous':
      return null;
    case 'ticket':
      final secret = scenario.authSecret;
      if (secret == null || secret.isEmpty) {
        throw StateError('ticket WAMP auth requires authSecret');
      }
      return <wamp_auth.AbstractAuthentication>[
        wamp_auth.TicketAuthentication(secret),
      ];
    case 'wampcra':
    case 'cra':
      final secret = scenario.authSecret;
      if (secret == null || secret.isEmpty) {
        throw StateError('WAMP-CRA auth requires authSecret');
      }
      return <wamp_auth.AbstractAuthentication>[
        wamp_auth.CraAuthentication(secret),
      ];
    case 'wamp-scram':
    case 'scram':
      final secret = scenario.authSecret;
      if (secret == null || secret.isEmpty) {
        throw StateError('SCRAM auth requires authSecret');
      }
      return <wamp_auth.AbstractAuthentication>[
        wamp_auth.ScramAuthentication(secret),
      ];
    default:
      throw StateError('Unsupported WAMP auth method ${scenario.authMethod}');
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
  Future<void> publishLazyPayload(
    String topic, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.PublishOptions? options,
  }) async {
    await _session.publishLazyPayload(
      topic,
      payload: payload,
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
  Future<WampRegistration> registerLazyPayloadHandler(
    String procedure,
    FutureOr<void> Function(wamp_core.LazyInvocationPayload invocation)
    onInvoke, {
    wamp_core.RegisterOptions? options,
  }) async {
    final registered = await _session.registerLazyPayloadHandler(
      procedure,
      onInvoke,
      options: options,
    );
    return WampRegistration(
      cancel: () => _session.unregister(registered.registrationId),
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
  Future<wamp_core.LazyResultPayload> callSingleWithLazyPayload(
    String procedure, {
    required wamp_core.LazyMessagePayload payload,
    wamp_core.CallOptions? options,
  }) {
    return _session.callSingleLazyPayloadView(
      procedure,
      payload: payload,
      options: options,
    );
  }

  @override
  Future<void> cancelingCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    required String cancelMode,
    wamp_core.CallOptions? options,
  }) async {
    final cancelCompleter = Completer<String>();
    final stream = _session.call(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
      cancelCompleter: cancelCompleter,
    );
    final completion = Completer<void>();
    late final StreamSubscription<dynamic> subscription;
    subscription = stream.listen(
      (_) {
        if (!completion.isCompleted) {
          completion.completeError(
            StateError('Cancelled call unexpectedly produced a result'),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completion.isCompleted) {
          completion.complete();
        }
      },
      onDone: () {
        if (!completion.isCompleted) {
          completion.completeError(
            StateError('Cancelled call completed without an error'),
          );
        }
      },
    );
    cancelCompleter.complete(cancelMode);
    try {
      await completion.future;
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> close() async {
    await _client.disconnect();
  }
}

class WampScenario {
  WampScenario({
    this.realmUri = 'bench.control',
    this.authMethod = 'anonymous',
    this.authId,
    this.authSecret,
    this.secureTransport = false,
    required this.transport,
    this.clientImplementation = WampClientImplementation.dart,
    required this.serializer,
    this.peerSerializer,
    required this.mode,
    required this.uri,
    required this.iterations,
    required this.concurrency,
    this.inFlightPerSession = 1,
    this.peerCount = 1,
    required this.payloadBytes,
    this.websocketFragmentSize,
    this.controlCustomFields = false,
    this.pptScheme,
    this.pptSerializer,
  });

  final String realmUri;
  final String authMethod;
  final String? authId;
  final String? authSecret;
  final bool secureTransport;
  final WampTransport transport;
  final WampClientImplementation clientImplementation;
  final WampSerializer serializer;
  final WampSerializer? peerSerializer;
  final WampMode mode;
  final String uri;
  final int iterations;
  final int concurrency;
  final int inFlightPerSession;
  final int peerCount;
  final int payloadBytes;
  final int? websocketFragmentSize;
  final bool controlCustomFields;
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
    final rawRealm = json['realm'];
    final rawAuthMethod = json['auth_method'];
    final rawAuthId = json['auth_id'];
    final rawAuthSecret = json['auth_secret'];
    final iterations = _readPositiveInt(json['iterations'], fallback: 1);
    final concurrency = _readPositiveInt(json['concurrency'], fallback: 1);
    final inFlightPerSession = _readPositiveInt(
      json['in_flight_per_session'],
      fallback: 1,
    );
    final peerCount = _readPositiveInt(json['peer_count'], fallback: 1);
    final payloadBytes = _readPositiveInt(json['payload_bytes'], fallback: 0);
    return WampScenario(
      realmUri: rawRealm is String && rawRealm.trim().isNotEmpty
          ? rawRealm
          : 'bench.control',
      authMethod: rawAuthMethod is String && rawAuthMethod.trim().isNotEmpty
          ? rawAuthMethod
          : 'anonymous',
      authId: rawAuthId is String && rawAuthId.trim().isNotEmpty
          ? rawAuthId
          : null,
      authSecret: rawAuthSecret is String && rawAuthSecret.trim().isNotEmpty
          ? rawAuthSecret
          : null,
      secureTransport: json['secure_transport'] == true,
      transport: WampTransport.parse(rawTransport),
      clientImplementation: WampClientImplementation.parse(json['client_impl']),
      serializer: WampSerializer.parse(rawSerializer),
      peerSerializer: WampSerializer.tryParse(json['peer_serializer']),
      mode: WampMode.parse(rawMode),
      uri: uri,
      iterations: iterations,
      concurrency: concurrency,
      inFlightPerSession: inFlightPerSession,
      peerCount: peerCount,
      payloadBytes: payloadBytes,
      websocketFragmentSize: _readOptionalPositiveInt(
        json['websocket_fragment_size'],
      ),
      controlCustomFields: json['control_custom_fields'] == true,
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

  static int? _readOptionalPositiveInt(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = _readPositiveInt(value, fallback: 0);
    return parsed > 0 ? parsed : null;
  }

  Map<String, Object?> toJson() => {
    'realm': realmUri,
    'auth_method': authMethod,
    if (authId != null) 'auth_id': authId,
    if (authSecret != null) 'auth_secret': authSecret,
    if (secureTransport) 'secure_transport': true,
    'transport': transport.name,
    'client_impl': clientImplementation.name,
    'serializer': serializer.name,
    if (peerSerializer != null) 'peer_serializer': peerSerializer!.name,
    'mode': mode.wireName,
    'uri': uri,
    'iterations': iterations,
    'concurrency': concurrency,
    'in_flight_per_session': inFlightPerSession,
    'peer_count': peerCount,
    'payload_bytes': payloadBytes,
    if (websocketFragmentSize != null)
      'websocket_fragment_size': websocketFragmentSize,
    if (controlCustomFields) 'control_custom_fields': true,
    if (pptScheme != null) 'ppt_scheme': pptScheme,
    if (pptSerializer != null) 'ppt_serializer': pptSerializer,
  };

  WampScenario copyWith({
    String? realmUri,
    String? authMethod,
    Object? authId = _copySentinel,
    Object? authSecret = _copySentinel,
    bool? secureTransport,
    WampTransport? transport,
    WampClientImplementation? clientImplementation,
    WampSerializer? serializer,
    Object? peerSerializer = _copySentinel,
    WampMode? mode,
    String? uri,
    int? iterations,
    int? concurrency,
    int? inFlightPerSession,
    int? peerCount,
    int? payloadBytes,
    Object? websocketFragmentSize = _copySentinel,
    bool? controlCustomFields,
    Object? pptScheme = _copySentinel,
    Object? pptSerializer = _copySentinel,
  }) {
    return WampScenario(
      realmUri: realmUri ?? this.realmUri,
      authMethod: authMethod ?? this.authMethod,
      authId: identical(authId, _copySentinel)
          ? this.authId
          : authId as String?,
      authSecret: identical(authSecret, _copySentinel)
          ? this.authSecret
          : authSecret as String?,
      secureTransport: secureTransport ?? this.secureTransport,
      transport: transport ?? this.transport,
      clientImplementation: clientImplementation ?? this.clientImplementation,
      serializer: serializer ?? this.serializer,
      peerSerializer: identical(peerSerializer, _copySentinel)
          ? this.peerSerializer
          : peerSerializer as WampSerializer?,
      mode: mode ?? this.mode,
      uri: uri ?? this.uri,
      iterations: iterations ?? this.iterations,
      concurrency: concurrency ?? this.concurrency,
      inFlightPerSession: inFlightPerSession ?? this.inFlightPerSession,
      peerCount: peerCount ?? this.peerCount,
      payloadBytes: payloadBytes ?? this.payloadBytes,
      websocketFragmentSize: identical(websocketFragmentSize, _copySentinel)
          ? this.websocketFragmentSize
          : websocketFragmentSize as int?,
      controlCustomFields: controlCustomFields ?? this.controlCustomFields,
      pptScheme: identical(pptScheme, _copySentinel)
          ? this.pptScheme
          : pptScheme as String?,
      pptSerializer: identical(pptSerializer, _copySentinel)
          ? this.pptSerializer
          : pptSerializer as String?,
    );
  }
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

  static WampSerializer? tryParse(Object? raw) {
    if (raw == null) {
      return null;
    }
    return parse(raw);
  }

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

const Object _copySentinel = Object();

enum WampMode {
  authenticate,
  pubsub,
  rpc,
  publishAck,
  subscribeCycle,
  registerCycle,
  cancelCycle;

  String get wireName => switch (this) {
    WampMode.authenticate => 'authenticate',
    WampMode.pubsub => 'pubsub',
    WampMode.rpc => 'rpc',
    WampMode.publishAck => 'publish_ack',
    WampMode.subscribeCycle => 'subscribe_cycle',
    WampMode.registerCycle => 'register_cycle',
    WampMode.cancelCycle => 'cancel_cycle',
  };

  static WampMode parse(String raw) {
    switch (raw.toLowerCase()) {
      case 'pubsub':
      case 'wamp_pubsub':
        return WampMode.pubsub;
      case 'authenticate':
      case 'auth':
      case 'wamp_auth':
        return WampMode.authenticate;
      case 'rpc':
      case 'wamp_rpc':
        return WampMode.rpc;
      case 'publish_ack':
      case 'publishack':
      case 'wamp_publish_ack':
        return WampMode.publishAck;
      case 'subscribe_cycle':
      case 'subscribecycle':
      case 'wamp_subscribe_cycle':
        return WampMode.subscribeCycle;
      case 'register_cycle':
      case 'registercycle':
      case 'wamp_register_cycle':
        return WampMode.registerCycle;
      case 'cancel_cycle':
      case 'cancelcycle':
      case 'wamp_cancel_cycle':
        return WampMode.cancelCycle;
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
