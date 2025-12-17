part of '../router_instance.dart';

/// Immutable snapshot of an HTTP request surfaced by the native runtime.
class RouterHttpRequest {
  RouterHttpRequest({
    required this.listener,
    required this.connectionId,
    required this.method,
    required this.target,
    required this.path,
    required this.protocol,
    required this.version,
    required Map<String, String> headers,
    required NativeHttpRequestBody body,
    required this.handshakeHandle,
    this.query,
    this.realm,
    this.procedure,
  }) : headers = Map.unmodifiable(headers),
       _body = body;

  final RouterListener listener;
  final int connectionId;
  final String method;
  final String target;
  final String path;
  final String protocol;
  final int version;
  final Map<String, String> headers;
  final NativeHttpRequestBody _body;
  final int handshakeHandle;
  final String? query;
  final String? realm;
  final String? procedure;
  Uint8List? _bodyCache;

  int get listenerId => listener.listenerId;
  String get endpoint => '${listener.endpoint.host}:${listener.endpoint.port}';

  Uint8List get body => _bodyCache ??= _body.view;
  NativeHttpRequestBody get nativeBody => _body;

  HttpRequestSnapshot toSnapshot(int requestId) => HttpRequestSnapshot(
    id: requestId,
    method: method,
    target: target,
    path: path,
    protocol: protocol,
    version: version,
    headers: headers,
    body: _body.copy(),
    query: query,
    realm: realm,
    procedure: procedure,
  );
}

/// Public façade that wires the Dart router to the native transport runtime.
///
/// The binding owns all active listeners, polls for new connections/messages,
/// and delegates heavy lifting to worker isolates when the platform supports
/// native isolates. Call [dispose] to tear everything down and release native
/// resources once routing stops.
class RouterBinding {
  RouterBinding({
    required this.runtime,
    required List<Endpoint> endpoints,
    required this.configJson,
    required this.settings,
    this.workerEntryPoint = _routerWorkerEntryPoint,
    this.workerPollInterval = const Duration(milliseconds: 1),
    this.onEvent,
  }) : _pendingEndpoints = List<Endpoint>.unmodifiable(endpoints),
       _listenerSettingsByEndpoint = Map<String, ListenerSettings>.fromEntries(
         settings.listeners.map(
           (listener) => MapEntry(
             _normalizeConfiguredEndpoint(listener.endpoint),
             listener,
           ),
         ),
       );

  final NativeRuntime runtime;
  final Uint8List configJson;
  final RouterSettings settings;
  final RouterWorkerEntryPoint workerEntryPoint;
  final Duration workerPollInterval;
  final void Function(Object event)? onEvent;

  final List<Endpoint> _pendingEndpoints;
  final List<RouterListener> _listeners = [];
  final Map<int, RouterListener> _listenerById = {};
  final Map<int, _ConnectionState> _connections = {};
  final Set<RouterSession> _internalSessions = {};
  final Map<String, RouterSession> _internalSessionsByRealm = {};
  final Map<int, _PendingHttpCall> _pendingHttpCalls = {};
  final Map<String, ListenerSettings> _listenerSettingsByEndpoint;
  final Map<int, ListenerSettings?> _listenerConfigById = {};
  Future<void>? _internalBootstrap;
  Object? _internalBootstrapError;
  StackTrace? _internalBootstrapStack;
  _MetricsService? _metricsService;
  NativeMessageHandleDecoder? _handleDecoder;
  _RouterBoss? _boss;
  bool _ready = false;
  int _nextHttpRequestId = 1;
  HttpServer? _openMetricsHttpServer;
  Future<HttpServer?>? _openMetricsHttpServerFuture;

  List<RouterListener> get listeners =>
      List<RouterListener>.unmodifiable(_listeners);

  bool get isReady => _ready;

  void activateListeners() {
    if (_ready) {
      return;
    }
    for (final endpoint in _pendingEndpoints) {
      final listenerId = runtime.listen(endpoint.host, endpoint.port);
      final boundPort = runtime.getLocalPort(listenerId);
      final http3Port = runtime.getHttp3Port(listenerId);
      final config = _lookupListenerSettings(endpoint);
      final listener = RouterListener(
        listenerId: listenerId,
        endpoint: endpoint,
        port: boundPort,
        http3Port: http3Port,
        settings: config,
      );
      _listenerConfigById[listenerId] = config;
      if (config != null) {
        final pendingProtocols = config.protocols
            .where((protocol) => protocol != ListenerProtocol.rawsocket)
            .map(listenerProtocolToString)
            .toList(growable: false);
        if (pendingProtocols.isNotEmpty) {
          onEvent?.call({
            'source': 'binding',
            'type': 'listener_protocol_pending',
            'listenerId': listenerId,
            'endpoint': '${endpoint.host}:${endpoint.port}',
            'protocols': pendingProtocols,
          });
        }
      }
      _listeners.add(listener);
      _listenerById[listener.listenerId] = listener;
    }
    if (supportsNativeIsolates && runtime is NativeRuntimeWithHandles) {
      final handlesRuntime = runtime as NativeRuntimeWithHandles;
      _boss = _RouterBoss(
        runtime: handlesRuntime,
        listeners: _listeners,
        pollInterval: workerPollInterval,
        entryPoint: workerEntryPoint,
        libraryPathHint: handlesRuntime.libraryPathHint,
        settings: settings,
        onEvent: onEvent,
        onHttpRequest: _handleHttpRequest,
      )..start();
    }
    _ready = true;
    _scheduleInternalBootstrap();
  }

  Future<int> _allocateSessionId(SendPort statePort) async {
    final replyPort = ReceivePort();
    statePort.send(SessionAllocateIdCommand(replyPort: replyPort.sendPort));
    final id = await replyPort.first as int;
    replyPort.close();
    return id;
  }

  Future<RouterSession> createInternalSession({
    required String realmUri,
    String? authId,
    String? authRole,
    Map<String, Object?> roles = const {},
  }) async {
    if (!_ready) {
      activateListeners();
    }
    final boss = _boss;
    if (boss == null) {
      throw StateError(
        'Embedded sessions require native isolate support on this platform.',
      );
    }
    final statePort = boss.stateCommandPort;
    final sessionId = await _allocateSessionId(statePort);
    final controlPort = ReceivePort();
    final handshakePort = ReceivePort();
    final isolate = await Isolate.spawn<_InternalSessionBootstrap>(
      _routerInternalSessionIsolate,
      _InternalSessionBootstrap(
        sessionId: sessionId,
        realmUri: realmUri,
        authId: authId,
        authRole: authRole,
        roles: roles,
        statePort: statePort,
        controlPort: controlPort.sendPort,
        handshakePort: handshakePort.sendPort,
      ),
      debugName: 'router-internal-session-$sessionId',
    );
    final handshake = await handshakePort.first;
    handshakePort.close();
    if (handshake is! Map ||
        handshake['commandPort'] is! SendPort ||
        handshake['invocationPort'] is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw StateError('Failed to initialize internal session isolate');
    }
    final requestPort = handshake['commandPort'] as SendPort;
    final internalPort = handshake['invocationPort'] as SendPort;
    final internalEndpoint = Endpoint(
      host: 'internal',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
    );
    final listenerSettings = _lookupListenerSettings(internalEndpoint);
    final listener = RouterListener(
      listenerId: -sessionId,
      endpoint: internalEndpoint,
      port: 0,
      http3Port: 0,
      settings: listenerSettings,
    );
    final responsePort = ReceivePort();
    final session = RouterSession._(
      binding: this,
      sessionId: sessionId,
      realmUri: realmUri,
      authId: authId,
      authRole: authRole,
      roles: roles,
      commandPort: requestPort,
      controlPort: controlPort,
      controlSubscription: null,
      responsePort: responsePort,
      isolate: isolate,
    );
    session._attachControlListener();
    final record = SessionRecord(
      id: sessionId,
      authId: authId,
      authRole: authRole,
      roles: roles,
      workerId: 0,
      connectionId: -sessionId,
      lastActivity: DateTime.now(),
      listener: listener,
      protocol: listenerSettings?.primaryProtocol ?? ListenerProtocol.rawsocket,
      internalSendPort: internalPort,
    );
    statePort.send(SessionOpenCommand(realmUri: realmUri, session: record));
    _internalSessions.add(session);
    _internalSessionsByRealm[realmUri] = session;
    return session;
  }

