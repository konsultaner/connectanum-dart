part of '../router_instance.dart';

/// Entry point signature for worker isolates. Custom entry points can be injected
/// in tests to observe scheduling behaviour.
typedef RouterWorkerEntryPoint = void Function(Map<String, Object?> init);

const int _workerCmdProcess = 1;
const int _workerCmdShutdown = 2;
const int _workerCmdAddConnection = 3;
const int _workerCmdRemoveConnection = 4;
const int _workerCmdSendMessage = 5;
const int _workerCmdDrainConnections = 6;
const int _workerCmdExportConnection = 7;
const int _workerCmdForgetTransferredConnection = 8;

const int _workerEventRegister = 1;
const int _workerEventReady = 2;
const int _workerEventError = 3;
const int _workerEventShutdown = 4;
const int _workerEventConnectionAdded = 5;
const int _workerEventConnectionRemoved = 6;
const int _workerEventDrained = 7;
const int _workerEventCallReceived = 8;
const int _workerEventCallDispatched = 9;
const int _workerEventCallDispatchComplete = 10;
const int _workerEventCallDispatchError = 11;
const int _workerEventPublishRouted = 12;
const int _workerEventWorkerShutdown = 13;
const int _workerEventSessionOpened = 14;
const int _workerEventConnectionTransferReady = 15;
const int _workerEventConnectionTransferRejected = 16;

final json_serializer.Serializer _jsonSerializer = json_serializer.Serializer();
final cbor_serializer.Serializer _cborSerializer = cbor_serializer.Serializer();
final msgpack_serializer.Serializer _msgpackSerializer =
    msgpack_serializer.Serializer();
RealmAuthorizationProviderCache? _workerAuthorizationProviderCache;

RouterListener decodeListener(Map<String, Object?> data) {
  final endpointMap = data['endpoint'] as Map<String, Object?>;
  final sni =
      (endpointMap['sni_certificates'] as List<dynamic>?)
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
    heartbeatInterval: endpointMap['heartbeat_interval_ms'] != null
        ? Duration(milliseconds: endpointMap['heartbeat_interval_ms'] as int)
        : null,
    heartbeatTimeout: endpointMap['heartbeat_timeout_ms'] != null
        ? Duration(milliseconds: endpointMap['heartbeat_timeout_ms'] as int)
        : null,
    handshakeTimeout: endpointMap['handshake_timeout_ms'] != null
        ? Duration(milliseconds: endpointMap['handshake_timeout_ms'] as int)
        : null,
    maxHttpContentLength: endpointMap['max_http_content_length'] as int?,
    maxRawSocketSizeExponent: endpointMap['max_rawsocket_size_exponent'] as int,
    webSocketPath: endpointMap['websocket_path'] as String?,
    sniCertificates: sni,
  );
  return RouterListener(
    listenerId: data['listenerId'] as int,
    endpoint: endpoint,
    port: data['port'] as int,
    http3Port: (data['http3Port'] as int?) ?? 0,
  );
}

ListenerSettings lookupListenerSettings(
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

RouterListener resolveListener(
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
  final sniCertificates =
      template?.endpoint.sniCertificates ?? const <SniCertificate>[];
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
    http3Port: template?.http3Port ?? 0,
  );
  registry[listenerId] = resolved;
  return resolved;
}

Future<void> sendAbort(
  SendPort bossPort,
  WorkerConnectionState state,
  int connectionId,
  String reason, {
  String? message,
  Map<String, Object?>? details,
  List<dynamic>? arguments,
  Map<String, Object?>? argumentsKeywords,
}) async {
  final serializer = state.serializer ?? NativeMessageSerializer.json;
  final abortDetails = <String, Object?>{};
  if (details != null && details.isNotEmpty) {
    abortDetails.addAll(details);
  }
  final abort = abort_msg.Abort(
    reason,
    details: abortDetails.isEmpty ? null : abortDetails,
    message: message,
    arguments: arguments,
    argumentsKeywords: argumentsKeywords,
  );
  await sendMessage(bossPort, connectionId, serializer, abort);
}

Future<void> sendMessage(
  SendPort bossPort,
  int connectionId,
  NativeMessageSerializer serializer,
  AbstractMessage message,
) async {
  final payload = encodeMessage(serializer, message);
  bossPort.send({
    'type': 'worker_send',
    'connectionId': connectionId,
    'payload': payload,
  });
}

Uint8List encodeMessage(
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
    case NativeMessageSerializer.cbor:
      return _cborSerializer.serialize(message);
    default:
      throw UnsupportedError('Serializer ${serializer.name} not supported');
  }
}

NativeMessageSerializer? _serializerFromName(String name) {
  switch (name) {
    case 'json':
      return NativeMessageSerializer.json;
    case 'msgpack':
      return NativeMessageSerializer.messagePack;
    case 'cbor':
      return NativeMessageSerializer.cbor;
    case 'ubjson':
      return NativeMessageSerializer.ubjson;
    case 'flatbuffers':
      return NativeMessageSerializer.flatbuffers;
  }
  return null;
}

