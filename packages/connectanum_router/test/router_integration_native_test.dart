@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_integration_native_test;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_router/src/native/ffi_bindings.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/snapshot.dart';
import 'package:ffi/ffi.dart';
import 'support/native_lib.dart';
import 'package:test/test.dart';
import 'package:http2/transport.dart' as http2;

class _HybridRuntime implements NativeRuntimeWithHandles {
  _HybridRuntime(this._inner, List<int> connectionSequence)
    : _connections = Queue<int>.from(connectionSequence) {
    _syntheticConnections.addAll(connectionSequence);
  }

  final NativeTransportRuntime _inner;
  final Queue<int> _connections;
  final Map<int, int> _ports = {};
  final Map<int, int> _http3Ports = {};
  final Map<int, int> _connectionMap = {};
  final Map<int, Queue<NativeHttp3Handshake>> _http3Handshakes = {};
  final Map<int, NativeConnectionProtocol> _protocolOverrides = {};
  final Map<int, NativeHttp3Connection> _http3Connections = {};
  final Map<int, Queue<NativeHttp2Handshake>> _http2Handshakes = {};
  final Set<int> _syntheticConnections = <int>{};

  @override
  void start() => _inner.start();

  @override
  void shutdown() => _inner.shutdown();

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _inner.listen(host, port, backlog: backlog);
    _ports[id] = _inner.getLocalPort(id);
    _http3Ports[id] = _inner.getHttp3Port(id);
    return id;
  }

  @override
  int getLocalPort(int listenerId) =>
      _ports[listenerId] ?? _inner.getLocalPort(listenerId);

  @override
  int getHttp3Port(int listenerId) =>
      _http3Ports[listenerId] ?? _inner.getHttp3Port(listenerId);

  @override
  void closeListener(int listenerId) => _inner.closeListener(listenerId);

  @override
  int pollConnection(int listenerId) {
    final actualId = _inner.pollConnection(listenerId);
    if (actualId > 0) {
      if (_connections.isNotEmpty) {
        final synthetic = _connections.removeFirst();
        _syntheticConnections.remove(synthetic);
        _connectionMap[synthetic] = actualId;
        return synthetic;
      }
      return actualId;
    }
    if (_connections.isNotEmpty) {
      final peek = _connections.first;
      if (_syntheticConnections.contains(peek)) {
        return _connections.removeFirst();
      }
    }
    return 0;
  }

  @override
  int connectionMaxRawSocketExponent(int connectionId) => 16;

  @override
  NativeConnectionProtocol connectionProtocol(int connectionId) {
    final override =
        _protocolOverrides[connectionId] ??
        _protocolOverrides[_resolveConnectionId(connectionId)];
    if (override != null) {
      return override;
    }
    if (_syntheticConnections.contains(connectionId)) {
      return NativeConnectionProtocol.rawsocket;
    }
    final resolved = _resolveConnectionId(connectionId);
    return _inner.connectionProtocol(resolved);
  }

  @override
  void closeConnection(int connectionId) {
    if (_syntheticConnections.contains(connectionId)) {
      return;
    }
    _inner.closeConnection(_resolveConnectionId(connectionId));
  }

  @override
  String? connectionWebSocketProtocol(int connectionId) =>
      _inner.connectionWebSocketProtocol(_resolveConnectionId(connectionId));

  @override
  NativeHttpHandshake? takeHttpHandshake(int connectionId) {
    if (_syntheticConnections.contains(connectionId)) {
      return null;
    }
    return _inner.takeHttpHandshake(_resolveConnectionId(connectionId));
  }

  @override
  void releaseHttpHandshake(int handle) => _inner.releaseHttpHandshake(handle);

  @override
  NativeWebSocketHandshake? takeWebSocketHandshake(int connectionId) =>
      _inner.takeWebSocketHandshake(_resolveConnectionId(connectionId));

  @override
  void acceptWebSocket({
    required int connectionId,
    required int handshakeHandle,
    required NativeMessageSerializer serializer,
    required String protocol,
  }) {
    _inner.acceptWebSocket(
      connectionId: _resolveConnectionId(connectionId),
      handshakeHandle: handshakeHandle,
      serializer: serializer,
      protocol: protocol,
    );
  }

  @override
  void rejectWebSocket({
    required int connectionId,
    required int handshakeHandle,
    int status = 400,
    String reason = '',
  }) {
    _inner.rejectWebSocket(
      connectionId: _resolveConnectionId(connectionId),
      handshakeHandle: handshakeHandle,
      status: status,
      reason: reason,
    );
  }

  @override
  NativeHttp2Handshake? takeHttp2Handshake(int connectionId) {
    final queue = _http2Handshakes[connectionId];
    if (queue != null && queue.isNotEmpty) {
      return queue.removeFirst();
    }
    final resolved = _resolveConnectionId(connectionId);
    final resolvedQueue = _http2Handshakes[resolved];
    if (resolvedQueue != null && resolvedQueue.isNotEmpty) {
      return resolvedQueue.removeFirst();
    }
    return _inner.takeHttp2Handshake(resolved);
  }

  @override
  void releaseHttp2Handshake(int handle) =>
      _inner.releaseHttp2Handshake(handle);

  @override
  NativeHttp3Handshake? takeHttp3Handshake(int connectionId) {
    final queue = _http3Handshakes[connectionId];
    if (queue != null && queue.isNotEmpty) {
      return queue.removeFirst();
    }
    final resolved = _resolveConnectionId(connectionId);
    final resolvedQueue = _http3Handshakes[resolved];
    if (resolvedQueue != null && resolvedQueue.isNotEmpty) {
      return resolvedQueue.removeFirst();
    }
    return _inner.takeHttp3Handshake(resolved);
  }

  @override
  void releaseHttp3Handshake(int handle) =>
      _inner.releaseHttp3Handshake(handle);

  @override
  NativeHttp3Connection? takeHttp3Connection(int connectionId) {
    final direct = _http3Connections.remove(connectionId);
    if (direct != null) {
      return direct;
    }
    final resolved = _resolveConnectionId(connectionId);
    final resolvedDirect = _http3Connections.remove(resolved);
    if (resolvedDirect != null) {
      return resolvedDirect;
    }
    try {
      return _inner.takeHttp3Connection(resolved);
    } on NativeTransportException catch (error) {
      if (error.code == NativeTransportErrorCode.connectionNotFound) {
        return null;
      }
      rethrow;
    }
  }

  @override
  NativeHttp3Stream? pollHttp3Stream(int connectionId) =>
      _inner.pollHttp3Stream(_resolveConnectionId(connectionId));

  @override
  NativeHttpHandshake? pollHttp3Request(int connectionId) {
    final resolved = _resolveConnectionId(connectionId);
    return _inner.pollHttp3Request(resolved);
  }

  @override
  String? get libraryPathHint => _inner.libraryPath;

  @override
  NativeIncomingMessage? pollMessage(int connectionId) =>
      _inner.pollMessage(_resolveConnectionId(connectionId));

  @override
  int pollMessageHandle(int connectionId) =>
      _pollMessageHandleSafe(connectionId);

  @override
  int pollWebSocketMessageHandle(int connectionId) =>
      _pollMessageHandleSafe(connectionId);

  int _pollMessageHandleSafe(int connectionId) {
    try {
      return _inner.pollMessageHandle(_resolveConnectionId(connectionId));
    } on NativeTransportException catch (error) {
      if (error.code == NativeTransportErrorCode.connectionNotFound) {
        return 0;
      }
      rethrow;
    }
  }

  @override
  int retainMessageHandle(int handle) => _inner.retainMessageHandle(handle);

  @override
  void releaseMessageHandle(int handle) => _inner.releaseMessageHandle(handle);

  int _resolveConnectionId(int connectionId) =>
      _connectionMap[connectionId] ?? connectionId;

  @override
  void forwardPublishEvent({
    required int handle,
    required int connectionId,
    required int subscriptionId,
    required int publicationId,
    int? publisherSessionId,
    String? topic,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void forwardCallInvocation({
    required int handle,
    required int connectionId,
    required int invocationId,
    required int registrationId,
    int? callerSessionId,
    String? procedure,
    bool? receiveProgress,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void sendMessage(int connectionId, Uint8List payload) {
    // Tests observe boss notifications; no outbound frame needed.
  }

  @override
  NativeHttpConnectionEvent? pollHttpConnectionEvent() =>
      _inner.pollHttpConnectionEvent();

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) => _inner.sendHttpResponse(
    handshakeHandle: handshakeHandle,
    connectionId: connectionId,
    response: response,
  );

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) => _inner.openHttpResponseStream(
    handshakeHandle: handshakeHandle,
    status: status,
    headers: headers,
  );

  @override
  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) => _inner.openHttpResponseStreamDescriptor(
    handshakeHandle: handshakeHandle,
    status: status,
    headers: headers,
  );

  @override
  NativeRouterMetrics? pollRouterMetrics() => _inner.pollRouterMetrics();

  @override
  void applyRouterConfig(Uint8List config) => _inner.applyRouterConfig(config);

  @override
  int reloadTls() => _inner.reloadTls();

  int enqueueTestMessage({
    required int connectionId,
    required NativeMessageSerializer serializer,
    required Uint8List frame,
  }) => _inner.enqueueTestMessage(
    connectionId: _resolveConnectionId(connectionId),
    serializer: serializer,
    frame: frame,
  );

  void clearTestMessages() => _inner.clearTestMessages();

  void enqueueHttp3Handshake(int connectionId, NativeHttp3Handshake handshake) {
    _http3Handshakes
        .putIfAbsent(connectionId, () => Queue<NativeHttp3Handshake>())
        .add(handshake);
  }

  void enqueueHttp2Handshake(int connectionId, NativeHttp2Handshake handshake) {
    _http2Handshakes
        .putIfAbsent(connectionId, () => Queue<NativeHttp2Handshake>())
        .add(handshake);
  }

  void enqueueHttp3Connection(
    int connectionId,
    NativeHttp3Connection connection,
  ) {
    _http3Connections[connectionId] = connection;
  }

  void queueConnection(int connectionId) {
    _connections.add(connectionId);
    _syntheticConnections.add(connectionId);
  }

  void setConnectionProtocol(
    int connectionId,
    NativeConnectionProtocol protocol,
  ) {
    _protocolOverrides[connectionId] = protocol;
  }

  bool get supportsHttp3TestClient => _inner.supportsHttp3TestClient;

  NativeHttpTestResponse runHttp3StreamRequest({
    required String host,
    required int port,
    required String path,
    required String method,
    Map<String, String> headers = const {},
    Uint8List? body,
    required String certificatePem,
  }) {
    return _inner.runHttp3StreamRequest(
      host: host,
      port: port,
      path: path,
      method: method,
      headers: headers,
      body: body,
      certificatePem: certificatePem,
    );
  }
}

