part of '../router_instance.dart';

String? _mqttRealmForListener(
  RouterListener listener,
  RouterSettings settings,
) {
  final configured = listener.settings?.options['realm'];
  if (configured is String && configured.trim().isNotEmpty) {
    return configured.trim();
  }
  return settings.realms.length == 1 ? settings.realms.single.name : null;
}

// Deadline/cancellation releases publication payloads immediately, but a custom
// provider's Future cannot be forcibly canceled. Count that work until it really
// settles, across gateway replacements, instead of admitting unlimited orphans.
final class _MqttPolicyBudget {
  _MqttPolicyBudget(this.limit);
  int limit;
  int pending = 0;
  Future<T> run<T>(Future<T> Function() create) {
    if (pending >= limit) {
      return Future.error(StateError('Gateway policy capacity exhausted'));
    }
    pending++;
    final work = Future<T>.sync(create);
    work.then<void>(
      (_) => pending--,
      onError: (Object error, StackTrace stack) {
        pending--;
      },
    );
    return work;
  }
}

/// Explicit, realm-scoped MQTT/WAMP publication gateway on a native binding.
extension RouterMqttGateway on RouterBinding {
  Future<MqttWampGateway> enableMqttGateway({
    required String realmUri,
    required String mqttAuthRole,
    String mqttAuthId = 'mqtt:anonymous',
    String serviceAuthRole = 'mqtt-gateway',
    int maxPendingBytes = 8 * 1024 * 1024,
    int maxPendingOperations = 256,
    Duration operationTimeout = const Duration(seconds: 5),
  }) async {
    if (_disposed || _draining) throw StateError('Router binding is closing');
    if (maxPendingBytes <= 0 ||
        maxPendingOperations <= 0 ||
        operationTimeout <= Duration.zero) {
      throw ArgumentError('Gateway limits must be positive');
    }
    final realm = settings.realms.firstWhereOrNull((r) => r.name == realmUri);
    if (realm == null ||
        !realm.roles.any((r) => r.name == mqttAuthRole) ||
        !realm.roles.any((r) => r.name == serviceAuthRole) ||
        mqttAuthId.isEmpty) {
      throw ArgumentError(
        'A configured realm and MQTT principal/role are required',
      );
    }
    if (!realm.roles.any((r) => r.permissions.isNotEmpty) &&
        realm.authorizationProvider == null &&
        AuthorizationProviderRegistry.provider == null) {
      throw ArgumentError(
        'Gateway requires an explicit realm authorization policy',
      );
    }
    if (!_ready) activateListeners();
    final boss = _boss;
    if (boss == null) {
      throw StateError('Gateway requires native router isolates');
    }
    final mqttListeners = _listeners.where(
      (l) => l.settings?.protocols.contains(ListenerProtocol.mqtt) == true,
    );
    if (mqttListeners.isEmpty) {
      throw ArgumentError('Gateway requires an MQTT listener');
    }
    for (final listener in mqttListeners) {
      final assigned = _mqttRealmForListener(listener, settings);
      if (!settings.realms.any((r) => r.name == assigned)) {
        throw ArgumentError(
          'Every MQTT listener requires an unambiguous configured realm',
        );
      }
    }
    final previous = _mqttGateways[realmUri];
    if (previous != null && !previous.isClosed) {
      throw StateError('Gateway already exists for $realmUri');
    }
    final gateway = MqttWampGateway._(
      this,
      boss._mqttBroker,
      realm,
      mqttAuthId,
      mqttAuthRole,
      serviceAuthRole,
      maxPendingBytes,
      maxPendingOperations,
      operationTimeout,
    );
    _mqttGateways[realmUri] = gateway;
    boss._mqttBroker.installGateway(realmUri, gateway);
    final startup = Completer<void>();
    _internalSessionStarts.add(startup.future);
    try {
      await gateway._start();
      return gateway;
    } catch (_) {
      await gateway.close();
      rethrow;
    } finally {
      startup.complete();
      _internalSessionStarts.remove(startup.future);
    }
  }
}