Future<int> allocateSessionId(SendPort? statePort) async {
  if (statePort == null) {
    return DateTime.now().microsecondsSinceEpoch;
  }
  final replyPort = ReceivePort();
  statePort.send(SessionAllocateIdCommand(replyPort: replyPort.sendPort));
  final id = await replyPort.first as int;
  replyPort.close();
  return id;
}

/// Default worker entry point that materialises native message handles in an
/// isolate and hands them over to the router once available.
void defaultRouterWorkerEntryPoint(Map<String, Object?> init) {
  _routerWorkerEntryPoint(init);
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
  _workerAuthorizationProviderCache = RealmAuthorizationProviderCache(settings);

  unawaited(RemoteWampDelegateRegistry.warmUpForSettings(settings));

  final decoder = NativeMessageHandleDecoder(libraryPath: libraryPath);
  final commandPort = ReceivePort();
  final Map<int, int> connections = initialConnectionId > 0
      ? <int, int>{initialConnectionId: initialListenerId}
      : <int, int>{};
  final RealmContextCache? realmContexts = statePort != null
      ? RealmContextCache(statePort: statePort)
      : null;

  final listeners = <int, RouterListener>{};
  final rawListeners = init['listeners'] as List<dynamic>?;
  if (rawListeners != null) {
    for (final raw in rawListeners) {
      final listener = decodeListener(raw as Map<String, Object?>);
      listeners[listener.listenerId] = listener;
    }
  }
  if (rawListener != null) {
    final listener = decodeListener(rawListener);
    listeners[listener.listenerId] = listener;
  }

  final connectionStates = <int, WorkerConnectionState>{};
  if (initialConnectionId > 0) {
    final initialListener = resolveListener(
      listeners,
      settings,
      initialListenerId,
    );
    final initialState = WorkerConnectionState(
      listener: initialListener,
      listenerSettings: lookupListenerSettings(settings, initialListener),
    );
    initialState.protocol =
        initialListener.settings?.primaryProtocol ?? ListenerProtocol.rawsocket;
    final Map<Object?, Object?>? initialMetadata = init['metadata'] is Map
        ? init['metadata'] as Map<Object?, Object?>
        : null;
    if (initialMetadata != null) {
      final protocol = initialMetadata['protocol'] as String?;
      if (protocol != null) {
        initialState.protocol = listenerProtocolFromString(protocol);
      }
      final wsProtocol = initialMetadata['websocketProtocol'] as String?;
      if (wsProtocol != null) {
        initialState.websocketProtocol = wsProtocol;
      }
      final wsSerializer = initialMetadata['websocketSerializer'] as String?;
      if (wsSerializer != null) {
        initialState.websocketSerializer = wsSerializer;
        initialState.serializer ??= _serializerFromName(wsSerializer);
      }
    }
    connectionStates[initialConnectionId] = initialState;
  }

  final workerId = Isolate.current.hashCode;

  bossPort.send({
    'type': 'worker_debug',
    'stage': 'start',
    'connectionId': initialConnectionId,
    'listenerId': initialListenerId,
    'libraryPath': libraryPath,
  });

  bossPort.send({
    'type': _workerEventRegister,
    'connectionId': initialConnectionId,
    'listenerId': initialListenerId,
    'commandPort': commandPort.sendPort,
    'statePort': statePort,
    'workerHash': workerId,
  });
  bossPort.send({
    'type': _workerEventReady,
    'connectionId': initialConnectionId,
  });

  bool shuttingDown = false;

  Future<void> processMessage(
    int connectionId,
    int listenerId,
    int handle,
  ) async {
    final state = connectionStates.putIfAbsent(connectionId, () {
      final listener = resolveListener(listeners, settings, listenerId);
      return WorkerConnectionState(
        listener: listener,
        listenerSettings: lookupListenerSettings(settings, listener),
      );
    });
    if (state.protocol == null &&
        state.listenerSettings.primaryProtocol != null) {
      state.protocol = state.listenerSettings.primaryProtocol;
    }
    state.protocol ??=
        state.listener.settings?.primaryProtocol ?? ListenerProtocol.rawsocket;

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
            statePort,
            realmContexts,
            state,
            message,
            connectionId,
            workerId,
          );
        } else {
          await _handleSessionMessage(
            bossPort: bossPort,
            statePort: statePort,
            realmContexts: realmContexts,
            connectionStates: connectionStates,
            state: state,
            message: message,
            connectionId: connectionId,
            incomingMessage: incoming,
          );
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
  subscription = commandPort.listen((dynamic raw) async {
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
      final metadata = raw.length > 3 && raw[3] is Map
          ? raw[3] as Map<Object?, Object?>
          : null;
      final transferData = raw.length > 4 && raw[4] is Map
          ? raw[4] as Map<Object?, Object?>
          : null;
      connections[newConnectionId] = listenerId;
      final listener = resolveListener(listeners, settings, listenerId);
      connectionStates[newConnectionId] = WorkerConnectionState(
        listener: listener,
        listenerSettings: lookupListenerSettings(settings, listener),
      );
      final state = connectionStates[newConnectionId];
      if (metadata != null && state != null) {
        final protocol = metadata['protocol'] as String?;
        if (protocol != null) {
          state.protocol = listenerProtocolFromString(protocol);
        }
        final wsProtocol = metadata['websocketProtocol'] as String?;
        if (wsProtocol != null) {
          state.websocketProtocol = wsProtocol;
        }
        final wsSerializer = metadata['websocketSerializer'] as String?;
        if (wsSerializer != null) {
          state.websocketSerializer = wsSerializer;
          state.serializer ??= _serializerFromName(wsSerializer);
        }
      }
      if (transferData != null) {
        state?.applyTransferData(transferData);
      }
      bossPort.send({
        'type': _workerEventConnectionAdded,
        'connectionId': newConnectionId,
        'listenerId': listenerId,
        'workerHash': workerId,
        if (state?.protocol != null)
          'protocol': listenerProtocolToString(state!.protocol!),
        if (state?.websocketProtocol != null)
          'websocketProtocol': state!.websocketProtocol,
        if (state?.websocketSerializer != null)
          'websocketSerializer': state!.websocketSerializer,
        if (state?.sessionId != null) 'sessionId': state!.sessionId,
      });
    } else if (command == _workerCmdRemoveConnection) {
      final removeId = raw[1] as int;
      await _handleConnectionRemoval(
        connectionId: removeId,
        connections: connections,
        connectionStates: connectionStates,
        statePort: statePort,
        realmContexts: realmContexts,
      );
      bossPort.send({
        'type': _workerEventConnectionRemoved,
        'connectionId': removeId,
        'workerHash': workerId,
      });
    } else if (command == _workerCmdExportConnection) {
      final transferConnectionId = raw[1] as int;
      final listenerId = connections[transferConnectionId];
      final state = connectionStates[transferConnectionId];
      final transferData = state?.toTransferData();
      if (listenerId == null || transferData == null) {
        bossPort.send({
          'type': _workerEventConnectionTransferRejected,
          'connectionId': transferConnectionId,
          'workerHash': workerId,
        });
        return;
      }
      bossPort.send({
        'type': _workerEventConnectionTransferReady,
        'connectionId': transferConnectionId,
        'listenerId': listenerId,
        'workerHash': workerId,
        'metadata': <String, Object?>{
          if (state?.protocol != null)
            'protocol': listenerProtocolToString(state!.protocol!),
          if (state?.websocketProtocol != null)
            'websocketProtocol': state!.websocketProtocol,
          if (state?.websocketSerializer != null)
            'websocketSerializer': state!.websocketSerializer,
        },
        'transferData': transferData,
      });
    } else if (command == _workerCmdForgetTransferredConnection) {
      final transferConnectionId = raw[1] as int;
      connections.remove(transferConnectionId);
      connectionStates.remove(transferConnectionId);
      bossPort.send({
        'type': _workerEventConnectionRemoved,
        'connectionId': transferConnectionId,
        'workerHash': workerId,
      });
    } else if (command == _workerCmdSendMessage) {
      final connectionId = raw[1] as int;
      final AbstractMessage message = raw[2] as AbstractMessage;
      final state = connectionStates[connectionId];
      if (state == null) {
        return;
      }
      final serializer = state.serializer ?? NativeMessageSerializer.json;
      await sendMessage(bossPort, connectionId, serializer, message);
    } else if (command == _workerCmdDrainConnections) {
      final reason = raw.length > 1 && raw[1] is String
          ? raw[1] as String
          : 'wamp.close.system_shutdown';
      final connectionIds = connectionStates.keys.toList(growable: false);
      for (final targetConnectionId in connectionIds) {
        final targetState = connectionStates[targetConnectionId];
        if (targetState == null) {
          continue;
        }
        connections.remove(targetConnectionId);
        await _handleGoodbye(
          bossPort: bossPort,
          statePort: statePort,
          realmContexts: realmContexts,
          state: targetState,
          connectionId: targetConnectionId,
          reason: reason,
        );
        connectionStates.remove(targetConnectionId);
        bossPort.send({
          'type': _workerEventConnectionRemoved,
          'connectionId': targetConnectionId,
        });
      }
      bossPort.send({'type': _workerEventDrained, 'workerHash': workerId});
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

@visibleForTesting
Future<void> handleRemoveConnectionForTest({
  required int connectionId,
  required Map<int, int> connections,
  required Map<int, WorkerConnectionState> connectionStates,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
}) async {
  await _handleConnectionRemoval(
    connectionId: connectionId,
    connections: connections,
    connectionStates: connectionStates,
    statePort: statePort,
    realmContexts: realmContexts,
  );
}

Future<void> _handleConnectionRemoval({
  required int connectionId,
  required Map<int, int> connections,
  required Map<int, WorkerConnectionState> connectionStates,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
}) async {
  connections.remove(connectionId);
  final state = connectionStates.remove(connectionId);
  if (state != null) {
    await _closeSession(
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
    );
  }
}
