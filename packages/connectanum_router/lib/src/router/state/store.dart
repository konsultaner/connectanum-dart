import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:connectanum_core/connectanum_core.dart' as wamp;

import '../config/router_settings.dart';
import 'commands.dart';
import 'ids.dart';
import 'procedure.dart';
import 'session.dart';
import 'snapshot.dart';
import 'subscription.dart';

/// Maintains all WAMP realm/session/subscription/registration state.
class RouterStateStore {
  static const int _maxGlobalRetryDeduplicationEntries = 16384;

  RouterStateStore({required this.settings})
    : _commandPort = ReceivePort(),
      _eventController = StreamController<StateChangedEvent>.broadcast(),
      _sessionMetaController = StreamController<SessionMetaEvent>.broadcast(),
      _subscriptionMetaController =
          StreamController<SubscriptionMetaEvent>.broadcast(),
      _registrationMetaController =
          StreamController<RegistrationMetaEvent>.broadcast(),
      _invocationTimeoutController =
          StreamController<InvocationTimeoutEvent>.broadcast(),
      _realmConfigs = Map.fromEntries(
        settings.realms.map((realm) => MapEntry(realm.name, realm)),
      );

  final RouterSettings settings;

  final ReceivePort _commandPort;
  final StreamController<StateChangedEvent> _eventController;
  final StreamController<SessionMetaEvent> _sessionMetaController;
  final StreamController<SubscriptionMetaEvent> _subscriptionMetaController;
  final StreamController<RegistrationMetaEvent> _registrationMetaController;
  final StreamController<InvocationTimeoutEvent> _invocationTimeoutController;
  final WampIdAllocatorRegistry ids = WampIdAllocatorRegistry();
  final Map<String, RealmRecord> _realms = {};
  final Map<(String, int), Timer> _invocationTimeouts = {};
  final Map<String, RealmSettings> _realmConfigs;
  final Map<_RetryDeduplicationKey, _RetryThrottleLease> _retryThrottleLeases =
      {};
  final Map<int, _RetryDeduplicationKey> _retryThrottleKeysByInvocation = {};
  final Map<_RetryDeduplicationKey, _PendingRetryDebounce>
  _pendingRetryDebounces = {};
  int _totalInvocationsDispatched = 0;
  int _totalPublicationsRouted = 0;
  int _totalRetryDeduplicationThrottleRejects = 0;
  int _totalRetryDeduplicationDebounceReplacements = 0;
  int _totalRetryDeduplicationCapacityRejects = 0;
  int _totalRetryDeduplicationExpirations = 0;

  Stream<StateChangedEvent> get events => _eventController.stream;
  Stream<SessionMetaEvent> get sessionMetaEvents =>
      _sessionMetaController.stream;
  Stream<SubscriptionMetaEvent> get subscriptionMetaEvents =>
      _subscriptionMetaController.stream;
  Stream<RegistrationMetaEvent> get registrationMetaEvents =>
      _registrationMetaController.stream;
  Stream<InvocationTimeoutEvent> get invocationTimeoutEvents =>
      _invocationTimeoutController.stream;
  SendPort get commandPort => _commandPort.sendPort;

  void start() {
    _commandPort.listen(_handleMessage);
  }

  void dispose() {
    for (final timer in _invocationTimeouts.values) {
      timer.cancel();
    }
    _invocationTimeouts.clear();
    for (final pending in _pendingRetryDebounces.values) {
      pending.timer?.cancel();
      pending.replyPort.send(
        StoreErrorResponse(
          StoreCommandError('Router state store disposed').toString(),
        ),
      );
    }
    _pendingRetryDebounces.clear();
    _retryThrottleLeases.clear();
    _retryThrottleKeysByInvocation.clear();
    _commandPort.close();
    _eventController.close();
    _sessionMetaController.close();
    _subscriptionMetaController.close();
    _registrationMetaController.close();
    _invocationTimeoutController.close();
    _realms.clear();
  }

  void _handleMessage(dynamic message) {
    if (message is RouterStateCommand) {
      try {
        _dispatchCommand(message);
      } catch (error, stackTrace) {
        _reportStoreError(error, stackTrace, command: message);
      }
    } else if (message is List && message.length == 2) {
      final command = message[0];
      final reply = message[1] as SendPort?;
      if (command is RouterStateCommand) {
        try {
          _dispatchCommand(command, replyPort: reply);
        } catch (error, stackTrace) {
          if (reply != null) {
            reply.send(StoreErrorResponse(error.toString()));
          }
          _reportStoreError(error, stackTrace, command: command);
        }
      }
    }
  }