class _RouterHarness {
  _RouterHarness._({
    required this.connectionId,
    required NativeTransportRuntime innerRuntime,
    required this.runtime,
    required this.binding,
    required StreamController<Map<String, Object?>> events,
    required StreamController<void> pendingEventSignals,
    required Queue<Map<String, Object?>> pendingEvents,
  }) : _innerRuntime = innerRuntime,
       _events = events,
       _pendingEventSignals = pendingEventSignals,
       _pendingEvents = pendingEvents,
       _statePort = binding.debugStatePort!;

  final int connectionId;
  final NativeTransportRuntime _innerRuntime;
  final _HybridRuntime runtime;
  final RouterBinding binding;
  final StreamController<Map<String, Object?>> _events;
  final StreamController<void> _pendingEventSignals;
  final Queue<Map<String, Object?>> _pendingEvents;
  final SendPort _statePort;
  int? _sessionId;
  bool _connectionQueued = false;
  bool _disposed = false;

  static Future<_RouterHarness> start({
    required int connectionId,
    required String? nativeLib,
    RouterConfig? config,
    RouterSettings? settings,
    List<int>? connectionSequence,
  }) async {
    final innerRuntime = NativeTransportRuntime(libraryPath: nativeLib);
    final runtime = _HybridRuntime(
      innerRuntime,
      connectionSequence ?? const [],
    );
    runtime.start();
    runtime.clearTestMessages();

    final pendingEvents = Queue<Map<String, Object?>>();
    final pendingSignals = StreamController<void>.broadcast();
    final events = StreamController<Map<String, Object?>>.broadcast();
    final routerConfig = config ?? _buildConfig();
    final routerSettings = settings ?? _buildSettings();
    final binding = Router(routerConfig, settings: routerSettings).start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          pendingEvents.add(event);
          pendingSignals.add(null);
          events.add(event);
        }
      },
    );

    final harness = _RouterHarness._(
      connectionId: connectionId,
      innerRuntime: innerRuntime,
      runtime: runtime,
      binding: binding,
      events: events,
      pendingEventSignals: pendingSignals,
      pendingEvents: pendingEvents,
    );
    try {
      await harness
          ._awaitEvent('worker_registered')
          .timeout(const Duration(seconds: 2));
      await harness
          ._awaitEvent('worker_ready')
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Worker startup events may arrive later; proceed regardless.
    }
    return harness;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    runtime.clearTestMessages();
    await binding.dispose();
    await _events.close();
    await _pendingEventSignals.close();
    runtime.shutdown();
    _innerRuntime.dispose();
  }

  Future<Map<String, Object?>> _awaitEvent(String type) => nextEvent(type);

  Future<Map<String, Object?>> nextEvent(String type) async {
    final pending = _takePending(type);
    if (pending != null) {
      return pending;
    }
    await for (final _ in _pendingEventSignals.stream) {
      final match = _takePending(type);
      if (match != null) {
        return match;
      }
    }
    throw StateError('Stream ended while waiting for $type');
  }

  Future<Map<String, Object?>> nextEventMatching(Set<String> types) async {
    final pending = _takePendingMatching(types);
    if (pending != null) {
      return pending;
    }
    await for (final _ in _pendingEventSignals.stream) {
      final match = _takePendingMatching(types);
      if (match != null) {
        return match;
      }
    }
    throw StateError('Stream ended while waiting for ${types.join(", ")}');
  }

  Map<String, Object?>? _takePending(String type) {
    for (final event in _pendingEvents) {
      if (event['type'] == type) {
        _pendingEvents.remove(event);
        return event;
      }
    }
    return null;
  }

  Map<String, Object?>? _takePendingMatching(Set<String> types) {
    for (final event in _pendingEvents) {
      final type = event['type'];
      if (type is String && types.contains(type)) {
        _pendingEvents.remove(event);
        return event;
      }
    }
    return null;
  }

  Stream<Map<String, Object?>> get events => _events.stream;

  Future<int> ensureSession() async {
    if (_sessionId != null) {
      return _sessionId!;
    }
    if (!_connectionQueued) {
      runtime.queueConnection(connectionId);
      _connectionQueued = true;
    }
    _enqueueHello(runtime, connectionId);
    _sessionId = await _awaitSessionId(_statePort, connectionId);
    return _sessionId!;
  }

  Future<int> registerProcedure({
    Map<String, Object?> details = const {},
  }) async {
    final sessionId = await ensureSession();
    return _registerProcedureWithRetry(_statePort, sessionId, details: details);
  }

  void enqueueCall({required int requestId, bool receiveProgress = false}) {
    _enqueueCall(
      runtime,
      connectionId,
      requestId,
      receiveProgress: receiveProgress,
    );
  }

  void enqueueYield({
    required int invocationId,
    required bool progress,
    required List<dynamic> arguments,
  }) {
    _enqueueYield(
      runtime,
      connectionId,
      invocationId,
      progress: progress,
      arguments: arguments,
    );
  }

  void enqueueInvocationError({
    required int invocationId,
    String errorUri = 'wamp.error.runtime_error',
  }) {
    _enqueueInvocationError(
      runtime,
      connectionId,
      invocationId,
      errorUri: errorUri,
    );
  }

  void enqueueCancel({required int requestId, String mode = 'killnowait'}) {
    _enqueueCancel(runtime, connectionId, requestId, mode: mode);
  }

  Future<void> expectInvocationCleared(int invocationId) async {
    final replyPort = ReceivePort();
    _statePort.send(
      InvocationGetCommand(
        realmUri: 'realm1',
        invocationId: invocationId,
        replyPort: replyPort.sendPort,
      ),
    );
    final result = await replyPort.first;
    replyPort.close();
    expect(result, isNull, reason: 'Invocation $invocationId still present');
  }

  Future<List<dynamic>> nextWorkerSendPayload({int? expectedCode}) async {
    while (true) {
      final event = await nextEvent('worker_send');
      final payload = event['payload'];
      if (payload is! Uint8List) {
        continue;
      }
      final decoded = json.decode(utf8.decode(payload)) as List<dynamic>;
      if (expectedCode == null || decoded.first == expectedCode) {
        return decoded;
      }
    }
  }

  Future<int> subscribe({required String topic, required int requestId}) async {
    await ensureSession();
    _enqueueSubscribe(runtime, connectionId, requestId, topic: topic);
    return _awaitSubscriptionId(
      _statePort,
      sessionId: _sessionId!,
      topic: topic,
    );
  }

  void publish({
    required int requestId,
    required String topic,
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    bool acknowledge = false,
  }) {
    _enqueuePublish(
      runtime,
      connectionId,
      requestId,
      topic: topic,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      acknowledge: acknowledge,
    );
  }
}

final bool _forwardNativePublishEventsEnabled = forwardNativePublishEvents;
final String? _nativePublishSkipReason = _forwardNativePublishEventsEnabled
    ? null
    : 'CONNECTANUM_FORWARD_NATIVE_PUBLISH not enabled (zero-copy publish forwarding disabled).';
