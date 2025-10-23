part of '../router_instance.dart';

/// Entry point signature for worker isolates. Custom entry points can be injected
/// in tests to observe scheduling behaviour.
typedef RouterWorkerEntryPoint = void Function(Map<String, Object?> init);

const int _workerCmdProcess = 1;
const int _workerCmdShutdown = 2;
const int _workerCmdAddConnection = 3;
const int _workerCmdRemoveConnection = 4;

const int _workerEventRegister = 1;
const int _workerEventReady = 2;
const int _workerEventError = 3;
const int _workerEventShutdown = 4;
const int _workerEventConnectionAdded = 5;
const int _workerEventConnectionRemoved = 6;

enum _HandshakePhase { awaitingHello, awaitingAuthenticate, open, aborted }

final json_serializer.Serializer _jsonSerializer =
    json_serializer.Serializer();
final msgpack_serializer.Serializer _msgpackSerializer =
    msgpack_serializer.Serializer();

class _WorkerConnectionState {
  _WorkerConnectionState({required this.listener, required this.listenerSettings});

  final RouterListener listener;
  final ListenerSettings listenerSettings;
  _HandshakePhase phase = _HandshakePhase.awaitingHello;
  NativeMessageSerializer? serializer;
  RealmSettings? realmSettings;
  String? realmUri;
  int? sessionId;
  Details? welcomeDetails;
  String? authMethod;
}

RouterListener _decodeListener(Map<String, Object?> data) {
  final endpointMap = data['endpoint'] as Map<String, Object?>;
  final sni = (endpointMap['sni_certificates'] as List<dynamic>?)
          ?.map((entry) {
            final cert = entry as Map<String, Object?>;
            return SniCertificate(
              hostname: cert['hostname'] as String,
              certificateChainPem: cert['certificate_chain_pem'] as String,
              privateKeyPem: cert['private_key_pem'] as String,
            );
          })
          .toList(growable: false) ??
      const <SniCertificate>[];
  final endpoint = Endpoint(
    host: endpointMap['host'] as String,
    port: endpointMap['port'] as int,
    tlsMode: TlsModeWireFormat.parse(endpointMap['tls_mode'] as String),
    idleTimeout: endpointMap['idle_timeout_ms'] != null
        ? Duration(milliseconds: endpointMap['idle_timeout_ms'] as int)
        : null,
    handshakeTimeout: endpointMap['handshake_timeout_ms'] != null
        ? Duration(milliseconds: endpointMap['handshake_timeout_ms'] as int)
        : null,
    maxHttpContentLength:
        endpointMap['max_http_content_length'] as int?,
    maxRawSocketSizeExponent:
        endpointMap['max_rawsocket_size_exponent'] as int,
    webSocketPath: endpointMap['websocket_path'] as String?,
    sniCertificates: sni,
  );
  return RouterListener(
    listenerId: data['listenerId'] as int,
    endpoint: endpoint,
    port: data['port'] as int,
  );
}

ListenerSettings _lookupListenerSettings(
  RouterSettings settings,
  RouterListener listener,
) {
  final target = '${listener.endpoint.host}:${listener.endpoint.port}';
  return settings.listeners.firstWhere(
    (entry) => entry.endpoint == target,
    orElse: () => settings.listeners.isNotEmpty
        ? settings.listeners.first
        : ListenerSettings(type: 'rawsocket', endpoint: target),
  );
}