  void _dispatchCommand(RouterStateCommand command, {SendPort? replyPort}) {
    switch (command) {
      case RealmEnsureCommand():
        _getOrCreateRealm(command.realmUri);
      case RealmSnapshotCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: () => _getSnapshot(
            command.realmUri,
            knownVersion: command.knownVersion,
          ),
        );
      case SessionOpenCommand():
        _openSession(command.realmUri, command.session);
      case SessionAllocateIdCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: ids.session.next,
        );
      case SessionCloseCommand():
        _closeSession(command.realmUri, command.sessionId);
      case SubscriptionAddCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: () => _addSubscription(
            command.realmUri,
            command.sessionId,
            command.topic,
            command.matchPolicy,
            command.details,
          ),
        );
      case SubscriptionRemoveCommand():
        _removeSubscription(
          command.realmUri,
          command.sessionId,
          command.subscriptionId,
        );
      case SubscriptionMatchCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: () => _matchSubscriptions(
            command.realmUri,
            command.topic,
            publisherSessionId: command.publisherSessionId,
            options: command.options,
          ),
        );
      case ProcedureRegisterCommand():
        try {
          final registrationId = _registerProcedure(
            command.realmUri,
            command.sessionId,
            command.procedure,
            command.details,
          );
          command.replyPort.send(registrationId);
        } catch (error) {
          if (error is StoreCommandError) {
            command.replyPort.send(StoreErrorResponse(error.toString()));
          } else {
            command.replyPort.send(error);
          }
        }
      case ProcedureUnregisterCommand():
        _unregisterProcedure(
          command.realmUri,
          command.sessionId,
          command.registrationId,
        );
      case InvocationDispatchCommand():
        _handleInvocationDispatch(command);
      case InvocationFindByCallerCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: () => _findInvocationByCaller(
            command.realmUri,
            command.callerSessionId,
            command.requestId,
          ),
        );
      case InvocationCancelCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: () => _cancelInvocation(
            command.realmUri,
            command.invocationId,
            command.mode,
            command.waitForAck,
          ),
        );
      case InvocationGetCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: () => _getInvocation(command.realmUri, command.invocationId),
        );
      case InvocationCompleteCommand():
        final result = _guardedAction(
          command: command,
          action: () =>
              _completeInvocation(command.realmUri, command.invocationId),
        );
        if (command.replyPort != null) {
          command.replyPort!.send(result);
        }
      case InvocationTouchCommand():
        final result = _guardedAction(
          command: command,
          action: () =>
              _touchInvocation(command.realmUri, command.invocationId),
        );
        if (command.replyPort != null) {
          command.replyPort!.send(result);
        }
      case MetricsSnapshotCommand():
        _sendGuardedReply(
          command: command,
          replyPort: command.replyPort,
          action: _collectMetrics,
        );
    }
  }

  void _sendGuardedReply({
    required RouterStateCommand command,
    required SendPort replyPort,
    required Object? Function() action,
  }) {
    try {
      replyPort.send(action());
    } catch (error, stackTrace) {
      replyPort.send(StoreErrorResponse(error.toString()));
      _reportStoreError(error, stackTrace, command: command);
    }
  }

  Object? _guardedAction({
    required RouterStateCommand command,
    required Object? Function() action,
  }) {
    try {
      return action();
    } catch (error, stackTrace) {
      _reportStoreError(error, stackTrace, command: command);
      return StoreErrorResponse(error.toString());
    }
  }

  void _reportStoreError(
    Object error,
    StackTrace stackTrace, {
    RouterStateCommand? command,
  }) {
    if (error is StoreCommandError) {
      return;
    }
    // For now, surface errors to stdout so tests and embedding code can see
    // unexpected failures without silently killing the isolate.
    // In the future we can plug this into a proper logger.
    // ignore: avoid_print
    print(
      'RouterStateStore error handling command $command: $error\n'
      '$stackTrace',
    );
  }

  RouterStateMetrics _collectMetrics() {
    var sessionCount = 0;
    var subscriptionCount = 0;
    var registrationCount = 0;
    var pendingInvocationCount = 0;
    for (final realm in _realms.values) {
      sessionCount += realm.sessions.length;
      subscriptionCount += realm.subscriptionsById.length;
      registrationCount += realm.proceduresById.length;
      pendingInvocationCount += realm.invocations.length;
    }
    _reapExpiredRetryThrottleLeases(DateTime.now());
    return RouterStateMetrics(
      realmCount: _realms.length,
      sessionCount: sessionCount,
      subscriptionCount: subscriptionCount,
      registrationCount: registrationCount,
      pendingInvocationCount: pendingInvocationCount,
      totalInvocationsDispatched: _totalInvocationsDispatched,
      totalPublicationsRouted: _totalPublicationsRouted,
      retryDeduplicationActiveCount:
          _retryThrottleLeases.length + _pendingRetryDebounces.length,
      totalRetryDeduplicationThrottleRejects:
          _totalRetryDeduplicationThrottleRejects,
      totalRetryDeduplicationDebounceReplacements:
          _totalRetryDeduplicationDebounceReplacements,
      totalRetryDeduplicationCapacityRejects:
          _totalRetryDeduplicationCapacityRejects,
      totalRetryDeduplicationExpirations: _totalRetryDeduplicationExpirations,
    );
  }

  RealmRecord _getOrCreateRealm(String realmUri) {
    final existing = _realms[realmUri];
    if (existing != null) {
      return existing;
    }
    final config = _realmConfigs[realmUri];
    if (config == null) {
      throw StateError('Realm $realmUri is not configured');
    }
    final record = RealmRecord(realmUri: realmUri, settings: config);
    _realms[realmUri] = record;
    return record;
  }

  RealmSnapshotResponse _getSnapshot(String realmUri, {int? knownVersion}) {
    final realm = _getOrCreateRealm(realmUri);
    if (knownVersion != null && knownVersion == realm.version) {
      return RealmSnapshotResponse(
        snapshot: realm.lastSnapshot ?? realm.buildSnapshot(),
        isNew: false,
      );
    }
    final snapshot = realm.buildSnapshot();
    realm.lastSnapshot = snapshot;
    return RealmSnapshotResponse(snapshot: snapshot, isNew: true);
  }

  void _openSession(String realmUri, SessionRecord session) {
    final realm = _getOrCreateRealm(realmUri);
    realm.sessions[session.id] = session;
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
    _sessionMetaController.add(
      SessionMetaEvent(
        realmUri: realmUri,
        type: SessionMetaEventType.joined,
        sessionId: session.id,
        authId: session.authId,
        authRole: session.authRole,
        authMethod: session.authMethod,
        authProvider: session.authProvider,
      ),
    );
  }

  void _removeInvocationsForSession(String realmUri, int sessionId) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return;
    }
    final invocationIds = realm.invocations.values
        .where(
          (invocation) =>
              invocation.callerSessionId == sessionId ||
              invocation.calleeSessionId == sessionId,
        )
        .map((invocation) => invocation.invocationId)
        .toList(growable: false);
    for (final invocationId in invocationIds) {
      _cancelInvocationTimeout(realmUri, invocationId);
      realm.invocations.remove(invocationId);
      _releaseRetryThrottleLease(invocationId);
    }
  }

  void _closeSession(String realmUri, int sessionId) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return;
    }
    _cancelPendingRetryDebouncesForCaller(realmUri, sessionId);
    _removeInvocationsForSession(realmUri, sessionId);
    final session = realm.sessions.remove(sessionId);
    if (session == null) {
      return;
    }
    for (final subId in session.subscriptionIds.toList()) {
      _removeSubscription(realmUri, sessionId, subId);
    }
    for (final regId in session.registrationIds.toList()) {
      _unregisterProcedure(realmUri, sessionId, regId);
    }
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
    _sessionMetaController.add(
      SessionMetaEvent(
        realmUri: realmUri,
        type: SessionMetaEventType.left,
        sessionId: session.id,
        authId: session.authId,
        authRole: session.authRole,
        authMethod: session.authMethod,
        authProvider: session.authProvider,
      ),
    );
  }

  int _addSubscription(
    String realmUri,
    int sessionId,
    String topic,
    TopicMatchPolicy matchPolicy,
    Map<String, Object?> details,
  ) {
    final realm = _getOrCreateRealm(realmUri);
    final session =
        realm.sessions[sessionId] ??
        (throw StoreCommandError(
          'Session $sessionId not found in realm $realmUri',
        ));
    final id = ids.subscription.next();
    final entry = realm.findOrCreateSubscription(topic, matchPolicy, id);
    final wasEmpty = entry.subscribers.isEmpty;
    entry.subscribers[sessionId] = SubscriberRecord(
      sessionId: sessionId,
      authRole: session.authRole,
      details: details,
    );
    session.subscriptionIds.add(entry.id);
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
    if (wasEmpty) {
      _subscriptionMetaController.add(
        SubscriptionMetaEvent(
          realmUri: realmUri,
          type: SubscriptionMetaEventType.created,
          subscriptionId: entry.id,
          topic: entry.topic,
          matchPolicy: entry.matchPolicy,
          created: entry.created,
          details: Map<String, Object?>.from(entry.options),
          sessionId: sessionId,
        ),
      );
    }
    _subscriptionMetaController.add(
      SubscriptionMetaEvent(
        realmUri: realmUri,
        type: SubscriptionMetaEventType.subscribed,
        subscriptionId: entry.id,
        topic: entry.topic,
        matchPolicy: entry.matchPolicy,
        created: entry.created,
        details: Map<String, Object?>.from(entry.options),
        sessionId: sessionId,
      ),
    );
    return entry.id;
  }

  void _removeSubscription(String realmUri, int sessionId, int subscriptionId) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return;
    }
    final entry = realm.findSubscriptionById(subscriptionId);
    if (entry == null) {
      return;
    }
    final removed = entry.subscribers.remove(sessionId);
    final session = realm.sessions[sessionId];
    session?.subscriptionIds.remove(subscriptionId);
    if (removed != null) {
      _subscriptionMetaController.add(
        SubscriptionMetaEvent(
          realmUri: realmUri,
          type: SubscriptionMetaEventType.unsubscribed,
          subscriptionId: entry.id,
          topic: entry.topic,
          matchPolicy: entry.matchPolicy,
          created: entry.created,
          details: Map<String, Object?>.from(entry.options),
          sessionId: sessionId,
        ),
      );
    }
    if (entry.subscribers.isEmpty) {
      _subscriptionMetaController.add(
        SubscriptionMetaEvent(
          realmUri: realmUri,
          type: SubscriptionMetaEventType.deleted,
          subscriptionId: entry.id,
          topic: entry.topic,
          matchPolicy: entry.matchPolicy,
          created: entry.created,
          details: Map<String, Object?>.from(entry.options),
          sessionId: sessionId,
        ),
      );
      realm.removeSubscription(entry);
    }
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
  }

  int _registerProcedure(
    String realmUri,
    int sessionId,
    String procedure,
    Map<String, Object?> details,
  ) {
    final realm = _getOrCreateRealm(realmUri);
    final session =
        realm.sessions[sessionId] ??
        (throw StoreCommandError(
          'Session $sessionId not found in realm $realmUri',
        ));
    final policy = _policyFromDetails(details);
    final matchPolicy = _matchPolicyFromDetails(details);
    final retryDeduplication = _retryDeduplicationFromDetails(details);
    final registrationId = ids.registration.next();
    final entry = realm.findOrCreateProcedure(
      procedure,
      registrationId,
      policy,
      matchPolicy,
    );
    final wasEmpty = entry.callees.isEmpty;
    if (!wasEmpty) {
      if (entry.policy == InvocationPolicy.single) {
        throw StoreCommandError('Procedure $procedure already registered');
      }
      if (entry.matchPolicy != matchPolicy) {
        throw StoreCommandError(
          'Procedure $procedure already registered with match policy '
          '${entry.matchPolicy.name}',
        );
      }
      if (policy != entry.policy &&
          details.containsKey('invoke') &&
          entry.policy != InvocationPolicy.single) {
        throw StoreCommandError(
          'Procedure $procedure already registered with policy '
          '${entry.policy.name}',
        );
      }
      final existingRetryDeduplication = _retryDeduplicationForEntry(entry);
      if (!_sameRetryDeduplication(
        existingRetryDeduplication,
        retryDeduplication,
      )) {
        throw StoreCommandError(
          'Procedure $procedure already registered with different '
          'auto_deduplication settings',
        );
      }
    }
    final record = RegistrationRecord(
      registrationId: registrationId,
      procedure: procedure,
      sessionId: sessionId,
      authRole: session.authRole,
      details: details,
      matchPolicy: matchPolicy,
    );
    entry.addCallee(record);
    realm.procedureAtlas.indexRegistration(registrationId, entry);
    realm.proceduresById[registrationId] = entry;
    session.registrationIds.add(registrationId);
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
    if (wasEmpty) {
      _registrationMetaController.add(
        RegistrationMetaEvent(
          realmUri: realmUri,
          type: RegistrationMetaEventType.created,
          registrationId: entry.registrationId,
          procedure: entry.procedure,
          policy: entry.policy,
          matchPolicy: entry.matchPolicy,
          created: entry.created,
          details: Map<String, Object?>.from(record.details),
          sessionId: sessionId,
        ),
      );
    }
    _registrationMetaController.add(
      RegistrationMetaEvent(
        realmUri: realmUri,
        type: RegistrationMetaEventType.registered,
        registrationId: entry.registrationId,
        procedure: entry.procedure,
        policy: entry.policy,
        matchPolicy: entry.matchPolicy,
        created: entry.created,
        details: Map<String, Object?>.from(record.details),
        sessionId: sessionId,
      ),
    );
    return registrationId;
  }

  void _unregisterProcedure(
    String realmUri,
    int sessionId,
    int registrationId,
  ) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return;
    }
    final entry = realm.findProcedureByRegistrationId(registrationId);
    if (entry == null) {
      return;
    }
    final removed = entry.removeCallee(registrationId);
    final session = realm.sessions[sessionId];
    session?.registrationIds.remove(registrationId);
    realm.proceduresById.remove(registrationId);
    realm.procedureAtlas.removeRegistration(registrationId);
    if (removed != null) {
      _registrationMetaController.add(
        RegistrationMetaEvent(
          realmUri: realmUri,
          type: RegistrationMetaEventType.unregistered,
          registrationId: entry.registrationId,
          procedure: entry.procedure,
          policy: entry.policy,
          matchPolicy: entry.matchPolicy,
          created: entry.created,
          details: Map<String, Object?>.from(removed.details),
          sessionId: sessionId,
        ),
      );
    }
    if (entry.callees.isEmpty) {
      _registrationMetaController.add(
        RegistrationMetaEvent(
          realmUri: realmUri,
          type: RegistrationMetaEventType.deleted,
          registrationId: entry.registrationId,
          procedure: entry.procedure,
          policy: entry.policy,
          matchPolicy: entry.matchPolicy,
          created: entry.created,
          details: removed != null
              ? Map<String, Object?>.from(removed.details)
              : const {},
          sessionId: sessionId,
        ),
      );
      _clearRetryDeduplicationForRegistration(
        realmUri,
        entry.registrationId,
      );
      realm.removeProcedure(entry);
    }
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
  }

  void _handleInvocationDispatch(InvocationDispatchCommand command) {
    try {
      final existing = _findInvocationByCaller(
        command.realmUri,
        command.callerSessionId,
        command.requestId,
      );
      if (existing != null) {
        command.replyPort.send(
          _dispatchInvocation(
            command.realmUri,
            command.callerSessionId,
            command.requestId,
            command.procedure,
            command.options,
          ),
        );
        return;
      }

      final transactionHash = _transactionHashFromOptions(command.options);
      final realm = _getOrCreateRealm(command.realmUri);
      final entry = realm.procedureAtlas.match(command.procedure);
      if (transactionHash == null || entry == null || entry.callees.isEmpty) {
        command.replyPort.send(
          _dispatchInvocation(
            command.realmUri,
            command.callerSessionId,
            command.requestId,
            command.procedure,
            command.options,
          ),
        );
        return;
      }

      final policy = _retryDeduplicationForEntry(entry);
      if (policy == null) {
        command.replyPort.send(
          _dispatchInvocation(
            command.realmUri,
            command.callerSessionId,
            command.requestId,
            command.procedure,
            command.options,
          ),
        );
        return;
      }

      final now = DateTime.now();
      _reapExpiredRetryThrottleLeases(now);
      final key = (
        realmUri: command.realmUri,
        registrationId: entry.registrationId,
        transactionHash: transactionHash,
      );
      if (policy.isThrottle) {
        if (_retryThrottleLeases.containsKey(key)) {
          _totalRetryDeduplicationThrottleRejects += 1;
          throw StoreCommandError(wamp.Error.autoDeduplication);
        }
        _ensureRetryDeduplicationCapacity(entry, policy);
        final dispatch = _dispatchInvocation(
          command.realmUri,
          command.callerSessionId,
          command.requestId,
          command.procedure,
          command.options,
        );
        _retryThrottleLeases[key] = _RetryThrottleLease(
          invocationId: dispatch.invocationId,
          expiresAt: now.add(policy.expiry),
        );
        _retryThrottleKeysByInvocation[dispatch.invocationId] = key;
        command.replyPort.send(dispatch);
        return;
      }

      final previous = _pendingRetryDebounces.remove(key);
      final expiresAt = previous?.expiresAt ?? now.add(policy.expiry);
      if (previous != null) {
        previous.timer?.cancel();
        previous.replyPort.send(
          StoreErrorResponse(
            StoreCommandError(wamp.Error.autoDeduplication).toString(),
          ),
        );
        _totalRetryDeduplicationDebounceReplacements += 1;
      } else {
        _ensureRetryDeduplicationCapacity(entry, policy);
      }

      final quietAt = now.add(policy.debounce!);
      final fireAt = quietAt.isBefore(expiresAt) ? quietAt : expiresAt;
      final pending = _PendingRetryDebounce(
        realmUri: command.realmUri,
        callerSessionId: command.callerSessionId,
        requestId: command.requestId,
        procedure: command.procedure,
        options: Map<String, Object?>.from(command.options),
        replyPort: command.replyPort,
        expiresAt: expiresAt,
      );
      _pendingRetryDebounces[key] = pending;
      pending.timer = Timer(
        fireAt.difference(now),
        () => _dispatchPendingRetryDebounce(
          key,
          expired: !quietAt.isBefore(expiresAt),
        ),
      );
    } catch (error, stackTrace) {
      command.replyPort.send(StoreErrorResponse(error.toString()));
      _reportStoreError(error, stackTrace, command: command);
    }
  }

  void _dispatchPendingRetryDebounce(
    _RetryDeduplicationKey key, {
    required bool expired,
  }) {
    final pending = _pendingRetryDebounces.remove(key);
    if (pending == null) {
      return;
    }
    pending.timer?.cancel();
    if (expired) {
      _totalRetryDeduplicationExpirations += 1;
    }
    try {
      final dispatch = _dispatchInvocation(
        pending.realmUri,
        pending.callerSessionId,
        pending.requestId,
        pending.procedure,
        pending.options,
      );
      pending.replyPort.send(dispatch);
    } catch (error, stackTrace) {
      pending.replyPort.send(StoreErrorResponse(error.toString()));
      _reportStoreError(error, stackTrace);
    }
  }

  void _ensureRetryDeduplicationCapacity(
    ProcedureEntry entry,
    wamp.RetryDeduplication policy,
  ) {
    final registrationCount =
        _retryThrottleLeases.keys
            .where((key) => key.registrationId == entry.registrationId)
            .length +
        _pendingRetryDebounces.keys
            .where((key) => key.registrationId == entry.registrationId)
            .length;
    final globalCount =
        _retryThrottleLeases.length + _pendingRetryDebounces.length;
    if (registrationCount >= policy.capacity ||
        globalCount >= _maxGlobalRetryDeduplicationEntries) {
      _totalRetryDeduplicationCapacityRejects += 1;
      throw StoreCommandError(
        '${wamp.Error.autoDeduplication}: capacity exceeded',
      );
    }
  }

  void _reapExpiredRetryThrottleLeases(DateTime now) {
    final expiredKeys = _retryThrottleLeases.entries
        .where((entry) => !entry.value.expiresAt.isAfter(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredKeys) {
      final lease = _retryThrottleLeases.remove(key);
      if (lease == null) {
        continue;
      }
      _retryThrottleKeysByInvocation.remove(lease.invocationId);
      _totalRetryDeduplicationExpirations += 1;
    }
  }

  void _releaseRetryThrottleLease(int invocationId) {
    final key = _retryThrottleKeysByInvocation.remove(invocationId);
    if (key != null) {
      _retryThrottleLeases.remove(key);
    }
  }

  void _cancelPendingRetryDebouncesForCaller(
    String realmUri,
    int callerSessionId,
  ) {
    final keys = _pendingRetryDebounces.entries
        .where(
          (entry) =>
              entry.value.realmUri == realmUri &&
              entry.value.callerSessionId == callerSessionId,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      final pending = _pendingRetryDebounces.remove(key);
      pending?.timer?.cancel();
      pending?.replyPort.send(
        StoreErrorResponse(
          StoreCommandError(
            'Caller session $callerSessionId closed',
          ).toString(),
        ),
      );
    }
  }

  void _clearRetryDeduplicationForRegistration(
    String realmUri,
    int registrationId,
  ) {
    final throttleKeys = _retryThrottleLeases.keys
        .where(
          (key) =>
              key.realmUri == realmUri && key.registrationId == registrationId,
        )
        .toList(growable: false);
    for (final key in throttleKeys) {
      final lease = _retryThrottleLeases.remove(key);
      if (lease != null) {
        _retryThrottleKeysByInvocation.remove(lease.invocationId);
      }
    }

    final debounceKeys = _pendingRetryDebounces.keys
        .where(
          (key) =>
              key.realmUri == realmUri && key.registrationId == registrationId,
        )
        .toList(growable: false);
    for (final key in debounceKeys) {
      final pending = _pendingRetryDebounces.remove(key);
      pending?.timer?.cancel();
      pending?.replyPort.send(
        StoreErrorResponse(
          StoreCommandError('Registration $registrationId removed').toString(),
        ),
      );
    }
  }

  String? _transactionHashFromOptions(Map<String, Object?> options) {
    try {
      return wamp.CallOptions(
        custom: Map<String, dynamic>.from(options),
      ).transactionHash;
    } catch (error) {
      throw StoreCommandError('Invalid transaction_hash: $error');
    }
  }

  wamp.RetryDeduplication? _retryDeduplicationFromDetails(
    Map<String, Object?> details,
  ) {
    try {
      return wamp.RegisterOptions(
        custom: Map<String, dynamic>.from(details),
      ).autoDeduplication;
    } catch (error) {
      throw StoreCommandError('Invalid auto_deduplication: $error');
    }
  }

  wamp.RetryDeduplication? _retryDeduplicationForEntry(
    ProcedureEntry entry,
  ) {
    if (entry.callees.isEmpty) {
      return null;
    }
    return _retryDeduplicationFromDetails(entry.callees.values.first.details);
  }

  bool _sameRetryDeduplication(
    wamp.RetryDeduplication? left,
    wamp.RetryDeduplication? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.debounce == right.debounce &&
        left.capacity == right.capacity &&
        left.expiry == right.expiry;
  }

  InvocationDispatchResult _dispatchInvocation(
    String realmUri,
    int callerSessionId,
    int requestId,
    String procedure,
    Map<String, Object?> options,
  ) {
    final realm = _getOrCreateRealm(realmUri);
    final callerSession =
        realm.sessions[callerSessionId] ??
        (throw StoreCommandError('Caller session $callerSessionId not found'));
    final progress = options['progress'] == true;
    final existing = _findInvocationByCaller(
      realmUri,
      callerSessionId,
      requestId,
    );
    if (existing != null) {
      if (!existing.progressiveInvocationOpen) {
        throw StoreCommandError(
          'Invalid progressive invocation: invocation '
          '${existing.invocationId} is not accepting more chunks',
        );
      }
      if (existing.procedure != procedure) {
        throw StoreCommandError(
          'Invalid progressive invocation: procedure changed from '
          '${existing.procedure} to $procedure',
        );
      }
      existing.progressiveInvocationOpen = progress;
      realm.bumpVersion();
      return InvocationDispatchResult(
        invocationId: existing.invocationId,
        registrationId: existing.registrationId,
        calleeSessionId: existing.calleeSessionId,
        calleeConnectionId: existing.calleeConnectionId!,
        calleeInternalSendPort: existing.calleeInternalSendPort,
        callerInternalSendPort: existing.callerInternalSendPort,
        disclosedCallerSessionId: existing.disclosedCallerSessionId,
        disclosedCallerAuthId: existing.disclosedCallerAuthId,
        disclosedCallerAuthRole: existing.disclosedCallerAuthRole,
        initiatingOptions: Map<String, Object?>.from(
          existing.initiatingOptions,
        ),
        progressiveInvocation: true,
        progress: progress,
        timeoutForwarded: existing.timeoutForwarded,
      );
    }

    final entry = realm.procedureAtlas.match(procedure);
    if (entry == null || entry.callees.isEmpty) {
      throw StoreCommandError('No registration for procedure $procedure');
    }
    final callee = entry.nextCallee();
    if (callee == null) {
      throw StoreCommandError('No available callee for procedure $procedure');
    }
    final invocationId = ids.invocation.next();
    final calleeSession = realm.sessions[callee.sessionId];
    final timeoutValue = options['timeout'];
    if (timeoutValue != null && timeoutValue is! int) {
      throw StoreCommandError('CALL timeout must be an integer');
    }
    if (timeoutValue is int && timeoutValue < 0) {
      throw StoreCommandError('CALL timeout must be >= 0');
    }
    final timeout = timeoutValue is int && timeoutValue > 0
        ? timeoutValue
        : null;
    final timeoutForwarded = callee.details['forward_timeout'] == true;
    final discloseCaller =
        options['disclose_me'] == true ||
        callee.details['disclose_caller'] == true;
    final initiatingOptions = Map<String, Object?>.from(options)
      ..remove('progress')
      ..remove(wamp.CallOptions.transactionHashWireField);
    final calleeConnectionId = _connectionIdForSession(realm, callee.sessionId);
    final record = PendingInvocation(
      invocationId: invocationId,
      registrationId: callee.registrationId,
      procedure: procedure,
      callerRequestId: requestId,
      calleeSessionId: callee.sessionId,
      calleeConnectionId: calleeConnectionId,
      allowProgress: options['receive_progress'] == true,
      callerSessionId: callerSessionId,
      calleeInternalSendPort: calleeSession?.internalSendPort,
      callerInternalSendPort: callerSession.internalSendPort,
      initiatingOptions: initiatingOptions,
      progressiveInvocation: progress,
      progressiveInvocationOpen: progress,
      timeout: timeout,
      timeoutForwarded: timeoutForwarded,
      disclosedCallerSessionId: discloseCaller ? callerSessionId : null,
      disclosedCallerAuthId: discloseCaller ? callerSession.authId : null,
      disclosedCallerAuthRole: discloseCaller ? callerSession.authRole : null,
    );
    realm.invocations[invocationId] = record;
    if (timeout != null && !timeoutForwarded) {
      _scheduleInvocationTimeout(realmUri, record);
    }
    callee.lastInvocation = DateTime.now();
    _totalInvocationsDispatched += 1;
    realm.bumpVersion();
    return InvocationDispatchResult(
      invocationId: invocationId,
      registrationId: callee.registrationId,
      calleeSessionId: callee.sessionId,
      calleeConnectionId: calleeConnectionId,
      calleeInternalSendPort: calleeSession?.internalSendPort,
      callerInternalSendPort: callerSession.internalSendPort,
      disclosedCallerSessionId: record.disclosedCallerSessionId,
      disclosedCallerAuthId: record.disclosedCallerAuthId,
      disclosedCallerAuthRole: record.disclosedCallerAuthRole,
      initiatingOptions: Map<String, Object?>.from(initiatingOptions),
      progressiveInvocation: progress,
      progress: progress,
      timeoutForwarded: timeoutForwarded,
    );
  }

  PendingInvocation? _completeInvocation(
    String realmUri,
    int invocationId,
  ) {
    final realm = _realms[realmUri];
    _cancelInvocationTimeout(realmUri, invocationId);
    final invocation = realm?.invocations.remove(invocationId);
    if (invocation != null) {
      _releaseRetryThrottleLease(invocationId);
    }
    return invocation;
  }

  bool _touchInvocation(String realmUri, int invocationId) {
    final invocation = _realms[realmUri]?.invocations[invocationId];
    if (invocation == null) {
      return false;
    }
    if (invocation.timeout == null || invocation.timeoutForwarded) {
      return true;
    }
    _scheduleInvocationTimeout(realmUri, invocation);
    return true;
  }

  void _scheduleInvocationTimeout(
    String realmUri,
    PendingInvocation invocation,
  ) {
    final timeout = invocation.timeout;
    if (timeout == null || timeout <= 0 || invocation.timeoutForwarded) {
      return;
    }
    final key = (realmUri, invocation.invocationId);
    _invocationTimeouts.remove(key)?.cancel();
    _invocationTimeouts[key] = Timer(
      Duration(milliseconds: timeout),
      () => _expireInvocation(realmUri, invocation.invocationId),
    );
  }

  void _cancelInvocationTimeout(String realmUri, int invocationId) {
    _invocationTimeouts.remove((realmUri, invocationId))?.cancel();
  }

  void _expireInvocation(String realmUri, int invocationId) {
    _invocationTimeouts.remove((realmUri, invocationId));
    final realm = _realms[realmUri];
    final invocation = realm?.invocations.remove(invocationId);
    if (realm == null || invocation == null) {
      return;
    }
    _releaseRetryThrottleLease(invocationId);
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
    final callerSession = realm.sessions[invocation.callerSessionId];
    _invocationTimeoutController.add(
      InvocationTimeoutEvent(
        realmUri: realmUri,
        invocationId: invocation.invocationId,
        callerRequestId: invocation.callerRequestId,
        callerSessionId: invocation.callerSessionId,
        calleeSessionId: invocation.calleeSessionId,
        callerConnectionId: callerSession?.connectionId,
        calleeConnectionId: invocation.calleeConnectionId,
        callerInternalSendPort: invocation.callerInternalSendPort,
        calleeInternalSendPort: invocation.calleeInternalSendPort,
      ),
    );
  }

  PendingInvocation? _getInvocation(String realmUri, int invocationId) {
    final realm = _realms[realmUri];
    return realm?.invocations[invocationId];
  }

  PendingInvocation? _findInvocationByCaller(
    String realmUri,
    int callerSessionId,
    int requestId,
  ) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return null;
    }
    for (final record in realm.invocations.values) {
      if (record.callerSessionId == callerSessionId &&
          record.callerRequestId == requestId) {
        return record;
      }
    }
    return null;
  }

  bool _cancelInvocation(
    String realmUri,
    int invocationId,
    String mode,
    bool waitForAck,
  ) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return false;
    }
    final invocation = realm.invocations[invocationId];
    if (invocation == null) {
      return false;
    }
    invocation.cancelRequested = true;
    invocation.cancelMode = mode;
    invocation.waitForCancelAck = waitForAck;
    _cancelInvocationTimeout(realmUri, invocationId);
    if (!waitForAck) {
      realm.invocations.remove(invocationId);
      _releaseRetryThrottleLease(invocationId);
    }
    return true;
  }

  InvocationPolicy _policyFromDetails(Map<String, Object?> details) {
    final invoke = details['invoke'];
    if (invoke == null) {
      return InvocationPolicy.single;
    }
    if (invoke is! String) {
      throw ArgumentError.value(invoke, 'invoke', 'must be a String');
    }
    switch (invoke) {
      case 'single':
        return InvocationPolicy.single;
      case 'first':
        return InvocationPolicy.first;
      case 'last':
        return InvocationPolicy.last;
      case 'roundrobin':
        return InvocationPolicy.roundRobin;
      case 'random':
        return InvocationPolicy.random;
      default:
        throw ArgumentError.value(
          invoke,
          'invoke',
          'Unsupported invocation policy',
        );
    }
  }

  ProcedureMatchPolicy _matchPolicyFromDetails(Map<String, Object?> details) {
    final raw = details['match'];
    if (raw == null) {
      return ProcedureMatchPolicy.exact;
    }
    if (raw is! String) {
      throw ArgumentError.value(raw, 'match', 'must be a String');
    }
    switch (raw) {
      case 'prefix':
        return ProcedureMatchPolicy.prefix;
      case 'wildcard':
        return ProcedureMatchPolicy.wildcard;
      case 'exact':
      case 'exactly':
        return ProcedureMatchPolicy.exact;
      default:
        throw ArgumentError.value(raw, 'match', 'unsupported match policy');
    }
  }

  PublicationRouting _matchSubscriptions(
    String realmUri,
    String topic, {
    required int publisherSessionId,
    required Map<String, Object?> options,
  }) {
    _totalPublicationsRouted += 1;
    final realm = _getOrCreateRealm(realmUri);
    final matches = <SubscriptionMatch>[];
    final publicationId = ids.publication.next();
    final excludeMe = options['exclude_me'] == true;
    final excludeIds = _decodeIdSet(options['exclude']);
    final eligibleIds = _decodeIdSet(options['eligible']);
    final excludeAuthIds =
        _decodeStringSet(options['exclude_authid']) ??
        _decodeStringSet(options['exclude_authids']);
    final excludeAuthRoles =
        _decodeStringSet(options['exclude_authrole']) ??
        _decodeStringSet(options['exclude_authroles']);
    final eligibleAuthIds =
        _decodeStringSet(options['eligible_authid']) ??
        _decodeStringSet(options['eligible_authids']);
    final eligibleAuthRoles =
        _decodeStringSet(options['eligible_authrole']) ??
        _decodeStringSet(options['eligible_authroles']);
    final entries = realm.subscriptionAtlas.match(topic);
    for (final entry in entries) {
      entry.subscribers.forEach((sessionId, record) {
        if (excludeMe && sessionId == publisherSessionId) {
          return;
        }
        if (excludeIds != null && excludeIds.contains(sessionId)) {
          return;
        }
        if (eligibleIds != null && !eligibleIds.contains(sessionId)) {
          return;
        }
        final session = realm.sessions[sessionId];
        if (session == null) {
          return;
        }
        final recordAuthId = session.authId;
        if (excludeAuthIds != null &&
            recordAuthId != null &&
            excludeAuthIds.contains(recordAuthId)) {
          return;
        }
        if (eligibleAuthIds != null &&
            (recordAuthId == null || !eligibleAuthIds.contains(recordAuthId))) {
          return;
        }
        final recordAuthRole = record.authRole ?? session.authRole;
        if (excludeAuthRoles != null &&
            recordAuthRole != null &&
            excludeAuthRoles.contains(recordAuthRole)) {
          return;
        }
        if (eligibleAuthRoles != null &&
            (recordAuthRole == null ||
                !eligibleAuthRoles.contains(recordAuthRole))) {
          return;
        }
        matches.add(
          SubscriptionMatch(
            subscriptionId: entry.id,
            sessionId: sessionId,
            connectionId: session.connectionId,
            internalSendPort: session.internalSendPort,
            authRole: record.authRole,
            details: Map<String, Object?>.from(record.details),
          ),
        );
      });
    }
    return PublicationRouting(publicationId: publicationId, matches: matches);
  }

  int _connectionIdForSession(RealmRecord realm, int sessionId) {
    final session = realm.sessions[sessionId];
    if (session == null) {
      throw StateError(
        'Session $sessionId not found in realm ${realm.realmUri}',
      );
    }
    return session.connectionId;
  }

  Set<int>? _decodeIdSet(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Iterable) {
      final set = <int>{};
      for (final element in value) {
        final id = element is int ? element : int.tryParse('$element');
        if (id != null) {
          set.add(id);
        }
      }
      return set;
    }
    return null;
  }

  Set<String>? _decodeStringSet(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Iterable) {
      final set = <String>{};
      for (final element in value) {
        if (element == null) {
          continue;
        }
        final str = element.toString();
        if (str.isNotEmpty) {
          set.add(str);
        }
      }
      return set;
    }
    return null;
  }
}