const _zeroCopyPublishTag = 'zero_copy_publish';

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('Router + FFI test mode', () {
    test('forwards progressive and final results', () async {
      const stepTimeout = Duration(seconds: 10);
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession().timeout(stepTimeout);
      await harness.registerProcedure().timeout(stepTimeout);

      const requestId = 42;
      harness.enqueueCall(requestId: requestId, receiveProgress: true);
      final invocationEvent = await harness
          .nextEvent('worker_forward_native_invocation')
          .timeout(stepTimeout);
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueYield(
        invocationId: invocationId,
        progress: true,
        arguments: const ['chunk'],
      );
      final progressEvent = await harness
          .nextEvent('worker_forward_native_result')
          .timeout(stepTimeout);
      expect(progressEvent['progress'], isTrue);
      expect(progressEvent['requestId'], equals(requestId));

      harness.enqueueYield(
        invocationId: invocationId,
        progress: false,
        arguments: const ['complete'],
      );
      final finalEvent = await harness
          .nextEvent('worker_forward_native_result')
          .timeout(stepTimeout);
      expect(finalEvent['progress'], isFalse);
      expect(finalEvent['requestId'], equals(requestId));

      await harness.expectInvocationCleared(invocationId).timeout(stepTimeout);
    }, skip: skipReason);

    test('propagates callee errors', () async {
      const stepTimeout = Duration(seconds: 10);
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession().timeout(stepTimeout);
      await harness.registerProcedure().timeout(stepTimeout);

      const requestId = 99;
      harness.enqueueCall(requestId: requestId);
      final invocationEvent = await harness
          .nextEvent('worker_forward_native_invocation')
          .timeout(stepTimeout);
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueInvocationError(
        invocationId: invocationId,
        errorUri: 'wamp.error.runtime_error',
      );

      final errorEvent = await harness
          .nextEventMatching(const {
            'worker_forward_native_error',
            'worker_forward_native_error_error',
            'worker_forward_message',
            'worker_error',
          })
          .timeout(stepTimeout);
      expect(errorEvent['type'], equals('worker_forward_native_error'));
      expect(errorEvent['connectionId'], equals(9102));
      expect(errorEvent['requestId'], equals(requestId));

      await harness.expectInvocationCleared(invocationId).timeout(stepTimeout);
    }, skip: skipReason);

    test('handles caller cancellation', () async {
      const stepTimeout = Duration(seconds: 10);
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession().timeout(stepTimeout);
      await harness.registerProcedure().timeout(stepTimeout);

      const requestId = 123;
      harness.enqueueCall(requestId: requestId);
      final invocationEvent = await harness
          .nextEvent('worker_forward_native_invocation')
          .timeout(stepTimeout);
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueCancel(requestId: requestId, mode: 'killnowait');

      await harness.nextEvent('worker_forward_message').timeout(stepTimeout);

      await harness.expectInvocationCleared(invocationId).timeout(stepTimeout);
    }, skip: skipReason);

    test(
      'forwards native events to subscribers',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9102,
          nativeLib: nativeLib,
        );
        addTearDown(harness.dispose);

        await harness.ensureSession();
        final subscriptionId = await harness.subscribe(
          topic: 'com.example.topic',
          requestId: 1,
        );
        expect(subscriptionId, greaterThan(0));

        harness.publish(
          requestId: 2,
          topic: 'com.example.topic',
          arguments: const ['payload'],
          acknowledge: true,
        );

        final event = await harness.nextEvent('worker_forward_native_event');
        expect(event['connectionId'], equals(9102));
        expect(event['subscriptionId'], equals(subscriptionId));
        expect(event['handle'], isA<int>());
        expect(event['handle'], greaterThan(0));
      },
      tags: _zeroCopyPublishTag,
      skip: skipReason ?? _nativePublishSkipReason,
    );

    test(
      'routes HTTP request through native runtime',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9102,
          nativeLib: nativeLib,
        );
        addTearDown(harness.dispose);

        final binding = harness.binding;

        final httpSession = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'http-handler',
          authRole: 'internal',
        );
        addTearDown(httpSession.close);

        final registration = await httpSession.register(
          'com.example.http.health',
        );
        registration.onInvoke((invocation) {
          final context = HttpInvocationContext.maybeFromInvocation(invocation);
          expect(context, isNotNull, reason: 'Invocation missing HTTP context');
          expect(context!.request.method, equals('GET'));
          expect(context.request.path, equals('/api/health'));
          context.sendText(
            body: 'service:ok',
            status: 202,
            headers: const {'x-router': 'native'},
          );
        });

        final listener = binding.listeners.single;
        final socket = await Socket.connect('127.0.0.1', listener.port);
        addTearDown(socket.destroy);

        socket.write('GET /api/health HTTP/1.1\r\nHost: localhost\r\n\r\n');
        await socket.flush();

        final requestEvent = await harness.nextEvent('listener_http_request');
        expect(requestEvent['path'], equals('/api/health'));
        expect(requestEvent['realm'], equals('realm1'));
        expect(requestEvent['procedure'], equals('com.example.http.health'));

        await harness.nextEvent('http_request_dispatched');
        final responseSent = await harness.nextEvent('http_response_sent');
        expect(responseSent['listenerId'], equals(listener.listenerId));

        final response = await _readHttpResponse(socket);
        expect(response, contains('HTTP/1.1 202 Accepted'));
        expect(response, contains('x-router: native'));
        expect(response.trim(), endsWith('service:ok'));
      },
      tags: _zeroCopyPublishTag,
      skip: skipReason ?? _nativePublishSkipReason,
    );

    test('hosts MCP over HTTP using the router internal session', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9111,
        nativeLib: nativeLib,
        settings: _buildRouterSettings(enableHttp3: false, enableMcp: true),
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      final serviceSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'mcp-test-service',
        authRole: 'internal',
      );
      addTearDown(serviceSession.close);

      final registration = await serviceSession.register('app.echo');
      registration.onInvoke((invocation) {
        invocation.respondWith(
          argumentsKeywords: {'received': invocation.argumentsKeywords},
        );
      });

      final listener = binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final initialize = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-11-25'},
      });
      expect(initialize.statusCode, equals(HttpStatus.ok));
      expect(initialize.json?['result'], isA<Map<String, Object?>>());

      final initialized = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': {},
      });
      expect(initialized.statusCode, equals(HttpStatus.accepted));

      final tools = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': {},
      });
      final toolList =
          ((tools.json?['result'] as Map<String, Object?>)['tools'] as List)
              .cast<Map>();
      expect(toolList.map((tool) => tool['name']), contains('app.echo'));
      expect(
        toolList.map((tool) => tool['name']),
        contains('wamp.registration.list'),
      );
      expect(
        toolList.map((tool) => tool['name']),
        contains('connectanum.pubsub.publish'),
      );

      final echo = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'app.echo',
          'arguments': {'message': 'hello'},
        },
      });
      final echoResult =
          (echo.json?['result'] as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(echoResult['argumentsKeywords'], {
        'received': {'message': 'hello'},
      });

      final meta = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {'name': 'wamp.registration.list', 'arguments': {}},
      });
      final metaResult =
          (meta.json?['result'] as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      final exact =
          (metaResult['argumentsKeywords'] as Map<String, Object?>)['exact']
              as List;
      expect(exact, isNotEmpty);
    }, skip: skipReason);

    test(
      'does not run anonymous MCP calls as a privileged realm session',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9113,
          nativeLib: nativeLib,
          settings: _buildMcpAnonymousIsolationSettings(),
        );
        addTearDown(harness.dispose);

        final binding = harness.binding;
        final serviceSession = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-admin-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final publicRegistration = await serviceSession.register(
          'app.public.lookup',
        );
        publicRegistration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: {'value': invocation.argumentsKeywords?['id']},
          );
        });

        final adminRegistration = await serviceSession.register(
          'app.admin.reset',
        );
        adminRegistration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: {'reset': invocation.argumentsKeywords?['id']},
          );
        });

        final listener = binding.listeners.single;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        await _initializeMcp(client, listener.port, '/mcp');

        final publicResult = await _callMcpTool(
          client,
          listener.port,
          '/mcp',
          'app.public.lookup',
          {'id': 'T-1'},
        );
        expect(publicResult['isError'], isFalse);
        expect(
          (publicResult['structuredContent'] as Map)['argumentsKeywords'],
          containsPair('value', 'T-1'),
        );

        final adminResult = await _callMcpTool(
          client,
          listener.port,
          '/mcp',
          'app.admin.reset',
          {'id': 'T-1'},
        );
        expect(adminResult['isError'], isTrue);
        expect(jsonEncode(adminResult), contains('Not authorized'));
      },
      skip: skipReason,
    );

    test('smoke tests MCP router RPC pubsub and route security', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9112,
        nativeLib: nativeLib,
        settings: _buildMcpSmokeSettings(),
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      final serviceSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'mcp-smoke-service',
        authRole: 'internal',
      );
      addTearDown(serviceSession.close);

      final safeRegistration = await serviceSession.register(
        'app.safe.lookup',
        options: core.RegisterOptions(
          custom: const {
            '_ai_meta_data': {
              'short_description': 'Look up task state',
              'description': 'Reads task state without modifying data.',
              'domain': 'app',
              'entity': 'task',
              'verbs': ['lookup'],
              'tags': ['safe'],
              'publishes_events': ['app.events.audit'],
              'input_json_schema': {
                'type': 'object',
                'properties': {
                  'taskId': {'type': 'string'},
                },
                'required': ['taskId'],
              },
              'output_json_schema': {
                'type': 'object',
                'properties': {
                  'status': {'type': 'string'},
                },
              },
              'read_only_hint': true,
              'destructive_hint': false,
              'idempotent_hint': true,
              'open_world_hint': false,
            },
          },
        ),
      );
      safeRegistration.onInvoke((invocation) {
        invocation.respondWith(
          argumentsKeywords: {
            'status': 'open',
            'request': invocation.argumentsKeywords,
          },
        );
      });

      final unsafeRegistration = await serviceSession.register(
        'app.unsafe.delete',
        options: core.RegisterOptions(
          custom: const {
            '_ai_meta_data': {
              'short_description': 'Delete a task',
              'description': 'Deletes task data and requires approval.',
              'domain': 'app',
              'entity': 'task',
              'verbs': ['delete'],
              'tags': ['unsafe'],
              'danger': {'level': 'WRITE', 'requiresApproval': true},
              'read_only_hint': false,
              'destructive_hint': true,
              'idempotent_hint': false,
              'open_world_hint': false,
            },
          },
        ),
      );
      unsafeRegistration.onInvoke((invocation) {
        invocation.respondWith(
          argumentsKeywords: {
            'deleted': invocation.argumentsKeywords?['taskId'],
          },
        );
      });

      final listener = binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      await _initializeMcp(client, listener.port, '/mcp/public');
      final tools = await _listMcpTools(client, listener.port, '/mcp/public');
      final toolByName = {
        for (final tool in tools) tool['name'] as String: tool,
      };
      expect(toolByName, contains('app.safe.lookup'));
      expect(toolByName, contains('app.unsafe.delete'));
      expect(toolByName, isNot(contains('app.documented.only')));
      expect(
        toolByName['app.safe.lookup']?['annotations'],
        containsPair('readOnlyHint', true),
      );
      expect(
        toolByName['app.unsafe.delete']?['annotations'],
        containsPair('destructiveHint', true),
      );

      final safeResult = await _callMcpTool(
        client,
        listener.port,
        '/mcp/public',
        'app.safe.lookup',
        {'taskId': 'T-1'},
      );
      expect(safeResult['isError'], isFalse);
      final safeContent =
          safeResult['structuredContent'] as Map<String, Object?>;
      expect(
        (safeContent['argumentsKeywords'] as Map)['status'],
        equals('open'),
      );

      final publicUnsafeResult = await _callMcpTool(
        client,
        listener.port,
        '/mcp/public',
        'app.unsafe.delete',
        {'taskId': 'T-1'},
      );
      expect(publicUnsafeResult['isError'], isTrue);

      final hiddenCall = await _postJson(client, listener.port, '/mcp/public', {
        'jsonrpc': '2.0',
        'id': 50,
        'method': 'tools/call',
        'params': {
          'name': 'app.documented.only',
          'arguments': {'taskId': 'T-1'},
        },
      });
      expect(hiddenCall.statusCode, equals(HttpStatus.ok));
      expect(hiddenCall.json?['error'], isA<Map<String, Object?>>());
      expect(jsonEncode(hiddenCall.json?['error']), contains('Unknown MCP'));

      final describeHidden = await _callMcpTool(
        client,
        listener.port,
        '/mcp/public',
        'connectanum.api.describe',
        {'uri': 'app.documented.only'},
      );
      final hiddenApi =
          describeHidden['structuredContent'] as Map<String, Object?>;
      expect(hiddenApi['allowCall'], isFalse);

      final subscribeResult = await _callMcpTool(
        client,
        listener.port,
        '/mcp/public',
        'connectanum.pubsub.subscribe',
        {'topic': 'app.events.audit', 'queueLimit': 5},
      );
      final subscription =
          subscribeResult['structuredContent'] as Map<String, Object?>;
      final handle = subscription['handle'] as String;

      final publishResult = await _callMcpTool(
        client,
        listener.port,
        '/mcp/public',
        'connectanum.pubsub.publish',
        {
          'topic': 'app.events.audit',
          'argumentsKeywords': {'via': 'mcp'},
          'acknowledge': true,
        },
      );
      expect(
        publishResult['structuredContent'],
        containsPair('acknowledged', true),
      );

      await serviceSession.publish(
        'app.events.audit',
        argumentsKeywords: {'via': 'service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final pollResult = await _pollMcpUntilEvents(
        client,
        listener.port,
        '/mcp/public',
        handle,
      );
      expect(jsonEncode(pollResult['events']), contains('service'));

      final unauthorized = await _postJson(
        client,
        listener.port,
        '/mcp/secure',
        {
          'jsonrpc': '2.0',
          'id': 60,
          'method': 'initialize',
          'params': {'protocolVersion': '2025-11-25'},
        },
      );
      expect(unauthorized.statusCode, equals(HttpStatus.unauthorized));

      final token = await _issueTicketHttpToken(client, listener.port);
      final authHeaders = {'authorization': 'Bearer $token'};
      await _initializeMcp(
        client,
        listener.port,
        '/mcp/secure',
        headers: authHeaders,
      );
      final secureUnsafeResult = await _callMcpTool(
        client,
        listener.port,
        '/mcp/secure',
        'app.unsafe.delete',
        {'taskId': 'T-2'},
        headers: authHeaders,
      );
      expect(secureUnsafeResult['isError'], isFalse);
      final secureContent =
          secureUnsafeResult['structuredContent'] as Map<String, Object?>;
      expect(
        (secureContent['argumentsKeywords'] as Map)['deleted'],
        equals('T-2'),
      );
    }, skip: skipReason);

    test('serves OpenMetrics payload over HTTP metrics route', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9110,
        nativeLib: nativeLib,
        settings: _buildRouterSettings(enableHttp3: false, enableMetrics: true),
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      await binding.ensureInternalServicesReady();

      final listener = binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get('127.0.0.1', listener.port, '/metrics');
      final response = await request.close();
      expect(response.statusCode, equals(200));
      expect(response.headers.contentType?.mimeType, equals('text/plain'));
      final body = await utf8.decoder.bind(response).join();
      expect(body, contains('connectanum_router_realms'));
      expect(body, contains('realm="realm1"'));
      expect(body, contains('connectanum_router_http_events_total'));

      await _writeOpenMetricsSnapshot(binding, 'http_metrics_scrape');
    }, skip: skipReason);

    test('streams HTTP request and response payloads end-to-end', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9104,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      final httpSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'http-stream',
        authRole: 'internal',
      );
      addTearDown(httpSession.close);

      final payloadLength = 60000;
      final requestPayload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => (index % 26) + 65),
      );
      final responseChunk = Uint8List.fromList(
        List<int>.filled(64 * 1024, 0x5A),
      );
      final finalChunk = Uint8List.fromList('stream-complete'.codeUnits);
      const chunkCount = 3;

      final registration = await httpSession.register(
        'com.example.http.stream',
      );
      registration.onInvoke((invocation) async {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull, reason: 'Invocation missing HTTP context');
        final requestPayloadMap =
            (invocation.details.custom[HttpInvocationKeys.request] as Map)
                .cast<String, Object?>();
        expect(requestPayloadMap.containsKey('body'), isFalse);
        expect(
          requestPayloadMap[HttpInvocationKeys.requestBodyHandle],
          isA<int>(),
        );
        expect(
          requestPayloadMap[HttpInvocationKeys.requestBodyLength],
          equals(requestPayload.length),
        );
        expect(
          requestPayloadMap[HttpInvocationKeys.requestBodyStreaming],
          isA<bool>(),
        );
        final nativeBody = context!.request.nativeBody;
        expect(nativeBody, isNotNull);
        final streamedBody = BytesBuilder(copy: false);
        await for (final chunk in nativeBody!.openRead(chunkSize: 16 * 1024)) {
          streamedBody.add(chunk);
        }
        final body = streamedBody.takeBytes();
        expect(body.length, equals(requestPayload.length));
        expect(body, orderedEquals(requestPayload));

        final stream = context.streamResponse(
          status: 201,
          headers: const {
            'content-type': 'application/octet-stream',
            'x-router': 'native-stream',
          },
        );
        for (var i = 0; i < chunkCount; i++) {
          stream.add(responseChunk);
        }
        stream.close(finalChunk);
      });

      final listener = binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.post(
        '127.0.0.1',
        listener.port,
        '/api/stream',
      );
      request.contentLength = requestPayload.length;
      const chunkSize = 32768;
      await request.addStream(() async* {
        var offset = 0;
        while (offset < requestPayload.length) {
          final end = math.min(offset + chunkSize, requestPayload.length);
          yield requestPayload.sublist(offset, end);
          offset = end;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }());

      final response = await request.close();
      expect(response.statusCode, equals(201));
      expect(response.headers.value('x-router'), equals('native-stream'));

      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      final responseBody = builder.takeBytes();
      final expectedLength =
          responseChunk.length * chunkCount + finalChunk.length;
      expect(responseBody.length, equals(expectedLength));
      expect(
        responseBody.sublist(0, responseChunk.length),
        orderedEquals(responseChunk),
      );
      expect(
        responseBody.sublist(
          responseBody.length - finalChunk.length,
          responseBody.length,
        ),
        orderedEquals(finalChunk),
      );
      final resultEvent = await harness.nextEvent('http_request_result');
      expect(resultEvent['progress'], isFalse);
    }, skip: skipReason);

    test(
      'reuses HTTP/1.1 keep-alive connection after streamed request and response',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9109,
          nativeLib: nativeLib,
        );
        addTearDown(harness.dispose);

        final binding = harness.binding;
        final httpSession = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'http1-keepalive',
          authRole: 'internal',
        );
        addTearDown(httpSession.close);

        final requestPayload = Uint8List.fromList(
          List<int>.generate(70000, (index) => 65 + (index % 26)),
        );
        final responseChunk = Uint8List.fromList(
          List<int>.filled(32 * 1024, 0x72),
        );
        final finalChunk = Uint8List.fromList('stream-finished'.codeUnits);
        var invocationCount = 0;

        final registration = await httpSession.register(
          'com.example.http.stream',
        );
        registration.onInvoke((invocation) async {
          invocationCount += 1;
          final context = HttpInvocationContext.maybeFromInvocation(invocation);
          expect(context, isNotNull, reason: 'Invocation missing HTTP context');

          final nativeBody = context!.request.nativeBody;
          expect(nativeBody, isNotNull);
          final builder = BytesBuilder(copy: false);
          await for (final chunk in nativeBody!.openRead(chunkSize: 8 * 1024)) {
            builder.add(chunk);
          }
          final body = builder.takeBytes();

          if (invocationCount == 1) {
            expect(body, orderedEquals(requestPayload));
            final stream = context.streamResponse(
              status: 207,
              headers: const {
                'content-type': 'application/octet-stream',
                'x-router': 'native-h1-keepalive',
              },
            );
            for (var i = 0; i < 4; i++) {
              stream.add(responseChunk);
            }
            stream.close(finalChunk);
            return;
          }

          expect(body, isEmpty);
          context.sendText(
            status: 200,
            headers: const {'x-router': 'native-h1-second'},
            body: 'second-response',
          );
        });

        final listener = binding.listeners.single;
        final socket = await Socket.connect('127.0.0.1', listener.port);
        addTearDown(socket.destroy);
        final reader = _SocketHttpReader(socket);
        addTearDown(reader.cancel);

        socket.add(
          utf8.encode(
            'POST /api/stream HTTP/1.1\r\n'
            'Host: localhost\r\n'
            'Connection: keep-alive\r\n'
            'Content-Length: ${requestPayload.length}\r\n'
            '\r\n',
          ),
        );
        socket.add(requestPayload);
        await socket.flush();

        final firstRequestEvent = await harness.nextEvent(
          'listener_http_request',
        );
        expect(firstRequestEvent['path'], equals('/api/stream'));
        expect(firstRequestEvent['connectionId'], isA<int>());

        final firstHead = await reader.readResponseHead();
        expect(firstHead, contains('HTTP/1.1 207'));
        expect(firstHead.toLowerCase(), contains('transfer-encoding: chunked'));
        final firstBody = await reader.readChunkedBody();
        final expectedLength = responseChunk.length * 4 + finalChunk.length;
        expect(firstBody.length, equals(expectedLength));
        expect(
          firstBody.sublist(0, responseChunk.length),
          orderedEquals(responseChunk),
        );
        expect(
          firstBody.sublist(
            firstBody.length - finalChunk.length,
            firstBody.length,
          ),
          orderedEquals(finalChunk),
        );

        socket.add(
          utf8.encode(
            'POST /api/stream HTTP/1.1\r\n'
            'Host: localhost\r\n'
            'Connection: close\r\n'
            'Content-Length: 0\r\n'
            '\r\n',
          ),
        );
        await socket.flush();

        final secondRequestEvent = await harness.nextEvent(
          'listener_http_request',
        );
        expect(
          secondRequestEvent['connectionId'],
          equals(firstRequestEvent['connectionId']),
        );
        expect(secondRequestEvent['path'], equals('/api/stream'));

        final secondHead = await reader.readResponseHead();
        expect(secondHead, contains('HTTP/1.1 200 OK'));
        expect(secondHead.toLowerCase(), contains('content-length: 15'));
        final secondBody = await reader.readContentLengthBody(secondHead);
        expect(utf8.decode(secondBody), equals('second-response'));
        expect(invocationCount, equals(2));
      },
      skip: skipReason,
    );

    test('streams HTTP/2 request and response payloads end-to-end', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9105,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      final httpSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'http2-stream',
        authRole: 'internal',
      );
      addTearDown(httpSession.close);

      final payloadLength = 60000;
      final requestPayload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => index % 251),
      );
      final responseChunk = Uint8List.fromList(
        List<int>.filled(24 * 1024, 0x41),
      );
      const chunkCount = 4;

      final registration = await httpSession.register(
        'com.example.http.stream',
      );
      registration.onInvoke((invocation) async {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull, reason: 'Invocation missing HTTP context');
        final body = context!.request.body;
        expect(body, isNotNull);
        expect(body!.length, equals(requestPayload.length));
        expect(body, orderedEquals(requestPayload));

        final stream = context.streamResponse(
          status: 207,
          headers: const {'x-router': 'native-h2'},
        );
        for (var i = 0; i < chunkCount; i++) {
          stream.add(responseChunk);
        }
        stream.close();
      });

      final listener = binding.listeners.single;
      final socket = await Socket.connect('127.0.0.1', listener.port);
      addTearDown(() => socket.destroy());
      final connection = http2.ClientTransportConnection.viaSocket(socket);
      addTearDown(() async {
        await connection.finish();
      });
      await connection.onInitialPeerSettingsReceived;

      final headers = <http2.Header>[
        http2.Header.ascii(':method', 'POST'),
        http2.Header.ascii(':scheme', 'http'),
        http2.Header.ascii(':path', '/api/stream'),
        http2.Header.ascii(':authority', '127.0.0.1:${listener.port}'),
        http2.Header.ascii('content-type', 'application/octet-stream'),
        http2.Header.ascii('content-length', payloadLength.toString()),
      ];
      final stream = connection.makeRequest(headers, endStream: false);
      const chunkSize = 32768;
      var offset = 0;
      while (offset < requestPayload.length) {
        final end = math.min(offset + chunkSize, requestPayload.length);
        stream.outgoingMessages.add(
          http2.DataStreamMessage(
            Uint8List.sublistView(requestPayload, offset, end),
          ),
        );
        offset = end;
      }
      await stream.outgoingMessages.close();

      var statusCode = 0;
      final buffer = BytesBuilder(copy: false);
      await for (final message in stream.incomingMessages) {
        if (message is http2.HeadersStreamMessage) {
          for (final header in message.headers) {
            final name = utf8.decode(header.name);
            if (name == ':status') {
              statusCode =
                  int.tryParse(utf8.decode(header.value)) ?? statusCode;
            }
          }
        } else if (message is http2.DataStreamMessage) {
          buffer.add(message.bytes);
        }
      }

      expect(statusCode, equals(207));
      final responseBody = buffer.takeBytes();
      final expectedLength = responseChunk.length * chunkCount;
      expect(responseBody.length, equals(expectedLength));
      expect(
        responseBody.sublist(0, responseChunk.length),
        orderedEquals(responseChunk),
      );
      expect(
        responseBody.sublist(
          responseBody.length - responseChunk.length,
          responseBody.length,
        ),
        orderedEquals(responseChunk),
      );
    }, skip: skipReason);

    test('streams multi-MB HTTP/2 payloads and exports metrics', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9107,
        nativeLib: nativeLib,
        settings: _buildRouterSettings(enableHttp3: false, enableMetrics: true),
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      final httpSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'http2-large',
        authRole: 'internal',
      );
      addTearDown(httpSession.close);

      final payloadLength = 48 * 1024;
      final requestPayload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => (index * 5) % 251),
      );
      final responseChunk = Uint8List.fromList(
        List<int>.filled(1024 * 1024, 0x4B),
      );
      const chunkCount = 2;
      final finalChunk = Uint8List.fromList('http2-large-complete'.codeUnits);

      final registration = await httpSession.register(
        'com.example.http.stream',
      );
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull, reason: 'Invocation missing HTTP context');
        final body = context!.request.body;
        expect(body, isNotNull);
        expect(body!.length, equals(requestPayload.length));
        expect(body.first, equals(requestPayload.first));
        expect(body[1024], equals(requestPayload[1024]));
        expect(body.last, equals(requestPayload.last));

        final stream = context.streamResponse(
          status: 206,
          headers: const {
            'content-type': 'application/octet-stream',
            'x-router': 'native-h2-large',
          },
        );
        for (var i = 0; i < chunkCount; i++) {
          stream.add(responseChunk);
        }
        stream.close(finalChunk);
      });

      final listener = binding.listeners.single;
      final socket = await Socket.connect('127.0.0.1', listener.port);
      addTearDown(() => socket.destroy());
      final connection = http2.ClientTransportConnection.viaSocket(socket);
      addTearDown(() async {
        await connection.finish();
      });

      final headers = <http2.Header>[
        http2.Header.ascii(':method', 'POST'),
        http2.Header.ascii(':scheme', 'http'),
        http2.Header.ascii(':path', '/api/stream'),
        http2.Header.ascii(':authority', '127.0.0.1:${listener.port}'),
        http2.Header.ascii('content-type', 'application/octet-stream'),
        http2.Header.ascii('content-length', payloadLength.toString()),
      ];
      final stream = connection.makeRequest(headers, endStream: false);
      final responseFuture = () async {
        var statusCode = 0;
        final buffer = BytesBuilder(copy: false);
        await for (final message in stream.incomingMessages) {
          if (message is http2.HeadersStreamMessage) {
            for (final header in message.headers) {
              final name = utf8.decode(header.name);
              if (name == ':status') {
                statusCode =
                    int.tryParse(utf8.decode(header.value)) ?? statusCode;
              }
            }
          } else if (message is http2.DataStreamMessage) {
            buffer.add(message.bytes);
          }
        }
        return (statusCode: statusCode, body: buffer.takeBytes());
      }();
      const chunkSize = 16 * 1024;
      var offset = 0;
      while (offset < requestPayload.length) {
        final end = math.min(offset + chunkSize, requestPayload.length);
        stream.outgoingMessages.add(
          http2.DataStreamMessage(
            Uint8List.sublistView(requestPayload, offset, end),
          ),
        );
        offset = end;
      }
      await stream.outgoingMessages.close();
      final response = await responseFuture;
      expect(response.statusCode, equals(206));
      final responseBody = response.body;
      final expectedLength =
          responseChunk.length * chunkCount + finalChunk.length;
      expect(responseBody.length, equals(expectedLength));
      expect(
        responseBody.sublist(0, responseChunk.length),
        orderedEquals(responseChunk),
      );
      expect(
        responseBody.sublist(
          responseBody.length - finalChunk.length,
          responseBody.length,
        ),
        orderedEquals(finalChunk),
      );

      await _writeOpenMetricsSnapshot(binding, 'http2_multi_mb_stream');
    }, skip: skipReason);

    test('streams HTTP/3 request and response payloads end-to-end', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9106,
        nativeLib: nativeLib,
        config: _buildTlsConfig(),
        settings: _buildTlsSettings(),
        connectionSequence: const [],
      );
      addTearDown(harness.dispose);

      if (!harness.runtime.supportsHttp3TestClient) {
        // Skip without failing the suite when ffi-test helpers are unavailable.
        // ignore: avoid_print
        print(
          'Skipping HTTP/3 streaming test: native runtime lacks test client',
        );
        return;
      }

      final binding = harness.binding;
      final httpSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'http3-stream',
        authRole: 'internal',
      );
      addTearDown(httpSession.close);

      final payloadLength = 62000;
      final requestPayload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => (index * 3) % 251),
      );
      final responseChunk = Uint8List.fromList(
        List<int>.filled(20 * 1024, 0x6B),
      );
      final finalChunk = Uint8List.fromList('http3-complete'.codeUnits);
      const chunkCount = 5;

      final registration = await httpSession.register(
        'com.example.http.stream',
      );
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull, reason: 'Invocation missing HTTP context');
        final body = context!.request.body;
        expect(body, isNotNull);
        expect(body!.length, equals(requestPayload.length));
        expect(body, orderedEquals(requestPayload));

        final stream = context.streamResponse(
          status: 208,
          headers: const {
            'content-type': 'application/octet-stream',
            'x-router': 'native-h3',
          },
        );
        for (var i = 0; i < chunkCount; i++) {
          stream.add(responseChunk);
        }
        stream.close(finalChunk);
      });

      final listener = binding.listeners.single;
      expect(
        listener.http3Port,
        greaterThan(0),
        reason: 'Router did not expose an HTTP/3 port',
      );

      final response = await _runHttp3StreamRequestInIsolate(
        nativeLib!,
        host: '127.0.0.1',
        port: listener.http3Port,
        path: '/api/stream',
        method: 'POST',
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': payloadLength.toString(),
          'x-client': 'router-http3-test',
        },
        body: requestPayload,
        certificatePem: _http3CaCertificatePem,
      );
      expect(response.status, equals(208));
      final responseBody = response.body;
      final expectedLength =
          responseChunk.length * chunkCount + finalChunk.length;
      expect(responseBody.length, equals(expectedLength));
      expect(
        responseBody.sublist(0, responseChunk.length),
        orderedEquals(responseChunk),
      );
      expect(
        responseBody.sublist(
          responseBody.length - finalChunk.length,
          responseBody.length,
        ),
        orderedEquals(finalChunk),
      );
    }, skip: skipReason);

    test('streams multi-MB HTTP/3 payloads and exports metrics', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9108,
        nativeLib: nativeLib,
        config: _buildTlsConfig(),
        settings: _buildTlsSettings(enableMetrics: true),
        connectionSequence: const [],
      );
      addTearDown(harness.dispose);

      if (!harness.runtime.supportsHttp3TestClient) {
        // ignore: avoid_print
        print(
          'Skipping HTTP/3 large streaming test: native runtime lacks test client',
        );
        return;
      }

      final binding = harness.binding;
      final httpSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'http3-large',
        authRole: 'internal',
      );
      addTearDown(httpSession.close);

      final payloadLength = 3 * 1024 * 1024 + 509;
      final requestPayload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => (index * 7) % 251),
      );
      final responseChunk = Uint8List.fromList(
        List<int>.filled(1024 * 1024, 0x65),
      );
      const chunkCount = 2;
      final finalChunk = Uint8List.fromList('http3-large-complete'.codeUnits);

      final registration = await httpSession.register(
        'com.example.http.stream',
      );
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull, reason: 'Invocation missing HTTP context');
        final body = context!.request.body;
        expect(body, isNotNull);
        expect(body!.length, equals(requestPayload.length));
        expect(body.first, equals(requestPayload.first));
        expect(body[2048], equals(requestPayload[2048]));
        expect(body.last, equals(requestPayload.last));

        final stream = context.streamResponse(
          status: 209,
          headers: const {
            'content-type': 'application/octet-stream',
            'x-router': 'native-h3-large',
          },
        );
        for (var i = 0; i < chunkCount; i++) {
          stream.add(responseChunk);
        }
        stream.close(finalChunk);
      });

      final listener = binding.listeners.single;
      expect(
        listener.http3Port,
        greaterThan(0),
        reason: 'Router did not expose an HTTP/3 port',
      );

      final response = await _runHttp3StreamRequestInIsolate(
        nativeLib!,
        host: '127.0.0.1',
        port: listener.http3Port,
        path: '/api/stream',
        method: 'POST',
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': payloadLength.toString(),
          'x-client': 'router-http3-large-test',
        },
        body: requestPayload,
        certificatePem: _http3CaCertificatePem,
      );
      expect(response.status, equals(209));
      final responseBody = response.body;
      final expectedLength =
          responseChunk.length * chunkCount + finalChunk.length;
      expect(responseBody.length, equals(expectedLength));
      expect(
        responseBody.sublist(0, responseChunk.length),
        orderedEquals(responseChunk),
      );
      expect(
        responseBody.sublist(
          responseBody.length - finalChunk.length,
          responseBody.length,
        ),
        orderedEquals(finalChunk),
      );

      await _writeOpenMetricsSnapshot(binding, 'http3_multi_mb_stream');
    }, skip: skipReason);

    test('reports HTTP/2 connection as pending protocol', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      harness.runtime.setConnectionProtocol(
        harness.connectionId,
        NativeConnectionProtocol.http2,
      );
      harness.runtime.enqueueHttp2Handshake(
        harness.connectionId,
        NativeHttp2Handshake.synthetic(
          handle: 1,
          protocol: 'http/2',
          alpn: 'h2',
          listenerProtocols: const <String>['rawsocket', 'http', 'http2'],
          onRelease: () {},
        ),
      );
      harness.runtime.queueConnection(harness.connectionId);

      Map<String, Object?> pending;
      while (true) {
        pending = await harness.nextEvent('listener_protocol_pending');
        if (pending['protocol'] == 'http2') {
          break;
        }
      }

      expect(pending['protocol'], 'http2');
      final details = pending['details'] as Map?;
      expect(details?['protocol'], 'http/2');
      expect(details?['alpn'], 'h2');
      final listenerProtocols = (details?['listenerProtocols'] as List?)
          ?.cast<String>();
      expect(listenerProtocols, isNotNull);
      expect(
        listenerProtocols,
        containsAll(<String>['rawsocket', 'http', 'http2']),
      );
    }, skip: skipReason);

    test('reports HTTP/3 connection as pending protocol', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9103,
        nativeLib: nativeLib,
        config: _buildTlsConfig(),
        settings: _buildTlsSettings(),
      );
      addTearDown(harness.dispose);

      harness.runtime.setConnectionProtocol(
        harness.connectionId,
        NativeConnectionProtocol.http3,
      );
      harness.runtime.enqueueHttp3Handshake(
        harness.connectionId,
        NativeHttp3Handshake.synthetic(
          handle: 1,
          protocol: 'http/3',
          alpn: 'h3',
          listenerProtocols: const <String>[
            'rawsocket',
            'http',
            'http2',
            'http3',
          ],
          onRelease: () {},
        ),
      );
      harness.runtime.queueConnection(harness.connectionId);

      Map<String, Object?> pending;
      while (true) {
        pending = await harness.nextEvent('listener_protocol_pending');
        if (pending['protocol'] == 'http3') {
          break;
        }
      }

      expect(pending['protocol'], 'http3');
      final details = pending['details'] as Map?;
      expect(details?['protocol'], 'http/3');
      expect(details?['alpn'], 'h3');
      final http3Port = details?['http3Port'];
      if (http3Port != null) {
        expect(http3Port, isA<int>());
        expect(http3Port, greaterThan(0));
      }
      final listenerProtocols = (details?['listenerProtocols'] as List?)
          ?.cast<String>();
      expect(listenerProtocols, isNotNull);
      expect(
        listenerProtocols,
        containsAll(<String>['rawsocket', 'http', 'http2', 'http3']),
      );
    }, skip: skipReason);
  });
}

