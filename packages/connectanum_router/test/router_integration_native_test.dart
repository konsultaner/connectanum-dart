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
  int pollConnection(int listenerId) {
    final actualId = _inner.pollConnection(listenerId);
    if (actualId > 0) {
      if (_connections.isNotEmpty) {
        final synthetic = _connections.removeFirst();
        _syntheticConnections.remove(synthetic);
        _connectionMap[synthetic] = actualId;
        // ignore: avoid_print
        print(
          'hybrid: mapping synthetic $synthetic -> actual $actualId (listener $listenerId)',
        );
        return synthetic;
      }
      // ignore: avoid_print
      print(
        'hybrid: returning actual connection $actualId for listener $listenerId',
      );
      return actualId;
    }
    if (_connections.isNotEmpty) {
      final peek = _connections.first;
      if (_syntheticConnections.contains(peek)) {
        // ignore: avoid_print
        print(
          'hybrid: returning synthetic connection $peek for listener $listenerId',
        );
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
    final protocol = _inner.connectionProtocol(resolved);
    // ignore: avoid_print
    print(
      'hybrid: connectionProtocol synthetic $connectionId resolved $resolved -> $protocol',
    );
    return protocol;
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
    final handshake = _inner.pollHttp3Request(resolved);
    if (handshake != null) {
      // ignore: avoid_print
      print(
        'hybrid: polled http/3 request for synthetic $connectionId (actual $resolved) '
        '${handshake.method} ${handshake.path}',
      );
    }
    return handshake;
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
  NativeRouterMetrics? pollRouterMetrics() => _inner.pollRouterMetrics();

  @override
  void applyRouterConfig(Uint8List config) => _inner.applyRouterConfig(config);

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

  Map<String, Object?>? _takePending(String type) {
    for (final event in _pendingEvents) {
      if (event['type'] == type) {
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

void main() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('Router + FFI test mode', () {
    group('publish ack path', () {
      // Skipped: rawsocket publish ACK is covered by publish_ack_test.dart.
      test('publish acked for each routed event', () async {}, skip: true);
    });

    test('forwards progressive and final results', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      await harness.registerProcedure();

      const requestId = 42;
      harness.enqueueCall(requestId: requestId, receiveProgress: true);
      final invocationEvent = await harness.nextEvent(
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueYield(
        invocationId: invocationId,
        progress: true,
        arguments: const ['chunk'],
      );
      final progressEvent = await harness.nextEvent(
        'worker_forward_native_result',
      );
      expect(progressEvent['progress'], isTrue);
      expect(progressEvent['requestId'], equals(requestId));

      harness.enqueueYield(
        invocationId: invocationId,
        progress: false,
        arguments: const ['complete'],
      );
      final finalEvent = await harness.nextEvent(
        'worker_forward_native_result',
      );
      expect(finalEvent['progress'], isFalse);
      expect(finalEvent['requestId'], equals(requestId));

      await harness.expectInvocationCleared(invocationId);
    }, skip: skipReason);

    test('propagates callee errors', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      await harness.registerProcedure();

      const requestId = 99;
      harness.enqueueCall(requestId: requestId);
      final invocationEvent = await harness.nextEvent(
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueInvocationError(
        invocationId: invocationId,
        errorUri: 'wamp.error.runtime_error',
      );

      final errorEvent = await harness.nextEvent('worker_forward_native_error');
      expect(errorEvent['connectionId'], equals(9102));
      expect(errorEvent['requestId'], equals(requestId));

      await harness.expectInvocationCleared(invocationId);
    }, skip: skipReason);

    test('handles caller cancellation', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      await harness.registerProcedure();

      const requestId = 123;
      harness.enqueueCall(requestId: requestId);
      final invocationEvent = await harness.nextEvent(
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueCancel(requestId: requestId, mode: 'killnowait');

      await harness.nextEvent('worker_forward_message');

      await harness.expectInvocationCleared(invocationId);
    }, skip: skipReason);

    test(
      'forwards native events to subscribers',
      () async {
        if (!_forwardNativePublishEventsEnabled) {
          // ignore: avoid_print
          print(
            'Skipping native publish forwarding test: CONNECTANUM_FORWARD_NATIVE_PUBLISH not enabled',
          );
          return;
        }

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
      skip: skipReason ?? _nativePublishSkipReason,
    );

    test('routes HTTP request through native runtime', () async {
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
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull, reason: 'Invocation missing HTTP context');
        final body = context!.request.body;
        expect(body, isNotNull);
        expect(body!.length, equals(requestPayload.length));
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
    }, skip: skipReason);

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

String? _resolveNativeLib() {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  const candidates = [
    'native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/debug/libct_ffi.so',
    'native/transport/target/ffi-test/debug/libct_ffi.so',
    '../../native/transport/target/ffi-test/debug/libct_ffi.so',
    'native/transport/target/ffi-test/release/libct_ffi.so',
    '../../native/transport/target/ffi-test/release/libct_ffi.so',
    'native/transport/target/release/libct_ffi.so',
    '../../native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/release/libct_ffi.so',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
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

RouterSettings _buildSettings() => _buildRouterSettings(enableHttp3: false);
RouterSettings _buildTlsSettings() => _buildRouterSettings(enableHttp3: true);

RouterSettings _buildRouterSettings({required bool enableHttp3}) {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')..allowOperations(const [
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
      RoleSettingsBuilder('bench')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')..allowOperations(const [
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
  listener
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      HttpListenerSettings(
        alpn: enableHttp3
            ? const ['http/1.1', 'h2', 'h3']
            : const ['http/1.1', 'h2'],
        http3: enableHttp3 ? const Http3Settings(enabled: true) : null,
        routes: const [
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/api/health'),
            action: HttpRouteAction(
              type: HttpRouteActionType.rpc,
              procedure: 'com.example.http.health',
              realm: 'realm1',
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/api/stream'),
            action: HttpRouteAction(
              type: HttpRouteActionType.rpc,
              procedure: 'com.example.http.stream',
              realm: 'realm1',
            ),
          ),
        ],
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  return RouterSettingsBuilder()
      .addRealmFromBuilder(realmBuilder)
      .addRealmFromBuilder(benchRealm)
      .addListenerFromBuilder(listener)
      .addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
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