typedef _RetryDeduplicationKey = ({
  String realmUri,
  int registrationId,
  String transactionHash,
});

class _RetryThrottleLease {
  const _RetryThrottleLease({
    required this.invocationId,
    required this.expiresAt,
  });

  final int invocationId;
  final DateTime expiresAt;
}

class _PendingRetryDebounce {
  _PendingRetryDebounce({
    required this.realmUri,
    required this.callerSessionId,
    required this.requestId,
    required this.procedure,
    required this.options,
    required this.replyPort,
    required this.expiresAt,
  });

  final String realmUri;
  final int callerSessionId;
  final int requestId;
  final String procedure;
  final Map<String, Object?> options;
  final SendPort replyPort;
  final DateTime expiresAt;
  Timer? timer;
}

/// Holds all mutable state for a single realm.
class RealmRecord {
  RealmRecord({required this.realmUri, required this.settings});

  final String realmUri;
  final RealmSettings settings;

  int version = 0;
  RealmSnapshot? lastSnapshot;
  final Map<int, SessionRecord> sessions = SplayTreeMap<int, SessionRecord>();
  final SubscriptionAtlas subscriptionAtlas = SubscriptionAtlas();
  final ProcedureAtlas procedureAtlas = ProcedureAtlas();
  final Map<int, SubscriptionEntry> subscriptionsById = {};
  final Map<int, ProcedureEntry> proceduresById = {};
  final Map<int, PendingInvocation> invocations = {};