final String _http3CertificatePem = _loadRouterCert('http3_cert.pem');
final String _http3PrivateKeyPem = _loadRouterCert('http3_key.pem');
final String _http3CaCertificatePem = _loadRouterCert('http3_ca_cert.pem');

final List<SniCertificate> _http3SniCertificates = [
  SniCertificate(
    hostname: 'localhost',
    certificateChainPem: _http3CertificatePem,
    privateKeyPem: _http3PrivateKeyPem,
  ),
];

String _loadRouterCert(String fileName) {
  final candidates = <Uri>[
    Uri.base.resolve('packages/connectanum_router/test/certs/$fileName'),
  ];
  if (Platform.script.scheme == 'file') {
    candidates.add(Platform.script.resolve('certs/$fileName'));
  }
  for (final uri in candidates) {
    if (uri.scheme != 'file') {
      continue;
    }
    final file = File.fromUri(uri);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  final fallbacks = <String>[
    'packages/connectanum_router/test/certs/$fileName',
    'test/certs/$fileName',
    fileName,
  ];
  for (final path in fallbacks) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError('Missing router test certificate $fileName');
}

RouterConfig _buildConfig() => _buildRouterConfig(enableTls: false);
RouterConfig _buildTlsConfig() => _buildRouterConfig(enableTls: true);

RouterConfig _buildRouterConfig({required bool enableTls}) => RouterConfig(
  endpoints: [
    Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: enableTls ? TlsMode.native : TlsMode.disabled,
      idleTimeout: const Duration(seconds: 30),
      maxRawSocketSizeExponent: 16,
      sniCertificates: enableTls ? _http3SniCertificates : const [],
    ),
  ],
);

