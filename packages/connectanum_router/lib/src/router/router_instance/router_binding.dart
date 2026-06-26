part of '../router_instance.dart';

/// Handles an HTTP route that is resolved directly inside the Dart router.
typedef RouterHttpRouteHandler =
    FutureOr<NativeHttpResponse> Function(RouterHttpRequest request);

String? _httpRouteHandlerId(HttpRouteAction action) {
  final delegate = action.delegate?.trim();
  if (delegate != null && delegate.isNotEmpty) {
    return delegate;
  }
  const optionKeys = [
    'handler',
    'handler_id',
    'handlerId',
    'callback',
    'callback_id',
    'callbackId',
  ];
  for (final key in optionKeys) {
    final value = action.options[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
  }
  return null;
}

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
    nativeBody: _body,
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
    this.workerEntryPoint = defaultRouterWorkerEntryPoint,
    this.workerPollInterval = const Duration(milliseconds: 1),
    this.onEvent,
    Map<String, RouterHttpRouteHandler> httpRouteHandlers = const {},
  }) : _pendingEndpoints = List<Endpoint>.unmodifiable(endpoints),
       _httpRouteHandlers = Map<String, RouterHttpRouteHandler>.unmodifiable(
         httpRouteHandlers.map((key, value) => MapEntry(key.trim(), value))
           ..removeWhere((key, _) => key.isEmpty),
       ),
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
  final Map<String, RouterHttpRouteHandler> _httpRouteHandlers;

  final List<Endpoint> _pendingEndpoints;
  final List<RouterListener> _listeners = [];
  final Map<int, RouterListener> _listenerById = {};
  final Map<int, _ConnectionState> _connections = {};
  final Set<RouterSession> _internalSessions = {};
  final Map<String, RouterSession> _internalSessionsByRealm = {};
  final Map<String, RouterSession> _internalSessionsByCacheKey = {};
  final Map<int, _PendingHttpCall> _pendingHttpCalls = {};
  final Map<String, _HttpRouteRateLimitState> _httpRouteRateLimitStates = {};
  final Map<String, _RouterMcpEndpoint> _mcpEndpoints = {};
  final Map<String, _PendingHttpAuthTransaction> _pendingHttpAuthTransactions =
      {};
  final Map<String, _HttpAuthTokenRecord> _httpAuthTokens = {};
  final Map<String, _HttpRefreshTokenRecord> _httpRefreshTokens = {};
  final Map<String, Future<HttpAuthProvider>> _httpAuthProviderCache = {};
  final Map<String, ListenerSettings> _listenerSettingsByEndpoint;
  final Map<int, ListenerSettings?> _listenerConfigById = {};
  final Random _random = Random.secure();
  Future<void>? _internalBootstrap;
  Object? _internalBootstrapError;
  StackTrace? _internalBootstrapStack;
  _MetricsService? _metricsService;
  NativeMessageHandleDecoder? _handleDecoder;
  _RouterBoss? _boss;
  bool _ready = false;
  int _nextHttpRequestId = 1;
  Future<void>? _drainFuture;
  bool _draining = false;
  final Set<int> _closedListenerIds = {};
  DateTime? _drainStartedAtUtc;
  DateTime? _drainDeadlineAtUtc;
  Duration? _lastDrainDuration;
  int _drainCount = 0;
  int _drainTimeoutCount = 0;
  int _closedListenersCount = 0;
  int _closedPendingConnectionsCount = 0;

  List<RouterListener> get listeners =>
      List<RouterListener>.unmodifiable(_listeners);

  bool get isReady => _ready;

  bool get isDraining => _draining;

  /// Stops accepting new external connections and drains worker sessions.
  ///
  /// The native listener sockets are closed first so no additional connections
  /// can enter the accept pipeline while workers send GOODBYE and close their
  /// owned sessions.
  Future<void> drain({Duration drainTimeout = const Duration(seconds: 15)}) {
    final existing = _drainFuture;
    if (existing != null) {
      return existing;
    }

    final future = () async {
      if (!_ready || _draining) {
        return;
      }
      _draining = true;
      _drainCount += 1;
      _drainStartedAtUtc = DateTime.now().toUtc();
      _drainDeadlineAtUtc = _drainStartedAtUtc!.add(drainTimeout);
      onEvent?.call({
        'source': 'binding',
        'type': 'drain_started',
        'timeout_ms': drainTimeout.inMilliseconds,
      });
      try {
        Future<void>? bossStop;
        final boss = _boss;
        if (boss != null) {
          bossStop = boss.stop(drainTimeout: drainTimeout);
        }
        await _closeListenersAndPendingConnections(
          includeOpenMetricsListeners: false,
        );
        if (bossStop != null) {
          await bossStop;
        }
        await _closeListenersAndPendingConnections();

        final finishedAt = DateTime.now().toUtc();
        _lastDrainDuration = finishedAt.difference(_drainStartedAtUtc!);
        if (_drainDeadlineAtUtc != null &&
            finishedAt.isAfter(_drainDeadlineAtUtc!)) {
          _drainTimeoutCount += 1;
        }
        onEvent?.call({
          'source': 'binding',
          'type': 'drain_completed',
          'duration_ms': _lastDrainDuration!.inMilliseconds,
          'listeners_closed': _closedListenersCount,
          'pending_connections_closed': _closedPendingConnectionsCount,
        });
      } catch (error, stackTrace) {
        onEvent?.call({
          'source': 'binding',
          'type': 'drain_failed',
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
        rethrow;
      } finally {
        _draining = false;
      }
    }();

    _drainFuture = future;
    return future.whenComplete(() {
      if (identical(_drainFuture, future)) {
        _drainFuture = null;
      }
    });
  }

  Future<void> _closeListenersAndPendingConnections({
    bool includeOpenMetricsListeners = true,
  }) async {
    if (_listeners.isEmpty || _closedListenerIds.length == _listeners.length) {
      return;
    }

    var closedListeners = 0;
    var closedPendingConnections = 0;
    final snapshot = _listeners
        .where((listener) {
          if (_closedListenerIds.contains(listener.listenerId)) {
            return false;
          }
          return includeOpenMetricsListeners ||
              !_isOpenMetricsListener(listener);
        })
        .toList(growable: false);
    if (snapshot.isEmpty) {
      return;
    }
    for (final listener in snapshot) {
      try {
        runtime.closeListener(listener.listenerId);
        _closedListenerIds.add(listener.listenerId);
        closedListeners += 1;
      } catch (error) {
        onEvent?.call({
          'source': 'binding',
          'type': 'listener_close_failed',
          'listenerId': listener.listenerId,
          'error': error.toString(),
        });
      }

      while (true) {
        int connectionId;
        try {
          connectionId = runtime.pollConnection(listener.listenerId);
        } catch (_) {
          break;
        }
        if (connectionId == 0) {
          break;
        }
        try {
          runtime.closeConnection(connectionId);
          closedPendingConnections += 1;
        } catch (error) {
          onEvent?.call({
            'source': 'binding',
            'type': 'pending_connection_close_failed',
            'listenerId': listener.listenerId,
            'connectionId': connectionId,
            'error': error.toString(),
          });
        }
      }
    }
    _closedListenersCount += closedListeners;
    _closedPendingConnectionsCount += closedPendingConnections;
    onEvent?.call({
      'source': 'binding',
      'type': 'listeners_closed',
      'listeners_closed': closedListeners,
      'pending_connections_closed': closedPendingConnections,
    });
  }

  bool _isOpenMetricsListener(RouterListener listener) {
    return listener.settings?.options['connectanum_open_metrics_listener'] ==
        true;
  }

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
    String? authMethod,
    String? authProvider,
    Map<String, Object?> roles = const {},
    String? sessionProfile,
    String? cacheKey,
    bool authorizationIsInternal = true,
    bool indexByRealm = true,
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
    final resolvedProfile = _resolveSessionProfile(sessionProfile);
    final resolvedRealmUri =
        (resolvedProfile?.realm != null && resolvedProfile!.realm!.isNotEmpty)
        ? resolvedProfile.realm!
        : realmUri;
    final resolvedAuthId = authId ?? resolvedProfile?.auth.authId;
    final requestedAuthRole = authRole ?? resolvedProfile?.auth.authRole;
    final resolvedRoles = <String, Object?>{
      ...?resolvedProfile?.roles,
      ...roles,
    };

    RealmSettings? realmSettings;
    for (final candidate in settings.realms) {
      if (candidate.name == resolvedRealmUri) {
        realmSettings = candidate;
        break;
      }
    }
    final resolvedAuthRole =
        requestedAuthRole ??
        (realmSettings?.roles.any((role) => role.name == 'anonymous') == true
            ? 'anonymous'
            : null);
    final statePort = boss.stateCommandPort;
    final sessionId = await _allocateSessionId(statePort);
    final controlPort = RawReceivePort();
    final handshakePort = ReceivePort();
    final isolate = await Isolate.spawn<_InternalSessionBootstrap>(
      _routerInternalSessionIsolate,
      _InternalSessionBootstrap(
        sessionId: sessionId,
        realmUri: resolvedRealmUri,
        authId: resolvedAuthId,
        authRole: resolvedAuthRole,
        authMethod: authMethod,
        authProvider: authProvider,
        authorizationIsInternal: authorizationIsInternal,
        roles: resolvedRoles,
        realmSettings: realmSettings,
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
      realmUri: resolvedRealmUri,
      authId: resolvedAuthId,
      authRole: resolvedAuthRole,
      authMethod: authMethod,
      authProvider: authProvider,
      authorizationIsInternal: authorizationIsInternal,
      cacheKey: cacheKey,
      roles: resolvedRoles,
      commandPort: requestPort,
      controlPort: controlPort,
      responsePort: responsePort,
      isolate: isolate,
    );
    final record = SessionRecord(
      id: sessionId,
      authId: resolvedAuthId,
      authRole: resolvedAuthRole,
      authMethod: authMethod,
      authProvider: authProvider,
      roles: resolvedRoles,
      workerId: 0,
      connectionId: -sessionId,
      lastActivity: DateTime.now(),
      listener: listener,
      protocol: listenerSettings?.primaryProtocol ?? ListenerProtocol.rawsocket,
      internalSendPort: internalPort,
    );
    statePort.send(
      SessionOpenCommand(realmUri: resolvedRealmUri, session: record),
    );
    _internalSessions.add(session);
    if (indexByRealm) {
      _internalSessionsByRealm[resolvedRealmUri] = session;
    }
    if (cacheKey != null && cacheKey.isNotEmpty) {
      _internalSessionsByCacheKey[cacheKey] = session;
    }
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
      return response.copyWith(
        shutdown: _buildShutdownMetrics(),
        process: _collectProcessMetrics(),
      );
    }
    if (response is StoreErrorResponse) {
      throw StateError('Failed to collect metrics: ${response.message}');
    }
    throw StateError('Unexpected metrics response: $response');
  }

  RouterShutdownMetrics _buildShutdownMetrics() {
    return RouterShutdownMetrics(
      drainInProgress: _draining,
      drainTotal: _drainCount,
      drainTimeouts: _drainTimeoutCount,
      closedListenersTotal: _closedListenersCount,
      closedPendingConnectionsTotal: _closedPendingConnectionsCount,
      lastDrainDurationMs: _lastDrainDuration?.inMilliseconds,
      drainStartedAtUtc: _drainStartedAtUtc,
      drainDeadlineAtUtc: _drainDeadlineAtUtc,
    );
  }

  RouterProcessMetrics _collectProcessMetrics() => RouterProcessMetrics(
    processId: pid,
    currentRssBytes: ProcessInfo.currentRss,
    maxRssBytes: ProcessInfo.maxRss,
  );

  Future<String?> collectOpenMetricsText([
    RouterMetricsSnapshot? snapshot,
  ]) async {
    final service = _metricsService;
    if (service == null) {
      return null;
    }
    return service.buildOpenMetricsPayload(snapshot: snapshot);
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
    for (final pending in _pendingHttpAuthTransactions.values.toList()) {
      unawaited(pending.abort(reason: 'binding_dispose'));
    }
    _pendingHttpAuthTransactions.clear();
    _httpAuthTokens.clear();
    _httpRefreshTokens.clear();
    try {
      await _closeListenersAndPendingConnections();
    } catch (_) {}
    await _metricsService?.dispose();
    _metricsService = null;
    for (final endpoint in _mcpEndpoints.values.toList()) {
      await endpoint.dispose();
    }
    _mcpEndpoints.clear();
    for (final session in _internalSessions.toList()) {
      await session.close();
    }
    _internalSessions.clear();
    _internalSessionsByRealm.clear();
    _internalSessionsByCacheKey.clear();
    _listenerConfigById.clear();
    for (final state in _connections.values) {
      state.dispose();
    }
    _connections.clear();
    _internalBootstrap = null;
    _internalBootstrapError = null;
    _internalBootstrapStack = null;
    try {
      await drain();
    } catch (_) {}
    final boss = _boss;
    if (boss != null) {
      await boss.stop();
    }
  }

  void _removeInternalSession(RouterSession session) {
    _internalSessions.remove(session);
    final cacheKey = session.cacheKey;
    if (cacheKey != null) {
      final cached = _internalSessionsByCacheKey[cacheKey];
      if (identical(cached, session)) {
        _internalSessionsByCacheKey.remove(cacheKey);
      }
    }
    final existing = _internalSessionsByRealm[session.realmUri];
    if (identical(existing, session)) {
      _internalSessionsByRealm.remove(session.realmUri);
    }
    if (_metricsService?.ownsSession(session) == true) {
      _metricsService = null;
    }
    final removedMcpEndpoints = <_RouterMcpEndpoint>[];
    _mcpEndpoints.removeWhere((_, endpoint) {
      final ownsSession = endpoint.ownsSession(session);
      if (ownsSession) {
        removedMcpEndpoints.add(endpoint);
      }
      return ownsSession;
    });
    for (final endpoint in removedMcpEndpoints) {
      unawaited(endpoint.dispose());
    }
  }

  @visibleForTesting
  SendPort? get debugStatePort => _boss?.stateCommandPort;

  @visibleForTesting
  RouterSession? internalSessionForRealm(String realmUri) =>
      _internalSessionsByRealm[realmUri];

  SessionProfileSettings? _resolveSessionProfile(String? profileName) {
    final trimmed = profileName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    for (final profile in settings.sessionProfiles) {
      if (profile.name == trimmed) {
        return profile;
      }
    }
    throw StateError('Unknown session profile "$trimmed".');
  }

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
    NativeHttpHandshake? retainedHandshake = handshake;
    _cleanupExpiredHttpAuthState();
    final listenerSettings = _listenerConfigById[request.listenerId];
    final routeMatch = _matchHttpRoute(listenerSettings?.http, request);
    final matchedRoute = routeMatch.route;
    final responseRoute = matchedRoute ?? routeMatch.errorRoute;
    final sessionProfile = _resolveHttpSessionProfile(
      listenerSettings: listenerSettings,
      route: responseRoute,
    );
    final mcpRoute = responseRoute?.action.type == HttpRouteActionType.mcp
        ? responseRoute
        : null;
    final httpMethod = request.method.trim().toUpperCase();
    final requestMcpProtocolVersion = mcpRoute == null
        ? null
        : _mcpHeaderValue(this, request, _mcpProtocolVersionHeader);
    final responseMcpProtocolVersion =
        requestMcpProtocolVersion != null &&
            _mcpSupportedHttpProtocolVersions.contains(
              requestMcpProtocolVersion,
            )
        ? requestMcpProtocolVersion
        : mcp.mcpLatestProtocolVersion;
    final mcpResponseSessionId = mcpRoute == null
        ? null
        : _mcpResponseSessionIdForRequest(
            httpMethod: httpMethod,
            streamableHttpRequest:
                httpMethod == 'POST' &&
                _mcpAcceptRequestsStreamableHttpSession(this, request),
            sessionId: _mcpHeaderValue(this, request, _mcpSessionIdHeader),
          );
    if (routeMatch.isMethodNotAllowed) {
      final extraHeaders = <String, String>{
        HttpHeaders.allowHeader: routeMatch.allowedMethods.join(', '),
      };
      await _sendImmediateHttpResponse(
        request: request,
        handshake: retainedHandshake,
        response: mcpRoute == null
            ? NativeHttpResponse(
                status: HttpStatus.methodNotAllowed,
                headers: extraHeaders,
                body: NativeHttpResponseJson(const <String, Object?>{
                  'status': 'error',
                  'reason': 'method_not_allowed',
                  'message': 'HTTP method is not allowed for this route',
                }),
              )
            : _mcpJsonRpcHttpError(
                status: HttpStatus.methodNotAllowed,
                code: mcp.McpErrorCodes.invalidRequest,
                message: 'HTTP method is not allowed for this MCP route',
                sessionId: mcpResponseSessionId,
                protocolVersion: responseMcpProtocolVersion,
                extraHeaders: <String, String>{
                  ...extraHeaders,
                  ..._mcpCorsResponseHeaders(
                    this,
                    request,
                    mcpRoute,
                    preflight: _isCorsPreflight(request),
                  ),
                },
              ),
      );
      retainedHandshake?.release();
      return;
    }
    if (routeMatch.isProtocolNotAllowed) {
      final extraHeaders = <String, String>{
        HttpHeaders.upgradeHeader: routeMatch.allowedProtocols.join(', '),
      };
      await _sendImmediateHttpResponse(
        request: request,
        handshake: retainedHandshake,
        response: mcpRoute == null
            ? NativeHttpResponse(
                status: HttpStatus.upgradeRequired,
                headers: extraHeaders,
                body: NativeHttpResponseJson(const <String, Object?>{
                  'status': 'error',
                  'reason': 'protocol_not_allowed',
                  'message': 'HTTP protocol is not allowed for this route',
                }),
              )
            : _mcpJsonRpcHttpError(
                status: HttpStatus.upgradeRequired,
                code: mcp.McpErrorCodes.invalidRequest,
                message: 'HTTP protocol is not allowed for this MCP route',
                sessionId: mcpResponseSessionId,
                protocolVersion: responseMcpProtocolVersion,
                extraHeaders: <String, String>{
                  ...extraHeaders,
                  ..._mcpCorsResponseHeaders(
                    this,
                    request,
                    mcpRoute,
                    preflight: _isCorsPreflight(request),
                  ),
                },
              ),
      );
      retainedHandshake?.release();
      return;
    }
    if (routeMatch.isNotFound && listenerSettings?.http != null) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: retainedHandshake,
        response: NativeHttpResponse(
          status: HttpStatus.notFound,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'route_not_found',
            'message': 'HTTP route not found',
          }),
        ),
      );
      retainedHandshake?.release();
      return;
    }
    final rateLimitDecision = mcpRoute != null && httpMethod == 'DELETE'
        ? null
        : _evaluateHttpRouteRateLimit(request: request, route: matchedRoute);
    if (rateLimitDecision != null) {
      final rateLimitHeaders = rateLimitDecision.headers;
      final responseHeaders = mcpRoute == null
          ? rateLimitHeaders
          : _mcpHttpResponseHeaders(
              sessionId: mcpResponseSessionId,
              extra: <String, String>{
                ...rateLimitHeaders,
                ..._mcpCorsResponseHeaders(
                  this,
                  request,
                  mcpRoute,
                  preflight: _isCorsPreflight(request),
                ),
              },
            );
      onEvent?.call({
        'source': 'binding',
        'type': 'http_route_rate_limited',
        'listenerId': request.listenerId,
        'connectionId': request.connectionId,
        'endpoint': request.endpoint,
        'rateLimitKey': rateLimitDecision.key,
        'limit': rateLimitDecision.limit,
        'windowMs': rateLimitDecision.windowMs,
        'retryAfterMs': rateLimitDecision.retryAfterMs,
      });
      await _sendImmediateHttpResponse(
        request: request,
        handshake: retainedHandshake,
        response: NativeHttpResponse(
          status: 429,
          headers: responseHeaders,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': 'rate_limited',
            'message': 'HTTP route rate limit exceeded',
            'retry_after_ms': rateLimitDecision.retryAfterMs,
          }),
        ),
      );
      retainedHandshake?.release();
      return;
    }
    final transportAuthFailure = _evaluateHttpRouteTransportAuth(
      request: request,
      route: matchedRoute,
      sessionProfile: sessionProfile,
      listenerSettings: listenerSettings,
    );
    if (transportAuthFailure != null) {
      final resolvedRealm = sessionProfile?.realm?.trim();
      final authRealm = resolvedRealm != null && resolvedRealm.isNotEmpty
          ? resolvedRealm
          : (request.realm ?? 'router.http');
      final authHeaders = transportAuthFailure.bearerChallenge
          ? _httpUnauthorizedHeaders(
              realm: authRealm,
              authPath: _httpAuthPathFor(listenerSettings?.http),
            )
          : const <String, String>{};
      final responseHeaders = mcpRoute == null
          ? authHeaders
          : _mcpHttpResponseHeaders(
              sessionId: mcpResponseSessionId,
              extra: <String, String>{
                ...authHeaders,
                ..._mcpCorsResponseHeaders(this, request, mcpRoute),
              },
            );
      await _sendImmediateHttpResponse(
        request: request,
        handshake: retainedHandshake,
        response: NativeHttpResponse(
          status: transportAuthFailure.status,
          headers: responseHeaders,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': transportAuthFailure.reason,
            'message': transportAuthFailure.message,
          }),
        ),
      );
      retainedHandshake?.release();
      return;
    }
    if (matchedRoute?.action.type == HttpRouteActionType.auth) {
      try {
        await _handleHttpAuthRequest(
          request: request,
          handshake: retainedHandshake,
          listenerSettings: listenerSettings,
          route: matchedRoute!,
          sessionProfile: sessionProfile,
        );
      } finally {
        retainedHandshake?.release();
      }
      return;
    }
    if (matchedRoute?.action.type == HttpRouteActionType.mcp) {
      try {
        await _handleMcpHttpRequestForBinding(
          this,
          request: request,
          handshake: retainedHandshake,
          listenerSettings: listenerSettings,
          route: matchedRoute!,
          sessionProfile: sessionProfile,
        );
      } finally {
        retainedHandshake?.release();
      }
      return;
    }
    if (matchedRoute?.action.type == HttpRouteActionType.handler) {
      final handlerId = _httpRouteHandlerId(matchedRoute!.action);
      final handler = handlerId == null ? null : _httpRouteHandlers[handlerId];
      if (handler == null) {
        final event = <String, Object?>{
          'source': 'binding',
          'type': 'http_handler_missing',
          'listenerId': request.listenerId,
          'connectionId': request.connectionId,
          'endpoint': request.endpoint,
        };
        if (handlerId != null) {
          event['handlerId'] = handlerId;
        }
        onEvent?.call(event);
        try {
          final body = <String, Object?>{
            'status': 'error',
            'reason': 'handler_not_registered',
            'message': 'HTTP route handler is not registered',
          };
          if (handlerId != null) {
            body['handler'] = handlerId;
          }
          await _sendImmediateHttpResponse(
            request: request,
            handshake: retainedHandshake,
            response: NativeHttpResponse(
              status: HttpStatus.notImplemented,
              body: NativeHttpResponseJson(body),
            ),
          );
        } finally {
          retainedHandshake?.release();
        }
        return;
      }
      try {
        onEvent?.call({
          'source': 'binding',
          'type': 'http_handler_request',
          'listenerId': request.listenerId,
          'connectionId': request.connectionId,
          'endpoint': request.endpoint,
          'handlerId': handlerId,
        });
        final response = await handler(request);
        await _sendImmediateHttpResponse(
          request: request,
          handshake: retainedHandshake,
          response: response,
        );
        onEvent?.call({
          'source': 'binding',
          'type': 'http_handler_response_sent',
          'listenerId': request.listenerId,
          'connectionId': request.connectionId,
          'endpoint': request.endpoint,
          'handlerId': handlerId,
          'status': response.status,
        });
      } catch (error, stackTrace) {
        onEvent?.call({
          'source': 'binding',
          'type': 'http_handler_error',
          'listenerId': request.listenerId,
          'connectionId': request.connectionId,
          'endpoint': request.endpoint,
          'handlerId': handlerId,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
        await _sendImmediateHttpResponse(
          request: request,
          handshake: retainedHandshake,
          response: NativeHttpResponse(
            status: HttpStatus.internalServerError,
            body: NativeHttpResponseJson(const <String, Object?>{
              'status': 'error',
              'reason': 'handler_failed',
              'message': 'HTTP route handler failed',
            }),
          ),
        );
      } finally {
        retainedHandshake?.release();
      }
      return;
    }

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
    final nativeLibraryPath = runtime is NativeRuntimeWithHandles
        ? (runtime as NativeRuntimeWithHandles).libraryPathHint
        : null;
    final requestPayload = snapshot.toInvocationPayload(
      nativeLibraryPath: nativeLibraryPath,
    );
    final profileRealm = sessionProfile?.realm?.trim();
    final resolvedRealmUri = (profileRealm != null && profileRealm.isNotEmpty)
        ? profileRealm
        : realmUri;
    RouterSession session;
    try {
      final bearer = _extractBearerToken(request.headers);
      if (bearer != null) {
        session = await _authenticatedHttpSessionForToken(
          token: bearer,
          request: request,
          realmUri: resolvedRealmUri,
          sessionProfile: sessionProfile,
        );
      } else {
        final allowsAnonymous = httpSessionProfileAllowsAnonymous(
          sessionProfile,
        );
        final requiresBridgeAuth =
            sessionProfile != null &&
            sessionProfile.auth.methods.isNotEmpty &&
            !allowsAnonymous;
        if (requiresBridgeAuth) {
          await _sendImmediateHttpResponse(
            request: request,
            handshake: retainedHandshake,
            response: NativeHttpResponse(
              status: HttpStatus.unauthorized,
              headers: _httpUnauthorizedHeaders(
                realm: resolvedRealmUri,
                authPath: _httpAuthPathFor(listenerSettings?.http),
              ),
              body: NativeHttpResponseJson(<String, Object?>{
                'status': 'error',
                'reason': 'unauthorized',
                'message': 'Bearer token required',
              }),
            ),
          );
          retainedHandshake?.release();
          return;
        }
        session = await _ensureInternalSession(
          realmUri: resolvedRealmUri,
          sessionProfile: sessionProfile?.name,
        );
      }
    } on _HttpUnauthorized catch (error) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: retainedHandshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          headers: _httpUnauthorizedHeaders(
            realm: resolvedRealmUri,
            authPath: _httpAuthPathFor(listenerSettings?.http),
          ),
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': error.reason,
            if (error.message != null) 'message': error.message,
          }),
        ),
      );
      retainedHandshake?.release();
      return;
    } catch (error, stackTrace) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_request_session_error',
        'listenerId': request.listenerId,
        'connectionId': request.connectionId,
        'endpoint': request.endpoint,
        'realm': resolvedRealmUri,
        'procedure': procedure,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      retainedHandshake?.release();
      return;
    }

    final httpDetails = <String, Object?>{...requestPayload};
    final connectionDetails = <String, Object?>{
      'listenerId': request.listenerId,
      'connectionId': request.connectionId,
      'endpoint': request.endpoint,
    };
    final keywords = <String, Object?>{
      '_http': httpDetails,
      '_connection': connectionDetails,
    };

    final pending = _PendingHttpCall(
      id: httpRequestId,
      request: request,
      snapshot: snapshot,
      session: session,
      handshake: retainedHandshake,
    );
    _pendingHttpCalls[httpRequestId] = pending;

    StreamSubscription<result_msg.Result>? subscription;
    try {
      final options = call_msg.CallOptions(
        custom: <String, dynamic>{
          HttpInvocationKeys.requestId: httpRequestId,
          HttpInvocationKeys.request: requestPayload,
          HttpInvocationKeys.responseStreamControlPort:
              session._controlPort.sendPort,
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
            final pending = _pendingHttpCalls[httpRequestId];
            if (pending?.directResponseStream != null) {
              pending!.directResponseStreamCompleted = true;
            }
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
      pending.subscription = subscription;
    } catch (error, stackTrace) {
      _pendingHttpCalls.remove(httpRequestId);
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
    retainedHandshake = null;
    onEvent?.call({
      'source': 'binding',
      'type': 'http_request_dispatched',
      'httpRequestId': httpRequestId,
      'listenerId': request.listenerId,
      'connectionId': request.connectionId,
      'realm': resolvedRealmUri,
      'procedure': procedure,
    });

    retainedHandshake?.release();
  }

  Future<RouterSession> _ensureInternalSession({
    required String realmUri,
    String? sessionProfile,
    String? authId,
    String? authRole,
    String? authMethod,
    String? authProvider,
    Map<String, Object?> roles = const {},
    String? cacheKey,
    bool authorizationIsInternal = true,
  }) async {
    final resolvedCacheKey =
        cacheKey ??
        (authorizationIsInternal
            ? sessionProfile
            : _externalSessionCacheKey(
                realmUri: realmUri,
                sessionProfile: sessionProfile,
                authId: authId,
                authRole: authRole,
                authMethod: authMethod,
                authProvider: authProvider,
              ));
    final existing = resolvedCacheKey == null
        ? (authorizationIsInternal ? _internalSessionsByRealm[realmUri] : null)
        : _internalSessionsByCacheKey[resolvedCacheKey];
    if (existing != null) {
      return existing;
    }
    return createInternalSession(
      realmUri: realmUri,
      authId: authId,
      authRole: authRole,
      authMethod: authMethod,
      authProvider: authProvider,
      roles: roles,
      sessionProfile: sessionProfile,
      cacheKey: resolvedCacheKey,
      authorizationIsInternal: authorizationIsInternal,
      indexByRealm: authorizationIsInternal && resolvedCacheKey == null,
    );
  }

  String _externalSessionCacheKey({
    required String realmUri,
    String? sessionProfile,
    String? authId,
    String? authRole,
    String? authMethod,
    String? authProvider,
  }) {
    return [
      'http-external',
      realmUri,
      sessionProfile ?? '',
      authId ?? 'anonymous',
      authRole ?? '',
      authMethod ?? '',
      authProvider ?? '',
    ].join(':');
  }

  SessionProfileSettings? _resolveHttpSessionProfile({
    required ListenerSettings? listenerSettings,
    required HttpRouteSettings? route,
  }) {
    final routeProfile = route?.action.sessionProfile?.trim();
    final listenerProfile = listenerSettings?.http?.sessionProfile?.trim();
    final profileName = (routeProfile != null && routeProfile.isNotEmpty)
        ? routeProfile
        : ((listenerProfile != null && listenerProfile.isNotEmpty)
              ? listenerProfile
              : null);
    return _resolveSessionProfile(profileName);
  }

  _HttpRouteMatchResult _matchHttpRoute(
    HttpListenerSettings? httpSettings,
    RouterHttpRequest request,
  ) {
    if (httpSettings == null) {
      return const _HttpRouteMatchResult.notFound();
    }
    final allowedMethods = <String>{};
    final allowedProtocols = <String>{};
    HttpRouteSettings? methodNotAllowedRoute;
    HttpRouteSettings? protocolNotAllowedRoute;
    for (final route in httpSettings.routes) {
      if (_httpRouteMatchesRequest(route, request)) {
        return _HttpRouteMatchResult.route(route);
      }
      if (_httpRouteMatchesRequest(route, request, ignoreMethod: true)) {
        methodNotAllowedRoute ??= route;
        allowedMethods.addAll(_httpRouteAllowedMethods(route));
      }
      if (route.match.protocols.isNotEmpty &&
          _httpRouteMatchesRequest(
            route,
            request,
            ignoreMethod: true,
            ignoreProtocol: true,
          )) {
        final requestProtocol = _normaliseHttpRouteProtocol(request.protocol);
        final routeProtocols = route.match.protocols
            .map(_normaliseHttpRouteProtocol)
            .where((protocol) => protocol.isNotEmpty);
        if (!routeProtocols.contains(requestProtocol)) {
          protocolNotAllowedRoute ??= route;
          allowedProtocols.addAll(routeProtocols);
        }
      }
    }
    if (allowedMethods.isNotEmpty) {
      final normalized = allowedMethods.toList(growable: false)..sort();
      return _HttpRouteMatchResult.methodNotAllowed(
        normalized,
        route: methodNotAllowedRoute,
      );
    }
    if (allowedProtocols.isNotEmpty) {
      final normalized = allowedProtocols.toList(growable: false)..sort();
      return _HttpRouteMatchResult.protocolNotAllowed(
        normalized,
        route: protocolNotAllowedRoute,
      );
    }
    return const _HttpRouteMatchResult.notFound();
  }

  List<String> _httpRouteAllowedMethods(HttpRouteSettings route) {
    final allowed = <String>{};
    for (final method in route.match.methods) {
      final normalized = method.trim().toUpperCase();
      if (normalized.isNotEmpty) {
        allowed.add(normalized);
      }
    }
    for (final method in route.methodActions.keys) {
      final normalized = method.trim().toUpperCase();
      if (normalized.isNotEmpty) {
        allowed.add(normalized);
      }
    }
    return allowed.toList(growable: false);
  }

  bool _httpRouteMatchesRequest(
    HttpRouteSettings route,
    RouterHttpRequest request, {
    bool ignoreMethod = false,
    bool ignoreProtocol = false,
  }) {
    final match = route.match;
    if (match.path != null && match.path != request.path) {
      return false;
    }
    if (match.path == null &&
        match.prefix != null &&
        !request.path.startsWith(match.prefix!)) {
      return false;
    }
    if (match.host != null) {
      final hostHeader = request.headers.entries
          .firstWhere(
            (entry) => entry.key.toLowerCase() == 'host',
            orElse: () => const MapEntry<String, String>('', ''),
          )
          .value;
      if (hostHeader.isEmpty) {
        return false;
      }
      final requestHost = hostHeader.split(':').first.trim().toLowerCase();
      if (requestHost != match.host!.trim().toLowerCase()) {
        return false;
      }
    }
    if (!ignoreProtocol && match.protocols.isNotEmpty) {
      final requestProtocol = _normaliseHttpRouteProtocol(request.protocol);
      final allowedProtocols = match.protocols.map(_normaliseHttpRouteProtocol);
      if (!allowedProtocols.contains(requestProtocol)) {
        return false;
      }
    }
    final allowedMethods = _httpRouteAllowedMethods(route);
    if (!ignoreMethod && allowedMethods.isNotEmpty) {
      final requestMethod = request.method.trim().toUpperCase();
      if (!allowedMethods.contains(requestMethod)) {
        return false;
      }
    }
    if (match.headers.isNotEmpty) {
      final normalizedHeaders = <String, String>{
        for (final entry in request.headers.entries)
          entry.key.toLowerCase(): entry.value,
      };
      for (final entry in match.headers.entries) {
        final actual = normalizedHeaders[entry.key.toLowerCase()];
        if (actual != entry.value) {
          return false;
        }
      }
    }
    return true;
  }

  _HttpRouteTransportAuthFailure? _evaluateHttpRouteTransportAuth({
    required RouterHttpRequest request,
    required HttpRouteSettings? route,
    required SessionProfileSettings? sessionProfile,
    required ListenerSettings? listenerSettings,
  }) {
    if (route == null) {
      return null;
    }
    final requirements = deriveHttpRouteTransportAuth(
      action: route.action,
      sessionProfile: sessionProfile,
    );
    if (!requirements.isConfigured) {
      return null;
    }
    if (requirements.requireMutualTls &&
        request.listener.endpoint.clientAuth?.mode !=
            TlsClientAuthMode.required) {
      return const _HttpRouteTransportAuthFailure.forbidden(
        reason: 'mutual_tls_required',
        message: 'Mutual TLS is required for this route',
      );
    }
    if (requirements.requireTls &&
        request.listener.endpoint.tlsMode == TlsMode.disabled) {
      return const _HttpRouteTransportAuthFailure.forbidden(
        reason: 'tls_required',
        message: 'TLS is required for this route',
      );
    }
    final bearerlessCorsPreflight =
        requirements.allowUnauthenticatedCorsPreflight &&
        request.method.toUpperCase() == 'OPTIONS' &&
        (_headerValue(request.headers, 'origin')?.trim().isNotEmpty ?? false) &&
        (_headerValue(
              request.headers,
              'access-control-request-method',
            )?.trim().isNotEmpty ??
            false);
    if (requirements.requireBearer &&
        !bearerlessCorsPreflight &&
        _extractBearerToken(request.headers) == null) {
      return _HttpRouteTransportAuthFailure.unauthorized(
        reason: 'unauthorized',
        message: 'Bearer token required',
      );
    }
    return null;
  }

  _HttpRouteRateLimitDecision? _evaluateHttpRouteRateLimit({
    required RouterHttpRequest request,
    required HttpRouteSettings? route,
  }) {
    final routeSettings = route;
    final settings = routeSettings?.action.rateLimit;
    if (routeSettings == null || settings == null) {
      return null;
    }
    final maxRequests = settings.maxRequests <= 0 ? 1 : settings.maxRequests;
    final windowMs = settings.windowMs <= 0 ? 1 : settings.windowMs;
    final now = DateTime.now().toUtc();
    final window = Duration(milliseconds: windowMs);
    final bucketKey = _httpRouteRateLimitBucketKey(
      request: request,
      route: routeSettings,
      settings: settings,
    );
    final state = _httpRouteRateLimitStates[bucketKey];
    if (state == null || now.difference(state.windowStart) >= window) {
      _httpRouteRateLimitStates[bucketKey] = _HttpRouteRateLimitState(
        windowStart: now,
        count: 1,
      );
      return null;
    }
    if (state.count < maxRequests) {
      state.count += 1;
      return null;
    }
    final resetAt = state.windowStart.add(window);
    final retryAfter = resetAt.difference(now);
    return _HttpRouteRateLimitDecision(
      key: settings.key,
      limit: maxRequests,
      windowMs: windowMs,
      retryAfterMs: retryAfter.isNegative ? 0 : retryAfter.inMilliseconds,
      resetAt: resetAt,
    );
  }

  String _httpRouteRateLimitBucketKey({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required HttpRouteRateLimitSettings settings,
  }) {
    final key = settings.key.trim().toLowerCase();
    final scopeValue = switch (key) {
      'connection' => 'connection:${request.connectionId}',
      'bearer' =>
        'bearer:${_extractBearerToken(request.headers) ?? '<missing>'}',
      _ when key.startsWith('header:') => _httpRouteRateLimitHeaderBucket(
        request,
        key.substring('header:'.length),
      ),
      _ => 'global',
    };
    return '${identityHashCode(route)}|$key|$scopeValue';
  }

  String _httpRouteRateLimitHeaderBucket(
    RouterHttpRequest request,
    String headerName,
  ) {
    final normalized = headerName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'header:<missing>:<missing>';
    }
    return 'header:$normalized:${_headerValue(request.headers, normalized) ?? '<missing>'}';
  }

  bool _isCorsPreflight(RouterHttpRequest request) {
    return request.method.toUpperCase() == 'OPTIONS' &&
        (_headerValue(request.headers, 'origin')?.trim().isNotEmpty ?? false) &&
        (_headerValue(
              request.headers,
              'access-control-request-method',
            )?.trim().isNotEmpty ??
            false);
  }

  Future<void> _handleHttpAuthRequest({
    required RouterHttpRequest request,
    required NativeHttpHandshake? handshake,
    required ListenerSettings? listenerSettings,
    required HttpRouteSettings route,
    required SessionProfileSettings? sessionProfile,
  }) async {
    if (request.method.trim().toUpperCase() != 'POST') {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.methodNotAllowed,
          headers: const {HttpHeaders.allowHeader: 'POST'},
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'method_not_allowed',
            'message': 'HTTP auth bridge only supports POST',
          }),
        ),
      );
      return;
    }

    late final Map<String, Object?> body;
    try {
      body = _decodeHttpJsonBody(request);
    } on FormatException catch (error) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.badRequest,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': 'invalid_json',
            'message': error.message,
          }),
        ),
      );
      return;
    }
    final query = _httpQueryParameters(request);
    final allowedMethods = sessionProfile?.auth.methods ?? const <String>[];
    if (allowedMethods.isEmpty) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.badRequest,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'invalid_profile',
            'message':
                'HTTP auth route requires a session profile with auth methods',
          }),
        ),
      );
      return;
    }

    final state = _firstNonEmptyString(
      body['state'],
      query['state'],
      _headerValue(request.headers, 'x-connectanum-auth-state'),
    );

    if (state != null) {
      await _continueHttpAuthTransaction(
        request: request,
        handshake: handshake,
        state: state,
        body: body,
        sessionProfile: sessionProfile,
        route: route,
        listenerSettings: listenerSettings,
      );
      return;
    }

    final grantType = _firstNonEmptyString(
      body['grant_type'],
      query['grant_type'],
      _headerValue(request.headers, 'x-connectanum-grant-type'),
    );
    if (grantType != null) {
      switch (grantType) {
        case 'refresh':
        case 'refresh_token':
          await _handleHttpRefreshGrant(
            request: request,
            handshake: handshake,
            body: body,
            query: query,
            sessionProfile: sessionProfile,
            route: route,
            listenerSettings: listenerSettings,
          );
          return;
        case 'revoke':
        case 'revocation':
          await _handleHttpRevokeGrant(
            request: request,
            handshake: handshake,
            body: body,
            query: query,
          );
          return;
      }
    }

    registerDefaultAuthenticators();
    final realmUri = _resolveHttpAuthRealm(
      request: request,
      route: route,
      sessionProfile: sessionProfile,
      body: body,
      query: query,
    );
    if (realmUri == null || realmUri.isEmpty) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.badRequest,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'missing_realm',
            'message': 'realm is required for HTTP authentication',
          }),
        ),
      );
      return;
    }

    final realmSettings = _realmSettingsFor(realmUri);
    if (realmSettings == null) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.notFound,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': wamp_core.Error.noSuchRealm,
            'message': 'Realm $realmUri is not configured',
          }),
        ),
      );
      return;
    }

    final authMethod = _firstNonEmptyString(
      body['authmethod'],
      query['authmethod'],
      _headerValue(request.headers, 'x-connectanum-auth-method'),
    );
    if (authMethod == null || authMethod == 'anonymous') {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.badRequest,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'missing_authmethod',
            'message': 'authmethod is required and must not be anonymous',
          }),
        ),
      );
      return;
    }
    if (!allowedMethods.contains(authMethod)) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': 'unsupported_authmethod',
            'message': 'authmethod $authMethod is not allowed for this route',
          }),
        ),
      );
      return;
    }
    if (realmSettings.auth.methods.isNotEmpty &&
        !realmSettings.auth.methods.contains(authMethod)) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': 'unsupported_authmethod',
            'message':
                'authmethod $authMethod is not enabled for realm $realmUri',
          }),
        ),
      );
      return;
    }

    final selection = createAuthenticatorSelectionForMethod(
      settings: settings,
      realmSettings: realmSettings,
      method: authMethod,
    );
    if (selection == null) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': 'unsupported_authmethod',
            'message': 'No authenticator is configured for $authMethod',
          }),
        ),
      );
      return;
    }

    final authId = _firstNonEmptyString(
      body['authid'],
      query['authid'],
      _headerValue(request.headers, 'x-connectanum-auth-id'),
    );
    final helloDetails = <String, Object?>{
      'authid': ?authId,
      'authmethods': <String>[authMethod],
      if (body['authextra'] is Map<String, Object?>)
        'authextra': Map<String, Object?>.from(
          body['authextra'] as Map<String, Object?>,
        )
      else if (body['authextra'] is Map)
        'authextra': Map<String, Object?>.from(body['authextra'] as Map),
    };

    final boss = _boss;
    if (boss == null) {
      throw StateError('HTTP auth bridge requires the router boss.');
    }
    final sessionId = await _allocateSessionId(boss.stateCommandPort);
    final authenticator = await selection.factory!.create(
      realmSettings,
      selection.options,
    );
    final context = AuthenticatorContext(
      realm: realmSettings,
      sessionId: sessionId,
      transport: buildTransportMetadata(
        listener: request.listener,
        connectionId: request.connectionId,
      ),
      helloDetails: helloDetails,
    );

    final result = await authenticator.onHello(context);
    switch (result.status) {
      case AuthStatus.challenge:
        final challenge = result.challenge!;
        final authState = _randomHttpAuthToken();
        final timeoutMs = realmSettings.limits.authTimeoutMs;
        _pendingHttpAuthTransactions[authState] = _PendingHttpAuthTransaction(
          state: authState,
          realmUri: realmUri,
          authMethod: authMethod,
          authId: authId,
          authenticator: authenticator,
          context: context,
          sessionProfileName: sessionProfile?.name,
          expiresAt: DateTime.now().toUtc().add(
            Duration(milliseconds: timeoutMs > 0 ? timeoutMs : 10000),
          ),
        );
        await _sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.unauthorized,
            headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'challenge',
              'state': authState,
              'realm': realmUri,
              'authmethod': authMethod,
              'challenge': challenge.challenge,
              'extra': challenge.extra,
            }),
          ),
        );
      case AuthStatus.success:
        final token = _issueHttpAuthToken(
          realmUri: realmUri,
          authMethod: authMethod,
          authProvider: _resolveAuthProviderFromDetails(
            result.success!.details,
          ),
          authId: result.success!.authId,
          authRole: result.success!.authRole,
          details: result.success!.details,
          sessionProfileName: sessionProfile?.name,
          route: route,
          listenerSettings: listenerSettings,
          realmSettings: realmSettings,
        );
        await _sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.ok,
            body: NativeHttpResponseJson(_httpAuthSuccessPayload(token)),
          ),
        );
      case AuthStatus.failure:
        await _sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.unauthorized,
            headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'error',
              'reason': result.failure!.reason,
              if (result.failure!.message != null)
                'message': result.failure!.message,
            }),
          ),
        );
    }
  }

  Future<void> _continueHttpAuthTransaction({
    required RouterHttpRequest request,
    required NativeHttpHandshake? handshake,
    required String state,
    required Map<String, Object?> body,
    required SessionProfileSettings? sessionProfile,
    required HttpRouteSettings route,
    required ListenerSettings? listenerSettings,
  }) async {
    final pending = _pendingHttpAuthTransactions.remove(state);
    if (pending == null) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'invalid_state',
            'message': 'Authentication state is unknown or expired',
          }),
        ),
      );
      return;
    }
    if (pending.expiresAt.isBefore(DateTime.now().toUtc())) {
      await pending.abort(reason: 'http_auth_timeout');
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'expired_state',
            'message': 'Authentication state expired',
          }),
        ),
      );
      return;
    }

    final signature = _firstNonEmptyString(
      body['signature'],
      _headerValue(request.headers, 'x-connectanum-auth-signature'),
    );
    if (signature == null || signature.isEmpty) {
      await pending.abort(reason: 'missing_signature');
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.badRequest,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'missing_signature',
            'message': 'signature is required to complete authentication',
          }),
        ),
      );
      return;
    }
    final extra = body['extra'];
    final message = AuthenticateMessage(
      signature: signature,
      extra: extra is Map<String, Object?>
          ? Map<String, Object?>.from(extra)
          : extra is Map
          ? Map<String, Object?>.from(extra)
          : const <String, Object?>{},
    );
    final result = await pending.authenticator.onAuthenticate(
      pending.context,
      message,
    );
    switch (result.status) {
      case AuthStatus.challenge:
        final nextState = _randomHttpAuthToken();
        _pendingHttpAuthTransactions[nextState] = pending.copyWith(
          state: nextState,
          expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 10)),
        );
        await _sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.unauthorized,
            headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'challenge',
              'state': nextState,
              'realm': pending.realmUri,
              'authmethod': pending.authMethod,
              'challenge': result.challenge!.challenge,
              'extra': result.challenge!.extra,
            }),
          ),
        );
      case AuthStatus.success:
        final realmSettings = _realmSettingsFor(pending.realmUri);
        if (realmSettings == null) {
          await _sendImmediateHttpResponse(
            request: request,
            handshake: handshake,
            response: NativeHttpResponse(
              status: HttpStatus.unauthorized,
              body: NativeHttpResponseJson(<String, Object?>{
                'status': 'error',
                'reason': wamp_core.Error.noSuchRealm,
                'message': 'Realm ${pending.realmUri} is no longer configured',
              }),
            ),
          );
          return;
        }
        final token = _issueHttpAuthToken(
          realmUri: pending.realmUri,
          authMethod: pending.authMethod,
          authProvider: _resolveAuthProviderFromDetails(
            result.success!.details,
          ),
          authId: result.success!.authId,
          authRole: result.success!.authRole,
          details: result.success!.details,
          sessionProfileName:
              pending.sessionProfileName ?? sessionProfile?.name,
          route: route,
          listenerSettings: listenerSettings,
          realmSettings: realmSettings,
        );
        await _sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.ok,
            body: NativeHttpResponseJson(_httpAuthSuccessPayload(token)),
          ),
        );
      case AuthStatus.failure:
        await pending.abort(reason: 'authenticate_failed');
        await _sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.unauthorized,
            headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'error',
              'reason': result.failure!.reason,
              if (result.failure!.message != null)
                'message': result.failure!.message,
            }),
          ),
        );
    }
  }

  Future<void> _handleHttpRefreshGrant({
    required RouterHttpRequest request,
    required NativeHttpHandshake? handshake,
    required Map<String, Object?> body,
    required Map<String, String> query,
    required SessionProfileSettings? sessionProfile,
    required HttpRouteSettings route,
    required ListenerSettings? listenerSettings,
  }) async {
    final refreshToken = _firstNonEmptyString(
      body['refresh_token'],
      body['token'],
      query['refresh_token'],
    );
    if (refreshToken == null || refreshToken.isEmpty) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.badRequest,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'missing_refresh_token',
            'message': 'refresh_token is required',
          }),
        ),
      );
      return;
    }

    final record = _httpRefreshTokens[refreshToken];
    if (record == null) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'invalid_refresh_token',
            'message': 'Refresh token is unknown',
          }),
        ),
      );
      return;
    }
    if (record.expiresAt.isBefore(DateTime.now().toUtc())) {
      await _revokeHttpRefreshToken(refreshToken);
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          headers: const {HttpHeaders.wwwAuthenticateHeader: 'Bearer'},
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'expired_refresh_token',
            'message': 'Refresh token expired',
          }),
        ),
      );
      return;
    }

    final allowedMethods = sessionProfile?.auth.methods ?? const <String>[];
    if (allowedMethods.isNotEmpty &&
        !allowedMethods.contains('anonymous') &&
        !allowedMethods.contains(record.authMethod)) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          body: NativeHttpResponseJson(const <String, Object?>{
            'status': 'error',
            'reason': 'wrong_authmethod',
            'message':
                'Refresh token auth method is not allowed for this route',
          }),
        ),
      );
      return;
    }

    final realmSettings = _realmSettingsFor(record.realmUri);
    if (realmSettings == null) {
      await _sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: NativeHttpResponse(
          status: HttpStatus.unauthorized,
          body: NativeHttpResponseJson(<String, Object?>{
            'status': 'error',
            'reason': wamp_core.Error.noSuchRealm,
            'message': 'Realm ${record.realmUri} is no longer configured',
          }),
        ),
      );
      return;
    }

    final rotateRefreshTokens = _resolveHttpRotateRefreshTokens(
      route: route,
      listenerSettings: listenerSettings,
    );
    final linkedAccessTokens = record.accessTokens.toList(growable: false);
    for (final accessToken in linkedAccessTokens) {
      await _revokeHttpAccessToken(accessToken, removeFromRefreshToken: false);
    }

    late final _HttpAuthIssueResult issued;
    if (rotateRefreshTokens) {
      _httpRefreshTokens.remove(refreshToken);
      issued = _issueHttpAuthToken(
        realmUri: record.realmUri,
        authMethod: record.authMethod,
        authProvider: record.authProvider,
        authId: record.authId,
        authRole: record.authRole,
        details: record.details,
        sessionProfileName: record.sessionProfileName ?? sessionProfile?.name,
        route: route,
        listenerSettings: listenerSettings,
        realmSettings: realmSettings,
      );
    } else {
      final accessRecord = _issueHttpAccessTokenRecord(
        realmUri: record.realmUri,
        authMethod: record.authMethod,
        authProvider: record.authProvider,
        authId: record.authId,
        authRole: record.authRole,
        details: record.details,
        sessionProfileName: record.sessionProfileName ?? sessionProfile?.name,
        expiresAt: DateTime.now().toUtc().add(
          _resolveHttpAuthTokenTtl(
            route: route,
            listenerSettings: listenerSettings,
            realmSettings: realmSettings,
          ),
        ),
        refreshToken: refreshToken,
      );
      _httpAuthTokens[accessRecord.token] = accessRecord;
      record
        ..accessTokens.clear()
        ..accessTokens.add(accessRecord.token);
      issued = _HttpAuthIssueResult(
        accessToken: accessRecord,
        refreshToken: record,
      );
    }

    await _sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.ok,
        body: NativeHttpResponseJson(_httpAuthSuccessPayload(issued)),
      ),
    );
  }

  Future<void> _handleHttpRevokeGrant({
    required RouterHttpRequest request,
    required NativeHttpHandshake? handshake,
    required Map<String, Object?> body,
    required Map<String, String> query,
  }) async {
    final token = _firstNonEmptyString(
      body['token'],
      body['refresh_token'],
      query['token'],
    );
    final tokenTypeHint = _firstNonEmptyString(
      body['token_type_hint'],
      query['token_type_hint'],
      _headerValue(request.headers, 'x-connectanum-token-type-hint'),
    );

    if (token != null && token.isNotEmpty) {
      if (tokenTypeHint == 'refresh_token') {
        await _revokeHttpRefreshToken(token);
      } else if (tokenTypeHint == 'access_token') {
        await _revokeHttpAccessToken(token);
      } else if (_httpRefreshTokens.containsKey(token)) {
        await _revokeHttpRefreshToken(token);
      } else {
        await _revokeHttpAccessToken(token);
      }
    }

    await _sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.ok,
        body: NativeHttpResponseJson(const <String, Object?>{
          'status': 'revoked',
        }),
      ),
    );
  }

  RealmSettings? _realmSettingsFor(String realmUri) {
    for (final realm in settings.realms) {
      if (realm.name == realmUri) {
        return realm;
      }
    }
    return null;
  }

  String? _resolveHttpAuthRealm({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required SessionProfileSettings? sessionProfile,
    required Map<String, Object?> body,
    required Map<String, String> query,
  }) {
    final bodyRealm = _firstNonEmptyString(body['realm']);
    if (bodyRealm != null) {
      return bodyRealm;
    }
    final queryRealm = _firstNonEmptyString(query['realm']);
    if (queryRealm != null) {
      return queryRealm;
    }
    final headerRealm = _headerValue(request.headers, 'x-connectanum-realm');
    if (headerRealm != null && headerRealm.isNotEmpty) {
      return headerRealm;
    }
    final routeRealm = route.action.realm?.trim();
    if (routeRealm != null && routeRealm.isNotEmpty) {
      return routeRealm;
    }
    final profileRealm = sessionProfile?.realm?.trim();
    if (profileRealm != null && profileRealm.isNotEmpty) {
      return profileRealm;
    }
    final requestRealm = request.realm?.trim();
    if (requestRealm != null && requestRealm.isNotEmpty) {
      return requestRealm;
    }
    return null;
  }

  Future<_ConfiguredHttpAuthProvider?> _configuredHttpAuthProviderFor(
    SessionProfileSettings? sessionProfile,
  ) async {
    final providerName = sessionProfile?.auth.httpProvider?.trim();
    if (providerName == null || providerName.isEmpty) {
      return null;
    }
    final definition = settings.httpAuthProviders[providerName];
    if (definition == null) {
      throw StateError(
        'Session profile ${sessionProfile!.name} references unknown '
        'HTTP auth provider $providerName',
      );
    }
    registerDefaultHttpAuthProviders();
    final future = _httpAuthProviderCache.putIfAbsent(providerName, () async {
      final factory = HttpAuthProviderRegistry.factoryFor(definition.type);
      if (factory == null) {
        throw StateError(
          'No HTTP auth provider factory registered for ${definition.type}',
        );
      }
      return factory.create(<String, Object?>{
        'name': providerName,
        ...definition.options,
      });
    });
    return _ConfiguredHttpAuthProvider(
      name: providerName,
      provider: await future,
    );
  }

  Future<RouterSession> _authenticatedHttpSessionForToken({
    required String token,
    required RouterHttpRequest request,
    required String realmUri,
    required SessionProfileSettings? sessionProfile,
  }) async {
    final record = _httpAuthTokens[token];
    if (record != null) {
      if (record.expiresAt.isBefore(DateTime.now().toUtc())) {
        await _revokeHttpAccessToken(token);
        throw const _HttpUnauthorized(
          reason: 'expired_token',
          message: 'Bearer token expired',
        );
      }
      if (record.realmUri != realmUri) {
        throw const _HttpUnauthorized(
          reason: 'wrong_realm',
          message: 'Bearer token does not grant access to this realm',
        );
      }
      final allowedMethods = sessionProfile?.auth.methods;
      if (allowedMethods != null &&
          allowedMethods.isNotEmpty &&
          !allowedMethods.contains('anonymous') &&
          !allowedMethods.contains(record.authMethod)) {
        throw const _HttpUnauthorized(
          reason: 'wrong_authmethod',
          message: 'Bearer token auth method is not allowed for this route',
        );
      }
      final cacheKey =
          sessionProfile?.name != null && sessionProfile!.name.isNotEmpty
          ? '${record.cacheKeyPrefix}:${sessionProfile.name}'
          : record.cacheKeyPrefix;
      return _ensureInternalSession(
        realmUri: realmUri,
        authId: record.authId,
        authRole: record.authRole,
        authMethod: record.authMethod,
        authProvider: record.authProvider,
        sessionProfile: sessionProfile?.name,
        cacheKey: cacheKey,
        authorizationIsInternal: false,
      );
    }

    final configuredProvider = await _configuredHttpAuthProviderFor(
      sessionProfile,
    );
    if (configuredProvider == null) {
      throw const _HttpUnauthorized(
        reason: 'invalid_token',
        message: 'Bearer token is unknown',
      );
    }

    final providerResult = await configuredProvider.provider.authenticate(
      HttpAuthBearerRequest(
        token: token,
        realmUri: realmUri,
        method: request.method,
        path: request.path,
        headers: request.headers,
        transport: buildTransportMetadata(
          listener: request.listener,
          connectionId: request.connectionId,
        ),
        sessionProfileName: sessionProfile?.name,
      ),
    );
    if (!providerResult.success) {
      final failure = providerResult.failure!;
      throw _HttpUnauthorized(reason: failure.reason, message: failure.message);
    }
    final authenticated = providerResult.authenticated!;
    final allowedMethods = sessionProfile?.auth.methods;
    if (allowedMethods != null &&
        allowedMethods.isNotEmpty &&
        !allowedMethods.contains('anonymous') &&
        !allowedMethods.contains(authenticated.authMethod)) {
      throw const _HttpUnauthorized(
        reason: 'wrong_authmethod',
        message: 'Bearer token auth method is not allowed for this route',
      );
    }

    final cacheKeyBase =
        'http-external:${configuredProvider.name}:$realmUri:$token';
    return _ensureInternalSession(
      realmUri: realmUri,
      authId: authenticated.authId,
      authRole: authenticated.authRole,
      authMethod: authenticated.authMethod,
      authProvider: authenticated.authProvider,
      roles: authenticated.roles,
      sessionProfile: sessionProfile?.name,
      cacheKey: sessionProfile?.name != null && sessionProfile!.name.isNotEmpty
          ? '$cacheKeyBase:${sessionProfile.name}'
          : cacheKeyBase,
      authorizationIsInternal: false,
    );
  }

  String? _extractBearerToken(Map<String, String> headers) {
    final header = _headerValue(headers, HttpHeaders.authorizationHeader);
    if (header == null) {
      return null;
    }
    const scheme = 'bearer';
    final value = header.trim();
    if (value.length <= scheme.length ||
        value.substring(0, scheme.length).toLowerCase() != scheme) {
      return null;
    }
    final separator = value.codeUnitAt(scheme.length);
    if (separator != 0x20 && separator != 0x09) {
      return null;
    }
    final token = value.substring(scheme.length + 1).trim();
    final hasInvalidTokenCharacter = token.codeUnits.any(
      (codeUnit) => codeUnit <= 0x20 || codeUnit == 0x7f,
    );
    if (token.isEmpty || hasInvalidTokenCharacter) {
      return null;
    }
    return token;
  }

  Map<String, String> _httpUnauthorizedHeaders({
    required String realm,
    required String authPath,
  }) {
    return <String, String>{
      HttpHeaders.wwwAuthenticateHeader:
          'Bearer realm="$realm", auth_path="$authPath"',
    };
  }

  String _httpAuthPathFor(HttpListenerSettings? httpSettings) {
    if (httpSettings == null) {
      return '/auth';
    }
    for (final route in httpSettings.routes) {
      if (route.action.type == HttpRouteActionType.auth &&
          route.match.path != null &&
          route.match.path!.isNotEmpty) {
        return route.match.path!;
      }
    }
    return '/auth';
  }

  Future<void> _sendImmediateHttpResponse({
    required RouterHttpRequest request,
    required NativeHttpHandshake? handshake,
    required NativeHttpResponse response,
  }) async {
    final handle = handshake?.handle ?? request.handshakeHandle;
    if (handle <= 0) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_response_send_unsupported',
        'connectionId': request.connectionId,
        'listenerId': request.listenerId,
        'error': 'missing native handshake handle',
      });
      return;
    }
    runtime.sendHttpResponse(
      handshakeHandle: handle,
      connectionId: request.connectionId,
      response: response,
    );
  }

  Map<String, Object?> _decodeHttpJsonBody(RouterHttpRequest request) {
    final bytes = request.body;
    if (bytes.isEmpty) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) {
      return Map<String, Object?>.from(decoded);
    }
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw FormatException('HTTP auth body must decode to a JSON object');
  }

  Map<String, String> _httpQueryParameters(RouterHttpRequest request) {
    final query = request.query;
    if (query == null || query.isEmpty) {
      return const <String, String>{};
    }
    return Uri.splitQueryString(query);
  }

  String? _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  String? _firstNonEmptyString([Object? a, Object? b, Object? c]) {
    for (final candidate in <Object?>[a, b, c]) {
      if (candidate is String) {
        final trimmed = candidate.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }

  _HttpAuthIssueResult _issueHttpAuthToken({
    required String realmUri,
    required String authMethod,
    required String? authProvider,
    required String authId,
    required String authRole,
    required Map<String, Object?> details,
    required String? sessionProfileName,
    required HttpRouteSettings? route,
    required ListenerSettings? listenerSettings,
    required RealmSettings realmSettings,
  }) {
    final ttl = _resolveHttpAuthTokenTtl(
      route: route,
      listenerSettings: listenerSettings,
      realmSettings: realmSettings,
    );
    final refreshTtl = _resolveHttpRefreshTokenTtl(
      route: route,
      listenerSettings: listenerSettings,
      realmSettings: realmSettings,
    );
    _HttpRefreshTokenRecord? refreshRecord;
    if (refreshTtl > Duration.zero) {
      final refreshToken = _randomHttpAuthToken();
      refreshRecord = _HttpRefreshTokenRecord(
        token: refreshToken,
        realmUri: realmUri,
        authMethod: authMethod,
        authProvider: authProvider,
        authId: authId,
        authRole: authRole,
        details: Map<String, Object?>.unmodifiable(details),
        sessionProfileName: sessionProfileName,
        expiresAt: DateTime.now().toUtc().add(refreshTtl),
      );
      _httpRefreshTokens[refreshToken] = refreshRecord;
    }
    final accessRecord = _issueHttpAccessTokenRecord(
      realmUri: realmUri,
      authMethod: authMethod,
      authProvider: authProvider,
      authId: authId,
      authRole: authRole,
      details: details,
      sessionProfileName: sessionProfileName,
      expiresAt: DateTime.now().toUtc().add(ttl),
      refreshToken: refreshRecord?.token,
    );
    _httpAuthTokens[accessRecord.token] = accessRecord;
    refreshRecord?.accessTokens.add(accessRecord.token);
    return _HttpAuthIssueResult(
      accessToken: accessRecord,
      refreshToken: refreshRecord,
    );
  }

  _HttpAuthTokenRecord _issueHttpAccessTokenRecord({
    required String realmUri,
    required String authMethod,
    required String? authProvider,
    required String authId,
    required String authRole,
    required Map<String, Object?> details,
    required String? sessionProfileName,
    required DateTime expiresAt,
    required String? refreshToken,
  }) {
    final token = _randomHttpAuthToken();
    return _HttpAuthTokenRecord(
      token: token,
      realmUri: realmUri,
      authMethod: authMethod,
      authProvider: authProvider,
      authId: authId,
      authRole: authRole,
      details: Map<String, Object?>.unmodifiable(details),
      sessionProfileName: sessionProfileName,
      expiresAt: expiresAt,
      refreshToken: refreshToken,
    );
  }

  Duration _resolveHttpAuthTokenTtl({
    required HttpRouteSettings? route,
    required ListenerSettings? listenerSettings,
    required RealmSettings realmSettings,
  }) {
    final routeTtl = route?.action.options['token_ttl_ms'];
    if (routeTtl is int && routeTtl > 0) {
      return Duration(milliseconds: routeTtl);
    }
    final listenerTtl = listenerSettings?.http?.options['auth_token_ttl_ms'];
    if (listenerTtl is int && listenerTtl > 0) {
      return Duration(milliseconds: listenerTtl);
    }
    final idleMs = realmSettings.limits.sessionIdleMs;
    if (idleMs > 0) {
      return Duration(milliseconds: idleMs);
    }
    return const Duration(minutes: 15);
  }

  Duration _resolveHttpRefreshTokenTtl({
    required HttpRouteSettings? route,
    required ListenerSettings? listenerSettings,
    required RealmSettings realmSettings,
  }) {
    final routeTtl = route?.action.options['refresh_token_ttl_ms'];
    if (routeTtl is int) {
      return routeTtl > 0 ? Duration(milliseconds: routeTtl) : Duration.zero;
    }
    final listenerTtl =
        listenerSettings?.http?.options['auth_refresh_token_ttl_ms'];
    if (listenerTtl is int) {
      return listenerTtl > 0
          ? Duration(milliseconds: listenerTtl)
          : Duration.zero;
    }
    final idleMs = realmSettings.limits.sessionIdleMs;
    if (idleMs > 0) {
      return Duration(milliseconds: idleMs * 4);
    }
    return const Duration(hours: 24);
  }

  bool _resolveHttpRotateRefreshTokens({
    required HttpRouteSettings? route,
    required ListenerSettings? listenerSettings,
  }) {
    final routeValue = route?.action.options['rotate_refresh_tokens'];
    if (routeValue is bool) {
      return routeValue;
    }
    final listenerValue =
        listenerSettings?.http?.options['auth_rotate_refresh_tokens'];
    if (listenerValue is bool) {
      return listenerValue;
    }
    return true;
  }

  String _randomHttpAuthToken([int bytes = 32]) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(values);
  }

  String? _resolveAuthProviderFromDetails(Map<String, Object?> details) {
    final provider =
        details['authprovider'] ??
        details['provider'] ??
        details['auth_provider'];
    if (provider is! String) {
      return null;
    }
    final trimmed = provider.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, Object?> _httpAuthSuccessPayload(_HttpAuthIssueResult issue) {
    final record = issue.accessToken;
    return <String, Object?>{
      'status': 'ok',
      'token_type': 'Bearer',
      'access_token': record.token,
      'realm': record.realmUri,
      'authid': record.authId,
      'authrole': record.authRole,
      'authmethod': record.authMethod,
      if (record.authProvider != null) 'authprovider': record.authProvider,
      'expires_in': record.expiresIn.inSeconds,
      if (issue.refreshToken != null)
        'refresh_token': issue.refreshToken!.token,
      if (issue.refreshToken != null)
        'refresh_token_expires_in': issue.refreshToken!.expiresIn.inSeconds,
      if (record.details.isNotEmpty) 'details': record.details,
    };
  }

  void _cleanupExpiredHttpAuthState() {
    if (_pendingHttpAuthTransactions.isEmpty &&
        _httpAuthTokens.isEmpty &&
        _httpRefreshTokens.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();
    final expiredPending = _pendingHttpAuthTransactions.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final state in expiredPending) {
      final pending = _pendingHttpAuthTransactions.remove(state);
      if (pending != null) {
        unawaited(pending.abort(reason: 'http_auth_timeout'));
      }
    }
    final expiredTokens = _httpAuthTokens.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final token in expiredTokens) {
      unawaited(_revokeHttpAccessToken(token));
    }
    final expiredRefreshTokens = _httpRefreshTokens.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final token in expiredRefreshTokens) {
      unawaited(_revokeHttpRefreshToken(token));
    }
  }

  Future<void> _revokeHttpAccessToken(
    String token, {
    bool removeFromRefreshToken = true,
  }) async {
    final record = _httpAuthTokens.remove(token);
    if (record == null) {
      return;
    }
    if (removeFromRefreshToken) {
      final refreshToken = record.refreshToken;
      if (refreshToken != null) {
        _httpRefreshTokens[refreshToken]?.accessTokens.remove(token);
      }
    }
    final cacheKeys = _internalSessionsByCacheKey.keys
        .where(
          (key) =>
              key == record.cacheKeyPrefix ||
              key.startsWith('${record.cacheKeyPrefix}:'),
        )
        .toList(growable: false);
    for (final cacheKey in cacheKeys) {
      final session = _internalSessionsByCacheKey[cacheKey];
      if (session != null) {
        await session.close();
      }
    }
  }

  Future<void> _revokeHttpRefreshToken(String token) async {
    final record = _httpRefreshTokens.remove(token);
    if (record == null) {
      return;
    }
    final linkedAccessTokens = record.accessTokens.toList(growable: false);
    for (final accessToken in linkedAccessTokens) {
      await _revokeHttpAccessToken(accessToken, removeFromRefreshToken: false);
    }
    record.accessTokens.clear();
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

  NativeHttpResponseStreamDescriptor? _openDirectResponseStream(
    _PendingHttpCall pending, {
    required int status,
    required Map<String, String> headers,
  }) {
    final existing = pending.directResponseStream;
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
      final descriptor = runtime.openHttpResponseStreamDescriptor(
        handshakeHandle: handshake.handle,
        status: status,
        headers: headers,
      );
      pending.directResponseStream = descriptor;
      return descriptor;
    } on UnsupportedError catch (error, stackTrace) {
      onEvent?.call({
        'source': 'binding',
        'type': 'http_response_stream_open_unsupported',
        'httpRequestId': pending.id,
        'listenerId': pending.request.listenerId,
        'connectionId': pending.request.connectionId,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      return null;
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
    final directStream = pending?.directResponseStream;
    if (directStream != null &&
        pending?.directResponseStreamCompleted != true) {
      try {
        NativeHttpResponseStream.borrowed(
          handle: directStream.handle,
          libraryPath: directStream.libraryPath,
        ).close();
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
          sessionProfile: internal.sessionProfile,
          cacheKey: internal.sessionProfile?.trim().isNotEmpty == true
              ? internal.sessionProfile!.trim()
              : internal.name,
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
    this.handshake,
  });

  final int id;
  final RouterHttpRequest request;
  final HttpRequestSnapshot snapshot;
  final RouterSession session;
  late StreamSubscription<result_msg.Result> subscription;
  NativeHttpHandshake? handshake;
  NativeHttpResponseStream? responseStream;
  NativeHttpResponseStreamDescriptor? directResponseStream;
  bool directResponseStreamCompleted = false;
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
  registered_msg.Registered? _healthRegistration;

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

    _healthRegistration = await session.register('connectanum.metrics.healthz');
    _healthRegistration!.onInvoke(
      (invocation) => unawaited(_handleHealthInvocation(invocation)),
    );
  }

  Future<void> dispose() async {
    if (_snapshotRegistration != null) {
      await session.unregister(_snapshotRegistration!.registrationId);
    }
    if (_openMetricsRegistration != null) {
      await session.unregister(_openMetricsRegistration!.registrationId);
    }
    if (_healthRegistration != null) {
      await session.unregister(_healthRegistration!.registrationId);
    }
    _snapshotRegistration = null;
    _openMetricsRegistration = null;
    _healthRegistration = null;
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
    final httpContext = HttpInvocationContext.maybeFromInvocation(invocation);
    try {
      if (httpContext != null && !_authorizeOpenMetricsHttp(httpContext)) {
        httpContext.sendText(
          body: '',
          status: HttpStatus.unauthorized,
          headers: const {
            'www-authenticate': 'Bearer',
            'cache-control': 'no-store',
          },
        );
        return;
      }

      final text = await buildOpenMetricsPayload();
      if (httpContext != null) {
        httpContext.sendText(
          body: _httpTextBody(httpContext, text),
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
      if (httpContext != null) {
        httpContext.sendText(
          body: '',
          status: HttpStatus.serviceUnavailable,
          headers: const {'cache-control': 'no-store'},
        );
        return;
      }
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.runtimeError,
        arguments: ['Failed to generate OpenMetrics payload'],
        argumentsKeywords: {'reason': error.toString()},
      );
    }
  }

  Future<void> _handleHealthInvocation(
    invocation_msg.Invocation invocation,
  ) async {
    final httpContext = HttpInvocationContext.maybeFromInvocation(invocation);
    final status = binding.isDraining || !binding.isReady
        ? HttpStatus.serviceUnavailable
        : HttpStatus.ok;
    final body = binding.isDraining
        ? 'draining'
        : (!binding.isReady ? 'starting' : 'ok');

    if (httpContext != null) {
      httpContext.sendText(
        body: _httpTextBody(httpContext, body),
        status: status,
        headers: const {
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'no-store',
        },
      );
      return;
    }

    invocation.respondWith(
      arguments: [body],
      argumentsKeywords: {'status': status},
    );
  }

  bool _authorizeOpenMetricsHttp(HttpInvocationContext httpContext) {
    final expectedToken = metricsSettings.authToken;
    if (expectedToken == null || expectedToken.isEmpty) {
      return true;
    }
    final authorization = _headerValue(
      httpContext.request.headers,
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null) {
      return false;
    }
    final parts = authorization.trim().split(RegExp(r'\s+'));
    return parts.length == 2 &&
        parts.first.toLowerCase() == 'bearer' &&
        parts.last == expectedToken;
  }

  String _httpTextBody(HttpInvocationContext httpContext, String body) {
    return httpContext.request.method.trim().toUpperCase() == 'HEAD'
        ? ''
        : body;
  }

  String? _headerValue(Map<String, String> headers, String name) {
    final lowerName = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerName) {
        return entry.value;
      }
    }
    return null;
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
        'collection_timeout_ms':
            metricsSettings.collectionTimeout.inMilliseconds,
        'auth_required': metricsSettings.authToken?.isNotEmpty == true,
      },
      if (transportAlerts != null)
        'alerts': _buildTransportAlertsPayload(transportAlerts),
    };
  }

  Map<String, Object?> _buildTransportAlertsPayload(
    RouterTransportMetrics transportAlerts,
  ) {
    final byListener = transportAlerts.alertBreakdown
        .map(_transportAlertEntryToJson)
        .toList(growable: false);
    return <String, Object?>{
      'backpressure': transportAlerts.backpressureAlerts,
      'transport': transportAlerts.transportAlerts,
      'goaway': transportAlerts.goAwayAlerts,
      'idle_timeout': transportAlerts.idleTimeoutAlerts,
      'body_timeout': transportAlerts.bodyTimeoutAlerts,
      'protocol_error': transportAlerts.protocolErrorAlerts,
      'internal_error': transportAlerts.internalErrorAlerts,
      'active_throttles': transportAlerts.activeThrottleCount,
      if (transportAlerts.activeThrottles.isNotEmpty)
        'active_throttle_listeners': transportAlerts.activeThrottles
            .map(_transportAlertEntryToJson)
            .toList(growable: false),
      'by_listener': byListener,
    };
  }

  Map<String, Object?> _transportAlertEntryToJson(
    RouterTransportAlertBreakdown entry,
  ) => <String, Object?>{
    'listener_id': entry.listenerId,
    'protocol': entry.protocol,
    'endpoint': entry.endpoint,
    'backpressure': entry.backpressureAlerts,
    'transport': entry.transportAlerts,
    'goaway': entry.goAwayAlerts,
    'idle_timeout': entry.idleTimeoutAlerts,
    'body_timeout': entry.bodyTimeoutAlerts,
    'protocol_error': entry.protocolErrorAlerts,
    'internal_error': entry.internalErrorAlerts,
    'throttle_active': entry.throttleActive,
    if (entry.throttleRemainingMs != null)
      'throttle_remaining_ms': entry.throttleRemainingMs,
    if (entry.throttleUntil != null)
      'throttle_until': entry.throttleUntil!.toIso8601String(),
    if (entry.lastAlertAt != null)
      'last_alert_at': entry.lastAlertAt!.toIso8601String(),
    if (entry.lastAlertCategory != null)
      'last_alert_category': entry.lastAlertCategory,
    if (entry.lastAlertReason != null)
      'last_alert_reason': entry.lastAlertReason,
    if (entry.lastNewEvents != null) 'last_new_events': entry.lastNewEvents,
    if (entry.lastTotalEvents != null)
      'last_total_events': entry.lastTotalEvents,
  };

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

  Future<String> buildOpenMetricsPayload({RouterMetricsSnapshot? snapshot}) {
    return _buildOpenMetricsPayload(
      snapshot: snapshot,
    ).timeout(metricsSettings.collectionTimeout);
  }

  Future<String> _buildOpenMetricsPayload({
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

    final process = routerSnapshot.process;
    if (process != null) {
      buffer
        ..writeln(
          '# HELP connectanum_router_process_info Static information about the router VM process',
        )
        ..writeln('# TYPE connectanum_router_process_info gauge')
        ..writeln(
          'connectanum_router_process_info{pid="${process.processId}"} 1',
        )
        ..writeln(
          '# HELP connectanum_router_process_resident_memory_bytes Current resident set size of the router VM process',
        )
        ..writeln(
          '# TYPE connectanum_router_process_resident_memory_bytes gauge',
        )
        ..writeln(
          'connectanum_router_process_resident_memory_bytes ${process.currentRssBytes}',
        )
        ..writeln(
          '# HELP connectanum_router_process_max_resident_memory_bytes Maximum resident set size observed for the router VM process',
        )
        ..writeln(
          '# TYPE connectanum_router_process_max_resident_memory_bytes gauge',
        )
        ..writeln(
          'connectanum_router_process_max_resident_memory_bytes ${process.maxRssBytes}',
        );
    }

    final shutdown = routerSnapshot.shutdown;
    buffer
      ..writeln(
        '# HELP connectanum_router_drain_in_progress 1 while the router is draining and refusing new accepts',
      )
      ..writeln('# TYPE connectanum_router_drain_in_progress gauge')
      ..writeln(
        'connectanum_router_drain_in_progress ${shutdown.drainInProgress ? 1 : 0}',
      )
      ..writeln(
        '# HELP connectanum_router_drain_total Count of drain attempts started',
      )
      ..writeln('# TYPE connectanum_router_drain_total counter')
      ..writeln('connectanum_router_drain_total ${shutdown.drainTotal}')
      ..writeln(
        '# HELP connectanum_router_drain_timeouts_total Count of drains that exceeded their timeout budget',
      )
      ..writeln('# TYPE connectanum_router_drain_timeouts_total counter')
      ..writeln(
        'connectanum_router_drain_timeouts_total ${shutdown.drainTimeouts}',
      )
      ..writeln(
        '# HELP connectanum_router_listeners_closed_total Count of native listeners closed to stop accepting new connections',
      )
      ..writeln('# TYPE connectanum_router_listeners_closed_total counter')
      ..writeln(
        'connectanum_router_listeners_closed_total ${shutdown.closedListenersTotal}',
      )
      ..writeln(
        '# HELP connectanum_router_pending_connections_closed_total Count of accepted-but-unassigned connections closed during drain',
      )
      ..writeln(
        '# TYPE connectanum_router_pending_connections_closed_total counter',
      )
      ..writeln(
        'connectanum_router_pending_connections_closed_total ${shutdown.closedPendingConnectionsTotal}',
      );
    if (shutdown.lastDrainDurationMs != null) {
      buffer
        ..writeln(
          '# HELP connectanum_router_last_drain_duration_ms Duration of the most recent drain attempt in milliseconds',
        )
        ..writeln('# TYPE connectanum_router_last_drain_duration_ms gauge')
        ..writeln(
          'connectanum_router_last_drain_duration_ms ${shutdown.lastDrainDurationMs}',
        );
    }

    final alerts = routerSnapshot.alerts;
    buffer
      ..writeln(
        '# HELP connectanum_router_backpressure_alerts_total Listener backpressure alerts observed by the boss loop',
      )
      ..writeln('# TYPE connectanum_router_backpressure_alerts_total counter')
      ..writeln(
        'connectanum_router_backpressure_alerts_total ${alerts.backpressureAlerts}',
      )
      ..writeln(
        '# HELP connectanum_router_backpressure_alerts_throttled_total Backpressure alerts that triggered listener throttling',
      )
      ..writeln(
        '# TYPE connectanum_router_backpressure_alerts_throttled_total counter',
      )
      ..writeln(
        'connectanum_router_backpressure_alerts_throttled_total ${alerts.throttledBackpressureAlerts}',
      );
    if (alerts.backpressureAlertReasons.isNotEmpty) {
      buffer
        ..writeln(
          '# HELP connectanum_router_backpressure_alerts_by_reason_total Backpressure alerts grouped by reason',
        )
        ..writeln(
          '# TYPE connectanum_router_backpressure_alerts_by_reason_total counter',
        );
      alerts.backpressureAlertReasons.forEach((reason, count) {
        buffer.writeln(
          'connectanum_router_backpressure_alerts_by_reason_total${_formatLabels({'reason': reason})} $count',
        );
      });
    }

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

      buffer
        ..writeln(
          '# HELP connectanum_router_throttled_listeners Listeners currently throttled by the boss alert loop',
        )
        ..writeln('# TYPE connectanum_router_throttled_listeners gauge')
        ..writeln(
          'connectanum_router_throttled_listeners ${transport.activeThrottleCount}',
        );

      if (transport.alertBreakdown.isNotEmpty) {
        buffer
          ..writeln(
            '# HELP connectanum_router_listener_throttle_active Whether a listener/protocol is currently throttled',
          )
          ..writeln('# TYPE connectanum_router_listener_throttle_active gauge');
        for (final entry in transport.alertBreakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_listener_throttle_active$labels ${entry.throttleActive ? 1 : 0}',
          );
        }

        buffer
          ..writeln(
            '# HELP connectanum_router_listener_throttle_remaining_ms Remaining throttle window in milliseconds for a listener/protocol',
          )
          ..writeln(
            '# TYPE connectanum_router_listener_throttle_remaining_ms gauge',
          );
        for (final entry in transport.alertBreakdown) {
          final labels = _formatLabels({
            'listener_id': entry.listenerId.toString(),
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
          });
          buffer.writeln(
            'connectanum_router_listener_throttle_remaining_ms$labels ${entry.throttleRemainingMs ?? 0}',
          );
        }
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

class _PendingHttpAuthTransaction {
  const _PendingHttpAuthTransaction({
    required this.state,
    required this.realmUri,
    required this.authMethod,
    required this.authId,
    required this.authenticator,
    required this.context,
    required this.sessionProfileName,
    required this.expiresAt,
  });

  final String state;
  final String realmUri;
  final String authMethod;
  final String? authId;
  final Authenticator authenticator;
  final AuthenticatorContext context;
  final String? sessionProfileName;
  final DateTime expiresAt;

  _PendingHttpAuthTransaction copyWith({String? state, DateTime? expiresAt}) {
    return _PendingHttpAuthTransaction(
      state: state ?? this.state,
      realmUri: realmUri,
      authMethod: authMethod,
      authId: authId,
      authenticator: authenticator,
      context: context,
      sessionProfileName: sessionProfileName,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Future<void> abort({String? reason}) =>
      authenticator.onAbort(context, reason: reason);
}

class _HttpAuthIssueResult {
  const _HttpAuthIssueResult({required this.accessToken, this.refreshToken});

  final _HttpAuthTokenRecord accessToken;
  final _HttpRefreshTokenRecord? refreshToken;
}

class _HttpAuthTokenRecord {
  const _HttpAuthTokenRecord({
    required this.token,
    required this.realmUri,
    required this.authMethod,
    required this.authProvider,
    required this.authId,
    required this.authRole,
    required this.details,
    required this.sessionProfileName,
    required this.expiresAt,
    required this.refreshToken,
  });

  final String token;
  final String realmUri;
  final String authMethod;
  final String? authProvider;
  final String authId;
  final String authRole;
  final Map<String, Object?> details;
  final String? sessionProfileName;
  final DateTime expiresAt;
  final String? refreshToken;

  String get cacheKeyPrefix => 'http-auth-token:$token';

  Duration get expiresIn {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }
}

class _HttpRefreshTokenRecord {
  _HttpRefreshTokenRecord({
    required this.token,
    required this.realmUri,
    required this.authMethod,
    required this.authProvider,
    required this.authId,
    required this.authRole,
    required this.details,
    required this.sessionProfileName,
    required this.expiresAt,
    Set<String>? accessTokens,
  }) : accessTokens = accessTokens ?? <String>{};

  final String token;
  final String realmUri;
  final String authMethod;
  final String? authProvider;
  final String authId;
  final String authRole;
  final Map<String, Object?> details;
  final String? sessionProfileName;
  final DateTime expiresAt;
  final Set<String> accessTokens;

  Duration get expiresIn {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }
}

class _HttpRouteMatchResult {
  const _HttpRouteMatchResult._({
    this.route,
    this.errorRoute,
    this.allowedMethods = const [],
    this.allowedProtocols = const [],
  });

  const _HttpRouteMatchResult.route(HttpRouteSettings route)
    : this._(route: route);

  const _HttpRouteMatchResult.methodNotAllowed(
    List<String> allowedMethods, {
    HttpRouteSettings? route,
  }) : this._(errorRoute: route, allowedMethods: allowedMethods);

  const _HttpRouteMatchResult.protocolNotAllowed(
    List<String> allowedProtocols, {
    HttpRouteSettings? route,
  }) : this._(errorRoute: route, allowedProtocols: allowedProtocols);

  const _HttpRouteMatchResult.notFound() : this._();

  final HttpRouteSettings? route;
  final HttpRouteSettings? errorRoute;
  final List<String> allowedMethods;
  final List<String> allowedProtocols;

  bool get isMethodNotAllowed => route == null && allowedMethods.isNotEmpty;
  bool get isProtocolNotAllowed =>
      route == null && allowedMethods.isEmpty && allowedProtocols.isNotEmpty;
  bool get isNotFound =>
      route == null && allowedMethods.isEmpty && allowedProtocols.isEmpty;
}

String _normaliseHttpRouteProtocol(String protocol) {
  final cleaned = protocol.trim().toLowerCase();
  return switch (cleaned) {
    'http' || 'http1' || 'http/1' || 'http/1.0' || 'http/1.1' => 'http',
    'h2' || 'http2' || 'http/2' => 'http2',
    'h3' || 'http3' || 'http/3' => 'http3',
    _ => cleaned,
  };
}

class _HttpRouteTransportAuthFailure {
  const _HttpRouteTransportAuthFailure._({
    required this.status,
    required this.reason,
    required this.message,
    required this.bearerChallenge,
  });

  const _HttpRouteTransportAuthFailure.unauthorized({
    required String reason,
    required String message,
  }) : this._(
         status: HttpStatus.unauthorized,
         reason: reason,
         message: message,
         bearerChallenge: true,
       );

  const _HttpRouteTransportAuthFailure.forbidden({
    required String reason,
    required String message,
  }) : this._(
         status: HttpStatus.forbidden,
         reason: reason,
         message: message,
         bearerChallenge: false,
       );

  final int status;
  final String reason;
  final String message;
  final bool bearerChallenge;
}

class _HttpRouteRateLimitState {
  _HttpRouteRateLimitState({required this.windowStart, required this.count});

  DateTime windowStart;
  int count;
}

class _HttpRouteRateLimitDecision {
  _HttpRouteRateLimitDecision({
    required this.key,
    required this.limit,
    required this.windowMs,
    required this.retryAfterMs,
    required this.resetAt,
  });

  final String key;
  final int limit;
  final int windowMs;
  final int retryAfterMs;
  final DateTime resetAt;

  Map<String, String> get headers => <String, String>{
    HttpHeaders.retryAfterHeader: retryAfterSeconds.toString(),
    'x-ratelimit-limit': limit.toString(),
    'x-ratelimit-remaining': '0',
    'x-ratelimit-reset': resetEpochSeconds.toString(),
  };

  int get retryAfterSeconds {
    final seconds = (retryAfterMs / 1000).ceil();
    return seconds <= 0 ? 1 : seconds;
  }

  int get resetEpochSeconds => resetAt.millisecondsSinceEpoch ~/ 1000;
}

class _HttpUnauthorized implements Exception {
  const _HttpUnauthorized({required this.reason, this.message});

  final String reason;
  final String? message;
}

class _ConfiguredHttpAuthProvider {
  const _ConfiguredHttpAuthProvider({
    required this.name,
    required this.provider,
  });

  final String name;
  final HttpAuthProvider provider;
}
