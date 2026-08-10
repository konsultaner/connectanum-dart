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

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_router/src/native/ffi_bindings.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/auth/authorization.dart';
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
    String? callerAuthId,
    String? callerAuthRole,
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

      final registration = await serviceSession.register(
        'app.echo',
        options: core.RegisterOptions(
          custom: const <String, Object?>{
            'input_json_schema': {
              'type': 'object',
              'properties': {
                'message': {'type': 'string', 'x-mcp-header': 'Message'},
              },
            },
          },
        ),
      );
      registration.onInvoke((invocation) {
        invocation.respondWith(
          argumentsKeywords: {'received': invocation.argumentsKeywords},
        );
      });

      final listener = binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final directTools = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-tools-list',
          'method': 'tools/list',
          'params': {},
        },
        headers: {'Mcp-Method': 'tools/list'},
      );
      expect(directTools.statusCode, equals(HttpStatus.ok));
      expect(directTools.headers['mcp-session-id'], isNull);
      final directToolList =
          ((directTools.json?['result'] as Map<String, Object?>)['tools']
                  as List)
              .cast<Map>();
      expect(directToolList.map((tool) => tool['name']), contains('app.echo'));

      final directToolsWithHeaderWhitespace = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-tools-list-header-whitespace',
          'method': 'tools/list',
          'params': {},
        },
        headers: {'Mcp-Method': ' tools/list '},
      );
      expect(directToolsWithHeaderWhitespace.statusCode, equals(HttpStatus.ok));
      expect(directToolsWithHeaderWhitespace.headers['mcp-session-id'], isNull);

      final directInvalidMethod =
          await _postJson(client, listener.port, '/mcp', {
            'jsonrpc': '2.0',
            'id': 'direct-invalid-method',
            'method': 'tools/list\n',
            'params': {},
          });
      expect(directInvalidMethod.statusCode, equals(HttpStatus.ok));
      expect(
        (directInvalidMethod.json?['error'] as Map<String, Object?>)['code'],
        equals(-32600),
      );
      expect(
        jsonEncode(directInvalidMethod.json?['error']),
        contains('method must not contain whitespace or control characters'),
      );

      final directToolCall = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-tools-call',
          'method': 'tools/call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'direct-standard'},
          },
        },
        headers: {
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app.echo',
          'Mcp-Param-Message': 'direct-standard',
        },
      );
      expect(directToolCall.statusCode, equals(HttpStatus.ok));
      expect(directToolCall.headers['mcp-session-id'], isNull);
      expect(
        jsonEncode(directToolCall.json?['result']),
        contains('direct-standard'),
      );

      final directToolCallWithHeaderWhitespace = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-tools-call-header-whitespace',
          'method': 'tools/call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'direct-header-whitespace'},
          },
        },
        headers: {
          'Mcp-Method': ' tools/call ',
          'Mcp-Name': ' app.echo ',
          'Mcp-Param-Message': 'direct-header-whitespace',
        },
      );
      expect(
        directToolCallWithHeaderWhitespace.statusCode,
        equals(HttpStatus.ok),
      );
      expect(
        directToolCallWithHeaderWhitespace.headers['mcp-session-id'],
        isNull,
      );
      expect(
        jsonEncode(directToolCallWithHeaderWhitespace.json?['result']),
        contains('direct-header-whitespace'),
      );

      final directConnectanumToolCall = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-connectanum-tool-call',
          'method': 'connectanum.tool.call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'direct-connectanum'},
          },
        },
        headers: {
          'Mcp-Method': 'connectanum.tool.call',
          'Mcp-Name': 'app.echo',
          'Mcp-Param-Message': 'direct-connectanum',
        },
      );
      expect(directConnectanumToolCall.statusCode, equals(HttpStatus.ok));
      expect(directConnectanumToolCall.headers['mcp-session-id'], isNull);
      expect(
        jsonEncode(directConnectanumToolCall.json?['result']),
        contains('direct-connectanum'),
      );

      final directResources = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'direct-resources-list',
        'method': 'resources/list',
        'params': {},
      });
      expect(directResources.statusCode, equals(HttpStatus.ok));
      final directResourceList =
          ((directResources.json?['result']
                      as Map<String, Object?>)['resources']
                  as List)
              .cast<Map>();
      expect(
        directResourceList.map((resource) => resource['uri']),
        contains('app://example/context'),
      );

      final directResourceRead = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-resources-read',
          'method': 'resources/read',
          'params': {'uri': 'app://example/context'},
        },
      );
      expect(directResourceRead.statusCode, equals(HttpStatus.ok));
      expect(
        jsonEncode(directResourceRead.json?['result']),
        contains('router-hosted MCP'),
      );

      final directPrompt = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'direct-prompts-get',
        'method': 'prompts/get',
        'params': {
          'name': 'summarize-task',
          'arguments': {'taskId': 'T-direct'},
        },
      });
      expect(directPrompt.statusCode, equals(HttpStatus.ok));
      expect(jsonEncode(directPrompt.json?['result']), contains('T-direct'));

      final directHeaderMismatch = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-header-mismatch',
          'method': 'resources/list',
          'params': {},
        },
        headers: {'Mcp-Method': 'tools/list'},
      );
      expect(directHeaderMismatch.statusCode, equals(HttpStatus.badRequest));
      expect(
        (directHeaderMismatch.json?['error'] as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(directHeaderMismatch.json?['error']),
        contains('Mcp-Method'),
      );

      final initialize = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-11-25'},
      });
      expect(initialize.statusCode, equals(HttpStatus.ok));
      final initializeResult =
          initialize.json?['result'] as Map<String, Object?>;
      expect(initializeResult, isA<Map<String, Object?>>());
      final capabilities =
          initializeResult['capabilities'] as Map<String, Object?>;
      expect(capabilities['resources'], isA<Map<String, Object?>>());
      expect(capabilities['prompts'], isA<Map<String, Object?>>());

      final initialized = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': {},
      });
      expect(initialized.statusCode, equals(HttpStatus.accepted));

      final ping = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'ping',
        'method': 'ping',
        'params': {},
      });
      expect(ping.statusCode, equals(HttpStatus.ok));
      expect(ping.json?['result'], isEmpty);

      final resources = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'resources-list',
        'method': 'resources/list',
        'params': {},
      });
      expect(resources.statusCode, equals(HttpStatus.ok));
      final resourceList =
          ((resources.json?['result'] as Map<String, Object?>)['resources']
                  as List)
              .cast<Map>();
      expect(
        resourceList.map((resource) => resource['uri']),
        contains('app://example/context'),
      );

      final resourceRead = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'resources-read',
        'method': 'resources/read',
        'params': {'uri': 'app://example/context'},
      });
      expect(resourceRead.statusCode, equals(HttpStatus.ok));
      final resourceContents =
          ((resourceRead.json?['result'] as Map<String, Object?>)['contents']
                  as List)
              .cast<Map>();
      expect(resourceContents.single['text'], contains('router-hosted MCP'));

      final templates = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'resources-templates-list',
        'method': 'resources/templates/list',
        'params': {},
      });
      expect(templates.statusCode, equals(HttpStatus.ok));
      final templateList =
          ((templates.json?['result']
                      as Map<String, Object?>)['resourceTemplates']
                  as List)
              .cast<Map>();
      expect(
        templateList.map((template) => template['uriTemplate']),
        contains('app://example/task/{taskId}'),
      );

      final prompts = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'prompts-list',
        'method': 'prompts/list',
        'params': {},
      });
      expect(prompts.statusCode, equals(HttpStatus.ok));
      final promptList =
          ((prompts.json?['result'] as Map<String, Object?>)['prompts'] as List)
              .cast<Map>();
      expect(
        promptList.map((prompt) => prompt['name']),
        contains('summarize-task'),
      );

      final prompt = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'prompts-get',
        'method': 'prompts/get',
        'params': {
          'name': 'summarize-task',
          'arguments': {'taskId': 'T-100'},
        },
      });
      expect(prompt.statusCode, equals(HttpStatus.ok));
      final promptMessages =
          ((prompt.json?['result'] as Map<String, Object?>)['messages'] as List)
              .cast<Map>();
      final promptContent =
          promptMessages.single['content'] as Map<String, Object?>;
      expect(promptContent['text'], contains('T-100'));

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

      final directParamHeaderMismatch = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-param-header-mismatch',
          'method': 'tools/call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'hello'},
          },
        },
        headers: {
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app.echo',
          'Mcp-Param-Message': 'wrong',
        },
      );
      expect(
        directParamHeaderMismatch.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        (directParamHeaderMismatch.json?['error']
            as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(directParamHeaderMismatch.json?['error']),
        contains('Mcp-Param-Message'),
      );

      final directConnectanumParamHeaderMismatch = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-connectanum-param-header-mismatch',
          'method': 'connectanum.tool.call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'hello'},
          },
        },
        headers: {
          'Mcp-Method': 'connectanum.tool.call',
          'Mcp-Name': 'app.echo',
          'Mcp-Param-Message': 'wrong',
        },
      );
      expect(
        directConnectanumParamHeaderMismatch.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        (directConnectanumParamHeaderMismatch.json?['error']
            as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(directConnectanumParamHeaderMismatch.json?['error']),
        contains('Mcp-Param-Message'),
      );

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

    test('honors MCP route aliases and server identity metadata', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9113,
        nativeLib: nativeLib,
        settings: _buildRouterSettings(
          enableHttp3: false,
          enableMcp: true,
          mcpOptions: const <String, Object?>{
            'name': 'consumer-router-mcp',
            'version': '9.8.7',
            'title': 'Consumer router MCP',
            'description': 'Route metadata visible to MCP clients.',
            'instructions': 'Use this endpoint with route-scoped credentials.',
            'toolListPageSize': 1,
            'includePubsubTools': false,
            'includeStandardMetaApi': false,
            'includeRegisteredProcedures': false,
            'includeSubscribedTopics': false,
            'procedures': [
              {'procedure': 'app.alpha', 'toolName': 'alphaTask'},
              {'procedure': 'app.beta', 'toolName': 'betaTask'},
            ],
          },
        ),
      );
      addTearDown(harness.dispose);

      final listener = harness.binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final initialize = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'initialize-aliases',
        'method': 'initialize',
        'params': {'protocolVersion': '2025-11-25'},
      });
      expect(initialize.statusCode, equals(HttpStatus.ok));
      final initializeResult =
          initialize.json?['result'] as Map<String, Object?>;
      final serverInfo = initializeResult['serverInfo'] as Map<String, Object?>;
      expect(serverInfo['name'], equals('consumer-router-mcp'));
      expect(serverInfo['version'], equals('9.8.7'));
      expect(serverInfo['title'], equals('Consumer router MCP'));
      expect(
        serverInfo['description'],
        equals('Route metadata visible to MCP clients.'),
      );
      expect(
        initializeResult['instructions'],
        equals('Use this endpoint with route-scoped credentials.'),
      );

      final tools = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'tools-list-aliases',
        'method': 'tools/list',
        'params': {},
      });
      expect(tools.statusCode, equals(HttpStatus.ok));
      final toolsResult = tools.json?['result'] as Map<String, Object?>;
      final toolList = (toolsResult['tools'] as List).cast<Map>();
      expect(toolList, hasLength(1));
      expect(toolList.single['name'], equals('alphaTask'));
      expect(toolsResult['nextCursor'], isA<String>());
      expect(
        toolList.map((tool) => tool['name']),
        isNot(contains('connectanum.pubsub.publish')),
      );
      expect(
        toolList.map((tool) => tool['name']),
        isNot(contains('wamp.registration.list')),
      );
    }, skip: skipReason);

    test('guards MCP Streamable HTTP ingress and sessions', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9114,
        nativeLib: nativeLib,
        settings: _buildRouterSettings(enableHttp3: false, enableMcp: true),
      );
      addTearDown(harness.dispose);

      final listener = harness.binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final serviceSession = await harness.binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'mcp-sse-service',
        authRole: 'internal',
      );
      addTearDown(serviceSession.close);

      final get = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {HttpHeaders.acceptHeader: 'text/event-stream'},
      );
      expect(get.statusCode, equals(HttpStatus.badRequest));
      expect(jsonEncode(get.json?['error']), contains('MCP-Session-Id'));

      final getWithoutSessionInvalidAccept = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(
        getWithoutSessionInvalidAccept.statusCode,
        equals(HttpStatus.notAcceptable),
      );
      expect(
        getWithoutSessionInvalidAccept.headers,
        isNot(contains('mcp-session-id')),
      );

      final payload = <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'init',
        'method': 'initialize',
        'params': {'protocolVersion': '2025-11-25'},
      };

      final invalidOrigin = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {
          'origin': 'https://attacker.example',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        },
      );
      expect(invalidOrigin.statusCode, equals(HttpStatus.forbidden));
      expect(
        jsonEncode(invalidOrigin.json?['error']),
        contains('Invalid Origin'),
      );

      final invalidAccept = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {HttpHeaders.acceptHeader: 'text/plain'},
      );
      expect(invalidAccept.statusCode, equals(HttpStatus.notAcceptable));

      final jsonQZeroAccept = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {
          HttpHeaders.acceptHeader:
              'application/json;q=0, text/event-stream;q=1',
        },
      );
      expect(jsonQZeroAccept.statusCode, equals(HttpStatus.notAcceptable));

      final jsonQZeroWildcardAccept = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {HttpHeaders.acceptHeader: 'application/json;q=0, */*;q=1'},
      );
      expect(
        jsonQZeroWildcardAccept.statusCode,
        equals(HttpStatus.notAcceptable),
      );

      final invalidVersion = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {'MCP-Protocol-Version': '2099-01-01'},
      );
      expect(invalidVersion.statusCode, equals(HttpStatus.badRequest));

      final nullJsonRpcId = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'id': null, 'method': 'tools/list'},
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(nullJsonRpcId.statusCode, equals(HttpStatus.ok));
      expect(nullJsonRpcId.json?['id'], isNull);
      final nullJsonRpcIdError = (nullJsonRpcId.json?['error'] as Map)
          .cast<String, Object?>();
      expect(nullJsonRpcIdError['code'], equals(McpErrorCodes.invalidRequest));
      expect(nullJsonRpcIdError['message'], contains('string or integer'));
      expect(nullJsonRpcId.headers, isNot(contains('mcp-session-id')));

      final fractionalJsonRpcId = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'id': 1.5, 'method': 'tools/list'},
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(fractionalJsonRpcId.statusCode, equals(HttpStatus.ok));
      expect(fractionalJsonRpcId.json?['id'], isNull);
      final fractionalJsonRpcIdError =
          (fractionalJsonRpcId.json?['error'] as Map).cast<String, Object?>();
      expect(
        fractionalJsonRpcIdError['code'],
        equals(McpErrorCodes.invalidRequest),
      );
      expect(
        fractionalJsonRpcIdError['message'],
        contains('string or integer'),
      );
      expect(fractionalJsonRpcId.headers, isNot(contains('mcp-session-id')));

      final responseMemberJsonRpc = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'response-member',
          'method': 'tools/list',
          'result': <String, Object?>{},
        },
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(responseMemberJsonRpc.statusCode, equals(HttpStatus.ok));
      expect(responseMemberJsonRpc.json?['id'], equals('response-member'));
      final responseMemberJsonRpcError =
          (responseMemberJsonRpc.json?['error'] as Map).cast<String, Object?>();
      expect(
        responseMemberJsonRpcError['code'],
        equals(McpErrorCodes.invalidRequest),
      );
      expect(
        responseMemberJsonRpcError['message'],
        contains('result or error'),
      );
      expect(responseMemberJsonRpc.headers, isNot(contains('mcp-session-id')));

      final nullParamsJsonRpc = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'null-params',
          'method': 'tools/list',
          'params': null,
        },
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(nullParamsJsonRpc.statusCode, equals(HttpStatus.ok));
      expect(nullParamsJsonRpc.json?['id'], equals('null-params'));
      final nullParamsJsonRpcError = (nullParamsJsonRpc.json?['error'] as Map)
          .cast<String, Object?>();
      expect(
        nullParamsJsonRpcError['code'],
        equals(McpErrorCodes.invalidParams),
      );
      expect(
        nullParamsJsonRpcError['message'],
        contains('params must be an object'),
      );
      expect(nullParamsJsonRpc.headers, isNot(contains('mcp-session-id')));

      final nullParamsJsonRpcNotification = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'method': 'tools/list', 'params': null},
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(
        nullParamsJsonRpcNotification.statusCode,
        equals(HttpStatus.accepted),
      );
      expect(nullParamsJsonRpcNotification.body, isEmpty);
      expect(nullParamsJsonRpcNotification.json, isNull);
      expect(
        nullParamsJsonRpcNotification.headers,
        isNot(contains('mcp-session-id')),
      );

      final nullParamsJsonRpcBatchNotification = await _postJsonValue(
        client,
        listener.port,
        '/mcp',
        [
          {'jsonrpc': '2.0', 'method': 'tools/list', 'params': null},
          {
            'jsonrpc': '2.0',
            'id': 'after-invalid-notification',
            'method': 'tools/list',
          },
        ],
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(
        nullParamsJsonRpcBatchNotification.statusCode,
        equals(HttpStatus.ok),
      );
      expect(nullParamsJsonRpcBatchNotification.json, isA<List<Object?>>());
      final nullParamsJsonRpcBatchResponses =
          (nullParamsJsonRpcBatchNotification.json as List)
              .cast<Map<String, Object?>>();
      expect(nullParamsJsonRpcBatchResponses, hasLength(1));
      expect(
        nullParamsJsonRpcBatchResponses.single['id'],
        equals('after-invalid-notification'),
      );
      expect(
        nullParamsJsonRpcBatchResponses.single['result'],
        isA<Map<String, Object?>>(),
      );
      expect(
        nullParamsJsonRpcBatchNotification.headers,
        isNot(contains('mcp-session-id')),
      );

      final invalidDirectToolName = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'invalid-direct-tool-name',
          'method': 'tools/call',
          'params': {'name': 'bad tool', 'arguments': {}},
        },
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(invalidDirectToolName.statusCode, equals(HttpStatus.ok));
      expect(
        invalidDirectToolName.json?['id'],
        equals('invalid-direct-tool-name'),
      );
      final invalidDirectToolNameError =
          (invalidDirectToolName.json?['error'] as Map).cast<String, Object?>();
      expect(
        invalidDirectToolNameError['code'],
        equals(McpErrorCodes.invalidParams),
      );
      expect(
        invalidDirectToolNameError['message'],
        contains('tools/call.params.name'),
      );
      expect(invalidDirectToolNameError['message'], contains('1-128 ASCII'));

      final invalidDirectResourceUri = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'invalid-direct-resource-uri',
          'method': 'resources/read',
          'params': {'uri': 'relative/context'},
        },
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(invalidDirectResourceUri.statusCode, equals(HttpStatus.ok));
      expect(
        invalidDirectResourceUri.json?['id'],
        equals('invalid-direct-resource-uri'),
      );
      final invalidDirectResourceUriError =
          (invalidDirectResourceUri.json?['error'] as Map)
              .cast<String, Object?>();
      expect(
        invalidDirectResourceUriError['code'],
        equals(McpErrorCodes.invalidParams),
      );
      expect(
        invalidDirectResourceUriError['message'],
        contains('resources/read.params.uri'),
      );
      expect(
        invalidDirectResourceUriError['message'],
        contains('absolute URI'),
      );

      final invalidDirectPromptName = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'invalid-direct-prompt-name',
          'method': 'prompts/get',
          'params': {'name': ''},
        },
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(invalidDirectPromptName.statusCode, equals(HttpStatus.ok));
      expect(
        invalidDirectPromptName.json?['id'],
        equals('invalid-direct-prompt-name'),
      );
      final invalidDirectPromptNameError =
          (invalidDirectPromptName.json?['error'] as Map)
              .cast<String, Object?>();
      expect(
        invalidDirectPromptNameError['code'],
        equals(McpErrorCodes.invalidParams),
      );
      expect(
        invalidDirectPromptNameError['message'],
        contains('prompts/get.params.name'),
      );
      expect(
        invalidDirectPromptNameError['message'],
        contains('non-empty string'),
      );

      final olderVersionInitialize = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'older-protocol-init',
          'method': 'initialize',
          'params': {'protocolVersion': '2025-06-18'},
        },
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'MCP-Protocol-Version': '2025-06-18',
          'Mcp-Method': 'initialize',
        },
      );
      expect(olderVersionInitialize.statusCode, equals(HttpStatus.ok));
      expect(
        olderVersionInitialize.headers['mcp-protocol-version'],
        equals('2025-06-18'),
      );
      final olderVersionResult = (olderVersionInitialize.json?['result'] as Map)
          .cast<String, Object?>();
      expect(olderVersionResult['protocolVersion'], equals('2025-06-18'));
      final olderVersionSessionId =
          olderVersionInitialize.headers['mcp-session-id'];
      expect(olderVersionSessionId, isNotNull);
      final olderVersionDelete = await _deleteHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          'MCP-Session-Id': olderVersionSessionId!,
          'MCP-Protocol-Version': '2025-06-18',
        },
      );
      expect(olderVersionDelete.statusCode, equals(HttpStatus.accepted));

      final unsupportedBodyVersionInitialize = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'unsupported-body-protocol-init',
          'method': 'initialize',
          'params': {'protocolVersion': '2099-01-01'},
        },
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'initialize',
        },
      );
      expect(
        unsupportedBodyVersionInitialize.statusCode,
        equals(HttpStatus.ok),
      );
      expect(
        unsupportedBodyVersionInitialize.headers['mcp-protocol-version'],
        equals('2025-11-25'),
      );
      final unsupportedBodyVersionResult =
          (unsupportedBodyVersionInitialize.json?['result'] as Map)
              .cast<String, Object?>();
      expect(
        unsupportedBodyVersionResult['protocolVersion'],
        equals('2025-11-25'),
      );
      final unsupportedBodyVersionSessionId =
          unsupportedBodyVersionInitialize.headers['mcp-session-id'];
      expect(unsupportedBodyVersionSessionId, isNotNull);
      final unsupportedBodyVersionDelete = await _deleteHttp(
        client,
        listener.port,
        '/mcp',
        headers: {'MCP-Session-Id': unsupportedBodyVersionSessionId!},
      );
      expect(
        unsupportedBodyVersionDelete.statusCode,
        equals(HttpStatus.accepted),
      );

      final rejectedInitialize = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'bad-initialize',
          'method': 'initialize',
          'params': {'protocolVersion': 123},
        },
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'initialize',
        },
      );
      expect(rejectedInitialize.statusCode, equals(HttpStatus.ok));
      expect(rejectedInitialize.json?['error'], isA<Map<String, Object?>>());
      expect(
        jsonEncode(rejectedInitialize.json?['error']),
        contains('protocolVersion'),
      );
      expect(rejectedInitialize.headers, isNot(contains('mcp-session-id')));

      final rejectedHeaderInitializeBody = utf8.encode(jsonEncode(payload));
      final rejectedHeaderInitializeSocket = await Socket.connect(
        '127.0.0.1',
        listener.port,
      );
      late final String rejectedHeaderInitialize;
      try {
        rejectedHeaderInitializeSocket.add(
          utf8.encode(
            'POST /mcp HTTP/1.1\r\n'
            'Host: 127.0.0.1:${listener.port}\r\n'
            'Connection: close\r\n'
            'Origin: http://127.0.0.1:${listener.port}\r\n'
            'Accept: application/json, text/event-stream\r\n'
            'Content-Type: application/json\r\n'
            'Mcp-Method: initialize\r\n'
            'Mcp-Param-Probe: café\r\n'
            'Content-Length: ${rejectedHeaderInitializeBody.length}\r\n'
            '\r\n',
          ),
        );
        rejectedHeaderInitializeSocket.add(rejectedHeaderInitializeBody);
        await rejectedHeaderInitializeSocket.flush();
        rejectedHeaderInitialize = await _readHttpResponse(
          rejectedHeaderInitializeSocket,
        );
      } finally {
        rejectedHeaderInitializeSocket.destroy();
      }
      expect(
        rejectedHeaderInitialize,
        startsWith('HTTP/1.1 ${HttpStatus.badRequest}'),
      );
      final rejectedHeaderBodyStart =
          rejectedHeaderInitialize.indexOf('\r\n\r\n') + 4;
      final rejectedHeaderJson =
          jsonDecode(
                rejectedHeaderInitialize.substring(rejectedHeaderBodyStart),
              )
              as Map<String, Object?>;
      expect(
        jsonEncode(rejectedHeaderJson['error']),
        contains('contains invalid characters'),
      );
      final rejectedHeaderSessionId = RegExp(
        r'^mcp-session-id:\s*(\S+)\s*$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(rejectedHeaderInitialize)?.group(1);
      if (rejectedHeaderSessionId != null) {
        final rejectedHeaderSessionDelete = await _deleteHttp(
          client,
          listener.port,
          '/mcp',
          headers: {'MCP-Session-Id': rejectedHeaderSessionId},
        );
        expect(
          rejectedHeaderSessionDelete.statusCode,
          equals(HttpStatus.notFound),
        );
      }
      expect(rejectedHeaderSessionId, isNull);

      final clientSuppliedSessionInitialize = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'initialize',
          'MCP-Session-Id': 'client-chosen-session',
        },
      );
      expect(
        clientSuppliedSessionInitialize.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        jsonEncode(clientSuppliedSessionInitialize.json?['error']),
        contains('MCP-Session-Id'),
      );
      expect(
        clientSuppliedSessionInitialize.headers,
        isNot(contains('mcp-session-id')),
      );

      final malformedSessionIdHeaders = {
        'origin': 'http://127.0.0.1:${listener.port}',
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        'MCP-Protocol-Version': '2025-11-25',
        'Mcp-Method': 'tools/list',
        'MCP-Session-Id': 'malformed session',
      };
      final malformedSessionId =
          await _postJson(client, listener.port, '/mcp', {
            'jsonrpc': '2.0',
            'id': 'malformed-session-id',
            'method': 'tools/list',
            'params': {},
          }, headers: malformedSessionIdHeaders);
      expect(malformedSessionId.statusCode, equals(HttpStatus.badRequest));
      expect(
        jsonEncode(malformedSessionId.json?['error']),
        contains('MCP-Session-Id'),
      );
      expect(malformedSessionId.headers, isNot(contains('mcp-session-id')));

      final directJsonMalformedSessionId = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-json-malformed-session-id',
          'method': 'ping',
          'params': {},
        },
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json',
          'MCP-Protocol-Version': '2025-11-25',
          'MCP-Session-Id': 'malformed session',
        },
      );
      expect(
        directJsonMalformedSessionId.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        jsonEncode(directJsonMalformedSessionId.json?['error']),
        contains('MCP-Session-Id'),
      );
      expect(
        directJsonMalformedSessionId.headers,
        isNot(contains('mcp-session-id')),
      );

      final malformedSessionIdPoll = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'text/event-stream',
          'MCP-Protocol-Version': '2025-11-25',
          'MCP-Session-Id': 'malformed session',
        },
      );
      expect(malformedSessionIdPoll.statusCode, equals(HttpStatus.badRequest));
      expect(
        jsonEncode(malformedSessionIdPoll.json?['error']),
        contains('MCP-Session-Id'),
      );
      expect(malformedSessionIdPoll.headers, isNot(contains('mcp-session-id')));

      final headerlessInitialize = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        },
      );
      expect(headerlessInitialize.statusCode, equals(HttpStatus.ok));
      final headerlessMcpSessionId =
          headerlessInitialize.headers['mcp-session-id'];
      expect(headerlessMcpSessionId, isNotNull);
      expect(
        headerlessInitialize.headers['mcp-protocol-version'],
        equals('2025-11-25'),
      );
      final headerlessDelete = await _deleteHttp(
        client,
        listener.port,
        '/mcp',
        headers: {'MCP-Session-Id': headerlessMcpSessionId!},
      );
      expect(headerlessDelete.statusCode, equals(HttpStatus.accepted));

      final initialize = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'initialize',
        },
      );
      expect(initialize.statusCode, equals(HttpStatus.ok));
      final mcpSessionId = initialize.headers['mcp-session-id'];
      expect(mcpSessionId, isNotNull);
      expect(mcpSessionId, isNotEmpty);
      expect(initialize.headers['mcp-protocol-version'], equals('2025-11-25'));

      final sessionHeaders = <String, String>{
        'MCP-Session-Id': mcpSessionId!,
        'MCP-Protocol-Version': '2025-11-25',
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
      };
      Map<String, String> streamableHeaders(
        String method, {
        String? name,
        String? accept,
      }) {
        return <String, String>{
          ...sessionHeaders,
          HttpHeaders.acceptHeader: ?accept,
          'Mcp-Method': method,
          'Mcp-Name': ?name,
        };
      }

      final initialized = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
        headers: streamableHeaders('notifications/initialized'),
      );
      expect(initialized.statusCode, equals(HttpStatus.accepted));

      final jsonOnlyPost = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'json-only-post',
          'method': 'tools/list',
          'params': {},
        },
        headers: streamableHeaders(
          'tools/list',
          accept: 'application/json;q=1, text/event-stream;q=0',
        ),
      );
      expect(jsonOnlyPost.statusCode, equals(HttpStatus.ok));
      expect(
        jsonOnlyPost.headers[HttpHeaders.contentTypeHeader],
        contains('application/json'),
      );
      expect(jsonOnlyPost.json?['id'], equals('json-only-post'));

      final mismatchedMethodHeader = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'header-mismatch',
          'method': 'tools/list',
          'params': {},
        },
        headers: streamableHeaders('prompts/list'),
      );
      expect(mismatchedMethodHeader.statusCode, equals(HttpStatus.badRequest));
      expect(
        (mismatchedMethodHeader.json?['error'] as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(mismatchedMethodHeader.json?['error']),
        contains('Mcp-Method'),
      );

      final missingNameHeader = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'missing-name-header',
        'method': 'tools/call',
        'params': {'name': 'app.sse.dynamic', 'arguments': {}},
      }, headers: streamableHeaders('tools/call'));
      expect(missingNameHeader.statusCode, equals(HttpStatus.badRequest));
      expect(
        (missingNameHeader.json?['error'] as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(missingNameHeader.json?['error']),
        contains('Mcp-Name'),
      );

      final dynamicRegistration = await serviceSession.register(
        'app.sse.dynamic',
        options: core.RegisterOptions(
          custom: const {
            'input_json_schema': {
              'type': 'object',
              'properties': {
                'tenant': {'type': 'string', 'x-mcp-header': 'Tenant'},
                'priority': {'type': 'integer', 'x-mcp-header': 'Priority'},
              },
            },
            '_ai_meta_data': {
              'short_description': 'Dynamic SSE tool',
              'description': 'Tool registered after MCP initialization.',
            },
          },
        ),
      );
      dynamicRegistration.onInvoke((invocation) {
        invocation.respondWith(
          argumentsKeywords: {'received': invocation.argumentsKeywords},
        );
      });

      final missingParameterHeader = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'missing-parameter-header',
          'method': 'tools/call',
          'params': {
            'name': 'app.sse.dynamic',
            'arguments': {'tenant': 'consumer-a'},
          },
        },
        headers: streamableHeaders('tools/call', name: 'app.sse.dynamic'),
      );
      expect(missingParameterHeader.statusCode, equals(HttpStatus.badRequest));
      expect(
        (missingParameterHeader.json?['error'] as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(missingParameterHeader.json?['error']),
        contains('Mcp-Param-Tenant'),
      );

      final malformedParameterHeader = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'malformed-parameter-header',
          'method': 'tools/call',
          'params': {
            'name': 'app.sse.dynamic',
            'arguments': {'tenant': 'consumer-a'},
          },
        },
        headers: {
          ...streamableHeaders('tools/call', name: 'app.sse.dynamic'),
          'Mcp-Param-Tenant': '=?base64?not-base64?=',
        },
      );
      expect(
        malformedParameterHeader.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        (malformedParameterHeader.json?['error']
            as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(malformedParameterHeader.json?['error']),
        contains('Mcp-Param-Tenant'),
      );

      final headerlessToolCall = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'headerless-tool-call',
          'method': 'tools/call',
          'params': {
            'name': 'app.sse.dynamic',
            'arguments': {'tenant': 'consumer-a', 'priority': 7},
          },
        },
        headers: sessionHeaders,
      );
      expect(headerlessToolCall.statusCode, equals(HttpStatus.ok));
      expect(
        headerlessToolCall.headers['mcp-session-id'],
        equals(mcpSessionId),
      );
      expect(headerlessToolCall.body, contains('"id":"headerless-tool-call"'));
      expect(headerlessToolCall.body, contains('consumer-a'));

      final directMethodWithMethodHeader = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-method-with-method-header',
          'method': 'app.sse.dynamic',
          'params': {'tenant': 'consumer-b', 'priority': 8},
        },
        headers: streamableHeaders('app.sse.dynamic'),
      );
      expect(directMethodWithMethodHeader.statusCode, equals(HttpStatus.ok));
      expect(
        directMethodWithMethodHeader.headers['mcp-session-id'],
        equals(mcpSessionId),
      );
      expect(
        directMethodWithMethodHeader.body,
        contains('"id":"direct-method-with-method-header"'),
      );
      expect(directMethodWithMethodHeader.body, contains('consumer-b'));

      final missingSession = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'id': 'tools', 'method': 'tools/list', 'params': {}},
        headers: {
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'tools/list',
        },
      );
      expect(missingSession.statusCode, equals(HttpStatus.badRequest));
      expect(
        jsonEncode(missingSession.json?['error']),
        contains('MCP-Session-Id'),
      );

      final sse = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
        },
      );
      expect(sse.statusCode, equals(HttpStatus.ok));
      expect(
        sse.headers[HttpHeaders.contentTypeHeader],
        contains('text/event-stream'),
      );
      expect(sse.headers['mcp-session-id'], equals(mcpSessionId));
      expect(sse.body, contains('id: $mcpSessionId:'));
      expect(sse.body, contains('retry: 1000'));
      expect(sse.body, contains('data:'));
      expect(sse.body, contains('notifications/tools/list_changed'));
      final sseEventId = _firstSseEventId(sse.body);

      final sseQZeroWildcardAccept = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream;q=0, */*;q=1',
        },
      );
      expect(
        sseQZeroWildcardAccept.statusCode,
        equals(HttpStatus.notAcceptable),
      );
      expect(
        sseQZeroWildcardAccept.headers['mcp-session-id'],
        equals(mcpSessionId),
      );

      final unknownSessionWithInvalidSseAccept = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          'MCP-Session-Id': 'unknown-session',
          HttpHeaders.acceptHeader: 'application/json',
        },
      );
      expect(
        unknownSessionWithInvalidSseAccept.statusCode,
        equals(HttpStatus.notFound),
      );
      expect(
        unknownSessionWithInvalidSseAccept.headers,
        isNot(contains('mcp-session-id')),
      );

      final resumedSse = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
          'Last-Event-ID': sseEventId,
        },
      );
      expect(resumedSse.statusCode, equals(HttpStatus.ok));
      expect(resumedSse.body, isNot(contains(sseEventId)));
      expect(
        resumedSse.body,
        isNot(contains('notifications/tools/list_changed')),
      );
      expect(_firstSseEventId(resumedSse.body), startsWith('$mcpSessionId:'));

      final resetResumeSse = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
          'Last-Event-ID': '',
        },
      );
      expect(resetResumeSse.statusCode, equals(HttpStatus.ok));
      expect(
        resetResumeSse.headers[HttpHeaders.contentTypeHeader],
        contains('text/event-stream'),
      );
      expect(
        _firstSseEventId(resetResumeSse.body),
        startsWith('$mcpSessionId:'),
      );

      final unknownEvent = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
          'Last-Event-ID': '$mcpSessionId:missing:1',
        },
      );
      expect(unknownEvent.statusCode, equals(HttpStatus.badRequest));
      expect(
        jsonEncode(unknownEvent.json?['error']),
        contains('Last-Event-ID'),
      );

      final postSse = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'tools-sse',
        'method': 'tools/list',
        'params': {},
      }, headers: streamableHeaders('tools/list'));
      expect(postSse.statusCode, equals(HttpStatus.ok));
      expect(
        postSse.headers[HttpHeaders.contentTypeHeader],
        contains('text/event-stream'),
      );
      expect(postSse.headers['mcp-session-id'], equals(mcpSessionId));
      expect(postSse.json, isNull);
      expect(postSse.body, contains('"id":"tools-sse"'));
      expect(postSse.body, contains('"tools"'));
      final postSseEventIds = _sseEventIds(postSse.body);
      expect(postSseEventIds, hasLength(2));
      expect(postSseEventIds.first, startsWith('$mcpSessionId:'));
      expect(postSseEventIds.last, startsWith('$mcpSessionId:'));

      final replayPostSse = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: {
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
          'Last-Event-ID': postSseEventIds.first,
        },
      );
      expect(replayPostSse.statusCode, equals(HttpStatus.ok));
      expect(replayPostSse.body, contains(postSseEventIds.last));
      expect(replayPostSse.body, contains('"id":"tools-sse"'));

      final tools = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'id': 'tools', 'method': 'tools/list', 'params': {}},
        headers: streamableHeaders('tools/list', accept: 'application/json'),
      );
      expect(tools.statusCode, equals(HttpStatus.ok));
      expect(tools.json?['id'], equals('tools'));

      final unknownSession = await _postJson(
        client,
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'id': 'tools', 'method': 'tools/list', 'params': {}},
        headers: {
          ...streamableHeaders('tools/list'),
          'MCP-Session-Id': 'unknown-session',
        },
      );
      expect(unknownSession.statusCode, equals(HttpStatus.notFound));
      expect(unknownSession.headers, isNot(contains('mcp-session-id')));

      final unknownSessionWithInvalidContentType = await _postBody(
        client,
        listener.port,
        '/mcp',
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'unknown-session-invalid-content-type',
          'method': 'tools/list',
          'params': <String, Object?>{},
        }),
        contentType: ContentType.text,
        headers: {
          ...streamableHeaders('tools/list'),
          'MCP-Session-Id': 'unknown-session',
        },
      );
      expect(
        unknownSessionWithInvalidContentType.statusCode,
        equals(HttpStatus.notFound),
      );
      expect(
        unknownSessionWithInvalidContentType.json?['id'],
        equals('unknown-session-invalid-content-type'),
      );
      expect(
        unknownSessionWithInvalidContentType.headers,
        isNot(contains('mcp-session-id')),
      );

      final liveSessionWithInvalidContentType = await _postBody(
        client,
        listener.port,
        '/mcp',
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'live-session-invalid-content-type',
          'method': 'tools/list',
          'params': <String, Object?>{},
        }),
        contentType: ContentType.text,
        headers: streamableHeaders('tools/list'),
      );
      expect(
        liveSessionWithInvalidContentType.statusCode,
        equals(HttpStatus.unsupportedMediaType),
      );
      expect(
        liveSessionWithInvalidContentType.headers['mcp-session-id'],
        equals(mcpSessionId),
      );

      final directUnknownSession = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-stale-session',
          'method': 'tools/list',
          'params': {},
        },
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          'MCP-Session-Id': 'unknown-session',
          'MCP-Protocol-Version': '2025-11-25',
        },
      );
      expect(directUnknownSession.statusCode, equals(HttpStatus.ok));
      expect(directUnknownSession.json?['id'], equals('direct-stale-session'));
      expect(directUnknownSession.headers, isNot(contains('mcp-session-id')));

      final directInvalidVersionStaleSession = await _postJson(
        client,
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'direct-invalid-version-stale-session',
          'method': 'tools/list',
          'params': {},
        },
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          'MCP-Session-Id': 'unknown-session',
          'MCP-Protocol-Version': '2099-01-01',
        },
      );
      expect(
        directInvalidVersionStaleSession.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        directInvalidVersionStaleSession.headers,
        isNot(contains('mcp-session-id')),
      );

      final directMalformedStaleSession = await _postBody(
        client,
        listener.port,
        '/mcp',
        '{"jsonrpc":"2.0","id":"direct-malformed-stale-session",',
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          'MCP-Session-Id': 'unknown-session',
          'MCP-Protocol-Version': '2025-11-25',
        },
      );
      expect(
        directMalformedStaleSession.statusCode,
        equals(HttpStatus.badRequest),
      );
      expect(
        jsonEncode(directMalformedStaleSession.json?['error']),
        contains('Invalid JSON-RPC message'),
      );
      expect(
        directMalformedStaleSession.headers,
        isNot(contains('mcp-session-id')),
      );

      final liveMalformedStreamable = await _postBody(
        client,
        listener.port,
        '/mcp',
        '{"jsonrpc":"2.0","id":"live-malformed-streamable",',
        headers: streamableHeaders('tools/list'),
      );
      expect(liveMalformedStreamable.statusCode, equals(HttpStatus.badRequest));
      expect(
        liveMalformedStreamable.headers['mcp-session-id'],
        equals(mcpSessionId),
      );
      expect(
        jsonEncode(liveMalformedStreamable.json?['error']),
        contains('Invalid JSON-RPC message'),
      );

      final delete = await _deleteHttp(
        client,
        listener.port,
        '/mcp',
        headers: sessionHeaders,
      );
      expect(delete.statusCode, equals(HttpStatus.accepted));

      final afterDelete = await _postJson(client, listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'tools-after-delete',
        'method': 'tools/list',
        'params': {},
      }, headers: streamableHeaders('tools/list'));
      expect(afterDelete.statusCode, equals(HttpStatus.notFound));
      expect(afterDelete.headers, isNot(contains('mcp-session-id')));

      final malformedAfterDelete = await _postBody(
        client,
        listener.port,
        '/mcp',
        '{"jsonrpc":"2.0","id":"malformed-after-delete",',
        headers: streamableHeaders('tools/list'),
      );
      expect(malformedAfterDelete.statusCode, equals(HttpStatus.notFound));
      expect(malformedAfterDelete.headers, isNot(contains('mcp-session-id')));
      expect(malformedAfterDelete.body, contains('Unknown MCP HTTP session'));
      expect(
        malformedAfterDelete.body,
        isNot(contains('Invalid JSON-RPC message')),
      );

      final mismatchedHeadersAfterDelete =
          await _postJson(client, listener.port, '/mcp', {
            'jsonrpc': '2.0',
            'id': 'mismatched-headers-after-delete',
            'method': 'tools/list',
            'params': {},
          }, headers: streamableHeaders('resources/list'));
      expect(
        mismatchedHeadersAfterDelete.statusCode,
        equals(HttpStatus.notFound),
      );
      expect(
        mismatchedHeadersAfterDelete.headers,
        isNot(contains('mcp-session-id')),
      );

      final getAfterDelete = await _getHttp(
        client,
        listener.port,
        '/mcp',
        headers: <String, String>{
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
        },
      );
      expect(getAfterDelete.statusCode, equals(HttpStatus.notFound));
      expect(getAfterDelete.headers, isNot(contains('mcp-session-id')));

      final deleteAfterDelete = await _deleteHttp(
        client,
        listener.port,
        '/mcp',
        headers: sessionHeaders,
      );
      expect(deleteAfterDelete.statusCode, equals(HttpStatus.notFound));
      expect(deleteAfterDelete.headers, isNot(contains('mcp-session-id')));
    }, skip: skipReason);

    test(
      'allows MCP CORS preflight when explicit methods omit OPTIONS',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9123,
          nativeLib: nativeLib,
          settings: _buildRouterSettings(
            enableHttp3: false,
            enableMcp: true,
            mcpRouteMatch: const HttpRouteMatch(
              path: '/mcp',
              methods: ['GET', 'POST', 'DELETE'],
            ),
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final origin = 'http://127.0.0.1:${listener.port}';
        final request = await client.open(
          'OPTIONS',
          '127.0.0.1',
          listener.port,
          '/mcp',
        );
        request.headers.set('Origin', origin);
        request.headers.set('Access-Control-Request-Method', 'POST');
        request.headers.set(
          'Access-Control-Request-Headers',
          'Authorization, Content-Type, MCP-Protocol-Version',
        );

        final preflight = await _readJsonHttpResponse(await request.close());

        expect(preflight.statusCode, equals(HttpStatus.noContent));
        expect(
          preflight.headers['access-control-allow-origin'],
          equals(origin),
        );
        expect(
          preflight.headers['access-control-allow-methods'],
          allOf(
            contains('GET'),
            contains('POST'),
            contains('DELETE'),
            contains('OPTIONS'),
          ),
        );
        expect(
          preflight.headers['access-control-allow-headers']?.toLowerCase(),
          allOf(
            contains('authorization'),
            contains('content-type'),
            contains('mcp-protocol-version'),
          ),
        );
        expect(preflight.headers, isNot(contains('mcp-session-id')));
      },
      skip: skipReason,
    );

    test(
      'allows MCP CORS preflight for method actions without explicit OPTIONS',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 91231,
          nativeLib: nativeLib,
          settings: _buildRouterSettings(
            enableHttp3: false,
            enableMcp: true,
            mcpRouteMatch: const HttpRouteMatch(path: '/mcp', methods: ['GET']),
            mcpRouteAction: const HttpRouteAction(
              type: HttpRouteActionType.rpc,
              realm: 'realm1',
              procedure: 'com.example.http.health',
            ),
            mcpMethodActions: const <String, HttpRouteAction>{
              'POST': HttpRouteAction(
                type: HttpRouteActionType.mcp,
                realm: 'realm1',
              ),
            },
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final origin = 'http://127.0.0.1:${listener.port}';
        final request = await client.open(
          'OPTIONS',
          '127.0.0.1',
          listener.port,
          '/mcp',
        );
        request.headers.set('Origin', origin);
        request.headers.set('Access-Control-Request-Method', 'POST');
        request.headers.set(
          'Access-Control-Request-Headers',
          'Content-Type, MCP-Protocol-Version',
        );

        final preflight = await _readJsonHttpResponse(await request.close());

        expect(preflight.statusCode, equals(HttpStatus.noContent));
        expect(
          preflight.headers['access-control-allow-origin'],
          equals(origin),
        );
        expect(
          preflight.headers['access-control-allow-methods'],
          allOf(contains('POST'), contains('OPTIONS')),
        );
        expect(
          preflight.headers['access-control-allow-headers']?.toLowerCase(),
          allOf(contains('content-type'), contains('mcp-protocol-version')),
        );
        expect(preflight.headers, isNot(contains('mcp-session-id')));
      },
      skip: skipReason,
    );

    test(
      'serves MCP 2026 discovery and ordinary requests without sessions',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9128,
          nativeLib: nativeLib,
          settings: _buildRouterSettings(enableHttp3: false, enableMcp: true),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri.parse('http://127.0.0.1:${listener.port}/mcp');
        final client = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-native-test',
            'version': '1.0.0',
          },
        );
        addTearDown(() => client.close(force: true));

        final discovery = await client.discover(id: 'discover-modern');
        final tools = await client.listTools(id: 'tools-modern');

        expect(discovery.supportedVersions, contains('2026-07-28'));
        expect(discovery.capabilities, contains('tools'));
        expect(discovery.serverInfo?['name'], equals('connectanum-router'));
        expect(tools.tools, isNotEmpty);
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        final rawClient = HttpClient();
        addTearDown(() => rawClient.close(force: true));
        final mismatched = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'mismatched-modern-version',
            'method': 'tools/list',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2025-11-25',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
            'Mcp-Method': 'tools/list',
          },
        );
        expect(mismatched.statusCode, equals(HttpStatus.badRequest));
        final mismatchError = (mismatched.json?['error'] as Map)
            .cast<String, Object?>();
        expect(mismatchError['code'], equals(McpErrorCodes.headerMismatch));
        expect(mismatched.headers, isNot(contains('mcp-session-id')));

        final unsupported = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'unsupported-modern-version',
            'method': 'tools/list',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2099-01-01',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2099-01-01',
            'Mcp-Method': 'tools/list',
          },
        );
        expect(unsupported.statusCode, equals(HttpStatus.badRequest));
        final unsupportedError = (unsupported.json?['error'] as Map)
            .cast<String, Object?>();
        expect(
          unsupportedError['code'],
          equals(McpErrorCodes.unsupportedProtocolVersion),
        );
        expect(
          (unsupportedError['data'] as Map)['supportedVersions'],
          contains('2026-07-28'),
        );
        expect(unsupported.headers, isNot(contains('mcp-session-id')));

        final rawModern = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'raw-modern-tools',
            'method': 'tools/list',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
            'Mcp-Method': 'tools/list',
          },
        );
        expect(rawModern.statusCode, equals(HttpStatus.ok));
        final rawModernResult = (rawModern.json?['result'] as Map)
            .cast<String, Object?>();
        expect(rawModernResult['resultType'], equals('complete'));
        expect(
          (rawModernResult['_meta'] as Map),
          contains('io.modelcontextprotocol/serverInfo'),
        );
        expect(rawModern.headers, isNot(contains('mcp-session-id')));

        final rawModernBatch = await _postJsonValue(
          rawClient,
          listener.port,
          '/mcp',
          [
            {
              'jsonrpc': '2.0',
              'id': 'raw-modern-batch-tools',
              'method': 'tools/list',
              'params': {
                '_meta': {
                  'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                  'io.modelcontextprotocol/clientCapabilities':
                      <String, Object?>{},
                },
              },
            },
            {
              'jsonrpc': '2.0',
              'id': 'raw-modern-batch-ping',
              'method': 'ping',
              'params': {
                '_meta': {
                  'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                  'io.modelcontextprotocol/clientCapabilities':
                      <String, Object?>{},
                },
              },
            },
          ],
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
          },
        );
        expect(rawModernBatch.statusCode, equals(HttpStatus.badRequest));
        final rawModernBatchBody = (rawModernBatch.json as Map)
            .cast<String, Object?>();
        final rawModernBatchError = (rawModernBatchBody['error'] as Map)
            .cast<String, Object?>();
        expect(rawModernBatchBody['id'], isNull);
        expect(
          rawModernBatchError['code'],
          equals(McpErrorCodes.invalidRequest),
        );
        expect(
          rawModernBatchError['message'],
          contains('one JSON-RPC message object'),
        );
        expect(
          rawModernBatch.headers['mcp-protocol-version'],
          equals('2026-07-28'),
        );
        expect(rawModernBatch.headers, isNot(contains('mcp-session-id')));

        final missingMetadata = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'missing-modern-metadata',
            'method': 'tools/list',
            'params': <String, Object?>{},
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
            'Mcp-Method': 'tools/list',
          },
        );
        expect(missingMetadata.statusCode, equals(HttpStatus.badRequest));
        expect(
          (missingMetadata.json?['error'] as Map)['code'],
          equals(McpErrorCodes.invalidParams),
        );

        final missingProtocolHeader = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'missing-modern-protocol-header',
            'method': 'tools/list',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'Mcp-Method': 'tools/list',
          },
        );
        expect(missingProtocolHeader.statusCode, equals(HttpStatus.badRequest));
        expect(
          (missingProtocolHeader.json?['error'] as Map)['code'],
          equals(McpErrorCodes.headerMismatch),
        );

        final malformedListener = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'malformed-modern-listener',
            'method': 'subscriptions/listen',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
              'notifications': <String, Object?>{'toolsListChanged': 'yes'},
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
            'Mcp-Method': 'subscriptions/listen',
          },
        );
        expect(malformedListener.statusCode, equals(HttpStatus.badRequest));
        expect(
          (malformedListener.json?['error'] as Map)['code'],
          equals(McpErrorCodes.invalidParams),
        );
        expect(malformedListener.headers, isNot(contains('mcp-session-id')));

        final unknownMethod = await _postJson(
          rawClient,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'unknown-modern-method',
            'method': 'consumer/unknown',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
            'Mcp-Method': 'consumer/unknown',
          },
        );
        expect(unknownMethod.statusCode, equals(HttpStatus.notFound));
        expect(
          (unknownMethod.json?['error'] as Map)['code'],
          equals(McpErrorCodes.methodNotFound),
        );
        expect(unknownMethod.headers, isNot(contains('mcp-session-id')));

        final modernGet = await _getHttp(
          rawClient,
          listener.port,
          '/mcp',
          headers: {
            HttpHeaders.acceptHeader: 'text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
          },
        );
        expect(modernGet.statusCode, equals(HttpStatus.methodNotAllowed));
        expect(modernGet.headers, isNot(contains('mcp-session-id')));
      },
      skip: skipReason,
    );

    test(
      'keeps MCP response envelope on route-level method rejection',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9124,
          nativeLib: nativeLib,
          settings: _buildRouterSettings(
            enableHttp3: false,
            enableMcp: true,
            mcpRouteMatch: const HttpRouteMatch(
              path: '/mcp',
              methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
            ),
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final rejected = await _putJson(
          client,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'method-rejected',
            'method': 'initialize',
            'params': {'protocolVersion': '2025-11-25'},
          },
          headers: {HttpHeaders.acceptHeader: 'application/json'},
        );

        expect(rejected.statusCode, equals(HttpStatus.methodNotAllowed));
        expect(rejected.headers['allow'], contains('POST'));
        expect(rejected.headers['mcp-protocol-version'], equals('2025-11-25'));
        expect(rejected.json?['jsonrpc'], equals('2.0'));
        expect(rejected.json?['id'], isNull);
        final error = rejected.json?['error'] as Map<String, Object?>;
        expect(error['code'], equals(McpErrorCodes.invalidRequest));
        expect(error['message'], contains('HTTP method is not allowed'));
        expect(rejected.headers, isNot(contains('mcp-session-id')));
      },
      skip: skipReason,
    );

    test(
      'keeps MCP response envelope on route-level protocol rejection',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9125,
          nativeLib: nativeLib,
          settings: _buildRouterSettings(
            enableHttp3: false,
            enableMcp: true,
            mcpRouteMatch: const HttpRouteMatch(
              path: '/mcp',
              protocols: ['h2'],
            ),
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final rejected = await _postJson(
          client,
          listener.port,
          '/mcp',
          {
            'jsonrpc': '2.0',
            'id': 'protocol-rejected',
            'method': 'initialize',
            'params': {'protocolVersion': '2025-11-25'},
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json',
            'MCP-Protocol-Version': '2025-11-25',
          },
        );

        expect(rejected.statusCode, equals(HttpStatus.upgradeRequired));
        expect(rejected.headers['upgrade'], contains('http2'));
        expect(rejected.headers['mcp-protocol-version'], equals('2025-11-25'));
        expect(rejected.json?['jsonrpc'], equals('2.0'));
        expect(rejected.json?['id'], isNull);
        final error = rejected.json?['error'] as Map<String, Object?>;
        expect(error['code'], equals(McpErrorCodes.invalidRequest));
        expect(error['message'], contains('HTTP protocol is not allowed'));
        expect(rejected.headers, isNot(contains('mcp-session-id')));
      },
      skip: skipReason,
    );

    test('serves router-hosted MCP over native HTTP/2', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9126,
        nativeLib: nativeLib,
        settings: _buildRouterSettings(
          enableHttp3: false,
          enableMcp: true,
          mcpRouteMatch: const HttpRouteMatch(path: '/mcp', protocols: ['h2']),
          mcpOptions: const <String, Object?>{
            'post_response_transport': 'json',
          },
        ),
      );
      addTearDown(harness.dispose);

      final binding = harness.binding;
      final serviceSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'mcp-http2-service',
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
      final initialize = await _postHttp2Json(
        listener.port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'h2-initialize',
          'method': 'initialize',
          'params': {'protocolVersion': '2025-11-25'},
        },
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'initialize',
        },
      );

      expect(initialize.statusCode, equals(HttpStatus.ok));
      expect(initialize.headers['mcp-protocol-version'], equals('2025-11-25'));
      final mcpSessionId = initialize.headers['mcp-session-id'];
      expect(mcpSessionId, isNotNull);
      expect(mcpSessionId, isNotEmpty);
      final initializeResult =
          initialize.json?['result'] as Map<String, Object?>;
      expect(initializeResult['capabilities'], isA<Map<String, Object?>>());

      final sessionHeaders = <String, String>{
        'origin': 'http://127.0.0.1:${listener.port}',
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        'MCP-Protocol-Version': '2025-11-25',
        'MCP-Session-Id': mcpSessionId!,
      };
      Map<String, String> streamableHeaders(String method) {
        return <String, String>{...sessionHeaders, 'Mcp-Method': method};
      }

      final initialized = await _postHttp2Json(
        listener.port,
        '/mcp',
        {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
        headers: streamableHeaders('notifications/initialized'),
      );
      expect(initialized.statusCode, equals(HttpStatus.accepted));

      final tools = await _postHttp2Json(listener.port, '/mcp', {
        'jsonrpc': '2.0',
        'id': 'h2-tools-list',
        'method': 'tools/list',
        'params': {},
      }, headers: streamableHeaders('tools/list'));

      expect(tools.statusCode, equals(HttpStatus.ok));
      expect(tools.headers['mcp-session-id'], equals(mcpSessionId));
      final toolList =
          ((tools.json?['result'] as Map<String, Object?>)['tools'] as List)
              .cast<Map>();
      expect(toolList.map((tool) => tool['name']), contains('app.echo'));
    }, skip: skipReason);

    test('serves router-hosted MCP over native HTTP/3', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9127,
        nativeLib: nativeLib,
        config: _buildTlsConfig(),
        settings: _buildRouterSettings(
          enableHttp3: true,
          enableMcp: true,
          mcpRouteMatch: const HttpRouteMatch(
            path: '/mcp',
            protocols: ['http3'],
          ),
        ),
        connectionSequence: const [],
      );
      addTearDown(harness.dispose);

      if (!harness.runtime.supportsHttp3TestClient) {
        // Skip without failing the suite when ffi-test helpers are unavailable.
        // ignore: avoid_print
        print('Skipping HTTP/3 MCP test: native runtime lacks test client');
        return;
      }

      final binding = harness.binding;
      final serviceSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'mcp-http3-service',
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
      expect(
        listener.http3Port,
        greaterThan(0),
        reason: 'Router did not expose an HTTP/3 port',
      );
      final nativeLibPath = nativeLib!;
      final origin = 'https://127.0.0.1:${listener.http3Port}';
      final initialize = await _postHttp3Json(
        nativeLibPath,
        listener.http3Port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'h3-initialize',
          'method': 'initialize',
          'params': {'protocolVersion': '2025-11-25'},
        },
        headers: {
          'origin': origin,
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'Mcp-Method': 'initialize',
        },
      );

      expect(initialize.statusCode, equals(HttpStatus.ok));
      expect(initialize.headers['mcp-protocol-version'], equals('2025-11-25'));
      final mcpSessionId = initialize.headers['mcp-session-id'];
      expect(mcpSessionId, isNotNull);
      expect(mcpSessionId, isNotEmpty);
      final initializeResult =
          initialize.json?['result'] as Map<String, Object?>;
      expect(initializeResult['capabilities'], isA<Map<String, Object?>>());

      final sessionHeaders = <String, String>{
        'origin': origin,
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        'MCP-Protocol-Version': '2025-11-25',
        'MCP-Session-Id': mcpSessionId!,
      };
      Map<String, String> streamableHeaders(String method) {
        return <String, String>{...sessionHeaders, 'Mcp-Method': method};
      }

      final initialized = await _postHttp3Json(
        nativeLibPath,
        listener.http3Port,
        '/mcp',
        {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
        headers: streamableHeaders('notifications/initialized'),
      );
      expect(initialized.statusCode, equals(HttpStatus.accepted));

      final tools = await _postHttp3Json(
        nativeLibPath,
        listener.http3Port,
        '/mcp',
        {
          'jsonrpc': '2.0',
          'id': 'h3-tools-list',
          'method': 'tools/list',
          'params': {},
        },
        headers: streamableHeaders('tools/list'),
      );

      expect(tools.statusCode, equals(HttpStatus.ok));
      expect(
        tools.headers[HttpHeaders.contentTypeHeader],
        contains('text/event-stream'),
      );
      expect(tools.headers['mcp-session-id'], equals(mcpSessionId));
      expect(tools.json, isNull);
      expect(tools.body, contains('"id":"h3-tools-list"'));
      expect(tools.body, contains('"tools"'));
      expect(tools.body, contains('"app.echo"'));
      final postSseEventIds = _sseEventIds(tools.body);
      expect(postSseEventIds, hasLength(2));
      expect(postSseEventIds.first, startsWith('$mcpSessionId:'));
      expect(postSseEventIds.last, startsWith('$mcpSessionId:'));

      final replayPostSse = await _requestHttp3(
        nativeLibPath,
        listener.http3Port,
        '/mcp',
        method: 'GET',
        headers: <String, String>{
          ...sessionHeaders,
          HttpHeaders.acceptHeader: 'text/event-stream',
          'Last-Event-ID': postSseEventIds.first,
        },
      );
      expect(replayPostSse.statusCode, equals(HttpStatus.ok));
      expect(
        replayPostSse.headers[HttpHeaders.contentTypeHeader],
        contains('text/event-stream'),
      );
      expect(replayPostSse.headers['mcp-session-id'], equals(mcpSessionId));
      expect(replayPostSse.body, contains(postSseEventIds.last));
      expect(replayPostSse.body, contains('"id":"h3-tools-list"'));
    }, skip: skipReason);

    test(
      'enforces protected router-hosted MCP auth over native HTTP/3',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9137,
          nativeLib: nativeLib,
          config: _buildTlsConfig(),
          settings: _buildMcpSmokeSettings(enableHttp3: true),
          connectionSequence: const [],
        );
        addTearDown(harness.dispose);

        if (!harness.runtime.supportsHttp3TestClient) {
          // Skip without failing the suite when ffi-test helpers are unavailable.
          // ignore: avoid_print
          print(
            'Skipping protected HTTP/3 MCP test: '
            'native runtime lacks test client',
          );
          return;
        }

        final listener = harness.binding.listeners.single;
        expect(
          listener.http3Port,
          greaterThan(0),
          reason: 'Router did not expose an HTTP/3 port',
        );
        final nativeLibPath = nativeLib!;
        final origin = 'https://127.0.0.1:${listener.http3Port}';

        final primaryGrant = await _issueTicketHttp3Grant(
          nativeLibPath,
          listener.http3Port,
          authId: 'user-1',
        );
        final otherGrant = await _issueTicketHttp3Grant(
          nativeLibPath,
          listener.http3Port,
          authId: 'user-2',
        );

        final initializePayload = <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'secure-h3-initialize',
          'method': 'initialize',
          'params': {'protocolVersion': '2025-11-25'},
        };
        Map<String, String> initializeHeaders({String? bearerToken}) {
          return <String, String>{
            'origin': origin,
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'Mcp-Method': 'initialize',
            if (bearerToken != null)
              HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
          };
        }

        final missingBearerInitialize = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          initializePayload,
          headers: initializeHeaders(),
        );
        expect(
          missingBearerInitialize.statusCode,
          equals(HttpStatus.unauthorized),
        );
        expect(
          missingBearerInitialize.headers[HttpHeaders.wwwAuthenticateHeader],
          contains('Bearer'),
        );
        expect(
          missingBearerInitialize.headers,
          isNot(contains('mcp-session-id')),
        );

        final invalidBearerInitialize = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          {...initializePayload, 'id': 'secure-h3-invalid-bearer'},
          headers: initializeHeaders(bearerToken: 'invalid-token'),
        );
        expect(
          invalidBearerInitialize.statusCode,
          equals(HttpStatus.unauthorized),
        );
        expect(
          invalidBearerInitialize.headers,
          isNot(contains('mcp-session-id')),
        );

        final initialize = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          initializePayload,
          headers: initializeHeaders(bearerToken: primaryGrant.accessToken),
        );
        expect(initialize.statusCode, equals(HttpStatus.ok));
        expect(
          initialize.headers['mcp-protocol-version'],
          equals('2025-11-25'),
        );
        final mcpSessionId = initialize.headers['mcp-session-id'];
        expect(mcpSessionId, isNotNull);
        expect(mcpSessionId, isNotEmpty);

        final sessionHeaders = <String, String>{
          'origin': origin,
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'MCP-Protocol-Version': '2025-11-25',
          'MCP-Session-Id': mcpSessionId!,
        };
        Map<String, String> streamableHeaders(
          String method, {
          String? bearerToken,
        }) {
          return <String, String>{
            ...sessionHeaders,
            'Mcp-Method': method,
            if (bearerToken != null)
              HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
          };
        }

        final initialized = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          headers: streamableHeaders(
            'notifications/initialized',
            bearerToken: primaryGrant.accessToken,
          ),
        );
        expect(initialized.statusCode, equals(HttpStatus.accepted));

        final toolsPayload = <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'secure-h3-tools',
          'method': 'tools/list',
          'params': {},
        };
        final tools = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          toolsPayload,
          headers: streamableHeaders(
            'tools/list',
            bearerToken: primaryGrant.accessToken,
          ),
        );
        expect(tools.statusCode, equals(HttpStatus.ok));
        expect(
          tools.headers[HttpHeaders.contentTypeHeader],
          contains('text/event-stream'),
        );
        expect(tools.headers['mcp-session-id'], equals(mcpSessionId));
        expect(tools.body, contains('"id":"secure-h3-tools"'));
        expect(tools.body, contains('"connectanum.api.list"'));
        final postSseEventIds = _sseEventIds(tools.body);
        expect(postSseEventIds, hasLength(2));
        expect(postSseEventIds.first, startsWith('$mcpSessionId:'));
        expect(postSseEventIds.last, startsWith('$mcpSessionId:'));

        final replayWithPrimary = await _requestHttp3(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          method: 'GET',
          headers: <String, String>{
            ...sessionHeaders,
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader:
                'Bearer ${primaryGrant.accessToken}',
            'Last-Event-ID': postSseEventIds.first,
          },
        );
        expect(replayWithPrimary.statusCode, equals(HttpStatus.ok));
        expect(
          replayWithPrimary.headers['mcp-session-id'],
          equals(mcpSessionId),
        );
        expect(replayWithPrimary.body, contains(postSseEventIds.last));

        final streamableMissingBearer = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          {...toolsPayload, 'id': 'secure-h3-missing-bearer'},
          headers: streamableHeaders('tools/list'),
        );
        expect(
          streamableMissingBearer.statusCode,
          equals(HttpStatus.unauthorized),
        );
        expect(
          streamableMissingBearer.headers,
          isNot(contains('mcp-session-id')),
        );

        final reuseWithOtherPrincipal = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          {...toolsPayload, 'id': 'secure-h3-other-principal'},
          headers: streamableHeaders(
            'tools/list',
            bearerToken: otherGrant.accessToken,
          ),
        );
        expect(reuseWithOtherPrincipal.statusCode, equals(HttpStatus.notFound));
        expect(
          reuseWithOtherPrincipal.headers,
          isNot(contains('mcp-session-id')),
        );
        expect(
          reuseWithOtherPrincipal.body,
          contains('Unknown MCP HTTP session'),
        );

        final replayWithOtherPrincipal = await _requestHttp3(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          method: 'GET',
          headers: <String, String>{
            ...sessionHeaders,
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${otherGrant.accessToken}',
            'Last-Event-ID': postSseEventIds.first,
          },
        );
        expect(
          replayWithOtherPrincipal.statusCode,
          equals(HttpStatus.notFound),
        );

        final primaryAfterRejected = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          {...toolsPayload, 'id': 'secure-h3-primary-after-rejected'},
          headers: streamableHeaders(
            'tools/list',
            bearerToken: primaryGrant.accessToken,
          ),
        );
        expect(primaryAfterRejected.statusCode, equals(HttpStatus.ok));
        expect(
          primaryAfterRejected.headers['mcp-session-id'],
          equals(mcpSessionId),
        );

        final delete = await _requestHttp3(
          nativeLibPath,
          listener.http3Port,
          '/mcp/secure',
          method: 'DELETE',
          headers: <String, String>{
            ...sessionHeaders,
            HttpHeaders.authorizationHeader:
                'Bearer ${primaryGrant.accessToken}',
          },
        );
        expect(delete.statusCode, equals(HttpStatus.accepted));
      },
      skip: skipReason,
    );

    test(
      'serves protected direct JSON WAMP helpers over native HTTP/3',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9138,
          nativeLib: nativeLib,
          config: _buildTlsConfig(),
          settings: _buildMcpSmokeSettings(enableHttp3: true),
          connectionSequence: const [],
        );
        addTearDown(harness.dispose);

        if (!harness.runtime.supportsHttp3TestClient) {
          // Skip without failing the suite when ffi-test helpers are unavailable.
          // ignore: avoid_print
          print(
            'Skipping protected HTTP/3 MCP direct JSON test: '
            'native runtime lacks test client',
          );
          return;
        }

        final binding = harness.binding;
        final serviceSession = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-http3-direct-secure-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final registration = await serviceSession.register('app.safe.lookup');
        registration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: {'received': invocation.argumentsKeywords},
          );
        });

        final listener = binding.listeners.single;
        expect(
          listener.http3Port,
          greaterThan(0),
          reason: 'Router did not expose an HTTP/3 port',
        );
        final nativeLibPath = nativeLib!;
        final origin = 'https://127.0.0.1:${listener.http3Port}';
        final grant = await _issueTicketHttp3Grant(
          nativeLibPath,
          listener.http3Port,
          authId: 'user-1',
        );

        Map<String, String> directHeaders(
          String method, {
          String? bearerToken,
        }) {
          return <String, String>{
            'origin': origin,
            HttpHeaders.acceptHeader: ContentType.json.mimeType,
            'MCP-Protocol-Version': '2025-11-25',
            'Mcp-Method': method,
            if (bearerToken != null)
              HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
          };
        }

        Future<
          ({
            String body,
            Map<String, String> headers,
            Map<String, Object?>? json,
            int statusCode,
          })
        >
        postDirectJsonResponse(
          String method,
          Map<String, Object?> params, {
          required String id,
          String? bearerToken,
        }) {
          return _postHttp3Json(
            nativeLibPath,
            listener.http3Port,
            '/mcp/secure',
            {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params},
            headers: directHeaders(method, bearerToken: bearerToken),
          );
        }

        Future<Map<String, Object?>> postDirectJson(
          String method,
          Map<String, Object?> params, {
          required String id,
        }) async {
          final response = await postDirectJsonResponse(
            method,
            params,
            id: id,
            bearerToken: grant.accessToken,
          );
          expect(response.statusCode, equals(HttpStatus.ok));
          expect(response.headers['mcp-session-id'], isNull);
          expect(response.json?['id'], equals(id));
          final error = response.json?['error'];
          if (error != null) {
            fail(
              'Protected HTTP/3 direct JSON method $method returned '
              'error: ${jsonEncode(error)}',
            );
          }
          return (response.json?['result'] as Map).cast<String, Object?>();
        }

        Future<Map<String, Object?>> pollUntilEvents(String handle) async {
          for (var attempt = 0; attempt < 30; attempt += 1) {
            final result = await postDirectJson(
              'connectanum.pubsub.poll',
              {'handle': handle, 'limit': 10},
              id: 'secure-h3-direct-pubsub-poll-$attempt',
            );
            final structured = (result['structuredContent'] as Map)
                .cast<String, Object?>();
            final events = structured['events'] as List? ?? const [];
            if (events.isNotEmpty) {
              return structured;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          fail(
            'Timed out waiting for protected HTTP/3 direct JSON pub/sub events',
          );
        }

        final missingBearer = await postDirectJsonResponse(
          'connectanum.api.list',
          {'kind': 'topic'},
          id: 'secure-h3-direct-missing-bearer',
        );
        expect(missingBearer.statusCode, equals(HttpStatus.unauthorized));
        expect(
          missingBearer.headers[HttpHeaders.wwwAuthenticateHeader],
          contains('Bearer'),
        );
        expect(missingBearer.headers, isNot(contains('mcp-session-id')));

        final invalidBearer = await postDirectJsonResponse(
          'connectanum.api.list',
          {'kind': 'topic'},
          id: 'secure-h3-direct-invalid-bearer',
          bearerToken: 'invalid-token',
        );
        expect(invalidBearer.statusCode, equals(HttpStatus.unauthorized));
        expect(invalidBearer.headers, isNot(contains('mcp-session-id')));

        final tools = await postDirectJson(
          'tools/list',
          const <String, Object?>{},
          id: 'secure-h3-direct-tools-list',
        );
        final toolList = (tools['tools'] as List).cast<Map>();
        expect(
          toolList.map((tool) => tool['name']),
          contains('app.safe.lookup'),
        );
        expect(
          toolList.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        expect(
          toolList.map((tool) => tool['name']),
          contains('connectanum.pubsub.publish'),
        );

        final topicCatalog = await postDirectJson('connectanum.api.list', {
          'kind': 'topic',
        }, id: 'secure-h3-direct-topic-catalog');
        final topicCatalogContent = (topicCatalog['structuredContent'] as Map)
            .cast<String, Object?>();
        expect(
          (topicCatalogContent['metadata'] as Map).cast<String, Object?>(),
          allOf(
            containsPair('authid', 'user-1'),
            containsPair('authrole', 'member'),
          ),
        );
        expect(jsonEncode(topicCatalogContent), contains('app.secure.audit'));

        final sessionList = await postDirectJson(
          'wamp.session.list',
          const <String, Object?>{},
          id: 'secure-h3-direct-session-list',
        );
        final sessionIds =
            (((sessionList['structuredContent'] as Map)['argumentsKeywords']
                            as Map)
                        .cast<String, Object?>()['session_ids']
                    as List)
                .cast<Object?>();
        expect(sessionIds, hasLength(1));
        expect(sessionIds, isNot(contains(serviceSession.sessionId)));
        final visibleSessionId = (sessionIds.single as num).toInt();

        final sessionGet = await postDirectJson('wamp.session.get', {
          'id': visibleSessionId,
        }, id: 'secure-h3-direct-session-get');
        final sessionDetails =
            ((((sessionGet['structuredContent'] as Map)['argumentsKeywords']
                            as Map)
                        .cast<String, Object?>()['details']
                    as Map)
                .cast<String, Object?>());
        expect(sessionDetails['authid'], equals('user-1'));
        expect(sessionDetails['authrole'], equals('member'));

        final registrationLookup = await postDirectJson(
          'wamp.registration.lookup',
          {
            'arguments': ['app.safe.lookup'],
            'argumentsKeywords': {'match': 'exact'},
          },
          id: 'secure-h3-direct-registration-lookup',
        );
        final registrationId =
            (((registrationLookup['structuredContent'] as Map)['arguments']
                            as List)
                        .single
                    as num)
                .toInt();
        expect(registrationId, greaterThan(0));

        final registrationCallees = await postDirectJson(
          'wamp.registration.list_callees',
          {'id': registrationId},
          id: 'secure-h3-direct-registration-callees',
        );
        final registrationCalleeIds =
            ((registrationCallees['structuredContent'] as Map)['arguments']
                    as List)
                .cast<Object?>();
        expect(registrationCalleeIds, isEmpty);
        expect(
          registrationCalleeIds,
          isNot(contains(serviceSession.sessionId)),
        );

        String? subscriptionHandle;
        try {
          final subscribe = await postDirectJson(
            'connectanum.pubsub.subscribe',
            {'topic': 'app.secure.audit', 'queueLimit': 5},
            id: 'secure-h3-direct-pubsub-subscribe',
          );
          final subscribeContent = (subscribe['structuredContent'] as Map)
              .cast<String, Object?>();
          expect(subscribeContent['topic'], equals('app.secure.audit'));
          subscriptionHandle = subscribeContent['handle'] as String;
          expect(subscriptionHandle, isNotEmpty);

          final publish = await postDirectJson('connectanum.pubsub.publish', {
            'topic': 'app.secure.audit',
            'argumentsKeywords': {'via': 'secure-h3-direct-json-publish'},
            'acknowledge': true,
          }, id: 'secure-h3-direct-pubsub-publish');
          expect(
            publish['structuredContent'],
            containsPair('acknowledged', true),
          );

          await serviceSession.publish(
            'app.secure.audit',
            argumentsKeywords: {'via': 'secure-h3-direct-json-service'},
            options: core.PublishOptions(acknowledge: true),
          );
          final polled = await pollUntilEvents(subscriptionHandle);
          expect(
            jsonEncode(polled['events']),
            contains('secure-h3-direct-json-service'),
          );
        } finally {
          if (subscriptionHandle != null) {
            final unsubscribe = await postDirectJson(
              'connectanum.pubsub.unsubscribe',
              {'handle': subscriptionHandle},
              id: 'secure-h3-direct-pubsub-unsubscribe',
            );
            expect(
              unsubscribe['structuredContent'],
              containsPair('unsubscribed', true),
            );
          }
        }
      },
      skip: skipReason,
    );

    test('allows MCP CORS preflight over native HTTP/3', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9136,
        nativeLib: nativeLib,
        config: _buildTlsConfig(),
        settings: _buildRouterSettings(
          enableHttp3: true,
          enableMcp: true,
          mcpRouteMatch: const HttpRouteMatch(
            path: '/mcp',
            methods: ['GET'],
            protocols: ['http3'],
          ),
          mcpMethodActions: const <String, HttpRouteAction>{
            'POST': HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: 'realm1',
            ),
          },
        ),
        connectionSequence: const [],
      );
      addTearDown(harness.dispose);

      if (!harness.runtime.supportsHttp3TestClient) {
        // Skip without failing the suite when ffi-test helpers are unavailable.
        // ignore: avoid_print
        print(
          'Skipping HTTP/3 MCP preflight test: '
          'native runtime lacks test client',
        );
        return;
      }

      final listener = harness.binding.listeners.single;
      expect(
        listener.http3Port,
        greaterThan(0),
        reason: 'Router did not expose an HTTP/3 port',
      );
      final nativeLibPath = nativeLib!;
      final origin = 'https://127.0.0.1:${listener.http3Port}';
      final preflight = await _requestHttp3(
        nativeLibPath,
        listener.http3Port,
        '/mcp',
        method: 'OPTIONS',
        headers: <String, String>{
          'origin': origin,
          'access-control-request-method': 'POST',
          'access-control-request-headers':
              'Content-Type, MCP-Protocol-Version',
        },
      );

      expect(preflight.statusCode, equals(HttpStatus.noContent));
      expect(preflight.body, isEmpty);
      expect(preflight.headers['access-control-allow-origin'], equals(origin));
      expect(
        preflight.headers['access-control-allow-methods'],
        allOf(contains('POST'), contains('OPTIONS')),
      );
      expect(
        preflight.headers['access-control-allow-headers']?.toLowerCase(),
        allOf(contains('content-type'), contains('mcp-protocol-version')),
      );
      expect(preflight.headers, isNot(contains('mcp-session-id')));
    }, skip: skipReason);

    test('serves direct JSON WAMP helpers over native HTTP/3', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9128,
        nativeLib: nativeLib,
        config: _buildTlsConfig(),
        settings: _buildRouterSettings(
          enableHttp3: true,
          enableMcp: true,
          mcpRouteMatch: const HttpRouteMatch(
            path: '/mcp',
            protocols: ['http3'],
          ),
          mcpOptions: const <String, Object?>{
            'post_response_transport': 'json',
            'tool_list_page_size': 100,
            'topics': [
              {
                'topic': 'app.events.audit',
                'title': 'Audit events',
                'description': 'Events exposed through router-hosted MCP.',
              },
            ],
          },
        ),
        connectionSequence: const [],
      );
      addTearDown(harness.dispose);

      if (!harness.runtime.supportsHttp3TestClient) {
        // Skip without failing the suite when ffi-test helpers are unavailable.
        // ignore: avoid_print
        print(
          'Skipping HTTP/3 MCP direct JSON test: '
          'native runtime lacks test client',
        );
        return;
      }

      final binding = harness.binding;
      final serviceSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'mcp-http3-direct-service',
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
      expect(
        listener.http3Port,
        greaterThan(0),
        reason: 'Router did not expose an HTTP/3 port',
      );
      final nativeLibPath = nativeLib!;
      final origin = 'https://127.0.0.1:${listener.http3Port}';

      Map<String, String> directHeaders(String method) {
        return <String, String>{
          'origin': origin,
          HttpHeaders.acceptHeader: ContentType.json.mimeType,
          'MCP-Protocol-Version': '2025-11-25',
          'Mcp-Method': method,
        };
      }

      Future<Map<String, Object?>> postDirectJson(
        String method,
        Map<String, Object?> params, {
        required String id,
      }) async {
        final response = await _postHttp3Json(
          nativeLibPath,
          listener.http3Port,
          '/mcp',
          {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params},
          headers: directHeaders(method),
        );
        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.headers['mcp-session-id'], isNull);
        expect(response.json?['id'], equals(id));
        final error = response.json?['error'];
        if (error != null) {
          fail(
            'HTTP/3 direct JSON method $method returned '
            'error: ${jsonEncode(error)}',
          );
        }
        return (response.json?['result'] as Map).cast<String, Object?>();
      }

      Future<Map<String, Object?>> pollUntilEvents(String handle) async {
        for (var attempt = 0; attempt < 30; attempt += 1) {
          final result = await postDirectJson('connectanum.pubsub.poll', {
            'handle': handle,
            'limit': 10,
          }, id: 'h3-direct-pubsub-poll-$attempt');
          final structured = (result['structuredContent'] as Map)
              .cast<String, Object?>();
          final events = structured['events'] as List? ?? const [];
          if (events.isNotEmpty) {
            return structured;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Timed out waiting for HTTP/3 direct JSON pub/sub events');
      }

      final tools = await postDirectJson(
        'tools/list',
        const <String, Object?>{},
        id: 'h3-direct-tools-list',
      );
      final toolList = (tools['tools'] as List).cast<Map>();
      expect(toolList.map((tool) => tool['name']), contains('app.echo'));

      final topicCatalog = await postDirectJson('connectanum.api.list', {
        'kind': 'topic',
      }, id: 'h3-direct-topic-catalog');
      final topicCatalogContent = (topicCatalog['structuredContent'] as Map)
          .cast<String, Object?>();
      expect(
        (topicCatalogContent['metadata'] as Map).cast<String, Object?>(),
        containsPair('authid', 'anonymous'),
      );
      expect(jsonEncode(topicCatalogContent), contains('app.events.audit'));

      final registrationLookup = await postDirectJson(
        'wamp.registration.lookup',
        {
          'arguments': ['app.echo'],
          'argumentsKeywords': {'match': 'exact'},
        },
        id: 'h3-direct-registration-lookup',
      );
      final registrationLookupContent =
          (registrationLookup['structuredContent'] as Map)
              .cast<String, Object?>();
      final registrationId =
          ((registrationLookupContent['arguments'] as List).single as num)
              .toInt();
      expect(registrationId, greaterThan(0));

      final registrationCallees = await postDirectJson(
        'wamp.registration.list_callees',
        {
          'arguments': [registrationId],
        },
        id: 'h3-direct-registration-callees',
      );
      final registrationCalleeIds =
          ((registrationCallees['structuredContent'] as Map)['arguments']
                  as List)
              .cast<Object?>();
      expect(registrationCalleeIds, isEmpty);
      expect(registrationCalleeIds, isNot(contains(serviceSession.sessionId)));

      String? subscriptionHandle;
      try {
        final subscribe = await postDirectJson('connectanum.pubsub.subscribe', {
          'topic': 'app.events.audit',
          'queueLimit': 5,
        }, id: 'h3-direct-pubsub-subscribe');
        final subscribeContent = (subscribe['structuredContent'] as Map)
            .cast<String, Object?>();
        expect(subscribeContent['topic'], equals('app.events.audit'));
        subscriptionHandle = subscribeContent['handle'] as String;
        expect(subscriptionHandle, isNotEmpty);

        final publish = await postDirectJson('connectanum.pubsub.publish', {
          'topic': 'app.events.audit',
          'argumentsKeywords': {'via': 'h3-direct-json-publish'},
          'acknowledge': true,
        }, id: 'h3-direct-pubsub-publish');
        final publishContent = (publish['structuredContent'] as Map)
            .cast<String, Object?>();
        expect(publishContent['acknowledged'], isTrue);

        await serviceSession.publish(
          'app.events.audit',
          argumentsKeywords: {'via': 'h3-direct-json-service'},
          options: core.PublishOptions(acknowledge: true),
        );
        final polled = await pollUntilEvents(subscriptionHandle);
        expect(
          jsonEncode(polled['events']),
          contains('h3-direct-json-service'),
        );
      } finally {
        if (subscriptionHandle != null) {
          final unsubscribe = await postDirectJson(
            'connectanum.pubsub.unsubscribe',
            {'handle': subscriptionHandle},
            id: 'h3-direct-pubsub-unsubscribe',
          );
          final unsubscribeContent = (unsubscribe['structuredContent'] as Map)
              .cast<String, Object?>();
          expect(unsubscribeContent['unsubscribed'], isTrue);
        }
      }
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

        final adminResult = await _postJson(client, listener.port, '/mcp', {
          'jsonrpc': '2.0',
          'id': 'admin-reset-denied',
          'method': 'tools/call',
          'params': {
            'name': 'app.admin.reset',
            'arguments': {'id': 'T-1'},
          },
        });
        expect(adminResult.statusCode, equals(HttpStatus.ok));
        expect(adminResult.json?['error'], isA<Map<String, Object?>>());
        expect(jsonEncode(adminResult.json?['error']), contains('Unknown MCP'));
      },
      skip: skipReason,
    );

    test(
      'isolates MCP Streamable HTTP sessions by route and bearer principal',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9115,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-session-isolation-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);
        final observedSafeLookupTaskIds = <String>{};
        final directMetaRegistration = await serviceSession.register(
          'app.safe.lookup',
        );
        directMetaRegistration.onInvoke((invocation) {
          final taskId = invocation.argumentsKeywords?['taskId'];
          if (taskId != null) {
            observedSafeLookupTaskIds.add(taskId.toString());
          }
          invocation.respondWith(
            argumentsKeywords: {'value': invocation.argumentsKeywords?['id']},
          );
        });
        final httpClient = HttpClient();
        addTearDown(() => httpClient.close(force: true));

        final primaryGrant = await _issueTicketHttpGrant(
          httpClient,
          listener.port,
          authId: 'user-1',
        );
        final otherGrant = await _issueTicketHttpGrant(
          httpClient,
          listener.port,
          authId: 'user-2',
        );

        final secureMcpEndpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/secure',
        );
        final primaryMcpClient = McpStreamableHttpClient.withAuthGrant(
          secureMcpEndpoint,
          primaryGrant,
        );
        addTearDown(() => primaryMcpClient.close(force: true));

        await primaryMcpClient.initialize();
        await primaryMcpClient.notifyInitialized();
        final primarySessionId = primaryMcpClient.sessionId;
        expect(primarySessionId, isNotNull);

        final sessionHeaders = <String, String>{
          'MCP-Session-Id': primarySessionId!,
          'MCP-Protocol-Version': '2025-11-25',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        };
        final toolsHeaders = <String, String>{
          ...sessionHeaders,
          'Mcp-Method': 'tools/list',
        };
        final toolsPayload = <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'secure-tools',
          'method': 'tools/list',
          'params': {},
        };
        final directMissingBearer = await _postJson(
          httpClient,
          listener.port,
          '/mcp/secure',
          toolsPayload,
          headers: {
            HttpHeaders.acceptHeader: 'application/json',
            'MCP-Session-Id': primarySessionId,
            'MCP-Protocol-Version': '2025-11-25',
          },
        );
        expect(directMissingBearer.statusCode, equals(HttpStatus.unauthorized));
        expect(
          directMissingBearer.headers[HttpHeaders.wwwAuthenticateHeader],
          contains('Bearer'),
        );
        expect(directMissingBearer.headers, isNot(contains('mcp-session-id')));

        final directInvalidBearer = await _postJson(
          httpClient,
          listener.port,
          '/mcp/secure',
          toolsPayload,
          headers: {
            HttpHeaders.acceptHeader: 'application/json',
            'MCP-Session-Id': primarySessionId,
            'MCP-Protocol-Version': '2025-11-25',
            HttpHeaders.authorizationHeader: 'Bearer invalid-token',
          },
        );
        expect(directInvalidBearer.statusCode, equals(HttpStatus.unauthorized));
        expect(directInvalidBearer.headers, isNot(contains('mcp-session-id')));

        final streamableMissingBearer = await _postJson(
          httpClient,
          listener.port,
          '/mcp/secure',
          toolsPayload,
          headers: toolsHeaders,
        );
        expect(
          streamableMissingBearer.statusCode,
          equals(HttpStatus.unauthorized),
        );
        expect(
          streamableMissingBearer.headers,
          isNot(contains('mcp-session-id')),
        );

        final reuseWithOtherPrincipal = await _postJson(
          httpClient,
          listener.port,
          '/mcp/secure',
          {...toolsPayload, 'id': 'cross-principal-tools'},
          headers: {
            ...toolsHeaders,
            HttpHeaders.authorizationHeader: 'Bearer ${otherGrant.accessToken}',
          },
        );
        expect(reuseWithOtherPrincipal.statusCode, equals(HttpStatus.notFound));
        expect(
          reuseWithOtherPrincipal.headers,
          isNot(contains('mcp-session-id')),
        );
        expect(
          jsonEncode(reuseWithOtherPrincipal.json?['error']),
          contains('Unknown MCP HTTP session'),
        );

        final otherPrincipalMcpClient = McpStreamableHttpClient.withBearerToken(
          secureMcpEndpoint,
          otherGrant.accessToken,
        );
        addTearDown(() => otherPrincipalMcpClient.close(force: true));
        final otherDirectTools = await otherPrincipalMcpClient.listToolsDirect(
          id: 'secure-other-direct-tools',
        );
        expect(
          otherDirectTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        await _expectDirectSafeLookupMethod(
          otherPrincipalMcpClient,
          taskId: 'T-secure-other-direct-method',
          label: 'secure-other',
        );
        await _expectDirectSafeLookupNotifications(
          otherPrincipalMcpClient,
          observedSafeLookupTaskIds,
          label: 'secure-other',
        );
        final otherDirectTopicCatalog = await otherPrincipalMcpClient
            .listWampApi(
              id: 'secure-other-direct-topic-catalog',
              kind: 'topic',
              directJson: true,
            );
        expect(
          jsonEncode(otherDirectTopicCatalog),
          contains('app.secure.audit'),
        );
        await _expectDirectPrincipalWampMetaHelpers(
          otherPrincipalMcpClient,
          serviceSession,
          procedure: 'app.safe.lookup',
          topic: 'app.secure.audit',
          authId: 'user-2',
          authRole: 'member',
          label: 'secure-other-direct',
        );
        final otherDirectSubscription = await otherPrincipalMcpClient
            .subscribeWampTopicDirect(
              'app.secure.audit',
              id: 'secure-other-direct-subscribe',
              queueLimit: 4,
            );
        try {
          await serviceSession.publish(
            'app.secure.audit',
            argumentsKeywords: const <String, Object?>{
              'via': 'secure-other-direct-service',
            },
            options: core.PublishOptions(acknowledge: true),
          );
          final otherDirectEvents = await _pollDirectRouterJsonUntilEvents(
            httpClient,
            listener.port,
            '/mcp/secure',
            otherDirectSubscription.handle,
            headers: <String, String>{
              HttpHeaders.authorizationHeader:
                  'bearer ${otherGrant.accessToken}',
            },
          );
          expect(
            jsonEncode(otherDirectEvents['events']),
            contains('secure-other-direct-service'),
          );
        } finally {
          await otherPrincipalMcpClient.unsubscribeWampTopicDirect(
            otherDirectSubscription.handle,
            id: 'secure-other-direct-unsubscribe',
          );
        }
        expect(otherPrincipalMcpClient.sessionId, isNull);
        expect(otherPrincipalMcpClient.lastEventId, isNull);

        final otherInitialize = await otherPrincipalMcpClient.initialize(
          id: 'secure-other-initialize',
        );
        expect(otherInitialize['id'], equals('secure-other-initialize'));
        final otherSessionId = otherPrincipalMcpClient.sessionId;
        expect(otherSessionId, isNotNull);
        expect(otherSessionId, isNot(equals(primarySessionId)));
        await otherPrincipalMcpClient.notifyInitialized();
        final otherTools = await otherPrincipalMcpClient.listTools(
          id: 'secure-other-tools',
        );
        expect(
          otherTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        expect(otherPrincipalMcpClient.sessionId, equals(otherSessionId));
        expect(
          otherPrincipalMcpClient.lastEventId,
          startsWith('$otherSessionId:'),
        );
        final otherToolsEventId = otherPrincipalMcpClient.lastEventId;
        final otherStreamableSubscription = await otherPrincipalMcpClient
            .subscribeWampTopic(
              'app.secure.audit',
              id: 'secure-other-streamable-subscribe',
              queueLimit: 4,
            );
        try {
          await serviceSession.publish(
            'app.secure.audit',
            argumentsKeywords: const <String, Object?>{
              'via': 'secure-other-streamable-service',
            },
            options: core.PublishOptions(acknowledge: true),
          );
          final otherStreamableEvents = await _pollStreamableMcpUntilEvents(
            otherPrincipalMcpClient,
            otherStreamableSubscription.handle,
          );
          expect(
            jsonEncode(otherStreamableEvents['events']),
            contains('secure-other-streamable-service'),
          );
        } finally {
          await otherPrincipalMcpClient.unsubscribeWampTopic(
            otherStreamableSubscription.handle,
            id: 'secure-other-streamable-unsubscribe',
          );
        }
        expect(otherPrincipalMcpClient.sessionId, equals(otherSessionId));
        expect(
          otherPrincipalMcpClient.lastEventId,
          allOf(
            startsWith('$otherSessionId:'),
            isNot(equals(otherToolsEventId)),
          ),
        );
        await otherPrincipalMcpClient.deleteSession();
        expect(otherPrincipalMcpClient.sessionId, isNull);
        expect(otherPrincipalMcpClient.lastEventId, isNull);
        expect(primaryMcpClient.sessionId, equals(primarySessionId));

        final publicRouteReuse =
            await _postJson(httpClient, listener.port, '/mcp/public', {
              'jsonrpc': '2.0',
              'id': 'cross-route-tools',
              'method': 'tools/list',
              'params': {},
            }, headers: toolsHeaders);
        expect(publicRouteReuse.statusCode, equals(HttpStatus.notFound));
        expect(publicRouteReuse.headers, isNot(contains('mcp-session-id')));
        expect(
          jsonEncode(publicRouteReuse.json?['error']),
          contains('Unknown MCP HTTP session'),
        );

        final pollWithOtherPrincipal = await _getHttp(
          httpClient,
          listener.port,
          '/mcp/secure',
          headers: {
            ...sessionHeaders,
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${otherGrant.accessToken}',
          },
        );
        expect(pollWithOtherPrincipal.statusCode, equals(HttpStatus.notFound));

        final deleteWithOtherPrincipal = await _deleteHttp(
          httpClient,
          listener.port,
          '/mcp/secure',
          headers: {
            ...sessionHeaders,
            HttpHeaders.authorizationHeader: 'Bearer ${otherGrant.accessToken}',
          },
        );
        expect(
          deleteWithOtherPrincipal.statusCode,
          equals(HttpStatus.notFound),
        );

        final primaryTools = await primaryMcpClient.listTools(
          id: 'primary-tools-after-reuse-attempts',
        );
        expect(
          primaryTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );

        await primaryMcpClient.deleteSession();
        expect(primaryMcpClient.sessionId, isNull);

        primaryMcpClient.sessionId = primarySessionId;
        primaryMcpClient.lastEventId = '$primarySessionId:get:1';
        await expectLater(
          primaryMcpClient.listTools(id: 'primary-tools-after-delete'),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        expect(primaryMcpClient.sessionId, isNull);
        expect(primaryMcpClient.lastEventId, isNull);

        final recoveredInitialize = await primaryMcpClient.initialize(
          id: 'recovered-initialize',
        );
        expect(recoveredInitialize['id'], equals('recovered-initialize'));
        expect(primaryMcpClient.sessionId, isNotNull);
        expect(primaryMcpClient.sessionId, isNot(equals(primarySessionId)));
        await primaryMcpClient.notifyInitialized();
        final recoveredTools = await primaryMcpClient.listTools(
          id: 'primary-tools-after-reinitialize',
        );
        expect(
          recoveredTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        await primaryMcpClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'does not retain compatibility MCP sessions for initialize notifications',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9170,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxSessionCount: 1),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final httpClient = HttpClient();
        addTearDown(() => httpClient.close(force: true));

        final notification = await _postJson(
          httpClient,
          listener.port,
          endpoint.path,
          <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'initialize',
            'params': <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{},
              'clientInfo': <String, Object?>{
                'name': 'router-initialize-notification-test',
                'version': '1.0.0',
              },
            },
          },
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'Origin': 'http://127.0.0.1:${listener.port}',
            'MCP-Protocol-Version': '2025-11-25',
          },
        );
        expect(notification.statusCode, equals(HttpStatus.accepted));
        expect(notification.body, isEmpty);
        expect(notification.headers, isNot(contains('mcp-session-id')));

        final validClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => validClient.close(force: true));
        final initialized = await validClient.initialize(
          id: 'initialize-after-notification',
        );
        expect(initialized['id'], equals('initialize-after-notification'));
        expect(validClient.sessionId, isNotNull);
        await validClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'bounds compatibility MCP sessions per route without blocking auth or direct JSON',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9143,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxSessionCount: 1),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final publicEndpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final secureEndpoint = publicEndpoint.replace(path: '/mcp/secure');
        final publicPrimary = McpStreamableHttpClient(publicEndpoint);
        final publicContender = McpStreamableHttpClient(publicEndpoint);
        final publicDirect = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-session-capacity-test',
            'version': '1.0.0',
          },
        );
        addTearDown(() => publicPrimary.close(force: true));
        addTearDown(() => publicContender.close(force: true));
        addTearDown(() => publicDirect.close(force: true));

        await publicPrimary.initialize(id: 'public-capacity-primary');
        await publicPrimary.notifyInitialized();
        final publicSessionId = publicPrimary.sessionId;
        expect(publicSessionId, isNotNull);

        await expectLater(
          publicContender.initialize(id: 'public-capacity-contender'),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.serviceUnavailable,
                )
                .having(
                  (error) => error.body,
                  'body',
                  contains('session capacity is exhausted'),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(publicContender.sessionId, isNull);
        expect(publicContender.lastEventId, isNull);
        expect(
          await publicDirect.pingDirect(id: 'public-capacity-direct'),
          containsPair('resultType', 'complete'),
        );
        expect(publicDirect.sessionId, isNull);
        expect(publicDirect.lastEventId, isNull);
        final publicTools = await publicPrimary.listTools(
          id: 'public-capacity-primary-tools',
        );
        expect(
          publicTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        expect(publicPrimary.sessionId, equals(publicSessionId));

        final unauthenticatedSecure = McpStreamableHttpClient(secureEndpoint);
        addTearDown(() => unauthenticatedSecure.close(force: true));
        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final grant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final securePrimary = McpStreamableHttpClient.withAuthGrant(
          secureEndpoint,
          grant,
        );
        final secureContender = McpStreamableHttpClient.withAuthGrant(
          secureEndpoint,
          grant,
        );
        addTearDown(() => securePrimary.close(force: true));
        addTearDown(() => secureContender.close(force: true));

        await securePrimary.initialize(id: 'secure-capacity-primary');
        await securePrimary.notifyInitialized();
        final secureSessionId = securePrimary.sessionId;
        expect(secureSessionId, isNotNull);
        await expectLater(
          unauthenticatedSecure.initialize(
            id: 'secure-capacity-unauthenticated',
          ),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );
        expect(unauthenticatedSecure.sessionId, isNull);
        await expectLater(
          secureContender.initialize(id: 'secure-capacity-contender'),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.serviceUnavailable,
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(secureContender.sessionId, isNull);
        final secureTools = await securePrimary.listTools(
          id: 'secure-capacity-primary-tools',
        );
        expect(
          secureTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        expect(securePrimary.sessionId, equals(secureSessionId));

        await publicPrimary.deleteSession();
        await publicContender.initialize(id: 'public-capacity-after-delete');
        expect(publicContender.sessionId, isNotNull);
        await publicContender.deleteSession();

        await securePrimary.deleteSession();
        await secureContender.initialize(id: 'secure-capacity-after-delete');
        expect(secureContender.sessionId, isNotNull);
        await secureContender.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'bounds modern request-scoped MCP SSE acknowledgment events and releases capacity',
      () async {
        const responseLimit = 4096;
        const requestId = 'modern-listener-response-wire-bound';
        const resourcePrefix = 'app://mcp/modern-listener-wire-bound/';

        Map<String, Object?> acknowledgmentFor(String resourceUri) =>
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/subscriptions/acknowledged',
              'params': <String, Object?>{
                '_meta': <String, Object?>{
                  'io.modelcontextprotocol/subscriptionId': requestId,
                },
                'notifications': <String, Object?>{
                  'resourceSubscriptions': <String>[resourceUri],
                },
              },
            };

        final unpaddedJson = jsonEncode(acknowledgmentFor(resourcePrefix));
        final paddingLength = responseLimit - utf8.encode(unpaddedJson).length;
        expect(paddingLength, greaterThan(0));
        final resourceUri =
            '$resourcePrefix${List<String>.filled(paddingLength, 'x').join()}';
        final acknowledgmentJson = jsonEncode(acknowledgmentFor(resourceUri));
        expect(utf8.encode(acknowledgmentJson).length, equals(responseLimit));
        expect(
          utf8.encode('data: $acknowledgmentJson\n\n').length,
          greaterThan(responseLimit),
        );

        final harness = await _RouterHarness.start(
          connectionId: 9144,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(
            maxRequestScopedListenerCount: 1,
            maxResponseBytes: responseLimit,
            additionalLiveResourceUris: <String>[resourceUri],
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-modern-listener-response-bound',
            'version': '1.0.0',
          },
        );
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.listen(
            id: requestId,
            resourceSubscriptions: <String>[resourceUri],
          ),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  contains('response body exceeds the configured limit'),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        final recovered = await client.listen(
          id: 'modern-listener-response-bound-recovered',
          toolsListChanged: true,
        );
        addTearDown(recovered.close);
        expect(recovered.acknowledgedNotifications.toolsListChanged, isTrue);
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        await recovered.close();
        expect(
          await client.pingDirect(
            id: 'modern-listener-response-bound-direct-recovery',
          ),
          containsPair('resultType', 'complete'),
        );
      },
      skip: skipReason,
    );

    test(
      'bounds modern request-scoped MCP SSE graceful completion events',
      () async {
        const responseLimit = 4096;
        const requestId = 'modern-listener-final-wire-bound';
        final serverDescription = List<String>.filled(
          responseLimit,
          'x',
        ).join();
        final acknowledgmentBytes = utf8
            .encode(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'method': 'notifications/subscriptions/acknowledged',
                'params': <String, Object?>{
                  '_meta': <String, Object?>{'io.modelcontextprotocol/subscriptionId': requestId},
                  'notifications': <String, Object?>{},
                },
              })}\n\n',
            )
            .length;
        final finalEventBytes = utf8
            .encode(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': requestId,
                'result': <String, Object?>{
                  'resultType': 'complete',
                  '_meta': <String, Object?>{
                    'io.modelcontextprotocol/serverInfo': <String, Object?>{'name': 'connectanum-router', 'version': '3.0.0-beta', 'description': serverDescription},
                    'io.modelcontextprotocol/subscriptionId': requestId,
                  },
                },
              })}\n\n',
            )
            .length;
        expect(acknowledgmentBytes, lessThanOrEqualTo(responseLimit));
        expect(finalEventBytes, greaterThan(responseLimit));

        final harness = await _RouterHarness.start(
          connectionId: 9144,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(
            maxResponseBytes: responseLimit,
            serverDescription: serverDescription,
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final client = McpStreamableHttpClient.stateless(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/public',
          ),
          clientInfo: const <String, Object?>{
            'name': 'router-modern-listener-final-bound',
            'version': '1.0.0',
          },
        );
        addTearDown(() => client.close(force: true));

        final subscription = await client.listen(id: requestId);
        final writeError = harness
            .nextEvent('mcp_request_scoped_sse_write_error')
            .timeout(const Duration(seconds: 5));
        await harness.dispose();

        expect(
          await subscription.closed.timeout(const Duration(seconds: 5)),
          equals(McpSubscriptionCloseReason.remote),
        );
        final event = await writeError;
        expect(
          event['error'],
          allOf(
            contains('$finalEventBytes bytes'),
            contains('configured $responseLimit-byte response limit'),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
      skip: skipReason,
    );

    test(
      'bounds request-scoped MCP listeners without blocking auth or other protocols',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9144,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxRequestScopedListenerCount: 1),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-listener-capacity-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final publicEndpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final secureEndpoint = publicEndpoint.replace(path: '/mcp/secure');
        final publicPrimary = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-primary',
            'version': '1.0.0',
          },
        );
        final publicContender = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-contender',
            'version': '1.0.0',
          },
        );
        final compatibilityClient = McpStreamableHttpClient(publicEndpoint);
        addTearDown(() => publicPrimary.close(force: true));
        addTearDown(() => publicContender.close(force: true));
        addTearDown(() => compatibilityClient.close(force: true));

        final publicSubscription = await publicPrimary.listen(
          id: 'public-listener-capacity-primary',
          toolsListChanged: true,
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        expect(
          publicSubscription.acknowledgedNotifications.toolsListChanged,
          isTrue,
        );
        expect(
          publicSubscription.acknowledgedNotifications.resourceSubscriptions,
          equals(const <String>['app://mcp/live-context']),
        );
        addTearDown(publicSubscription.close);
        final publicNotifications = StreamIterator<Map<String, Object?>>(
          publicSubscription.notifications,
        );
        addTearDown(publicNotifications.cancel);

        await expectLater(
          publicContender.listen(id: 'public-listener-capacity-contender'),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.serviceUnavailable,
                )
                .having(
                  (error) => error.body,
                  'body',
                  contains('request-scoped listener capacity is exhausted'),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(publicContender.sessionId, isNull);
        expect(publicContender.lastEventId, isNull);

        final rawClient = HttpClient();
        addTearDown(() => rawClient.close(force: true));
        final malformedListener = await _postJson(
          rawClient,
          listener.port,
          '/mcp/public',
          {
            'jsonrpc': '2.0',
            'id': 'public-listener-capacity-malformed',
            'method': 'subscriptions/listen',
            'params': {
              '_meta': {
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
              'notifications': <String, Object?>{'toolsListChanged': 'yes'},
            },
          },
          headers: {
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2026-07-28',
            'Mcp-Method': 'subscriptions/listen',
          },
        );
        expect(malformedListener.statusCode, equals(HttpStatus.badRequest));
        expect(
          (malformedListener.json?['error'] as Map)['code'],
          equals(McpErrorCodes.invalidParams),
        );

        expect(
          await publicContender.pingDirect(
            id: 'public-listener-capacity-direct',
          ),
          containsPair('resultType', 'complete'),
        );
        await compatibilityClient.initialize(
          id: 'public-listener-capacity-streamable-initialize',
        );
        await compatibilityClient.notifyInitialized();
        expect(
          (await compatibilityClient.listTools(
            id: 'public-listener-capacity-streamable-tools',
          )).tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        await compatibilityClient.deleteSession();

        final unauthenticatedSecure = McpStreamableHttpClient.stateless(
          secureEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-unauthenticated',
            'version': '1.0.0',
          },
        );
        addTearDown(() => unauthenticatedSecure.close(force: true));
        final primaryGrant = await _issueTicketHttpGrant(
          rawClient,
          listener.port,
        );
        final contenderGrant = await _issueTicketHttpGrant(
          rawClient,
          listener.port,
        );
        final securePrimary = McpStreamableHttpClient.statelessWithAuthGrant(
          secureEndpoint,
          primaryGrant,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-secure-primary',
            'version': '1.0.0',
          },
        );
        final secureContender = McpStreamableHttpClient.statelessWithAuthGrant(
          secureEndpoint,
          contenderGrant,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-secure-contender',
            'version': '1.0.0',
          },
        );
        addTearDown(() => securePrimary.close(force: true));
        addTearDown(() => secureContender.close(force: true));
        final secureSubscription = await securePrimary.listen(
          id: 'secure-listener-capacity-primary',
        );
        addTearDown(secureSubscription.close);

        await expectLater(
          unauthenticatedSecure.listen(
            id: 'secure-listener-capacity-unauthenticated',
          ),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );
        await expectLater(
          secureContender.listen(id: 'secure-listener-capacity-contender'),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.serviceUnavailable,
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );

        final publicUpdate = publicNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );
        final continuityRegistration = await serviceSession.register(
          'app.safe.listener_capacity_continuity',
        );
        addTearDown(
          () =>
              serviceSession.unregister(continuityRegistration.registrationId),
        );
        continuityRegistration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: const <String, Object?>{'status': 'ready'},
          );
        });
        await publicContender.listToolsDirect(
          id: 'public-listener-capacity-continuity-refresh',
        );
        expect(await publicUpdate, isTrue);
        expect(
          publicNotifications.current['method'],
          equals('notifications/tools/list_changed'),
        );
        expect(publicPrimary.sessionId, isNull);
        expect(publicPrimary.lastEventId, isNull);

        await publicNotifications.cancel();
        await publicSubscription.close();
        McpStreamableSubscription? recoveredSubscription;
        addTearDown(() async {
          await recoveredSubscription?.close();
        });
        final recoveryRegistration = await serviceSession.register(
          'app.safe.listener_capacity_recovery',
        );
        addTearDown(
          () => serviceSession.unregister(recoveryRegistration.registrationId),
        );
        recoveryRegistration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: const <String, Object?>{'status': 'ready'},
          );
        });
        for (var attempt = 0; attempt < 50; attempt++) {
          await serviceSession.publish(
            'app.events.resource.context',
            argumentsKeywords: <String, Object?>{'attempt': attempt},
            options: core.PublishOptions(acknowledge: true),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          try {
            recoveredSubscription = await publicContender.listen(
              id: 'public-listener-capacity-recovered-$attempt',
            );
            break;
          } on McpStreamableHttpException catch (error) {
            expect(error.statusCode, equals(HttpStatus.serviceUnavailable));
          }
        }
        expect(recoveredSubscription, isNotNull);
        expect(publicContender.sessionId, isNull);
        expect(publicContender.lastEventId, isNull);
        await recoveredSubscription!.close();
        await secureSubscription.close();
      },
      skip: skipReason,
    );

    test(
      'reserves request-scoped listener capacity during resource authorization',
      () async {
        final preparationEntered = Completer<void>();
        final releasePreparation = Completer<void>();
        AuthorizationProviderRegistry.registerProvider(
          _BlockingCatalogAuthorizationProvider(
            action: AuthorizationAction.subscribe,
            uri: 'app.events.resource.context',
            entered: preparationEntered,
            release: releasePreparation,
          ),
        );
        addTearDown(AuthorizationProviderRegistry.clear);
        addTearDown(() {
          if (!releasePreparation.isCompleted) {
            releasePreparation.complete();
          }
        });

        final harness = await _RouterHarness.start(
          connectionId: 9145,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxRequestScopedListenerCount: 1),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final primary = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-pending-primary',
            'version': '1.0.0',
          },
        );
        final contender = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-listener-capacity-pending-contender',
            'version': '1.0.0',
          },
        );
        addTearDown(() => primary.close(force: true));
        addTearDown(() => contender.close(force: true));

        final pendingPrimary = primary.listen(
          id: 'listener-capacity-pending-primary',
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        await preparationEntered.future.timeout(const Duration(seconds: 2));
        await expectLater(
          contender.listen(id: 'listener-capacity-pending-contender'),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.serviceUnavailable,
            ),
          ),
        );
        releasePreparation.complete();
        final primarySubscription = await pendingPrimary.timeout(
          const Duration(seconds: 3),
        );
        expect(primary.sessionId, isNull);
        expect(primary.lastEventId, isNull);
        await primarySubscription.close();
      },
      skip: skipReason,
    );

    test(
      'bounds router-hosted MCP WAMP subscriptions and event queues per route',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9146,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(
            maxWampSubscriptionCount: 1,
            maxWampSubscriptionQueueLimit: 2,
            maxWampSubscriptionQueueBytes: 2048,
          ),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-wamp-capacity-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final publicEndpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final secureEndpoint = publicEndpoint.replace(path: '/mcp/secure');
        final primary = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-capacity-primary',
            'version': '1.0.0',
          },
        );
        final contender = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-capacity-contender',
            'version': '1.0.0',
          },
        );
        final compatibility = McpStreamableHttpClient(publicEndpoint);
        final unauthenticatedSecure = McpStreamableHttpClient.stateless(
          secureEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-capacity-unauthenticated',
            'version': '1.0.0',
          },
        );
        addTearDown(() => primary.close(force: true));
        addTearDown(() => contender.close(force: true));
        addTearDown(() => compatibility.close(force: true));
        addTearDown(() => unauthenticatedSecure.close(force: true));

        await expectLater(
          primary.subscribeWampTopicDirect(
            'app.events.audit',
            id: 'wamp-capacity-oversized-queue',
            queueLimit: 3,
          ),
          throwsA(
            isA<McpStreamableWampToolException>().having(
              (error) => error.message,
              'message',
              contains('queue limit exceeds configured maximum'),
            ),
          ),
        );

        final primarySubscription = await primary.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'wamp-capacity-primary',
          queueLimit: 2,
        );
        expect(primarySubscription.queueLimit, equals(2));
        expect(primarySubscription.queueByteLimit, equals(2048));
        expect(primary.sessionId, isNull);

        await expectLater(
          contender.subscribeWampTopicDirect(
            'app.events.audit',
            id: 'wamp-capacity-contender',
            queueLimit: 1,
          ),
          throwsA(
            isA<McpStreamableWampToolException>().having(
              (error) => error.message,
              'message',
              contains('WAMP subscription capacity is exhausted'),
            ),
          ),
        );

        await serviceSession.publish(
          'app.events.audit',
          argumentsKeywords: const <String, Object?>{
            'via': 'capacity-continuity',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final primaryEvents = await primary.pollWampEventsDirect(
          primarySubscription.handle,
          id: 'wamp-capacity-primary-poll',
        );
        expect(primaryEvents.events, isNotEmpty);
        expect(primaryEvents.remainingBytes, 0);

        final byteBoundPadding = List<String>.filled(1200, 'x').join();
        for (var sequence = 1; sequence <= 2; sequence++) {
          await serviceSession.publish(
            'app.events.audit',
            argumentsKeywords: <String, Object?>{
              'sequence': sequence,
              'padding': byteBoundPadding,
            },
            options: core.PublishOptions(acknowledge: true),
          );
        }
        final byteBoundEvents = await primary.pollWampEventsDirect(
          primarySubscription.handle,
          id: 'wamp-capacity-byte-bound-poll',
        );
        expect(byteBoundEvents.events, hasLength(1));
        expect(
          byteBoundEvents.events.single['argumentsKeywords'],
          containsPair('sequence', 2),
        );
        expect(byteBoundEvents.dropped, 1);
        expect(byteBoundEvents.remaining, 0);
        expect(byteBoundEvents.remainingBytes, 0);

        await serviceSession.publish(
          'app.events.audit',
          argumentsKeywords: <String, Object?>{
            'sequence': 3,
            'padding': List<String>.filled(2200, 'x').join(),
          },
          options: core.PublishOptions(acknowledge: true),
        );
        await serviceSession.publish(
          'app.events.audit',
          argumentsKeywords: const <String, Object?>{'sequence': 4},
          options: core.PublishOptions(acknowledge: true),
        );
        final recoveredByteBoundEvents = await primary.pollWampEventsDirect(
          primarySubscription.handle,
          id: 'wamp-capacity-byte-bound-recovery-poll',
        );
        expect(recoveredByteBoundEvents.events, hasLength(1));
        expect(
          recoveredByteBoundEvents.events.single['argumentsKeywords'],
          containsPair('sequence', 4),
        );
        expect(recoveredByteBoundEvents.dropped, 2);
        expect(recoveredByteBoundEvents.remainingBytes, 0);

        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final primaryGrant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final contenderGrant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final securePrimary = McpStreamableHttpClient.statelessWithAuthGrant(
          secureEndpoint,
          primaryGrant,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-capacity-secure-primary',
            'version': '1.0.0',
          },
        );
        final secureContender = McpStreamableHttpClient.statelessWithAuthGrant(
          secureEndpoint,
          contenderGrant,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-capacity-secure-contender',
            'version': '1.0.0',
          },
        );
        addTearDown(() => securePrimary.close(force: true));
        addTearDown(() => secureContender.close(force: true));

        final secureSubscription = await securePrimary.subscribeWampTopicDirect(
          'app.secure.audit',
          id: 'wamp-capacity-secure-primary',
          queueLimit: 2,
        );
        await expectLater(
          unauthenticatedSecure.subscribeWampTopicDirect(
            'app.secure.audit',
            id: 'wamp-capacity-secure-unauthenticated',
            queueLimit: 1,
          ),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );
        await expectLater(
          secureContender.subscribeWampTopicDirect(
            'app.secure.audit',
            id: 'wamp-capacity-secure-contender',
            queueLimit: 1,
          ),
          throwsA(
            isA<McpStreamableWampToolException>().having(
              (error) => error.message,
              'message',
              contains('WAMP subscription capacity is exhausted'),
            ),
          ),
        );
        await securePrimary.unsubscribeWampTopicDirect(
          secureSubscription.handle,
          id: 'wamp-capacity-secure-release',
        );
        final recoveredSecure = await secureContender.subscribeWampTopicDirect(
          'app.secure.audit',
          id: 'wamp-capacity-secure-recovered',
          queueLimit: 1,
        );
        await secureContender.unsubscribeWampTopicDirect(
          recoveredSecure.handle,
          id: 'wamp-capacity-secure-recovered-release',
        );

        await primary.unsubscribeWampTopicDirect(
          primarySubscription.handle,
          id: 'wamp-capacity-primary-release',
        );

        final concurrentOutcomes = await Future.wait<Object>(<Future<Object>>[
          primary
              .subscribeWampTopicDirect(
                'app.events.audit',
                id: 'wamp-capacity-concurrent-primary',
                queueLimit: 1,
              )
              .then<Object>(
                (subscription) => subscription,
                onError: (error) => error,
              ),
          contender
              .subscribeWampTopicDirect(
                'app.events.audit',
                id: 'wamp-capacity-concurrent-contender',
                queueLimit: 1,
              )
              .then<Object>(
                (subscription) => subscription,
                onError: (error) => error,
              ),
        ]);
        expect(
          concurrentOutcomes.whereType<McpStreamableWampSubscriptionResult>(),
          hasLength(1),
        );
        expect(
          concurrentOutcomes.whereType<McpStreamableWampToolException>(),
          hasLength(1),
        );
        final concurrentWinner = concurrentOutcomes.indexWhere(
          (outcome) => outcome is McpStreamableWampSubscriptionResult,
        );
        final concurrentSubscription =
            concurrentOutcomes[concurrentWinner]
                as McpStreamableWampSubscriptionResult;
        final concurrentWinnerClient = concurrentWinner == 0
            ? primary
            : contender;
        final concurrentLoserClient = concurrentWinner == 0
            ? contender
            : primary;
        await concurrentWinnerClient.unsubscribeWampTopicDirect(
          concurrentSubscription.handle,
          id: 'wamp-capacity-concurrent-winner-release',
        );
        final concurrentRecovery = await concurrentLoserClient
            .subscribeWampTopicDirect(
              'app.events.audit',
              id: 'wamp-capacity-concurrent-loser-recovered',
              queueLimit: 1,
            );
        await concurrentLoserClient.unsubscribeWampTopicDirect(
          concurrentRecovery.handle,
          id: 'wamp-capacity-concurrent-loser-release',
        );

        await compatibility.initialize(id: 'wamp-capacity-compat-initialize');
        await compatibility.notifyInitialized();
        final compatibilitySubscription = await compatibility
            .subscribeWampTopic(
              'app.events.audit',
              id: 'wamp-capacity-compat-subscribe',
              queueLimit: 1,
            );
        expect(compatibilitySubscription.queueByteLimit, equals(2048));
        await expectLater(
          contender.subscribeWampTopicDirect(
            'app.events.audit',
            id: 'wamp-capacity-compat-blocks-direct',
            queueLimit: 1,
          ),
          throwsA(isA<McpStreamableWampToolException>()),
        );
        await compatibility.deleteSession();

        final recoveredPublic = await contender.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'wamp-capacity-after-session-delete',
          queueLimit: 1,
        );
        await contender.unsubscribeWampTopicDirect(
          recoveredPublic.handle,
          id: 'wamp-capacity-after-session-delete-release',
        );
      },
      skip: skipReason,
    );

    test(
      'authorizes each router-hosted MCP dynamic resource read once',
      () async {
        final provider = _FailDeferredAuthorizationProvider(
          action: AuthorizationAction.call,
          uri: 'app.safe.resource.read',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9161,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-read-single-authorization-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        var invocationCount = 0;
        final registration = await serviceSession.register(
          'app.safe.resource.read',
        );
        registration.onInvoke((invocation) {
          invocationCount++;
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'uri': invocation.arguments?.single,
              'invocation': invocationCount,
            },
          );
        });

        final listener = harness.binding.listeners.single;
        final client = McpStreamableHttpClient(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/public',
          ),
          clientInfo: const <String, Object?>{
            'name': 'router-resource-read-single-authorization',
            'version': '1.0.0',
          },
        );
        addTearDown(() => client.close(force: true));

        final requestsBeforeDirect = provider.matchingRequestCount;
        provider.failOnMatchingRequest(3);
        final directContents = await client.readResourceDirect(
          'app://mcp/live-context',
          id: 'resource-read-single-authorization-direct',
        );
        provider.clearPendingFailure();
        expect(provider.matchingRequestCount, equals(requestsBeforeDirect + 2));
        expect(invocationCount, equals(1));
        expect(
          jsonDecode(directContents.single['text'] as String),
          containsPair('argumentsKeywords', containsPair('invocation', 1)),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        await client.initialize(id: 'resource-read-single-authorization-init');
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final lastEventId = client.lastEventId;
        expect(sessionId, isNotNull);

        final requestsBeforeStreamable = provider.matchingRequestCount;
        provider.failOnMatchingRequest(3);
        final streamableContents = await client.readResource(
          'app://mcp/live-context',
          id: 'resource-read-single-authorization-streamable',
        );
        provider.clearPendingFailure();
        expect(
          provider.matchingRequestCount,
          equals(requestsBeforeStreamable + 2),
        );
        expect(invocationCount, equals(2));
        expect(
          jsonDecode(streamableContents.single['text'] as String),
          containsPair('argumentsKeywords', containsPair('invocation', 2)),
        );
        expect(client.sessionId, equals(sessionId));
        expect(client.lastEventId, isNotNull);
        expect(client.lastEventId, isNot(equals(lastEventId)));

        await client.deleteSession();
        expect(client.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'filters router-hosted MCP dynamic resource catalogs by call authorization',
      () async {
        final provider = _ToggleAuthorizationProvider(
          action: AuthorizationAction.call,
          uri: 'app.safe.resource.read',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9162,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-catalog-authorization-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        var invocationCount = 0;
        final registration = await serviceSession.register(
          'app.safe.resource.read',
        );
        registration.onInvoke((invocation) {
          invocationCount++;
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'uri': invocation.arguments?.single,
              'invocation': invocationCount,
            },
          );
        });

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final directClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-catalog-authorization-direct',
            'version': '1.0.0',
          },
        );
        addTearDown(() => directClient.close(force: true));

        final deniedDirectRequests = provider.matchingRequestCount;
        final deniedDirectResources = await directClient.listResources(
          id: 'resource-catalog-authorization-direct-denied-list',
          directJson: true,
        );
        expect(provider.matchingRequestCount, equals(deniedDirectRequests + 1));
        expect(
          deniedDirectResources.resources.map((resource) => resource['uri']),
          contains('app://mcp/context'),
        );
        expect(
          deniedDirectResources.resources.map((resource) => resource['uri']),
          isNot(contains('app://mcp/live-context')),
        );

        final deniedDirectReadRequests = provider.matchingRequestCount;
        await expectLater(
          directClient.readResource(
            'app://mcp/live-context',
            id: 'resource-catalog-authorization-direct-denied-read',
            directJson: true,
          ),
          throwsA(
            isA<McpJsonRpcException>().having(
              (error) => error.error['code'],
              'code',
              McpErrorCodes.resourceNotFound,
            ),
          ),
        );
        expect(
          provider.matchingRequestCount,
          equals(deniedDirectReadRequests + 1),
        );
        expect(invocationCount, isZero);

        final discovery = await directClient.discover(
          id: 'resource-catalog-authorization-discover',
        );
        expect(
          discovery.capabilities['resources'],
          containsPair('listChanged', true),
        );
        final modernSubscription = await directClient.listen(
          id: 'resource-catalog-authorization-listen',
          resourcesListChanged: true,
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        addTearDown(modernSubscription.close);
        expect(
          modernSubscription.acknowledgedNotifications.resourcesListChanged,
          isTrue,
        );
        expect(
          modernSubscription.acknowledgedNotifications.resourceSubscriptions,
          isEmpty,
        );
        final modernNotifications = StreamIterator<Map<String, Object?>>(
          modernSubscription.notifications,
        );
        final listChanged = modernNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );

        provider.allowed = true;
        final allowedDirectRequests = provider.matchingRequestCount;
        final allowedDirectResources = await directClient.listResources(
          id: 'resource-catalog-authorization-direct-allowed-list',
          directJson: true,
        );
        expect(
          provider.matchingRequestCount,
          equals(allowedDirectRequests + 1),
        );
        expect(
          allowedDirectResources.resources.map((resource) => resource['uri']),
          contains('app://mcp/live-context'),
        );
        expect(await listChanged, isTrue);
        expect(
          modernNotifications.current['method'],
          equals('notifications/resources/list_changed'),
        );

        final allowedDirectReadRequests = provider.matchingRequestCount;
        final directContents = await directClient.readResource(
          'app://mcp/live-context',
          id: 'resource-catalog-authorization-direct-allowed-read',
          directJson: true,
        );
        expect(
          provider.matchingRequestCount,
          equals(allowedDirectReadRequests + 2),
        );
        expect(
          jsonDecode(directContents.single['text'] as String),
          containsPair('argumentsKeywords', containsPair('invocation', 1)),
        );
        expect(directClient.sessionId, isNull);
        expect(directClient.lastEventId, isNull);
        await modernNotifications.cancel();
        await modernSubscription.close();

        provider.allowed = false;
        final streamableClient = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-catalog-authorization-streamable',
            'version': '1.0.0',
          },
        );
        addTearDown(() => streamableClient.close(force: true));
        final initialize = await streamableClient.initialize(
          id: 'resource-catalog-authorization-initialize',
        );
        final capabilities =
            ((initialize['result'] as Map)['capabilities'] as Map)
                .cast<String, Object?>();
        expect(capabilities['resources'], containsPair('listChanged', true));
        await streamableClient.notifyInitialized();
        final sessionId = streamableClient.sessionId;
        expect(sessionId, isNotNull);

        final deniedStreamableRequests = provider.matchingRequestCount;
        final deniedStreamableResources = await streamableClient.listResources(
          id: 'resource-catalog-authorization-streamable-denied-list',
        );
        expect(
          provider.matchingRequestCount,
          equals(deniedStreamableRequests + 1),
        );
        expect(
          deniedStreamableResources.resources.map(
            (resource) => resource['uri'],
          ),
          isNot(contains('app://mcp/live-context')),
        );
        await expectLater(
          streamableClient.subscribeResource(
            'app://mcp/live-context',
            id: 'resource-catalog-authorization-streamable-denied-subscribe',
          ),
          throwsA(
            isA<McpJsonRpcException>()
                .having(
                  (error) => error.method,
                  'method',
                  'resources/subscribe',
                )
                .having(
                  (error) => error.error['code'],
                  'code',
                  McpErrorCodes.resourceNotFound,
                ),
          ),
        );
        expect(streamableClient.sessionId, equals(sessionId));
        final cursorBeforeVisibilityChange = streamableClient.lastEventId;

        provider.allowed = true;
        final allowedStreamableRequests = provider.matchingRequestCount;
        final allowedStreamableResources = await streamableClient.listResources(
          id: 'resource-catalog-authorization-streamable-allowed-list',
        );
        expect(
          provider.matchingRequestCount,
          equals(allowedStreamableRequests + 1),
        );
        expect(
          allowedStreamableResources.resources.map(
            (resource) => resource['uri'],
          ),
          contains('app://mcp/live-context'),
        );
        expect(streamableClient.sessionId, equals(sessionId));
        expect(streamableClient.lastEventId, startsWith('$sessionId:'));
        expect(
          streamableClient.lastEventId,
          isNot(equals(cursorBeforeVisibilityChange)),
        );

        final allowedStreamableReadRequests = provider.matchingRequestCount;
        final streamableContents = await streamableClient.readResource(
          'app://mcp/live-context',
          id: 'resource-catalog-authorization-streamable-allowed-read',
        );
        expect(
          provider.matchingRequestCount,
          equals(allowedStreamableReadRequests + 2),
        );
        expect(
          jsonDecode(streamableContents.single['text'] as String),
          containsPair('argumentsKeywords', containsPair('invocation', 2)),
        );
        expect(streamableClient.sessionId, equals(sessionId));
        await streamableClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'revokes router-hosted MCP resource update owners when visibility is lost',
      () async {
        final provider = _ToggleAuthorizationProvider(
          action: AuthorizationAction.call,
          uri: 'app.safe.resource.read',
        )..allowed = true;
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9163,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-visibility-revocation-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final compatibilityClient = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-visibility-revocation-compatibility',
            'version': '1.0.0',
          },
        );
        final modernClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-visibility-revocation-modern',
            'version': '1.0.0',
          },
        );
        addTearDown(() => compatibilityClient.close(force: true));
        addTearDown(() => modernClient.close(force: true));

        await compatibilityClient.initialize(
          id: 'resource-visibility-revocation-initialize',
        );
        await compatibilityClient.notifyInitialized();
        final compatibilitySessionId = compatibilityClient.sessionId;
        expect(compatibilitySessionId, isNotNull);
        await compatibilityClient.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-visibility-revocation-compatibility-subscribe',
        );

        final modernSubscription = await modernClient.listen(
          id: 'resource-visibility-revocation-modern-listen',
          resourcesListChanged: true,
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        addTearDown(modernSubscription.close);
        expect(
          modernSubscription.acknowledgedNotifications.resourceSubscriptions,
          equals(const <String>['app://mcp/live-context']),
        );
        final modernNotifications = StreamIterator<Map<String, Object?>>(
          modernSubscription.notifications,
        );
        addTearDown(modernNotifications.cancel);

        final subscriptionLookup = await modernClient
            .lookupWampSubscriptionDirect(
              'app.events.resource.context',
              id: 'resource-visibility-revocation-subscription-lookup',
            );
        final subscriptionId = (subscriptionLookup.arguments.single as num)
            .toInt();
        Future<int> subscriberCount() async {
          final result = await modernClient
              .countWampSubscriptionSubscribersDirect(
                subscriptionId,
                id: 'resource-visibility-revocation-subscriber-count',
              );
          return (result.arguments.single as num).toInt();
        }

        expect(await subscriberCount(), equals(1));
        final revokedListChanged = modernNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );
        provider.allowed = false;
        final deniedModernResources = await modernClient.listResources(
          id: 'resource-visibility-revocation-modern-denied-list',
          directJson: true,
        );
        final deniedCompatibilityResources = await compatibilityClient
            .listResources(
              id: 'resource-visibility-revocation-compatibility-denied-list',
            );
        expect(
          deniedModernResources.resources.map((resource) => resource['uri']),
          isNot(contains('app://mcp/live-context')),
        );
        expect(
          deniedCompatibilityResources.resources.map(
            (resource) => resource['uri'],
          ),
          isNot(contains('app://mcp/live-context')),
        );
        expect(await revokedListChanged, isTrue);
        expect(
          modernNotifications.current['method'],
          equals('notifications/resources/list_changed'),
        );

        var subscribersAfterRevocation = 1;
        for (var attempt = 0; attempt < 50; attempt++) {
          subscribersAfterRevocation = await subscriberCount();
          if (subscribersAfterRevocation == 0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(subscribersAfterRevocation, isZero);

        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'via': 'resource-visibility-revocation',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final restoredListChanged = modernNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );
        provider.allowed = true;
        final restoredModernResources = await modernClient.listResources(
          id: 'resource-visibility-revocation-modern-restored-list',
          directJson: true,
        );
        expect(
          restoredModernResources.resources.map((resource) => resource['uri']),
          contains('app://mcp/live-context'),
        );
        expect(await restoredListChanged, isTrue);
        expect(
          modernNotifications.current['method'],
          equals('notifications/resources/list_changed'),
        );
        expect(await subscriberCount(), isZero);
        expect(compatibilityClient.sessionId, equals(compatibilitySessionId));

        await compatibilityClient.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-visibility-revocation-restored-subscribe',
        );
        final restoredSubscriptionLookup = await modernClient
            .lookupWampSubscriptionDirect(
              'app.events.resource.context',
              id: 'resource-visibility-revocation-restored-lookup',
            );
        final restoredSubscriptionId =
            (restoredSubscriptionLookup.arguments.single as num).toInt();
        final restoredSubscriberCount = await modernClient
            .countWampSubscriptionSubscribersDirect(
              restoredSubscriptionId,
              id: 'resource-visibility-revocation-restored-count',
            );
        expect(restoredSubscriberCount.arguments.single, equals(1));
        await compatibilityClient.unsubscribeResource(
          'app://mcp/live-context',
          id: 'resource-visibility-revocation-restored-unsubscribe',
        );
        final subscribersAfterExplicitUnsubscribe = await modernClient
            .countWampSubscriptionSubscribersDirect(
              restoredSubscriptionId,
              id: 'resource-visibility-revocation-final-count',
            );
        expect(subscribersAfterExplicitUnsubscribe.arguments.single, isZero);
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        await modernNotifications.cancel();
        await modernSubscription.close();
        await compatibilityClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'revokes pending MCP resource owners before stale authorization completes',
      () async {
        final provider = _BlockingSnapshotAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.resource.context',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9165,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-pending-revocation-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);
        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final modernClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-pending-revocation-modern',
            'version': '1.0.0',
          },
        );
        addTearDown(() => modernClient.close(force: true));

        await modernClient.listWampApiDirect(
          id: 'resource-pending-revocation-prime-catalog',
        );
        Future<List<int>> subscriptionIds() async {
          final result = await modernClient.lookupWampSubscriptionDirect(
            'app.events.resource.context',
            id: 'resource-pending-revocation-subscription-lookup',
          );
          return <int>[for (final id in result.arguments) (id as num).toInt()];
        }

        expect(await subscriptionIds(), isEmpty);
        final authorizationEntered = Completer<void>();
        final releaseAuthorization = Completer<void>();
        provider.blockNextDecision(
          entered: authorizationEntered,
          release: releaseAuthorization,
        );
        final staleListen = modernClient.listen(
          id: 'resource-pending-revocation-stale-listen',
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        await authorizationEntered.future.timeout(const Duration(seconds: 5));

        provider.allowed = false;
        final markerRegistration = await serviceSession.register(
          'app.safe.resource_pending_revocation_marker',
        );
        addTearDown(
          () => serviceSession.unregister(markerRegistration.registrationId),
        );
        expect(
          jsonEncode(
            await modernClient
                .listWampApiDirect(
                  id: 'resource-pending-revocation-refresh-catalog',
                )
                .timeout(const Duration(seconds: 5)),
          ),
          contains('app.safe.resource_pending_revocation_marker'),
        );
        releaseAuthorization.complete();

        final staleSubscription = await staleListen;
        addTearDown(staleSubscription.close);
        expect(
          staleSubscription.acknowledgedNotifications.resourceSubscriptions,
          isEmpty,
        );
        expect(await subscriptionIds(), isEmpty);
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        provider.allowed = true;
        final compatibilityClient = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-pending-revocation-compatibility',
            'version': '1.0.0',
          },
        );
        addTearDown(() => compatibilityClient.close(force: true));
        await compatibilityClient.initialize(
          id: 'resource-pending-revocation-compatibility-initialize',
        );
        await compatibilityClient.notifyInitialized();
        final compatibilitySessionId = compatibilityClient.sessionId;
        expect(compatibilitySessionId, isNotNull);

        Future<List<int>> compatibilitySubscriptionIds() async {
          final result = await compatibilityClient.lookupWampSubscription(
            'app.events.resource.context',
            id: 'resource-pending-revocation-compatibility-lookup',
          );
          return <int>[for (final id in result.arguments) (id as num).toInt()];
        }

        final compatibilityAuthorizationEntered = Completer<void>();
        final releaseCompatibilityAuthorization = Completer<void>();
        provider.blockNextDecision(
          entered: compatibilityAuthorizationEntered,
          release: releaseCompatibilityAuthorization,
        );
        final staleCompatibilitySubscribe = compatibilityClient
            .subscribeResource(
              'app://mcp/live-context',
              id: 'resource-pending-revocation-stale-compatibility-subscribe',
            );
        await compatibilityAuthorizationEntered.future.timeout(
          const Duration(seconds: 5),
        );

        provider.allowed = false;
        final compatibilityMarkerRegistration = await serviceSession.register(
          'app.safe.resource_pending_compatibility_revocation_marker',
        );
        addTearDown(
          () => serviceSession.unregister(
            compatibilityMarkerRegistration.registrationId,
          ),
        );
        expect(
          jsonEncode(
            await compatibilityClient.listWampApi(
              id: 'resource-pending-revocation-compatibility-refresh',
            ),
          ),
          contains('app.safe.resource_pending_compatibility_revocation_marker'),
        );
        releaseCompatibilityAuthorization.complete();
        await expectLater(
          staleCompatibilitySubscribe,
          throwsA(
            isA<McpJsonRpcException>()
                .having(
                  (error) => error.method,
                  'method',
                  'resources/subscribe',
                )
                .having(
                  (error) => error.error['code'],
                  'code',
                  McpErrorCodes.invalidRequest,
                ),
          ),
        );
        expect(await compatibilitySubscriptionIds(), isEmpty);
        expect(compatibilityClient.sessionId, equals(compatibilitySessionId));

        provider.allowed = true;
        await compatibilityClient.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-pending-revocation-compatibility-replacement',
        );
        expect(await compatibilitySubscriptionIds(), hasLength(1));
        await compatibilityClient.unsubscribeResource(
          'app://mcp/live-context',
          id: 'resource-pending-revocation-compatibility-unsubscribe',
        );
        expect(await compatibilitySubscriptionIds(), isEmpty);

        final replacementSubscription = await modernClient.listen(
          id: 'resource-pending-revocation-replacement-listen',
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        addTearDown(replacementSubscription.close);
        expect(
          replacementSubscription
              .acknowledgedNotifications
              .resourceSubscriptions,
          equals(const <String>['app://mcp/live-context']),
        );
        final replacementSubscriptionIds = await subscriptionIds();
        expect(replacementSubscriptionIds, hasLength(1));
        final replacementSubscriberCount = await modernClient
            .countWampSubscriptionSubscribersDirect(
              replacementSubscriptionIds.single,
              id: 'resource-pending-revocation-replacement-count',
            );
        expect(replacementSubscriberCount.arguments.single, equals(1));
        await replacementSubscription.close();
        await staleSubscription.close();
      },
      skip: skipReason,
    );

    test(
      'revokes router-hosted MCP resource owners when subscribe access is lost',
      () async {
        final provider = _ToggleAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.resource.context',
        )..allowed = true;
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9164,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-subscribe-revocation-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final compatibilityClient = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-subscribe-revocation-compatibility',
            'version': '1.0.0',
          },
        );
        final modernClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-subscribe-revocation-modern',
            'version': '1.0.0',
          },
        );
        addTearDown(() => compatibilityClient.close(force: true));
        addTearDown(() => modernClient.close(force: true));

        await compatibilityClient.initialize(
          id: 'resource-subscribe-revocation-initialize',
        );
        await compatibilityClient.notifyInitialized();
        final compatibilitySessionId = compatibilityClient.sessionId;
        expect(compatibilitySessionId, isNotNull);
        await compatibilityClient.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-subscribe-revocation-compatibility-subscribe',
        );

        final modernSubscription = await modernClient.listen(
          id: 'resource-subscribe-revocation-modern-listen',
          toolsListChanged: true,
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        addTearDown(modernSubscription.close);
        expect(
          modernSubscription.acknowledgedNotifications.resourceSubscriptions,
          equals(const <String>['app://mcp/live-context']),
        );
        final modernNotifications = StreamIterator<Map<String, Object?>>(
          modernSubscription.notifications,
        );
        addTearDown(modernNotifications.cancel);

        final subscriptionLookup = await modernClient
            .lookupWampSubscriptionDirect(
              'app.events.resource.context',
              id: 'resource-subscribe-revocation-subscription-lookup',
            );
        final subscriptionId = (subscriptionLookup.arguments.single as num)
            .toInt();
        Future<int> subscriberCount() async {
          final result = await modernClient
              .countWampSubscriptionSubscribersDirect(
                subscriptionId,
                id: 'resource-subscribe-revocation-subscriber-count',
              );
          return (result.arguments.single as num).toInt();
        }

        expect(await subscriberCount(), equals(1));
        provider.allowed = false;
        final deniedModernResources = await modernClient.listResources(
          id: 'resource-subscribe-revocation-modern-list',
          directJson: true,
        );
        final deniedCompatibilityResources = await compatibilityClient
            .listResources(
              id: 'resource-subscribe-revocation-compatibility-list',
            );
        expect(
          deniedModernResources.resources.map((resource) => resource['uri']),
          contains('app://mcp/live-context'),
        );
        expect(
          deniedCompatibilityResources.resources.map(
            (resource) => resource['uri'],
          ),
          contains('app://mcp/live-context'),
        );
        var subscribersAfterRevocation = 1;
        for (var attempt = 0; attempt < 50; attempt++) {
          subscribersAfterRevocation = await subscriberCount();
          if (subscribersAfterRevocation == 0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(subscribersAfterRevocation, isZero);

        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'via': 'resource-subscribe-revocation',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final catalogMarker = modernNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );
        final markerRegistration = await serviceSession.register(
          'app.safe.resource_subscribe_revocation_marker',
        );
        addTearDown(
          () => serviceSession.unregister(markerRegistration.registrationId),
        );
        expect(
          jsonEncode(
            await modernClient.listWampApiDirect(
              id: 'resource-subscribe-revocation-catalog-marker',
            ),
          ),
          contains('app.safe.resource_subscribe_revocation_marker'),
        );
        expect(await catalogMarker, isTrue);
        expect(
          modernNotifications.current['method'],
          equals('notifications/tools/list_changed'),
        );

        provider.allowed = true;
        final restoredResources = await modernClient.listResources(
          id: 'resource-subscribe-revocation-restored-list',
          directJson: true,
        );
        expect(
          restoredResources.resources.map((resource) => resource['uri']),
          contains('app://mcp/live-context'),
        );
        expect(await subscriberCount(), isZero);
        expect(compatibilityClient.sessionId, equals(compatibilitySessionId));

        await compatibilityClient.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-subscribe-revocation-restored-subscribe',
        );
        final restoredSubscriptionLookup = await modernClient
            .lookupWampSubscriptionDirect(
              'app.events.resource.context',
              id: 'resource-subscribe-revocation-restored-lookup',
            );
        final restoredSubscriptionId =
            (restoredSubscriptionLookup.arguments.single as num).toInt();
        final restoredSubscriberCount = await modernClient
            .countWampSubscriptionSubscribersDirect(
              restoredSubscriptionId,
              id: 'resource-subscribe-revocation-restored-count',
            );
        expect(restoredSubscriberCount.arguments.single, equals(1));
        await compatibilityClient.unsubscribeResource(
          'app://mcp/live-context',
          id: 'resource-subscribe-revocation-restored-unsubscribe',
        );
        final finalSubscriberCount = await modernClient
            .countWampSubscriptionSubscribersDirect(
              restoredSubscriptionId,
              id: 'resource-subscribe-revocation-final-count',
            );
        expect(finalSubscriberCount.arguments.single, isZero);
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        await modernNotifications.cancel();
        await modernSubscription.close();
        await compatibilityClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'authorizes each router-hosted MCP resource subscribe owner once',
      () async {
        final provider = _FailDeferredAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.resource.context',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9160,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-single-authorization-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final compatibilityClient = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-single-authorization-compatibility',
            'version': '1.0.0',
          },
        );
        final modernClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-single-authorization-modern',
            'version': '1.0.0',
          },
        );
        addTearDown(() => compatibilityClient.close(force: true));
        addTearDown(() => modernClient.close(force: true));

        await compatibilityClient.initialize(
          id: 'resource-single-authorization-initialize',
        );
        await compatibilityClient.notifyInitialized();
        final compatibilitySessionId = compatibilityClient.sessionId;
        expect(compatibilitySessionId, isNotNull);

        provider.failOnMatchingRequest(2);
        await compatibilityClient.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-single-authorization-compatibility-subscribe',
        );
        expect(provider.matchingRequestCount, equals(1));
        provider.clearPendingFailure();
        expect(compatibilityClient.sessionId, equals(compatibilitySessionId));

        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'via': 'resource-single-authorization-compatibility',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final compatibilityUpdate = await _pollStreamableMcpUntilResourceUpdate(
          compatibilityClient,
          'app://mcp/live-context',
        );
        expect(
          compatibilityUpdate['method'],
          equals('notifications/resources/updated'),
        );
        expect(compatibilityClient.sessionId, equals(compatibilitySessionId));

        await compatibilityClient.unsubscribeResource(
          'app://mcp/live-context',
          id: 'resource-single-authorization-compatibility-unsubscribe',
        );

        final requestsBeforeModern = provider.matchingRequestCount;
        provider.failOnMatchingRequest(2);
        final modernSubscription = await modernClient.listen(
          id: 'resource-single-authorization-modern-listen',
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        addTearDown(modernSubscription.close);
        provider.clearPendingFailure();
        expect(
          modernSubscription.acknowledgedNotifications.resourceSubscriptions,
          equals(const <String>['app://mcp/live-context']),
        );
        expect(provider.matchingRequestCount, equals(requestsBeforeModern + 1));
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        final modernNotifications = StreamIterator<Map<String, Object?>>(
          modernSubscription.notifications,
        );
        addTearDown(modernNotifications.cancel);
        final modernUpdateFuture = modernNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );
        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'via': 'resource-single-authorization-modern',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        expect(await modernUpdateFuture, isTrue);
        expect(
          modernNotifications.current['method'],
          equals('notifications/resources/updated'),
        );
        expect(
          (modernNotifications.current['params']
              as Map<String, Object?>)['uri'],
          equals('app://mcp/live-context'),
        );
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        await compatibilityClient.deleteSession();
        expect(compatibilityClient.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'redacts router-hosted MCP WAMP unsubscribe failures and preserves retry state',
      () async {
        final provider = _FailDeferredAuthorizationProvider(
          action: AuthorizationAction.unsubscribe,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9158,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxWampSubscriptionCount: 1),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-wamp-unsubscribe-failure-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final primary = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-unsubscribe-failure-primary',
            'version': '1.0.0',
          },
        );
        final contender = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-wamp-unsubscribe-failure-contender',
            'version': '1.0.0',
          },
        );
        addTearDown(() => primary.close(force: true));
        addTearDown(() => contender.close(force: true));

        final subscription = await primary.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'wamp-unsubscribe-failure-subscribe',
          queueLimit: 2,
        );
        provider.failOnMatchingRequest(1);

        await expectLater(
          primary.unsubscribeWampTopicDirect(
            subscription.handle,
            id: 'wamp-unsubscribe-failure-first-attempt',
          ),
          throwsA(
            isA<McpStreamableWampToolException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('MCP authorization check failed'),
                isNot(contains('authorization backend detail')),
              ),
            ),
          ),
        );

        final failureEvent = await harness
            .nextEvent('mcp_authorization_error')
            .timeout(const Duration(seconds: 2));
        expect(failureEvent['realm'], equals('realm1'));
        expect(failureEvent['action'], equals('unsubscribe'));
        expect(failureEvent['errorType'], equals('StateError'));
        expect(failureEvent, isNot(contains('error')));
        expect(failureEvent, isNot(contains('stackTrace')));
        expect(
          jsonEncode(failureEvent),
          isNot(contains('authorization backend detail')),
        );
        expect(primary.sessionId, isNull);
        expect(primary.lastEventId, isNull);

        await serviceSession.publish(
          'app.events.audit',
          argumentsKeywords: const <String, Object?>{
            'via': 'unsubscribe-retry-continuity',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final retainedEvents = await primary.pollWampEventsDirect(
          subscription.handle,
          id: 'wamp-unsubscribe-failure-poll',
        );
        expect(
          retainedEvents.events,
          contains(
            isA<Map<String, Object?>>().having(
              (event) => event['argumentsKeywords'],
              'argumentsKeywords',
              containsPair('via', 'unsubscribe-retry-continuity'),
            ),
          ),
        );

        await expectLater(
          contender.subscribeWampTopicDirect(
            'app.events.audit',
            id: 'wamp-unsubscribe-failure-capacity-retained',
            queueLimit: 1,
          ),
          throwsA(
            isA<McpStreamableWampToolException>().having(
              (error) => error.message,
              'message',
              contains('WAMP subscription capacity is exhausted'),
            ),
          ),
        );

        final retriedUnsubscribe = await primary.unsubscribeWampTopicDirect(
          subscription.handle,
          id: 'wamp-unsubscribe-failure-retry',
        );
        expect(retriedUnsubscribe.unsubscribed, isTrue);

        final recovered = await contender.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'wamp-unsubscribe-failure-recovered',
          queueLimit: 1,
        );
        await contender.unsubscribeWampTopicDirect(
          recovered.handle,
          id: 'wamp-unsubscribe-failure-recovered-release',
        );
        expect(contender.sessionId, isNull);
        expect(contender.lastEventId, isNull);
      },
      skip: skipReason,
    );

    test(
      'redacts router-hosted MCP resource unsubscribe failures and preserves retry state',
      () async {
        final provider = _FailDeferredAuthorizationProvider(
          action: AuthorizationAction.unsubscribe,
          uri: 'app.events.resource.context',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9159,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxWampSubscriptionCount: 1),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-unsubscribe-failure-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final primary = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-unsubscribe-failure-primary',
            'version': '1.0.0',
          },
        );
        final contender = McpStreamableHttpClient(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-unsubscribe-failure-contender',
            'version': '1.0.0',
          },
        );
        addTearDown(() => primary.close(force: true));
        addTearDown(() => contender.close(force: true));

        await primary.initialize(id: 'resource-unsubscribe-failure-initialize');
        await primary.notifyInitialized();
        await contender.initialize(
          id: 'resource-unsubscribe-failure-contender-initialize',
        );
        await contender.notifyInitialized();
        await primary.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-unsubscribe-failure-subscribe',
        );
        final sessionId = primary.sessionId;
        final cursorBeforeFailure = primary.lastEventId;
        expect(sessionId, isNotNull);
        expect(cursorBeforeFailure, isNotNull);
        provider.failOnMatchingRequest(1);

        await expectLater(
          primary.unsubscribeResource(
            'app://mcp/live-context',
            id: 'resource-unsubscribe-failure-first-attempt',
          ),
          throwsA(
            isA<McpJsonRpcException>()
                .having(
                  (error) => error.method,
                  'method',
                  'resources/unsubscribe',
                )
                .having(
                  (error) => error.error['message'],
                  'message',
                  allOf(
                    contains('MCP authorization check failed'),
                    isNot(contains('authorization backend detail')),
                  ),
                ),
          ),
        );

        final failureEvent = await harness
            .nextEvent('mcp_authorization_error')
            .timeout(const Duration(seconds: 2));
        expect(failureEvent['realm'], equals('realm1'));
        expect(failureEvent['action'], equals('unsubscribe'));
        expect(failureEvent['errorType'], equals('StateError'));
        expect(failureEvent, isNot(contains('error')));
        expect(failureEvent, isNot(contains('stackTrace')));
        expect(
          jsonEncode(failureEvent),
          isNot(contains('authorization backend detail')),
        );
        expect(primary.sessionId, equals(sessionId));
        final cursorAfterFailure = primary.lastEventId;
        expect(cursorAfterFailure, startsWith('$sessionId:'));
        expect(cursorAfterFailure, isNot(equals(cursorBeforeFailure)));

        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'via': 'resource-unsubscribe-retry-continuity',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final retainedUpdate = await _pollStreamableMcpUntilResourceUpdate(
          primary,
          'app://mcp/live-context',
        );
        expect(
          retainedUpdate['method'],
          equals('notifications/resources/updated'),
        );
        expect(primary.sessionId, equals(sessionId));

        await expectLater(
          contender.subscribeResource(
            'app://mcp/live-context',
            id: 'resource-unsubscribe-failure-capacity-retained',
          ),
          throwsA(
            isA<McpJsonRpcException>().having(
              (error) => error.error['message'],
              'message',
              contains('WAMP subscription capacity is exhausted'),
            ),
          ),
        );

        await primary.unsubscribeResource(
          'app://mcp/live-context',
          id: 'resource-unsubscribe-failure-retry',
        );
        await contender.subscribeResource(
          'app://mcp/live-context',
          id: 'resource-unsubscribe-failure-recovered',
        );
        await contender.unsubscribeResource(
          'app://mcp/live-context',
          id: 'resource-unsubscribe-failure-recovered-release',
        );
        await primary.deleteSession();
        await contender.deleteSession();
        expect(primary.sessionId, isNull);
        expect(contender.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'bounds router-hosted MCP request bodies without poisoning auth or session state',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9139,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxRequestBytes: 1024),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final publicEndpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final secureEndpoint = publicEndpoint.replace(path: '/mcp/secure');
        final padding = List<String>.filled(600, 'é').join();
        final oversizedModernRequest = <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'public-modern-oversized',
          'method': 'ping',
          'params': <String, Object?>{'padding': padding},
        };
        final encodedOversizedModernRequest = jsonEncode(
          oversizedModernRequest,
        );
        expect(encodedOversizedModernRequest.length, lessThan(1024));
        expect(
          utf8.encode(encodedOversizedModernRequest).length,
          greaterThan(1024),
        );

        final publicClient = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-request-bound-test',
            'version': '1.0.0',
          },
          maxRequestBytes: 4096,
        );
        addTearDown(() => publicClient.close(force: true));
        await expectLater(
          publicClient.postDirect(oversizedModernRequest),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.requestEntityTooLarge,
                )
                .having(
                  (error) => error.body,
                  'body',
                  contains('exceeds the configured limit'),
                ),
          ),
        );
        expect(publicClient.sessionId, isNull);
        expect(publicClient.lastEventId, isNull);
        expect(
          await publicClient.pingDirect(id: 'public-modern-after-oversized'),
          containsPair('resultType', 'complete'),
        );

        final unauthenticatedClient = McpStreamableHttpClient.stateless(
          secureEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-request-bound-test',
            'version': '1.0.0',
          },
          maxRequestBytes: 4096,
        );
        addTearDown(() => unauthenticatedClient.close(force: true));
        await expectLater(
          unauthenticatedClient.postDirect(<String, Object?>{
            ...oversizedModernRequest,
            'id': 'secure-missing-bearer-oversized',
          }),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );

        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final grant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final protectedClient = McpStreamableHttpClient.withAuthGrant(
          secureEndpoint,
          grant,
          maxRequestBytes: 4096,
        );
        addTearDown(() => protectedClient.close(force: true));

        await protectedClient.initialize(id: 'secure-bounds-initialize');
        await protectedClient.notifyInitialized();
        final sessionId = protectedClient.sessionId;
        expect(sessionId, isNotNull);

        await expectLater(
          protectedClient.post(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 'secure-compatibility-oversized',
            'method': 'ping',
            'params': <String, Object?>{'padding': padding},
          }),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.requestEntityTooLarge,
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(protectedClient.sessionId, equals(sessionId));

        await expectLater(
          protectedClient.postDirect(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 'secure-modern-oversized',
            'method': 'ping',
            'params': <String, Object?>{'padding': padding},
          }, protocolVersion: McpStreamableHttpClient.latestProtocolVersion),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.requestEntityTooLarge,
            ),
          ),
        );
        expect(protectedClient.sessionId, equals(sessionId));
        final tools = await protectedClient.listTools(
          id: 'secure-compatibility-after-oversized',
        );
        expect(
          tools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        await protectedClient.deleteSession();
        expect(protectedClient.sessionId, isNull);

        final oversizedAfterDelete = await _postBody(
          authHttpClient,
          listener.port,
          '/mcp/secure',
          encodedOversizedModernRequest,
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': sessionId!,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            'Mcp-Method': 'ping',
          },
        );
        expect(oversizedAfterDelete.statusCode, equals(HttpStatus.notFound));
        expect(oversizedAfterDelete.headers, isNot(contains('mcp-session-id')));
        expect(oversizedAfterDelete.body, contains('Unknown MCP HTTP session'));
        expect(
          oversizedAfterDelete.body,
          isNot(contains('exceeds the configured limit')),
        );
      },
      skip: skipReason,
    );

    test(
      'keeps the public MCP session alive while a tool call is in flight',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9137,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(sessionIdleTimeoutMs: 300),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-slow-tool-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final invocationsStarted = Completer<void>();
        var invocationCount = 0;
        final registration = await serviceSession.register(
          'app.safe.slow_lookup',
          options: core.RegisterOptions(
            custom: const <String, Object?>{
              '_ai_meta_data': <String, Object?>{
                'short_description': 'Complete a delayed lookup',
                'description': 'Returns after a bounded application delay.',
                'read_only_hint': true,
                'destructive_hint': false,
                'idempotent_hint': true,
                'open_world_hint': false,
              },
            },
          ),
        );
        registration.onInvoke((invocation) async {
          invocationCount++;
          if (invocationCount == 2 && !invocationsStarted.isCompleted) {
            invocationsStarted.complete();
          }
          final delayMs = invocation.argumentsKeywords?['delayMs'] as int;
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'status': 'complete',
              'delayMs': delayMs,
            },
          );
        });

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'in-flight-idle-initialize');
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);

        final firstToolCall = client.callTool(
          'app.safe.slow_lookup',
          id: 'in-flight-idle-first-tool',
          arguments: const <String, Object?>{'delayMs': 700},
        );
        final secondToolCall = client.callTool(
          'app.safe.slow_lookup',
          id: 'in-flight-idle-second-tool',
          arguments: const <String, Object?>{'delayMs': 1200},
        );
        await invocationsStarted.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final firstToolResult = await firstToolCall.timeout(
          const Duration(seconds: 2),
        );
        expect(firstToolResult['isError'], isFalse);
        expect(
          (firstToolResult['structuredContent'] as Map)['argumentsKeywords'],
          containsPair('delayMs', 700),
        );
        expect(client.sessionId, equals(sessionId));

        final toolsWhileSecondCallActive = await client.listTools(
          id: 'in-flight-idle-concurrent-tools',
        );
        expect(
          toolsWhileSecondCallActive.tools.map((tool) => tool['name']),
          contains('app.safe.slow_lookup'),
        );

        final secondToolResult = await secondToolCall.timeout(
          const Duration(seconds: 2),
        );
        expect(secondToolResult['isError'], isFalse);
        expect(
          (secondToolResult['structuredContent'] as Map)['argumentsKeywords'],
          containsPair('delayMs', 1200),
        );
        expect(client.sessionId, equals(sessionId));

        final activeTools = await client.listTools(
          id: 'in-flight-idle-active-tools',
        );
        expect(
          activeTools.tools.map((tool) => tool['name']),
          contains('app.safe.slow_lookup'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 500));
        await expectLater(
          client.listTools(id: 'in-flight-idle-expired-tools'),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        expect(client.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'bounds router-hosted MCP responses without poisoning auth or session state',
      () async {
        const responseLimit = 4096;
        final harness = await _RouterHarness.start(
          connectionId: 9143,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(maxResponseBytes: responseLimit),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-response-bound-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        var invocationCount = 0;
        final padding = List<String>.filled(1100, 'é').join();
        const wireBoundRequestId = 'secure-compatibility-sse-wire-bound';
        final wireBoundPadding = List<String>.filled(1914, 'x').join();
        final registration = await serviceSession.register(
          'app.safe.response_bound_lookup',
          options: core.RegisterOptions(
            custom: const <String, Object?>{
              '_ai_meta_data': <String, Object?>{
                'short_description': 'Return bounded response content',
                'read_only_hint': true,
                'destructive_hint': false,
                'idempotent_hint': true,
                'open_world_hint': false,
              },
            },
          ),
        );
        registration.onInvoke((invocation) {
          invocationCount++;
          final useWireBoundPadding =
              invocation.argumentsKeywords?['wireBound'] == true;
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'status': 'complete',
              if (invocation.argumentsKeywords?['small'] != true)
                'padding': useWireBoundPadding ? wireBoundPadding : padding,
            },
          );
        });

        final structuredContent = <String, Object?>{
          'argumentsKeywords': <String, Object?>{
            'status': 'complete',
            'padding': padding,
          },
        };
        final representativeCompatibilityResponse = jsonEncode(
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'bounded-response-shape',
            'result': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': jsonEncode(structuredContent),
                },
              ],
              'isError': false,
              'structuredContent': structuredContent,
            },
          },
        );
        expect(
          representativeCompatibilityResponse.length,
          lessThan(responseLimit),
        );
        expect(
          utf8.encode(representativeCompatibilityResponse).length,
          greaterThan(responseLimit),
        );
        final wireBoundStructuredContent = <String, Object?>{
          'argumentsKeywords': <String, Object?>{
            'status': 'complete',
            'padding': wireBoundPadding,
          },
        };
        final representativeWireBoundResponse = jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': wireBoundRequestId,
          'result': <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(wireBoundStructuredContent),
              },
            ],
            'isError': false,
            'structuredContent': wireBoundStructuredContent,
          },
        });
        expect(
          utf8.encode(representativeWireBoundResponse).length,
          equals(responseLimit),
        );

        final listener = harness.binding.listeners.single;
        final publicEndpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final secureEndpoint = publicEndpoint.replace(path: '/mcp/secure');
        final publicClient = McpStreamableHttpClient.stateless(
          publicEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-response-bound-test',
            'version': '1.0.0',
          },
          maxResponseBytes: 8192,
        );
        addTearDown(() => publicClient.close(force: true));

        await expectLater(
          publicClient.callToolDirect(
            'app.safe.response_bound_lookup',
            id: 'public-modern-oversized-response',
          ),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  contains('response body exceeds the configured limit'),
                ),
          ),
        );
        expect(publicClient.sessionId, isNull);
        expect(publicClient.lastEventId, isNull);
        final publicRecovery = await publicClient.callToolDirect(
          'app.safe.response_bound_lookup',
          id: 'public-modern-response-recovery',
          arguments: const <String, Object?>{'small': true},
        );
        expect(publicRecovery['isError'], isFalse);

        final unauthenticatedClient = McpStreamableHttpClient.stateless(
          secureEndpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-response-bound-test',
            'version': '1.0.0',
          },
          maxResponseBytes: 8192,
        );
        addTearDown(() => unauthenticatedClient.close(force: true));
        await expectLater(
          unauthenticatedClient.callToolDirect(
            'app.safe.response_bound_lookup',
            id: 'secure-missing-bearer-oversized-response',
          ),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );
        expect(invocationCount, 2);

        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final grant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final protectedClient = McpStreamableHttpClient.withAuthGrant(
          secureEndpoint,
          grant,
          maxResponseBytes: 8192,
        );
        addTearDown(() => protectedClient.close(force: true));

        await protectedClient.initialize(id: 'secure-response-initialize');
        await protectedClient.notifyInitialized();
        final sessionId = protectedClient.sessionId;
        expect(sessionId, isNotNull);

        await expectLater(
          protectedClient.callTool(
            'app.safe.response_bound_lookup',
            id: wireBoundRequestId,
            arguments: const <String, Object?>{'wireBound': true},
          ),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  contains('response body exceeds the configured limit'),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(protectedClient.sessionId, equals(sessionId));
        expect(protectedClient.lastEventId, isNull);

        final rawClient = HttpClient();
        addTearDown(() => rawClient.close(force: true));
        final wireBoundRecovery = await _postJson(
          rawClient,
          listener.port,
          '/mcp/secure',
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'secure-compatibility-wire-recovery',
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'app.safe.response_bound_lookup',
              'arguments': const <String, Object?>{'small': true},
            },
          },
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': sessionId!,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
          },
        );
        expect(wireBoundRecovery.statusCode, equals(HttpStatus.ok));
        expect(
          utf8.encode(wireBoundRecovery.body).length,
          lessThanOrEqualTo(responseLimit),
        );
        final wireBoundRecoveryEventIds = _sseEventIds(wireBoundRecovery.body);
        expect(wireBoundRecoveryEventIds, hasLength(2));

        final wireBoundReplay = await _getHttp(
          rawClient,
          listener.port,
          '/mcp/secure',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': sessionId,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            'Last-Event-ID': wireBoundRecoveryEventIds.first,
          },
        );
        expect(wireBoundReplay.statusCode, equals(HttpStatus.ok));
        expect(wireBoundReplay.body, contains(wireBoundRecoveryEventIds.last));
        expect(
          wireBoundReplay.body,
          contains('secure-compatibility-wire-recovery'),
        );
        expect(protectedClient.sessionId, equals(sessionId));
        expect(protectedClient.lastEventId, isNull);

        final wireBoundDirectRecovery = await protectedClient.callToolDirect(
          'app.safe.response_bound_lookup',
          id: 'secure-wire-bound-direct-recovery',
          arguments: const <String, Object?>{'small': true},
        );
        expect(wireBoundDirectRecovery['isError'], isFalse);
        expect(protectedClient.sessionId, equals(sessionId));
        expect(protectedClient.lastEventId, isNull);

        await expectLater(
          protectedClient.callTool(
            'app.safe.response_bound_lookup',
            id: 'secure-compatibility-oversized-response',
          ),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(protectedClient.sessionId, equals(sessionId));

        await expectLater(
          protectedClient.callToolDirect(
            'app.safe.response_bound_lookup',
            id: 'secure-modern-oversized-response',
          ),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.internalServerError,
            ),
          ),
        );
        expect(protectedClient.sessionId, equals(sessionId));
        expect(protectedClient.lastEventId, isNull);

        final recovered = await protectedClient.callTool(
          'app.safe.response_bound_lookup',
          id: 'secure-response-recovery',
          arguments: const <String, Object?>{'small': true},
        );
        expect(recovered['isError'], isFalse);
        expect(protectedClient.sessionId, equals(sessionId));
        await protectedClient.deleteSession();
        expect(protectedClient.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'bounds router-hosted MCP SSE replay history bytes and keeps the endpoint reusable',
      () async {
        const responseLimit = 4096;
        final harness = await _RouterHarness.start(
          connectionId: 9146,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(
            maxResponseBytes: responseLimit,
            maxSseHistoryBytes: responseLimit,
          ),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-sse-history-bound-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final padding = List<String>.filled(1200, 'x').join();
        final registration = await serviceSession.register(
          'app.safe.sse_history_bound_lookup',
          options: core.RegisterOptions(
            custom: const <String, Object?>{
              '_ai_meta_data': <String, Object?>{
                'short_description': 'Return replay-history test content',
                'read_only_hint': true,
                'destructive_hint': false,
                'idempotent_hint': true,
                'open_world_hint': false,
              },
            },
          ),
        );
        registration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'status': 'complete',
              'padding': padding,
            },
          );
        });

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/secure',
        );
        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final grant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final client = McpStreamableHttpClient.withAuthGrant(
          endpoint,
          grant,
          maxResponseBytes: 8192,
        );
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'sse-history-bound-initialize');
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);
        final activeSessionId = sessionId!;

        final rawClient = HttpClient();
        addTearDown(() => rawClient.close(force: true));
        final responseEventIds = <List<String>>[];
        var retainedCandidateBytes = 0;
        for (var index = 0; index < 4; index++) {
          final response = await _postJson(
            rawClient,
            listener.port,
            '/mcp/secure',
            <String, Object?>{
              'jsonrpc': '2.0',
              'id': 'sse-history-bound-call-$index',
              'method': 'tools/call',
              'params': <String, Object?>{
                'name': 'app.safe.sse_history_bound_lookup',
                'arguments': const <String, Object?>{},
              },
            },
            headers: <String, String>{
              HttpHeaders.acceptHeader: 'application/json, text/event-stream',
              HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
              'MCP-Session-Id': activeSessionId,
              'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            },
          );
          expect(response.statusCode, equals(HttpStatus.ok));
          expect(
            utf8.encode(response.body).length,
            lessThanOrEqualTo(responseLimit),
          );
          final eventIds = _sseEventIds(response.body);
          expect(eventIds, hasLength(2));
          responseEventIds.add(eventIds);
          retainedCandidateBytes += utf8.encode(response.body).length;
        }
        expect(responseEventIds.length * 2, lessThan(128));
        expect(retainedCandidateBytes, greaterThan(responseLimit));

        final evictedCursor = await _getHttp(
          rawClient,
          listener.port,
          '/mcp/secure',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': activeSessionId,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            'Last-Event-ID': responseEventIds.first.first,
          },
        );
        expect(evictedCursor.statusCode, equals(HttpStatus.badRequest));
        expect(evictedCursor.body, contains('Last-Event-ID'));

        final newestReplay = await _getHttp(
          rawClient,
          listener.port,
          '/mcp/secure',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': activeSessionId,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            'Last-Event-ID': responseEventIds.last.first,
          },
        );
        expect(newestReplay.statusCode, equals(HttpStatus.ok));
        expect(newestReplay.body, contains(responseEventIds.last.last));
        expect(newestReplay.body, contains('sse-history-bound-call-3'));
        expect(client.sessionId, equals(activeSessionId));

        final directRecovery = await client.callToolDirect(
          'app.safe.sse_history_bound_lookup',
          id: 'sse-history-bound-direct-recovery',
        );
        expect(directRecovery['isError'], isFalse);
        expect(client.sessionId, equals(activeSessionId));
        await client.deleteSession();
        expect(client.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'coalesces repeated router-hosted MCP compatibility notifications',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9145,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-notification-coalescing-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/secure',
        );
        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final grant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final client = McpStreamableHttpClient.withAuthGrant(endpoint, grant);
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'notification-coalescing-initialize');
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);

        for (var index = 0; index < 8; index++) {
          final registration = await serviceSession.register(
            'app.safe.notification_coalescing_transient',
            options: core.RegisterOptions(
              custom: const <String, Object?>{
                '_ai_meta_data': <String, Object?>{
                  'short_description': 'Transient coalescing tool',
                  'read_only_hint': true,
                  'destructive_hint': false,
                  'idempotent_hint': true,
                  'open_world_hint': false,
                },
              },
            ),
          );
          await client.ping(id: 'notification-coalescing-register-$index');
          await serviceSession.unregister(registration.registrationId);
          await client.ping(id: 'notification-coalescing-unregister-$index');
        }

        final rawClient = HttpClient();
        addTearDown(() => rawClient.close(force: true));
        final firstPoll = await _getHttp(
          rawClient,
          listener.port,
          '/mcp/secure',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': sessionId!,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
          },
        );
        expect(firstPoll.statusCode, equals(HttpStatus.ok));
        expect(
          RegExp(
            'notifications/tools/list_changed',
          ).allMatches(firstPoll.body).length,
          equals(1),
        );
        final lastEventId = RegExp(
          r'^id: (.+)$',
          multiLine: true,
        ).allMatches(firstPoll.body).last.group(1);

        final nextPoll = await _getHttp(
          rawClient,
          listener.port,
          '/mcp/secure',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': sessionId,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            'Last-Event-ID': ?lastEventId,
          },
        );
        expect(nextPoll.statusCode, equals(HttpStatus.ok));
        expect(
          nextPoll.body,
          isNot(contains('notifications/tools/list_changed')),
        );
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'bounds router-hosted MCP Streamable poll responses and keeps queued events recoverable',
      () async {
        const responseLimit = 4096;
        const notificationCount = 48;
        final batchedResourceUris = List<String>.generate(
          notificationCount,
          (index) => 'app://mcp/poll-response-batch-$index',
          growable: false,
        );
        final oversizedResourceUri =
            'app://mcp/live/${List<String>.filled(responseLimit, 'x').join()}';
        final harness = await _RouterHarness.start(
          connectionId: 9144,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(
            maxResponseBytes: responseLimit,
            liveResourceUri: oversizedResourceUri,
            additionalLiveResourceUris: batchedResourceUris,
          ),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-poll-response-bound-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/secure',
        );
        final authHttpClient = HttpClient();
        addTearDown(() => authHttpClient.close(force: true));
        final grant = await _issueTicketHttpGrant(
          authHttpClient,
          listener.port,
        );
        final client = McpStreamableHttpClient.withAuthGrant(
          endpoint,
          grant,
          maxResponseBytes: 8192,
        );
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'poll-response-bound-initialize');
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);
        final activeSessionId = sessionId!;

        for (var index = 0; index < batchedResourceUris.length; index++) {
          await client.subscribeResource(
            batchedResourceUris[index],
            id: 'poll-response-bound-resource-subscribe-$index',
          );
        }
        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{'version': 1},
          options: core.PublishOptions(acknowledge: true),
        );

        final rawClient = HttpClient();
        addTearDown(() => rawClient.close(force: true));
        String? lastEventId;
        var deliveredNotifications = 0;
        var pollCount = 0;
        while (deliveredNotifications < notificationCount) {
          final response = await _getHttp(
            rawClient,
            listener.port,
            '/mcp/secure',
            headers: <String, String>{
              HttpHeaders.acceptHeader: 'text/event-stream',
              HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
              'MCP-Session-Id': activeSessionId,
              'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
              'Last-Event-ID': ?lastEventId,
            },
          );
          expect(response.statusCode, equals(HttpStatus.ok));
          expect(
            utf8.encode(response.body).length,
            lessThanOrEqualTo(responseLimit),
          );
          final delivered = RegExp(
            'notifications/resources/updated',
          ).allMatches(response.body).length;
          expect(delivered, greaterThan(0));
          deliveredNotifications += delivered;
          lastEventId = RegExp(
            r'^id: (.+)$',
            multiLine: true,
          ).allMatches(response.body).last.group(1);
          pollCount++;
          expect(pollCount, lessThan(10));
        }
        expect(deliveredNotifications, equals(notificationCount));
        expect(pollCount, greaterThan(1));

        await client.subscribeResource(
          oversizedResourceUri,
          id: 'poll-response-bound-resource-subscribe',
        );
        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{'version': 2},
          options: core.PublishOptions(acknowledge: true),
        );

        late ({
          int statusCode,
          Map<String, Object?>? json,
          String body,
          Map<String, String> headers,
        })
        oversizedPoll;
        for (var attempt = 0; attempt < 20; attempt++) {
          oversizedPoll = await _getHttp(
            rawClient,
            listener.port,
            '/mcp/secure',
            headers: <String, String>{
              HttpHeaders.acceptHeader: 'text/event-stream',
              HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
              'MCP-Session-Id': activeSessionId,
              'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
              'Last-Event-ID': ?lastEventId,
            },
          );
          if (oversizedPoll.statusCode == HttpStatus.internalServerError) {
            break;
          }
          expect(oversizedPoll.statusCode, equals(HttpStatus.ok));
          lastEventId = RegExp(
            r'^id: (.+)$',
            multiLine: true,
          ).allMatches(oversizedPoll.body).last.group(1);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(
          oversizedPoll.statusCode,
          equals(HttpStatus.internalServerError),
        );
        expect(
          oversizedPoll.body,
          contains('SSE event exceeds the configured response limit'),
        );
        expect(oversizedPoll.headers, isNot(contains('mcp-session-id')));

        final recoveredPoll = await _getHttp(
          rawClient,
          listener.port,
          '/mcp/secure',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
            'MCP-Session-Id': activeSessionId,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
            'Last-Event-ID': ?lastEventId,
          },
        );
        expect(recoveredPoll.statusCode, equals(HttpStatus.ok));
        expect(utf8.encode(recoveredPoll.body).length, lessThan(responseLimit));
        expect(recoveredPoll.body, contains('retry: 1000'));
        expect(client.sessionId, equals(activeSessionId));
        await client.deleteSession();
        expect(client.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'keeps router-hosted MCP pubsub handles across tool catalog refreshes',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9147,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-pubsub-refresh-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));

        final directSubscription = await client.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'pubsub-refresh-direct-subscribe',
          queueLimit: 4,
        );
        await client.initialize(id: 'pubsub-refresh-initialize');
        await client.notifyInitialized();
        final streamableSubscription = await client.subscribeWampTopic(
          'app.events.audit',
          id: 'pubsub-refresh-streamable-subscribe',
          queueLimit: 4,
        );

        final dynamicRegistration = await serviceSession.register(
          'app.safe.catalog_refresh',
          options: core.RegisterOptions(
            custom: const <String, Object?>{
              '_ai_meta_data': <String, Object?>{
                'short_description': 'Catalog refresh marker',
                'read_only_hint': true,
                'destructive_hint': false,
                'idempotent_hint': true,
                'open_world_hint': false,
              },
            },
          ),
        );
        addTearDown(
          () => serviceSession.unregister(dynamicRegistration.registrationId),
        );

        expect(
          jsonEncode(
            await client.listWampApiDirect(id: 'pubsub-refresh-direct-catalog'),
          ),
          contains('app.safe.catalog_refresh'),
        );
        expect(
          jsonEncode(
            await client.listWampApi(id: 'pubsub-refresh-streamable-catalog'),
          ),
          contains('app.safe.catalog_refresh'),
        );

        await serviceSession.publish(
          'app.events.audit',
          argumentsKeywords: const <String, Object?>{'via': 'catalog-refresh'},
          options: core.PublishOptions(acknowledge: true),
        );

        Future<McpStreamableWampEventBatch> pollUntilEvent({
          required String handle,
          required bool directJson,
        }) async {
          var batch = directJson
              ? await client.pollWampEventsDirect(
                  handle,
                  id: 'pubsub-refresh-direct-poll-0',
                )
              : await client.pollWampEvents(
                  handle,
                  id: 'pubsub-refresh-streamable-poll-0',
                );
          for (
            var attempt = 1;
            batch.events.isEmpty && attempt < 50;
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            batch = directJson
                ? await client.pollWampEventsDirect(
                    handle,
                    id: 'pubsub-refresh-direct-poll-$attempt',
                  )
                : await client.pollWampEvents(
                    handle,
                    id: 'pubsub-refresh-streamable-poll-$attempt',
                  );
          }
          return batch;
        }

        final directEvents = await pollUntilEvent(
          handle: directSubscription.handle,
          directJson: true,
        );
        final streamableEvents = await pollUntilEvent(
          handle: streamableSubscription.handle,
          directJson: false,
        );
        expect(jsonEncode(directEvents.events), contains('catalog-refresh'));
        expect(
          jsonEncode(streamableEvents.events),
          contains('catalog-refresh'),
        );

        expect(
          (await client.unsubscribeWampTopicDirect(
            directSubscription.handle,
            id: 'pubsub-refresh-direct-unsubscribe',
          )).unsubscribed,
          isTrue,
        );
        expect(
          (await client.unsubscribeWampTopic(
            streamableSubscription.handle,
            id: 'pubsub-refresh-streamable-unsubscribe',
          )).unsubscribed,
          isTrue,
        );
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'revokes router-hosted MCP pubsub handles when subscribe access is lost',
      () async {
        final provider = _ToggleAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.audit',
        )..allowed = true;
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9165,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-pubsub-subscribe-revocation-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));

        final directSubscription = await client.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'pubsub-subscribe-revocation-direct-subscribe',
          queueLimit: 4,
        );
        final retainedSubscription = await client.subscribeWampTopicDirect(
          'app.events.readonly',
          id: 'pubsub-subscribe-revocation-retained-subscribe',
          queueLimit: 4,
        );
        await client.initialize(id: 'pubsub-subscribe-revocation-initialize');
        await client.notifyInitialized();
        final compatibilitySessionId = client.sessionId;
        expect(compatibilitySessionId, isNotNull);
        final streamableSubscription = await client.subscribeWampTopic(
          'app.events.audit',
          id: 'pubsub-subscribe-revocation-streamable-subscribe',
          queueLimit: 4,
        );
        expect(
          streamableSubscription.subscriptionId,
          equals(directSubscription.subscriptionId),
        );

        Future<int> subscriberCount(int subscriptionId, String label) async {
          final result = await client.countWampSubscriptionSubscribersDirect(
            subscriptionId,
            id: 'pubsub-subscribe-revocation-$label-count',
          );
          return (result.arguments.single as num).toInt();
        }

        expect(
          await subscriberCount(
            directSubscription.subscriptionId!,
            'revoked-before',
          ),
          equals(1),
        );
        expect(
          await subscriberCount(
            retainedSubscription.subscriptionId!,
            'retained-before',
          ),
          equals(1),
        );

        provider.allowed = false;
        final deniedCatalog = await client.listWampApiDirect(
          id: 'pubsub-subscribe-revocation-denied-catalog',
        );
        final deniedCompatibilityCatalog = await client.listWampApi(
          id: 'pubsub-subscribe-revocation-denied-compatibility-catalog',
        );
        expect(
          jsonEncode(deniedCatalog),
          allOf(
            contains('app.events.audit'),
            contains('"allowSubscribe":false'),
          ),
        );
        expect(
          jsonEncode(deniedCompatibilityCatalog),
          allOf(
            contains('app.events.audit'),
            contains('"allowSubscribe":false'),
          ),
        );
        expect(
          await subscriberCount(
            directSubscription.subscriptionId!,
            'revoked-after',
          ),
          isZero,
        );
        expect(
          await subscriberCount(
            retainedSubscription.subscriptionId!,
            'retained-after',
          ),
          equals(1),
        );

        await expectLater(
          client.pollWampEventsDirect(
            directSubscription.handle,
            id: 'pubsub-subscribe-revocation-direct-poll',
          ),
          throwsA(isA<McpStreamableWampToolException>()),
        );
        await expectLater(
          client.pollWampEvents(
            streamableSubscription.handle,
            id: 'pubsub-subscribe-revocation-streamable-poll',
          ),
          throwsA(isA<McpStreamableWampToolException>()),
        );
        expect(client.sessionId, equals(compatibilitySessionId));

        await serviceSession.publish(
          'app.events.readonly',
          argumentsKeywords: const <String, Object?>{
            'via': 'pubsub-subscribe-revocation-retained',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        var retainedEvents = await client.pollWampEventsDirect(
          retainedSubscription.handle,
          id: 'pubsub-subscribe-revocation-retained-poll-0',
        );
        for (
          var attempt = 1;
          retainedEvents.events.isEmpty && attempt < 50;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          retainedEvents = await client.pollWampEventsDirect(
            retainedSubscription.handle,
            id: 'pubsub-subscribe-revocation-retained-poll-$attempt',
          );
        }
        expect(
          jsonEncode(retainedEvents.events),
          contains('pubsub-subscribe-revocation-retained'),
        );

        provider.allowed = true;
        final restoredCatalog = await client.listWampApiDirect(
          id: 'pubsub-subscribe-revocation-restored-catalog',
        );
        expect(jsonEncode(restoredCatalog), contains('app.events.audit'));
        expect(
          await subscriberCount(
            directSubscription.subscriptionId!,
            'revoked-restored',
          ),
          isZero,
        );

        final replacement = await client.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'pubsub-subscribe-revocation-replacement-subscribe',
          queueLimit: 4,
        );
        expect(
          await subscriberCount(
            replacement.subscriptionId!,
            'replacement-active',
          ),
          equals(1),
        );
        await client.unsubscribeWampTopicDirect(
          replacement.handle,
          id: 'pubsub-subscribe-revocation-replacement-unsubscribe',
        );
        await client.unsubscribeWampTopicDirect(
          retainedSubscription.handle,
          id: 'pubsub-subscribe-revocation-retained-unsubscribe',
        );
        expect(client.sessionId, equals(compatibilitySessionId));
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'refreshes router-hosted MCP topic catalogs without tool shape changes',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9148,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-topic-catalog-refresh-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));

        const dynamicTopic = 'app.events.catalog_refresh';
        expect(
          jsonEncode(
            await client.listWampApiDirect(
              id: 'topic-catalog-refresh-direct-before',
            ),
          ),
          isNot(contains(dynamicTopic)),
        );
        await client.initialize(id: 'topic-catalog-refresh-initialize');
        await client.notifyInitialized();
        expect(
          jsonEncode(
            await client.listWampApi(
              id: 'topic-catalog-refresh-streamable-before',
            ),
          ),
          isNot(contains(dynamicTopic)),
        );

        await serviceSession.subscribe(dynamicTopic);

        expect(
          jsonEncode(
            await client.listWampApiDirect(
              id: 'topic-catalog-refresh-direct-after',
            ),
          ),
          contains(dynamicTopic),
        );
        expect(
          jsonEncode(
            await client.listWampApi(
              id: 'topic-catalog-refresh-streamable-after',
            ),
          ),
          contains(dynamicTopic),
        );
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'bounds router-hosted MCP WAMP calls and keeps the session reusable',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9142,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(callTimeoutMs: 80),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-bounded-call-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final stalledInvocations = <core.Invocation>[];
        final registration = await serviceSession.register(
          'app.safe.bounded_lookup',
          options: core.RegisterOptions(
            custom: const <String, Object?>{
              '_ai_meta_data': <String, Object?>{
                'short_description': 'Complete or stall a lookup',
                'read_only_hint': true,
                'destructive_hint': false,
                'idempotent_hint': true,
                'open_world_hint': false,
              },
            },
          ),
        );
        registration.onInvoke((invocation) {
          if (invocation.argumentsKeywords?['stall'] == true) {
            stalledInvocations.add(invocation);
            return;
          }
          invocation.respondWith(
            argumentsKeywords: const <String, Object?>{'status': 'complete'},
          );
        });
        final resourceRegistration = await serviceSession.register(
          'app.safe.resource.read',
        );
        resourceRegistration.onInvoke((_) {});

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));

        final directResult = await client
            .callToolDirect(
              'app.safe.bounded_lookup',
              id: 'bounded-direct-call',
              arguments: const <String, Object?>{'stall': true},
            )
            .timeout(const Duration(seconds: 2));
        expect(directResult['isError'], isTrue);
        expect(client.sessionId, isNull);
        final directTimeout = await harness
            .nextEvent('invocation_timeout')
            .timeout(const Duration(seconds: 2));

        await client.initialize(id: 'bounded-call-initialize');
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);

        final streamableResult = await client
            .callTool(
              'app.safe.bounded_lookup',
              id: 'bounded-streamable-call',
              arguments: const <String, Object?>{'stall': true},
            )
            .timeout(const Duration(seconds: 2));
        expect(streamableResult['isError'], isTrue);
        expect(client.sessionId, equals(sessionId));
        final streamableTimeout = await harness
            .nextEvent('invocation_timeout')
            .timeout(const Duration(seconds: 2));
        expect(stalledInvocations, hasLength(2));
        expect(directTimeout['invocationId'], isPositive);
        expect(streamableTimeout['invocationId'], isPositive);
        expect(
          streamableTimeout['invocationId'],
          isNot(directTimeout['invocationId']),
        );

        await expectLater(
          client
              .readResourceDirect(
                'app://mcp/live-context',
                id: 'bounded-direct-resource-read',
              )
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<McpJsonRpcException>()
                .having((error) => error.method, 'method', 'resources/read')
                .having(
                  (error) => error.error['code'],
                  'code',
                  McpErrorCodes.internalError,
                ),
          ),
        );
        final resourceTimeout = await harness
            .nextEvent('invocation_timeout')
            .timeout(const Duration(seconds: 2));
        expect(resourceTimeout['invocationId'], isPositive);
        expect(client.sessionId, equals(sessionId));

        final recovered = await client.callTool(
          'app.safe.bounded_lookup',
          id: 'bounded-call-recovery',
        );
        expect(recovered['isError'], isFalse);
        expect(
          recovered['structuredContent'],
          containsPair('argumentsKeywords', containsPair('status', 'complete')),
        );
        expect(client.sessionId, equals(sessionId));
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'refreshes the MCP catalog once before validating and dispatching',
      () async {
        final provider = _CountingCatalogAuthorizationProvider(
          action: AuthorizationAction.publish,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9139,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final client = McpStreamableHttpClient(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/public',
          ),
        );
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'single-catalog-refresh-initialize');

        expect(provider.matchingRequestCount, equals(1));
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'serializes overlapping router-hosted MCP catalog refreshes',
      () async {
        final firstRefreshEntered = Completer<void>();
        final secondRefreshEntered = Completer<void>();
        final releaseFirstRefresh = Completer<void>();
        final provider = _ConcurrentCatalogAuthorizationProvider(
          action: AuthorizationAction.publish,
          uri: 'app.events.audit',
          firstEntered: firstRefreshEntered,
          secondEntered: secondRefreshEntered,
          releaseFirst: releaseFirstRefresh,
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);
        addTearDown(() {
          if (!releaseFirstRefresh.isCompleted) {
            releaseFirstRefresh.complete();
          }
        });

        final harness = await _RouterHarness.start(
          connectionId: 9149,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final firstClient = McpStreamableHttpClient(endpoint);
        final secondClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => firstClient.close(force: true));
        addTearDown(() => secondClient.close(force: true));

        final firstRefresh = firstClient.listWampApiDirect(
          id: 'overlapping-catalog-refresh-first',
        );
        await firstRefreshEntered.future.timeout(const Duration(seconds: 2));
        final secondRefresh = secondClient.listWampApiDirect(
          id: 'overlapping-catalog-refresh-second',
        );
        final secondEnteredBeforeRelease = await Future.any(<Future<bool>>[
          secondRefreshEntered.future.then((_) => true),
          Future<bool>.delayed(const Duration(milliseconds: 500), () => false),
        ]);
        releaseFirstRefresh.complete();

        await Future.wait(<Future<Object?>>[firstRefresh, secondRefresh]);
        expect(secondEnteredBeforeRelease, isFalse);
        expect(provider.maxConcurrentMatchingRequests, equals(1));
      },
      skip: skipReason,
    );

    test(
      'returns bounded errors and recovers after MCP catalog authorization failures',
      () async {
        final provider = _FailNextCatalogAuthorizationProvider(
          action: AuthorizationAction.publish,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9150,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final statelessClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'catalog-refresh-failure-test',
            'version': '1.0.0',
          },
        );
        addTearDown(() => statelessClient.close(force: true));

        provider.failNext();
        await expectLater(
          statelessClient
              .listWampApiDirect(id: 'catalog-refresh-direct-failure')
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  allOf(
                    contains('catalog-refresh-direct-failure'),
                    contains('MCP catalog could not be refreshed'),
                    isNot(contains('authorization backend detail')),
                  ),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        final refreshError = await harness
            .nextEvent('mcp_catalog_refresh_error')
            .timeout(const Duration(seconds: 2));
        expect(refreshError['errorType'], equals('StateError'));
        expect(refreshError, isNot(contains('error')));
        expect(refreshError, isNot(contains('stackTrace')));
        expect(statelessClient.sessionId, isNull);
        expect(statelessClient.lastEventId, isNull);
        expect(
          jsonEncode(
            await statelessClient.listWampApiDirect(
              id: 'catalog-refresh-direct-recovery',
            ),
          ),
          contains('app.documented.only'),
        );

        final streamableClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => streamableClient.close(force: true));

        provider.failNext();
        await expectLater(
          streamableClient
              .initialize(id: 'catalog-refresh-initialize-failure')
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  allOf(
                    contains('catalog-refresh-initialize-failure'),
                    contains('MCP catalog could not be refreshed'),
                    isNot(contains('authorization backend detail')),
                  ),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  isNot(contains('mcp-session-id')),
                ),
          ),
        );
        expect(streamableClient.sessionId, isNull);
        expect(streamableClient.lastEventId, isNull);

        await streamableClient.initialize(
          id: 'catalog-refresh-initialize-recovery',
        );
        await streamableClient.notifyInitialized();
        final sessionId = streamableClient.sessionId;
        expect(sessionId, isNotNull);

        provider.failNext();
        await expectLater(
          streamableClient
              .listWampApi(id: 'catalog-refresh-streamable-failure')
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  allOf(
                    contains('catalog-refresh-streamable-failure'),
                    contains('MCP catalog could not be refreshed'),
                    isNot(contains('authorization backend detail')),
                  ),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  containsPair('mcp-session-id', <String>[sessionId!]),
                ),
          ),
        );
        expect(streamableClient.sessionId, equals(sessionId));
        expect(streamableClient.lastEventId, isNull);
        expect(
          jsonEncode(
            await streamableClient.listWampApi(
              id: 'catalog-refresh-streamable-recovery',
            ),
          ),
          contains('app.documented.only'),
        );
        expect(streamableClient.sessionId, equals(sessionId));

        final resumeCursor = streamableClient.lastEventId;
        provider.failNext();
        await expectLater(
          streamableClient.poll().timeout(const Duration(seconds: 2)),
          throwsA(
            isA<McpStreamableHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                )
                .having(
                  (error) => error.body,
                  'body',
                  allOf(
                    contains('MCP catalog could not be refreshed'),
                    isNot(contains('authorization backend detail')),
                  ),
                )
                .having(
                  (error) => error.responseHeaders,
                  'responseHeaders',
                  containsPair('mcp-session-id', <String>[sessionId]),
                ),
          ),
        );
        expect(streamableClient.sessionId, equals(sessionId));
        expect(streamableClient.lastEventId, equals(resumeCursor));
        await streamableClient.poll().timeout(const Duration(seconds: 2));
        expect(streamableClient.sessionId, equals(sessionId));
        await streamableClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'redacts MCP action authorization failures and preserves session recovery',
      () async {
        final provider = _FailDeferredAuthorizationProvider(
          action: AuthorizationAction.call,
          uri: 'app.safe.authorization_lookup',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9151,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-authorization-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);
        final registration = await serviceSession.register(
          'app.safe.authorization_lookup',
        );
        final observedRequests = <Object?>[];
        registration.onInvoke((invocation) {
          observedRequests.add(invocation.argumentsKeywords?['request']);
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'request': invocation.argumentsKeywords,
              'status': 'complete',
            },
          );
        });

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final statelessClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'action-authorization-failure-test',
            'version': '1.0.0',
          },
        );
        addTearDown(() => statelessClient.close(force: true));

        Future<void> expectBoundedAuthorizationErrorEvent() async {
          final event = await harness
              .nextEvent('mcp_authorization_error')
              .timeout(const Duration(seconds: 2));
          expect(event['realm'], equals('realm1'));
          expect(event['action'], equals('call'));
          expect(event['errorType'], equals('StateError'));
          expect(event, isNot(contains('error')));
          expect(event, isNot(contains('stackTrace')));
          expect(
            jsonEncode(event),
            isNot(contains('authorization backend detail')),
          );
        }

        provider.failOnMatchingRequest(2);
        final directFailure = await statelessClient
            .callToolDirect(
              'app.safe.authorization_lookup',
              id: 'action-authorization-direct-failure',
              arguments: const <String, Object?>{'request': 'direct-failure'},
            )
            .timeout(const Duration(seconds: 2));
        expect(directFailure['isError'], isTrue);
        expect(
          jsonEncode(directFailure),
          allOf(
            contains('MCP authorization check failed'),
            isNot(contains('authorization backend detail')),
          ),
        );
        expect(statelessClient.sessionId, isNull);
        expect(statelessClient.lastEventId, isNull);
        expect(observedRequests, isEmpty);
        await expectBoundedAuthorizationErrorEvent();

        final directRecovery = await statelessClient
            .callToolDirect(
              'app.safe.authorization_lookup',
              id: 'action-authorization-direct-recovery',
              arguments: const <String, Object?>{'request': 'direct-recovery'},
            )
            .timeout(const Duration(seconds: 2));
        expect(directRecovery['isError'], isNot(true));
        expect(jsonEncode(directRecovery), contains('direct-recovery'));
        expect(statelessClient.sessionId, isNull);
        expect(observedRequests, equals(<Object?>['direct-recovery']));

        final streamableClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => streamableClient.close(force: true));
        await streamableClient.initialize(
          id: 'action-authorization-initialize',
        );
        await streamableClient.notifyInitialized();
        final sessionId = streamableClient.sessionId;
        expect(sessionId, isNotNull);
        final cursorBeforeFailure = streamableClient.lastEventId;

        provider.failOnMatchingRequest(2);
        final streamableFailure = await streamableClient
            .callTool(
              'app.safe.authorization_lookup',
              id: 'action-authorization-streamable-failure',
              arguments: const <String, Object?>{
                'request': 'streamable-failure',
              },
            )
            .timeout(const Duration(seconds: 2));
        expect(streamableFailure['isError'], isTrue);
        expect(
          jsonEncode(streamableFailure),
          allOf(
            contains('MCP authorization check failed'),
            isNot(contains('authorization backend detail')),
          ),
        );
        expect(streamableClient.sessionId, equals(sessionId));
        expect(observedRequests, equals(<Object?>['direct-recovery']));
        final failureCursor = streamableClient.lastEventId;
        expect(failureCursor, startsWith('$sessionId:'));
        expect(failureCursor, isNot(equals(cursorBeforeFailure)));
        await expectBoundedAuthorizationErrorEvent();

        final streamableRecovery = await streamableClient
            .callTool(
              'app.safe.authorization_lookup',
              id: 'action-authorization-streamable-recovery',
              arguments: const <String, Object?>{
                'request': 'streamable-recovery',
              },
            )
            .timeout(const Duration(seconds: 2));
        expect(streamableRecovery['isError'], isNot(true));
        expect(jsonEncode(streamableRecovery), contains('streamable-recovery'));
        expect(streamableClient.sessionId, equals(sessionId));
        expect(
          observedRequests,
          equals(<Object?>['direct-recovery', 'streamable-recovery']),
        );
        expect(streamableClient.lastEventId, startsWith('$sessionId:'));
        expect(streamableClient.lastEventId, isNot(equals(failureCursor)));
        await streamableClient.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'keeps a new MCP session alive while its tool catalog refreshes',
      () async {
        final refreshEntered = Completer<void>();
        final releaseRefresh = Completer<void>();
        AuthorizationProviderRegistry.registerProvider(
          _BlockingCatalogAuthorizationProvider(
            action: AuthorizationAction.publish,
            uri: 'app.events.audit',
            entered: refreshEntered,
            release: releaseRefresh,
          ),
        );
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9138,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(sessionIdleTimeoutMs: 500),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));
        addTearDown(() {
          if (!releaseRefresh.isCompleted) {
            releaseRefresh.complete();
          }
        });

        final initialize = client.initialize(
          id: 'catalog-refresh-idle-initialize',
        );
        await refreshEntered.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        releaseRefresh.complete();

        final initializeResult = await initialize.timeout(
          const Duration(seconds: 3),
        );
        expect(
          initializeResult['id'],
          equals('catalog-refresh-idle-initialize'),
        );
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);

        await client.notifyInitialized();
        final tools = await client.listTools(id: 'catalog-refresh-idle-tools');
        expect(
          tools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        expect(client.sessionId, equals(sessionId));
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'clears and recovers the public client after MCP session idle expiry',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9117,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(
            sessionIdleTimeoutMs: 1000,
            maxSessionCount: 1,
          ),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        final replacementClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));
        addTearDown(() => replacementClient.close(force: true));

        await client.initialize(id: 'idle-expiry-initialize');
        await client.notifyInitialized();
        final expiredSessionId = client.sessionId;
        expect(expiredSessionId, isNotNull);
        final expiringSubscription = await client.subscribeWampTopic(
          'app.events.audit',
          id: 'idle-expiry-subscribe',
          queueLimit: 4,
        );
        final subscriptionId = expiringSubscription.subscriptionId!;

        Future<int> subscriberCount() async {
          final snapshot = await _fetchSnapshot(harness._statePort);
          for (final subscription in snapshot.subscriptions) {
            if (subscription.id == subscriptionId) {
              return subscription.subscribers.length;
            }
          }
          return 0;
        }

        expect(await subscriberCount(), equals(1));

        await expectLater(
          replacementClient.initialize(id: 'idle-expiry-capacity-blocked'),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.serviceUnavailable,
            ),
          ),
        );
        expect(replacementClient.sessionId, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 1500));

        var observedSubscriberCount = 1;
        for (var attempt = 0; attempt < 50; attempt++) {
          observedSubscriberCount = await subscriberCount();
          if (observedSubscriberCount == 0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(observedSubscriberCount, equals(0));

        await expectLater(
          client.listTools(id: 'idle-expiry-stale-tools'),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        await replacementClient.initialize(
          id: 'idle-expiry-replacement-initialize',
        );
        expect(replacementClient.sessionId, isNotNull);
        expect(replacementClient.sessionId, isNot(equals(expiredSessionId)));
        await replacementClient.notifyInitialized();
        final replacementTools = await replacementClient.listTools(
          id: 'idle-expiry-replacement-tools',
        );
        expect(
          replacementTools.tools.map((tool) => tool['name']),
          contains('connectanum.api.list'),
        );
        await replacementClient.deleteSession();
        expect(replacementClient.sessionId, isNull);
      },
      skip: skipReason,
    );

    test(
      'revokes pending and pre-dispatch MCP WAMP pubsub when a Streamable session is deleted',
      () async {
        final provider = _BlockingSnapshotAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9166,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'pending-delete-initialize');
        await client.notifyInitialized();
        final deletedSessionId = client.sessionId;
        expect(deletedSessionId, isNotNull);

        Future<int> subscriberCount() async {
          final snapshot = await _fetchSnapshot(harness._statePort);
          for (final subscription in snapshot.subscriptions) {
            if (subscription.topic == 'app.events.audit') {
              return subscription.subscribers.length;
            }
          }
          return 0;
        }

        final authorizationEntered = Completer<void>();
        final releaseAuthorization = Completer<void>();
        final matchingRequestsBeforePendingSubscribe =
            provider.matchingRequestCount;
        addTearDown(() {
          if (!releaseAuthorization.isCompleted) {
            releaseAuthorization.complete();
          }
        });
        provider.blockNextDecision(
          entered: authorizationEntered,
          release: releaseAuthorization,
          skipMatchingDecisions: 1,
        );
        final staleSubscribe = client.subscribeWampTopic(
          'app.events.audit',
          id: 'pending-delete-stale-subscribe',
          queueLimit: 4,
        );
        await authorizationEntered.future.timeout(const Duration(seconds: 5));
        expect(
          provider.matchingRequestCount,
          equals(matchingRequestsBeforePendingSubscribe + 2),
          reason:
              'the request catalog check must complete before the action '
              'authorization is blocked',
        );

        await client.deleteSession().timeout(const Duration(seconds: 5));
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(await subscriberCount(), isZero);

        releaseAuthorization.complete();
        await expectLater(
          staleSubscribe,
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(await subscriberCount(), isZero);

        await client.initialize(id: 'predispatch-delete-initialize');
        await client.notifyInitialized();
        final predispatchDeletedSessionId = client.sessionId;
        expect(predispatchDeletedSessionId, isNotNull);
        expect(predispatchDeletedSessionId, isNot(equals(deletedSessionId)));

        final catalogAuthorizationEntered = Completer<void>();
        final releaseCatalogAuthorization = Completer<void>();
        final matchingRequestsBeforePredispatchSubscribe =
            provider.matchingRequestCount;
        addTearDown(() {
          if (!releaseCatalogAuthorization.isCompleted) {
            releaseCatalogAuthorization.complete();
          }
        });
        provider.blockNextDecision(
          entered: catalogAuthorizationEntered,
          release: releaseCatalogAuthorization,
        );
        final stalePredispatchSubscribe = client.subscribeWampTopic(
          'app.events.audit',
          id: 'predispatch-delete-stale-subscribe',
          queueLimit: 4,
        );
        await catalogAuthorizationEntered.future.timeout(
          const Duration(seconds: 5),
        );
        expect(
          provider.matchingRequestCount,
          equals(matchingRequestsBeforePredispatchSubscribe + 1),
          reason: 'the request must still be blocked in its catalog refresh',
        );

        await client.deleteSession().timeout(const Duration(seconds: 5));
        releaseCatalogAuthorization.complete();
        await expectLater(
          stalePredispatchSubscribe,
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(await subscriberCount(), isZero);

        await client.initialize(id: 'pending-delete-replacement-initialize');
        await client.notifyInitialized();
        expect(client.sessionId, isNotNull);
        expect(client.sessionId, isNot(equals(deletedSessionId)));
        expect(client.sessionId, isNot(equals(predispatchDeletedSessionId)));
        final replacement = await client.subscribeWampTopic(
          'app.events.audit',
          id: 'pending-delete-replacement-subscribe',
          queueLimit: 4,
        );
        expect(await subscriberCount(), equals(1));
        await client.unsubscribeWampTopic(
          replacement.handle,
          id: 'pending-delete-replacement-unsubscribe',
        );
        expect(await subscriberCount(), isZero);
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'rejects pending MCP GET after its Streamable session is deleted',
      () async {
        final provider = _BlockingSnapshotAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9168,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-pending-get-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        final rawClient = HttpClient();
        addTearDown(() => client.close(force: true));
        addTearDown(() => rawClient.close(force: true));

        await client.initialize(id: 'pending-get-initialize');
        await client.notifyInitialized();
        final deletedSessionId = client.sessionId;
        expect(deletedSessionId, isNotNull);
        await client.subscribeResource(
          'app://mcp/live-context',
          id: 'pending-get-resource-subscribe',
        );
        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'via': 'pending-get-stale-notification',
          },
          options: core.PublishOptions(acknowledge: true),
        );

        final authorizationEntered = Completer<void>();
        final releaseAuthorization = Completer<void>();
        addTearDown(() {
          if (!releaseAuthorization.isCompleted) {
            releaseAuthorization.complete();
          }
        });
        provider.blockNextDecision(
          entered: authorizationEntered,
          release: releaseAuthorization,
        );
        final matchingRequestsBeforePoll = provider.matchingRequestCount;
        final stalePoll = _getHttp(
          rawClient,
          listener.port,
          '/mcp/public',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            'MCP-Session-Id': deletedSessionId!,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
          },
        );
        await authorizationEntered.future.timeout(const Duration(seconds: 5));
        expect(
          provider.matchingRequestCount,
          equals(matchingRequestsBeforePoll + 1),
          reason: 'the GET must be blocked in its catalog refresh',
        );

        await client.deleteSession().timeout(const Duration(seconds: 5));
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        releaseAuthorization.complete();

        final staleResponse = await stalePoll.timeout(
          const Duration(seconds: 5),
        );
        expect(
          staleResponse.body,
          isNot(contains('notifications/resources/updated')),
        );
        expect(staleResponse.statusCode, equals(HttpStatus.notFound));
        expect(staleResponse.headers, isNot(contains('mcp-session-id')));

        await client.initialize(id: 'pending-get-replacement-initialize');
        await client.notifyInitialized();
        expect(client.sessionId, isNotNull);
        expect(client.sessionId, isNot(equals(deletedSessionId)));
        final replacementEvents = await client.poll();
        expect(replacementEvents, isNotEmpty);
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'prefers deleted MCP sessions over pending catalog failures',
      () async {
        final provider = _BlockingFailNextCatalogAuthorizationProvider(
          action: AuthorizationAction.subscribe,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9169,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final client = McpStreamableHttpClient(endpoint);
        final rawClient = HttpClient();
        addTearDown(() => client.close(force: true));
        addTearDown(() => rawClient.close(force: true));

        await client.initialize(id: 'deleted-catalog-get-initialize');
        await client.notifyInitialized();
        final deletedGetSessionId = client.sessionId;
        expect(deletedGetSessionId, isNotNull);

        final getAuthorizationEntered = Completer<void>();
        final releaseGetAuthorization = Completer<void>();
        addTearDown(() {
          if (!releaseGetAuthorization.isCompleted) {
            releaseGetAuthorization.complete();
          }
        });
        provider.blockNextFailure(
          entered: getAuthorizationEntered,
          release: releaseGetAuthorization,
        );
        final staleGet = _getHttp(
          rawClient,
          listener.port,
          '/mcp/public',
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'text/event-stream',
            'MCP-Session-Id': deletedGetSessionId!,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
          },
        );
        await getAuthorizationEntered.future.timeout(
          const Duration(seconds: 5),
        );
        await client.deleteSession().timeout(const Duration(seconds: 5));
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        releaseGetAuthorization.complete();

        final staleGetResponse = await staleGet.timeout(
          const Duration(seconds: 5),
        );
        expect(staleGetResponse.statusCode, equals(HttpStatus.notFound));
        expect(staleGetResponse.headers, isNot(contains('mcp-session-id')));
        expect(staleGetResponse.body, contains('Unknown MCP HTTP session'));
        expect(
          staleGetResponse.body,
          isNot(contains('MCP catalog could not be refreshed')),
        );

        await client.initialize(id: 'deleted-catalog-post-initialize');
        await client.notifyInitialized();
        final deletedPostSessionId = client.sessionId;
        expect(deletedPostSessionId, isNotNull);
        expect(deletedPostSessionId, isNot(equals(deletedGetSessionId)));

        final postAuthorizationEntered = Completer<void>();
        final releasePostAuthorization = Completer<void>();
        addTearDown(() {
          if (!releasePostAuthorization.isCompleted) {
            releasePostAuthorization.complete();
          }
        });
        provider.blockNextFailure(
          entered: postAuthorizationEntered,
          release: releasePostAuthorization,
        );
        final stalePost = _postJson(
          rawClient,
          listener.port,
          '/mcp/public',
          const <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'deleted-catalog-post-request',
            'method': 'tools/list',
          },
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            'MCP-Session-Id': deletedPostSessionId!,
            'MCP-Protocol-Version': mcpLatestSessionProtocolVersion,
          },
        );
        await postAuthorizationEntered.future.timeout(
          const Duration(seconds: 5),
        );
        await client.deleteSession().timeout(const Duration(seconds: 5));
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        releasePostAuthorization.complete();

        final stalePostResponse = await stalePost.timeout(
          const Duration(seconds: 5),
        );
        expect(stalePostResponse.statusCode, equals(HttpStatus.notFound));
        expect(stalePostResponse.headers, isNot(contains('mcp-session-id')));
        expect(
          stalePostResponse.json,
          containsPair('id', 'deleted-catalog-post-request'),
        );
        expect(stalePostResponse.body, contains('Unknown MCP HTTP session'));
        expect(
          stalePostResponse.body,
          isNot(contains('MCP catalog could not be refreshed')),
        );

        await client.initialize(id: 'deleted-catalog-replacement-initialize');
        await client.notifyInitialized();
        expect(client.sessionId, isNotNull);
        expect(client.sessionId, isNot(equals(deletedPostSessionId)));
        final replacementTools = await client.listTools(
          id: 'deleted-catalog-replacement-tools',
        );
        expect(replacementTools.tools, isNotEmpty);
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'prevents MCP WAMP actions from completing after their Streamable session is deleted',
      () async {
        final provider = _BlockingSnapshotAuthorizationProvider(
          action: AuthorizationAction.publish,
          uri: 'app.events.audit',
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9167,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final directClient = McpStreamableHttpClient(endpoint);
        final streamableClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => directClient.close(force: true));
        addTearDown(() => streamableClient.close(force: true));

        final directSubscription = await directClient.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'deleted-action-direct-subscribe',
          queueLimit: 4,
        );
        expect(directClient.sessionId, isNull);
        expect(directClient.lastEventId, isNull);

        Future<McpStreamableWampEventBatch> pollDirectUntilEvent(
          String id,
        ) async {
          var batch = await directClient.pollWampEventsDirect(
            directSubscription.handle,
            id: '$id-0',
          );
          for (
            var attempt = 1;
            batch.events.isEmpty && attempt < 50;
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            batch = await directClient.pollWampEventsDirect(
              directSubscription.handle,
              id: '$id-$attempt',
            );
          }
          return batch;
        }

        await streamableClient.initialize(id: 'deleted-action-initialize');
        await streamableClient.notifyInitialized();
        final deletedSessionId = streamableClient.sessionId;
        expect(deletedSessionId, isNotNull);

        final authorizationEntered = Completer<void>();
        final releaseAuthorization = Completer<void>();
        final matchingRequestsBeforePublish = provider.matchingRequestCount;
        addTearDown(() {
          if (!releaseAuthorization.isCompleted) {
            releaseAuthorization.complete();
          }
        });
        provider.blockNextDecision(
          entered: authorizationEntered,
          release: releaseAuthorization,
          skipMatchingDecisions: 1,
        );
        final stalePublish = streamableClient.publishWampEvent(
          'app.events.audit',
          id: 'deleted-action-stale-publish',
          argumentsKeywords: const <String, Object?>{
            'marker': 'deleted-action-stale',
          },
          acknowledge: true,
          options: const <String, Object?>{'exclude_me': false},
        );
        await authorizationEntered.future.timeout(const Duration(seconds: 5));
        expect(
          provider.matchingRequestCount,
          equals(matchingRequestsBeforePublish + 2),
          reason:
              'the request catalog check must complete before the action '
              'authorization is blocked',
        );

        await streamableClient.deleteSession().timeout(
          const Duration(seconds: 5),
        );
        expect(streamableClient.sessionId, isNull);
        expect(streamableClient.lastEventId, isNull);

        releaseAuthorization.complete();
        await expectLater(
          stalePublish,
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        final eventsAfterDelete = await pollDirectUntilEvent(
          'deleted-action-stale-poll',
        );
        expect(
          eventsAfterDelete.events,
          isEmpty,
          reason: 'a deleted MCP session must not complete its WAMP publish',
        );
        expect(streamableClient.sessionId, isNull);
        expect(streamableClient.lastEventId, isNull);

        await streamableClient.initialize(
          id: 'deleted-action-replacement-initialize',
        );
        await streamableClient.notifyInitialized();
        expect(streamableClient.sessionId, isNotNull);
        expect(streamableClient.sessionId, isNot(equals(deletedSessionId)));
        final replacementPublication = await streamableClient.publishWampEvent(
          'app.events.audit',
          id: 'deleted-action-replacement-publish',
          argumentsKeywords: const <String, Object?>{
            'marker': 'deleted-action-replacement',
          },
          acknowledge: true,
          options: const <String, Object?>{'exclude_me': false},
        );
        expect(replacementPublication.acknowledged, isTrue);
        final replacementEvents = await pollDirectUntilEvent(
          'deleted-action-replacement-poll',
        );
        expect(replacementEvents.events, hasLength(1));
        expect(
          replacementEvents.events.single['argumentsKeywords'],
          containsPair('marker', 'deleted-action-replacement'),
        );
        await streamableClient.deleteSession();

        final directUnsubscribe = await directClient.unsubscribeWampTopicDirect(
          directSubscription.handle,
          id: 'deleted-action-direct-unsubscribe',
        );
        expect(directUnsubscribe.unsubscribed, isTrue);
        expect(directClient.sessionId, isNull);
        expect(directClient.lastEventId, isNull);
      },
      skip: skipReason,
    );

    test(
      'prevents MCP WAMP calls from completing after their Streamable session is deleted',
      () async {
        const procedure = 'app.safe.deleted_action_lookup';
        final provider = _BlockingSnapshotAuthorizationProvider(
          action: AuthorizationAction.call,
          uri: procedure,
        );
        AuthorizationProviderRegistry.registerProvider(provider);
        addTearDown(AuthorizationProviderRegistry.clear);

        final harness = await _RouterHarness.start(
          connectionId: 9168,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-deleted-action-call-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);
        var invocationCount = 0;
        final registration = await serviceSession.register(procedure);
        addTearDown(
          () => serviceSession.unregister(registration.registrationId),
        );
        registration.onInvoke((invocation) {
          invocationCount++;
          invocation.respondWith(
            argumentsKeywords: <String, Object?>{
              'invocation': invocationCount,
              'request': invocation.argumentsKeywords,
            },
          );
        });

        final listener = harness.binding.listeners.single;
        final client = McpStreamableHttpClient(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/public',
          ),
        );
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'deleted-call-initialize');
        await client.notifyInitialized();
        final deletedSessionId = client.sessionId;
        expect(deletedSessionId, isNotNull);

        final authorizationEntered = Completer<void>();
        final releaseAuthorization = Completer<void>();
        final matchingRequestsBeforeCall = provider.matchingRequestCount;
        addTearDown(() {
          if (!releaseAuthorization.isCompleted) {
            releaseAuthorization.complete();
          }
        });
        provider.blockNextDecision(
          entered: authorizationEntered,
          release: releaseAuthorization,
          skipMatchingDecisions: 1,
        );
        final staleCall = client.callTool(
          procedure,
          id: 'deleted-call-stale',
          arguments: const <String, Object?>{'marker': 'stale'},
        );
        await authorizationEntered.future.timeout(const Duration(seconds: 5));
        expect(
          provider.matchingRequestCount,
          equals(matchingRequestsBeforeCall + 2),
          reason:
              'the request catalog check must complete before the action '
              'authorization is blocked',
        );

        await client.deleteSession().timeout(const Duration(seconds: 5));
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        releaseAuthorization.complete();
        await expectLater(
          staleCall,
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
        expect(invocationCount, isZero);
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        await client.initialize(id: 'deleted-call-replacement-initialize');
        await client.notifyInitialized();
        expect(client.sessionId, isNotNull);
        expect(client.sessionId, isNot(equals(deletedSessionId)));
        final replacementResult = await client.callTool(
          procedure,
          id: 'deleted-call-replacement',
          arguments: const <String, Object?>{'marker': 'replacement'},
        );
        expect(replacementResult['isError'], isFalse);
        expect(invocationCount, equals(1));
        expect(
          replacementResult['structuredContent'],
          containsPair('argumentsKeywords', containsPair('invocation', 1)),
        );
        await client.deleteSession();
      },
      skip: skipReason,
    );

    test(
      'deletes MCP Streamable HTTP sessions without interrupting shared direct JSON pubsub or modern resource owners',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9118,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final serviceSession = await harness.binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-resource-delete-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final listener = harness.binding.listeners.single;
        final httpClient = HttpClient();
        addTearDown(() => httpClient.close(force: true));

        final endpoint = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        );
        final directClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => directClient.close(force: true));
        final modernClient = McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'router-resource-delete-test',
            'version': '1.0.0',
          },
        );
        addTearDown(() => modernClient.close(force: true));
        final mcpClient = McpStreamableHttpClient(endpoint);
        addTearDown(() => mcpClient.close(force: true));

        final modernListener = await modernClient.listen(
          id: 'cleanup-modern-resource-listen',
          resourceSubscriptions: const <String>['app://mcp/live-context'],
        );
        expect(
          modernListener.acknowledgedNotifications.resourceSubscriptions,
          equals(const <String>['app://mcp/live-context']),
        );
        final modernNotifications = StreamIterator<Map<String, Object?>>(
          modernListener.notifications,
        );
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        final directSubscription = await directClient.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'cleanup-direct-subscribe',
          queueLimit: 5,
        );
        final subscriptionId = directSubscription.subscriptionId;
        expect(subscriptionId, isNotNull);
        expect(directClient.sessionId, isNull);
        expect(directClient.lastEventId, isNull);

        await mcpClient.initialize(id: 'cleanup-initialize');
        await mcpClient.notifyInitialized();
        final deletedStreamableSessionId = mcpClient.sessionId;
        expect(deletedStreamableSessionId, isNotNull);
        final subscription = await mcpClient.subscribeWampTopic(
          'app.events.audit',
          id: 'cleanup-subscribe',
          queueLimit: 5,
        );
        expect(subscription.subscriptionId, equals(subscriptionId));
        await mcpClient.subscribeResource(
          'app://mcp/live-context',
          id: 'cleanup-resource-subscribe',
        );

        Future<int> subscriberCount() async {
          final result = await _callRouterJsonMethod(
            httpClient,
            listener.port,
            '/mcp/public',
            'wamp.subscription.count_subscribers',
            {'id': subscriptionId},
          );
          final arguments =
              (result['structuredContent'] as Map<String, Object?>)['arguments']
                  as List;
          return arguments.single as int;
        }

        expect(await subscriberCount(), equals(1));

        final resourceSubscriptionLookup = await mcpClient
            .lookupWampSubscription(
              'app.events.resource.context',
              id: 'cleanup-resource-subscription-lookup',
            );
        final resourceSubscriptionId =
            (resourceSubscriptionLookup.arguments.single as num).toInt();

        Future<int> resourceSubscriberCount() async {
          final result = await _callRouterJsonMethod(
            httpClient,
            listener.port,
            '/mcp/public',
            'wamp.subscription.count_subscribers',
            {'id': resourceSubscriptionId},
          );
          final arguments =
              (result['structuredContent'] as Map<String, Object?>)['arguments']
                  as List;
          return arguments.single as int;
        }

        Future<int> waitForResourceSubscriberCount(int expected) async {
          var actual = -1;
          for (var attempt = 0; attempt < 50; attempt++) {
            actual = await resourceSubscriberCount();
            if (actual == expected) {
              return actual;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return actual;
        }

        expect(await resourceSubscriberCount(), equals(1));

        await mcpClient.deleteSession();
        expect(mcpClient.sessionId, isNull);
        expect(mcpClient.lastEventId, isNull);
        expect(directClient.sessionId, isNull);
        expect(directClient.lastEventId, isNull);

        expect(await subscriberCount(), equals(1));
        expect(await resourceSubscriberCount(), equals(1));

        final directPublication = await directClient.publishWampEventDirect(
          'app.events.audit',
          id: 'cleanup-direct-publish-after-delete',
          argumentsKeywords: const <String, Object?>{
            'marker': 'cleanup-direct-after-delete',
          },
          acknowledge: true,
          options: const <String, Object?>{'exclude_me': false},
        );
        expect(directPublication.acknowledged, isTrue);
        final directPoll = await _pollDirectRouterJsonUntilEvents(
          httpClient,
          listener.port,
          '/mcp/public',
          directSubscription.handle,
        );
        expect(
          jsonEncode(directPoll['events']),
          contains('cleanup-direct-after-delete'),
        );

        final modernUpdateAfterDelete = modernNotifications.moveNext().timeout(
          const Duration(seconds: 5),
        );
        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'marker': 'cleanup-modern-after-delete',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        expect(await modernUpdateAfterDelete, isTrue);
        expect(
          modernNotifications.current['method'],
          equals('notifications/resources/updated'),
        );
        expect(
          (modernNotifications.current['params'] as Map)['uri'],
          equals('app://mcp/live-context'),
        );
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);

        await mcpClient.initialize(id: 'cleanup-replacement-initialize');
        await mcpClient.notifyInitialized();
        expect(mcpClient.sessionId, isNotNull);
        expect(mcpClient.sessionId, isNot(equals(deletedStreamableSessionId)));
        await mcpClient.subscribeResource(
          'app://mcp/live-context',
          id: 'cleanup-replacement-resource-subscribe',
        );
        expect(await resourceSubscriberCount(), equals(1));

        await modernNotifications.cancel();
        await modernListener.close();
        expect(
          await modernListener.closed,
          equals(McpSubscriptionCloseReason.local),
        );
        expect(modernClient.sessionId, isNull);
        expect(modernClient.lastEventId, isNull);
        expect(await waitForResourceSubscriberCount(1), equals(1));

        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: const <String, Object?>{
            'marker': 'cleanup-replacement-after-modern-close',
          },
          options: core.PublishOptions(acknowledge: true),
        );
        final replacementUpdate = await _pollStreamableMcpUntilResourceUpdate(
          mcpClient,
          'app://mcp/live-context',
        );
        expect(
          replacementUpdate['method'],
          equals('notifications/resources/updated'),
        );
        await mcpClient.unsubscribeResource(
          'app://mcp/live-context',
          id: 'cleanup-replacement-resource-unsubscribe',
        );
        var finalResourceSubscriberCount = 1;
        for (var attempt = 0; attempt < 50; attempt++) {
          await serviceSession.publish(
            'app.events.resource.context',
            argumentsKeywords: <String, Object?>{
              'marker': 'cleanup-final-resource-$attempt',
            },
            options: core.PublishOptions(acknowledge: true),
          );
          finalResourceSubscriberCount = await resourceSubscriberCount();
          if (finalResourceSubscriberCount == 0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(finalResourceSubscriberCount, equals(0));
        await mcpClient.deleteSession();
        expect(mcpClient.sessionId, isNull);
        expect(mcpClient.lastEventId, isNull);

        final directUnsubscribe = await directClient.unsubscribeWampTopicDirect(
          directSubscription.handle,
          id: 'cleanup-direct-unsubscribe',
        );
        expect(directUnsubscribe.unsubscribed, isTrue);
        expect(directClient.sessionId, isNull);
        expect(directClient.lastEventId, isNull);
        expect(await subscriberCount(), equals(0));
      },
      skip: skipReason,
    );

    test(
      'serves Streamable HTTP batch responses on router MCP routes',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9116,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final binding = harness.binding;
        final serviceSession = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'mcp-batch-service',
          authRole: 'internal',
        );
        addTearDown(serviceSession.close);

        final registration = await serviceSession.register(
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
                'read_only_hint': true,
                'destructive_hint': false,
                'idempotent_hint': true,
                'open_world_hint': false,
              },
            },
          ),
        );
        registration.onInvoke((invocation) {
          invocation.respondWith(
            argumentsKeywords: {
              'taskId': invocation.argumentsKeywords?['taskId'],
              'status': 'open',
            },
          );
        });

        final listener = binding.listeners.single;
        final httpClient = HttpClient();
        addTearDown(() => httpClient.close(force: true));

        Future<void> expectStreamableBatch(
          McpStreamableHttpClient client,
          String label,
        ) async {
          await client.initialize();
          await client.notifyInitialized();
          final responses = await client.postBatch([
            {
              'jsonrpc': '2.0',
              'id': '$label-batch-tools',
              'method': 'tools/list',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'id': '$label-batch-call',
              'method': 'tools/call',
              'params': {
                'name': 'app.safe.lookup',
                'arguments': {'taskId': 'T-$label-batch'},
              },
            },
            {
              'jsonrpc': '2.0',
              'method': 'notifications/initialized',
              'params': {},
            },
          ]);
          expect(responses, isNotNull);
          expect(responses, hasLength(2));
          expect(responses![0]['id'], equals('$label-batch-tools'));
          expect(jsonEncode(responses[0]), contains('app.safe.lookup'));
          expect(responses[1]['id'], equals('$label-batch-call'));
          expect(jsonEncode(responses[1]), contains('T-$label-batch'));
          expect(client.lastEventId, startsWith('${client.sessionId}:'));

          final sessionId = client.sessionId;
          expect(sessionId, isNotNull);
          final previousEventId = client.lastEventId;
          final errorResponses = await client.postBatch([
            {
              'jsonrpc': '2.0',
              'id': '$label-batch-error-tools',
              'method': 'tools/list',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'id': '$label-batch-error-unknown',
              'method': 'consumer.unknown.method',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'method': 'notifications/initialized',
              'params': {},
            },
          ]);
          expect(errorResponses, isNotNull);
          expect(errorResponses, hasLength(2));
          expect(errorResponses![0]['id'], equals('$label-batch-error-tools'));
          expect(jsonEncode(errorResponses[0]), contains('app.safe.lookup'));
          expect(errorResponses[1]['id'], equals('$label-batch-error-unknown'));
          expect((errorResponses[1]['error'] as Map)['code'], equals(-32601));
          expect(
            jsonEncode(errorResponses[1]['error']),
            contains('Unknown MCP method'),
          );
          expect(client.sessionId, equals(sessionId));
          expect(client.lastEventId, startsWith('$sessionId:'));
          expect(client.lastEventId, isNot(equals(previousEventId)));
        }

        final publicClient = McpStreamableHttpClient(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/public',
          ),
        );
        addTearDown(() => publicClient.close(force: true));
        await expectStreamableBatch(publicClient, 'public');

        final grant = await _issueTicketHttpGrant(httpClient, listener.port);
        final secureClient = McpStreamableHttpClient.withAuthGrant(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/secure',
          ),
          grant,
        );
        addTearDown(() => secureClient.close(force: true));
        await expectStreamableBatch(secureClient, 'secure');
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
      final observedSafeLookupTaskIds = <String>{};
      safeRegistration.onInvoke((invocation) {
        final taskId = invocation.argumentsKeywords?['taskId'];
        if (taskId != null) {
          observedSafeLookupTaskIds.add(taskId.toString());
        }
        invocation.respondWith(
          argumentsKeywords: {
            'status': 'open',
            'request': invocation.argumentsKeywords,
          },
        );
      });

      final mrtrCallDetails = <Map<String, dynamic>>[];
      final mrtrRegistration = await serviceSession.register(
        'app.safe.deploy',
        options: core.RegisterOptions(
          custom: const {
            '_ai_meta_data': {
              'short_description': 'Prepare a deployment',
              'description': 'Collects required form input before preparing.',
              'domain': 'app',
              'entity': 'deployment',
              'verbs': ['prepare'],
              'tags': ['safe'],
              'input_json_schema': {
                'type': 'object',
                'properties': {
                  'release': {'type': 'string'},
                },
                'required': ['release'],
              },
              'read_only_hint': true,
              'destructive_hint': false,
              'idempotent_hint': true,
              'open_world_hint': false,
            },
          },
        ),
      );
      mrtrRegistration.onInvoke((invocation) {
        final details = Map<String, dynamic>.from(invocation.details.custom);
        mrtrCallDetails.add(details);
        if (!details.containsKey(McpWampMrtrFields.inputResponses)) {
          invocation.respondWith(
            options: core.YieldOptions(
              custom: <String, dynamic>{
                McpWampMrtrFields.resultType: 'input_required',
                McpWampMrtrFields.inputRequests: <String, dynamic>{
                  'deployment': <String, dynamic>{
                    'method': 'elicitation/create',
                    'params': <String, dynamic>{
                      'mode': 'form',
                      'message': 'Confirm the deployment settings.',
                      'requestedSchema': <String, dynamic>{
                        'type': 'object',
                        'properties': <String, dynamic>{
                          'email': <String, dynamic>{
                            'type': 'string',
                            'format': 'email',
                          },
                          'replicas': <String, dynamic>{
                            'type': 'integer',
                            'minimum': 1,
                            'maximum': 8,
                          },
                        },
                        'required': <String>['email', 'replicas'],
                      },
                    },
                  },
                },
                McpWampMrtrFields.requestState: 'router-opaque-round-1',
              },
            ),
          );
          return;
        }
        invocation.respondWith(
          argumentsKeywords: <String, dynamic>{
            'status': 'ready',
            'release': invocation.argumentsKeywords?['release'],
            'inputResponses': details[McpWampMrtrFields.inputResponses],
            'requestState': details[McpWampMrtrFields.requestState],
          },
        );
      });

      var liveResourceVersion = 1;
      final observedLiveResourceUris = <String>[];
      final liveResourceRegistration = await serviceSession.register(
        'app.safe.resource.read',
      );
      liveResourceRegistration.onInvoke((invocation) {
        final resourceUri = invocation.arguments?.single;
        if (resourceUri != null) {
          observedLiveResourceUris.add(resourceUri.toString());
        }
        invocation.respondWith(
          argumentsKeywords: {
            'uri': resourceUri,
            'version': liveResourceVersion,
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
      await serviceSession.subscribe('app.events.audit');
      await serviceSession.subscribe('app.secure.audit');

      final listener = binding.listeners.single;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final directPublicMcpClient = McpStreamableHttpClient(
        Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        ),
      );
      addTearDown(() => directPublicMcpClient.close(force: true));

      final directPublicTools = await directPublicMcpClient
          .listConnectanumToolsDirect(id: 'direct-public-tools');
      final directPublicToolNames = {
        for (final tool in directPublicTools.tools) tool['name'] as String,
      };
      expect(directPublicToolNames, contains('app.safe.lookup'));
      expect(directPublicToolNames, isNot(contains('app.unsafe.delete')));
      expect(directPublicMcpClient.sessionId, isNull);

      final deniedDirectResourceRead = await directPublicMcpClient
          .requestDirect(
            'resources/read',
            id: 'direct-public-member-resource-read',
            params: {'uri': 'app://mcp/member-context'},
          );
      expect(
        (deniedDirectResourceRead['error'] as Map)['code'],
        equals(McpErrorCodes.resourceNotFound),
      );
      expect(
        jsonEncode(deniedDirectResourceRead['error']),
        contains('Resource not found'),
      );

      final directCatalogContent = await directPublicMcpClient.listWampApi(
        id: 'direct-public-catalog',
        kind: 'procedure',
        directJson: true,
      );
      final directCatalogMetadata =
          directCatalogContent['metadata'] as Map<String, Object?>;
      expect(directCatalogMetadata, containsPair('authid', 'anonymous'));
      expect(jsonEncode(directCatalogContent), contains('app.safe.lookup'));
      expect(jsonEncode(directCatalogContent), contains('app.documented.only'));
      expect(
        jsonEncode(directCatalogContent),
        isNot(contains('app.unsafe.delete')),
      );

      final directPublicTopicCatalog = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'connectanum.api.list',
        {'kind': 'topic'},
      );
      final directPublicTopicCatalogJson = jsonEncode(
        directPublicTopicCatalog['structuredContent'],
      );
      expect(directPublicTopicCatalogJson, contains('app.events.audit'));
      expect(directPublicTopicCatalogJson, isNot(contains('app.secure.audit')));

      final directPublicResources = await directPublicMcpClient.listResources(
        id: 'direct-public-resources',
        directJson: true,
      );
      expect(
        directPublicResources.resources.map((resource) => resource['uri']),
        containsAll(['app://mcp/context', 'app://mcp/live-context']),
      );

      final directPublicResourceContents = await directPublicMcpClient
          .readResource(
            'app://mcp/context',
            id: 'direct-public-resource-read',
            directJson: true,
          );
      expect(
        directPublicResourceContents.single['text'],
        contains('router-hosted MCP route'),
      );

      final directLiveResourceContents = await directPublicMcpClient
          .readResource(
            'app://mcp/live-context',
            id: 'direct-public-live-resource-read',
            directJson: true,
          );
      final directLiveResource =
          jsonDecode(directLiveResourceContents.single['text'] as String)
              as Map<String, Object?>;
      expect(
        (directLiveResource['argumentsKeywords'] as Map)['version'],
        equals(1),
      );
      expect(observedLiveResourceUris, contains('app://mcp/live-context'));

      final directResourceSubscribe = await directPublicMcpClient.requestDirect(
        'resources/subscribe',
        id: 'direct-public-resource-subscribe',
        params: {'uri': 'app://mcp/live-context'},
      );
      expect(
        (directResourceSubscribe['error'] as Map)['code'],
        equals(McpErrorCodes.invalidRequest),
      );
      expect(
        jsonEncode(directResourceSubscribe['error']),
        contains('requires a Streamable HTTP session'),
      );
      expect(directPublicMcpClient.sessionId, isNull);

      final statelessPublicMcpClient = McpStreamableHttpClient.stateless(
        Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        ),
        clientInfo: const <String, Object?>{
          'name': 'router-native-test',
          'version': '1.0.0',
        },
      );
      addTearDown(() => statelessPublicMcpClient.close(force: true));
      final statelessDiscovery = await statelessPublicMcpClient.discover(
        id: 'stateless-public-discover',
      );
      expect(
        statelessDiscovery.capabilities['tools'],
        containsPair('listChanged', true),
      );
      expect(
        statelessDiscovery.capabilities['resources'],
        containsPair('subscribe', true),
      );

      await expectLater(
        statelessPublicMcpClient.callTool(
          'app.safe.deploy',
          id: 'stateless-mrtr-missing-capability',
          arguments: const <String, Object?>{'release': '1.2.3'},
        ),
        throwsA(
          isA<McpStreamableHttpException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.badRequest,
              )
              .having(
                (error) => (error.error?['error'] as Map?)?['code'],
                'error code',
                McpErrorCodes.missingRequiredClientCapability,
              ),
        ),
      );

      Future<McpFormElicitationResponse> answerDeploymentForm(
        McpFormElicitationRequest request,
      ) async {
        expect(request.inputRequestId, equals('deployment'));
        expect(request.message, equals('Confirm the deployment settings.'));
        return McpFormElicitationResponse.accept(const <String, Object?>{
          'email': 'operator@example.com',
          'replicas': 3,
        });
      }

      final statelessMrtrResult = await statelessPublicMcpClient
          .callToolWithFormElicitation(
            'app.safe.deploy',
            id: 'stateless-mrtr-streamable',
            arguments: const <String, Object?>{'release': '1.2.3'},
            onElicitation: answerDeploymentForm,
          );
      final directMrtrResult = await statelessPublicMcpClient
          .callToolDirectWithFormElicitation(
            'app.safe.deploy',
            id: 'stateless-mrtr-direct',
            arguments: const <String, Object?>{'release': '1.2.3'},
            onElicitation: answerDeploymentForm,
          );
      for (final result in [statelessMrtrResult, directMrtrResult]) {
        expect(result['isError'], isFalse);
        expect(
          (result['structuredContent'] as Map)['argumentsKeywords'],
          <String, Object?>{
            'status': 'ready',
            'release': '1.2.3',
            'inputResponses': <String, Object?>{
              'deployment': <String, Object?>{
                'action': 'accept',
                'content': <String, Object?>{
                  'email': 'operator@example.com',
                  'replicas': 3,
                },
              },
            },
            'requestState': 'router-opaque-round-1',
          },
        );
      }
      expect(mrtrCallDetails, hasLength(5));
      expect(
        mrtrCallDetails.first,
        isNot(contains(McpWampMrtrFields.clientCapabilities)),
      );
      for (final firstCallIndex in const <int>[1, 3]) {
        expect(
          mrtrCallDetails[firstCallIndex][McpWampMrtrFields.clientCapabilities],
          <String, Object?>{
            'elicitation': <String, Object?>{'form': <String, Object?>{}},
          },
        );
        expect(
          mrtrCallDetails[firstCallIndex + 1][McpWampMrtrFields.inputResponses],
          <String, Object?>{
            'deployment': <String, Object?>{
              'action': 'accept',
              'content': <String, Object?>{
                'email': 'operator@example.com',
                'replicas': 3,
              },
            },
          },
        );
        expect(
          mrtrCallDetails[firstCallIndex + 1][McpWampMrtrFields.requestState],
          equals('router-opaque-round-1'),
        );
      }
      expect(statelessPublicMcpClient.sessionId, isNull);

      final statelessSubscription = await statelessPublicMcpClient.listen(
        id: 'stateless-public-listen',
        toolsListChanged: true,
        promptsListChanged: true,
        resourcesListChanged: true,
        resourceSubscriptions: const <String>[
          'app://mcp/live-context',
          'app://mcp/member-context',
        ],
      );
      expect(
        statelessSubscription.acknowledgedNotifications.toolsListChanged,
        isTrue,
      );
      expect(
        statelessSubscription.acknowledgedNotifications.promptsListChanged,
        isFalse,
      );
      expect(
        statelessSubscription.acknowledgedNotifications.resourcesListChanged,
        isTrue,
      );
      expect(
        statelessSubscription.acknowledgedNotifications.resourceSubscriptions,
        equals(const <String>['app://mcp/live-context']),
      );
      final secondaryStatelessSubscription = await statelessPublicMcpClient
          .listen(
            id: 'stateless-public-listen-secondary',
            resourceSubscriptions: const <String>['app://mcp/live-context'],
          );
      expect(
        secondaryStatelessSubscription
            .acknowledgedNotifications
            .resourceSubscriptions,
        equals(const <String>['app://mcp/live-context']),
      );
      expect(statelessPublicMcpClient.sessionId, isNull);
      expect(statelessPublicMcpClient.lastEventId, isNull);

      final statelessNotifications = StreamIterator<Map<String, Object?>>(
        statelessSubscription.notifications,
      );
      final secondaryStatelessNotifications =
          StreamIterator<Map<String, Object?>>(
            secondaryStatelessSubscription.notifications,
          );
      final toolListChangedFuture = statelessNotifications.moveNext().timeout(
        const Duration(seconds: 5),
      );
      final lateSafeRegistration = await serviceSession.register(
        'app.safe.late_lookup',
      );
      lateSafeRegistration.onInvoke((invocation) {
        invocation.respondWith(argumentsKeywords: const {'status': 'ready'});
      });
      final refreshedStatelessTools = await statelessPublicMcpClient.listTools(
        id: 'stateless-public-tools-after-registration',
      );
      expect(
        refreshedStatelessTools.tools.map((tool) => tool['name']),
        contains('app.safe.late_lookup'),
      );
      expect(await toolListChangedFuture, isTrue);
      final toolListChanged = statelessNotifications.current;
      expect(
        toolListChanged['method'],
        equals('notifications/tools/list_changed'),
      );
      expect(
        ((toolListChanged['params'] as Map)['_meta']
            as Map)['io.modelcontextprotocol/subscriptionId'],
        equals('stateless-public-listen'),
      );

      final statelessResourceUpdateFuture = statelessNotifications
          .moveNext()
          .timeout(const Duration(seconds: 5));
      final secondaryResourceUpdateFuture = secondaryStatelessNotifications
          .moveNext()
          .timeout(const Duration(seconds: 5));
      await serviceSession.publish(
        'app.events.resource.context',
        argumentsKeywords: {'version': liveResourceVersion},
        options: core.PublishOptions(acknowledge: true),
      );
      expect(await statelessResourceUpdateFuture, isTrue);
      final statelessResourceUpdate = statelessNotifications.current;
      expect(
        statelessResourceUpdate['method'],
        equals('notifications/resources/updated'),
      );
      final statelessResourceUpdateParams =
          statelessResourceUpdate['params'] as Map<String, Object?>;
      expect(
        statelessResourceUpdateParams['uri'],
        equals('app://mcp/live-context'),
      );
      expect(
        (statelessResourceUpdateParams['_meta']
            as Map)['io.modelcontextprotocol/subscriptionId'],
        equals('stateless-public-listen'),
      );
      expect(await secondaryResourceUpdateFuture, isTrue);
      expect(
        ((secondaryStatelessNotifications.current['params'] as Map)['_meta']
            as Map)['io.modelcontextprotocol/subscriptionId'],
        equals('stateless-public-listen-secondary'),
      );
      final statelessResourceSubscriptionLookup = await statelessPublicMcpClient
          .lookupWampSubscriptionDirect(
            'app.events.resource.context',
            id: 'stateless-public-resource-subscription-lookup',
          );
      final statelessResourceSubscriptionId =
          (statelessResourceSubscriptionLookup.arguments.single as num).toInt();
      Future<int> statelessResourceSubscriberCount() async {
        final result = await statelessPublicMcpClient
            .countWampSubscriptionSubscribersDirect(
              statelessResourceSubscriptionId,
              id: 'stateless-public-resource-subscriber-count',
            );
        return (result.arguments.single as num).toInt();
      }

      expect(await statelessResourceSubscriberCount(), equals(1));
      await statelessNotifications.cancel();
      await statelessSubscription.close();
      expect(
        await statelessSubscription.closed,
        equals(McpSubscriptionCloseReason.local),
      );
      expect(statelessPublicMcpClient.sessionId, isNull);
      final secondaryUpdateAfterPrimaryClose = secondaryStatelessNotifications
          .moveNext()
          .timeout(const Duration(seconds: 5));
      await serviceSession.publish(
        'app.events.resource.context',
        argumentsKeywords: {'version': liveResourceVersion},
        options: core.PublishOptions(acknowledge: true),
      );
      expect(await secondaryUpdateAfterPrimaryClose, isTrue);
      var subscriberCountWithSecondaryListener = 0;
      for (var attempt = 0; attempt < 50; attempt++) {
        subscriberCountWithSecondaryListener =
            await statelessResourceSubscriberCount();
        if (subscriberCountWithSecondaryListener == 1) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(subscriberCountWithSecondaryListener, equals(1));

      final directPublicResourceTemplates = await directPublicMcpClient
          .listResourceTemplates(
            id: 'direct-public-resource-templates',
            directJson: true,
          );
      expect(
        directPublicResourceTemplates.resourceTemplates.map(
          (template) => template['uriTemplate'],
        ),
        contains('app://mcp/task/{taskId}'),
      );

      final directPublicPrompts = await directPublicMcpClient.listPrompts(
        id: 'direct-public-prompts',
        directJson: true,
      );
      expect(
        directPublicPrompts.prompts.map((prompt) => prompt['name']),
        contains('inspect-task'),
      );

      final directPublicPrompt = await directPublicMcpClient.getPrompt(
        'inspect-task',
        id: 'direct-public-prompt',
        arguments: {'taskId': 'T-direct-public'},
        directJson: true,
      );
      expect(jsonEncode(directPublicPrompt), contains('T-direct-public'));
      expect(directPublicMcpClient.sessionId, isNull);

      final directPublicRegistrationList = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.list',
        const {},
      );
      expect(directPublicRegistrationList['isError'], isFalse);
      final directPublicRegistrationListKwargs =
          (directPublicRegistrationList['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(directPublicRegistrationListKwargs['exact'], isNotEmpty);

      final directPublicSafeRegistration = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.match',
        {'procedure': 'app.safe.lookup'},
      );
      final directPublicSafeRegistrationIds =
          (directPublicSafeRegistration['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directPublicSafeRegistrationIds, isNotEmpty);
      final directPublicSafeRegistrationId =
          directPublicSafeRegistrationIds.single as int;

      final directPublicSafeRegistrationGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.get',
        {'id': directPublicSafeRegistrationId},
      );
      final directPublicSafeRegistrationDetails =
          (directPublicSafeRegistrationGet['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(
        directPublicSafeRegistrationDetails,
        containsPair('uri', 'app.safe.lookup'),
      );

      final directPublicSafeRegistrationCallees = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.list_callees',
        {'id': directPublicSafeRegistrationId},
      );
      final directPublicSafeCalleeIds =
          (directPublicSafeRegistrationCallees['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directPublicSafeCalleeIds, isEmpty);
      expect(
        directPublicSafeCalleeIds,
        isNot(contains(serviceSession.sessionId)),
      );

      final directPublicSafeCalleeCount = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.count_callees',
        {'id': directPublicSafeRegistrationId},
      );
      expect(
        (directPublicSafeCalleeCount['structuredContent']
            as Map<String, Object?>)['arguments'],
        equals([0]),
      );

      final directPublicUnsafeRegistration = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.match',
        {'procedure': 'app.unsafe.delete'},
      );
      final directPublicUnsafeRegistrationIds =
          (directPublicUnsafeRegistration['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directPublicUnsafeRegistrationIds, isEmpty);

      final directPublicSessionCount = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.session.count',
        const {},
      );
      final directPublicSessionCountKwargs =
          (directPublicSessionCount['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(directPublicSessionCountKwargs['count'], equals(1));

      final directPublicSessionList = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.session.list',
        const {},
      );
      final directPublicSessionIds =
          ((directPublicSessionList['structuredContent']
                      as Map<String, Object?>)['argumentsKeywords']
                  as Map<String, Object?>)['session_ids']
              as List;
      expect(directPublicSessionIds, hasLength(1));
      expect(directPublicSessionIds, isNot(contains(serviceSession.sessionId)));
      final directPublicSessionId = directPublicSessionIds.single as int;

      final directPublicSessionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.session.get',
        {'id': directPublicSessionId},
      );
      final directPublicSessionDetails =
          ((directPublicSessionGet['structuredContent']
                      as Map<String, Object?>)['argumentsKeywords']
                  as Map<String, Object?>)['details']
              as Map<String, Object?>;
      expect(directPublicSessionDetails['authid'], equals('anonymous'));
      expect(directPublicSessionDetails['authrole'], equals('anonymous'));

      final directPublicServiceSessionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.session.get',
        {'id': serviceSession.sessionId},
      );
      final directPublicServiceSessionGetArguments =
          (directPublicServiceSessionGet['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(
        directPublicServiceSessionGetArguments,
        contains('wamp.error.no_such_session'),
      );

      final streamableClient = McpStreamableHttpClient(
        Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/public',
        ),
      );
      addTearDown(() => streamableClient.close(force: true));

      final streamableInitialize = await streamableClient.initialize();
      expect(streamableInitialize['id'], equals('initialize'));
      expect(streamableClient.sessionId, isNotNull);
      final streamableCapabilities =
          ((streamableInitialize['result'] as Map)['capabilities'] as Map)
              .cast<String, Object?>();
      expect(
        streamableCapabilities['resources'],
        containsPair('subscribe', true),
      );
      await streamableClient.notifyInitialized();

      final streamablePing = await streamableClient.ping(id: 'streamable-ping');
      expect(streamablePing, isEmpty);

      final streamableTools = await streamableClient.listTools(
        id: 'streamable-tools',
      );
      final streamableToolNames = {
        for (final tool in streamableTools.tools) tool['name'] as String,
      };
      expect(streamableToolNames, contains('app.safe.lookup'));
      expect(streamableToolNames, isNot(contains('app.unsafe.delete')));
      expect(streamableClient.lastEventId, isNotNull);

      final streamableResources = await streamableClient.listResources(
        id: 'streamable-resources',
      );
      expect(
        streamableResources.resources.map((resource) => resource['uri']),
        containsAll(['app://mcp/context', 'app://mcp/live-context']),
      );

      final streamableLiveResource = await streamableClient.readResource(
        'app://mcp/live-context',
        id: 'streamable-live-resource-read',
      );
      expect(
        ((jsonDecode(streamableLiveResource.single['text'] as String)
                as Map)['argumentsKeywords']
            as Map)['version'],
        equals(1),
      );

      await streamableClient.subscribeResource(
        'app://mcp/live-context',
        id: 'streamable-live-resource-subscribe',
      );
      final publicStreamableSessionId = streamableClient.sessionId;
      await expectLater(
        streamableClient.subscribeResource(
          'app://mcp/member-context',
          id: 'streamable-member-resource-subscribe',
        ),
        throwsA(
          isA<McpJsonRpcException>()
              .having((error) => error.method, 'method', 'resources/subscribe')
              .having(
                (error) => error.error['code'],
                'code',
                McpErrorCodes.resourceNotFound,
              )
              .having(
                (error) => error.error['message'],
                'message',
                contains('Resource not found'),
              ),
        ),
      );
      expect(streamableClient.sessionId, publicStreamableSessionId);
      final modernUpdateWithStreamable = secondaryStatelessNotifications
          .moveNext()
          .timeout(const Duration(seconds: 5));
      liveResourceVersion = 2;
      await serviceSession.publish(
        'app.events.resource.context',
        argumentsKeywords: {'version': liveResourceVersion},
        options: core.PublishOptions(acknowledge: true),
      );
      expect(await modernUpdateWithStreamable, isTrue);
      expect(
        secondaryStatelessNotifications.current['method'],
        equals('notifications/resources/updated'),
      );
      final liveResourceUpdate = await _pollStreamableMcpUntilResourceUpdate(
        streamableClient,
        'app://mcp/live-context',
      );
      expect(
        liveResourceUpdate['method'],
        equals('notifications/resources/updated'),
      );
      final updatedLiveResource = await streamableClient.readResource(
        'app://mcp/live-context',
        id: 'streamable-live-resource-reread',
      );
      expect(
        ((jsonDecode(updatedLiveResource.single['text'] as String)
                as Map)['argumentsKeywords']
            as Map)['version'],
        equals(2),
      );
      await streamableClient.unsubscribeResource(
        'app://mcp/live-context',
        id: 'streamable-live-resource-unsubscribe',
      );
      final modernUpdateAfterStreamableUnsubscribe =
          secondaryStatelessNotifications.moveNext().timeout(
            const Duration(seconds: 5),
          );
      liveResourceVersion = 3;
      await serviceSession.publish(
        'app.events.resource.context',
        argumentsKeywords: {'version': liveResourceVersion},
        options: core.PublishOptions(acknowledge: true),
      );
      expect(await modernUpdateAfterStreamableUnsubscribe, isTrue);

      await streamableClient.subscribeResource(
        'app://mcp/live-context',
        id: 'streamable-live-resource-resubscribe',
      );
      await secondaryStatelessNotifications.cancel();
      await secondaryStatelessSubscription.close();
      expect(
        await secondaryStatelessSubscription.closed,
        equals(McpSubscriptionCloseReason.local),
      );
      liveResourceVersion = 4;
      await serviceSession.publish(
        'app.events.resource.context',
        argumentsKeywords: {'version': liveResourceVersion},
        options: core.PublishOptions(acknowledge: true),
      );
      final streamableUpdateAfterModernClose =
          await _pollStreamableMcpUntilResourceUpdate(
            streamableClient,
            'app://mcp/live-context',
          );
      expect(
        streamableUpdateAfterModernClose['method'],
        equals('notifications/resources/updated'),
      );
      await streamableClient.unsubscribeResource(
        'app://mcp/live-context',
        id: 'streamable-live-resource-final-unsubscribe',
      );
      var subscriberCountAfterClose = 1;
      for (var attempt = 0; attempt < 50; attempt++) {
        await serviceSession.publish(
          'app.events.resource.context',
          argumentsKeywords: {'version': liveResourceVersion},
          options: core.PublishOptions(acknowledge: true),
        );
        subscriberCountAfterClose = await statelessResourceSubscriberCount();
        if (subscriberCountAfterClose == 0) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(subscriberCountAfterClose, equals(0));

      final streamableTemplates = await streamableClient.listResourceTemplates(
        id: 'streamable-resource-templates',
      );
      expect(
        streamableTemplates.resourceTemplates.map(
          (template) => template['uriTemplate'],
        ),
        contains('app://mcp/task/{taskId}'),
      );

      final streamablePrompt = await streamableClient.getPrompt(
        'inspect-task',
        id: 'streamable-prompt',
        arguments: {'taskId': 'T-streamable-prompt'},
      );
      expect(jsonEncode(streamablePrompt), contains('T-streamable-prompt'));

      final streamableTopicCatalogResult = await streamableClient.callTool(
        'connectanum.api.list',
        id: 'streamable-topic-catalog',
        arguments: {'kind': 'topic'},
      );
      expect(streamableTopicCatalogResult['isError'], isFalse);
      final streamableTopicCatalogJson = jsonEncode(
        streamableTopicCatalogResult['structuredContent'],
      );
      expect(streamableTopicCatalogJson, contains('app.events.audit'));
      expect(streamableTopicCatalogJson, contains('app.events.readonly'));
      expect(streamableTopicCatalogJson, isNot(contains('app.secure.audit')));

      final streamableReadOnlyTopic = await streamableClient.callTool(
        'connectanum.api.describe',
        id: 'streamable-readonly-topic',
        arguments: {'uri': 'app.events.readonly'},
      );
      final streamableReadOnlyTopicDetails =
          streamableReadOnlyTopic['structuredContent'] as Map<String, Object?>;
      expect(streamableReadOnlyTopicDetails['allowPublish'], isFalse);
      expect(streamableReadOnlyTopicDetails['allowSubscribe'], isTrue);

      final streamableSafeRegistration = await streamableClient
          .matchWampRegistration(
            'app.safe.lookup',
            id: 'streamable-registration-match',
          );
      expect(
        streamableSafeRegistration.arguments,
        equals([directPublicSafeRegistrationId]),
      );

      final streamableUnsafeRegistration = await streamableClient
          .matchWampRegistration(
            'app.unsafe.delete',
            id: 'streamable-unsafe-registration-match',
          );
      expect(streamableUnsafeRegistration.arguments, isEmpty);

      final streamableSafeResult = await streamableClient.callTool(
        'app.safe.lookup',
        id: 'streamable-safe',
        arguments: {'taskId': 'T-streamable'},
      );
      expect(streamableSafeResult['isError'], isFalse);
      expect(
        (((streamableSafeResult['structuredContent']
                    as Map)['argumentsKeywords']
                as Map)['request']
            as Map)['taskId'],
        equals('T-streamable'),
      );

      final crossEraDirectSubscription = await directPublicMcpClient
          .subscribeWampTopicDirect(
            'app.events.audit',
            id: 'cross-era-direct-pubsub-subscribe',
            queueLimit: 5,
          );
      final crossEraDirectHandle = crossEraDirectSubscription.handle;
      final crossEraSubscriptionId = crossEraDirectSubscription.subscriptionId!;
      expect(directPublicMcpClient.sessionId, isNull);
      expect(directPublicMcpClient.lastEventId, isNull);

      final streamableSubscribe = await streamableClient.request(
        'tools/call',
        id: 'streamable-pubsub-subscribe',
        params: {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.events.audit', 'queueLimit': 5},
        },
      );
      final streamableSubscription =
          ((streamableSubscribe['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      final streamableHandle = streamableSubscription['handle'] as String;
      expect(streamableSubscription['topic'], equals('app.events.audit'));
      expect(
        streamableSubscription['subscriptionId'],
        equals(crossEraSubscriptionId),
      );
      final crossEraStreamableSessionId = streamableClient.sessionId;
      expect(crossEraStreamableSessionId, isNotNull);

      final streamableSubscriptionLookup = await streamableClient
          .lookupWampSubscription(
            'app.events.audit',
            id: 'streamable-subscription-lookup',
          );
      expect(streamableSubscriptionLookup.arguments, isNotEmpty);

      final streamablePublish = await streamableClient.request(
        'tools/call',
        id: 'streamable-pubsub-publish',
        params: {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': 'app.events.audit',
            'argumentsKeywords': {'via': 'cross-era-shared-publish'},
            'acknowledge': true,
            'options': {'exclude_me': false},
          },
        },
      );
      final streamablePublishResult =
          ((streamablePublish['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      expect(streamablePublishResult['acknowledged'], isTrue);

      final directCrossEraPoll = await _pollDirectRouterJsonUntilEvents(
        client,
        listener.port,
        '/mcp/public',
        crossEraDirectHandle,
      );
      expect(
        jsonEncode(directCrossEraPoll['events']),
        contains('cross-era-shared-publish'),
      );
      final streamableCrossEraPoll = await _pollStreamableMcpUntilEvents(
        streamableClient,
        streamableHandle,
      );
      expect(
        jsonEncode(streamableCrossEraPoll['events']),
        contains('cross-era-shared-publish'),
      );

      final streamableReadOnlyPublish = await streamableClient.request(
        'tools/call',
        id: 'streamable-readonly-publish',
        params: {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': 'app.events.readonly',
            'argumentsKeywords': {'via': 'streamable-readonly'},
            'acknowledge': true,
          },
        },
      );
      final streamableReadOnlyPublishResult =
          (streamableReadOnlyPublish['result'] as Map).cast<String, Object?>();
      expect(streamableReadOnlyPublishResult['isError'], isTrue);
      expect(
        jsonEncode(streamableReadOnlyPublishResult),
        contains('not publishable'),
      );

      final streamableUnsubscribe = await streamableClient.request(
        'tools/call',
        id: 'streamable-pubsub-unsubscribe',
        params: {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': streamableHandle},
        },
      );
      final streamableUnsubscribeResult =
          ((streamableUnsubscribe['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      expect(streamableUnsubscribeResult['unsubscribed'], isTrue);

      await serviceSession.publish(
        'app.events.audit',
        argumentsKeywords: {'via': 'after-streamable-unsubscribe'},
        options: core.PublishOptions(acknowledge: true),
      );
      final directAfterStreamableUnsubscribe =
          await _pollDirectRouterJsonUntilEvents(
            client,
            listener.port,
            '/mcp/public',
            crossEraDirectHandle,
          );
      expect(
        jsonEncode(directAfterStreamableUnsubscribe['events']),
        contains('after-streamable-unsubscribe'),
      );

      final streamableResubscribe = await streamableClient.request(
        'tools/call',
        id: 'streamable-pubsub-resubscribe',
        params: {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.events.audit', 'queueLimit': 5},
        },
      );
      final streamableResubscription =
          ((streamableResubscribe['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      final streamableResubscriptionHandle =
          streamableResubscription['handle'] as String;
      expect(
        streamableResubscription['subscriptionId'],
        equals(crossEraSubscriptionId),
      );

      final directCrossEraUnsubscribe = await directPublicMcpClient
          .unsubscribeWampTopicDirect(
            crossEraDirectHandle,
            id: 'cross-era-direct-pubsub-unsubscribe',
          );
      expect(directCrossEraUnsubscribe.unsubscribed, isTrue);
      expect(directPublicMcpClient.sessionId, isNull);
      expect(directPublicMcpClient.lastEventId, isNull);
      expect(streamableClient.sessionId, crossEraStreamableSessionId);

      await serviceSession.publish(
        'app.events.audit',
        argumentsKeywords: {'via': 'after-direct-unsubscribe'},
        options: core.PublishOptions(acknowledge: true),
      );
      final streamableAfterDirectUnsubscribe =
          await _pollStreamableMcpUntilEvents(
            streamableClient,
            streamableResubscriptionHandle,
          );
      expect(
        jsonEncode(streamableAfterDirectUnsubscribe['events']),
        contains('after-direct-unsubscribe'),
      );

      final streamableFinalUnsubscribe = await streamableClient.request(
        'tools/call',
        id: 'streamable-pubsub-final-unsubscribe',
        params: {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': streamableResubscriptionHandle},
        },
      );
      final streamableFinalUnsubscribeResult =
          ((streamableFinalUnsubscribe['result'] as Map)['structuredContent']
                  as Map)
              .cast<String, Object?>();
      expect(streamableFinalUnsubscribeResult['unsubscribed'], isTrue);
      expect(streamableClient.sessionId, crossEraStreamableSessionId);

      List<Object?> remainingCrossEraSubscribers = const <Object?>[1];
      for (var attempt = 0; attempt < 50; attempt++) {
        final count = await directPublicMcpClient
            .countWampSubscriptionSubscribersDirect(
              crossEraSubscriptionId,
              id: 'cross-era-subscription-final-count-$attempt',
            );
        remainingCrossEraSubscribers = count.arguments;
        if (remainingCrossEraSubscribers.length == 1 &&
            remainingCrossEraSubscribers.single == 0) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(remainingCrossEraSubscribers, equals([0]));

      final streamableSecureTopicDenied = await streamableClient.request(
        'tools/call',
        id: 'streamable-secure-topic-denied',
        params: {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.secure.audit', 'queueLimit': 5},
        },
      );
      final streamableSecureTopicDeniedResult =
          (streamableSecureTopicDenied['result'] as Map)
              .cast<String, Object?>();
      expect(streamableSecureTopicDeniedResult['isError'], isTrue);
      expect(
        jsonEncode(streamableSecureTopicDeniedResult),
        contains('Unknown declared WAMP topic: app.secure.audit'),
      );

      final directSafeResult = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'app.safe.lookup',
        {'taskId': 'T-json'},
      );
      expect(directSafeResult['isError'], isFalse);
      expect(
        ((directSafeResult['structuredContent'] as Map)['argumentsKeywords']
            as Map)['status'],
        equals('open'),
      );
      await _expectDirectSafeLookupNotifications(
        directPublicMcpClient,
        observedSafeLookupTaskIds,
        label: 'direct-public',
      );

      final directBatch = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          {
            'jsonrpc': '2.0',
            'id': 'batch-catalog',
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
          {
            'jsonrpc': '2.0',
            'id': 'batch-safe',
            'method': 'app.safe.lookup',
            'params': {'taskId': 'T-batch'},
          },
          {
            'jsonrpc': '2.0',
            'id': 'batch-resources',
            'method': 'resources/list',
            'params': {},
          },
          {
            'jsonrpc': '2.0',
            'id': 'batch-prompt',
            'method': 'prompts/get',
            'params': {
              'name': 'inspect-task',
              'arguments': {'taskId': 'T-batch-prompt'},
            },
          },
          {
            'jsonrpc': '2.0',
            'method': 'connectanum.tool.call',
            'params': {
              'name': 'app.safe.lookup',
              'arguments': {'taskId': 'T-batch-notification'},
            },
          },
        ],
      );
      expect(directBatch.statusCode, equals(HttpStatus.ok));
      expect(directBatch.json, isA<List<Object?>>());
      final directBatchResponses = (directBatch.json as List)
          .cast<Map<String, Object?>>();
      expect(directBatchResponses, hasLength(4));
      expect(directBatchResponses[0]['id'], equals('batch-catalog'));
      expect(
        jsonEncode(directBatchResponses[0]['result']),
        contains('app.safe.lookup'),
      );
      expect(directBatchResponses[1]['id'], equals('batch-safe'));
      expect(
        (((directBatchResponses[1]['result'] as Map)['structuredContent']
                as Map)['argumentsKeywords']
            as Map)['status'],
        equals('open'),
      );
      expect(directBatchResponses[2]['id'], equals('batch-resources'));
      expect(
        jsonEncode(directBatchResponses[2]['result']),
        contains('app://mcp/context'),
      );
      expect(directBatchResponses[3]['id'], equals('batch-prompt'));
      expect(
        jsonEncode(directBatchResponses[3]['result']),
        contains('T-batch-prompt'),
      );

      final directBatchWithError = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          {
            'jsonrpc': '2.0',
            'id': 'batch-ok',
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
          {
            'jsonrpc': '2.0',
            'id': 'batch-unknown',
            'method': 'consumer.unknown.method',
            'params': {},
          },
          {
            'jsonrpc': '2.0',
            'method': 'connectanum.tool.call',
            'params': {
              'name': 'app.safe.lookup',
              'arguments': {'taskId': 'T-batch-notification'},
            },
          },
        ],
      );
      expect(directBatchWithError.statusCode, equals(HttpStatus.ok));
      expect(directBatchWithError.json, isA<List<Object?>>());
      final directBatchWithErrorResponses = (directBatchWithError.json as List)
          .cast<Map<String, Object?>>();
      expect(directBatchWithErrorResponses, hasLength(2));
      expect(directBatchWithErrorResponses[0]['id'], equals('batch-ok'));
      expect(
        jsonEncode(directBatchWithErrorResponses[0]['result']),
        contains('app.safe.lookup'),
      );
      expect(directBatchWithErrorResponses[1]['id'], equals('batch-unknown'));
      expect(
        (directBatchWithErrorResponses[1]['error'] as Map)['code'],
        equals(-32601),
      );
      expect(
        jsonEncode(directBatchWithErrorResponses[1]['error']),
        contains('Unknown MCP method'),
      );

      final directBatchWithMalformedMethod = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          {
            'jsonrpc': '2.0',
            'id': 'batch-valid-before-malformed',
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
          {
            'jsonrpc': '2.0',
            'id': 'batch-malformed-method',
            'method': 'tools/list\n',
            'params': {},
          },
        ],
      );
      expect(directBatchWithMalformedMethod.statusCode, equals(HttpStatus.ok));
      expect(directBatchWithMalformedMethod.json, isA<List<Object?>>());
      final directBatchWithMalformedMethodResponses =
          (directBatchWithMalformedMethod.json as List)
              .cast<Map<String, Object?>>();
      expect(directBatchWithMalformedMethodResponses, hasLength(2));
      expect(
        directBatchWithMalformedMethodResponses[0]['id'],
        equals('batch-valid-before-malformed'),
      );
      expect(
        jsonEncode(directBatchWithMalformedMethodResponses[0]['result']),
        contains('app.safe.lookup'),
      );
      expect(
        directBatchWithMalformedMethodResponses[1]['id'],
        equals('batch-malformed-method'),
      );
      expect(
        (directBatchWithMalformedMethodResponses[1]['error'] as Map)['code'],
        equals(-32600),
      );
      expect(
        jsonEncode(directBatchWithMalformedMethodResponses[1]['error']),
        contains('method must not contain whitespace or control characters'),
      );

      final directDuplicateBatchId = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          {
            'jsonrpc': '2.0',
            'id': 'duplicate-batch',
            'method': 'app.safe.lookup',
            'params': {'taskId': 'T-duplicate-batch'},
          },
          {
            'jsonrpc': '2.0',
            'id': 'duplicate-batch',
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
        ],
      );
      expect(directDuplicateBatchId.statusCode, equals(HttpStatus.ok));
      expect(directDuplicateBatchId.json, isA<Map<String, Object?>>());
      final directDuplicateBatchJson =
          directDuplicateBatchId.json as Map<String, Object?>;
      final directDuplicateBatchError =
          directDuplicateBatchJson['error'] as Map<String, Object?>;
      expect(directDuplicateBatchJson['id'], isNull);
      expect(directDuplicateBatchError['code'], equals(-32600));
      expect(
        directDuplicateBatchError['message'],
        contains('duplicate request id duplicate-batch'),
      );
      expect(observedSafeLookupTaskIds, isNot(contains('T-duplicate-batch')));

      final directInvalidNotification = await _postJson(
        client,
        listener.port,
        '/mcp/public',
        {
          'jsonrpc': '2.0',
          'method': 'connectanum.tool.call',
          'params': {
            'arguments': {'taskId': 'T-invalid-notification'},
          },
        },
      );
      expect(directInvalidNotification.statusCode, equals(HttpStatus.accepted));
      expect(directInvalidNotification.body, isEmpty);
      expect(directInvalidNotification.json, isNull);

      final directBatchInvalidNotification = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          {
            'jsonrpc': '2.0',
            'method': 'connectanum.tool.call',
            'params': {
              'arguments': {'taskId': 'T-batch-invalid-notification'},
            },
          },
          {
            'jsonrpc': '2.0',
            'id': 'batch-after-invalid-notification',
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
        ],
      );
      expect(directBatchInvalidNotification.statusCode, equals(HttpStatus.ok));
      expect(directBatchInvalidNotification.json, isA<List<Object?>>());
      final directBatchInvalidNotificationResponses =
          (directBatchInvalidNotification.json as List)
              .cast<Map<String, Object?>>();
      expect(directBatchInvalidNotificationResponses, hasLength(1));
      expect(
        directBatchInvalidNotificationResponses.single['id'],
        equals('batch-after-invalid-notification'),
      );
      expect(
        jsonEncode(directBatchInvalidNotificationResponses.single['result']),
        contains('app.safe.lookup'),
      );

      final directNotificationOnlyBatch = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          {
            'jsonrpc': '2.0',
            'method': 'connectanum.tool.call',
            'params': {
              'name': 'app.safe.lookup',
              'arguments': {'taskId': 'T-notification-only-batch'},
            },
          },
          {
            'jsonrpc': '2.0',
            'method': 'connectanum.tool.call',
            'params': {
              'arguments': {'taskId': 'T-invalid-notification-only-batch'},
            },
          },
        ],
      );
      expect(
        directNotificationOnlyBatch.statusCode,
        equals(HttpStatus.accepted),
      );
      expect(directNotificationOnlyBatch.headers['mcp-session-id'], isNull);
      expect(directNotificationOnlyBatch.body, isEmpty);
      expect(directNotificationOnlyBatch.json, isNull);
      await _expectSafeLookupObserved(
        observedSafeLookupTaskIds,
        'T-notification-only-batch',
        label: 'public notification-only batch',
      );
      expect(
        observedSafeLookupTaskIds,
        isNot(contains('T-invalid-notification-only-batch')),
      );

      final nestedBatch = await _postJsonValue(
        client,
        listener.port,
        '/mcp/public',
        [
          [
            {
              'jsonrpc': '2.0',
              'id': 'nested-batch',
              'method': 'connectanum.api.list',
            },
          ],
        ],
      );
      expect(nestedBatch.statusCode, equals(HttpStatus.ok));
      expect(nestedBatch.json, isA<List<Object?>>());
      final nestedBatchResponses = (nestedBatch.json as List)
          .cast<Map<String, Object?>>();
      expect(nestedBatchResponses, hasLength(1));
      expect(nestedBatchResponses.single['id'], isNull);
      expect(
        (nestedBatchResponses.single['error'] as Map)['code'],
        equals(-32600),
      );

      final directPubSubSubscription = await directPublicMcpClient
          .subscribeWampTopic(
            'app.events.audit',
            id: 'direct-pubsub-subscribe',
            queueLimit: 5,
            directJson: true,
          );
      final directPubSubHandle = directPubSubSubscription.handle;
      expect(directPubSubSubscription.topic, equals('app.events.audit'));

      final directPublicSubscriptionList = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.list',
        const {},
      );
      final directPublicSubscriptionListKwargs =
          (directPublicSubscriptionList['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(directPublicSubscriptionListKwargs['exact'], isNotEmpty);

      final directPublicSubscriptionLookup = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.lookup',
        {'topic': 'app.events.audit'},
      );
      final directPublicSubscriptionLookupIds =
          (directPublicSubscriptionLookup['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directPublicSubscriptionLookupIds, isNotEmpty);
      final directPublicSubscriptionId =
          directPublicSubscriptionLookupIds.single as int;

      final directPublicSubscriptionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.get',
        {'id': directPublicSubscriptionId},
      );
      final directPublicSubscriptionDetails =
          (directPublicSubscriptionGet['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(
        directPublicSubscriptionDetails,
        containsPair('uri', 'app.events.audit'),
      );

      final directPublicSubscriptionSubscribers = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.list_subscribers',
        {'id': directPublicSubscriptionId},
      );
      final directPublicSubscriberIds =
          (directPublicSubscriptionSubscribers['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directPublicSubscriberIds, contains(directPublicSessionId));
      expect(
        directPublicSubscriberIds,
        isNot(contains(serviceSession.sessionId)),
      );
      expect(directPublicSubscriberIds, hasLength(1));

      final directPublicSubscriptionSubscriberCount =
          await _callRouterJsonMethod(
            client,
            listener.port,
            '/mcp/public',
            'wamp.subscription.count_subscribers',
            {'id': directPublicSubscriptionId},
          );
      expect(
        (directPublicSubscriptionSubscriberCount['structuredContent']
            as Map<String, Object?>)['arguments'],
        equals([1]),
      );

      final configuredReadOnlySubscriptionLookup = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.lookup',
        {'topic': 'app.events.readonly'},
      );
      final configuredReadOnlySubscriptionIds =
          (configuredReadOnlySubscriptionLookup['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(configuredReadOnlySubscriptionIds, hasLength(1));
      final configuredReadOnlySubscriptionId =
          (configuredReadOnlySubscriptionIds.single as num).toInt();
      expect(configuredReadOnlySubscriptionId, greaterThan(0));
      final lateLiveSubscription = await serviceSession.subscribe(
        'app.events.late',
      );
      expect(
        lateLiveSubscription.subscriptionId,
        isNot(equals(configuredReadOnlySubscriptionId)),
      );

      final configuredReadOnlySubscriptionMatch = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.match',
        {'topic': 'app.events.readonly'},
      );
      expect(
        (configuredReadOnlySubscriptionMatch['structuredContent']
            as Map<String, Object?>)['arguments'],
        contains(configuredReadOnlySubscriptionId),
      );

      final configuredReadOnlySubscriptionList = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.list',
        const {},
      );
      final configuredReadOnlySubscriptionExactIds =
          ((configuredReadOnlySubscriptionList['structuredContent']
                      as Map<String, Object?>)['argumentsKeywords']
                  as Map<String, Object?>)['exact']
              as List;
      expect(
        configuredReadOnlySubscriptionExactIds,
        contains(configuredReadOnlySubscriptionId),
      );

      final configuredReadOnlySubscriptionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.get',
        {'id': configuredReadOnlySubscriptionId},
      );
      final configuredReadOnlySubscriptionDetails =
          (configuredReadOnlySubscriptionGet['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(
        configuredReadOnlySubscriptionDetails,
        containsPair('uri', 'app.events.readonly'),
      );

      final configuredReadOnlySubscribers = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.list_subscribers',
        {'id': configuredReadOnlySubscriptionId},
      );
      expect(
        (configuredReadOnlySubscribers['structuredContent']
            as Map<String, Object?>)['arguments'],
        isEmpty,
      );

      final configuredReadOnlySubscriberCount = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.count_subscribers',
        {'id': configuredReadOnlySubscriptionId},
      );
      expect(
        (configuredReadOnlySubscriberCount['structuredContent']
            as Map<String, Object?>)['arguments'],
        equals([0]),
      );

      final directPubSubPublish = await directPublicMcpClient.publishWampEvent(
        'app.events.audit',
        id: 'direct-pubsub-publish',
        argumentsKeywords: const <String, Object?>{
          'via': 'direct-json-publish',
        },
        acknowledge: true,
        directJson: true,
      );
      expect(directPubSubPublish.acknowledged, isTrue);

      final directReadOnlyTopic = await _callMcpTool(
        client,
        listener.port,
        '/mcp/public',
        'connectanum.api.describe',
        {'uri': 'app.events.readonly'},
      );
      final directReadOnlyTopicDetails =
          directReadOnlyTopic['structuredContent'] as Map<String, Object?>;
      expect(directReadOnlyTopicDetails['allowPublish'], isFalse);
      expect(directReadOnlyTopicDetails['allowSubscribe'], isTrue);

      final directReadOnlyPublish = await _postJson(
        client,
        listener.port,
        '/mcp/public',
        {
          'jsonrpc': '2.0',
          'id': 'direct-readonly-publish',
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': 'app.events.readonly',
            'argumentsKeywords': {'via': 'direct-readonly'},
            'acknowledge': true,
          },
        },
      );
      expect(directReadOnlyPublish.statusCode, equals(HttpStatus.ok));
      final directReadOnlyPublishResult =
          (directReadOnlyPublish.json?['result'] as Map)
              .cast<String, Object?>();
      expect(directReadOnlyPublishResult['isError'], isTrue);
      expect(
        jsonEncode(directReadOnlyPublishResult),
        contains('not publishable'),
      );

      await serviceSession.publish(
        'app.events.audit',
        argumentsKeywords: {'via': 'direct-json-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final directPubSubPoll = await _pollDirectRouterJsonUntilEvents(
        client,
        listener.port,
        '/mcp/public',
        directPubSubHandle,
      );
      expect(
        jsonEncode(directPubSubPoll['events']),
        contains('direct-json-service'),
      );

      final directPubSubUnsubscribe = await directPublicMcpClient
          .unsubscribeWampTopic(
            directPubSubHandle,
            id: 'direct-pubsub-unsubscribe',
            directJson: true,
          );
      expect(directPubSubUnsubscribe.unsubscribed, isTrue);

      final directSecureTopicDenied = await _postJson(
        client,
        listener.port,
        '/mcp/public',
        {
          'jsonrpc': '2.0',
          'id': 'direct-secure-topic-denied',
          'method': 'connectanum.pubsub.subscribe',
          'params': {'topic': 'app.secure.audit', 'queueLimit': 5},
        },
      );
      expect(directSecureTopicDenied.statusCode, equals(HttpStatus.ok));
      final directSecureTopicDeniedResult =
          (directSecureTopicDenied.json?['result'] as Map)
              .cast<String, Object?>();
      expect(directSecureTopicDeniedResult['isError'], isTrue);
      expect(
        jsonEncode(directSecureTopicDeniedResult),
        contains('Unknown declared WAMP topic: app.secure.audit'),
      );

      final directUnsafeResult = await _postJson(
        client,
        listener.port,
        '/mcp/public',
        {
          'jsonrpc': '2.0',
          'id': 'direct-unsafe-denied',
          'method': 'connectanum.tool.call',
          'params': {
            'name': 'app.unsafe.delete',
            'arguments': {'taskId': 'T-json'},
          },
        },
      );
      expect(directUnsafeResult.statusCode, equals(HttpStatus.ok));
      expect(directUnsafeResult.json?['error'], isA<Map<String, Object?>>());
      expect(
        jsonEncode(directUnsafeResult.json?['error']),
        contains('Unknown MCP'),
      );

      final directUnsafeMethodResult = await _postJson(
        client,
        listener.port,
        '/mcp/public',
        {
          'jsonrpc': '2.0',
          'id': 'direct-unsafe-method-denied',
          'method': 'app.unsafe.delete',
          'params': {'taskId': 'T-json'},
        },
      );
      expect(directUnsafeMethodResult.statusCode, equals(HttpStatus.ok));
      expect(
        directUnsafeMethodResult.json?['error'],
        isA<Map<String, Object?>>(),
      );
      expect(
        jsonEncode(directUnsafeMethodResult.json?['error']),
        contains('Unknown MCP'),
      );

      await _initializeMcp(client, listener.port, '/mcp/public');
      final tools = await _listMcpTools(client, listener.port, '/mcp/public');
      final toolByName = {
        for (final tool in tools) tool['name'] as String: tool,
      };
      expect(toolByName, contains('app.safe.lookup'));
      expect(toolByName, isNot(contains('app.unsafe.delete')));
      expect(toolByName, isNot(contains('app.documented.only')));
      expect(
        toolByName['app.safe.lookup']?['annotations'],
        containsPair('readOnlyHint', true),
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

      final publicUnsafeResult = await _postJson(
        client,
        listener.port,
        '/mcp/public',
        {
          'jsonrpc': '2.0',
          'id': 'public-unsafe-denied',
          'method': 'tools/call',
          'params': {
            'name': 'app.unsafe.delete',
            'arguments': {'taskId': 'T-1'},
          },
        },
      );
      expect(publicUnsafeResult.statusCode, equals(HttpStatus.ok));
      expect(publicUnsafeResult.json?['error'], isA<Map<String, Object?>>());
      expect(
        jsonEncode(publicUnsafeResult.json?['error']),
        contains('Unknown MCP'),
      );

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

      final documentedRegistrationLookup = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.lookup',
        {'uri': 'app.documented.only'},
      );
      final documentedRegistrationIds =
          (documentedRegistrationLookup['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(documentedRegistrationIds, hasLength(1));
      final documentedRegistrationId = (documentedRegistrationIds.single as num)
          .toInt();
      expect(documentedRegistrationId, greaterThan(0));
      final lateLiveRegistration = await serviceSession.register(
        'app.late.live',
      );
      expect(
        lateLiveRegistration.registrationId,
        isNot(equals(documentedRegistrationId)),
      );

      final documentedRegistrationList = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.list',
        const {},
      );
      final documentedRegistrationExactIds =
          ((documentedRegistrationList['structuredContent']
                      as Map<String, Object?>)['argumentsKeywords']
                  as Map<String, Object?>)['exact']
              as List;
      expect(
        documentedRegistrationExactIds,
        contains(documentedRegistrationId),
      );

      final documentedRegistrationGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.get',
        {'id': documentedRegistrationId},
      );
      final documentedRegistrationDetails =
          (documentedRegistrationGet['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(
        documentedRegistrationDetails,
        containsPair('uri', 'app.documented.only'),
      );

      final documentedRegistrationCallees = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.list_callees',
        {'id': documentedRegistrationId},
      );
      expect(
        (documentedRegistrationCallees['structuredContent']
            as Map<String, Object?>)['arguments'],
        isEmpty,
      );

      final documentedRegistrationCalleeCount = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.registration.count_callees',
        {'id': documentedRegistrationId},
      );
      expect(
        (documentedRegistrationCalleeCount['structuredContent']
            as Map<String, Object?>)['arguments'],
        equals([0]),
      );

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
      expect(
        unauthorized.headers['www-authenticate'],
        allOf(
          contains('scope="mcp:read mcp:write"'),
          contains('resource_metadata="https://mcp.example.test/mcp/secure"'),
        ),
      );

      final metadataRequest = await client.get(
        '127.0.0.1',
        listener.port,
        '/mcp/secure',
      );
      metadataRequest.headers.set(
        HttpHeaders.acceptHeader,
        ContentType.json.mimeType,
      );
      final metadataOrigin = 'http://127.0.0.1:${listener.port}';
      metadataRequest.headers.set('origin', metadataOrigin);
      final metadataResponse = await _readJsonHttpResponse(
        await metadataRequest.close(),
      );
      expect(metadataResponse.statusCode, equals(HttpStatus.ok));
      expect(
        metadataResponse.json,
        equals(<String, Object?>{
          'resource': 'https://mcp.example.test/mcp/secure',
          'authorization_servers': <Object?>['https://auth.example.test'],
          'scopes_supported': <Object?>['mcp:read', 'mcp:write'],
          'resource_name': 'Connectanum MCP',
          'bearer_methods_supported': <Object?>['header'],
        }),
      );
      expect(metadataResponse.headers, isNot(contains('mcp-session-id')));
      expect(
        metadataResponse.headers['access-control-allow-origin'],
        equals(metadataOrigin),
      );

      final unauthorizedSse = await client.get(
        '127.0.0.1',
        listener.port,
        '/mcp/secure',
      );
      unauthorizedSse.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream',
      );
      final unauthorizedSseResponse = await _readJsonHttpResponse(
        await unauthorizedSse.close(),
      );
      expect(
        unauthorizedSseResponse.statusCode,
        equals(HttpStatus.unauthorized),
      );

      final unauthorizedDirectResources =
          await _postJson(client, listener.port, '/mcp/secure', {
            'jsonrpc': '2.0',
            'id': 'secure-direct-resources-unauthorized',
            'method': 'resources/list',
            'params': {},
          });
      expect(
        unauthorizedDirectResources.statusCode,
        equals(HttpStatus.unauthorized),
      );

      final unauthorizedJsonPost = await _postJson(
        client,
        listener.port,
        '/mcp/secure-json-post',
        {
          'jsonrpc': '2.0',
          'id': 'secure-json-post-unauthorized',
          'method': 'initialize',
          'params': {'protocolVersion': '2025-11-25'},
        },
      );
      expect(unauthorizedJsonPost.statusCode, equals(HttpStatus.unauthorized));
      expect(unauthorizedJsonPost.headers, isNot(contains('mcp-session-id')));

      final unknownBearerJsonPost = await _postJson(
        client,
        listener.port,
        '/mcp/secure',
        {
          'jsonrpc': '2.0',
          'id': 'secure-unknown-bearer',
          'method': 'tools/list',
          'params': {},
        },
        headers: {'authorization': 'Bearer unknown-access-token'},
      );
      expect(unknownBearerJsonPost.statusCode, equals(HttpStatus.unauthorized));
      expect(unknownBearerJsonPost.headers, isNot(contains('mcp-session-id')));
      expect(
        unknownBearerJsonPost.headers['www-authenticate'],
        allOf(
          contains('scope="mcp:read mcp:write"'),
          contains('resource_metadata="https://mcp.example.test/mcp/secure"'),
        ),
      );

      final grant = await _issueTicketHttpGrant(client, listener.port);
      final otherGrant = await _issueTicketHttpGrant(
        client,
        listener.port,
        authId: 'user-2',
      );
      final authHeaders = {'authorization': 'bearer ${grant.accessToken}'};
      final otherAuthHeaders = {
        'authorization': 'Bearer ${otherGrant.accessToken}',
      };
      final directSecureMcpClient = McpStreamableHttpClient.withAuthGrant(
        Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/secure',
        ),
        grant,
      );
      addTearDown(() => directSecureMcpClient.close(force: true));

      final directSecureCatalog = await directSecureMcpClient.listWampApi(
        id: 'direct-secure-catalog',
        kind: 'procedure',
        directJson: true,
      );
      expect(jsonEncode(directSecureCatalog), contains('app.unsafe.delete'));

      final directSecureResources = await directSecureMcpClient.listResources(
        id: 'direct-secure-resources',
        directJson: true,
      );
      expect(
        directSecureResources.resources.map((resource) => resource['uri']),
        contains('app://mcp/context'),
      );

      final directSecurePrompt = await directSecureMcpClient.getPrompt(
        'inspect-task',
        id: 'direct-secure-prompt',
        arguments: {'taskId': 'T-direct-secure'},
        directJson: true,
      );
      expect(jsonEncode(directSecurePrompt), contains('T-direct-secure'));
      await _expectDirectSafeLookupMethod(
        directSecureMcpClient,
        taskId: 'T-direct-secure-method',
        label: 'direct-secure',
      );
      await _expectDirectSafeLookupNotifications(
        directSecureMcpClient,
        observedSafeLookupTaskIds,
        label: 'direct-secure',
      );
      expect(directSecureMcpClient.sessionId, isNull);

      final secureJsonPostEndpoint = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: listener.port,
        path: '/mcp/secure-json-post',
      );
      final secureJsonPostClient = McpStreamableHttpClient.withAuthGrant(
        secureJsonPostEndpoint,
        grant,
      );
      addTearDown(() => secureJsonPostClient.close(force: true));

      final secureJsonDirectTools = await secureJsonPostClient
          .listConnectanumToolsDirect(id: 'secure-json-post-direct-tools');
      final secureJsonDirectToolNames = {
        for (final tool in secureJsonDirectTools.tools) tool['name'] as String,
      };
      expect(secureJsonDirectToolNames, contains('app.safe.lookup'));
      expect(secureJsonDirectToolNames, contains('app.unsafe.delete'));
      await _expectDirectSafeLookupMethod(
        secureJsonPostClient,
        taskId: 'T-secure-json-post-direct-method',
        label: 'secure-json-post',
      );
      await _expectDirectSafeLookupNotifications(
        secureJsonPostClient,
        observedSafeLookupTaskIds,
        label: 'secure-json-post',
      );
      expect(secureJsonPostClient.sessionId, isNull);

      final secureJsonDirectTopicCatalog = await secureJsonPostClient
          .listWampApi(
            id: 'secure-json-post-direct-topic-catalog',
            kind: 'topic',
            directJson: true,
          );
      expect(
        jsonEncode(secureJsonDirectTopicCatalog),
        contains('app.secure.audit'),
      );
      final secureJsonDirectDocumentedRegistration = await secureJsonPostClient
          .lookupWampRegistration(
            'app.documented.only',
            id: 'secure-json-post-direct-documented-registration-lookup',
            directJson: true,
          );
      expect(secureJsonDirectDocumentedRegistration.arguments, hasLength(1));
      final secureJsonDirectDocumentedRegistrationId =
          (secureJsonDirectDocumentedRegistration.arguments.single as num)
              .toInt();
      expect(secureJsonDirectDocumentedRegistrationId, greaterThan(0));
      final secureJsonDirectDocumentedRegistrationDetails =
          await secureJsonPostClient.getWampRegistration(
            secureJsonDirectDocumentedRegistrationId,
            id: 'secure-json-post-direct-documented-registration-get',
            directJson: true,
          );
      expect(
        secureJsonDirectDocumentedRegistrationDetails.argumentsKeywords,
        containsPair('uri', 'app.documented.only'),
      );

      final secureJsonDirectResources = await secureJsonPostClient
          .listResources(
            id: 'secure-json-post-direct-resources',
            directJson: true,
          );
      expect(
        secureJsonDirectResources.resources.map((resource) => resource['uri']),
        contains('app://mcp/context'),
      );

      final secureJsonDirectResourceContents = await secureJsonPostClient
          .readResource(
            'app://mcp/context',
            id: 'secure-json-post-direct-resource-read',
            directJson: true,
          );
      expect(
        secureJsonDirectResourceContents.single['text'],
        contains('router-hosted MCP route'),
      );

      final secureJsonDirectResourceTemplates = await secureJsonPostClient
          .listResourceTemplates(
            id: 'secure-json-post-direct-resource-templates',
            directJson: true,
          );
      expect(
        secureJsonDirectResourceTemplates.resourceTemplates.map(
          (template) => template['uriTemplate'],
        ),
        contains('app://mcp/task/{taskId}'),
      );

      final secureJsonDirectPrompts = await secureJsonPostClient.listPrompts(
        id: 'secure-json-post-direct-prompts',
        directJson: true,
      );
      expect(
        secureJsonDirectPrompts.prompts.map((prompt) => prompt['name']),
        contains('inspect-task'),
      );

      final secureJsonDirectPrompt = await secureJsonPostClient.getPrompt(
        'inspect-task',
        id: 'secure-json-post-direct-prompt',
        arguments: {'taskId': 'T-secure-json-direct-prompt'},
        directJson: true,
      );
      expect(
        jsonEncode(secureJsonDirectPrompt),
        contains('T-secure-json-direct-prompt'),
      );
      expect(secureJsonPostClient.sessionId, isNull);

      final secureJsonInitialize = await secureJsonPostClient.initialize(
        id: 'secure-json-post-initialize',
      );
      expect(secureJsonInitialize['id'], equals('secure-json-post-initialize'));
      final secureJsonSessionId = secureJsonPostClient.sessionId;
      expect(secureJsonSessionId, isNotNull);
      final activeSecureJsonSessionId = secureJsonSessionId!;
      expect(secureJsonPostClient.lastEventId, isNull);

      await secureJsonPostClient.notifyInitialized();
      expect(secureJsonPostClient.sessionId, equals(secureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final secureJsonTools = await secureJsonPostClient.listTools(
        id: 'secure-json-post-tools',
      );
      final secureJsonToolNames = {
        for (final tool in secureJsonTools.tools) tool['name'] as String,
      };
      expect(secureJsonToolNames, contains('app.safe.lookup'));
      expect(secureJsonToolNames, contains('app.unsafe.delete'));
      expect(secureJsonPostClient.sessionId, equals(secureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final activeMissingBearerJsonPost = await _postJson(
        client,
        listener.port,
        '/mcp/secure-json-post',
        {
          'jsonrpc': '2.0',
          'id': 'secure-json-post-active-missing-bearer',
          'method': 'tools/list',
          'params': {},
        },
        headers: {
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'mcp-session-id': activeSecureJsonSessionId,
        },
      );
      expect(
        activeMissingBearerJsonPost.statusCode,
        equals(HttpStatus.unauthorized),
      );
      expect(
        activeMissingBearerJsonPost.headers,
        isNot(contains('mcp-session-id')),
      );

      final activeUnknownBearerJsonPost = await _postJson(
        client,
        listener.port,
        '/mcp/secure-json-post',
        {
          'jsonrpc': '2.0',
          'id': 'secure-json-post-active-unknown-bearer',
          'method': 'tools/list',
          'params': {},
        },
        headers: {
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'authorization': 'Bearer unknown-access-token',
          'mcp-session-id': activeSecureJsonSessionId,
        },
      );
      expect(
        activeUnknownBearerJsonPost.statusCode,
        equals(HttpStatus.unauthorized),
      );
      expect(
        activeUnknownBearerJsonPost.headers,
        isNot(contains('mcp-session-id')),
      );
      expect(secureJsonPostClient.sessionId, equals(activeSecureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final activeOtherPrincipalJsonPost = await _postJson(
        client,
        listener.port,
        '/mcp/secure-json-post',
        {
          'jsonrpc': '2.0',
          'id': 'secure-json-post-active-other-principal',
          'method': 'tools/list',
          'params': {},
        },
        headers: {
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          'authorization': 'Bearer ${otherGrant.accessToken}',
          'MCP-Method': 'tools/list',
          'MCP-Protocol-Version': '2025-11-25',
          'mcp-session-id': activeSecureJsonSessionId,
        },
      );
      expect(
        activeOtherPrincipalJsonPost.statusCode,
        equals(HttpStatus.notFound),
      );
      expect(
        activeOtherPrincipalJsonPost.headers,
        isNot(contains('mcp-session-id')),
      );
      expect(
        jsonEncode(activeOtherPrincipalJsonPost.json?['error']),
        contains('Unknown MCP HTTP session'),
      );
      expect(secureJsonPostClient.sessionId, equals(activeSecureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final otherPrincipalJsonPostClient =
          McpStreamableHttpClient.withBearerToken(
            secureJsonPostEndpoint,
            otherGrant.accessToken,
          );
      addTearDown(() => otherPrincipalJsonPostClient.close(force: true));
      final otherPrincipalDirectTools = await otherPrincipalJsonPostClient
          .listToolsDirect(id: 'secure-json-post-other-direct-tools');
      expect(
        otherPrincipalDirectTools.tools.map((tool) => tool['name']),
        contains('app.safe.lookup'),
      );
      await _expectDirectSafeLookupMethod(
        otherPrincipalJsonPostClient,
        taskId: 'T-secure-json-post-other-direct-method',
        label: 'secure-json-post-other',
      );
      await _expectDirectSafeLookupNotifications(
        otherPrincipalJsonPostClient,
        observedSafeLookupTaskIds,
        label: 'secure-json-post-other',
      );
      expect(otherPrincipalJsonPostClient.sessionId, isNull);
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      final otherPrincipalDirectResources = await otherPrincipalJsonPostClient
          .listResources(
            id: 'secure-json-post-other-direct-resources',
            directJson: true,
          );
      expect(
        otherPrincipalDirectResources.resources.map(
          (resource) => resource['uri'],
        ),
        contains('app://mcp/context'),
      );

      final otherPrincipalDirectResourceContents =
          await otherPrincipalJsonPostClient.readResource(
            'app://mcp/context',
            id: 'secure-json-post-other-direct-resource-read',
            directJson: true,
          );
      expect(
        otherPrincipalDirectResourceContents.single['text'],
        contains('router-hosted MCP route'),
      );

      final otherPrincipalDirectResourceTemplates =
          await otherPrincipalJsonPostClient.listResourceTemplates(
            id: 'secure-json-post-other-direct-resource-templates',
            directJson: true,
          );
      expect(
        otherPrincipalDirectResourceTemplates.resourceTemplates.map(
          (template) => template['uriTemplate'],
        ),
        contains('app://mcp/task/{taskId}'),
      );

      final otherPrincipalDirectPrompts = await otherPrincipalJsonPostClient
          .listPrompts(
            id: 'secure-json-post-other-direct-prompts',
            directJson: true,
          );
      expect(
        otherPrincipalDirectPrompts.prompts.map((prompt) => prompt['name']),
        contains('inspect-task'),
      );

      final otherPrincipalDirectPrompt = await otherPrincipalJsonPostClient
          .getPrompt(
            'inspect-task',
            id: 'secure-json-post-other-direct-prompt',
            arguments: {'taskId': 'T-secure-json-post-other-direct-prompt'},
            directJson: true,
          );
      expect(
        jsonEncode(otherPrincipalDirectPrompt),
        contains('T-secure-json-post-other-direct-prompt'),
      );
      expect(otherPrincipalJsonPostClient.sessionId, isNull);
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      final otherPrincipalDirectTopicCatalog = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure-json-post',
        'connectanum.api.list',
        {'kind': 'topic'},
        headers: otherAuthHeaders,
      );
      expect(
        jsonEncode(otherPrincipalDirectTopicCatalog['structuredContent']),
        contains('app.secure.audit'),
      );
      await _expectDirectPrincipalWampMetaHelpers(
        otherPrincipalJsonPostClient,
        serviceSession,
        procedure: 'app.safe.lookup',
        topic: 'app.secure.audit',
        authId: 'user-2',
        authRole: 'member',
        label: 'secure-json-post-other-direct',
      );

      final otherPrincipalDirectSubscription = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure-json-post',
        'connectanum.pubsub.subscribe',
        {'topic': 'app.secure.audit', 'queueLimit': 5},
        headers: otherAuthHeaders,
      );
      final otherPrincipalDirectSubscriptionContent =
          otherPrincipalDirectSubscription['structuredContent']
              as Map<String, Object?>;
      final otherPrincipalDirectSubscriptionHandle =
          otherPrincipalDirectSubscriptionContent['handle'] as String;
      expect(
        otherPrincipalDirectSubscriptionContent['topic'],
        equals('app.secure.audit'),
      );

      await serviceSession.publish(
        'app.secure.audit',
        argumentsKeywords: {'via': 'secure-json-post-other-direct-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final otherPrincipalDirectPoll = await _pollDirectRouterJsonUntilEvents(
        client,
        listener.port,
        '/mcp/secure-json-post',
        otherPrincipalDirectSubscriptionHandle,
        headers: otherAuthHeaders,
      );
      expect(
        jsonEncode(otherPrincipalDirectPoll['events']),
        contains('secure-json-post-other-direct-service'),
      );

      final otherPrincipalDirectUnsubscribe = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure-json-post',
        'connectanum.pubsub.unsubscribe',
        {'handle': otherPrincipalDirectSubscriptionHandle},
        headers: otherAuthHeaders,
      );
      expect(
        otherPrincipalDirectUnsubscribe['structuredContent'],
        containsPair('unsubscribed', true),
      );
      expect(otherPrincipalJsonPostClient.sessionId, isNull);
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      final otherPrincipalInitialize = await otherPrincipalJsonPostClient
          .initialize(id: 'secure-json-post-other-initialize');
      expect(
        otherPrincipalInitialize['id'],
        equals('secure-json-post-other-initialize'),
      );
      final otherPrincipalSessionId = otherPrincipalJsonPostClient.sessionId;
      expect(otherPrincipalSessionId, isNotNull);
      expect(otherPrincipalSessionId, isNot(equals(activeSecureJsonSessionId)));
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      await otherPrincipalJsonPostClient.notifyInitialized();
      final otherPrincipalTools = await otherPrincipalJsonPostClient.listTools(
        id: 'secure-json-post-other-tools',
      );
      expect(
        otherPrincipalTools.tools.map((tool) => tool['name']),
        contains('app.safe.lookup'),
      );
      expect(
        otherPrincipalJsonPostClient.sessionId,
        equals(otherPrincipalSessionId),
      );
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      final otherPrincipalResources = await otherPrincipalJsonPostClient
          .listResources(id: 'secure-json-post-other-resources');
      expect(
        otherPrincipalResources.resources.map((resource) => resource['uri']),
        contains('app://mcp/context'),
      );

      final otherPrincipalResourceContents = await otherPrincipalJsonPostClient
          .readResource(
            'app://mcp/context',
            id: 'secure-json-post-other-resource-read',
          );
      expect(
        otherPrincipalResourceContents.single['text'],
        contains('router-hosted MCP route'),
      );

      final otherPrincipalResourceTemplates = await otherPrincipalJsonPostClient
          .listResourceTemplates(
            id: 'secure-json-post-other-resource-templates',
          );
      expect(
        otherPrincipalResourceTemplates.resourceTemplates.map(
          (template) => template['uriTemplate'],
        ),
        contains('app://mcp/task/{taskId}'),
      );

      final otherPrincipalPrompts = await otherPrincipalJsonPostClient
          .listPrompts(id: 'secure-json-post-other-prompts');
      expect(
        otherPrincipalPrompts.prompts.map((prompt) => prompt['name']),
        contains('inspect-task'),
      );

      final otherPrincipalPrompt = await otherPrincipalJsonPostClient.getPrompt(
        'inspect-task',
        id: 'secure-json-post-other-prompt',
        arguments: {'taskId': 'T-secure-json-post-other-prompt'},
      );
      expect(
        jsonEncode(otherPrincipalPrompt),
        contains('T-secure-json-post-other-prompt'),
      );
      expect(
        otherPrincipalJsonPostClient.sessionId,
        equals(otherPrincipalSessionId),
      );
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      final otherPrincipalSubscribe = await otherPrincipalJsonPostClient
          .request(
            'tools/call',
            id: 'secure-json-post-other-pubsub-subscribe',
            params: {
              'name': 'connectanum.pubsub.subscribe',
              'arguments': {'topic': 'app.secure.audit', 'queueLimit': 5},
            },
          );
      final otherPrincipalSubscription =
          ((otherPrincipalSubscribe['result'] as Map)['structuredContent']
                  as Map)
              .cast<String, Object?>();
      final otherPrincipalHandle =
          otherPrincipalSubscription['handle'] as String;
      expect(otherPrincipalSubscription['topic'], equals('app.secure.audit'));

      await serviceSession.publish(
        'app.secure.audit',
        argumentsKeywords: {'via': 'secure-json-post-other-streamable-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final otherPrincipalPoll = await _pollStreamableMcpUntilEvents(
        otherPrincipalJsonPostClient,
        otherPrincipalHandle,
      );
      expect(
        jsonEncode(otherPrincipalPoll['events']),
        contains('secure-json-post-other-streamable-service'),
      );

      final otherPrincipalUnsubscribe = await otherPrincipalJsonPostClient
          .request(
            'tools/call',
            id: 'secure-json-post-other-pubsub-unsubscribe',
            params: {
              'name': 'connectanum.pubsub.unsubscribe',
              'arguments': {'handle': otherPrincipalHandle},
            },
          );
      final otherPrincipalUnsubscribeResult =
          ((otherPrincipalUnsubscribe['result'] as Map)['structuredContent']
                  as Map)
              .cast<String, Object?>();
      expect(otherPrincipalUnsubscribeResult['unsubscribed'], isTrue);
      expect(
        otherPrincipalJsonPostClient.sessionId,
        equals(otherPrincipalSessionId),
      );
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);

      await otherPrincipalJsonPostClient.deleteSession();
      expect(otherPrincipalJsonPostClient.sessionId, isNull);
      expect(otherPrincipalJsonPostClient.lastEventId, isNull);
      expect(secureJsonPostClient.sessionId, equals(activeSecureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final secureJsonResources = await secureJsonPostClient.listResources(
        id: 'secure-json-post-resources',
      );
      expect(
        secureJsonResources.resources.map((resource) => resource['uri']),
        contains('app://mcp/context'),
      );

      final secureJsonResourceContents = await secureJsonPostClient
          .readResource(
            'app://mcp/context',
            id: 'secure-json-post-resource-read',
          );
      expect(
        secureJsonResourceContents.single['text'],
        contains('router-hosted MCP route'),
      );

      final secureJsonResourceTemplates = await secureJsonPostClient
          .listResourceTemplates(id: 'secure-json-post-resource-templates');
      expect(
        secureJsonResourceTemplates.resourceTemplates.map(
          (template) => template['uriTemplate'],
        ),
        contains('app://mcp/task/{taskId}'),
      );

      final secureJsonPrompts = await secureJsonPostClient.listPrompts(
        id: 'secure-json-post-prompts',
      );
      expect(
        secureJsonPrompts.prompts.map((prompt) => prompt['name']),
        contains('inspect-task'),
      );

      final secureJsonPrompt = await secureJsonPostClient.getPrompt(
        'inspect-task',
        id: 'secure-json-post-prompt',
        arguments: {'taskId': 'T-secure-json-prompt'},
      );
      expect(jsonEncode(secureJsonPrompt), contains('T-secure-json-prompt'));
      expect(secureJsonPostClient.sessionId, equals(secureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final secureJsonSubscribe = await secureJsonPostClient.request(
        'tools/call',
        id: 'secure-json-post-pubsub-subscribe',
        params: {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.secure.audit', 'queueLimit': 5},
        },
      );
      final secureJsonSubscription =
          ((secureJsonSubscribe['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      final secureJsonHandle = secureJsonSubscription['handle'] as String;
      expect(secureJsonSubscription['topic'], equals('app.secure.audit'));
      expect(secureJsonPostClient.sessionId, equals(secureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      await serviceSession.publish(
        'app.secure.audit',
        argumentsKeywords: {'via': 'secure-json-post-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final secureJsonPoll = await _pollStreamableMcpUntilEvents(
        secureJsonPostClient,
        secureJsonHandle,
      );
      expect(
        jsonEncode(secureJsonPoll['events']),
        contains('secure-json-post-service'),
      );
      expect(secureJsonPostClient.sessionId, equals(secureJsonSessionId));
      expect(secureJsonPostClient.lastEventId, isNull);

      final secureJsonUnsubscribe = await secureJsonPostClient.request(
        'tools/call',
        id: 'secure-json-post-pubsub-unsubscribe',
        params: {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': secureJsonHandle},
        },
      );
      final secureJsonUnsubscribeResult =
          ((secureJsonUnsubscribe['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      expect(secureJsonUnsubscribeResult['unsubscribed'], isTrue);
      await secureJsonPostClient.deleteSession();
      expect(secureJsonPostClient.sessionId, isNull);
      expect(secureJsonPostClient.lastEventId, isNull);

      final directSecureUnsafeRegistration = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.registration.match',
        {'procedure': 'app.unsafe.delete'},
        headers: authHeaders,
      );
      final directSecureUnsafeRegistrationIds =
          (directSecureUnsafeRegistration['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directSecureUnsafeRegistrationIds, isNotEmpty);
      final directSecureUnsafeRegistrationId =
          directSecureUnsafeRegistrationIds.single as int;

      final directSecureUnsafeRegistrationGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.registration.get',
        {'id': directSecureUnsafeRegistrationId},
        headers: authHeaders,
      );
      final directSecureUnsafeRegistrationDetails =
          (directSecureUnsafeRegistrationGet['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(
        directSecureUnsafeRegistrationDetails,
        containsPair('uri', 'app.unsafe.delete'),
      );

      final directSecureUnsafeRegistrationCallees = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.registration.list_callees',
        {'id': directSecureUnsafeRegistrationId},
        headers: authHeaders,
      );
      final directSecureUnsafeCalleeIds =
          (directSecureUnsafeRegistrationCallees['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directSecureUnsafeCalleeIds, isEmpty);
      expect(
        directSecureUnsafeCalleeIds,
        isNot(contains(serviceSession.sessionId)),
      );

      final directSecureUnsafeCalleeCount = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.registration.count_callees',
        {'id': directSecureUnsafeRegistrationId},
        headers: authHeaders,
      );
      expect(
        (directSecureUnsafeCalleeCount['structuredContent']
            as Map<String, Object?>)['arguments'],
        equals([0]),
      );

      final directSecureSessionList = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.session.list',
        const {},
        headers: authHeaders,
      );
      final directSecureSessionIds =
          ((directSecureSessionList['structuredContent']
                      as Map<String, Object?>)['argumentsKeywords']
                  as Map<String, Object?>)['session_ids']
              as List;
      expect(directSecureSessionIds, hasLength(1));
      expect(directSecureSessionIds, isNot(contains(serviceSession.sessionId)));
      final directSecureSessionId = directSecureSessionIds.single as int;

      final directSecureSessionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.session.get',
        {'id': directSecureSessionId},
        headers: authHeaders,
      );
      final directSecureSessionDetails =
          ((directSecureSessionGet['structuredContent']
                      as Map<String, Object?>)['argumentsKeywords']
                  as Map<String, Object?>)['details']
              as Map<String, Object?>;
      expect(directSecureSessionDetails['authid'], equals('user-1'));
      expect(directSecureSessionDetails['authrole'], equals('member'));

      final directSecureServiceSessionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.session.get',
        {'id': serviceSession.sessionId},
        headers: authHeaders,
      );
      final directSecureServiceSessionGetArguments =
          (directSecureServiceSessionGet['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(
        directSecureServiceSessionGetArguments,
        contains('wamp.error.no_such_session'),
      );

      final directSecureTopicCatalog = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'connectanum.api.list',
        {'kind': 'topic'},
        headers: authHeaders,
      );
      expect(
        jsonEncode(directSecureTopicCatalog['structuredContent']),
        contains('app.secure.audit'),
      );

      final directSecureSubscription = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'connectanum.pubsub.subscribe',
        {'topic': 'app.secure.audit', 'queueLimit': 5},
        headers: authHeaders,
      );
      final directSecureSubscriptionContent =
          directSecureSubscription['structuredContent'] as Map<String, Object?>;
      final directSecureSubscriptionHandle =
          directSecureSubscriptionContent['handle'] as String;
      expect(
        directSecureSubscriptionContent['topic'],
        equals('app.secure.audit'),
      );

      final directPublicSecureSubscriptionMeta = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/public',
        'wamp.subscription.match',
        {'topic': 'app.secure.audit'},
      );
      final directPublicSecureSubscriptionMetaIds =
          (directPublicSecureSubscriptionMeta['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directPublicSecureSubscriptionMetaIds, isEmpty);

      final directSecureSubscriptionMeta = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.subscription.match',
        {'topic': 'app.secure.audit'},
        headers: authHeaders,
      );
      final directSecureSubscriptionMetaIds =
          (directSecureSubscriptionMeta['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directSecureSubscriptionMetaIds, isNotEmpty);
      final directSecureSubscriptionId =
          directSecureSubscriptionMetaIds.single as int;

      final directSecureSubscriptionGet = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.subscription.get',
        {'id': directSecureSubscriptionId},
        headers: authHeaders,
      );
      final directSecureSubscriptionDetails =
          (directSecureSubscriptionGet['structuredContent']
                  as Map<String, Object?>)['argumentsKeywords']
              as Map<String, Object?>;
      expect(
        directSecureSubscriptionDetails,
        containsPair('uri', 'app.secure.audit'),
      );

      final directSecureSubscriptionSubscribers = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'wamp.subscription.list_subscribers',
        {'id': directSecureSubscriptionId},
        headers: authHeaders,
      );
      final directSecureSubscriberIds =
          (directSecureSubscriptionSubscribers['structuredContent']
                  as Map<String, Object?>)['arguments']
              as List;
      expect(directSecureSubscriberIds, contains(directSecureSessionId));
      expect(
        directSecureSubscriberIds,
        isNot(contains(serviceSession.sessionId)),
      );
      expect(directSecureSubscriberIds, hasLength(1));

      final directSecureSubscriptionSubscriberCount =
          await _callRouterJsonMethod(
            client,
            listener.port,
            '/mcp/secure',
            'wamp.subscription.count_subscribers',
            {'id': directSecureSubscriptionId},
            headers: authHeaders,
          );
      expect(
        (directSecureSubscriptionSubscriberCount['structuredContent']
            as Map<String, Object?>)['arguments'],
        equals([1]),
      );

      final directSecurePublish = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'connectanum.pubsub.publish',
        {
          'topic': 'app.secure.audit',
          'argumentsKeywords': {'via': 'secure-direct-json-publish'},
          'acknowledge': true,
        },
        headers: authHeaders,
      );
      expect(
        directSecurePublish['structuredContent'],
        containsPair('acknowledged', true),
      );

      await serviceSession.publish(
        'app.secure.audit',
        argumentsKeywords: {'via': 'secure-direct-json-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final directSecurePoll = await _pollDirectRouterJsonUntilEvents(
        client,
        listener.port,
        '/mcp/secure',
        directSecureSubscriptionHandle,
        headers: authHeaders,
      );
      expect(
        jsonEncode(directSecurePoll['events']),
        contains('secure-direct-json-service'),
      );

      final directSecureUnsubscribe = await _callRouterJsonMethod(
        client,
        listener.port,
        '/mcp/secure',
        'connectanum.pubsub.unsubscribe',
        {'handle': directSecureSubscriptionHandle},
        headers: authHeaders,
      );
      expect(
        directSecureUnsubscribe['structuredContent'],
        containsPair('unsubscribed', true),
      );

      final directSecureUnsafeResult = await directSecureMcpClient
          .callConnectanumToolDirect(
            'app.unsafe.delete',
            id: 'direct-secure-delete',
            arguments: {'taskId': 'T-3'},
          );
      expect(directSecureUnsafeResult['isError'], isFalse);
      expect(
        ((directSecureUnsafeResult['structuredContent']
                as Map)['argumentsKeywords']
            as Map)['deleted'],
        equals('T-3'),
      );

      final secureStreamableClient = McpStreamableHttpClient.withAuthGrant(
        Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: listener.port,
          path: '/mcp/secure',
        ),
        grant,
      );
      addTearDown(() => secureStreamableClient.close(force: true));

      final secureStreamableInitialize = await secureStreamableClient
          .initialize();
      expect(secureStreamableInitialize['id'], equals('initialize'));
      expect(secureStreamableClient.sessionId, isNotNull);
      await secureStreamableClient.notifyInitialized();

      final secureStreamableTools = await secureStreamableClient.listTools(
        id: 'secure-streamable-tools',
      );
      final secureStreamableToolNames = {
        for (final tool in secureStreamableTools.tools) tool['name'] as String,
      };
      expect(secureStreamableToolNames, contains('app.safe.lookup'));
      expect(secureStreamableToolNames, contains('app.unsafe.delete'));

      final secureStreamableTopicCatalogResult = await secureStreamableClient
          .callTool(
            'connectanum.api.list',
            id: 'secure-streamable-topic-catalog',
            arguments: {'kind': 'topic'},
          );
      expect(secureStreamableTopicCatalogResult['isError'], isFalse);
      expect(
        jsonEncode(secureStreamableTopicCatalogResult['structuredContent']),
        contains('app.secure.audit'),
      );

      final secureStreamableUnsafeResult = await secureStreamableClient
          .callTool(
            'app.unsafe.delete',
            id: 'secure-streamable-unsafe',
            arguments: {'taskId': 'T-secure-streamable'},
          );
      expect(secureStreamableUnsafeResult['isError'], isFalse);
      expect(
        ((secureStreamableUnsafeResult['structuredContent']
                as Map)['argumentsKeywords']
            as Map)['deleted'],
        equals('T-secure-streamable'),
      );

      expect(secureStreamableClient.lastEventId, isNotNull);

      final secureStreamableSubscribe = await secureStreamableClient.request(
        'tools/call',
        id: 'secure-streamable-pubsub-subscribe',
        params: {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.secure.audit', 'queueLimit': 5},
        },
      );
      final secureStreamableSubscription =
          ((secureStreamableSubscribe['result'] as Map)['structuredContent']
                  as Map)
              .cast<String, Object?>();
      final secureStreamableHandle =
          secureStreamableSubscription['handle'] as String;
      expect(secureStreamableSubscription['topic'], equals('app.secure.audit'));

      final secureStreamablePublish = await secureStreamableClient.request(
        'tools/call',
        id: 'secure-streamable-pubsub-publish',
        params: {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': 'app.secure.audit',
            'argumentsKeywords': {'via': 'secure-streamable-publish'},
            'acknowledge': true,
          },
        },
      );
      final secureStreamablePublishResult =
          ((secureStreamablePublish['result'] as Map)['structuredContent']
                  as Map)
              .cast<String, Object?>();
      expect(secureStreamablePublishResult['acknowledged'], isTrue);

      await serviceSession.publish(
        'app.secure.audit',
        argumentsKeywords: {'via': 'secure-streamable-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final secureStreamablePoll = await _pollStreamableMcpUntilEvents(
        secureStreamableClient,
        secureStreamableHandle,
      );
      expect(
        jsonEncode(secureStreamablePoll['events']),
        contains('secure-streamable-service'),
      );

      final secureStreamableUnsubscribe = await secureStreamableClient.request(
        'tools/call',
        id: 'secure-streamable-pubsub-unsubscribe',
        params: {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': secureStreamableHandle},
        },
      );
      final secureStreamableUnsubscribeResult =
          ((secureStreamableUnsubscribe['result'] as Map)['structuredContent']
                  as Map)
              .cast<String, Object?>();
      expect(secureStreamableUnsubscribeResult['unsubscribed'], isTrue);

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
  HttpRouteMatch? mcpRouteMatch,
  HttpRouteAction? mcpRouteAction,
  Map<String, HttpRouteAction> mcpMethodActions =
      const <String, HttpRouteAction>{},
  Map<String, Object?>? mcpOptions,
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
    final effectiveMcpOptions =
        mcpOptions ??
        const <String, Object?>{
          'tool_list_page_size': 100,
          'resource_list_page_size': 10,
          'resource_template_list_page_size': 10,
          'prompt_list_page_size': 10,
          'resources': [
            {
              'uri': 'app://example/context',
              'name': 'example-context',
              'title': 'Example context',
              'description':
                  'Static context exposed by the router MCP endpoint.',
              'mime_type': 'text/plain',
              'text': 'This context came from router-hosted MCP.',
            },
          ],
          'resource_templates': [
            {
              'uri_template': 'app://example/task/{taskId}',
              'name': 'example-task',
              'title': 'Example task resource',
              'description':
                  'Template for task resources exposed by the router.',
              'mime_type': 'application/json',
            },
          ],
          'prompts': [
            {
              'name': 'summarize-task',
              'title': 'Summarize task',
              'description': 'Builds a task summary prompt.',
              'arguments': [
                {
                  'name': 'taskId',
                  'description': 'Task identifier to summarize.',
                  'required': true,
                },
              ],
              'messages': [
                {
                  'role': 'user',
                  'text': 'Summarize task {{taskId}} using router context.',
                },
              ],
            },
          ],
        };
    routes.add(
      HttpRouteSettings(
        match: mcpRouteMatch ?? const HttpRouteMatch(path: '/mcp'),
        action:
            mcpRouteAction ??
            HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: 'realm1',
              options: effectiveMcpOptions,
            ),
        methodActions: mcpMethodActions,
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
        http3: enableHttp3 ? const Http3Settings(enabled: true, port: 0) : null,
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
        ..addListenerFromBuilder(listener)
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        ))
      .build();
}

final class _ToggleAuthorizationProvider implements AuthorizationProvider {
  _ToggleAuthorizationProvider({required this.action, required this.uri});

  final AuthorizationAction action;
  final String uri;
  bool allowed = false;
  int matchingRequestCount = 0;

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action != action || request.uri != uri) {
      return null;
    }
    matchingRequestCount++;
    return allowed
        ? null
        : const AuthorizationDecision.deny(
            message: 'blocked by dynamic resource policy',
          );
  }
}

final class _BlockingSnapshotAuthorizationProvider
    implements AuthorizationProvider {
  _BlockingSnapshotAuthorizationProvider({
    required this.action,
    required this.uri,
  });

  final AuthorizationAction action;
  final String uri;
  bool allowed = true;
  int matchingRequestCount = 0;
  Completer<void>? _nextEntered;
  Completer<void>? _nextRelease;
  int _matchingDecisionsBeforeBlock = 0;

  void blockNextDecision({
    required Completer<void> entered,
    required Completer<void> release,
    int skipMatchingDecisions = 0,
  }) {
    if (_nextEntered != null || _nextRelease != null) {
      throw StateError('An authorization decision is already blocked');
    }
    if (skipMatchingDecisions < 0) {
      throw ArgumentError.value(
        skipMatchingDecisions,
        'skipMatchingDecisions',
        'must not be negative',
      );
    }
    _nextEntered = entered;
    _nextRelease = release;
    _matchingDecisionsBeforeBlock = skipMatchingDecisions;
  }

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action != action || request.uri != uri) {
      return null;
    }
    matchingRequestCount++;
    final decisionAllowed = allowed;
    final entered = _nextEntered;
    final release = _nextRelease;
    if (entered != null && release != null) {
      if (_matchingDecisionsBeforeBlock > 0) {
        _matchingDecisionsBeforeBlock--;
      } else {
        _nextEntered = null;
        _nextRelease = null;
        entered.complete();
        await release.future;
      }
    }
    return decisionAllowed
        ? null
        : const AuthorizationDecision.deny(
            message: 'blocked by resource subscription policy',
          );
  }
}

final class _CountingCatalogAuthorizationProvider
    implements AuthorizationProvider {
  _CountingCatalogAuthorizationProvider({
    required this.action,
    required this.uri,
  });

  final AuthorizationAction action;
  final String uri;
  int matchingRequestCount = 0;

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action == action && request.uri == uri) {
      matchingRequestCount += 1;
    }
    return null;
  }
}

final class _FailNextCatalogAuthorizationProvider
    implements AuthorizationProvider {
  _FailNextCatalogAuthorizationProvider({
    required this.action,
    required this.uri,
  });

  final AuthorizationAction action;
  final String uri;
  bool _failNext = false;

  void failNext() {
    _failNext = true;
  }

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (_failNext && request.action == action && request.uri == uri) {
      _failNext = false;
      throw StateError('catalog authorization backend detail');
    }
    return null;
  }
}

final class _BlockingFailNextCatalogAuthorizationProvider
    implements AuthorizationProvider {
  _BlockingFailNextCatalogAuthorizationProvider({
    required this.action,
    required this.uri,
  });

  final AuthorizationAction action;
  final String uri;
  Completer<void>? _nextEntered;
  Completer<void>? _nextRelease;

  void blockNextFailure({
    required Completer<void> entered,
    required Completer<void> release,
  }) {
    if (_nextEntered != null || _nextRelease != null) {
      throw StateError('An authorization failure is already blocked');
    }
    _nextEntered = entered;
    _nextRelease = release;
  }

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action != action || request.uri != uri) {
      return null;
    }
    final entered = _nextEntered;
    final release = _nextRelease;
    if (entered == null || release == null) {
      return null;
    }
    _nextEntered = null;
    _nextRelease = null;
    entered.complete();
    await release.future;
    throw StateError('catalog authorization backend detail');
  }
}

final class _FailDeferredAuthorizationProvider
    implements AuthorizationProvider {
  _FailDeferredAuthorizationProvider({required this.action, required this.uri});

  final AuthorizationAction action;
  final String uri;
  int? _matchingRequestsUntilFailure;
  int matchingRequestCount = 0;

  void failOnMatchingRequest(int requestNumber) {
    assert(requestNumber > 0);
    _matchingRequestsUntilFailure = requestNumber;
  }

  void clearPendingFailure() {
    _matchingRequestsUntilFailure = null;
  }

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action != action || request.uri != uri) {
      return null;
    }
    matchingRequestCount++;
    final remaining = _matchingRequestsUntilFailure;
    if (remaining == null) {
      return null;
    }
    if (remaining == 1) {
      _matchingRequestsUntilFailure = null;
      throw StateError('action authorization backend detail');
    }
    _matchingRequestsUntilFailure = remaining - 1;
    return null;
  }
}

final class _BlockingCatalogAuthorizationProvider
    implements AuthorizationProvider {
  _BlockingCatalogAuthorizationProvider({
    required this.action,
    required this.uri,
    required this.entered,
    required this.release,
  });

  final AuthorizationAction action;
  final String uri;
  final Completer<void> entered;
  final Completer<void> release;
  bool _blocked = false;

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (!_blocked && request.action == action && request.uri == uri) {
      _blocked = true;
      if (!entered.isCompleted) {
        entered.complete();
      }
      await release.future;
    }
    return null;
  }
}

final class _ConcurrentCatalogAuthorizationProvider
    implements AuthorizationProvider {
  _ConcurrentCatalogAuthorizationProvider({
    required this.action,
    required this.uri,
    required this.firstEntered,
    required this.secondEntered,
    required this.releaseFirst,
  });

  final AuthorizationAction action;
  final String uri;
  final Completer<void> firstEntered;
  final Completer<void> secondEntered;
  final Completer<void> releaseFirst;
  int _matchingRequestCount = 0;
  int _activeMatchingRequests = 0;
  int maxConcurrentMatchingRequests = 0;

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action != action || request.uri != uri) {
      return null;
    }
    _matchingRequestCount += 1;
    _activeMatchingRequests += 1;
    if (_activeMatchingRequests > maxConcurrentMatchingRequests) {
      maxConcurrentMatchingRequests = _activeMatchingRequests;
    }
    try {
      if (_matchingRequestCount == 1) {
        firstEntered.complete();
        await releaseFirst.future;
      } else if (_matchingRequestCount == 2 && !secondEntered.isCompleted) {
        secondEntered.complete();
      }
    } finally {
      _activeMatchingRequests -= 1;
    }
    return null;
  }
}

RouterSettings _buildMcpSmokeSettings({
  bool enableHttp3 = false,
  int? sessionIdleTimeoutMs,
  int? maxSessionCount,
  int? maxRequestScopedListenerCount,
  int? maxWampSubscriptionCount,
  int? maxWampSubscriptionQueueLimit,
  int? maxWampSubscriptionQueueBytes,
  int? maxRequestBytes,
  int? maxResponseBytes,
  int? maxSseHistoryBytes,
  int? callTimeoutMs,
  String? serverDescription,
  String? liveResourceUri,
  List<String> additionalLiveResourceUris = const <String>[],
}) {
  const protectedResourceMetadata = <String, Object?>{
    'metadata_url': 'https://mcp.example.test/mcp/secure',
    'resource': 'https://mcp.example.test/mcp/secure',
    'authorization_servers': ['https://auth.example.test'],
    'scopes_supported': ['mcp:read', 'mcp:write'],
    'resource_name': 'Connectanum MCP',
  };
  final mcpOptions = <String, Object?>{
    'description': ?serverDescription,
    'tool_list_page_size': 100,
    'session_idle_timeout_ms': ?sessionIdleTimeoutMs,
    'max_session_count': ?maxSessionCount,
    'max_request_scoped_listener_count': ?maxRequestScopedListenerCount,
    'max_wamp_subscription_count': ?maxWampSubscriptionCount,
    'max_wamp_subscription_queue_limit': ?maxWampSubscriptionQueueLimit,
    'max_wamp_subscription_queue_bytes': ?maxWampSubscriptionQueueBytes,
    'max_request_bytes': ?maxRequestBytes,
    'max_response_bytes': ?maxResponseBytes,
    'max_sse_history_bytes': ?maxSseHistoryBytes,
    'call_timeout_ms': ?callTimeoutMs,
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
      {
        'topic': 'app.events.readonly',
        'title': 'Read-only audit events',
        'description': 'Audit events that MCP clients may subscribe to only.',
        'allowPublish': false,
        'allowSubscribe': true,
      },
      {
        'topic': 'app.secure.audit',
        'title': 'Protected audit events',
        'description': 'Member-only audit events exposed through MCP pub/sub.',
        '_ai_meta_data': {
          'short_description': 'Protected task audit stream',
          'description': 'Member-only events emitted when task state changes.',
          'domain': 'app',
          'entity': 'task',
          'tags': ['protected', 'events'],
          'output_json_schema': {
            'type': 'object',
            'properties': {
              'via': {'type': 'string'},
            },
          },
        },
      },
    ],
    'resource_list_page_size': 10,
    'resource_template_list_page_size': 10,
    'prompt_list_page_size': 10,
    'resources': [
      {
        'uri': 'app://mcp/context',
        'name': 'mcp-context',
        'title': 'MCP route context',
        'description': 'Static context exposed by the MCP route.',
        'mime_type': 'text/plain',
        'text': 'This context is served by the router-hosted MCP route.',
      },
      {
        'uri': liveResourceUri ?? 'app://mcp/live-context',
        'name': 'mcp-live-context',
        'title': 'MCP live route context',
        'description':
            'Dynamic context read through an explicitly configured procedure.',
        'mime_type': 'application/json',
        'read_procedure': 'app.safe.resource.read',
        'update_topic': 'app.events.resource.context',
      },
      for (var index = 0; index < additionalLiveResourceUris.length; index++)
        {
          'uri': additionalLiveResourceUris[index],
          'name': 'mcp-live-context-$index',
          'title': 'MCP live route context $index',
          'description':
              'Dynamic context read through an explicitly configured procedure.',
          'mime_type': 'application/json',
          'read_procedure': 'app.safe.resource.read',
          'update_topic': 'app.events.resource.context',
        },
      {
        'uri': 'app://mcp/member-context',
        'name': 'mcp-member-context',
        'title': 'MCP member route context',
        'description': 'Context protected by WAMP call and subscribe grants.',
        'mime_type': 'application/json',
        'read_procedure': 'app.unsafe.delete',
        'update_topic': 'app.secure.audit',
      },
    ],
    'resource_templates': [
      {
        'uri_template': 'app://mcp/task/{taskId}',
        'name': 'mcp-task',
        'title': 'MCP task resource',
        'description': 'Template for task resources exposed by the MCP route.',
        'mime_type': 'application/json',
      },
    ],
    'prompts': [
      {
        'name': 'inspect-task',
        'title': 'Inspect task',
        'description': 'Builds a task inspection prompt.',
        'arguments': [
          {
            'name': 'taskId',
            'description': 'Task identifier to inspect.',
            'required': true,
          },
        ],
        'messages': [
          {
            'role': 'user',
            'text': 'Inspect task {{taskId}} using the route context.',
          },
        ],
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
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.secure.')
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
      HttpListenerSettings(
        alpn: enableHttp3 ? const ['http/1.1', 'h2', 'h3'] : const ['http/1.1'],
        http3: enableHttp3 ? const Http3Settings(enabled: true, port: 0) : null,
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
                'protected_resource_metadata': protectedResourceMetadata,
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/mcp/secure-json-post'),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: 'realm1',
              sessionProfile: 'mcp-ticket',
              options: <String, Object?>{
                ...mcpOptions,
                'allow_insecure_transport': true,
                'post_response_transport': 'json',
              },
            ),
          ),
        ],
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});
  if (enableHttp3) {
    listener
      ..addProtocol(ListenerProtocol.http2)
      ..addProtocol(ListenerProtocol.http3);
  }

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
                'user-2': <String, Object?>{
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
      final responseHeadersPtrPtr = arena<ffi.Pointer<ffi.Uint8>>();
      final responseHeadersLenPtr = arena<ffi.IntPtr>();
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
        responseHeadersPtrPtr,
        responseHeadersLenPtr,
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
      final responseHeadersPtr = responseHeadersPtrPtr.value;
      final responseHeadersLen = responseHeadersLenPtr.value;
      Uint8List responseHeaders;
      if (responseHeadersPtr == ffi.nullptr || responseHeadersLen == 0) {
        responseHeaders = Uint8List(0);
      } else {
        responseHeaders = Uint8List.fromList(
          responseHeadersPtr.asTypedList(responseHeadersLen),
        );
        bufferFree(responseHeadersPtr, responseHeadersLen);
      }
      final responsePtr = responsePtrPtr.value;
      final responseLen = responseLenPtr.value;
      Uint8List responseBody;
      if (responsePtr == ffi.nullptr || responseLen == 0) {
        responseBody = Uint8List(0);
      } else {
        responseBody = Uint8List.fromList(responsePtr.asTypedList(responseLen));
        bufferFree(responsePtr, responseLen);
      }
      return <String, Object?>{
        'status': status,
        'headers': responseHeaders,
        'body': responseBody,
      };
    });
  });
  final status = result['status'] as int? ?? 0;
  final responseHeaders = (result['headers'] as Uint8List?) ?? Uint8List(0);
  final responseBody = (result['body'] as Uint8List?) ?? Uint8List(0);
  return NativeHttpTestResponse(
    status,
    responseBody,
    _parseHttpTestHeaderBlock(responseHeaders),
  );
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

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_postJson(
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
  return _readJsonHttpResponse(await request.close());
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_postHttp2Json(
  int port,
  String path,
  Map<String, Object?> payload, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final connection = http2.ClientTransportConnection.viaSocket(socket);
  try {
    await connection.onInitialPeerSettingsReceived;
    final bodyBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final stream = connection.makeRequest(<http2.Header>[
      http2.Header.ascii(':method', 'POST'),
      http2.Header.ascii(':scheme', 'http'),
      http2.Header.ascii(':path', path),
      http2.Header.ascii(':authority', '127.0.0.1:$port'),
      http2.Header.ascii('content-type', ContentType.json.mimeType),
      http2.Header.ascii('content-length', bodyBytes.length.toString()),
      for (final entry in headers.entries)
        http2.Header.ascii(entry.key.toLowerCase(), entry.value),
    ], endStream: false);
    stream.outgoingMessages.add(http2.DataStreamMessage(bodyBytes));
    await stream.outgoingMessages.close();
    final response = await _readJsonHttp2Response(stream.incomingMessages);
    await connection.finish();
    socket.destroy();
    return response;
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_postHttp3Json(
  String nativeLibPath,
  int port,
  String path,
  Map<String, Object?> payload, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final bodyText = jsonEncode(payload);
  final bodyBytes = Uint8List.fromList(utf8.encode(bodyText));
  final response = await _requestHttp3(
    nativeLibPath,
    port,
    path,
    method: 'POST',
    headers: <String, String>{
      'content-type': ContentType.json.mimeType,
      'content-length': bodyBytes.length.toString(),
      ...headers,
    },
    body: bodyBytes,
  );
  final body = response.body;
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
    headers: response.headers,
  );
}

Future<({int statusCode, String body, Map<String, String> headers})>
_requestHttp3(
  String nativeLibPath,
  int port,
  String path, {
  required String method,
  Map<String, String> headers = const <String, String>{},
  Uint8List? body,
}) async {
  final response = await _runHttp3StreamRequestInIsolate(
    nativeLibPath,
    host: '127.0.0.1',
    port: port,
    path: path,
    method: method,
    headers: headers,
    body: body ?? Uint8List(0),
    certificatePem: _http3CaCertificatePem,
  );
  return (
    statusCode: response.status,
    body: utf8.decode(response.body),
    headers: response.headers,
  );
}

Map<String, String> _parseHttpTestHeaderBlock(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const {};
  }
  final headers = <String, String>{};
  for (final line in utf8.decode(bytes).split('\n')) {
    if (line.isEmpty) {
      continue;
    }
    final separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    final name = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    if (name.isEmpty) {
      continue;
    }
    headers.update(
      name,
      (existing) => '$existing, $value',
      ifAbsent: () => value,
    );
  }
  return headers;
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_putJson(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> payload, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.put('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  headers.forEach(request.headers.set);
  final bodyBytes = utf8.encode(jsonEncode(payload));
  request.contentLength = bodyBytes.length;
  request.add(bodyBytes);
  return _readJsonHttpResponse(await request.close());
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_readJsonHttp2Response(Stream<Object?> messages) async {
  var statusCode = 0;
  final bodyBuilder = BytesBuilder(copy: false);
  final headers = <String, String>{};
  await for (final message in messages) {
    if (message is http2.HeadersStreamMessage) {
      for (final header in message.headers) {
        final name = utf8.decode(header.name).toLowerCase();
        final value = utf8.decode(header.value);
        if (name == ':status') {
          statusCode = int.tryParse(value) ?? statusCode;
          continue;
        }
        headers.update(
          name,
          (existing) => '$existing, $value',
          ifAbsent: () => value,
        );
      }
    } else if (message is http2.DataStreamMessage) {
      bodyBuilder.add(message.bytes);
    }
  }
  final body = utf8.decode(bodyBuilder.takeBytes());
  Object? decoded;
  if (body.isNotEmpty) {
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
  }
  return (
    statusCode: statusCode,
    json: decoded is Map ? decoded.cast<String, Object?>() : null,
    body: body,
    headers: headers,
  );
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_postBody(
  HttpClient client,
  int port,
  String path,
  String body, {
  ContentType? contentType,
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = contentType ?? ContentType.json;
  headers.forEach(request.headers.set);
  final bodyBytes = utf8.encode(body);
  request.contentLength = bodyBytes.length;
  request.add(bodyBytes);
  return _readJsonHttpResponse(await request.close());
}

Future<
  ({int statusCode, Object? json, String body, Map<String, String> headers})
>
_postJsonValue(
  HttpClient client,
  int port,
  String path,
  Object? payload, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  headers.forEach(request.headers.set);
  final bodyBytes = utf8.encode(jsonEncode(payload));
  request.contentLength = bodyBytes.length;
  request.add(bodyBytes);
  return _readJsonHttpResponseValue(await request.close());
}

String _firstSseEventId(String body) {
  final ids = _sseEventIds(body);
  if (ids.isNotEmpty) {
    return ids.first;
  }
  fail('SSE body did not contain an event id: $body');
}

List<String> _sseEventIds(String body) {
  return [
    for (final line in const LineSplitter().convert(body))
      if (line.startsWith('id: ')) line.substring(4),
  ];
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_getHttp(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.get('127.0.0.1', port, path);
  headers.forEach(request.headers.set);
  return _readJsonHttpResponse(await request.close());
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_deleteHttp(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.delete('127.0.0.1', port, path);
  headers.forEach(request.headers.set);
  return _readJsonHttpResponse(await request.close());
}

Future<
  ({
    int statusCode,
    Map<String, Object?>? json,
    String body,
    Map<String, String> headers,
  })
>
_readJsonHttpResponse(HttpClientResponse response) async {
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
    headers: _httpResponseHeaders(response),
  );
}

Future<
  ({int statusCode, Object? json, String body, Map<String, String> headers})
>
_readJsonHttpResponseValue(HttpClientResponse response) async {
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
    json: decoded,
    body: body,
    headers: _httpResponseHeaders(response),
  );
}

Map<String, String> _httpResponseHeaders(HttpClientResponse response) {
  final headers = <String, String>{};
  response.headers.forEach((name, values) {
    headers[name.toLowerCase()] = values.join(', ');
  });
  return headers;
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

Future<Map<String, Object?>> _callRouterJsonMethod(
  HttpClient client,
  int port,
  String path,
  String method,
  Map<String, Object?> params, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final response = await _postJson(client, port, path, {
    'jsonrpc': '2.0',
    'id': 'direct-$method',
    'method': method,
    'params': params,
  }, headers: headers);
  expect(response.statusCode, equals(HttpStatus.ok));
  final error = response.json?['error'];
  if (error != null) {
    fail('Router JSON method $method returned error: ${jsonEncode(error)}');
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

Future<Map<String, Object?>> _pollDirectRouterJsonUntilEvents(
  HttpClient client,
  int port,
  String path,
  String handle, {
  Map<String, String> headers = const <String, String>{},
}) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final result = await _callRouterJsonMethod(
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
  fail('Timed out waiting for direct JSON MCP subscription events for $handle');
}

Future<void> _expectDirectPrincipalWampMetaHelpers(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String procedure,
  required String topic,
  required String authId,
  required String authRole,
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final sessionCount = await client.countWampSessionsDirect(
    id: '$label-session-count',
    headers: <String, String>{'x-consumer-trace': '$label-session-count'},
  );
  expect(sessionCount.argumentsKeywords['count'], equals(1));

  final sessionList = await client.listWampSessionsDirect(
    id: '$label-session-list',
    headers: <String, String>{'x-consumer-trace': '$label-session-list'},
  );
  final sessionIds = (sessionList.argumentsKeywords['session_ids'] as List)
      .cast<Object?>();
  expect(sessionIds, hasLength(1));
  expect(sessionIds, isNot(contains(serviceSession.sessionId)));
  final visibleSessionId = (sessionIds.single as num).toInt();

  final sessionGet = await client.getWampSessionDirect(
    visibleSessionId,
    id: '$label-session-get',
    headers: <String, String>{'x-consumer-trace': '$label-session-get'},
  );
  final sessionDetails = (sessionGet.argumentsKeywords['details'] as Map)
      .cast<String, Object?>();
  expect(sessionDetails['authid'], equals(authId));
  expect(sessionDetails['authrole'], equals(authRole));

  final registrationLookup = await client.lookupWampRegistrationDirect(
    procedure,
    id: '$label-registration-lookup',
    match: 'exact',
    headers: <String, String>{'x-consumer-trace': '$label-registration-lookup'},
  );
  final registrationId = (registrationLookup.arguments.single as num).toInt();
  expect(registrationId, greaterThan(0));

  final registrationMatch = await client.matchWampRegistrationDirect(
    procedure,
    id: '$label-registration-match',
    headers: <String, String>{'x-consumer-trace': '$label-registration-match'},
  );
  expect(registrationMatch.arguments, contains(registrationId));

  final registrationList = await client.listWampRegistrationsDirect(
    id: '$label-registration-list',
    headers: <String, String>{'x-consumer-trace': '$label-registration-list'},
  );
  final exactRegistrations =
      (registrationList.argumentsKeywords['exact'] as List).cast<Object?>();
  expect(exactRegistrations, contains(registrationId));

  final registrationGet = await client.getWampRegistrationDirect(
    registrationId,
    id: '$label-registration-get',
    headers: <String, String>{'x-consumer-trace': '$label-registration-get'},
  );
  expect(registrationGet.argumentsKeywords['uri'], equals(procedure));

  final registrationCallees = await client.listWampRegistrationCalleesDirect(
    registrationId,
    id: '$label-registration-callees',
    headers: <String, String>{
      'x-consumer-trace': '$label-registration-callees',
    },
  );
  expect(registrationCallees.arguments, isEmpty);
  expect(
    registrationCallees.arguments,
    isNot(contains(serviceSession.sessionId)),
  );

  final registrationCalleeCount = await client
      .countWampRegistrationCalleesDirect(
        registrationId,
        id: '$label-registration-callee-count',
        headers: <String, String>{
          'x-consumer-trace': '$label-registration-callee-count',
        },
      );
  expect(registrationCalleeCount.arguments, equals([0]));

  final subscription = await client.subscribeWampTopicDirect(
    topic,
    id: '$label-subscribe',
    queueLimit: 2,
    headers: <String, String>{'x-consumer-trace': '$label-subscribe'},
  );
  try {
    final subscriptionId = subscription.subscriptionId;
    expect(subscriptionId, isNotNull);
    expect(subscriptionId, greaterThan(0));

    final subscriptionLookup = await client.lookupWampSubscriptionDirect(
      topic,
      id: '$label-subscription-lookup',
      match: 'exact',
      headers: <String, String>{
        'x-consumer-trace': '$label-subscription-lookup',
      },
    );
    expect(subscriptionLookup.arguments, contains(subscriptionId));

    final subscriptionMatch = await client.matchWampSubscriptionDirect(
      topic,
      id: '$label-subscription-match',
      headers: <String, String>{
        'x-consumer-trace': '$label-subscription-match',
      },
    );
    expect(subscriptionMatch.arguments, contains(subscriptionId));

    final subscriptionList = await client.listWampSubscriptionsDirect(
      id: '$label-subscription-list',
      headers: <String, String>{'x-consumer-trace': '$label-subscription-list'},
    );
    final exactSubscriptions =
        (subscriptionList.argumentsKeywords['exact'] as List).cast<Object?>();
    expect(exactSubscriptions, contains(subscriptionId));

    final subscriptionGet = await client.getWampSubscriptionDirect(
      subscriptionId!,
      id: '$label-subscription-get',
      headers: <String, String>{'x-consumer-trace': '$label-subscription-get'},
    );
    expect(subscriptionGet.argumentsKeywords['uri'], equals(topic));

    final subscriptionSubscribers = await client
        .listWampSubscriptionSubscribersDirect(
          subscriptionId,
          id: '$label-subscription-subscribers',
          headers: <String, String>{
            'x-consumer-trace': '$label-subscription-subscribers',
          },
        );
    expect(subscriptionSubscribers.arguments, contains(visibleSessionId));
    expect(
      subscriptionSubscribers.arguments,
      isNot(contains(serviceSession.sessionId)),
    );

    final subscriptionSubscriberCount = await client
        .countWampSubscriptionSubscribersDirect(
          subscriptionId,
          id: '$label-subscription-subscriber-count',
          headers: <String, String>{
            'x-consumer-trace': '$label-subscription-subscriber-count',
          },
        );
    expect(subscriptionSubscriberCount.arguments, equals([1]));
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: '$label-unsubscribe',
      headers: <String, String>{'x-consumer-trace': '$label-unsubscribe'},
    );
  }

  expect(client.sessionId, equals(previousSessionId));
  expect(client.lastEventId, equals(previousEventId));
}

Future<void> _expectDirectSafeLookupMethod(
  McpStreamableHttpClient client, {
  required String taskId,
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final result = await client.callConnectanumMethodDirect(
    'app.safe.lookup',
    id: '$label-direct-safe-method',
    params: {'taskId': taskId, 'id': taskId},
    headers: <String, String>{'x-consumer-trace': '$label-direct-safe-method'},
  );
  expect(result['isError'], isFalse);
  expect(jsonEncode(result['structuredContent']), contains(taskId));
  expect(client.sessionId, equals(previousSessionId));
  expect(client.lastEventId, equals(previousEventId));
}

Future<void> _expectDirectSafeLookupNotifications(
  McpStreamableHttpClient client,
  Set<String> observedTaskIds, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final standardTaskId = 'T-$label-direct-standard-tool-notify';
  await client.notifyToolDirect(
    'app.safe.lookup',
    arguments: {'taskId': standardTaskId},
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-standard-tool-notify',
    },
  );
  await _expectSafeLookupObserved(
    observedTaskIds,
    standardTaskId,
    label: '$label standard tool notification',
  );

  final helperTaskId = 'T-$label-direct-tool-helper-notify';
  await client.notifyConnectanumToolDirect(
    'app.safe.lookup',
    arguments: {'taskId': helperTaskId},
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-tool-helper-notify',
    },
  );
  await _expectSafeLookupObserved(
    observedTaskIds,
    helperTaskId,
    label: '$label tool helper notification',
  );

  final dottedTaskId = 'T-$label-direct-dotted-method-notify';
  await client.notifyConnectanumMethodDirect(
    'app.safe.lookup',
    params: {'taskId': dottedTaskId},
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-dotted-method-notify',
    },
  );
  await _expectSafeLookupObserved(
    observedTaskIds,
    dottedTaskId,
    label: '$label dotted method notification',
  );

  final pluralAliasTaskId = 'T-$label-direct-tools-call-alias-notify';
  await client.notifyConnectanumMethodDirect(
    'connectanum.tools.call',
    params: {
      'name': 'app.safe.lookup',
      'arguments': {'taskId': pluralAliasTaskId},
    },
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-tools-call-alias-notify',
    },
  );
  await _expectSafeLookupObserved(
    observedTaskIds,
    pluralAliasTaskId,
    label: '$label plural tool alias notification',
  );

  expect(client.sessionId, equals(previousSessionId));
  expect(client.lastEventId, equals(previousEventId));
}

Future<void> _expectSafeLookupObserved(
  Set<String> observedTaskIds,
  String taskId, {
  required String label,
}) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (observedTaskIds.contains(taskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for app.safe.lookup notification: $label');
}

Future<Map<String, Object?>> _pollStreamableMcpUntilEvents(
  McpStreamableHttpClient client,
  String handle,
) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final response = await client.request(
      'tools/call',
      id: 'streamable-pubsub-poll-$attempt',
      params: {
        'name': 'connectanum.pubsub.poll',
        'arguments': {'handle': handle, 'limit': 10},
      },
    );
    final result = (response['result'] as Map).cast<String, Object?>();
    final structured = (result['structuredContent'] as Map)
        .cast<String, Object?>();
    final events = structured['events'] as List? ?? const [];
    if (events.isNotEmpty) {
      return structured;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for Streamable MCP subscription events for $handle');
}

Future<Map<String, Object?>> _pollStreamableMcpUntilResourceUpdate(
  McpStreamableHttpClient client,
  String resourceUri,
) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final events = await client.poll();
    for (final event in events) {
      final message = event.jsonData;
      if (message?['method'] != 'notifications/resources/updated') {
        continue;
      }
      final params = message?['params'];
      if (params is Map && params['uri'] == resourceUri) {
        return message!;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for MCP resource update for $resourceUri');
}

Future<ConnectanumHttpAuthGrant> _issueTicketHttp3Grant(
  String nativeLibPath,
  int port, {
  String realm = 'realm1',
  String authId = 'user-1',
  String ticket = 'signed-token',
}) async {
  final start = await _postHttp3Json(
    nativeLibPath,
    port,
    '/auth',
    {'realm': realm, 'authmethod': 'ticket', 'authid': authId},
    headers: {HttpHeaders.acceptHeader: 'application/json'},
  );
  expect(start.statusCode, equals(HttpStatus.unauthorized), reason: start.body);
  final state = start.json?['state'];
  expect(state, isA<String>());

  final authenticate = await core.TicketAuthentication(
    ticket,
  ).challenge(core.Extra());
  final success = await _postHttp3Json(
    nativeLibPath,
    port,
    '/auth',
    {
      'state': state as String,
      'signature': authenticate.signature,
      'extra': authenticate.extra,
    },
    headers: {HttpHeaders.acceptHeader: 'application/json'},
  );
  expect(success.statusCode, equals(HttpStatus.ok), reason: success.body);
  final successJson = success.json;
  expect(successJson, isNotNull);
  return ConnectanumHttpAuthGrant.fromJson(successJson!);
}

Future<ConnectanumHttpAuthGrant> _issueTicketHttpGrant(
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
  return ConnectanumHttpAuthGrant.fromJson(successJson!);
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