RouterSettings _buildSettings({bool enableMetrics = false}) =>
    _buildRouterSettings(enableHttp3: false, enableMetrics: enableMetrics);
RouterSettings _buildTlsSettings({bool enableMetrics = false}) =>
    _buildRouterSettings(enableHttp3: true, enableMetrics: enableMetrics);

RouterSettings _buildRouterSettings({
  required bool enableHttp3,
  bool enableMetrics = false,
  bool enableMcp = false,
}) {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
            'cancel',
          ]),
      ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('internal')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
            'cancel',
          ]),
      ),
    );

  final benchRealm = RealmSettingsBuilder('bench.control')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
            'cancel',
          ]),
      ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('bench')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
            'cancel',
          ]),
      ),
    );

  final listener = ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
    ..addAuthMethod('anonymous')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..addProtocol(ListenerProtocol.http)
    ..addProtocol(ListenerProtocol.http2);
  if (enableHttp3) {
    listener.addProtocol(ListenerProtocol.http3);
  }
  final routes = <HttpRouteSettings>[
    const HttpRouteSettings(
      match: HttpRouteMatch(path: '/api/health'),
      action: HttpRouteAction(
        type: HttpRouteActionType.rpc,
        procedure: 'com.example.http.health',
        realm: 'realm1',
      ),
    ),
    const HttpRouteSettings(
      match: HttpRouteMatch(path: '/api/stream'),
      action: HttpRouteAction(
        type: HttpRouteActionType.rpc,
        procedure: 'com.example.http.stream',
        realm: 'realm1',
      ),
    ),
  ];
  if (enableMetrics) {
    routes.add(
      const HttpRouteSettings(
        match: HttpRouteMatch(path: '/metrics'),
        action: HttpRouteAction(
          type: HttpRouteActionType.rpc,
          procedure: 'connectanum.metrics.openmetrics',
          realm: 'connectanum.metrics',
        ),
      ),
    );
  }
  if (enableMcp) {
    routes.add(
      const HttpRouteSettings(
        match: HttpRouteMatch(path: '/mcp'),
        action: HttpRouteAction(
          type: HttpRouteActionType.mcp,
          realm: 'realm1',
          options: {'tool_list_page_size': 100},
        ),
      ),
    );
  }
  listener
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      HttpListenerSettings(
        alpn: enableHttp3
            ? const ['http/1.1', 'h2', 'h3']
            : const ['http/1.1', 'h2'],
        http3: enableHttp3 ? const Http3Settings(enabled: true) : null,
        routes: routes,
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(realmBuilder)
    ..addRealmFromBuilder(benchRealm)
    ..addListenerFromBuilder(listener)
    ..addAuthenticator(
      'anonymous',
      const AuthenticatorDefinition(type: 'anonymous'),
    );

  if (enableMetrics) {
    final metricsRealm = RealmSettingsBuilder('connectanum.metrics')
      ..addAuthMethod('anonymous')
      ..addRoleFromBuilder(
        RoleSettingsBuilder('metrics')..addPermissionFromBuilder(
          PermissionSettingsBuilder('')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const [
              'register',
              'unregister',
              'subscribe',
              'unsubscribe',
              'publish',
              'call',
            ]),
        ),
      );
    final metricsInternalRealm =
        InternalRealmSettingsBuilder('connectanum.metrics')
          ..setAuthId('metrics-daemon')
          ..setAuthRole('metrics')
          ..addService('metrics');
    builder
      ..addRealmFromBuilder(metricsRealm)
      ..addInternalRealmFromBuilder(metricsInternalRealm)
      ..metrics(
        const MetricsSettings(
          openMetrics: OpenMetricsSettings(
            enabled: true,
            listen: '127.0.0.1:0',
            path: '/metrics',
            realm: 'connectanum.metrics',
          ),
        ),
      );
  }

  return builder.build();
}