  void bumpVersion() {
    version += 1;
    lastSnapshot = null;
  }

  SubscriptionEntry findOrCreateSubscription(
    String topic,
    TopicMatchPolicy policy,
    int id,
  ) {
    SubscriptionEntry? entry;
    switch (policy) {
      case TopicMatchPolicy.exact:
        entry = subscriptionAtlas.exact[topic];
        break;
      case TopicMatchPolicy.prefix:
        entry = subscriptionAtlas.prefixes[topic];
        break;
      case TopicMatchPolicy.wildcard:
        entry = subscriptionAtlas.wildcards[topic];
        break;
    }
    if (entry != null) {
      return entry;
    }
    final newEntry = SubscriptionEntry(
      id: id,
      topic: topic,
      matchPolicy: policy,
    );
    subscriptionsById[id] = newEntry;
    switch (policy) {
      case TopicMatchPolicy.exact:
        subscriptionAtlas.exact[topic] = newEntry;
        break;
      case TopicMatchPolicy.prefix:
        subscriptionAtlas.prefixes[topic] = newEntry;
        break;
      case TopicMatchPolicy.wildcard:
        subscriptionAtlas.wildcards[topic] = newEntry;
        break;
    }
    return newEntry;
  }

  SubscriptionEntry? findSubscriptionById(int id) => subscriptionsById[id];

