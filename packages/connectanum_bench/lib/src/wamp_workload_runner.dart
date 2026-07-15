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
typedef WampE2eeProviderFactory = wamp_core.WampE2eeProvider Function();

WampE2eeProviderFactory? e2eeProviderFactoryForScenario(WampScenario scenario) {
  if (scenario.pptScheme != wamp_core.ConnectanumE2eeProfile.scheme) {
    return null;
  }
  final keyId = scenario.pptKeyId;
  final cipher = scenario.pptCipher;
  if (keyId == null || keyId.isEmpty || cipher == null || cipher.isEmpty) {
    throw StateError(
      'WAMP E2EE benchmark scenarios require ppt_cipher and ppt_keyid',
    );
  }
  const key = <int>[
    0x63,
    0x6f,
    0x6e,
    0x6e,
    0x65,
    0x63,
    0x74,
    0x61,
    0x6e,
    0x75,
    0x6d,
    0x2d,
    0x65,
    0x32,
    0x65,
    0x65,
    0x2d,
    0x62,
    0x65,
    0x6e,
    0x63,
    0x68,
    0x2d,
    0x6b,
    0x65,
    0x79,
    0x2d,
    0x76,
    0x30,
    0x30,
    0x30,
    0x31,
  ];
  return switch ((scenario.clientImplementation, cipher)) {
    (
      WampClientImplementation.dart,
      wamp_core.ConnectanumE2eeProfile.xsalsa20Poly1305,
    ) =>
      () => wamp_core.WampCborXsalsa20Poly1305Provider.single(
        keyId: keyId,
        key: key,
      ),
    (
      WampClientImplementation.dart,
      wamp_core.ConnectanumE2eeProfile.aes256Gcm,
    ) =>
      () => wamp_core.WampCborAes256GcmProvider.single(keyId: keyId, key: key),
    (
      WampClientImplementation.native,
      wamp_core.ConnectanumE2eeProfile.xsalsa20Poly1305,
    ) =>
      () => wamp_client.NativeWampCborXsalsa20Poly1305Provider.single(
        keyId: keyId,
        key: key,
      ),
    (
      WampClientImplementation.native,
      wamp_core.ConnectanumE2eeProfile.aes256Gcm,
    ) =>
      () => wamp_client.NativeWampCborAes256GcmProvider.single(
        keyId: keyId,
        key: key,
      ),
    _ => throw StateError('Unsupported WAMP E2EE benchmark cipher $cipher'),
  };
}

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
      case WampMode.progressiveRpc:
        return _runProgressiveRpcScenario(scenario);
      case WampMode.timeoutRpc:
        return _runTimeoutRpcScenario(scenario);
      case WampMode.metaApi:
        return _runMetaApiScenario(scenario);
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
    final session = await _openSession(
      scenario,
      workerId: workerId,
      iteration: iteration,
      timeoutLabel: 'wamp_auth',
      logLabel: 'Authenticate',
    );
    await _runTimedOperation(
      session.close(),
      timeout: _eventTimeout,
      timeoutLabel: 'wamp_auth_close_timeout',
      logLabel: 'Authenticate close',
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
      ),
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

  Future<List<WampSample>> _runPubSubWorker(
    int workerId,
    WampScenario scenario,
    String payload,
  ) async {
    WampSession? publisher;
    final subscribers = <WampSession>[];
    final subscriptions = <WampSubscription>[];
    final eventBuffers = <WampEventBuffer>[];
    final samples = <WampSample>[];
    try {
      publisher = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'pubsub_publisher',
        logLabel: 'PUBSUB publisher',
      );
      for (var peerIndex = 0; peerIndex < scenario.peerCount; peerIndex += 1) {
        final subscriberScenario = _peerScenario(scenario);
        final subscriber = await _openSession(
          subscriberScenario,
          workerId: workerId,
          peerIndex: peerIndex,
          timeoutLabel: 'pubsub_subscriber',
          logLabel: 'PUBSUB subscriber',
        );
        subscribers.add(subscriber);
        final subscription = await _runTimedOperation(
          subscriber.subscribeLazyPayload(scenario.uri),
          timeout: _eventTimeout,
          timeoutLabel: 'pubsub_subscribe_timeout',
          logLabel: 'PUBSUB subscribe',
          details: _operationDetails(
            subscriberScenario,
            workerId: workerId,
            peerIndex: peerIndex,
          ),
        );
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
        subscriptions.add(subscription);
        eventBuffers.add(eventBuffer);
      }
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
            publisher!,
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
        await _runCleanupOperation(
          subscription.cancel,
          logLabel: 'PUBSUB subscription',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
      for (final subscriber in subscribers) {
        await _runCleanupOperation(
          subscriber.close,
          logLabel: 'PUBSUB subscriber session',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
      if (publisher != null) {
        await _runCleanupOperation(
          publisher.close,
          logLabel: 'PUBSUB publisher session',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
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
    await _runTimedOperation(
      publisher.publishLazyPayload(
        scenario.uri,
        payload: _buildLazyPayload(
          scenario,
          arguments: [payload],
          argumentsKeywords: metadata,
        ),
        options: _buildPublishOptions(scenario),
      ),
      timeout: _eventTimeout,
      timeoutLabel: 'pubsub_publish_timeout',
      logLabel: 'PUBSUB publish',
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
      ),
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

  Future<WampSession> _openSession(
    WampScenario scenario, {
    required int workerId,
    int? iteration,
    int? peerIndex,
    required String timeoutLabel,
    required String logLabel,
  }) {
    final details = StringBuffer()
      ..write('worker=$workerId ')
      ..write('transport=${scenario.transport.name} ')
      ..write('serializer=${scenario.serializer.name} ')
      ..write('realm=${scenario.realmUri} ')
      ..write('uri=${scenario.uri}');
    if (iteration != null) {
      details.write(' iteration=$iteration');
    }
    if (peerIndex != null) {
      details.write(' peer=$peerIndex');
    }
    return _runTimedOperation(
      _sessionFactory(scenario),
      timeout: _eventTimeout,
      timeoutLabel: '${timeoutLabel}_open_timeout',
      logLabel: '$logLabel session open',
      details: details.toString(),
    );
  }

  String _operationDetails(
    WampScenario scenario, {
    required int workerId,
    int? iteration,
    int? peerIndex,
    String? targetUri,
  }) {
    final details = StringBuffer()
      ..write('worker=$workerId ')
      ..write('transport=${scenario.transport.name} ')
      ..write('serializer=${scenario.serializer.name} ')
      ..write('realm=${scenario.realmUri} ')
      ..write('uri=${targetUri ?? scenario.uri}');
    if (iteration != null) {
      details.write(' iteration=$iteration');
    }
    if (peerIndex != null) {
      details.write(' peer=$peerIndex');
    }
    return details.toString();
  }

  Future<T> _runTimedOperation<T>(
    Future<T> operation, {
    required Duration timeout,
    required String timeoutLabel,
    required String logLabel,
    required String details,
  }) {
    return operation.timeout(
      timeout,
      onTimeout: () {
        _logger.severe('$logLabel timed out $details timeout=$timeout');
        throw TimeoutException(timeoutLabel);
      },
    );
  }

  Future<void> _runCleanupOperation(
    Future<void> Function() operation, {
    required String logLabel,
    required String details,
  }) async {
    try {
      await operation().timeout(_cancelCleanupTimeout);
    } on TimeoutException {
      _logger.warning(
        '$logLabel cleanup timed out $details timeout=$_cancelCleanupTimeout',
      );
    }
  }

  Future<WampRegistration> _registerLazyPayloadHandler(
    WampSession session,
    String procedure,
    FutureOr<void> Function(wamp_core.LazyInvocationPayload invocation)
    onInvoke, {
    required WampScenario scenario,
    required int workerId,
    int? iteration,
    required String timeoutLabel,
    required String logLabel,
    wamp_core.RegisterOptions? options,
  }) {
    return _runTimedOperation(
      session.registerLazyPayloadHandler(procedure, onInvoke, options: options),
      timeout: _eventTimeout,
      timeoutLabel: timeoutLabel,
      logLabel: logLabel,
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
        targetUri: procedure,
      ),
    );
  }

  Future<WampSubscription> _subscribeLazyPayload(
    WampSession session,
    String topic, {
    required WampScenario scenario,
    required int workerId,
    int? iteration,
    int? peerIndex,
    required String timeoutLabel,
    required String logLabel,
    wamp_core.SubscribeOptions? options,
  }) {
    return _runTimedOperation(
      session.subscribeLazyPayload(topic, options: options),
      timeout: _eventTimeout,
      timeoutLabel: timeoutLabel,
      logLabel: logLabel,
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
        peerIndex: peerIndex,
        targetUri: topic,
      ),
    );
  }

  Future<void> _cancelSubscription(
    WampSubscription subscription, {
    required WampScenario scenario,
    required int workerId,
    required int iteration,
    required String timeoutLabel,
    required String logLabel,
  }) {
    return _runTimedOperation(
      subscription.cancel(),
      timeout: _eventTimeout,
      timeoutLabel: timeoutLabel,
      logLabel: logLabel,
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
      ),
    );
  }

  Future<void> _cancelRegistration(
    WampRegistration registration, {
    required WampScenario scenario,
    required int workerId,
    required int iteration,
    required String timeoutLabel,
    required String logLabel,
  }) {
    return _runTimedOperation(
      registration.cancel(),
      timeout: _eventTimeout,
      timeoutLabel: timeoutLabel,
      logLabel: logLabel,
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
      ),
    );
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
    WampSession? session;
    WampSession? calleeSession;
    WampRegistration? registration;
    var procedure = scenario.uri;
    final samples = <WampSample>[];
    try {
      session = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'rpc_caller',
        logLabel: 'RPC caller',
      );
      if (scenario.peerSerializer != null) {
        procedure = _externalProcedureUri(scenario.uri, workerId);
        final peerScenario = _peerScenario(scenario);
        calleeSession = await _openSession(
          peerScenario,
          workerId: workerId,
          timeoutLabel: 'rpc_callee',
          logLabel: 'RPC callee',
        );
        registration = await _registerLazyPayloadHandler(
          calleeSession,
          procedure,
          (invocation) =>
              respondEchoLazyInvocation(invocation, logger: _logger),
          scenario: peerScenario,
          workerId: workerId,
          timeoutLabel: 'rpc_register_timeout',
          logLabel: 'RPC registration',
        );
      }
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
            session!,
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
      if (registration != null) {
        await _runCleanupOperation(
          registration.cancel,
          logLabel: 'RPC registration',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (calleeSession != null) {
        await _runCleanupOperation(
          calleeSession.close,
          logLabel: 'RPC callee session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (session != null) {
        await _runCleanupOperation(
          session.close,
          logLabel: 'RPC caller session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
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

  Future<List<WampSample>> _runProgressiveRpcScenario(
    WampScenario scenario,
  ) async {
    final payload = _buildPayloadString(scenario.payloadBytes);
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runProgressiveRpcWorker(workerId, scenario, payload),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runProgressiveRpcWorker(
    int workerId,
    WampScenario scenario,
    String payload,
  ) async {
    WampSession? caller;
    WampSession? callee;
    WampRegistration? registration;
    final procedure = _externalProcedureUri(scenario.uri, workerId);
    final chunksByInvocation = <int, int>{};
    try {
      caller = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'progressive_rpc_caller',
        logLabel: 'progressive RPC caller',
      );
      final peerScenario = _peerScenario(scenario);
      callee = await _openSession(
        peerScenario,
        workerId: workerId,
        timeoutLabel: 'progressive_rpc_callee',
        logLabel: 'progressive RPC callee',
      );
      registration = await _registerLazyPayloadHandler(
        callee,
        procedure,
        (invocation) {
          final chunkCount =
              (chunksByInvocation[invocation.requestId] ?? 0) + 1;
          chunksByInvocation[invocation.requestId] = chunkCount;
          if (invocation.progress) {
            return;
          }
          if (chunkCount != 3) {
            final pendingChunks = Map<int, int>.from(chunksByInvocation);
            chunksByInvocation.remove(invocation.requestId);
            invocation.respondWith(
              isError: true,
              errorUri: wamp_core.Error.invalidArgument,
              arguments: [
                'expected 3 progressive chunks, got $chunkCount for '
                    'invocation ${invocation.requestId}; pending '
                    '$pendingChunks',
              ],
            );
            return;
          }
          chunksByInvocation.remove(invocation.requestId);
          respondEchoLazyInvocation(invocation, logger: _logger);
        },
        scenario: peerScenario,
        workerId: workerId,
        timeoutLabel: 'progressive_rpc_register_timeout',
        logLabel: 'progressive RPC registration',
      );
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) => _runProgressiveRpcIteration(
          workerId,
          iteration,
          scenario,
          procedure,
          payload,
          caller!,
        ),
      );
    } finally {
      if (registration != null) {
        await _runCleanupOperation(
          registration.cancel,
          logLabel: 'progressive RPC registration',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (callee != null) {
        await _runCleanupOperation(
          callee.close,
          logLabel: 'progressive RPC callee session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (caller != null) {
        await _runCleanupOperation(
          caller.close,
          logLabel: 'progressive RPC caller session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
    }
  }

  Future<WampSample> _runProgressiveRpcIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String procedure,
    String payload,
    WampSession session,
  ) async {
    final start = DateTime.now();
    final call = session.startProgressiveCall(
      procedure,
      arguments: [payload],
      options: _buildCallOptions(scenario),
    );
    call.sendChunk(arguments: [payload]);
    call.finish(arguments: [payload]);
    try {
      await call.results.single.timeout(
        _eventTimeout,
        onTimeout: () => throw TimeoutException('progressive_rpc_timeout'),
      );
    } on wamp_core.Error catch (error) {
      throw StateError(
        'progressive RPC failed with ${error.error} '
        'arguments=${error.arguments} kwargs=${error.argumentsKeywords}',
      );
    }
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: scenario.payloadBytes * 3,
      responseBytes: scenario.payloadBytes,
    );
  }

  Future<List<WampSample>> _runTimeoutRpcScenario(WampScenario scenario) async {
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runTimeoutRpcWorker(workerId, scenario),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runTimeoutRpcWorker(
    int workerId,
    WampScenario scenario,
  ) async {
    WampSession? caller;
    WampSession? callee;
    WampRegistration? registration;
    final procedure = _externalProcedureUri(scenario.uri, workerId);
    try {
      caller = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'timeout_rpc_caller',
        logLabel: 'timeout RPC caller',
      );
      final peerScenario = _peerScenario(scenario);
      callee = await _openSession(
        peerScenario,
        workerId: workerId,
        timeoutLabel: 'timeout_rpc_callee',
        logLabel: 'timeout RPC callee',
      );
      registration = await _registerLazyPayloadHandler(
        callee,
        procedure,
        (_) {},
        scenario: peerScenario,
        workerId: workerId,
        timeoutLabel: 'timeout_rpc_register_timeout',
        logLabel: 'timeout RPC registration',
      );
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) => _runTimeoutRpcIteration(
          workerId,
          iteration,
          scenario,
          procedure,
          caller!,
        ),
      );
    } finally {
      if (registration != null) {
        await _runCleanupOperation(
          registration.cancel,
          logLabel: 'timeout RPC registration',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (callee != null) {
        await _runCleanupOperation(
          callee.close,
          logLabel: 'timeout RPC callee session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (caller != null) {
        await _runCleanupOperation(
          caller.close,
          logLabel: 'timeout RPC caller session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
    }
  }

  Future<WampSample> _runTimeoutRpcIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String procedure,
    WampSession session,
  ) async {
    final timeoutMilliseconds = scenario.callTimeoutMs ?? 50;
    final start = DateTime.now();
    try {
      await session
          .callSinglePayload(
            procedure,
            options: _buildCallOptions(scenario, timeout: timeoutMilliseconds),
          )
          .timeout(_eventTimeout);
      throw StateError('timeout RPC completed without wamp.error.timeout');
    } on wamp_core.Error catch (error) {
      if (error.error != wamp_core.Error.timeout) {
        rethrow;
      }
    }
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    final earliestAcceptedTimeoutMs = timeoutMilliseconds * 0.8;
    if (latencyMs < earliestAcceptedTimeoutMs) {
      throw StateError(
        'timeout RPC fired too early: ${latencyMs.toStringAsFixed(3)}ms '
        'for a ${timeoutMilliseconds}ms timeout',
      );
    }
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: 0,
      responseBytes: 0,
    );
  }

  Future<List<WampSample>> _runMetaApiScenario(WampScenario scenario) async {
    final workers = List.generate(
      scenario.concurrency,
      (workerId) => _runMetaApiWorker(workerId, scenario),
    );
    final results = await Future.wait(workers);
    return results.expand((samples) => samples).toList(growable: false);
  }

  Future<List<WampSample>> _runMetaApiWorker(
    int workerId,
    WampScenario scenario,
  ) async {
    WampSession? session;
    WampRegistration? registration;
    WampSubscription? subscription;
    final procedure = _externalProcedureUri(
      '${scenario.uri}.procedure',
      workerId,
    );
    final topic = _externalProcedureUri('${scenario.uri}.topic', workerId);
    try {
      session = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'meta_api_session',
        logLabel: 'Meta API',
      );
      registration = await _registerLazyPayloadHandler(
        session,
        procedure,
        respondEchoLazyInvocation,
        scenario: scenario,
        workerId: workerId,
        timeoutLabel: 'meta_api_register_timeout',
        logLabel: 'Meta API registration',
      );
      subscription = await _subscribeLazyPayload(
        session,
        topic,
        scenario: scenario,
        workerId: workerId,
        timeoutLabel: 'meta_api_subscribe_timeout',
        logLabel: 'Meta API subscription',
      );
      final sessionId = session.id;
      final registrationId = registration.id;
      final subscriptionId = subscription.id;
      if (sessionId == null ||
          registrationId == null ||
          subscriptionId == null) {
        throw StateError('Meta API workload requires live entity identifiers');
      }
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) => _runMetaApiIteration(
          workerId,
          iteration,
          scenario,
          procedure,
          topic,
          sessionId,
          registrationId,
          subscriptionId,
          session!,
        ),
      );
    } finally {
      if (subscription != null) {
        await _runCleanupOperation(
          subscription.cancel,
          logLabel: 'Meta API subscription',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: topic,
          ),
        );
      }
      if (registration != null) {
        await _runCleanupOperation(
          registration.cancel,
          logLabel: 'Meta API registration',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (session != null) {
        await _runCleanupOperation(
          session.close,
          logLabel: 'Meta API session',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
    }
  }

  Future<WampSample> _runMetaApiIteration(
    int workerId,
    int iteration,
    WampScenario scenario,
    String procedure,
    String topic,
    int sessionId,
    int registrationId,
    int subscriptionId,
    WampSession session,
  ) async {
    Future<void> call(String uri, [List<dynamic>? arguments]) async {
      await session
          .callSinglePayload(uri, arguments: arguments)
          .timeout(_eventTimeout);
    }

    final start = DateTime.now();
    await call('wamp.session.list');
    await call('wamp.session.count');
    await call('wamp.session.get', [sessionId]);
    await call('wamp.registration.list');
    await call('wamp.registration.lookup', [procedure]);
    await call('wamp.registration.match', [procedure]);
    await call('wamp.registration.get', [registrationId]);
    await call('wamp.registration.list_callees', [registrationId]);
    await call('wamp.registration.count_callees', [registrationId]);
    await call('wamp.subscription.list');
    await call('wamp.subscription.lookup', [topic]);
    await call('wamp.subscription.match', [topic]);
    await call('wamp.subscription.get', [subscriptionId]);
    await call('wamp.subscription.list_subscribers', [subscriptionId]);
    await call('wamp.subscription.count_subscribers', [subscriptionId]);
    final latencyMs = DateTime.now().difference(start).inMicroseconds / 1000.0;
    return WampSample(
      worker: workerId,
      iteration: iteration,
      latencyMs: latencyMs,
      requestBytes: 0,
      responseBytes: 0,
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
    WampSession? publisher;
    try {
      publisher = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'publish_ack_publisher',
        logLabel: 'Publish-ack publisher',
      );
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) => _runPublishAckIteration(
          workerId,
          iteration,
          scenario,
          payload,
          publisher!,
        ),
      );
    } finally {
      if (publisher != null) {
        await _runCleanupOperation(
          publisher.close,
          logLabel: 'Publish-ack publisher session',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
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
    await _runTimedOperation(
      publisher.publishLazyPayload(
        topic,
        payload: _buildLazyPayload(
          scenario,
          arguments: payload.isEmpty ? null : [payload],
        ),
        options: _buildControlPublishOptions(scenario),
      ),
      timeout: _eventTimeout,
      timeoutLabel: 'publish_ack_timeout',
      logLabel: 'Publish-ack publish',
      details: _operationDetails(
        scenario,
        workerId: workerId,
        iteration: iteration,
        targetUri: topic,
      ),
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
    WampSession? session;
    try {
      session = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'subscribe_cycle',
        logLabel: 'Subscribe-cycle',
      );
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) => _runSubscribeCycleIteration(
          workerId,
          iteration,
          scenario,
          session!,
        ),
      );
    } finally {
      if (session != null) {
        await _runCleanupOperation(
          session.close,
          logLabel: 'Subscribe-cycle session',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
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
    final subscription = await _subscribeLazyPayload(
      session,
      topic,
      scenario: scenario,
      workerId: workerId,
      iteration: iteration,
      timeoutLabel: 'subscribe_cycle_subscribe_timeout',
      logLabel: 'Subscribe-cycle subscribe',
      options: _buildControlSubscribeOptions(scenario),
    );
    await _cancelSubscription(
      subscription,
      scenario: scenario,
      workerId: workerId,
      iteration: iteration,
      timeoutLabel: 'subscribe_cycle_unsubscribe_timeout',
      logLabel: 'Subscribe-cycle unsubscribe',
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
    WampSession? session;
    try {
      session = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'register_cycle',
        logLabel: 'Register-cycle',
      );
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) =>
            _runRegisterCycleIteration(workerId, iteration, scenario, session!),
      );
    } finally {
      if (session != null) {
        await _runCleanupOperation(
          session.close,
          logLabel: 'Register-cycle session',
          details: _operationDetails(scenario, workerId: workerId),
        );
      }
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
    final registration = await _registerLazyPayloadHandler(
      session,
      procedure,
      (_) {},
      scenario: scenario,
      workerId: workerId,
      iteration: iteration,
      timeoutLabel: 'register_cycle_register_timeout',
      logLabel: 'Register-cycle register',
      options: _buildControlRegisterOptions(scenario),
    );
    await _cancelRegistration(
      registration,
      scenario: scenario,
      workerId: workerId,
      iteration: iteration,
      timeoutLabel: 'register_cycle_unregister_timeout',
      logLabel: 'Register-cycle unregister',
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
    WampSession? caller;
    WampSession? callee;
    final procedure = _externalProcedureUri(scenario.uri, workerId);
    WampRegistration? registration;
    try {
      caller = await _openSession(
        scenario,
        workerId: workerId,
        timeoutLabel: 'cancel_caller',
        logLabel: 'Cancel-cycle caller',
      );
      final peerScenario = _peerScenario(scenario);
      callee = await _openSession(
        peerScenario,
        workerId: workerId,
        timeoutLabel: 'cancel_callee',
        logLabel: 'Cancel-cycle callee',
      );
      registration = await _registerLazyPayloadHandler(
        callee,
        procedure,
        (_) {},
        scenario: _peerScenario(scenario),
        workerId: workerId,
        timeoutLabel: 'cancel_register_timeout',
        logLabel: 'Cancel-cycle registration',
        options: _buildControlRegisterOptions(scenario),
      );
      return await _runWithInFlightLimit(
        iterations: scenario.iterations,
        maxInFlight: scenario.inFlightPerSession,
        launch: (iteration) =>
            _runCancelCycleIteration(workerId, iteration, procedure, caller!),
      );
    } finally {
      if (registration != null) {
        await _runCleanupOperation(
          registration.cancel,
          logLabel: 'Cancel-cycle registration',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (callee != null) {
        await _runCleanupOperation(
          callee.close,
          logLabel: 'Cancel-cycle callee session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
      if (caller != null) {
        await _runCleanupOperation(
          caller.close,
          logLabel: 'Cancel-cycle caller session',
          details: _operationDetails(
            scenario,
            workerId: workerId,
            targetUri: procedure,
          ),
        );
      }
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
      pptCipher: scenario.pptCipher,
      pptKeyId: scenario.pptKeyId,
    );
  }

  wamp_core.PublishOptions _buildControlPublishOptions(WampScenario scenario) {
    final options = wamp_core.PublishOptions(
      acknowledge: true,
      excludeMe: true,
      discloseMe: true,
      pptScheme: scenario.pptScheme,
      pptSerializer: _resolvePptSerializer(scenario),
      pptCipher: scenario.pptCipher,
      pptKeyId: scenario.pptKeyId,
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

  wamp_core.CallOptions? _buildCallOptions(
    WampScenario scenario, {
    int? timeout,
  }) {
    if (scenario.pptScheme == null && timeout == null) {
      return null;
    }
    return wamp_core.CallOptions(
      timeout: timeout,
      pptScheme: scenario.pptScheme,
      pptSerializer: _resolvePptSerializer(scenario),
      pptCipher: scenario.pptCipher,
      pptKeyId: scenario.pptKeyId,
    );
  }

  String? _resolvePptSerializer(WampScenario scenario) {
    if (scenario.pptScheme == null) {
      return null;
    }
    if (scenario.pptScheme == wamp_core.ConnectanumE2eeProfile.scheme) {
      return wamp_core.ConnectanumE2eeProfile.serializer;
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
    this.id,
    Stream<wamp_core.LazyEventPayload> Function()? eventStreamFactory,
    void Function(void Function(wamp_core.LazyEventPayload event) onEvent)?
    attachEventHandler,
    Future<void> Function()? onRevoke,
    required Future<void> Function() cancel,
  }) : _eventStreamFactory = eventStreamFactory,
       _attachEventHandler = attachEventHandler,
       _onRevoke = onRevoke,
       _onCancel = cancel;

  final int? id;
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
  int? get id;

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

  WampProgressiveCall startProgressiveCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
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

class WampProgressiveCall {
  WampProgressiveCall({
    required this.results,
    required void Function({List<dynamic>? arguments}) sendChunk,
    required void Function({List<dynamic>? arguments}) finish,
  }) : _sendChunk = sendChunk,
       _finish = finish;

  final Stream<wamp_core.Result> results;
  final void Function({List<dynamic>? arguments}) _sendChunk;
  final void Function({List<dynamic>? arguments}) _finish;

  void sendChunk({List<dynamic>? arguments}) =>
      _sendChunk(arguments: arguments);

  void finish({List<dynamic>? arguments}) => _finish(arguments: arguments);
}

class WampRegistration {
  WampRegistration({this.id, required Future<void> Function() cancel})
    : _cancel = cancel;

  final int? id;
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
    this.e2eeProviderFactory,
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
  final WampE2eeProviderFactory? e2eeProviderFactory;

  Future<WampSession> call() async {
    final transport = switch (clientImplementation) {
      WampClientImplementation.dart => _buildDartTransport(),
      WampClientImplementation.native => _buildNativeTransport(),
    };
    final e2eeProvider = e2eeProviderFactory?.call();
    final client = wamp_client.Client(
      realm: realmUri,
      transport: transport,
      authId: authId,
      authenticationMethods: authenticationMethods,
      e2eeProvider: e2eeProvider,
    );
    try {
      final session = await client.connect().first;
      return _ClientBackedWampSession(client, session, e2eeProvider);
    } catch (_) {
      _releaseE2eeProvider(e2eeProvider);
      rethrow;
    }
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
    this.e2eeProviderFactory,
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
  final WampE2eeProviderFactory? e2eeProviderFactory;

  Future<WampSession> call() async {
    final transport = switch (clientImplementation) {
      WampClientImplementation.dart => _buildDartTransport(),
      WampClientImplementation.native => _buildNativeTransport(),
    };
    final e2eeProvider = e2eeProviderFactory?.call();
    final client = wamp_client.Client(
      realm: realmUri,
      transport: transport,
      authId: authId,
      authenticationMethods: authenticationMethods,
      e2eeProvider: e2eeProvider,
    );
    try {
      final session = await client.connect().first;
      return _ClientBackedWampSession(client, session, e2eeProvider);
    } catch (_) {
      _releaseE2eeProvider(e2eeProvider);
      rethrow;
    }
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

void _releaseE2eeProvider(wamp_core.WampE2eeProvider? provider) {
  if (provider is wamp_core.DisposableWampE2eeProvider) {
    provider.release();
  }
}

class _ClientBackedWampSession implements WampSession {
  _ClientBackedWampSession(
    this._client,
    this._session,
    this._ownedE2eeProvider,
  );

  final wamp_client.Client _client;
  final wamp_client.Session _session;
  final wamp_core.WampE2eeProvider? _ownedE2eeProvider;
  bool _closed = false;

  @override
  int? get id => _session.id;

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
      id: subscribed.subscriptionId,
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
      id: subscribed.subscriptionId,
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
      id: subscribed.subscriptionId,
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
      id: registered.registrationId,
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
  WampProgressiveCall startProgressiveCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    wamp_core.CallOptions? options,
  }) {
    final call = _session.startProgressiveCall(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
      options: options,
    );
    return WampProgressiveCall(
      results: call.results,
      sendChunk: ({arguments}) => call.sendChunk(arguments: arguments),
      finish: ({arguments}) => call.finish(arguments: arguments),
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
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _client.disconnect();
    } finally {
      _releaseE2eeProvider(_ownedE2eeProvider);
    }
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
    this.callTimeoutMs,
    this.controlCustomFields = false,
    this.pptScheme,
    this.pptSerializer,
    this.pptCipher,
    this.pptKeyId,
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
  final int? callTimeoutMs;
  final bool controlCustomFields;
  final String? pptScheme;
  final String? pptSerializer;
  final String? pptCipher;
  final String? pptKeyId;

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
    final pptScheme = _readOptionalString(json['ppt_scheme']);
    final pptSerializer = _readOptionalString(json['ppt_serializer']);
    final pptCipher = _readOptionalString(json['ppt_cipher']);
    final pptKeyId = _readOptionalString(json['ppt_keyid']);
    if (pptScheme == wamp_core.ConnectanumE2eeProfile.scheme) {
      if (pptSerializer != null &&
          pptSerializer != wamp_core.ConnectanumE2eeProfile.serializer) {
        throw FormatException('WAMP E2EE benchmark serializer must be cbor');
      }
      if (pptCipher != wamp_core.ConnectanumE2eeProfile.xsalsa20Poly1305 &&
          pptCipher != wamp_core.ConnectanumE2eeProfile.aes256Gcm) {
        throw FormatException(
          'WAMP E2EE benchmark cipher must be xsalsa20poly1305 or aes256gcm',
        );
      }
      if (pptKeyId == null) {
        throw FormatException('WAMP E2EE benchmark requires ppt_keyid');
      }
    }
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
      callTimeoutMs: _readOptionalPositiveInt(json['call_timeout_ms']),
      controlCustomFields: json['control_custom_fields'] == true,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
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

  static String? _readOptionalString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Expected non-empty string, got $value');
    }
    return value;
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
    if (callTimeoutMs != null) 'call_timeout_ms': callTimeoutMs,
    if (controlCustomFields) 'control_custom_fields': true,
    if (pptScheme != null) 'ppt_scheme': pptScheme,
    if (pptSerializer != null) 'ppt_serializer': pptSerializer,
    if (pptCipher != null) 'ppt_cipher': pptCipher,
    if (pptKeyId != null) 'ppt_keyid': pptKeyId,
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
    Object? callTimeoutMs = _copySentinel,
    bool? controlCustomFields,
    Object? pptScheme = _copySentinel,
    Object? pptSerializer = _copySentinel,
    Object? pptCipher = _copySentinel,
    Object? pptKeyId = _copySentinel,
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
      callTimeoutMs: identical(callTimeoutMs, _copySentinel)
          ? this.callTimeoutMs
          : callTimeoutMs as int?,
      controlCustomFields: controlCustomFields ?? this.controlCustomFields,
      pptScheme: identical(pptScheme, _copySentinel)
          ? this.pptScheme
          : pptScheme as String?,
      pptSerializer: identical(pptSerializer, _copySentinel)
          ? this.pptSerializer
          : pptSerializer as String?,
      pptCipher: identical(pptCipher, _copySentinel)
          ? this.pptCipher
          : pptCipher as String?,
      pptKeyId: identical(pptKeyId, _copySentinel)
          ? this.pptKeyId
          : pptKeyId as String?,
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
  progressiveRpc,
  timeoutRpc,
  metaApi,
  publishAck,
  subscribeCycle,
  registerCycle,
  cancelCycle;

  String get wireName => switch (this) {
    WampMode.authenticate => 'authenticate',
    WampMode.pubsub => 'pubsub',
    WampMode.rpc => 'rpc',
    WampMode.progressiveRpc => 'progressive_rpc',
    WampMode.timeoutRpc => 'timeout_rpc',
    WampMode.metaApi => 'meta_api',
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
      case 'progressive_rpc':
      case 'progressiverpc':
      case 'wamp_progressive_rpc':
        return WampMode.progressiveRpc;
      case 'timeout_rpc':
      case 'timeoutrpc':
      case 'wamp_timeout_rpc':
        return WampMode.timeoutRpc;
      case 'meta_api':
      case 'metaapi':
      case 'wamp_meta_api':
        return WampMode.metaApi;
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