RouterSettings _buildMcpAnonymousIsolationSettings() {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('app.public.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const ['call']),
      ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('internal')..addPermissionFromBuilder(
        PermissionSettingsBuilder('app.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
          ]),
      ),
    );

  final listener = ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
    ..setSessionProfile('public-wamp')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..addProtocol(ListenerProtocol.http)
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      const HttpListenerSettings(
        routes: [
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/mcp'),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: 'realm1',
              options: {'tool_list_page_size': 100},
            ),
          ),
        ],
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(realmBuilder)
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-wamp')
            ..addAuthMethod('anonymous'),
        )
        ..addListenerFromBuilder(listener)
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        ))
      .build();
}

RouterSettings _buildMcpSmokeSettings() {
  const mcpOptions = <String, Object?>{
    'tool_list_page_size': 100,
    'procedures': [
      {
        'procedure': 'app.documented.only',
        'title': 'Documented but not callable',
        'description': 'Visible in API metadata without becoming an MCP tool.',
        'allow_call': false,
        '_ai_meta_data': {
          'short_description': 'Documented API entry',
          'description': 'Documents a WAMP procedure without exposing calls.',
          'domain': 'app',
          'entity': 'task',
          'verbs': ['document'],
          'tags': ['safe', 'metadata'],
          'read_only_hint': true,
          'destructive_hint': false,
          'idempotent_hint': true,
          'open_world_hint': false,
        },
      },
    ],
    'topics': [
      {
        'topic': 'app.events.audit',
        'title': 'Audit events',
        'description': 'Task audit events exposed through MCP pub/sub.',
        '_ai_meta_data': {
          'short_description': 'Task audit stream',
          'description': 'Events emitted when task state changes.',
          'domain': 'app',
          'entity': 'task',
          'tags': ['safe', 'events'],
          'output_json_schema': {
            'type': 'object',
            'properties': {
              'via': {'type': 'string'},
            },
          },
        },
      },
    ],
  };

  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addAuthMethod('ticket', options: const {'authenticator': 'ticket-basic'})
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.safe.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.events.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['publish', 'subscribe', 'unsubscribe']),
        ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('member')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.events.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['publish', 'subscribe', 'unsubscribe']),
        ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('internal')..addPermissionFromBuilder(
        PermissionSettingsBuilder('app.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
          ]),
      ),
    );

  final listener = ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
    ..setSessionProfile('public-wamp')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..addProtocol(ListenerProtocol.http)
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      const HttpListenerSettings(
        sessionProfile: 'public-http',
        routes: [
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/auth'),
            action: HttpRouteAction(
              type: HttpRouteActionType.auth,
              sessionProfile: 'mcp-ticket',
              options: <String, Object?>{
                'allow_insecure_transport': true,
                'token_ttl_ms': 60000,
                'refresh_token_ttl_ms': 300000,
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/mcp/public'),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: 'realm1',
              sessionProfile: 'mcp-public',
              options: mcpOptions,
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/mcp/secure'),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: 'realm1',
              sessionProfile: 'mcp-ticket',
              options: <String, Object?>{
                ...mcpOptions,
                'allow_insecure_transport': true,
              },
            ),
          ),
        ],
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(realmBuilder)
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-wamp')
            ..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-http'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp-public')
            ..setRealm('realm1')
            ..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp-ticket')
            ..setRealm('realm1')
            ..setAuthMethods(const ['ticket']),
        )
        ..addListenerFromBuilder(listener)
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        )
        ..addAuthenticator(
          'ticket-basic',
          const AuthenticatorDefinition(
            type: 'ticket',
            options: <String, Object?>{
              'secrets': <String, Object?>{
                'user-1': <String, Object?>{
                  'ticket': 'signed-token',
                  'role': 'member',
                  'provider': 'ticket-db',
                },
              },
            },
          ),
        ))
      .build();
}