RouterListener _resolveListener(
  Map<int, RouterListener> registry,
  RouterSettings settings,
  int listenerId,
) {
  final existing = registry[listenerId];
  if (existing != null) {
    return existing;
  }
  RouterListener? template;
  if (registry.isNotEmpty) {
    template = registry.values.first;
  }

  String host = template?.endpoint.host ?? '0.0.0.0';
  int port = template?.endpoint.port ?? 0;
  final tlsMode = template?.endpoint.tlsMode ?? TlsMode.disabled;
  final idleTimeout = template?.endpoint.idleTimeout;
  final handshakeTimeout = template?.endpoint.handshakeTimeout;
  final maxHttp = template?.endpoint.maxHttpContentLength;
  final sniCertificates = template?.endpoint.sniCertificates ?? const <SniCertificate>[];
  int exponent = template?.endpoint.maxRawSocketSizeExponent ?? 16;
  final websocketPath = template?.endpoint.webSocketPath;

  if (template == null && settings.listeners.isNotEmpty) {
    final fallback = settings.listeners.first;
    final parts = fallback.endpoint.split(':');
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      host = parts.first;
    }
    if (parts.length > 1) {
      port = int.tryParse(parts[1]) ?? port;
    }
    exponent =
        fallback.options['max_rawsocket_size_exponent'] as int? ?? exponent;
  }

  final resolved = RouterListener(
    listenerId: listenerId,
    endpoint: Endpoint(
      host: host,
      port: port,
      tlsMode: tlsMode,
      idleTimeout: idleTimeout,
      handshakeTimeout: handshakeTimeout,
      maxHttpContentLength: maxHttp,
      maxRawSocketSizeExponent: exponent,
      webSocketPath: websocketPath,
      sniCertificates: sniCertificates,
    ),
    port: port,
  );
  registry[listenerId] = resolved;
  return resolved;
}

bool _allowsAnonymous(List<String> methods) =>
    methods.isEmpty || methods.contains('anonymous');

bool _clientAllowsAnonymous(List<String>? methods) =>
    methods == null || methods.isEmpty || methods.contains('anonymous');

Future<void> _handleHello(
  SendPort bossPort,
  SendPort? statePort,
  RouterSettings settings,
  _WorkerConnectionState state,
  Hello hello,
  int connectionId,
  RealmContextCache? realmContexts,
  int workerId,
) async {
  if (state.phase != _HandshakePhase.awaitingHello) {
    await _sendAbort(
      bossPort,
      state,
      connectionId,
      'wamp.error.protocol_violation',
      message: 'HELLO received in unexpected state',
    );
    state.phase = _HandshakePhase.aborted;
    return;
  }

  final realmUri = hello.realm;
  if (realmUri == null || realmUri.isEmpty) {
    await _sendAbort(
      bossPort,
      state,
      connectionId,
      'wamp.error.invalid_uri',
      message: 'Missing realm in HELLO',
    );
    state.phase = _HandshakePhase.aborted;
    return;
  }

  RealmSettings? realmSettings;
  for (final realm in settings.realms) {
    if (realm.name == realmUri) {
      realmSettings = realm;
      break;
    }
  }
  if (realmSettings == null) {
    await _sendAbort(
      bossPort,
      state,
      connectionId,
      'wamp.error.no_such_realm',
      message: 'Realm $realmUri is not configured',
    );
    state.phase = _HandshakePhase.aborted;
    return;
  }
  state.realmSettings = realmSettings;
  state.realmUri = realmUri;

  final realmAllowsAnonymous = _allowsAnonymous(realmSettings.auth.methods);
  final listenerAllowsAnonymous =
      _allowsAnonymous(state.listenerSettings.authmethods);
  final clientAllowsAnonymous =
      _clientAllowsAnonymous(hello.details.authmethods);

  if (!(realmAllowsAnonymous && listenerAllowsAnonymous && clientAllowsAnonymous)) {
    await _sendAbort(
      bossPort,
      state,
      connectionId,
      'wamp.error.not_authorized',
      message: 'Anonymous authentication is not permitted for realm $realmUri',
    );
    state.phase = _HandshakePhase.aborted;
    return;
  }

  statePort?.send(
    RealmEnsureCommand(
      realmUri: realmUri,
      options: const <String, Object?>{},
    ),
  );
  realmContexts?.invalidate(realmUri);

  final authId = hello.details.authid ?? 'anonymous';
  final welcomeDetails = Details.forWelcome(
    realm: realmUri,
    authId: authId,
    authMethod: 'anonymous',
    authProvider: 'static',
    authRole: 'anonymous',
  );
  state.welcomeDetails = welcomeDetails;
  state.authMethod = 'anonymous';

  final sessionId = await _allocateSessionId(statePort);
  state.sessionId = sessionId;

  final serializer = state.serializer ?? NativeMessageSerializer.json;
  await _sendMessage(
    bossPort,
    connectionId,
    serializer,
    Welcome(sessionId, welcomeDetails),
  );

  state.phase = _HandshakePhase.open;

  if (statePort != null) {
    final session = SessionRecord(
      id: sessionId,
      authId: authId,
      authRole: welcomeDetails.authrole,
      roles: _extractRolesMap(welcomeDetails),
      workerId: workerId,
      connectionId: connectionId,
      lastActivity: DateTime.now(),
      listener: state.listener,
    );
    statePort.send(
      SessionOpenCommand(realmUri: realmUri, session: session),
    );
  }
}