/// Application bytes cross this boundary; MQTT control packets never do.
final class MqttWampGateway implements MqttBrokerGatewayPolicy {
  MqttWampGateway._(
    this._binding,
    this._broker,
    this._realm,
    this.mqttAuthId,
    this.mqttAuthRole,
    this.serviceAuthRole,
    this.maxPendingBytes,
    this.maxPendingOperations,
    this.operationTimeout,
  ) : _providers = RealmAuthorizationProviderCache(_binding.settings);

  static const publishProcedure = 'connectanum.mqtt.v1.publish';
  static const _maxCacheBytes = 1024 * 1024;
  final RouterBinding _binding;
  final MqttQos0Broker _broker;
  final RealmSettings _realm;
  final RealmAuthorizationProviderCache _providers;
  late final _MqttPolicyBudget _policyBudget =
      _binding._mqttPolicyBudgets.putIfAbsent(
        realmUri,
        () => _MqttPolicyBudget(maxPendingOperations),
      )..limit = maxPendingOperations;
  final String mqttAuthId;
  final String mqttAuthRole;
  final String serviceAuthRole;
  final int maxPendingBytes;
  final int maxPendingOperations;
  final Duration operationTimeout;
  final MqttGatewayCancellation _lifetime = MqttGatewayCancellation();
  final Map<String, String> _topics = {};
  RouterSession? _session;
  bool _ready = false;
  bool _closed = false;
  Future<void>? _closeFuture;
  int _pendingBytes = 0;
  int _pendingOperations = 0;
  int _peakPendingBytes = 0;
  int _cacheBytes = 0;
  int _mqttPublications = 0;
  int _wampPublications = 0;
  int _denied = 0;
  int _errors = 0;

  String get realmUri => _realm.name;
  @override
  bool get isClosed => _closed;
  bool get _active => _ready && !_closed && !_binding._disposed;

  Map<String, int> get metrics => {
    'pending_bytes': _pendingBytes,
    'pending_operations': _pendingOperations,
    'peak_pending_bytes': _peakPendingBytes,
    'mqtt_publications': _mqttPublications,
    'wamp_publications': _wampPublications,
    'denied': _denied,
    'errors': _errors,
    'topic_cache_bytes': _cacheBytes,
    'topic_cache_entries': _topics.length,
    'cancellation_listeners': _lifetime.listenerCount,
    'pending_policy_futures': _policyBudget.pending,
    for (final entry in _broker.gatewayMetrics.entries)
      'broker_${entry.key}': entry.value,
  };

  Future<T> _wait<T>(Future<T> future, [MqttPeerContext? peer]) async {
    try {
      return await _lifetime.waitFor(
        future,
        other: peer?.cancellation,
        timeout: operationTimeout,
      );
    } on TimeoutException {
      // A wedged policy/state owner must not accumulate abandoned commands as
      // publication deadlines expire. Stop admission and release owned state.
      // The owned close Future retains cleanup failures for close()/dispose().
      // Awaiting it here would make an invocation wait for its own stream close.
      close().ignore();
      rethrow;
    }
  }

  Future<void> _start() async {
    await _wait(_policyBudget.run(() => _providers.providerFor(_realm)));
    final session = await _binding.createInternalSession(
      realmUri: realmUri,
      authId: 'connectanum:mqtt-gateway:$realmUri',
      authRole: serviceAuthRole,
      indexByRealm: false,
    );
    _session = session;
    // The binding owns this session throughout startup and closes it during
    // disposal. Registration uses the lifetime cancellation boundary below.
    final registration = await _wait(session.register(publishProcedure));
    registration.onInvoke(_onInvocation);
    _ready = true;
  }

  String _topicUri(String topic) {
    final cached = _topics[topic];
    if (cached != null) return cached;
    final uri = MqttTopicUriMapper.toWampUri(topic);
    final bytes = 2 * (topic.length + uri.length);
    while (_topics.isNotEmpty &&
        (_topics.length >= 256 || _cacheBytes + bytes > _maxCacheBytes)) {
      final oldest = _topics.keys.first;
      _cacheBytes -= 2 * (oldest.length + _topics.remove(oldest)!.length);
    }
    _topics[topic] = uri;
    _cacheBytes += bytes;
    return uri;
  }

