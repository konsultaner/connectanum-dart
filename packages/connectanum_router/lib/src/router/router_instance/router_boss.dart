part of '../router_instance.dart';

@visibleForTesting
Duration routerBossLoopDelay({
  required bool didWork,
  required Duration pollInterval,
}) => didWork ? Duration.zero : pollInterval;

const int _http3RequestDrainBudgetPerConnection = 1;

@visibleForTesting
final class RouterBossLoopPacer {
  Completer<void>? _wakeCompleter;
  bool _wakeRequested = false;

  void requestWake() {
    _wakeRequested = true;
    final wakeCompleter = _wakeCompleter;
    if (wakeCompleter != null && !wakeCompleter.isCompleted) {
      wakeCompleter.complete();
    }
  }

  Future<void> waitForNextTick({
    required bool didWork,
    required Duration pollInterval,
  }) async {
    final delay = routerBossLoopDelay(
      didWork: didWork || _consumeWakeRequest(),
      pollInterval: pollInterval,
    );
    if (delay == Duration.zero) {
      await Future<void>.delayed(Duration.zero);
      return;
    }

    final wakeCompleter = Completer<void>();
    _wakeCompleter = wakeCompleter;
    if (_consumeWakeRequest()) {
      if (identical(_wakeCompleter, wakeCompleter)) {
        _wakeCompleter = null;
      }
      await Future<void>.delayed(Duration.zero);
      return;
    }

    try {
      await Future.any<void>(<Future<void>>[
        Future<void>.delayed(delay),
        wakeCompleter.future,
      ]);
    } finally {
      if (identical(_wakeCompleter, wakeCompleter)) {
        _wakeCompleter = null;
      }
    }
  }

  bool _consumeWakeRequest() {
    final wakeRequested = _wakeRequested;
    _wakeRequested = false;
    return wakeRequested;
  }
}

/// Coordinates worker isolates and round-robins connections across them.
class _RouterBoss {
  _RouterBoss({
    required this.runtime,
    required this.listeners,
    required this.pollInterval,
    required this.entryPoint,
    required this.libraryPathHint,
    required this.settings,
    this.onEvent,
    this.onHttpRequest,
  }) : _eventPort = ReceivePort(),
       _commandPort = ReceivePort(),
       _stateStore = RouterStateStore(settings: settings) {
    _realmByName = {for (final realm in settings.realms) realm.name: realm};
    for (final listener in listeners) {
      _listenerById[listener.listenerId] = listener;
    }
    _emitProtocolAnnouncements();
    _eventSubscription = _eventPort.listen(_handleEvent);
    _commandPort.listen(_handleCommand);
    _stateStore.events.listen(_handleStateEvent);
    _stateStore.start();
  }

  final NativeRuntimeWithHandles runtime;
  final List<RouterListener> listeners;
  final Duration pollInterval;
  final RouterWorkerEntryPoint entryPoint;
  final String? libraryPathHint;
  final RouterSettings settings;
  final void Function(Object event)? onEvent;
  final Future<void> Function(
    RouterHttpRequest request,
    NativeHttpHandshake? handshake,
  )?
  onHttpRequest;

  final ReceivePort _eventPort;
  final ReceivePort _commandPort;
  late final StreamSubscription<dynamic> _eventSubscription;
  final Map<int, RouterListener> _listenerById = {};
  final List<_WorkerHandle> _workers = [];
  final Map<int, _WorkerHandle> _connectionOwners = {};
  final Map<int, Isolate> _pendingIsolates = {};
  final Map<int, RouterListener> _httpConnectionListeners = {};
  final Map<int, NativeHttp3Connection> _http3Connections = {};
  final Map<int, RouterListener> _http2ConnectionListeners = {};
  final Map<int, RouterListener> _http3ConnectionListeners = {};
  final Map<int, _WebSocketSelection> _webSocketSelectionByConnection = {};
  final RouterStateStore _stateStore;
  late final Map<String, RealmSettings> _realmByName;
  final Map<int, DateTime> _lastActivityByConnection = {};
  final Map<int, String> _realmByConnection = {};
  DateTime _lastIdleSweep = DateTime.fromMillisecondsSinceEpoch(0);
  NativeRouterMetrics? _lastRouterMetrics;
  final Map<String, RouterTransportMetricsBreakdown> _lastBreakdownByKey = {};
  final Map<String, _ListenerAlertCounts> _alertCountsByKey = {};
  final Map<String, _ListenerAlertSnapshot> _alertSnapshotByKey = {};
  final Map<int, DateTime> _lastAlertAtByListener = {};
  int _totalBackpressureAlerts = 0;
  int _totalGoAwayAlerts = 0;
  int _totalIdleTimeoutAlerts = 0;
  int _totalBodyTimeoutAlerts = 0;
  int _totalProtocolErrorAlerts = 0;
  int _totalInternalErrorAlerts = 0;
  final Map<int, DateTime> _listenerThrottleUntil = {};
  int _throttledBackpressureAlerts = 0;
  final Map<String, int> _backpressureAlertsByReason = {};
  final RouterBossLoopPacer _loopPacer = RouterBossLoopPacer();
  bool _running = false;
  bool _stopping = false;
  Future<void>? _loopFuture;
  int _nextWorkerIndex = 0;
  int _nextWorkerId = 1;
  int _nextPendingWorkerToken = -1;

  SendPort get stateCommandPort => _stateStore.commandPort;
  SendPort get bossCommandPort => _commandPort.sendPort;