Future<void> _handleAuthenticate(
  SendPort bossPort,
  _WorkerConnectionState state,
  authenticate_msg.Authenticate authenticate,
  int connectionId,
) async {
  if (state.phase != _HandshakePhase.awaitingAuthenticate) {
    await _sendAbort(
      bossPort,
      state,
      connectionId,
      'wamp.error.protocol_violation',
      message: 'AUTHENTICATE unexpected',
    );
    state.phase = _HandshakePhase.aborted;
    return;
  }

  await _sendAbort(
    bossPort,
    state,
    connectionId,
    'wamp.error.not_authorized',
    message: 'Authentication methods are not yet implemented',
  );
  state.phase = _HandshakePhase.aborted;
}

Future<void> _sendAbort(
  SendPort bossPort,
  _WorkerConnectionState state,
  int connectionId,
  String reason,
  {String? message}
) async {
  final serializer = state.serializer ?? NativeMessageSerializer.json;
  await _sendMessage(
    bossPort,
    connectionId,
    serializer,
    abort_msg.Abort(reason, message: message),
  );
}

Future<void> _sendMessage(
  SendPort bossPort,
  int connectionId,
  NativeMessageSerializer serializer,
  AbstractMessage message,
) async {
  final payload = _encodeMessage(serializer, message);
  bossPort.send({
    'type': 'worker_send',
    'connectionId': connectionId,
    'payload': payload,
  });
}

Uint8List _encodeMessage(
  NativeMessageSerializer serializer,
  AbstractMessage message,
) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return Uint8List.fromList(
        utf8.encode(_jsonSerializer.serializeToString(message)),
      );
    case NativeMessageSerializer.messagePack:
      return _msgpackSerializer.serialize(message);
    default:
      throw UnsupportedError('Serializer ${serializer.name} not supported');
  }
}

Future<int> _allocateSessionId(SendPort? statePort) async {
  if (statePort == null) {
    return DateTime.now().microsecondsSinceEpoch;
  }
  final replyPort = ReceivePort();
  statePort.send(
    SessionAllocateIdCommand(replyPort: replyPort.sendPort),
  );
  final id = await replyPort.first as int;
  replyPort.close();
  return id;
}

Map<String, Object?> _extractRolesMap(Details details) {
  final welcome = Welcome(0, details);
  final encoded = _jsonSerializer.serializeToString(welcome);
  final decoded = jsonDecode(encoded) as List<dynamic>;
  final detailsMap = decoded[2] as Map<String, dynamic>;
  final roles = detailsMap['roles'];
  if (roles is Map<String, dynamic>) {
    return Map<String, Object?>.from(roles);
  }
  return <String, Object?>{};
}