  void _validatePayload(String topic, Uint8List payload) {
    final bodyLength = 3 + utf8.encode(topic).length + payload.length;
    if (1 + encodeMqttVariableByteInteger(bodyLength).length + bodyLength >
        1024 * 1024) {
      throw const MqttProtocolException(
        'gateway publication exceeds MQTT packet limit',
      );
    }
  }

  bool _admit(int bytes) {
    if (!_active ||
        _pendingBytes + bytes > maxPendingBytes ||
        _pendingOperations >= maxPendingOperations) {
      _denied++;
      return false;
    }
    _pendingBytes += bytes;
    _pendingOperations++;
    if (_pendingBytes > _peakPendingBytes) _peakPendingBytes = _pendingBytes;
    return true;
  }

  void _release(int bytes) {
    _pendingBytes -= bytes;
    _pendingOperations--;
  }

  Future<bool> _allow(
    AuthorizationRequest request, [
    MqttPeerContext? peer,
  ]) async {
    if (!_active) return false;
    final provider = await _wait(
      _policyBudget.run(() => _providers.providerFor(_realm)),
      peer,
    );
    final decision = await _wait(
      _policyBudget.run(
        () => RealmAuthorizer.authorize(
          realmSettings: _realm,
          provider: provider,
          request: request,
        ),
      ),
      peer,
    );
    if (!decision.allowed) _denied++;
    return _active && decision.allowed;
  }

  AuthorizationRequest _mqttRequest(
    MqttPeerContext peer,
    AuthorizationAction action,
    String uri,
    Map<String, Object?> options,
  ) => AuthorizationRequest(
    realmUri: realmUri,
    action: action,
    uri: uri,
    sessionId: 0,
    connectionId: peer.connectionId,
    authId: mqttAuthId,
    authRole: mqttAuthRole,
    authMethod: 'anonymous',
    authProvider: 'mqtt-gateway',
    protocol: ListenerProtocol.mqtt,
    options: {'mqtt_client_id': peer.clientId, ...options},
  );

  @override
  Future<bool> publish(MqttPeerContext peer, MqttPublish publication) async {
    if (peer.realm != realmUri || !_admit(publication.payload.length)) {
      return false;
    }
    try {
      final uri = _topicUri(publication.topic);
      _validatePayload(publication.topic, publication.payload);
      if (!await _allow(
        _mqttRequest(peer, AuthorizationAction.publish, uri, {
          'mqtt_topic': publication.topic,
          'mqtt_direction': 'mqtt_to_wamp',
        }),
        peer,
      )) {
        return false;
      }
      await _publishWamp(
        publication.topic,
        uri,
        publication.payload,
        'mqtt',
        peer: peer,
      );
      _mqttPublications++;
      return true;
    } finally {
      _release(publication.payload.length);
    }
  }

  @override
  Future<bool> subscribe(MqttPeerContext peer, String filter) {
    final levels = filter
        .split('/')
        .takeWhile((s) => s != '+' && s != '#')
        .toList();
    final topic = levels.join('/');
    final uri = topic.isEmpty ? MqttTopicUriMapper.prefix : _topicUri(topic);
    return _allow(
      _mqttRequest(peer, AuthorizationAction.subscribe, uri, {
        'mqtt_filter': filter,
      }),
      peer,
    );
  }

  @override
  Future<bool> receive(MqttPeerContext peer, String topic) => _allow(
    _mqttRequest(peer, AuthorizationAction.subscribe, _topicUri(topic), {
      'mqtt_topic': topic,
    }),
    peer,
  );

