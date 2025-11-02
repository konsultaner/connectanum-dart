part of '../router_instance.dart';

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
  }) : _pendingEndpoints = List<Endpoint>.unmodifiable(endpoints);

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
  _RouterBoss? _boss;
  bool _ready = false;

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
      final listener = RouterListener(
        listenerId: listenerId,
        endpoint: endpoint,
        port: boundPort,
      );
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
      )..start();
    }
    _ready = true;
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
    final statePort = boss._stateStore.commandPort;
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
    final listener = RouterListener(
      listenerId: -sessionId,
      endpoint: Endpoint(
        host: 'internal',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      ),
      port: 0,
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
      internalSendPort: internalPort,
    );
    statePort.send(SessionOpenCommand(realmUri: realmUri, session: record));
    _internalSessions.add(session);
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
    for (final entry in _connections.entries) {
      final connectionId = entry.key;
      final state = entry.value;
      while (result.length < maxMessages) {
        final message = runtime.pollMessage(connectionId);
        if (message == null) {
          break;
        }
        result.add(RouterMessage(state.listener, connectionId, message));
      }
      if (result.length >= maxMessages) {
        break;
      }
    }
    return result;
  }

  void _acceptConnections(RouterListener listener) {
    while (true) {
      final connectionId = runtime.pollConnection(listener.listenerId);
      if (connectionId == 0) {
        break;
      }
      _connections.putIfAbsent(connectionId, () => _ConnectionState(listener));
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
    for (final session in _internalSessions.toList()) {
      await session.close();
    }
    _internalSessions.clear();
    final boss = _boss;
    if (boss != null) {
      await boss.stop();
    }
  }

  void _removeInternalSession(RouterSession session) {
    _internalSessions.remove(session);
  }

  @visibleForTesting
  SendPort? get debugStatePort => _boss?._stateStore.commandPort;

  void forwardMessageToConnection(
    int connectionId,
    AbstractMessage message,
  ) {
    final boss = _boss;
    if (boss == null) {
      throw StateError('Router boss not running');
    }
    boss.forwardMessageToConnection(connectionId, message);
  }
}

/// Tracks additional per-connection bookkeeping for the binding.
class _ConnectionState {
  _ConnectionState(this.listener);

  final RouterListener listener;
}