Future<NativeHttpTestResponse> _runHttp3StreamRequestInIsolate(
  String nativeLibPath, {
  required String host,
  required int port,
  required String path,
  required String method,
  required Map<String, String> headers,
  required Uint8List body,
  required String certificatePem,
}) async {
  final transferableBody = TransferableTypedData.fromList(<Uint8List>[body]);
  final headerCopy = Map<String, String>.from(headers);
  final result = await Isolate.run<Map<String, Object?>>(() {
    final library = ffi.DynamicLibrary.open(nativeLibPath);
    final bindings = CtFfiBindings(library);
    final requestFn = bindings.ctTestHttp3StreamRequestHandle;
    final bufferFree = bindings.ctTestBufferFreeHandle;
    if (requestFn == null || bufferFree == null) {
      throw UnsupportedError('HTTP/3 test client is not available');
    }
    final payload = transferableBody.materialize().asUint8List();
    return using((arena) {
      final hostPtr = host.toNativeUtf8(allocator: arena);
      final pathPtr = path.toNativeUtf8(allocator: arena);
      final methodPtr = method.toNativeUtf8(allocator: arena);
      final certPtr = certificatePem.toNativeUtf8(allocator: arena);

      final headerCount = headerCopy.length;
      final headerArray = headerCount == 0
          ? ffi.nullptr
          : arena<CtHttpHeader>(headerCount);
      var index = 0;
      headerCopy.forEach((name, value) {
        final namePtr = name.toNativeUtf8(allocator: arena);
        final valuePtr = value.toNativeUtf8(allocator: arena);
        headerArray[index]
          ..namePtr = namePtr.cast()
          ..nameLen = name.length
          ..valuePtr = valuePtr.cast()
          ..valueLen = value.length;
        index += 1;
      });

      final bodyPtr = payload.isEmpty
          ? ffi.nullptr
          : arena<ffi.Uint8>(payload.length);
      if (payload.isNotEmpty) {
        bodyPtr.asTypedList(payload.length).setAll(0, payload);
      }

      final statusPtr = arena<ffi.Int32>();
      final responsePtrPtr = arena<ffi.Pointer<ffi.Uint8>>();
      final responseLenPtr = arena<ffi.IntPtr>();

      final resultCode = requestFn(
        hostPtr,
        port,
        pathPtr,
        methodPtr,
        headerArray,
        headerCount,
        bodyPtr,
        payload.length,
        certPtr,
        statusPtr,
        responsePtrPtr,
        responseLenPtr,
      );
      if (resultCode != NativeTransportErrorCode.success) {
        throw NativeTransportException(
          resultCode,
          'HTTP/3 test request failed',
        );
      }
      final status = statusPtr.value;
      final responsePtr = responsePtrPtr.value;
      final responseLen = responseLenPtr.value;
      Uint8List responseBody;
      if (responsePtr == ffi.nullptr || responseLen == 0) {
        responseBody = Uint8List(0);
      } else {
        responseBody = Uint8List.fromList(responsePtr.asTypedList(responseLen));
        bufferFree(responsePtr, responseLen);
      }
      return <String, Object?>{'status': status, 'body': responseBody};
    });
  });
  final status = result['status'] as int? ?? 0;
  final responseBody = (result['body'] as Uint8List?) ?? Uint8List(0);
  return NativeHttpTestResponse(status, responseBody);
}

Future<void> _writeOpenMetricsSnapshot(
  RouterBinding binding,
  String name,
) async {
  final artifactDir = Platform.environment['CONNECTANUM_ARTIFACT_DIR'];
  if (artifactDir == null || artifactDir.isEmpty) {
    return;
  }
  final snapshot = await binding.collectMetrics();
  final openMetrics = await binding.collectOpenMetricsText(snapshot);
  final dir = Directory(artifactDir);
  await dir.create(recursive: true);
  final sanitized = name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  if (openMetrics != null) {
    final metricsFile = File('${dir.path}/$sanitized.openmetrics');
    await metricsFile.writeAsString(openMetrics);
  }
  final jsonFile = File('${dir.path}/$sanitized.metrics.json');
  await jsonFile.writeAsString(jsonEncode(snapshot.toJson()));
}

Future<RealmSnapshot> _fetchSnapshot(SendPort commandPort) async {
  final replyPort = ReceivePort();
  commandPort.send(
    RealmSnapshotCommand(
      realmUri: 'realm1',
      knownVersion: null,
      replyPort: replyPort.sendPort,
    ),
  );
  final response = await replyPort.first as RealmSnapshotResponse;
  replyPort.close();
  return response.snapshot;
}

class _SocketHttpReader {
  _SocketHttpReader(Socket socket)
    : _iterator = StreamIterator<List<int>>(socket);

  final StreamIterator<List<int>> _iterator;
  final List<int> _prefetched = <int>[];

  Future<String> readResponseHead() async {
    const terminator = [13, 10, 13, 10];
    while (true) {
      final headerEnd = _indexOfSequence(_prefetched, terminator);
      if (headerEnd != -1) {
        final head = utf8.decode(_prefetched.sublist(0, headerEnd + 4));
        _prefetched.removeRange(0, headerEnd + 4);
        return head;
      }
      if (!await _iterator.moveNext()) {
        throw StateError('HTTP response headers incomplete');
      }
      _prefetched.addAll(_iterator.current);
    }
  }

  Future<List<int>> readChunkedBody() async {
    final decoded = <int>[];
    while (true) {
      final line = await _readLine();
      final chunkLen = int.parse(utf8.decode(line).trim(), radix: 16);
      if (chunkLen == 0) {
        final trailer = await _readExact(2);
        expect(trailer, equals(utf8.encode('\r\n')));
        return decoded;
      }
      decoded.addAll(await _readExact(chunkLen));
      final suffix = await _readExact(2);
      expect(suffix, equals(utf8.encode('\r\n')));
    }
  }