  void removeSubscription(SubscriptionEntry entry) {
    subscriptionsById.remove(entry.id);
    switch (entry.matchPolicy) {
      case TopicMatchPolicy.exact:
        subscriptionAtlas.exact.remove(entry.topic);
        break;
      case TopicMatchPolicy.prefix:
        subscriptionAtlas.prefixes.remove(entry.topic);
        break;
      case TopicMatchPolicy.wildcard:
        subscriptionAtlas.wildcards.remove(entry.topic);
        break;
    }
  }

  ProcedureEntry findOrCreateProcedure(
    String procedure,
    int registrationId,
    InvocationPolicy policy,
    ProcedureMatchPolicy matchPolicy,
  ) => procedureAtlas.findOrCreate(
    procedure: procedure,
    matchPolicy: matchPolicy,
    registrationId: registrationId,
    invocationPolicy: policy,
  );

  ProcedureEntry? findProcedureByRegistrationId(int registrationId) =>
      procedureAtlas.findByRegistrationId(registrationId);

  void removeProcedure(ProcedureEntry entry) {
    for (final registrationId in entry.callees.keys.toList()) {
      proceduresById.remove(registrationId);
      procedureAtlas.removeRegistration(registrationId);
    }
    proceduresById.remove(entry.registrationId);
    procedureAtlas.removeRegistration(entry.registrationId);
  }