  Future<int> _publishWamp(
    String topic,
    String uri,
    Uint8List payload,
    String origin, {
    MqttPeerContext? peer,
    int? caller,
  }) async {
    final result = await _wait(
      _session!.publish(
        uri,
        arguments: [payload],
        options: publish_msg.PublishOptions(
          acknowledge: true,
          excludeMe: false,
          custom: {
            'mqtt_topic': topic,
            'mqtt_origin': origin,
            'mqtt_gateway': _session!.sessionId,
            if (peer != null) 'mqtt_client_id': peer.clientId,
            'mqtt_caller': ?caller,
          },
        ),
      ),
      peer,
    );
    return result!.publicationId;
  }

  Future<SessionInfo?> _caller(int invocationId) async {
    final reply = ReceivePort();
    try {
      _binding._boss!.stateCommandPort.send(
        InvocationCallerCommand(
          realmUri: realmUri,
          invocationId: invocationId,
          calleeSessionId: _session!.sessionId,
          replyPort: reply.sendPort,
        ),
      );
      final response = await _wait(reply.first);
      return response is SessionInfo ? response : null;
    } finally {
      reply.close();
    }
  }

  Future<void> _onInvocation(invocation_msg.Invocation invocation) async {
    var admitted = false;
    var bytes = 0;
    try {
      if (!_active) throw StateError('Gateway is closed');
      if (invocation.details.pptScheme != null) {
        throw const FormatException(
          'Gateway API requires application arguments',
        );
      }
      final args = invocation.arguments;
      if (args == null ||
          args.length != 2 ||
          args[0] is! String ||
          args[1] is! Uint8List ||
          (invocation.argumentsKeywords?.isNotEmpty ?? false)) {
        throw const FormatException(
          'Expected MQTT topic and binary application payload',
        );
      }
      final topic = args[0] as String;
      final payload = args[1] as Uint8List;
      final uri = _topicUri(topic);
      _validatePayload(topic, payload);
      bytes = payload.length;
      if (!_admit(bytes)) throw StateError('Gateway capacity unavailable');
      admitted = true;
      final caller = await _caller(invocation.requestId);
      if (caller == null ||
          !await _allow(
            AuthorizationRequest(
              realmUri: realmUri,
              action: AuthorizationAction.publish,
              uri: uri,
              sessionId: caller.id,
              connectionId: caller.connectionId,
              authId: caller.authId,
              authRole: caller.authRole,
              authMethod: caller.authMethod,
              authProvider: caller.authProvider,
              protocol: caller.protocol,
              options: {'mqtt_topic': topic, 'mqtt_direction': 'wamp_to_mqtt'},
            ),
          )) {
        if (!invocation.responseClosed) {
          invocation.respondWith(
            isError: true,
            errorUri: wamp_core.Error.notAuthorized,
          );
        }
        return;
      }
      // Authorization can await an application provider. A canceled/disconnected
      // caller must not be resurrected from the earlier identity snapshot.
      if (invocation.responseClosed ||
          await _caller(invocation.requestId) == null) {
        _denied++;
        if (!invocation.responseClosed) {
          invocation.respondWith(
            isError: true,
            errorUri: 'wamp.error.canceled',
          );
        }
        return;
      }
      final id = await _publishWamp(
        topic,
        uri,
        payload,
        'wamp',
        caller: caller.id,
      );
      _broker.publishFromGateway(
        realmUri,
        this,
        MqttGatewayPublication(topic: topic, payload: payload),
      );
      _wampPublications++;
      if (!invocation.responseClosed) invocation.respondWith(arguments: [id]);
    } catch (error) {
      _errors++;
      if (!invocation.responseClosed) {
        invocation.respondWith(
          isError: true,
          errorUri: error is FormatException || error is MqttProtocolException
              ? 'wamp.error.invalid_argument'
              : error is TimeoutException
              ? 'wamp.error.timeout'
              : 'wamp.error.canceled',
        );
      }
    } finally {
      if (admitted) _release(bytes);
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _ready = false;
    _lifetime.cancel();
    _broker.closeRealm(realmUri);
    _topics.clear();
    _cacheBytes = 0;
    await _session?.close();
  }
}