  Future<List<int>> readContentLengthBody(String headers) async {
    final contentLength = _parseContentLength(headers);
    return _readExact(contentLength);
  }

  Future<void> cancel() => _iterator.cancel();

  Future<List<int>> _readExact(int len) async {
    final output = <int>[];
    while (output.length < len) {
      if (_prefetched.isNotEmpty) {
        final take = math.min(len - output.length, _prefetched.length);
        output.addAll(_prefetched.sublist(0, take));
        _prefetched.removeRange(0, take);
        continue;
      }
      if (!await _iterator.moveNext()) {
        throw StateError('HTTP response body incomplete');
      }
      _prefetched.addAll(_iterator.current);
    }
    return output;
  }

  Future<List<int>> _readLine() async {
    while (true) {
      final lineEnd = _indexOfSequence(_prefetched, const [13, 10]);
      if (lineEnd != -1) {
        final line = _prefetched.sublist(0, lineEnd);
        _prefetched.removeRange(0, lineEnd + 2);
        return line;
      }
      if (!await _iterator.moveNext()) {
        throw StateError('HTTP chunk line incomplete');
      }
      _prefetched.addAll(_iterator.current);
    }
  }
}

Future<String> _readHttpResponse(Socket socket) async {
  final iterator = StreamIterator<List<int>>(socket);
  final collected = <int>[];
  const terminator = [13, 10, 13, 10];
  var headerEnd = -1;

  while (headerEnd == -1) {
    if (!await iterator.moveNext()) {
      break;
    }
    collected.addAll(iterator.current);
    headerEnd = _indexOfSequence(collected, terminator);
  }
  if (headerEnd == -1) {
    await iterator.cancel();
    throw StateError('HTTP response headers incomplete');
  }
  final headerText = utf8.decode(collected.sublist(0, headerEnd));
  final contentLength = _parseContentLength(headerText);
  final bodyStart = headerEnd + terminator.length;
  final expectedLength = bodyStart + contentLength;

  while (collected.length < expectedLength) {
    if (!await iterator.moveNext()) {
      await iterator.cancel();
      throw StateError('HTTP response body incomplete');
    }
    collected.addAll(iterator.current);
  }
  await iterator.cancel();
  return utf8.decode(collected);
}

Future<({int statusCode, Map<String, Object?>? json, String body})> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> payload, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  headers.forEach(request.headers.set);
  final bodyBytes = utf8.encode(jsonEncode(payload));
  request.contentLength = bodyBytes.length;
  request.add(bodyBytes);
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  Object? decoded;
  if (body.isNotEmpty) {
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
  }
  return (
    statusCode: response.statusCode,
    json: decoded is Map ? decoded.cast<String, Object?>() : null,
    body: body,
  );
}

Future<void> _initializeMcp(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final initialize = await _postJson(client, port, path, {
    'jsonrpc': '2.0',
    'id': 'initialize',
    'method': 'initialize',
    'params': {'protocolVersion': '2025-11-25'},
  }, headers: headers);
  expect(initialize.statusCode, equals(HttpStatus.ok));
  expect(initialize.json?['result'], isA<Map<String, Object?>>());

  final initialized = await _postJson(client, port, path, {
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
    'params': const <String, Object?>{},
  }, headers: headers);
  expect(initialized.statusCode, equals(HttpStatus.accepted));
}

Future<List<Map<String, Object?>>> _listMcpTools(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final response = await _postJson(client, port, path, {
    'jsonrpc': '2.0',
    'id': 'tools-list',
    'method': 'tools/list',
    'params': const <String, Object?>{},
  }, headers: headers);
  expect(response.statusCode, equals(HttpStatus.ok));
  final result = response.json?['result'] as Map<String, Object?>;
  final tools = result['tools'] as List;
  return [
    for (final tool in tools)
      if (tool is Map) tool.cast<String, Object?>(),
  ];
}

Future<Map<String, Object?>> _callMcpTool(
  HttpClient client,
  int port,
  String path,
  String name,
  Map<String, Object?> arguments, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final response = await _postJson(client, port, path, {
    'jsonrpc': '2.0',
    'id': 'call-$name',
    'method': 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  }, headers: headers);
  expect(response.statusCode, equals(HttpStatus.ok));
  final error = response.json?['error'];
  if (error != null) {
    fail('MCP tool call $name returned JSON-RPC error: ${jsonEncode(error)}');
  }
  return (response.json?['result'] as Map).cast<String, Object?>();
}

Future<Map<String, Object?>> _pollMcpUntilEvents(
  HttpClient client,
  int port,
  String path,
  String handle, {
  Map<String, String> headers = const <String, String>{},
}) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final result = await _callMcpTool(
      client,
      port,
      path,
      'connectanum.pubsub.poll',
      {'handle': handle, 'limit': 10},
      headers: headers,
    );
    final structured = result['structuredContent'] as Map<String, Object?>;
    final events = structured['events'] as List? ?? const [];
    if (events.isNotEmpty) {
      return structured;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for MCP subscription events for $handle');
}

Future<String> _issueTicketHttpToken(
  HttpClient client,
  int port, {
  String realm = 'realm1',
  String authId = 'user-1',
  String ticket = 'signed-token',
}) async {
  final start = await _postJson(client, port, '/auth', {
    'realm': realm,
    'authmethod': 'ticket',
    'authid': authId,
  });
  expect(start.statusCode, equals(HttpStatus.unauthorized), reason: start.body);
  final startJson = start.json;
  expect(startJson, isNotNull);
  final state = startJson!['state'] as String;

  final authenticate = await core.TicketAuthentication(
    ticket,
  ).challenge(core.Extra());
  final success = await _postJson(client, port, '/auth', {
    'state': state,
    'signature': authenticate.signature,
    'extra': authenticate.extra,
  });
  expect(success.statusCode, equals(HttpStatus.ok), reason: success.body);
  final successJson = success.json;
  expect(successJson, isNotNull);
  return successJson!['access_token'] as String;
}

int _parseContentLength(String headers) {
  for (final line in headers.split('\r\n')) {
    final separator = line.indexOf(':');
    if (separator == -1) {
      continue;
    }
    final name = line.substring(0, separator).trim().toLowerCase();
    if (name != 'content-length') {
      continue;
    }
    final value = line.substring(separator + 1).trim();
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw StateError('Invalid Content-Length header: $value');
    }
    return parsed;
  }
  throw StateError('Content-Length header missing');
}

int _indexOfSequence(List<int> source, List<int> needle) {
  if (needle.isEmpty || source.length < needle.length) {
    return -1;
  }
  final end = source.length - needle.length;
  for (var i = 0; i <= end; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (source[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }
  return -1;
}

Future<int> _registerProcedureWithRetry(
  SendPort commandPort,
  int sessionId, {
  Map<String, Object?> details = const {},
  int maxAttempts = 50,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final replyPort = ReceivePort();
    commandPort.send(
      ProcedureRegisterCommand(
        realmUri: 'realm1',
        sessionId: sessionId,
        procedure: 'com.example.proc',
        details: Map<String, Object?>.from(details),
        replyPort: replyPort.sendPort,
      ),
    );
    final result = await replyPort.first;
    replyPort.close();
    if (result is int) {
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out registering procedure for session $sessionId');
}

Future<int> _awaitSessionId(
  SendPort commandPort,
  int connectionId, {
  int maxAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final snapshot = await _fetchSnapshot(commandPort);
    for (final session in snapshot.sessions) {
      if (session.connectionId == connectionId) {
        return session.id;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Session for connection $connectionId not found');
}

Future<int> _awaitSubscriptionId(
  SendPort commandPort, {
  required int sessionId,
  required String topic,
  int maxAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final snapshot = await _fetchSnapshot(commandPort);
    for (final subscription in snapshot.subscriptions) {
      if (subscription.topic == topic) {
        final match = subscription.subscribers.any(
          (subscriber) => subscriber.sessionId == sessionId,
        );
        if (match) {
          return subscription.id;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Subscription for topic $topic not found');
}

void _enqueueHello(_HybridRuntime runtime, int connectionId) {
  final frame = utf8.encode(
    '[1,"realm1",{"roles":{"caller":{"features":{}},"callee":{"features":{}}}}]',
  );
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueCall(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required bool receiveProgress,
}) {
  final options = receiveProgress ? '{"receive_progress":true}' : '{}';
  final frame = utf8.encode('[48,$requestId,$options,"com.example.proc"]');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueYield(
  _HybridRuntime runtime,
  int connectionId,
  int invocationId, {
  required bool progress,
  required List<dynamic> arguments,
}) {
  final details = progress ? '{"progress":true}' : '{}';
  final frame = utf8.encode(
    '[70,$invocationId,$details,${json.encode(arguments)}]',
  );
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueInvocationError(
  _HybridRuntime runtime,
  int connectionId,
  int invocationId, {
  required String errorUri,
}) {
  final frame = utf8.encode('[8,68,$invocationId,{},"$errorUri"]');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueCancel(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required String mode,
}) {
  final frame = utf8.encode('[49,$requestId,{"mode":"$mode"}]');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueSubscribe(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required String topic,
}) {
  final frame = utf8.encode('[32,$requestId,{},"$topic"]');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueuePublish(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required String topic,
  List<dynamic>? arguments,
  Map<String, Object?>? argumentsKeywords,
  required bool acknowledge,
}) {
  final options = <String, Object?>{if (acknowledge) 'acknowledge': true};
  final buffer = StringBuffer()
    ..write('[16,$requestId,${json.encode(options)},"$topic"');
  if (arguments != null) {
    buffer
      ..write(',')
      ..write(json.encode(arguments));
    if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
      buffer
        ..write(',')
        ..write(json.encode(argumentsKeywords));
    }
  } else if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
    buffer.write(',[],${json.encode(argumentsKeywords)}');
  }
  buffer.write(']');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(utf8.encode(buffer.toString())),
  );
}
