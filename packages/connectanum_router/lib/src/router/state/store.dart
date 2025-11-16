import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import '../config/router_settings.dart';
import 'commands.dart';
import 'ids.dart';
import 'procedure.dart';
import 'session.dart';
import 'snapshot.dart';
import 'subscription.dart';

/// Maintains all WAMP realm/session/subscription/registration state.
class RouterStateStore {
  RouterStateStore({required this.settings})
    : _commandPort = ReceivePort(),
      _eventController = StreamController<StateChangedEvent>.broadcast(),
      _subscriptionMetaController =
          StreamController<SubscriptionMetaEvent>.broadcast(),
      _registrationMetaController =
          StreamController<RegistrationMetaEvent>.broadcast(),
      _realmConfigs = Map.fromEntries(
        settings.realms.map((realm) => MapEntry(realm.name, realm)),
      );

  final RouterSettings settings;

  final ReceivePort _commandPort;
  final StreamController<StateChangedEvent> _eventController;
  final StreamController<SubscriptionMetaEvent> _subscriptionMetaController;
  final StreamController<RegistrationMetaEvent> _registrationMetaController;
  final WampIdAllocatorRegistry ids = WampIdAllocatorRegistry();
  final Map<String, RealmRecord> _realms = {};
  final Map<String, RealmSettings> _realmConfigs;
  int _totalInvocationsDispatched = 0;
  int _totalPublicationsRouted = 0;

  Stream<StateChangedEvent> get events => _eventController.stream;
  Stream<SubscriptionMetaEvent> get subscriptionMetaEvents =>
      _subscriptionMetaController.stream;
  Stream<RegistrationMetaEvent> get registrationMetaEvents =>
      _registrationMetaController.stream;
  SendPort get commandPort => _commandPort.sendPort;

  void start() {
    _commandPort.listen(_handleMessage);
  }

  void dispose() {
    _commandPort.close();
    _eventController.close();
    _subscriptionMetaController.close();
    _registrationMetaController.close();
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
          command.replyPort.send(error);
        }
      case ProcedureUnregisterCommand():
        _unregisterProcedure(
          command.realmUri,
          command.sessionId,
          command.registrationId,
        );
      case InvocationDispatchCommand():
        try {
          final dispatch = _dispatchInvocation(
            command.realmUri,
            command.callerSessionId,
            command.requestId,
            command.procedure,
            command.options,
          );
          command.replyPort.send(dispatch);
        } catch (error) {
          command.replyPort.send(StoreErrorResponse(error.toString()));
          _reportStoreError(
            error,
            StackTrace.current,
            command: command,
          );
        }
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
    return RouterStateMetrics(
      realmCount: _realms.length,
      sessionCount: sessionCount,
      subscriptionCount: subscriptionCount,
      registrationCount: registrationCount,
      pendingInvocationCount: pendingInvocationCount,
      totalInvocationsDispatched: _totalInvocationsDispatched,
      totalPublicationsRouted: _totalPublicationsRouted,
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
  }

  void _closeSession(String realmUri, int sessionId) {
    final realm = _realms[realmUri];
    if (realm == null) {
      return;
    }
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
        (throw StateError('Session $sessionId not found in realm $realmUri'));
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
        (throw StateError('Session $sessionId not found in realm $realmUri'));
    final policy = _policyFromDetails(details);
    final matchPolicy = _matchPolicyFromDetails(details);
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
        throw StateError('Procedure $procedure already registered');
      }
      if (entry.matchPolicy != matchPolicy) {
        throw StateError(
          'Procedure $procedure already registered with match policy '
          '${entry.matchPolicy.name}',
        );
      }
      if (policy != entry.policy &&
          details.containsKey('invoke') &&
          entry.policy != InvocationPolicy.single) {
        throw StateError(
          'Procedure $procedure already registered with policy '
          '${entry.policy.name}',
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
          registrationId: record.registrationId,
          procedure: entry.procedure,
          policy: entry.policy,
          details: Map<String, Object?>.from(record.details),
          sessionId: sessionId,
        ),
      );
    }
    _registrationMetaController.add(
      RegistrationMetaEvent(
        realmUri: realmUri,
        type: RegistrationMetaEventType.registered,
        registrationId: record.registrationId,
        procedure: entry.procedure,
        policy: entry.policy,
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
          registrationId: removed.registrationId,
          procedure: entry.procedure,
          policy: entry.policy,
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
          registrationId: removed?.registrationId ?? registrationId,
          procedure: entry.procedure,
          policy: entry.policy,
          details: removed != null
              ? Map<String, Object?>.from(removed.details)
              : const {},
          sessionId: sessionId,
        ),
      );
      realm.removeProcedure(entry);
    }
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
    );
  }

  InvocationDispatchResult _dispatchInvocation(
    String realmUri,
    int callerSessionId,
    int requestId,
    String procedure,
    Map<String, Object?> options,
  ) {
    final realm = _getOrCreateRealm(realmUri);
    final entry = realm.procedureAtlas.match(procedure);
    if (entry == null || entry.callees.isEmpty) {
      throw StateError('No registration for procedure $procedure');
    }
    final callee = entry.nextCallee();
    if (callee == null) {
      throw StateError('No available callee for procedure $procedure');
    }
    final invocationId = ids.invocation.next();
    if (!realm.sessions.containsKey(callerSessionId)) {
      throw StateError('Caller session $callerSessionId not found');
    }
    final callerSession = realm.sessions[callerSessionId];
    final calleeSession = realm.sessions[callee.sessionId];
    final record = PendingInvocation(
      invocationId: invocationId,
      registrationId: callee.registrationId,
      callerRequestId: requestId,
      calleeSessionId: callee.sessionId,
      calleeConnectionId: _connectionIdForSession(realm, callee.sessionId),
      allowProgress: options['receive_progress'] == true,
      callerSessionId: callerSessionId,
      calleeInternalSendPort: calleeSession?.internalSendPort,
      callerInternalSendPort: callerSession?.internalSendPort,
    );
    realm.invocations[invocationId] = record;
    callee.lastInvocation = DateTime.now();
    _totalInvocationsDispatched += 1;
    realm.bumpVersion();
    return InvocationDispatchResult(
      invocationId: invocationId,
      registrationId: callee.registrationId,
      calleeSessionId: callee.sessionId,
      calleeConnectionId: _connectionIdForSession(realm, callee.sessionId),
      calleeInternalSendPort: calleeSession?.internalSendPort,
      callerInternalSendPort: callerSession?.internalSendPort,
    );
  }

  PendingInvocation? _completeInvocation(String realmUri, int invocationId) {
    final realm = _realms[realmUri];
    return realm?.invocations.remove(invocationId);
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
    if (!waitForAck) {
      realm.invocations.remove(invocationId);
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
    final excludeAuthRoles = _decodeStringSet(options['exclude_authroles']);
    final eligibleAuthRoles = _decodeStringSet(options['eligible_authroles']);
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
        final recordAuthRole = record.authRole;
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
        final session = realm.sessions[sessionId];
        if (session == null) {
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
      );
    }).toList();
    final registrationSnapshots = procedureAtlas.values.map((entry) {
      return RegistrationSnapshot(
        registrationId: entry.registrationId,
        procedure: entry.procedure,
        policy: entry.policy,
        matchPolicy: entry.matchPolicy,
        callees: entry.callees.values.toList(growable: false),
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
  });

  final int invocationId;
  final int registrationId;
  final int calleeSessionId;
  final int calleeConnectionId;
  final SendPort? calleeInternalSendPort;
  final SendPort? callerInternalSendPort;
}