  /// Polls the native runtime for pending messages and returns them eagerly.
  ///
  /// This is primarily used in single-isolate environments (e.g. web) where we
  /// fall back to timer-based polling instead of worker isolates.
  List<RouterMessage> pollNativeMessages({int maxMessages = 256}) {
    if (!_ready) {
      throw StateError(
        'Router listeners are not active yet. Call activateListeners() first.',
      );
    }
    if (_boss != null) {
      return const [];
    }
    if (maxMessages <= 0) {
      return const [];
    }
    for (final listener in listeners) {
      _acceptConnections(listener);
    }
    final result = <RouterMessage>[];
    final handlesRuntime = runtime is NativeRuntimeWithHandles
        ? runtime as NativeRuntimeWithHandles
        : null;
    if (_boss == null && handlesRuntime != null && _handleDecoder == null) {
      _handleDecoder = NativeMessageHandleDecoder(
        libraryPath: handlesRuntime.libraryPathHint,
      );
    }
    for (final entry in _connections.entries) {
      final connectionId = entry.key;
      final state = entry.value;
      while (result.length < maxMessages) {
        if (handlesRuntime != null && _boss == null) {
          var handle = handlesRuntime.pollMessageHandle(connectionId);
          if (handle == 0) {
            handle = handlesRuntime.pollWebSocketMessageHandle(connectionId);
          }
          if (handle == 0) {
            break;
          }
          final decoder = _handleDecoder!;
          try {
            final message = decoder.materialize(handle);
            result.add(RouterMessage(state.listener, connectionId, message));
          } catch (_) {
            decoder.release(handle);
            rethrow;
          }
          continue;
        } else {
          final message = runtime.pollMessage(connectionId);
          if (message == null) {
            break;
          }
          result.add(RouterMessage(state.listener, connectionId, message));
        }
      }
      if (result.length >= maxMessages) {
        break;
      }
    }
    return result;
  }

  Future<void> ensureInternalServicesReady() async {
    await (_internalBootstrap ?? Future<void>.value());
    if (_internalBootstrapError != null) {
      Error.throwWithStackTrace(
        _internalBootstrapError!,
        _internalBootstrapStack ?? StackTrace.current,
      );
    }
  }

  Future<RouterMetricsSnapshot> collectMetrics() async {
    final boss = _boss;
    if (boss == null) {
      throw StateError(
        'Metrics collection requires worker isolates and the native runtime.',
      );
    }
    final reply = ReceivePort();
    boss.bossCommandPort.send(_BossGetMetricsCommand(reply.sendPort));
    final response = await reply.first;
    reply.close();
    if (response is RouterMetricsSnapshot) {
      return response;
    }
    if (response is StoreErrorResponse) {
      throw StateError('Failed to collect metrics: ${response.message}');
    }
    throw StateError('Unexpected metrics response: $response');
  }

  Future<String?> collectOpenMetricsText([
    RouterMetricsSnapshot? snapshot,
  ]) async {
    final service = _metricsService;
    if (service == null) {
      return null;
    }
    return service.buildOpenMetricsPayload(snapshot: snapshot);
  }

  Future<HttpServer?> startOpenMetricsHttpServer({
    OpenMetricsSettings? settingsOverride,
  }) async {
    final metricsSettings = settingsOverride ?? settings.metrics?.openMetrics;
    if (metricsSettings == null || !metricsSettings.enabled) {
      return null;
    }
    final listen = metricsSettings.listen?.trim();
    if (listen == null || listen.isEmpty) {
      return null;
    }
    final existing = _openMetricsHttpServer;
    if (existing != null) {
      return existing;
    }
    final pending = _openMetricsHttpServerFuture;
    if (pending != null) {
      return pending;
    }
    final future = _startOpenMetricsHttpServer(metricsSettings, listen);
    _openMetricsHttpServerFuture = future;
    try {
      return await future;
    } finally {
      _openMetricsHttpServerFuture = null;
    }
  }

  Future<void> stopOpenMetricsHttpServer() async {
    _openMetricsHttpServerFuture = null;
    final server = _openMetricsHttpServer;
    if (server == null) {
      return;
    }
    _openMetricsHttpServer = null;
    await server.close(force: true);
  }

  Future<HttpServer> _startOpenMetricsHttpServer(
    OpenMetricsSettings metricsSettings,
    String listen,
  ) async {
    if (!_ready) {
      activateListeners();
    }
    await ensureInternalServicesReady();

    final parsed = _parseListenEndpoint(listen);
    final address = InternetAddress.tryParse(parsed.host) ?? parsed.host.trim();
    final server = await HttpServer.bind(address, parsed.port);
    _openMetricsHttpServer = server;

    final metricsPath = _normalizePath(metricsSettings.path);
    server.listen(
      (request) => unawaited(
        _handleOpenMetricsHttpRequest(request, metricsSettings, metricsPath),
      ),
    );

    onEvent?.call({
      'source': 'binding',
      'type': 'openmetrics_http_listening',
      'listen': '${server.address.address}:${server.port}',
      'path': metricsPath,
    });

    return server;
  }

  Future<void> _handleOpenMetricsHttpRequest(
    HttpRequest request,
    OpenMetricsSettings metricsSettings,
    String metricsPath,
  ) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    final path = request.uri.path;
    if (path == '/healthz' || path == '/health') {
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.text;
      if (request.method == 'GET') {
        response.write('ok');
      }
      await response.close();
      return;
    }

    if (path != metricsPath) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final expectedToken = metricsSettings.authToken;
    if (expectedToken != null && expectedToken.isNotEmpty) {
      final header = request.headers.value(HttpHeaders.authorizationHeader);
      final bearer = 'Bearer $expectedToken';
      if (header == null || header != bearer) {
        response.statusCode = HttpStatus.unauthorized;
        response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        await response.close();
        return;
      }
    }