  void _emitProtocolAnnouncements() {
    for (final listener in listeners) {
      final settings = listener.settings;
      if (settings == null) {
        continue;
      }
      final unsupported = settings.protocols
          .where((protocol) => protocol != ListenerProtocol.rawsocket)
          .map(listenerProtocolToString)
          .toList(growable: false);
      if (unsupported.isEmpty) {
        continue;
      }
      onEvent?.call({
        'source': 'boss',
        'type': 'listener_protocol_pending',
        'listenerId': listener.listenerId,
        'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
        'protocols': unsupported,
      });
    }
  }

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _loopFuture = _loop();
  }

  Future<void> stop({
    Duration drainTimeout = const Duration(seconds: 15),
  }) async {
    if (_stopping) {
      return;
    }
    _stopping = true;

    final drainFutures = <Future<void>>[];
    for (final worker in _workers) {
      worker.drainCompleter ??= Completer<void>();
      drainFutures.add(worker.drainCompleter!.future);
      worker.commandPort.send(<Object?>[
        _workerCmdDrainConnections,
        'wamp.close.system_shutdown',
      ]);
    }

    _running = false;
    _loopPacer.requestWake();
    final loop = _loopFuture;
    if (drainFutures.isNotEmpty) {
      try {
        await Future.wait(drainFutures).timeout(drainTimeout);
      } on TimeoutException {
        // Kill any workers that failed to drain in time.
        for (final worker in _workers.toList()) {
          _shutdownWorker(worker, terminateIsolate: true);
        }
        _workers.clear();
        onEvent?.call({
          'source': 'boss',
          'type': 'worker_drain_timeout',
          'timeout_ms': drainTimeout.inMilliseconds,
        });
      }
    }
    if (loop != null) {
      await loop;
    }
    await _eventSubscription.cancel();
    _eventPort.close();
    _commandPort.close();
    _stateStore.dispose();
    for (final worker in _workers.toList()) {
      _shutdownWorker(worker, terminateIsolate: true);
    }
    for (final isolate in _pendingIsolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _pendingIsolates.clear();
    _connectionOwners.clear();
    _httpConnectionListeners.clear();
    _http2ConnectionListeners.clear();
    if (_http3Connections.isNotEmpty) {
      final connections = _http3Connections.values.toList(growable: false);
      _http3Connections.clear();
      for (final connection in connections) {
        connection.release();
      }
    }
  }

  Future<void> _loop() async {
    while (_running) {
      var didWork = false;
      didWork = await _ensureMinimumWorkers() || didWork;
      for (final listener in listeners) {
        didWork = await _acceptConnections(listener) || didWork;
      }
      didWork = _dispatchMessages() || didWork;
      didWork = _expireIdleConnections() || didWork;
      didWork = _drainHttpRequests() || didWork;
      didWork = _drainHttp2Requests() || didWork;
      didWork = _drainHttp3Requests() || didWork;
      didWork = _drainHttpConnectionEvents() || didWork;
      didWork = _emitRouterMetrics() || didWork;
      await _loopPacer.waitForNextTick(
        didWork: didWork,
        pollInterval: pollInterval,
      );
    }
  }

  Future<bool> _ensureMinimumWorkers() async {
    if (listeners.isEmpty) {
      return false;
    }
    final minWorkers = settings.workerPool.minWorkers;
    if (minWorkers <= 0) {
      return false;
    }
    var didWork = false;
    while ((_workers.length + _pendingIsolates.length) < minWorkers) {
      await _spawnWorker(listeners.first, _allocatePendingWorkerToken());
      didWork = true;
    }
    return didWork;
  }

  Future<bool> _acceptConnections(RouterListener listener) async {
    final throttleUntil = _listenerThrottleUntil[listener.listenerId];
    if (throttleUntil != null && throttleUntil.isAfter(DateTime.now())) {
      return false;
    }
    var didWork = false;
    while (_running) {
      int connectionId;
      NativeConnectionProtocol protocol;
      try {
        connectionId = runtime.pollConnection(listener.listenerId);
      } on NativeTransportException catch (error) {
        onEvent?.call({
          'source': 'boss',
          'type': 'boss_error',
          'listenerId': listener.listenerId,
          'error': error.toString(),
        });
        break;
      }
      if (connectionId == 0) {
        break;
      }
      didWork = true;
      _lastActivityByConnection[connectionId] = DateTime.now();
      try {
        protocol = runtime.connectionProtocol(connectionId);
      } on NativeTransportException catch (error) {
        onEvent?.call({
          'source': 'boss',
          'type': 'boss_error',
          'listenerId': listener.listenerId,
          'connectionId': connectionId,
          'error': error.toString(),
        });
        protocol = NativeConnectionProtocol.rawsocket;
      }

      if (protocol != NativeConnectionProtocol.rawsocket) {
        if (protocol == NativeConnectionProtocol.http ||
            protocol == NativeConnectionProtocol.http2) {
          if (protocol == NativeConnectionProtocol.http) {
            _registerHttpConnection(listener, connectionId);
          }
          if (protocol == NativeConnectionProtocol.http2) {
            _registerHttp2Connection(listener, connectionId);
          }
          final handshake = runtime.takeHttpHandshake(connectionId);
          if (handshake != null) {
            _processHttpHandshake(listener, connectionId, protocol, handshake);
          } else {
            onEvent?.call({
              'source': 'boss',
              'type': 'listener_http_request_missing',
              'listenerId': listener.listenerId,
              'connectionId': connectionId,
            });
          }
        } else if (protocol == NativeConnectionProtocol.websocket) {
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
            _webSocketSelectionByConnection[connectionId] = selection;
            onEvent?.call({
              'source': 'boss',
              'type': 'listener_websocket_accepted',
              'listenerId': listener.listenerId,
              'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
              'connectionId': connectionId,
              'protocol': selection.protocol,
              'serializer': _serializerName(selection.serializer),
            });
          } on NativeTransportException catch (error) {
            handshake.release();
            onEvent?.call({
              'source': 'boss',
              'type': 'listener_websocket_accept_error',
              'listenerId': listener.listenerId,
              'connectionId': connectionId,
              'error': error.toString(),
            });
            continue;
          }
          await _assignConnection(
            listener,
            connectionId,
            metadata: {
              'protocol': _protocolName(protocol),
              'websocketProtocol': selection.protocol,
              'websocketSerializer': _serializerName(selection.serializer),
            },
          );
          continue;
        } else if (protocol == NativeConnectionProtocol.http3) {
          final handshake = runtime.takeHttp3Handshake(connectionId);
          final details = <String, Object?>{
            'protocol': handshake?.protocol ?? 'http/3',
          };
          if (listener.http3Port > 0) {
            details['http3Port'] = listener.http3Port;
          }
          final connectionHandle = runtime.takeHttp3Connection(connectionId);
          if (connectionHandle != null) {
            _replaceHttp3Connection(connectionId, connectionHandle);
          }
          _http3ConnectionListeners[connectionId] = listener;
          if (handshake != null) {
            final alpn = handshake.alpn;
            if (alpn != null && alpn.isNotEmpty) {
              details['alpn'] = alpn;
            }
            if (handshake.listenerProtocols.isNotEmpty) {
              details['listenerProtocols'] = handshake.listenerProtocols;
            }
            handshake.release();
          }
          onEvent?.call({
            'source': 'binding',
            'type': 'listener_protocol_pending',
            'listenerId': listener.listenerId,
            'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
            'connectionId': connectionId,
            'protocol': _protocolName(protocol),
            'details': details,
          });
        } else {
          onEvent?.call({
            'source': 'binding',
            'type': 'listener_protocol_pending',
            'listenerId': listener.listenerId,
            'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
            'connectionId': connectionId,
            'protocol': _protocolName(protocol),
          });
        }
        continue;
      }
      await _assignConnection(listener, connectionId);
    }
    return didWork;
  }

  Future<void> _assignConnection(
    RouterListener listener,
    int connectionId, {
    Map<String, Object?> metadata = const {},
  }) async {
    final minWorkers = settings.workerPool.minWorkers;
    if (_workers.length < minWorkers) {
      await _spawnWorker(listener, connectionId, metadata: metadata);
      return;
    }

    final worker = _chooseWorker();
    if (worker == null) {
      await _spawnWorker(listener, connectionId, metadata: metadata);
      return;
    }
    worker.connections.add(connectionId);
    _connectionOwners[connectionId] = worker;
    worker.commandPort.send(<Object?>[
      _workerCmdAddConnection,
      listener.listenerId,
      connectionId,
      metadata,
    ]);
  }

  String _protocolName(NativeConnectionProtocol protocol) {
    switch (protocol) {
      case NativeConnectionProtocol.rawsocket:
        return 'rawsocket';
      case NativeConnectionProtocol.websocket:
        return 'websocket';
      case NativeConnectionProtocol.http:
        return 'http';
      case NativeConnectionProtocol.http2:
        return 'http2';
      case NativeConnectionProtocol.http3:
        return 'http3';
    }
  }

  void _handleHttpConnectionEvent(NativeHttpConnectionEvent event) {
    final data = <String, Object?>{
      'connectionId': event.connectionId,
      'protocol': _protocolName(event.protocol),
      'reason': _httpConnectionReason(event.reason),
      'requestCount': event.requestCount,
      'idleTimeouts': event.idleTimeouts,
      'bodyTimeouts': event.bodyTimeouts,
      'backpressureEvents': event.backpressureEvents,
      'maxBackpressureDepth': event.maxBackpressureDepth,
      'goAwayEvents': event.goAwayEvents,
      if (event.detail != null) 'detail': event.detail,
    };
    onEvent?.call({'source': 'boss', 'type': 'http_connection_event', ...data});
    if (event.protocol == NativeConnectionProtocol.http) {
      _httpConnectionListeners.remove(event.connectionId);
    } else if (event.protocol == NativeConnectionProtocol.http2) {
      _http2ConnectionListeners.remove(event.connectionId);
    } else if (event.protocol == NativeConnectionProtocol.http3) {
      _http3ConnectionListeners.remove(event.connectionId);
      _releaseHttp3Connection(event.connectionId);
    }
  }

  int get _backpressureDepthAlertThreshold =>
      settings.metrics?.backpressure.depthThreshold ?? 16;
  int get _backpressureEventsAlertThreshold =>
      settings.metrics?.backpressure.newEventsThreshold ?? 1;
  Duration get _backpressureThrottleWindow =>
      settings.metrics?.backpressure.cooldown ??
      const Duration(milliseconds: 250);
  int get _goAwayAlertThreshold =>
      settings.metrics?.transportAlerts.goAwayDeltaThreshold ?? 1;
  int get _idleTimeoutAlertThreshold =>
      settings.metrics?.transportAlerts.idleTimeoutDeltaThreshold ?? 1;
  int get _bodyTimeoutAlertThreshold =>
      settings.metrics?.transportAlerts.bodyTimeoutDeltaThreshold ?? 1;
  int get _protocolErrorAlertThreshold =>
      settings.metrics?.transportAlerts.protocolErrorDeltaThreshold ?? 1;
  int get _internalErrorAlertThreshold =>
      settings.metrics?.transportAlerts.internalErrorDeltaThreshold ?? 1;
  Duration get _transportAlertCooldown =>
      settings.metrics?.transportAlerts.cooldown ??
      const Duration(milliseconds: 500);
  bool get _throttleOnTransportAlert =>
      settings.metrics?.transportAlerts.throttleOnAlert ?? true;

  bool _emitRouterMetrics() {
    final nativeMetrics = runtime.pollRouterMetrics();
    if (nativeMetrics == null) {
      final hadMetrics =
          _lastRouterMetrics != null ||
          _lastBreakdownByKey.isNotEmpty ||
          _alertCountsByKey.isNotEmpty ||
          _alertSnapshotByKey.isNotEmpty ||
          _lastAlertAtByListener.isNotEmpty ||
          _listenerThrottleUntil.isNotEmpty ||
          _totalBackpressureAlerts != 0 ||
          _totalGoAwayAlerts != 0 ||
          _totalIdleTimeoutAlerts != 0 ||
          _totalBodyTimeoutAlerts != 0 ||
          _totalProtocolErrorAlerts != 0 ||
          _totalInternalErrorAlerts != 0 ||
          _throttledBackpressureAlerts != 0 ||
          _backpressureAlertsByReason.isNotEmpty;
      _lastRouterMetrics = null;
      _lastBreakdownByKey.clear();
      _alertCountsByKey.clear();
      _alertSnapshotByKey.clear();
      _totalBackpressureAlerts = 0;
      _totalGoAwayAlerts = 0;
      _totalIdleTimeoutAlerts = 0;
      _totalBodyTimeoutAlerts = 0;
      _totalProtocolErrorAlerts = 0;
      _totalInternalErrorAlerts = 0;
      _throttledBackpressureAlerts = 0;
      _backpressureAlertsByReason.clear();
      _lastAlertAtByListener.clear();
      _listenerThrottleUntil.clear();
      return hadMetrics;
    }
    final last = _lastRouterMetrics;
    if (last != null && last.sameValues(nativeMetrics)) {
      return false;
    }
    _lastRouterMetrics = nativeMetrics;
    final converted = _convertTransportMetrics(nativeMetrics);
    _emitBreakdownAlerts(converted.breakdown);
    final refreshed = _convertTransportMetrics(nativeMetrics);
    final breakdown = refreshed.breakdown
        .map(
          (entry) => {
            'listenerId': entry.listenerId,
            'protocol': entry.protocol,
            'endpoint': entry.endpoint,
            'totalEvents': entry.totalEvents,
            'gracefulEvents': entry.gracefulEvents,
            'goAwayEvents': entry.goAwayEvents,
            'idleTimeoutEvents': entry.idleTimeoutEvents,
            'bodyTimeoutEvents': entry.bodyTimeoutEvents,
            'protocolErrorEvents': entry.protocolErrorEvents,
            'internalErrorEvents': entry.internalErrorEvents,
            'backpressureEvents': entry.backpressureEvents,
            'maxBackpressureDepth': entry.maxBackpressureDepth,
          },
        )
        .toList(growable: false);
    onEvent?.call({
      'source': 'boss',
      'type': 'router_metrics',
      'http': {
        'totalEvents': refreshed.totalEvents,
        'gracefulEvents': refreshed.gracefulEvents,
        'goAwayEvents': refreshed.goAwayEvents,
        'idleTimeoutEvents': refreshed.idleTimeoutEvents,
        'bodyTimeoutEvents': refreshed.bodyTimeoutEvents,
        'protocolErrorEvents': refreshed.protocolErrorEvents,
        'internalErrorEvents': refreshed.internalErrorEvents,
        'backpressureEvents': refreshed.backpressureEvents,
        'maxBackpressureDepth': refreshed.maxBackpressureDepth,
        'breakdown': breakdown,
      },
    });
    return true;
  }

  void _emitBreakdownAlerts(List<RouterTransportMetricsBreakdown> breakdowns) {
    for (final entry in breakdowns) {
      final key = '${entry.listenerId}:${entry.protocol}';
      final last = _lastBreakdownByKey[key];
      _lastBreakdownByKey[key] = entry;
      if (last == null) {
        continue;
      }
      final newBackpressure =
          entry.backpressureEvents - last.backpressureEvents;
      final depthAlert =
          entry.maxBackpressureDepth >= _backpressureDepthAlertThreshold;
      final eventsAlert = newBackpressure >= _backpressureEventsAlertThreshold;
      final newGoAway = entry.goAwayEvents - last.goAwayEvents;
      final newIdleTimeout = entry.idleTimeoutEvents - last.idleTimeoutEvents;
      final newBodyTimeout = entry.bodyTimeoutEvents - last.bodyTimeoutEvents;
      final newProtocolErrors =
          entry.protocolErrorEvents - last.protocolErrorEvents;
      final newInternalErrors =
          entry.internalErrorEvents - last.internalErrorEvents;
      final alerts = <Map<String, Object?>>[];

      if (depthAlert || eventsAlert) {
        final reason = _backpressureAlertReason(
          depthAlert: depthAlert,
          eventsAlert: eventsAlert,
        );
        alerts.add({
          'type': 'listener_backpressure_alert',
          'reason': reason,
          'newEvents': newBackpressure,
          'totalEvents': entry.backpressureEvents,
          'throttle': depthAlert ? _backpressureThrottleWindow : Duration.zero,
        });
        _recordBackpressureAlert(entry.listenerId, entry.protocol);
        _backpressureAlertsByReason[reason] =
            (_backpressureAlertsByReason[reason] ?? 0) + 1;
        if (depthAlert) {
          _throttledBackpressureAlerts++;
        }
      }
      void addTransportAlert(String reason, int newEvents, int totalEvents) {
        alerts.add({
          'type': 'listener_transport_alert',
          'reason': reason,
          'newEvents': newEvents,
          'totalEvents': totalEvents,
          'throttle': _throttleOnTransportAlert
              ? _transportAlertCooldown
              : Duration.zero,
        });
        _recordTransportAlert(entry.listenerId, entry.protocol, reason);
      }

      if (newGoAway >= _goAwayAlertThreshold && newGoAway > 0) {
        addTransportAlert('go_away', newGoAway, entry.goAwayEvents);
      }
      if (newIdleTimeout >= _idleTimeoutAlertThreshold && newIdleTimeout > 0) {
        addTransportAlert(
          'idle_timeout',
          newIdleTimeout,
          entry.idleTimeoutEvents,
        );
      }
      if (newBodyTimeout >= _bodyTimeoutAlertThreshold && newBodyTimeout > 0) {
        addTransportAlert(
          'body_timeout',
          newBodyTimeout,
          entry.bodyTimeoutEvents,
        );
      }
      if (newProtocolErrors >= _protocolErrorAlertThreshold &&
          newProtocolErrors > 0) {
        addTransportAlert(
          'protocol_error',
          newProtocolErrors,
          entry.protocolErrorEvents,
        );
      }
      if (newInternalErrors >= _internalErrorAlertThreshold &&
          newInternalErrors > 0) {
        addTransportAlert(
          'internal_error',
          newInternalErrors,
          entry.internalErrorEvents,
        );
      }
      for (final alert in alerts) {
        final throttle = alert['throttle'] as Duration? ?? Duration.zero;
        final throttled = throttle > Duration.zero;
        final now = DateTime.now().toUtc();
        final throttleUntil = throttled ? now.add(throttle) : null;
        if (throttled) {
          final existing = _listenerThrottleUntil[entry.listenerId];
          final until = now.add(throttle);
          if (existing == null || until.isAfter(existing)) {
            _listenerThrottleUntil[entry.listenerId] = until;
          }
        }
        _recordAlertSnapshot(
          listenerId: entry.listenerId,
          protocol: entry.protocol,
          category: alert['type'] == 'listener_backpressure_alert'
              ? 'backpressure'
              : 'transport',
          reason: alert['reason'] as String?,
          newEvents: alert['newEvents'] as int? ?? 0,
          totalEvents: alert['totalEvents'] as int? ?? 0,
          at: now,
          throttleUntil: throttleUntil,
        );
        onEvent?.call({
          'source': 'boss',
          'type': alert['type'] as String,
          'listenerId': entry.listenerId,
          'protocol': entry.protocol,
          'endpoint': entry.endpoint,
          'maxBackpressureDepth': entry.maxBackpressureDepth,
          'backpressureEvents': entry.backpressureEvents,
          'goAwayEvents': entry.goAwayEvents,
          'idleTimeoutEvents': entry.idleTimeoutEvents,
          'bodyTimeoutEvents': entry.bodyTimeoutEvents,
          'protocolErrorEvents': entry.protocolErrorEvents,
          'internalErrorEvents': entry.internalErrorEvents,
          'newEvents': alert['newEvents'],
          'totalEvents': alert['totalEvents'],
          'throttled': throttled,
          if (alert['reason'] != null) 'reason': alert['reason'],
        });
      }
    }
  }

  String _backpressureAlertReason({
    required bool depthAlert,
    required bool eventsAlert,
  }) {
    if (depthAlert && eventsAlert) {
      return 'depth_and_new_events';
    }
    if (depthAlert) {
      return 'depth_threshold';
    }
    return 'new_events_threshold';
  }

  RouterAlertMetrics _buildAlertMetrics() => RouterAlertMetrics(
    backpressureAlerts: _totalBackpressureAlerts,
    throttledBackpressureAlerts: _throttledBackpressureAlerts,
    backpressureAlertReasons: Map<String, int>.unmodifiable(
      _backpressureAlertsByReason,
    ),
  );

  RouterTransportMetrics? _ensureTransportMetrics() {
    final last = _lastRouterMetrics;
    if (last != null) {
      return _convertTransportMetrics(last);
    }
    final nativeMetrics = runtime.pollRouterMetrics();
    if (nativeMetrics == null) {
      _lastRouterMetrics = null;
      return null;
    }
    _lastRouterMetrics = nativeMetrics;
    final converted = _convertTransportMetrics(nativeMetrics);
    _emitBreakdownAlerts(converted.breakdown);
    return _convertTransportMetrics(nativeMetrics);
  }

  RouterTransportMetrics _convertTransportMetrics(NativeRouterMetrics metrics) {
    final snapshotAt = DateTime.now().toUtc();
    final alertBreakdown = <RouterTransportAlertBreakdown>[];
    final totalTransportAlerts =
        _totalGoAwayAlerts +
        _totalIdleTimeoutAlerts +
        _totalBodyTimeoutAlerts +
        _totalProtocolErrorAlerts +
        _totalInternalErrorAlerts;

    final breakdown = metrics.breakdown
        .map((entry) {
          final listener = _listenerById[entry.listenerId];
          final endpoint = listener != null
              ? '${listener.endpoint.host}:${entry.protocol == NativeConnectionProtocol.http3 && listener.http3Port > 0 ? listener.http3Port : listener.port}'
              : 'listener:${entry.listenerId}';
          final key = '${entry.listenerId}:${_protocolName(entry.protocol)}';
          final alertCounts = _alertCountsByKey[key];
          final alertSnapshot = _alertSnapshotByKey[key];
          final throttleUntil =
              _listenerThrottleUntil[entry.listenerId] ??
              alertSnapshot?.throttleUntil;
          final throttleActive =
              throttleUntil != null && throttleUntil.isAfter(snapshotAt);
          final throttleRemainingMs = throttleUntil == null
              ? null
              : (() {
                  final remaining = throttleUntil
                      .difference(snapshotAt)
                      .inMilliseconds;
                  if (remaining <= 0) {
                    return 0;
                  }
                  return remaining;
                })();
          alertBreakdown.add(
            RouterTransportAlertBreakdown(
              listenerId: entry.listenerId,
              protocol: _protocolName(entry.protocol),
              endpoint: endpoint,
              backpressureAlerts: alertCounts?.backpressure ?? 0,
              goAwayAlerts: alertCounts?.goAway ?? 0,
              idleTimeoutAlerts: alertCounts?.idleTimeout ?? 0,
              bodyTimeoutAlerts: alertCounts?.bodyTimeout ?? 0,
              protocolErrorAlerts: alertCounts?.protocolError ?? 0,
              internalErrorAlerts: alertCounts?.internalError ?? 0,
              throttleActive: throttleActive,
              throttleRemainingMs: throttleRemainingMs,
              throttleUntil: throttleUntil,
              lastAlertAt:
                  alertSnapshot?.at ?? _lastAlertAtByListener[entry.listenerId],
              lastAlertCategory: alertSnapshot?.category,
              lastAlertReason: alertSnapshot?.reason,
              lastNewEvents: alertSnapshot?.newEvents,
              lastTotalEvents: alertSnapshot?.totalEvents,
            ),
          );
          return RouterTransportMetricsBreakdown(
            listenerId: entry.listenerId,
            protocol: _protocolName(entry.protocol),
            endpoint: endpoint,
            totalEvents: entry.totalEvents,
            gracefulEvents: entry.gracefulEvents,
            goAwayEvents: entry.goAwayEvents,
            idleTimeoutEvents: entry.idleTimeoutEvents,
            bodyTimeoutEvents: entry.bodyTimeoutEvents,
            protocolErrorEvents: entry.protocolErrorEvents,
            internalErrorEvents: entry.internalErrorEvents,
            backpressureEvents: entry.backpressureEvents,
            maxBackpressureDepth: entry.maxBackpressureDepth,
          );
        })
        .toList(growable: false);
    return RouterTransportMetrics(
      totalEvents: metrics.totalEvents,
      gracefulEvents: metrics.gracefulEvents,
      goAwayEvents: metrics.goAwayEvents,
      idleTimeoutEvents: metrics.idleTimeoutEvents,
      bodyTimeoutEvents: metrics.bodyTimeoutEvents,
      protocolErrorEvents: metrics.protocolErrorEvents,
      internalErrorEvents: metrics.internalErrorEvents,
      backpressureEvents: metrics.backpressureEvents,
      maxBackpressureDepth: metrics.maxBackpressureDepth,
      backpressureAlerts: _totalBackpressureAlerts,
      transportAlerts: totalTransportAlerts,
      goAwayAlerts: _totalGoAwayAlerts,
      idleTimeoutAlerts: _totalIdleTimeoutAlerts,
      bodyTimeoutAlerts: _totalBodyTimeoutAlerts,
      protocolErrorAlerts: _totalProtocolErrorAlerts,
      internalErrorAlerts: _totalInternalErrorAlerts,
      httpResponseStream: metrics.responseStream == null
          ? null
          : RouterHttpResponseStreamMetrics(
              streamingResponsesTotal:
                  metrics.responseStream!.streamingResponsesTotal,
              streamOpenToHeadersSendSamplesTotal:
                  metrics.responseStream!.streamOpenToHeadersSendSamplesTotal,
              streamOpenToHeadersSendUsTotal:
                  metrics.responseStream!.streamOpenToHeadersSendUsTotal,
              headersSendCallSamplesTotal:
                  metrics.responseStream!.headersSendCallSamplesTotal,
              headersSendCallUsTotal:
                  metrics.responseStream!.headersSendCallUsTotal,
              headersToFirstConnectionWriteSamplesTotal: metrics
                  .responseStream!
                  .headersToFirstConnectionWriteSamplesTotal,
              headersToFirstConnectionWriteUsTotal:
                  metrics.responseStream!.headersToFirstConnectionWriteUsTotal,
              headersToFirstConnectionWriteGe1msTotal: metrics
                  .responseStream!
                  .headersToFirstConnectionWriteGe1msTotal,
              headersToFirstConnectionWriteGe5msTotal: metrics
                  .responseStream!
                  .headersToFirstConnectionWriteGe5msTotal,
              headersToFirstConnectionWriteGe10msTotal: metrics
                  .responseStream!
                  .headersToFirstConnectionWriteGe10msTotal,
              firstChunkChannelWaitSamplesTotal:
                  metrics.responseStream!.firstChunkChannelWaitSamplesTotal,
              firstChunkChannelWaitUsTotal:
                  metrics.responseStream!.firstChunkChannelWaitUsTotal,
              firstChunkChannelWaitGe1msTotal:
                  metrics.responseStream!.firstChunkChannelWaitGe1msTotal,
              firstChunkChannelWaitGe5msTotal:
                  metrics.responseStream!.firstChunkChannelWaitGe5msTotal,
              firstChunkChannelWaitGe10msTotal:
                  metrics.responseStream!.firstChunkChannelWaitGe10msTotal,
              headersToFirstChunkDequeueSamplesTotal: metrics
                  .responseStream!
                  .headersToFirstChunkDequeueSamplesTotal,
              headersToFirstChunkDequeueUsTotal:
                  metrics.responseStream!.headersToFirstChunkDequeueUsTotal,
              headersToFirstChunkDequeueGe1msTotal:
                  metrics.responseStream!.headersToFirstChunkDequeueGe1msTotal,
              headersToFirstChunkDequeueGe5msTotal:
                  metrics.responseStream!.headersToFirstChunkDequeueGe5msTotal,
              headersToFirstChunkDequeueGe10msTotal:
                  metrics.responseStream!.headersToFirstChunkDequeueGe10msTotal,
              firstChunkSendCallSamplesTotal:
                  metrics.responseStream!.firstChunkSendCallSamplesTotal,
              firstChunkSendCallUsTotal:
                  metrics.responseStream!.firstChunkSendCallUsTotal,
              firstChunkSendCallGe1msTotal:
                  metrics.responseStream!.firstChunkSendCallGe1msTotal,
              firstChunkSendCallGe5msTotal:
                  metrics.responseStream!.firstChunkSendCallGe5msTotal,
              firstChunkSendCallGe10msTotal:
                  metrics.responseStream!.firstChunkSendCallGe10msTotal,
              headersToFirstChunkSendCallSamplesTotal: metrics
                  .responseStream!
                  .headersToFirstChunkSendCallSamplesTotal,
              headersToFirstChunkSendCallUsTotal:
                  metrics.responseStream!.headersToFirstChunkSendCallUsTotal,
              tailChunkChannelWaitSamplesTotal:
                  metrics.responseStream!.tailChunkChannelWaitSamplesTotal,
              tailChunkChannelWaitUsTotal:
                  metrics.responseStream!.tailChunkChannelWaitUsTotal,
              tailChunkChannelWaitGe1msTotal:
                  metrics.responseStream!.tailChunkChannelWaitGe1msTotal,
              tailChunkChannelWaitGe5msTotal:
                  metrics.responseStream!.tailChunkChannelWaitGe5msTotal,
              tailChunkChannelWaitGe10msTotal:
                  metrics.responseStream!.tailChunkChannelWaitGe10msTotal,
              tailChunkSendCallSamplesTotal:
                  metrics.responseStream!.tailChunkSendCallSamplesTotal,
              tailChunkSendCallUsTotal:
                  metrics.responseStream!.tailChunkSendCallUsTotal,
              tailChunkSendCallGe1msTotal:
                  metrics.responseStream!.tailChunkSendCallGe1msTotal,
              tailChunkSendCallGe5msTotal:
                  metrics.responseStream!.tailChunkSendCallGe5msTotal,
              tailChunkSendCallGe10msTotal:
                  metrics.responseStream!.tailChunkSendCallGe10msTotal,
              firstToLastChunkSendSamplesTotal:
                  metrics.responseStream!.firstToLastChunkSendSamplesTotal,
              firstToLastChunkSendUsTotal:
                  metrics.responseStream!.firstToLastChunkSendUsTotal,
              firstToLastChunkSendGe1msTotal:
                  metrics.responseStream!.firstToLastChunkSendGe1msTotal,
              firstToLastChunkSendGe5msTotal:
                  metrics.responseStream!.firstToLastChunkSendGe5msTotal,
              firstToLastChunkSendGe10msTotal:
                  metrics.responseStream!.firstToLastChunkSendGe10msTotal,
            ),
      httpRequestBodyStream: metrics.requestBodyStream == null
          ? null
          : RouterHttpRequestBodyStreamMetrics(
              streamingRequestsTotal:
                  metrics.requestBodyStream!.streamingRequestsTotal,
              dataChunkSamplesTotal:
                  metrics.requestBodyStream!.dataChunkSamplesTotal,
              dataChunkWaitUsTotal:
                  metrics.requestBodyStream!.dataChunkWaitUsTotal,
              firstChunkWaitSamplesTotal:
                  metrics.requestBodyStream!.firstChunkWaitSamplesTotal,
              firstChunkWaitUsTotal:
                  metrics.requestBodyStream!.firstChunkWaitUsTotal,
              secondChunkWaitSamplesTotal:
                  metrics.requestBodyStream!.secondChunkWaitSamplesTotal,
              secondChunkWaitUsTotal:
                  metrics.requestBodyStream!.secondChunkWaitUsTotal,
              remainingTailReadSamplesTotal:
                  metrics.requestBodyStream!.remainingTailReadSamplesTotal,
              remainingTailReadUsTotal:
                  metrics.requestBodyStream!.remainingTailReadUsTotal,
              totalReadSamplesTotal:
                  metrics.requestBodyStream!.totalReadSamplesTotal,
              totalReadUsTotal: metrics.requestBodyStream!.totalReadUsTotal,
            ),
      alertBreakdown: alertBreakdown,
      breakdown: breakdown,
    );
  }

  void _recordBackpressureAlert(int listenerId, String protocol) {
    final key = '$listenerId:$protocol';
    final counts = _alertCountsByKey.putIfAbsent(key, _ListenerAlertCounts.new);
    counts.backpressure += 1;
    _lastAlertAtByListener[listenerId] = DateTime.now().toUtc();
    _totalBackpressureAlerts += 1;
  }

  void _recordTransportAlert(int listenerId, String protocol, String reason) {
    final key = '$listenerId:$protocol';
    final counts = _alertCountsByKey.putIfAbsent(key, _ListenerAlertCounts.new);
    switch (reason) {
      case 'go_away':
        counts.goAway += 1;
        _lastAlertAtByListener[listenerId] = DateTime.now().toUtc();
        _totalGoAwayAlerts += 1;
        break;
      case 'idle_timeout':
        counts.idleTimeout += 1;
        _lastAlertAtByListener[listenerId] = DateTime.now().toUtc();
        _totalIdleTimeoutAlerts += 1;
        break;
      case 'body_timeout':
        counts.bodyTimeout += 1;
        _lastAlertAtByListener[listenerId] = DateTime.now().toUtc();
        _totalBodyTimeoutAlerts += 1;
        break;
      case 'protocol_error':
        counts.protocolError += 1;
        _lastAlertAtByListener[listenerId] = DateTime.now().toUtc();
        _totalProtocolErrorAlerts += 1;
        break;
      case 'internal_error':
        counts.internalError += 1;
        _lastAlertAtByListener[listenerId] = DateTime.now().toUtc();
        _totalInternalErrorAlerts += 1;
        break;
    }
  }

  void _recordAlertSnapshot({
    required int listenerId,
    required String protocol,
    required String category,
    required String? reason,
    required int newEvents,
    required int totalEvents,
    required DateTime at,
    DateTime? throttleUntil,
  }) {
    _alertSnapshotByKey['$listenerId:$protocol'] = _ListenerAlertSnapshot(
      at: at,
      category: category,
      reason: reason,
      newEvents: newEvents,
      totalEvents: totalEvents,
      throttleUntil: throttleUntil,
    );
  }

  String _httpConnectionReason(NativeHttpConnectionCloseReason reason) {
    switch (reason) {
      case NativeHttpConnectionCloseReason.graceful:
        return 'graceful';
      case NativeHttpConnectionCloseReason.goAway:
        return 'goaway';
      case NativeHttpConnectionCloseReason.idleTimeout:
        return 'idle_timeout';
      case NativeHttpConnectionCloseReason.bodyTimeout:
        return 'body_timeout';
      case NativeHttpConnectionCloseReason.protocolError:
        return 'protocol_error';
      case NativeHttpConnectionCloseReason.internal:
        return 'internal';
    }
  }

  String _serializerName(NativeMessageSerializer serializer) {
    switch (serializer) {
      case NativeMessageSerializer.json:
        return 'json';
      case NativeMessageSerializer.messagePack:
        return 'msgpack';
      case NativeMessageSerializer.cbor:
        return 'cbor';
      case NativeMessageSerializer.ubjson:
        return 'ubjson';
      case NativeMessageSerializer.flatbuffers:
        return 'flatbuffers';
    }
  }

  _WorkerHandle? _chooseWorker() {
    if (_workers.isEmpty) {
      return null;
    }
    if (_nextWorkerIndex >= _workers.length) {
      _nextWorkerIndex %= _workers.length;
    }
    final worker = _workers[_nextWorkerIndex];
    _nextWorkerIndex = (_nextWorkerIndex + 1) % _workers.length;
    return worker;
  }

  bool _dispatchMessages() {
    var didWork = false;
    final workersSnapshot = List<_WorkerHandle>.from(_workers);
    for (final worker in workersSnapshot) {
      if (worker.busy || worker.connections.isEmpty) {
        continue;
      }
      final connections = worker.connections;
      if (connections.isEmpty) {
        continue;
      }
      if (worker.connectionCursor >= connections.length) {
        worker.connectionCursor %= connections.length;
      }
      int? chosenConnection;
      int handle = 0;
      for (var i = 0; i < connections.length; i++) {
        final index = (worker.connectionCursor + i) % connections.length;
        final connectionId = connections[index];
        handle = _pollHandleForConnection(connectionId);
        if (handle == 0) {
          continue;
        }
        chosenConnection = connectionId;
        worker.connectionCursor = (index + 1) % connections.length;
        break;
      }
      if (chosenConnection == null || handle == 0) {
        if (connections.isNotEmpty) {
          worker.connectionCursor =
              (worker.connectionCursor + 1) % connections.length;
        } else {
          worker.connectionCursor = 0;
        }
        continue;
      }
      worker.busy = true;
      worker.commandPort.send(<Object?>[
        _workerCmdProcess,
        chosenConnection,
        handle,
      ]);
      didWork = true;
    }
    return didWork;
  }

  int _pollHandleForConnection(int connectionId) {
    try {
      final handle = runtime.pollMessageHandle(connectionId);
      if (handle != 0) {
        _lastActivityByConnection[connectionId] = DateTime.now();
        return handle;
      }
    } on NativeTransportException catch (error) {
      _handlePollError(connectionId, error);
      return 0;
    }
    try {
      final wsHandle = runtime.pollWebSocketMessageHandle(connectionId);
      if (wsHandle != 0) {
        _lastActivityByConnection[connectionId] = DateTime.now();
        return wsHandle;
      }
    } on NativeTransportException catch (error) {
      _handlePollError(connectionId, error);
    }
    return 0;
  }

  void _handlePollError(int connectionId, NativeTransportException error) {
    onEvent?.call({
      'source': 'boss',
      'type': 'boss_error',
      'connectionId': connectionId,
      'error': error.toString(),
    });
    if (error.code == NativeTransportErrorCode.connectionNotFound) {
      _detachConnection(connectionId, notifyWorker: true);
    }
  }

  bool _expireIdleConnections() {
    if (_realmByConnection.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    if (now.difference(_lastIdleSweep) < const Duration(seconds: 1)) {
      return false;
    }
    _lastIdleSweep = now;

    var didWork = false;
    final connectionIds = List<int>.from(_realmByConnection.keys);
    for (final connectionId in connectionIds) {
      final realmUri = _realmByConnection[connectionId];
      if (realmUri == null) {
        continue;
      }
      final realm = _realmByName[realmUri];
      if (realm == null) {
        continue;
      }
      final idleMs = realm.limits.sessionIdleMs;
      if (idleMs <= 0) {
        continue;
      }
      final lastActivity = _lastActivityByConnection[connectionId] ?? now;
      if (now.difference(lastActivity).inMilliseconds < idleMs) {
        continue;
      }
      onEvent?.call({
        'source': 'boss',
        'type': 'session_idle_timeout',
        'connectionId': connectionId,
        'realmUri': realmUri,
        'idleMs': idleMs,
      });
      try {
        runtime.closeConnection(connectionId);
      } on NativeTransportException catch (error) {
        onEvent?.call({
          'source': 'boss',
          'type': 'session_idle_timeout_close_error',
          'connectionId': connectionId,
          'error': error.toString(),
        });
      }
      _detachConnection(connectionId, notifyWorker: true);
      _lastActivityByConnection.remove(connectionId);
      _realmByConnection.remove(connectionId);
      didWork = true;
    }
    return didWork;
  }

  bool _drainHttp3Requests() {
    if (_http3ConnectionListeners.isEmpty) {
      return false;
    }
    var didWork = false;
    while (true) {
      var drainedInPass = false;
      final connectionIds = List<int>.from(
        _http3ConnectionListeners.keys,
        growable: false,
      );
      for (final connectionId in connectionIds) {
        var drainedForConnection = 0;
        while (drainedForConnection < _http3RequestDrainBudgetPerConnection) {
          NativeHttpHandshake? handshake;
          try {
            handshake = runtime.pollHttp3Request(connectionId);
          } on NativeTransportException catch (error) {
            onEvent?.call({
              'source': 'boss',
              'type': 'boss_error',
              'connectionId': connectionId,
              'error': error.toString(),
            });
            if (error.code == NativeTransportErrorCode.connectionNotFound) {
              _releaseHttp3Connection(connectionId);
            }
            break;
          }
          if (handshake == null) {
            break;
          }
          drainedForConnection++;
          drainedInPass = true;
          didWork = true;
          final listener = _http3ConnectionListeners[connectionId];
          if (listener == null) {
            handshake.release();
            continue;
          }
          _processHttpHandshake(
            listener,
            connectionId,
            NativeConnectionProtocol.http3,
            handshake,
          );
        }
      }
      if (!drainedInPass) {
        break;
      }
    }
    return didWork;
  }

  bool _drainHttpConnectionEvents() {
    var didWork = false;
    while (true) {
      NativeHttpConnectionEvent? event;
      try {
        event = runtime.pollHttpConnectionEvent();
      } on NativeTransportException catch (error) {
        onEvent?.call({
          'source': 'boss',
          'type': 'boss_error',
          'error': error.toString(),
        });
        break;
      }
      if (event == null) {
        break;
      }
      didWork = true;
      _handleHttpConnectionEvent(event);
    }
    return didWork;
  }

  bool _drainHttpRequests() {
    if (_httpConnectionListeners.isEmpty) {
      return false;
    }
    var didWork = false;
    final connectionIds = List<int>.from(
      _httpConnectionListeners.keys,
      growable: false,
    );
    for (final connectionId in connectionIds) {
      while (true) {
        NativeHttpHandshake? handshake;
        try {
          handshake = runtime.takeHttpHandshake(connectionId);
        } on NativeTransportException catch (error) {
          onEvent?.call({
            'source': 'boss',
            'type': 'boss_error',
            'connectionId': connectionId,
            'error': error.toString(),
          });
          if (error.code == NativeTransportErrorCode.connectionNotFound) {
            _httpConnectionListeners.remove(connectionId);
          }
          break;
        }
        if (handshake == null) {
          break;
        }
        didWork = true;
        final listener = _httpConnectionListeners[connectionId];
        if (listener == null) {
          handshake.release();
          break;
        }
        _processHttpHandshake(
          listener,
          connectionId,
          NativeConnectionProtocol.http,
          handshake,
        );
      }
    }
    return didWork;
  }

  bool _drainHttp2Requests() {
    if (_http2ConnectionListeners.isEmpty) {
      return false;
    }
    var didWork = false;
    final connectionIds = List<int>.from(
      _http2ConnectionListeners.keys,
      growable: false,
    );
    for (final connectionId in connectionIds) {
      while (true) {
        NativeHttpHandshake? handshake;
        try {
          handshake = runtime.takeHttpHandshake(connectionId);
        } on NativeTransportException catch (error) {
          onEvent?.call({
            'source': 'boss',
            'type': 'boss_error',
            'connectionId': connectionId,
            'error': error.toString(),
          });
          if (error.code == NativeTransportErrorCode.connectionNotFound) {
            _http2ConnectionListeners.remove(connectionId);
          }
          break;
        }
        if (handshake == null) {
          break;
        }
        didWork = true;
        final listener = _http2ConnectionListeners[connectionId];
        if (listener == null) {
          handshake.release();
          break;
        }
        _processHttpHandshake(
          listener,
          connectionId,
          NativeConnectionProtocol.http2,
          handshake,
        );
      }
    }
    return didWork;
  }

  void _registerHttpConnection(RouterListener listener, int connectionId) {
    _httpConnectionListeners[connectionId] = listener;
  }

  void _registerHttp2Connection(RouterListener listener, int connectionId) {
    final alreadyTracked = _http2ConnectionListeners.containsKey(connectionId);
    _http2ConnectionListeners[connectionId] = listener;
    if (alreadyTracked) {
      return;
    }
    final details = _collectHttp2HandshakeDetails(connectionId);
    final event = <String, Object?>{
      'source': 'binding',
      'type': 'listener_protocol_pending',
      'listenerId': listener.listenerId,
      'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
      'connectionId': connectionId,
      'protocol': _protocolName(NativeConnectionProtocol.http2),
    };
    if (details != null && details.isNotEmpty) {
      event['details'] = details;
    }
    onEvent?.call(event);
  }

  Map<String, Object?>? _collectHttp2HandshakeDetails(int connectionId) {
    NativeHttp2Handshake? handshake;
    try {
      handshake = runtime.takeHttp2Handshake(connectionId);
    } on NativeTransportException catch (error) {
      onEvent?.call({
        'source': 'boss',
        'type': 'boss_error',
        'connectionId': connectionId,
        'error': error.toString(),
      });
      return null;
    }
    if (handshake == null) {
      return const {'protocol': 'http/2'};
    }
    try {
      final details = <String, Object?>{
        'protocol': handshake.protocol.isEmpty ? 'http/2' : handshake.protocol,
      };
      final alpn = handshake.alpn;
      if (alpn != null && alpn.isNotEmpty) {
        details['alpn'] = alpn;
      }
      if (handshake.listenerProtocols.isNotEmpty) {
        details['listenerProtocols'] = handshake.listenerProtocols;
      }
      return details;
    } finally {
      handshake.release();
    }
  }

  void _processHttpHandshake(
    RouterListener listener,
    int connectionId,
    NativeConnectionProtocol protocol,
    NativeHttpHandshake handshake,
  ) {
    final request = RouterHttpRequest(
      listener: listener,
      connectionId: connectionId,
      method: handshake.method,
      target: handshake.target,
      path: handshake.path,
      query: handshake.query,
      protocol: handshake.protocol,
      version: handshake.version,
      headers: handshake.headers,
      body: handshake.body,
      handshakeHandle: handshake.handle,
      realm: handshake.realm,
      procedure: handshake.procedure,
    );
    final event = <String, Object?>{
      'source': 'boss',
      'type': 'listener_http_request',
      'listenerId': listener.listenerId,
      'connectionId': connectionId,
      'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
      'method': request.method,
      'target': request.target,
      'path': request.path,
      'query': request.query,
      'protocol': request.protocol,
      'version': request.version,
      'realm': request.realm,
      'procedure': request.procedure,
      'headers': request.headers,
      'bodyLength': request.nativeBody.length,
    };
    onEvent?.call(event);
    final handler = onHttpRequest;
    if (handler != null) {
      unawaited(() async {
        try {
          await handler(request, handshake);
        } catch (error, stackTrace) {
          onEvent?.call({
            'source': 'boss',
            'type': 'http_request_handler_error',
            'listenerId': listener.listenerId,
            'connectionId': connectionId,
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          });
        }
      }());
    } else {
      handshake.release();
    }
    if (protocol == NativeConnectionProtocol.http) {
      onEvent?.call({
        'source': 'binding',
        'type': 'listener_protocol_pending',
        'listenerId': listener.listenerId,
        'endpoint': '${listener.endpoint.host}:${listener.endpoint.port}',
        'connectionId': connectionId,
        'protocol': _protocolName(protocol),
      });
    }
  }

  Future<RouterMetricsSnapshot> collectMetricsSnapshot() async {
    final stateMetrics = await _fetchStateMetrics();
    final transportMetrics = _ensureTransportMetrics();
    return RouterMetricsSnapshot(
      timestamp: DateTime.now().toUtc(),
      realmCount: stateMetrics.realmCount,
      sessionCount: stateMetrics.sessionCount,
      subscriptionCount: stateMetrics.subscriptionCount,
      registrationCount: stateMetrics.registrationCount,
      pendingInvocationCount: stateMetrics.pendingInvocationCount,
      totalInvocationsDispatched: stateMetrics.totalInvocationsDispatched,
      totalPublicationsRouted: stateMetrics.totalPublicationsRouted,
      activeConnections: _connectionOwners.length,
      workerCount: _workers.length,
      alerts: _buildAlertMetrics(),
      transport: transportMetrics,
    );
  }

  Future<RealmSnapshot> fetchRealmSnapshot(String realmUri) async {
    final reply = ReceivePort();
    _stateStore.commandPort.send(
      RealmSnapshotCommand(
        realmUri: realmUri,
        knownVersion: null,
        replyPort: reply.sendPort,
      ),
    );
    final response = await reply.first;
    reply.close();
    if (response is RealmSnapshotResponse) {
      return response.snapshot;
    }
    if (response is StoreErrorResponse) {
      throw StateError(
        'Failed to fetch snapshot for $realmUri: ${response.message}',
      );
    }
    throw StateError('Unexpected snapshot response: $response');
  }

  Future<RouterStateMetrics> _fetchStateMetrics() async {
    final reply = ReceivePort();
    _stateStore.commandPort.send(
      MetricsSnapshotCommand(replyPort: reply.sendPort),
    );
    final response = await reply.first;
    reply.close();
    if (response is RouterStateMetrics) {
      return response;
    }
    if (response is StoreErrorResponse) {
      throw StateError('Failed to gather metrics: ${response.message}');
    }
    throw StateError('Unexpected metrics response: $response');
  }

  Future<void> _spawnWorker(
    RouterListener listener,
    int connectionId, {
    Map<String, Object?> metadata = const {},
  }) async {
    final args = <String, Object?>{
      'bossPort': _eventPort.sendPort,
      'connectionId': connectionId,
      'listenerId': listener.listenerId,
      'libraryPath': libraryPathHint,
      'statePort': _stateStore.commandPort,
      'settings': RouterSettingsCodec.toMap(settings),
      'listener': {
        'listenerId': listener.listenerId,
        'port': listener.port,
        'endpoint': RouterSettingsCodec.endpointToMap(listener.endpoint),
      },
      'listeners': listeners
          .map(
            (entry) => {
              'listenerId': entry.listenerId,
              'port': entry.port,
              'endpoint': RouterSettingsCodec.endpointToMap(entry.endpoint),
            },
          )
          .toList(growable: false),
    };
    if (metadata.isNotEmpty) {
      args['metadata'] = metadata;
    }
    final isolate = await Isolate.spawn<Map<String, Object?>>(
      entryPoint,
      args,
      debugName: 'connectanum-router-worker-$connectionId',
    );
    _pendingIsolates[connectionId] = isolate;
  }

  int _allocatePendingWorkerToken() => _nextPendingWorkerToken--;

  void _handleEvent(dynamic message) {
    _loopPacer.requestWake();
    if (message is! Map) {
      onEvent?.call({
        'source': 'worker',
        'type': 'worker_unknown_event',
        'payload': message,
      });
      return;
    }

    final type = message['type'];
    final Map<String, Object?> payload = {'source': 'worker'};

    if (type == _workerEventRegister) {
      onEvent?.call({
        'source': 'worker',
        'type': 'worker_register_debug',
        'connectionId': message['connectionId'],
        'listenerId': message['listenerId'],
        'workerHash': message['workerHash'],
      });
      _handleWorkerRegister(message);
      payload
        ..['type'] = 'worker_registered'
        ..['connectionId'] = message['connectionId']
        ..['listenerId'] = message['listenerId'];
    } else if (type == _workerEventSessionOpened) {
      final connectionId = message['connectionId'] as int?;
      final realmUri = message['realmUri'] as String?;
      if (connectionId != null && realmUri != null) {
        _realmByConnection[connectionId] = realmUri;
        _lastActivityByConnection[connectionId] = DateTime.now();
      }
      payload
        ..['type'] = 'worker_session_opened'
        ..addAll(message.cast<String, Object?>());
    } else if (type == 'worker_send') {
      final connectionId = message['connectionId'] as int;
      final Uint8List payloadBytes = message['payload'] as Uint8List;
      try {
        runtime.sendMessage(connectionId, payloadBytes);
        _lastActivityByConnection[connectionId] = DateTime.now();
        payload
          ..['type'] = 'worker_send'
          ..['connectionId'] = connectionId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_send_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } on UnsupportedError catch (error) {
        payload
          ..['type'] = 'worker_send_unsupported'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      }
    } else if (type == 'worker_forward_message') {
      final connectionId = message['connectionId'] as int;
      final target = _connectionOwners[connectionId];
      if (target != null) {
        target.commandPort.send([
          _workerCmdSendMessage,
          connectionId,
          message['message'],
        ]);
      }
      payload
        ..['type'] = 'worker_forward_message'
        ..['connectionId'] = connectionId;
    } else if (type == 'worker_forward_native_event') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final subscriptionId = message['subscriptionId'] as int;
      final publicationId = message['publicationId'] as int;
      final publisherSessionId = message['publisherSessionId'] as int?;
      final topic = message['topic'] as String?;
      try {
        runtime.forwardPublishEvent(
          handle: handle,
          connectionId: connectionId,
          subscriptionId: subscriptionId,
          publicationId: publicationId,
          publisherSessionId: publisherSessionId,
          topic: topic,
        );
        payload
          ..['type'] = 'worker_forward_native_event'
          ..['connectionId'] = connectionId
          ..['subscriptionId'] = subscriptionId
          ..['publicationId'] = publicationId
          ..['handle'] = handle;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_event_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == 'worker_forward_native_invocation') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final invocationId = message['invocationId'] as int;
      final registrationId = message['registrationId'] as int;
      final callerSessionId = message['callerSessionId'] as int?;
      final procedure = message['procedure'] as String?;
      final receiveProgress = message['receiveProgress'] as bool?;
      try {
        runtime.forwardCallInvocation(
          handle: handle,
          connectionId: connectionId,
          invocationId: invocationId,
          registrationId: registrationId,
          callerSessionId: callerSessionId,
          procedure: procedure,
          receiveProgress: receiveProgress,
        );
        payload
          ..['type'] = 'worker_forward_native_invocation'
          ..['connectionId'] = connectionId
          ..['invocationId'] = invocationId
          ..['registrationId'] = registrationId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_invocation_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == 'worker_forward_native_result') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final requestId = message['requestId'] as int;
      final progress = message['progress'] as bool? ?? false;
      try {
        runtime.forwardResultFromYield(
          handle: handle,
          connectionId: connectionId,
          requestId: requestId,
          progress: progress,
        );
        payload
          ..['type'] = 'worker_forward_native_result'
          ..['connectionId'] = connectionId
          ..['requestId'] = requestId
          ..['progress'] = progress;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_result_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == 'worker_forward_native_error') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final requestType = message['requestType'] as int;
      final requestId = message['requestId'] as int;
      try {
        runtime.forwardInvocationError(
          handle: handle,
          connectionId: connectionId,
          requestType: requestType,
          requestId: requestId,
        );
        payload
          ..['type'] = 'worker_forward_native_error'
          ..['connectionId'] = connectionId
          ..['requestId'] = requestId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_error_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == _workerEventConnectionAdded) {
      payload
        ..['type'] = 'worker_connection_added'
        ..['connectionId'] = message['connectionId']
        ..['listenerId'] = message['listenerId'];
      final protocol = message['protocol'];
      if (protocol is String) {
        payload['protocol'] = protocol;
      }
      final wsProtocol = message['websocketProtocol'];
      if (wsProtocol is String) {
        payload['websocketProtocol'] = wsProtocol;
      }
      final wsSerializer = message['websocketSerializer'];
      if (wsSerializer is String) {
        payload['websocketSerializer'] = wsSerializer;
      }
    } else if (type == _workerEventConnectionRemoved) {
      final connectionId = message['connectionId'] as int;
      final worker = _connectionOwners.remove(connectionId);
      worker?.connections.remove(connectionId);
      _httpConnectionListeners.remove(connectionId);
      _http2ConnectionListeners.remove(connectionId);
      _releaseHttp3Connection(connectionId);
      _lastActivityByConnection.remove(connectionId);
      _realmByConnection.remove(connectionId);
      payload
        ..['type'] = 'worker_connection_removed'
        ..['connectionId'] = connectionId;
    } else if (type == _workerEventDrained) {
      final workerHash = message['workerHash'] as int?;
      _WorkerHandle? drainedWorker;
      if (workerHash != null) {
        for (final candidate in _workers) {
          if (candidate.isolateHash == workerHash) {
            drainedWorker = candidate;
            break;
          }
        }
      }
      final completer = drainedWorker?.drainCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      payload
        ..['type'] = 'worker_drained'
        ..['workerHash'] = workerHash;
    } else if (type == _workerEventReady) {
      final connectionId = message['connectionId'] as int;
      final worker = _connectionOwners[connectionId];
      worker?.busy = false;
      payload
        ..['type'] = 'worker_ready'
        ..['connectionId'] = connectionId;
    } else if (type == _workerEventShutdown) {
      final connectionId = message['connectionId'] as int;
      final worker = _connectionOwners[connectionId];
      if (worker != null) {
        _shutdownWorker(worker, terminateIsolate: false);
      }
      payload
        ..['type'] = 'worker_shutdown'
        ..['connectionId'] = connectionId;
    } else if (type == _workerEventCallReceived) {
      payload
        ..['type'] = 'worker_call_received'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventCallDispatched) {
      payload
        ..['type'] = 'worker_call_dispatched'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventCallDispatchComplete) {
      payload
        ..['type'] = 'worker_call_dispatch_complete'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventCallDispatchError) {
      payload
        ..['type'] = 'worker_call_dispatch_error'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventPublishRouted) {
      payload
        ..['type'] = 'worker_publish_routed'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventWorkerShutdown) {
      payload
        ..['type'] = 'worker_shutdown_event'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventWorkerShutdown) {
      payload
        ..['type'] = 'worker_shutdown_event'
        ..addAll(message.cast<String, Object?>());
    } else if (type == _workerEventError) {
      final connectionId = message['connectionId'] as int?;
      if (connectionId != null) {
        final worker = _connectionOwners[connectionId];
        worker?.busy = false;
      }
      payload
        ..['type'] = 'worker_error'
        ..['connectionId'] = connectionId
        ..['error'] = message['error']
        ..['stackTrace'] = message['stackTrace'];
    } else {
      payload
        ..['type'] = 'worker_unknown_event'
        ..['payload'] = message;
    }

    onEvent?.call(payload);
  }

  void _handleCommand(dynamic message) {
    _loopPacer.requestWake();
    if (message is _BossGetMetricsCommand) {
      _respondWithMetricsSnapshot(message.replyPort);
    }
  }

  void _respondWithMetricsSnapshot(SendPort replyPort) {
    unawaited(() async {
      try {
        final snapshot = await collectMetricsSnapshot();
        replyPort.send(snapshot);
      } catch (error, stackTrace) {
        replyPort.send(StoreErrorResponse(error.toString()));
        _reportBossError('metrics_snapshot_error', error, stackTrace);
      }
    }());
  }

  void _reportBossError(String type, Object error, StackTrace stackTrace) {
    onEvent?.call({
      'source': 'boss',
      'type': type,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }

  void _handleStateEvent(StateChangedEvent event) {
    _loopPacer.requestWake();
    onEvent?.call({
      'source': 'state',
      'type': 'state_changed',
      'realmUri': event.realmUri,
      'version': event.version,
    });
  }

  void forwardMessageToConnection(int connectionId, AbstractMessage message) {
    final worker = _connectionOwners[connectionId];
    if (worker == null) {
      throw StateError('Connection $connectionId not registered on router');
    }
    worker.commandPort.send(<Object?>[
      _workerCmdSendMessage,
      connectionId,
      message,
    ]);
  }

  void _handleWorkerRegister(Map<dynamic, dynamic> message) {
    final connectionId = message['connectionId'] as int;
    final listenerId = message['listenerId'] as int;
    final commandPort = message['commandPort'] as SendPort;
    final SendPort? statePort = message['statePort'] as SendPort?;
    final isolate = _pendingIsolates.remove(connectionId);
    final listener = _listenerById[listenerId];
    if (isolate == null || listener == null) {
      commandPort.send(<Object?>[_workerCmdShutdown]);
      isolate?.kill(priority: Isolate.immediate);
      return;
    }
    final worker = _WorkerHandle(
      id: _nextWorkerId++,
      isolate: isolate,
      commandPort: commandPort,
      statePort: statePort ?? _stateStore.commandPort,
      isolateHash: message['workerHash'] as int? ?? isolate.hashCode,
    );
    if (connectionId > 0) {
      worker.connections.add(connectionId);
    }
    _workers.add(worker);
    if (connectionId > 0) {
      _connectionOwners[connectionId] = worker;
    }
  }

  void _shutdownWorker(_WorkerHandle worker, {bool terminateIsolate = false}) {
    for (final connectionId in worker.connections.toList()) {
      _connectionOwners.remove(connectionId);
      _lastActivityByConnection.remove(connectionId);
      _realmByConnection.remove(connectionId);
      _httpConnectionListeners.remove(connectionId);
      _http2ConnectionListeners.remove(connectionId);
      worker.commandPort.send(<Object?>[
        _workerCmdRemoveConnection,
        connectionId,
      ]);
      _releaseHttp3Connection(connectionId);
      _webSocketSelectionByConnection.remove(connectionId);
    }
    worker.commandPort.send(<Object?>[_workerCmdShutdown]);
    if (terminateIsolate) {
      worker.isolate.kill(priority: Isolate.immediate);
    }
    _workers.remove(worker);
  }

  void _detachConnection(int connectionId, {bool notifyWorker = false}) {
    final worker = _connectionOwners.remove(connectionId);
    _lastActivityByConnection.remove(connectionId);
    _realmByConnection.remove(connectionId);
    _httpConnectionListeners.remove(connectionId);
    _http2ConnectionListeners.remove(connectionId);
    if (worker == null) {
      final pending = _pendingIsolates.remove(connectionId);
      pending?.kill(priority: Isolate.immediate);
      _releaseHttp3Connection(connectionId);
      return;
    }
    worker.connections.remove(connectionId);
    if (notifyWorker) {
      worker.commandPort.send(<Object?>[
        _workerCmdRemoveConnection,
        connectionId,
      ]);
    }
    _releaseHttp3Connection(connectionId);
    _webSocketSelectionByConnection.remove(connectionId);
  }

  void _replaceHttp3Connection(
    int connectionId,
    NativeHttp3Connection connection,
  ) {
    final previous = _http3Connections.remove(connectionId);
    previous?.release();
    _http3Connections[connectionId] = connection;
  }

  void _releaseHttp3Connection(int connectionId) {
    final connection = _http3Connections.remove(connectionId);
    connection?.release();
    _http3ConnectionListeners.remove(connectionId);
  }
}

class _WebSocketSelection {
  _WebSocketSelection(this.protocol, this.serializer);

  final String protocol;
  final NativeMessageSerializer serializer;
}

_WebSocketSelection? _selectWebSocketProtocol(List<String> proposals) {
  for (final proposal in proposals) {
    final serializer = _webSocketProtocols[proposal.toLowerCase()];
    if (serializer != null) {
      return _WebSocketSelection(proposal, serializer);
    }
  }
  return null;
}

sealed class _BossCommand {
  const _BossCommand();
}

class _BossGetMetricsCommand extends _BossCommand {
  const _BossGetMetricsCommand(this.replyPort) : super();

  final SendPort replyPort;
}

const Map<String, NativeMessageSerializer> _webSocketProtocols = {
  'wamp.2.json': NativeMessageSerializer.json,
  'wamp.2.msgpack': NativeMessageSerializer.messagePack,
  'wamp.2.cbor': NativeMessageSerializer.cbor,
  'wamp.2.ubjson': NativeMessageSerializer.ubjson,
  'wamp.2.flatbuffers': NativeMessageSerializer.flatbuffers,
};

class _ListenerAlertCounts {
  int backpressure = 0;
  int goAway = 0;
  int idleTimeout = 0;
  int bodyTimeout = 0;
  int protocolError = 0;
  int internalError = 0;
}

class _ListenerAlertSnapshot {
  const _ListenerAlertSnapshot({
    required this.at,
    required this.category,
    required this.reason,
    required this.newEvents,
    required this.totalEvents,
    this.throttleUntil,
  });

  final DateTime at;
  final String category;
  final String? reason;
  final int newEvents;
  final int totalEvents;
  final DateTime? throttleUntil;
}

class _WorkerHandle {
  _WorkerHandle({
    required this.id,
    required this.isolate,
    required this.commandPort,
    required this.statePort,
    required this.isolateHash,
  });

  final int id;
  final Isolate isolate;
  final SendPort commandPort;
  final SendPort statePort;
  final int isolateHash;
  final List<int> connections = [];
  int connectionCursor = 0;
  bool busy = false;
  Completer<void>? drainCompleter;
}
