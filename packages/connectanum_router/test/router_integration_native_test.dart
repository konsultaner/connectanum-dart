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

      final missingMethodHeader = await _postJson(
        client,
        listener.port,
        '/mcp',
        payload,
        headers: {
          'origin': 'http://127.0.0.1:${listener.port}',
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        },
      );
      expect(missingMethodHeader.statusCode, equals(HttpStatus.badRequest));
      expect(
        (missingMethodHeader.json?['error'] as Map<String, Object?>)['code'],
        equals(-32001),
      );
      expect(
        jsonEncode(missingMethodHeader.json?['error']),
        contains('Mcp-Method'),
      );

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

      await serviceSession.register(
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

        final primaryMcpClient = McpStreamableHttpClient.withAuthGrant(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/secure',
          ),
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
          streamableMissingBearer.headers['mcp-session-id'],
          equals(primarySessionId),
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
          jsonEncode(reuseWithOtherPrincipal.json?['error']),
          contains('Unknown MCP HTTP session'),
        );

        final publicRouteReuse =
            await _postJson(httpClient, listener.port, '/mcp/public', {
              'jsonrpc': '2.0',
              'id': 'cross-route-tools',
              'method': 'tools/list',
              'params': {},
            }, headers: toolsHeaders);
        expect(publicRouteReuse.statusCode, equals(HttpStatus.notFound));
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
      'deletes MCP Streamable HTTP sessions and cleans up pubsub subscribers',
      () async {
        final harness = await _RouterHarness.start(
          connectionId: 9117,
          nativeLib: nativeLib,
          settings: _buildMcpSmokeSettings(),
        );
        addTearDown(harness.dispose);

        final listener = harness.binding.listeners.single;
        final httpClient = HttpClient();
        addTearDown(() => httpClient.close(force: true));

        final mcpClient = McpStreamableHttpClient(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: listener.port,
            path: '/mcp/public',
          ),
        );
        addTearDown(() => mcpClient.close(force: true));

        await mcpClient.initialize(id: 'cleanup-initialize');
        await mcpClient.notifyInitialized();
        final subscription = await mcpClient.subscribeWampTopic(
          'app.events.audit',
          id: 'cleanup-subscribe',
          queueLimit: 5,
        );
        final subscriptionId = subscription.subscriptionId;
        expect(subscriptionId, isNotNull);

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

        await mcpClient.deleteSession();
        expect(mcpClient.sessionId, isNull);

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
        contains('app://mcp/context'),
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
        contains('app://mcp/context'),
      );

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
            'argumentsKeywords': {'via': 'streamable-publish'},
            'acknowledge': true,
          },
        },
      );
      final streamablePublishResult =
          ((streamablePublish['result'] as Map)['structuredContent'] as Map)
              .cast<String, Object?>();
      expect(streamablePublishResult['acknowledged'], isTrue);

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

      await serviceSession.publish(
        'app.events.audit',
        argumentsKeywords: {'via': 'streamable-service'},
        options: core.PublishOptions(acknowledge: true),
      );
      final streamablePoll = await _pollStreamableMcpUntilEvents(
        streamableClient,
        streamableHandle,
      );
      expect(
        jsonEncode(streamablePoll['events']),
        contains('streamable-service'),
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

      final grant = await _issueTicketHttpGrant(client, listener.port);
      final authHeaders = {'authorization': 'Bearer ${grant.accessToken}'};
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
      expect(directSecureMcpClient.sessionId, isNull);

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
        match: const HttpRouteMatch(path: '/mcp'),
        action: HttpRouteAction(
          type: HttpRouteActionType.mcp,
          realm: 'realm1',
          options: effectiveMcpOptions,
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