/// Default worker entry point that materialises native message handles in an
/// isolate and hands them over to the router once available.
void _routerWorkerEntryPoint(Map<String, Object?> init) {
  registerDefaultAuthenticators();

  final bossPort = init['bossPort'] as SendPort;
  final initialConnectionId = init['connectionId'] as int;
  final initialListenerId = init['listenerId'] as int;
  final libraryPath = init['libraryPath'] as String?;
  final SendPort? statePort = init['statePort'] as SendPort?;
  final settingsMap = init['settings'] as Map<String, Object?>?;
  final rawListener = init['listener'] as Map<String, Object?>?;

  final RouterSettings settings = settingsMap != null
      ? RouterSettingsCodec.fromMap(settingsMap)
      : RouterSettings(realms: const [], listeners: const [], metrics: null);

  final decoder = NativeMessageHandleDecoder(libraryPath: libraryPath);
  final commandPort = ReceivePort();
  final Map<int, int> connections = {initialConnectionId: initialListenerId};
  final RealmContextCache? realmContexts = statePort != null
      ? RealmContextCache(statePort: statePort)
      : null;

  final listeners = <int, RouterListener>{};
  final rawListeners = init['listeners'] as List<dynamic>?;
  if (rawListeners != null) {
    for (final raw in rawListeners) {
      final listener = _decodeListener(raw as Map<String, Object?>);
      listeners[listener.listenerId] = listener;
    }
  }
  if (rawListener != null) {
    final listener = _decodeListener(rawListener);
    listeners[listener.listenerId] = listener;
  }

  final connectionStates = <int, _WorkerConnectionState>{};
  final initialListener = _resolveListener(
    listeners,
    settings,
    initialListenerId,
  );
  connectionStates[initialConnectionId] = _WorkerConnectionState(
    listener: initialListener,
    listenerSettings: _lookupListenerSettings(settings, initialListener),
  );

  bossPort.send({
    'type': _workerEventRegister,
    'connectionId': initialConnectionId,
    'listenerId': initialListenerId,
    'commandPort': commandPort.sendPort,
    'statePort': statePort,
  });
  bossPort.send({'type': _workerEventReady, 'connectionId': initialConnectionId});

  final workerId = Isolate.current.hashCode;
  bool shuttingDown = false;

  Future<void> processMessage(int connectionId, int listenerId, int handle) async {
    final state = connectionStates.putIfAbsent(connectionId, () {
      final listener = _resolveListener(listeners, settings, listenerId);
      return _WorkerConnectionState(
        listener: listener,
        listenerSettings: _lookupListenerSettings(settings, listener),
      );
    });

    try {
      final incoming = decoder.materialize(handle);
      try {
        state.serializer ??= incoming.serializer;
        final message = incoming.message;
        if (message is Hello) {
          await _handleHello(
            bossPort,
            statePort,
            settings,
            state,
            message,
            connectionId,
            realmContexts,
            workerId,
          );
        } else if (message is authenticate_msg.Authenticate) {
          await _handleAuthenticate(
            bossPort,
            state,
            message,
            connectionId,
          );
        } else {
          // TODO: Forward to session handling once implemented.
        }
      } finally {
        incoming.dispose();
      }
    } catch (error, stackTrace) {
      bossPort.send({
        'type': _workerEventError,
        'connectionId': connectionId,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
    } finally {
      if (!shuttingDown) {
        bossPort.send({
          'type': _workerEventReady,
          'connectionId': connectionId,
        });
      }
    }
  }

  late final StreamSubscription<dynamic> subscription;
  subscription = commandPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return;
    }
    final command = raw[0];
    if (command == _workerCmdProcess) {
      if (shuttingDown) {
        return;
      }
      final connectionId = raw[1] as int;
      final handle = raw[2] as int;
      final listenerId = connections[connectionId] ?? initialListenerId;
      unawaited(processMessage(connectionId, listenerId, handle));
    } else if (command == _workerCmdAddConnection) {
      final listenerId = raw[1] as int;
      final newConnectionId = raw[2] as int;
      connections[newConnectionId] = listenerId;
      final listener = _resolveListener(listeners, settings, listenerId);
      connectionStates[newConnectionId] = _WorkerConnectionState(
        listener: listener,
        listenerSettings: _lookupListenerSettings(settings, listener),
      );
      bossPort.send({
        'type': _workerEventConnectionAdded,
        'connectionId': newConnectionId,
        'listenerId': listenerId,
      });
    } else if (command == _workerCmdRemoveConnection) {
      final removeId = raw[1] as int;
      connections.remove(removeId);
      connectionStates.remove(removeId);
      bossPort.send({
        'type': _workerEventConnectionRemoved,
        'connectionId': removeId,
      });
    } else if (command == _workerCmdShutdown) {
      if (shuttingDown) {
        return;
      }
      shuttingDown = true;
      subscription.cancel();
      commandPort.close();
      bossPort.send({
        'type': _workerEventShutdown,
        'connectionId': initialConnectionId,
      });
    }
  });
}