    final text = await collectOpenMetricsText();
    if (text == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/plain; version=0.0.4; charset=utf-8',
    );
    if (request.method == 'GET') {
      response.write(text);
    }
    await response.close();
  }

  void _acceptConnections(RouterListener listener) {
    while (true) {
      final connectionId = runtime.pollConnection(listener.listenerId);
      if (connectionId == 0) {
        break;
      }
      NativeConnectionProtocol protocol;
      try {
        protocol = runtime.connectionProtocol(connectionId);
      } on NativeTransportException {
        protocol = NativeConnectionProtocol.rawsocket;
      }
      final state = _connections.putIfAbsent(
        connectionId,
        () => _ConnectionState(listener),
      );
      if (protocol == NativeConnectionProtocol.websocket) {
        final handshake = runtime.takeWebSocketHandshake(connectionId);
        if (handshake == null) {
          onEvent?.call({
            'source': 'binding',
            'type': 'listener_websocket_handshake_missing',
            'listenerId': listener.listenerId,
            'connectionId': connectionId,
          });
          continue;
        }
        final selection = _selectWebSocketProtocol(handshake.protocols);
        if (selection == null) {
          runtime.rejectWebSocket(
            connectionId: connectionId,
            handshakeHandle: handshake.handle,
            status: 426,
            reason: 'unsupported subprotocol',
          );
          handshake.release();
          continue;
        }
        try {
          runtime.acceptWebSocket(
            connectionId: connectionId,
            handshakeHandle: handshake.handle,
            serializer: selection.serializer,
            protocol: selection.protocol,
          );
          handshake.consume();
        } on NativeTransportException catch (error) {
          handshake.release();
          onEvent?.call({
            'source': 'binding',
            'type': 'listener_websocket_accept_error',
            'listenerId': listener.listenerId,
            'connectionId': connectionId,
            'error': error.toString(),
          });
          continue;
        }
        continue;
      }
      if (protocol == NativeConnectionProtocol.http3) {
        final connectionHandle = runtime.takeHttp3Connection(connectionId);
        state.setHttp3Connection(connectionHandle);
      }
    }
  }

  /// Continuously polls native events and emits them as a stream.
  ///
  /// Callers must eventually call `dispose` on each [RouterMessage.message] they
  /// consume so the underlying native handles can be released.
  Stream<RouterMessage> watchNativeMessages({
    Duration pollInterval = const Duration(milliseconds: 10),
    int maxMessagesPerTick = 256,
  }) {
    if (!_ready) {
      throw StateError(
        'Router listeners are not active yet. Call activateListeners() first.',
      );
    }
    if (_boss != null) {
      return const Stream<RouterMessage>.empty();
    }
    final controller = StreamController<RouterMessage>();

    if (supportsNativeIsolates) {
      bool paused = false;
      bool cancelled = false;
      Future<void>? loopFuture;

      Future<void> loop() async {
        while (!controller.isClosed && !paused && !cancelled) {
          final messages = pollNativeMessages(maxMessages: maxMessagesPerTick);
          for (final message in messages) {
            if (controller.isClosed || paused || cancelled) {
              message.message.dispose();
              break;
            }
            controller.add(message);
          }
          if (controller.isClosed || paused || cancelled) {
            break;
          }
          await Future<void>.delayed(pollInterval);
        }
        loopFuture = null;
      }

      void ensureLoop() {
        if (loopFuture != null || controller.isClosed || paused || cancelled) {
          return;
        }
        loopFuture = loop();
      }

      controller
        ..onListen = () {
          paused = false;
          cancelled = false;
          ensureLoop();
        }
        ..onResume = () {
          paused = false;
          ensureLoop();
        }
        ..onPause = () {
          paused = true;
        }
        ..onCancel = () {
          cancelled = true;
        };
    } else {
      Timer? timer;

      late void Function() scheduleTick;

      void tick() {
        timer = null;
        if (controller.isClosed) {
          return;
        }
        final messages = pollNativeMessages(maxMessages: maxMessagesPerTick);
        for (final message in messages) {
          if (controller.isClosed) {
            message.message.dispose();
            break;
          }
          controller.add(message);
        }
        scheduleTick();
      }

      controller
        ..onListen = () {
          final messages = pollNativeMessages(maxMessages: maxMessagesPerTick);
          for (final message in messages) {
            controller.add(message);
          }
          if (!controller.isClosed) {
            scheduleTick();
          }
        }
        ..onPause = () {
          timer?.cancel();
          timer = null;
        }
        ..onResume = () {
          if (!controller.isClosed) {
            scheduleTick();
          }
        }
        ..onCancel = () {
          timer?.cancel();
          timer = null;
        };

      scheduleTick = () {
        timer?.cancel();
        timer = Timer(pollInterval, tick);
      };
    }

    return controller.stream;
  }

  /// Stops the background boss isolate (if running) and releases resources.
  Future<void> dispose() async {
    await stopOpenMetricsHttpServer();
    await _metricsService?.dispose();
    _metricsService = null;
    for (final session in _internalSessions.toList()) {
      await session.close();
    }
    _internalSessions.clear();
    _internalSessionsByRealm.clear();
    _listenerConfigById.clear();
    for (final state in _connections.values) {
      state.dispose();
    }
    _connections.clear();
    _internalBootstrap = null;
    _internalBootstrapError = null;
    _internalBootstrapStack = null;
    final boss = _boss;
    if (boss != null) {
      await boss.stop();
    }
  }

  void _removeInternalSession(RouterSession session) {
    _internalSessions.remove(session);
    final existing = _internalSessionsByRealm[session.realmUri];
    if (identical(existing, session)) {
      _internalSessionsByRealm.remove(session.realmUri);
    }
    if (_metricsService?.ownsSession(session) == true) {
      _metricsService = null;
    }
  }

  @visibleForTesting
  SendPort? get debugStatePort => _boss?.stateCommandPort;

  @visibleForTesting
  RouterSession? internalSessionForRealm(String realmUri) =>
      _internalSessionsByRealm[realmUri];

  @visibleForTesting
  ListenerSettings? listenerSettingsFor(int listenerId) =>
      _listenerConfigById[listenerId];

  ListenerSettings? _lookupListenerSettings(Endpoint endpoint) {
    final direct =
        _listenerSettingsByEndpoint[_endpointKey(endpoint.host, endpoint.port)];
    if (direct != null) {
      return direct;
    }
    return _listenerSettingsByEndpoint[_endpointKey(endpoint.host, 0)];
  }

  void forwardMessageToConnection(int connectionId, AbstractMessage message) {
    final boss = _boss;
    if (boss == null) {
      throw StateError('Router boss not running');
    }
    boss.forwardMessageToConnection(connectionId, message);
  }

  Future<void> _handleHttpRequest(
    RouterHttpRequest request,
    NativeHttpHandshake? handshake,
  ) async {
    // ignore: avoid_print
    print(
      'binding: handling HTTP request ${request.method} ${request.path} (${request.protocol}) '
      'conn=${request.connectionId}',
    );
    NativeHttpHandshake? retainedHandshake = handshake;
    final realmUri = request.realm;
    final procedure = request.procedure;
    if (realmUri == null || realmUri.isEmpty) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_request_unmapped_realm',
        'listenerId': request.listenerId,
        'connectionId': request.connectionId,
        'endpoint': request.endpoint,
      });
      retainedHandshake?.release();
      return;
    }
    if (procedure == null || procedure.isEmpty) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_request_unmapped_procedure',
        'listenerId': request.listenerId,
        'connectionId': request.connectionId,
        'endpoint': request.endpoint,
        'realm': realmUri,
      });
      retainedHandshake?.release();
      return;
    }

    final httpRequestId = _nextHttpRequestId++;
    final snapshot = request.toSnapshot(httpRequestId);
    RouterSession session;
    try {
      session = await _ensureInternalSession(realmUri);
    } catch (error, stackTrace) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_request_session_error',
        'listenerId': request.listenerId,
        'connectionId': request.connectionId,
        'endpoint': request.endpoint,
        'realm': realmUri,
        'procedure': procedure,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      retainedHandshake?.release();
      return;
    }

    final httpDetails = <String, Object?>{...snapshot.toInvocationPayload()};
    final connectionDetails = <String, Object?>{
      'listenerId': request.listenerId,
      'connectionId': request.connectionId,
      'endpoint': request.endpoint,
    };
    final keywords = <String, Object?>{
      '_http': httpDetails,
      '_connection': connectionDetails,
    };

    StreamSubscription<result_msg.Result>? subscription;
    try {
      final options = call_msg.CallOptions(
        custom: <String, dynamic>{
          HttpInvocationKeys.requestId: httpRequestId,
          HttpInvocationKeys.request: snapshot.toInvocationPayload(),
        },
      );
      final stream = session.call(
        procedure,
        argumentsKeywords: Map<String, dynamic>.from(keywords),
        options: options,
      );
      subscription = stream.listen(
        (result) {
          final progress = result.details.progress ?? false;
          onEvent?.call({
            'source': 'binding',
            'type': 'http_request_result',
            'httpRequestId': httpRequestId,
            'listenerId': request.listenerId,
            'connectionId': request.connectionId,
            'progress': progress,
            'arguments': result.arguments,
            'argumentsKeywords': result.argumentsKeywords,
          });
          final responsePayload = HttpResponsePayload.fromKeywordArguments(
            result.argumentsKeywords?.cast<String, Object?>(),
          );
          if (responsePayload != null) {
            final pending = _pendingHttpCalls[responsePayload.requestId];
            if (pending == null) {
              onEvent?.call({
                'source': 'binding',
                'type': 'http_response_missing_request',
                'httpRequestId': responsePayload.requestId,
                'listenerId': request.listenerId,
                'connectionId': request.connectionId,
              });
              return;
            }
            onEvent?.call({
              'source': 'binding',
              'type': 'http_response_ready',
              'httpRequestId': responsePayload.requestId,
              'listenerId': request.listenerId,
              'connectionId': request.connectionId,
              'response': responsePayload.toEventPayload(),
            });
            if (responsePayload.progress || pending.responseStream != null) {
              final sent = _forwardStreamingResponseChunk(
                pending,
                responsePayload,
              );
              if (!sent) {
                _completeHttpRequest(responsePayload.requestId);
                return;
              }
              if (!responsePayload.progress) {
                _finishStreamingResponse(pending);
              }
              return;
            }
            try {
              final handshakeHandle = pending.handshake?.handle ?? -1;
              if (handshakeHandle > 0) {
                runtime.sendHttpResponse(
                  handshakeHandle: handshakeHandle,
                  connectionId: request.connectionId,
                  response: _toNativeHttpResponse(responsePayload),
                );
                onEvent?.call({
                  'source': 'binding',
                  'type': 'http_response_sent',
                  'httpRequestId': responsePayload.requestId,
                  'listenerId': request.listenerId,
                  'connectionId': request.connectionId,
                });
              } else {
                onEvent?.call({
                  'source': 'binding',
                  'type': 'http_response_send_unsupported',
                  'httpRequestId': responsePayload.requestId,
                  'listenerId': request.listenerId,
                  'connectionId': request.connectionId,
                  'error': 'missing native handshake handle',
                });
              }
            } on UnsupportedError catch (error) {
              onEvent?.call({
                'source': 'binding',
                'type': 'http_response_send_unsupported',
                'httpRequestId': responsePayload.requestId,
                'listenerId': request.listenerId,
                'connectionId': request.connectionId,
                'error': error.toString(),
              });
            } catch (error, stackTrace) {
              onEvent?.call({
                'source': 'binding',
                'type': 'http_response_send_error',
                'httpRequestId': responsePayload.requestId,
                'listenerId': request.listenerId,
                'connectionId': request.connectionId,
                'error': error.toString(),
                'stackTrace': stackTrace.toString(),
              });
            } finally {
              _completeHttpRequest(responsePayload.requestId);
            }
          } else if (!progress) {
            _completeHttpRequest(httpRequestId);
          }
        },
        onError: (error, stack) {
          onEvent?.call({
            'source': 'binding',
            'type': 'http_request_error',
            'httpRequestId': httpRequestId,
            'listenerId': request.listenerId,
            'connectionId': request.connectionId,
            'error': error.toString(),
            if (stack is StackTrace) 'stackTrace': stack.toString(),
          });
          _completeHttpRequest(httpRequestId);
        },
        onDone: () {
          _completeHttpRequest(httpRequestId);
        },
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      subscription?.cancel();
      onEvent?.call({
        'source': 'binding',
        'type': 'http_request_dispatch_error',
        'listenerId': request.listenerId,
        'connectionId': request.connectionId,
        'endpoint': request.endpoint,
        'realm': realmUri,
        'procedure': procedure,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      retainedHandshake?.release();
      return;
    }

    _pendingHttpCalls[httpRequestId] = _PendingHttpCall(
      id: httpRequestId,
      request: request,
      snapshot: snapshot,
      session: session,
      subscription: subscription,
      handshake: retainedHandshake,
    );
    retainedHandshake = null;
    onEvent?.call({
      'source': 'binding',
      'type': 'http_request_dispatched',
      'httpRequestId': httpRequestId,
      'listenerId': request.listenerId,
      'connectionId': request.connectionId,
      'realm': realmUri,
      'procedure': procedure,
    });

    retainedHandshake?.release();
  }

  Future<RouterSession> _ensureInternalSession(String realmUri) async {
    final existing = _internalSessionsByRealm[realmUri];
    if (existing != null) {
      return existing;
    }
    return createInternalSession(realmUri: realmUri);
  }

  NativeHttpResponse _toNativeHttpResponse(HttpResponsePayload payload) {
    final headers = payload.headers;
    switch (payload.bodyKind) {
      case HttpResponseBodyKind.bytes:
        return NativeHttpResponse(
          status: payload.status,
          headers: headers,
          body: NativeHttpResponseBytes(payload.bodyBytes ?? Uint8List(0)),
        );
      case HttpResponseBodyKind.text:
        return NativeHttpResponse(
          status: payload.status,
          headers: headers,
          body: NativeHttpResponseText(
            payload.bodyText ?? '',
            encoding: payload.bodyEncoding ?? 'utf8',
          ),
        );
      case HttpResponseBodyKind.json:
        return NativeHttpResponse(
          status: payload.status,
          headers: headers,
          body: NativeHttpResponseJson(payload.bodyJson),
        );
      case HttpResponseBodyKind.file:
        throw UnsupportedError(
          'File-backed HTTP responses are not supported yet.',
        );
    }
  }

  bool _forwardStreamingResponseChunk(
    _PendingHttpCall pending,
    HttpResponsePayload payload,
  ) {
    final stream = _ensureStreamingResponse(pending, payload);
    if (stream == null) {
      return false;
    }
    final chunk = payload.encodeBodyBytes();
    if (chunk == null) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_response_stream_unsupported_body',
        'httpRequestId': pending.id,
        'listenerId': pending.request.listenerId,
        'connectionId': pending.request.connectionId,
        'bodyKind': payload.bodyKind.name,
      });
      return false;
    }
    if (chunk.isEmpty) {
      return true;
    }
    try {
      stream.add(chunk);
      return true;
    } catch (error, stackTrace) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_response_stream_error',
        'httpRequestId': pending.id,
        'listenerId': pending.request.listenerId,
        'connectionId': pending.request.connectionId,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      pending.responseStream = null;
      return false;
    }
  }

  NativeHttpResponseStream? _ensureStreamingResponse(
    _PendingHttpCall pending,
    HttpResponsePayload payload,
  ) {
    final existing = pending.responseStream;
    if (existing != null) {
      return existing;
    }
    final handshake = pending.handshake;
    if (handshake == null) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_response_stream_missing_handshake',
        'httpRequestId': pending.id,
        'listenerId': pending.request.listenerId,
        'connectionId': pending.request.connectionId,
      });
      return null;
    }
    try {
      final stream = runtime.openHttpResponseStream(
        handshakeHandle: handshake.handle,
        status: payload.status,
        headers: payload.headers,
      );
      pending.responseStream = stream;
      return stream;
    } on NativeTransportException catch (error, stackTrace) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_response_stream_open_error',
        'httpRequestId': pending.id,
        'listenerId': pending.request.listenerId,
        'connectionId': pending.request.connectionId,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      return null;
    }
  }

  void _finishStreamingResponse(_PendingHttpCall pending) {
    final stream = pending.responseStream;
    pending.responseStream = null;
    if (stream != null && !stream.isClosed) {
      try {
        stream.close();
      } catch (error, stackTrace) {
        onEvent?.call({
          'source': 'binding',
          'type': 'http_response_stream_finish_error',
          'httpRequestId': pending.id,
          'listenerId': pending.request.listenerId,
          'connectionId': pending.request.connectionId,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
      }
    }
    _completeHttpRequest(pending.id);
  }

  void _completeHttpRequest(int httpRequestId) {
    final pending = _pendingHttpCalls.remove(httpRequestId);
    final stream = pending?.responseStream;
    if (stream != null && !stream.isClosed) {
      try {
        stream.close();
      } catch (error, stackTrace) {
        onEvent?.call({
          'source': 'binding',
          'type': 'http_response_stream_finish_error',
          'httpRequestId': httpRequestId,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
      }
    }
    pending?.subscription.cancel();
    pending?.handshake?.release();
  }

  void _scheduleInternalBootstrap() {
    if (_internalBootstrap != null) {
      return;
    }
    final boss = _boss;
    if (boss == null) {
      return;
    }
    final requiresBootstrap =
        settings.internalRealms.isNotEmpty ||
        (settings.metrics?.openMetrics?.enabled ?? false);
    if (!requiresBootstrap) {
      return;
    }
    _internalBootstrapError = null;
    _internalBootstrapStack = null;
    _internalBootstrap = _bootstrapInternalRealmsAndServices(boss).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _internalBootstrapError = error;
      _internalBootstrapStack = stackTrace;
      onEvent?.call({
        'source': 'binding',
        'type': 'internal_bootstrap_error',
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
    });
  }

  Future<void> _bootstrapInternalRealmsAndServices(_RouterBoss boss) async {
    final metricsConfig = settings.metrics?.openMetrics;
    final bool metricsEnabled = metricsConfig?.enabled ?? false;
    var metricsConfigured = false;

    for (final internal in settings.internalRealms) {
      try {
        final session = await createInternalSession(
          realmUri: internal.name,
          authId: internal.authId,
          authRole: internal.authRole,
          roles: internal.roles,
        );
        if (metricsEnabled && internal.name == metricsConfig!.realm) {
          if (!internal.services.contains('metrics')) {
            throw StateError(
              'Internal realm "${internal.name}" must declare the "metrics" '
              'service when the OpenMetrics exporter is enabled.',
            );
          }
          final service = _MetricsService(
            binding: this,
            boss: boss,
            session: session,
            metricsSettings: metricsConfig,
          );
          await service.initialize();
          _metricsService = service;
          metricsConfigured = true;
        }
      } catch (error, stackTrace) {
        onEvent?.call({
          'source': 'binding',
          'type': 'internal_realm_bootstrap_error',
          'realm': internal.name,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
        rethrow;
      }
    }

    if (metricsEnabled && !metricsConfigured) {
      final error = StateError(
        'Metrics exporter enabled for realm "${metricsConfig!.realm}" but no '
        'matching internal realm was bootstrapped.',
      );
      onEvent?.call({
        'source': 'binding',
        'type': 'internal_realm_bootstrap_error',
        'realm': metricsConfig.realm,
        'error': error.toString(),
      });
      throw error;
    }
  }
}

String _endpointKey(String host, int port) =>
    '${host.trim().toLowerCase()}:$port';

String _normalizeConfiguredEndpoint(String endpoint) {
  final trimmed = endpoint.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  if (trimmed.startsWith('[')) {
    final closing = trimmed.indexOf(']');
    if (closing != -1 &&
        closing + 1 < trimmed.length &&
        trimmed[closing + 1] == ':') {
      final host = trimmed.substring(1, closing);
      final portPart = trimmed.substring(closing + 2);
      final port = int.tryParse(portPart) ?? 0;
      return _endpointKey(host, port);
    }
  }
  final lastColon = trimmed.lastIndexOf(':');
  if (lastColon == -1) {
    return _endpointKey(trimmed, 0);
  }
  final hostPart = trimmed.substring(0, lastColon);
  final portPart = trimmed.substring(lastColon + 1);
  final port = int.tryParse(portPart) ?? 0;
  return _endpointKey(hostPart, port);
}

/// Tracks additional per-connection bookkeeping for the binding.
class _ConnectionState {
  _ConnectionState(this.listener);

  final RouterListener listener;
  NativeHttp3Connection? _http3Connection;

  void setHttp3Connection(NativeHttp3Connection? connection) {
    if (!identical(_http3Connection, connection)) {
      _http3Connection?.release();
      _http3Connection = connection;
    }
  }

  void dispose() {
    _http3Connection?.release();
    _http3Connection = null;
  }
}

class _PendingHttpCall {
  _PendingHttpCall({
    required this.id,
    required this.request,
    required this.snapshot,
    required this.session,
    required this.subscription,
    this.handshake,
  });

  final int id;
  final RouterHttpRequest request;
  final HttpRequestSnapshot snapshot;
  final RouterSession session;
  final StreamSubscription<result_msg.Result> subscription;
  NativeHttpHandshake? handshake;
  NativeHttpResponseStream? responseStream;
}

class _MetricsService {
  _MetricsService({
    required this.binding,
    required this.boss,
    required this.session,
    required this.metricsSettings,
  });

  final RouterBinding binding;
  final _RouterBoss boss;
  final RouterSession session;
  final OpenMetricsSettings metricsSettings;

  registered_msg.Registered? _snapshotRegistration;
  registered_msg.Registered? _openMetricsRegistration;

  Future<void> initialize() async {
    _snapshotRegistration = await session.register(
      'connectanum.metrics.snapshot',
    );
    _snapshotRegistration!.onInvoke(
      (invocation) => unawaited(_handleSnapshotInvocation(invocation)),
    );

    _openMetricsRegistration = await session.register(
      'connectanum.metrics.openmetrics',
    );
    _openMetricsRegistration!.onInvoke(
      (invocation) => unawaited(_handleOpenMetricsInvocation(invocation)),
    );
  }

  Future<void> dispose() async {
    if (_snapshotRegistration != null) {
      await session.unregister(_snapshotRegistration!.registrationId);
    }
    if (_openMetricsRegistration != null) {
      await session.unregister(_openMetricsRegistration!.registrationId);
    }
    _snapshotRegistration = null;
    _openMetricsRegistration = null;
  }

  bool ownsSession(RouterSession candidate) => identical(candidate, session);

  Future<void> _handleSnapshotInvocation(
    invocation_msg.Invocation invocation,
  ) async {
    try {
      final payload = await _buildSnapshotPayload();
      invocation.respondWith(arguments: [payload]);
    } catch (error, stackTrace) {
      binding.onEvent?.call({
        'source': 'metrics',
        'type': 'snapshot_error',
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.runtimeError,
        arguments: ['Failed to collect metrics'],
        argumentsKeywords: {'reason': error.toString()},
      );
    }
  }

  Future<void> _handleOpenMetricsInvocation(
    invocation_msg.Invocation invocation,
  ) async {
    try {
      final text = await buildOpenMetricsPayload();
      final httpContext = HttpInvocationContext.maybeFromInvocation(invocation);
      if (httpContext != null) {
        httpContext.sendText(
          body: text,
          headers: const {
            'content-type': 'text/plain; version=0.0.4; charset=utf-8',
            'cache-control': 'no-store',
          },
        );
        return;
      }
      invocation.respondWith(arguments: [text]);
    } catch (error, stackTrace) {
      binding.onEvent?.call({
        'source': 'metrics',
        'type': 'openmetrics_error',
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.runtimeError,
        arguments: ['Failed to generate OpenMetrics payload'],
        argumentsKeywords: {'reason': error.toString()},
      );
    }
  }

  Future<Map<String, Object?>> _buildSnapshotPayload() async {
    final routerSnapshot = await binding.collectMetrics();
    final realmReports = await _collectRealmReports();
    final transportAlerts = routerSnapshot.transport;
    return <String, Object?>{
      'router': routerSnapshot.toJson(),
      'realms': realmReports.map((report) => report.toJson()).toList(),
      'exporter': <String, Object?>{
        'realm': metricsSettings.realm,
        'path': metricsSettings.path,
        if (metricsSettings.listen != null) 'listen': metricsSettings.listen,
        if (metricsSettings.authToken != null)
          'auth_token': metricsSettings.authToken,
      },
      if (transportAlerts != null)
        'alerts': <String, Object?>{
          'backpressure': transportAlerts.backpressureAlerts,
          'transport': transportAlerts.transportAlerts,
          'goaway': transportAlerts.goAwayAlerts,
          'idle_timeout': transportAlerts.idleTimeoutAlerts,
          'body_timeout': transportAlerts.bodyTimeoutAlerts,
          'protocol_error': transportAlerts.protocolErrorAlerts,
          'internal_error': transportAlerts.internalErrorAlerts,
          'by_listener': transportAlerts.alertBreakdown
              .map(
                (entry) => <String, Object?>{
                  'listener_id': entry.listenerId,
                  'protocol': entry.protocol,
                  'endpoint': entry.endpoint,
                  'backpressure': entry.backpressureAlerts,
                  'goaway': entry.goAwayAlerts,
                  'idle_timeout': entry.idleTimeoutAlerts,
                  'body_timeout': entry.bodyTimeoutAlerts,
                  'protocol_error': entry.protocolErrorAlerts,
                  'internal_error': entry.internalErrorAlerts,
                  if (entry.throttleUntil != null)
                    'throttle_until': entry.throttleUntil!.toIso8601String(),
                },
              )
              .toList(growable: false),
        },
    };
  }

  Future<List<_RealmMetricsReport>> _collectRealmReports() async {
    final realmNames = <String>{
      for (final realm in binding.settings.realms) realm.name,
      for (final internal in binding.settings.internalRealms) internal.name,
    };
    final reports = <_RealmMetricsReport>[];
    for (final realmName in realmNames) {
      try {
        final snapshot = await boss.fetchRealmSnapshot(realmName);
        reports.add(_buildRealmReport(snapshot));
      } catch (error, stackTrace) {
        binding.onEvent?.call({
          'source': 'metrics',
          'type': 'snapshot_realm_error',
          'realm': realmName,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
      }
    }
    return reports;
  }

  Future<String> buildOpenMetricsPayload({
    RouterMetricsSnapshot? snapshot,
  }) async {
    final routerSnapshot = snapshot ?? await binding.collectMetrics();
    final realmReports = await _collectRealmReports();
    return _buildOpenMetricsText(routerSnapshot, realmReports);
  }

  _RealmMetricsReport _buildRealmReport(RealmSnapshot snapshot) {
    final topicDetails = <_TopicMetricsDetail>[];
    for (final subscription in snapshot.subscriptions) {
      if (_isMetaTopic(subscription.topic)) {
        continue;
      }
      topicDetails.add(
        _TopicMetricsDetail(
          id: subscription.id,
          topic: subscription.topic,
          match: subscription.matchPolicy,
          subscriberCount: subscription.subscribers.length,
        ),
      );
    }
    final topics = topicDetails.length;
    final topicSubscribers = topicDetails.fold<int>(
      0,
      (sum, detail) => sum + detail.subscriberCount,
    );

    final procedureDetails = <_ProcedureMetricsDetail>[];
    for (final registration in snapshot.registrations) {
      if (_isMetaProcedure(registration.procedure)) {
        continue;
      }
      procedureDetails.add(
        _ProcedureMetricsDetail(
          id: registration.registrationId,
          procedure: registration.procedure,
          match: registration.matchPolicy,
          policy: registration.policy,
          calleeCount: registration.callees.length,
        ),
      );
    }
    final registeredProcedures = procedureDetails.length;
    final procedureEndpoints = procedureDetails.fold<int>(
      0,
      (sum, detail) => sum + detail.calleeCount,
    );

    return _RealmMetricsReport(
      realm: snapshot.realmUri,
      sessionCount: snapshot.sessions.length,
      topics: topics,
      topicSubscribers: topicSubscribers,
      topicDetails: topicDetails,
      registeredProcedures: registeredProcedures,
      procedureEndpoints: procedureEndpoints,
      procedureDetails: procedureDetails,
    );
  }

  String _buildOpenMetricsText(
    RouterMetricsSnapshot routerSnapshot,
    List<_RealmMetricsReport> realms,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        '# HELP connectanum_router_realms Number of realms currently tracked by the router',
      )
      ..writeln('# TYPE connectanum_router_realms gauge')
      ..writeln('connectanum_router_realms ${routerSnapshot.realmCount}')
      ..writeln(
        '# HELP connectanum_router_sessions Total active sessions across all realms',
      )
      ..writeln('# TYPE connectanum_router_sessions gauge')
      ..writeln('connectanum_router_sessions ${routerSnapshot.sessionCount}')
      ..writeln(
        '# HELP connectanum_router_subscriptions Total subscriptions across all realms',
      )
      ..writeln('# TYPE connectanum_router_subscriptions gauge')
      ..writeln(
        'connectanum_router_subscriptions ${routerSnapshot.subscriptionCount}',
      )
      ..writeln(
        '# HELP connectanum_router_registrations Total procedure registrations across all realms',
      )
      ..writeln('# TYPE connectanum_router_registrations gauge')
      ..writeln(
        'connectanum_router_registrations ${routerSnapshot.registrationCount}',
      )
      ..writeln(
        '# HELP connectanum_router_pending_invocations Invocations waiting for completion',
      )
      ..writeln('# TYPE connectanum_router_pending_invocations gauge')
      ..writeln(
        'connectanum_router_pending_invocations ${routerSnapshot.pendingInvocationCount}',
      )
      ..writeln(
        '# HELP connectanum_router_total_invocations_dispatched Total invocations dispatched since router start',
      )
      ..writeln(
        '# TYPE connectanum_router_total_invocations_dispatched counter',
      )
      ..writeln(
        'connectanum_router_total_invocations_dispatched_total ${routerSnapshot.totalInvocationsDispatched}',
      )
      ..writeln(
        '# HELP connectanum_router_total_publications_routed Total publications routed since router start',
      )
      ..writeln('# TYPE connectanum_router_total_publications_routed counter')
      ..writeln(
        'connectanum_router_total_publications_routed_total ${routerSnapshot.totalPublicationsRouted}',
      )
      ..writeln(
        '# HELP connectanum_router_active_connections Active TCP connections handled by the router',
      )
      ..writeln('# TYPE connectanum_router_active_connections gauge')
      ..writeln(
        'connectanum_router_active_connections ${routerSnapshot.activeConnections}',
      )
      ..writeln(
        '# HELP connectanum_router_worker_isolates Worker isolates currently running',
      )
      ..writeln('# TYPE connectanum_router_worker_isolates gauge')
      ..writeln(
        'connectanum_router_worker_isolates ${routerSnapshot.workerCount}',
      );

    buffer
      ..writeln(
        '# HELP connectanum_router_realm_sessions Active sessions per realm',
      )
      ..writeln('# TYPE connectanum_router_realm_sessions gauge');
    for (final realm in realms) {
      buffer.writeln(
        'connectanum_router_realm_sessions${_formatLabels({'realm': realm.realm})} ${realm.sessionCount}',
      );
    }

    buffer
      ..writeln('# HELP connectanum_router_topics Managed topics per realm')
      ..writeln('# TYPE connectanum_router_topics gauge');
    for (final realm in realms) {
      buffer.writeln(
        'connectanum_router_topics${_formatLabels({'realm': realm.realm})} ${realm.topics}',
      );
    }

    buffer
      ..writeln(
        '# HELP connectanum_router_topics_subscribed Total subscriber count across topics per realm',
      )
      ..writeln('# TYPE connectanum_router_topics_subscribed gauge');
    for (final realm in realms) {
      buffer.writeln(
        'connectanum_router_topics_subscribed${_formatLabels({'realm': realm.realm})} ${realm.topicSubscribers}',
      );
    }

    final transport = routerSnapshot.transport;
    if (transport != null) {
      buffer
        ..writeln(
          '# HELP connectanum_router_http_events_total Total HTTP connection lifecycle events observed by the runtime',
        )
        ..writeln('# TYPE connectanum_router_http_events_total counter')
        ..writeln(
          'connectanum_router_http_events_total ${transport.totalEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_goaway_total HTTP connections closed via GOAWAY',
        )
        ..writeln('# TYPE connectanum_router_http_goaway_total counter')
        ..writeln(
          'connectanum_router_http_goaway_total ${transport.goAwayEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_idle_timeouts_total HTTP connections closed due to idle timeouts',
        )
        ..writeln('# TYPE connectanum_router_http_idle_timeouts_total counter')
        ..writeln(
          'connectanum_router_http_idle_timeouts_total ${transport.idleTimeoutEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_body_timeouts_total HTTP connections closed due to body timeouts',
        )
        ..writeln('# TYPE connectanum_router_http_body_timeouts_total counter')
        ..writeln(
          'connectanum_router_http_body_timeouts_total ${transport.bodyTimeoutEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_protocol_errors_total HTTP connections closed due to protocol errors',
        )
        ..writeln(
          '# TYPE connectanum_router_http_protocol_errors_total counter',
        )
        ..writeln(
          'connectanum_router_http_protocol_errors_total ${transport.protocolErrorEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_internal_errors_total HTTP connections closed due to internal errors',
        )
        ..writeln(
          '# TYPE connectanum_router_http_internal_errors_total counter',
        )
        ..writeln(
          'connectanum_router_http_internal_errors_total ${transport.internalErrorEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_backpressure_events_total Count of backpressure incidents observed on HTTP request queues',
        )
        ..writeln(
          '# TYPE connectanum_router_http_backpressure_events_total counter',
        )
        ..writeln(
          'connectanum_router_http_backpressure_events_total ${transport.backpressureEvents}',
        )
        ..writeln(
          '# HELP connectanum_router_http_max_backpressure_depth Maximum pending HTTP request queue depth observed',
        )
        ..writeln('# TYPE connectanum_router_http_max_backpressure_depth gauge')
        ..writeln(
          'connectanum_router_http_max_backpressure_depth ${transport.maxBackpressureDepth}',
        );
      if (transport.breakdown.isNotEmpty) {
        buffer
          ..writeln(
            '# HELP connectanum_router_http_events_by_listener_total HTTP connection lifecycle events per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_events_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_events_by_listener_total$labels ${entry.totalEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_goaway_by_listener_total HTTP connections closed via GOAWAY per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_goaway_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_goaway_by_listener_total$labels ${entry.goAwayEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_idle_timeouts_by_listener_total HTTP idle timeout closures per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_idle_timeouts_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_idle_timeouts_by_listener_total$labels ${entry.idleTimeoutEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_body_timeouts_by_listener_total HTTP body timeout closures per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_body_timeouts_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_body_timeouts_by_listener_total$labels ${entry.bodyTimeoutEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_protocol_errors_by_listener_total HTTP protocol error closures per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_protocol_errors_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_protocol_errors_by_listener_total$labels ${entry.protocolErrorEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_internal_errors_by_listener_total HTTP internal error closures per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_internal_errors_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_internal_errors_by_listener_total$labels ${entry.internalErrorEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_backpressure_events_by_listener_total HTTP request queue backpressure events per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_backpressure_events_by_listener_total counter',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_backpressure_events_by_listener_total$labels ${entry.backpressureEvents}',
          );
        }
        buffer
          ..writeln(
            '# HELP connectanum_router_http_max_backpressure_depth_by_listener Maximum observed HTTP request queue depth per listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_http_max_backpressure_depth_by_listener gauge',
          );
        for (final entry in transport.breakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_http_max_backpressure_depth_by_listener$labels ${entry.maxBackpressureDepth}',
          );
        }
      }
    }

    if (transport != null) {
      buffer
        ..writeln(
          '# HELP connectanum_router_transport_alerts_total Transport/backpressure alerts emitted by the boss',
        )
        ..writeln('# TYPE connectanum_router_transport_alerts_total counter');
      final alertTotals = <String, int>{
        'backpressure': transport.backpressureAlerts,
        'go_away': transport.goAwayAlerts,
        'idle_timeout': transport.idleTimeoutAlerts,
        'body_timeout': transport.bodyTimeoutAlerts,
        'protocol_error': transport.protocolErrorAlerts,
        'internal_error': transport.internalErrorAlerts,
      };
      alertTotals.forEach((reason, value) {
        buffer.writeln(
          'connectanum_router_transport_alerts_total${_formatLabels({'reason': reason})} $value',
        );
      });

      var printedAlertHeader = false;
      for (final entry in transport.alertBreakdown) {
        final alertByReason = <String, int>{
          'backpressure': entry.backpressureAlerts,
          'go_away': entry.goAwayAlerts,
          'idle_timeout': entry.idleTimeoutAlerts,
          'body_timeout': entry.bodyTimeoutAlerts,
          'protocol_error': entry.protocolErrorAlerts,
          'internal_error': entry.internalErrorAlerts,
        };
        if (alertByReason.values.every((value) => value == 0)) {
          continue;
        }
        if (!printedAlertHeader) {
          buffer
            ..writeln(
              '# HELP connectanum_router_transport_alerts_by_listener_total Transport/backpressure alerts by listener/protocol',
            )
            ..writeln(
              '# TYPE connectanum_router_transport_alerts_by_listener_total counter',
            );
          printedAlertHeader = true;
        }
        final baseLabels = {
          'listener_id': entry.listenerId.toString(),
          'protocol': entry.protocol,
          'endpoint': entry.endpoint,
        };
        alertByReason.forEach((reason, value) {
          if (value == 0) {
            return;
          }
          buffer.writeln(
            'connectanum_router_transport_alerts_by_listener_total${_formatLabels({...baseLabels, 'reason': reason})} $value',
          );
        });
      }
    }

    buffer
      ..writeln(
        '# HELP connectanum_router_topic_subscribers Subscribers per topic',
      )
      ..writeln('# TYPE connectanum_router_topic_subscribers gauge');
    for (final realm in realms) {
      for (final topic in realm.topicDetails) {
        buffer.writeln(
          'connectanum_router_topic_subscribers${_formatLabels({'realm': realm.realm, 'topic': topic.topic, 'match': _topicMatchPolicyToString(topic.match), 'subscription_id': topic.id.toString()})} ${topic.subscriberCount}',
        );
      }
    }

    buffer
      ..writeln(
        '# HELP connectanum_router_registered_procedures Registered procedures per realm',
      )
      ..writeln('# TYPE connectanum_router_registered_procedures gauge');
    for (final realm in realms) {
      buffer.writeln(
        'connectanum_router_registered_procedures${_formatLabels({'realm': realm.realm})} ${realm.registeredProcedures}',
      );
    }

    buffer
      ..writeln(
        '# HELP connectanum_router_procedure_endpoints Total callees per realm',
      )
      ..writeln('# TYPE connectanum_router_procedure_endpoints gauge');
    for (final realm in realms) {
      buffer.writeln(
        'connectanum_router_procedure_endpoints${_formatLabels({'realm': realm.realm})} ${realm.procedureEndpoints}',
      );
    }

    buffer
      ..writeln(
        '# HELP connectanum_router_procedure_endpoint_count Callees per registered procedure',
      )
      ..writeln('# TYPE connectanum_router_procedure_endpoint_count gauge');
    for (final realm in realms) {
      for (final procedure in realm.procedureDetails) {
        buffer.writeln(
          'connectanum_router_procedure_endpoint_count${_formatLabels({'realm': realm.realm, 'procedure': procedure.procedure, 'match': _procedureMatchPolicyToString(procedure.match), 'policy': _invocationPolicyToString(procedure.policy), 'registration_id': procedure.id.toString()})} ${procedure.calleeCount}',
        );
      }
    }

    return buffer.toString();
  }

  String _formatLabels(Map<String, String> labels) {
    if (labels.isEmpty) {
      return '';
    }
    final formatted = labels.entries
        .map((entry) {
          final escaped = entry.value
              .replaceAll(r'\', r'\\')
              .replaceAll('\n', r'\n')
              .replaceAll('"', r'\"');
          return '${entry.key}="$escaped"';
        })
        .join(',');
    return '{$formatted}';
  }

  bool _isMetaTopic(String topic) => topic.startsWith('wamp.');

  bool _isMetaProcedure(String procedure) => procedure.startsWith('wamp.');

  String _topicMatchPolicyToString(TopicMatchPolicy policy) => switch (policy) {
    TopicMatchPolicy.exact => 'exact',
    TopicMatchPolicy.prefix => 'prefix',
    TopicMatchPolicy.wildcard => 'wildcard',
  };

  String _procedureMatchPolicyToString(ProcedureMatchPolicy policy) =>
      switch (policy) {
        ProcedureMatchPolicy.exact => 'exact',
        ProcedureMatchPolicy.prefix => 'prefix',
        ProcedureMatchPolicy.wildcard => 'wildcard',
      };

  String _invocationPolicyToString(InvocationPolicy policy) => switch (policy) {
    InvocationPolicy.single => 'single',
    InvocationPolicy.roundRobin => 'round_robin',
    InvocationPolicy.random => 'random',
    InvocationPolicy.first => 'first',
    InvocationPolicy.last => 'last',
    InvocationPolicy.load => 'load',
  };
}

class _RealmMetricsReport {
  const _RealmMetricsReport({
    required this.realm,
    required this.sessionCount,
    required this.topics,
    required this.topicSubscribers,
    required this.topicDetails,
    required this.registeredProcedures,
    required this.procedureEndpoints,
    required this.procedureDetails,
  });

  final String realm;
  final int sessionCount;
  final int topics;
  final int topicSubscribers;
  final List<_TopicMetricsDetail> topicDetails;
  final int registeredProcedures;
  final int procedureEndpoints;
  final List<_ProcedureMetricsDetail> procedureDetails;

  Map<String, Object?> toJson() => <String, Object?>{
    'realm': realm,
    'session_count': sessionCount,
    'topics': topics,
    'topic_subscribers': topicSubscribers,
    'topic_details': topicDetails.map((detail) => detail.toJson()).toList(),
    'registered_procedures': registeredProcedures,
    'procedure_endpoints': procedureEndpoints,
    'procedure_details': procedureDetails
        .map((detail) => detail.toJson())
        .toList(),
  };
}

class _TopicMetricsDetail {
  const _TopicMetricsDetail({
    required this.id,
    required this.topic,
    required this.match,
    required this.subscriberCount,
  });

  final int id;
  final String topic;
  final TopicMatchPolicy match;
  final int subscriberCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'topic': topic,
    'match': match.name,
    'subscriber_count': subscriberCount,
  };
}

class _ProcedureMetricsDetail {
  const _ProcedureMetricsDetail({
    required this.id,
    required this.procedure,
    required this.match,
    required this.policy,
    required this.calleeCount,
  });

  final int id;
  final String procedure;
  final ProcedureMatchPolicy match;
  final InvocationPolicy policy;
  final int calleeCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'procedure': procedure,
    'match': match.name,
    'policy': policy.name,
    'callee_count': calleeCount,
  };
}

class _ParsedListenEndpoint {
  const _ParsedListenEndpoint({required this.host, required this.port});

  final String host;
  final int port;
}

_ParsedListenEndpoint _parseListenEndpoint(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw FormatException('Listen endpoint must not be empty');
  }
  if (trimmed.startsWith('[')) {
    final closing = trimmed.indexOf(']');
    if (closing == -1 ||
        closing + 1 >= trimmed.length ||
        trimmed[closing + 1] != ':') {
      throw FormatException('Listen endpoint "$value" must include :port');
    }
    final host = trimmed.substring(1, closing);
    final portPart = trimmed.substring(closing + 2);
    final port = int.parse(portPart);
    return _ParsedListenEndpoint(host: host, port: port);
  }
  final lastColon = trimmed.lastIndexOf(':');
  if (lastColon == -1) {
    throw FormatException('Listen endpoint "$value" must include :port');
  }
  final host = trimmed.substring(0, lastColon);
  final portPart = trimmed.substring(lastColon + 1);
  final port = int.parse(portPart);
  return _ParsedListenEndpoint(host: host, port: port);
}

String _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '/';
  }
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}