  RealmSnapshot buildSnapshot() {
    final sessionSnapshots = sessions.values.map((session) {
      return SessionInfo(
        id: session.id,
        authId: session.authId,
        authRole: session.authRole,
        authMethod: session.authMethod,
        authProvider: session.authProvider,
        roles: Map.unmodifiable(session.roles),
        workerId: session.workerId,
        connectionId: session.connectionId,
        lastActivity: session.lastActivity,
        protocol: session.protocol,
      );
    }).toList();
    final subscriptionSnapshots = subscriptionsById.values.map((entry) {
      return SubscriptionSnapshot(
        id: entry.id,
        topic: entry.topic,
        matchPolicy: entry.matchPolicy,
        subscribers: entry.subscribers.values.toList(growable: false),
        options: Map.unmodifiable(entry.options),
        created: entry.created,
      );
    }).toList();
    final registrationSnapshots = procedureAtlas.values.map((entry) {
      return RegistrationSnapshot(
        registrationId: entry.registrationId,
        procedure: entry.procedure,
        policy: entry.policy,
        matchPolicy: entry.matchPolicy,
        callees: entry.callees.values.toList(growable: false),
        created: entry.created,
      );
    }).toList();
    return RealmSnapshot(
      realmUri: realmUri,
      version: version,
      sessions: sessionSnapshots,
      subscriptions: subscriptionSnapshots,
      registrations: registrationSnapshots,
    );
  }
}

/// Result of an invocation dispatch request.
class InvocationDispatchResult {
  InvocationDispatchResult({
    required this.invocationId,
    required this.registrationId,
    required this.calleeSessionId,
    required this.calleeConnectionId,
    this.calleeInternalSendPort,
    this.callerInternalSendPort,
    this.disclosedCallerSessionId,
    this.disclosedCallerAuthId,
    this.disclosedCallerAuthRole,
    this.initiatingOptions = const {},
    this.progressiveInvocation = false,
    this.progress = false,
    this.timeoutForwarded = false,
  });

  final int invocationId;
  final int registrationId;
  final int calleeSessionId;
  final int calleeConnectionId;
  final SendPort? calleeInternalSendPort;
  final SendPort? callerInternalSendPort;
  final int? disclosedCallerSessionId;
  final String? disclosedCallerAuthId;
  final String? disclosedCallerAuthRole;
  final Map<String, Object?> initiatingOptions;
  final bool progressiveInvocation;
  final bool progress;
  final bool timeoutForwarded;
}
