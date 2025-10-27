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
      _realmConfigs = Map.fromEntries(
        settings.realms.map((realm) => MapEntry(realm.name, realm)),
      );

  final RouterSettings settings;

  final ReceivePort _commandPort;
  final StreamController<StateChangedEvent> _eventController;
  final WampIdAllocatorRegistry ids = WampIdAllocatorRegistry();
  final Map<String, RealmRecord> _realms = {};
  final Map<String, RealmSettings> _realmConfigs;

  Stream<StateChangedEvent> get events => _eventController.stream;
  SendPort get commandPort => _commandPort.sendPort;

  void start() {
    _commandPort.listen(_handleMessage);
  }

  void dispose() {
    _commandPort.close();
    _eventController.close();
    _realms.clear();
  }

  void _handleMessage(dynamic message) {
    if (message is RouterStateCommand) {
      _dispatchCommand(message);
    } else if (message is List && message.length == 2) {
      final command = message[0];
      final reply = message[1] as SendPort?;
      if (command is RouterStateCommand) {
        _dispatchCommand(command, replyPort: reply);
      }
    }
  }

  void _dispatchCommand(RouterStateCommand command, {SendPort? replyPort}) {
    switch (command) {
      case RealmEnsureCommand():
        _getOrCreateRealm(command.realmUri);
      case RealmSnapshotCommand():
        final snapshot = _getSnapshot(
          command.realmUri,
          knownVersion: command.knownVersion,
        );
        command.replyPort.send(snapshot);
      case SessionOpenCommand():
        _openSession(command.realmUri, command.session);
      case SessionAllocateIdCommand():
        command.replyPort.send(ids.session.next());
      case SessionCloseCommand():
        _closeSession(command.realmUri, command.sessionId);
      case SubscriptionAddCommand():
        final subscriptionId = _addSubscription(
          command.realmUri,
          command.sessionId,
          command.topic,
          command.matchPolicy,
          command.details,
        );
        command.replyPort.send(subscriptionId);
      case SubscriptionRemoveCommand():
        _removeSubscription(
          command.realmUri,
          command.sessionId,
          command.subscriptionId,
        );
      case SubscriptionMatchCommand():
        final routing = _matchSubscriptions(
          command.realmUri,
          command.topic,
          publisherSessionId: command.publisherSessionId,
          options: command.options,
        );
        command.replyPort.send(routing);
      case ProcedureRegisterCommand():
        final registrationId = _registerProcedure(
          command.realmUri,
          command.sessionId,
          command.procedure,
          command.details,
        );
        command.replyPort.send(registrationId);
      case ProcedureUnregisterCommand():
        _unregisterProcedure(
          command.realmUri,
          command.sessionId,
          command.registrationId,
        );
      case InvocationDispatchCommand():
        final dispatch = _dispatchInvocation(
          command.realmUri,
          command.callerSessionId,
          command.requestId,
          command.procedure,
          command.options,
        );
        command.replyPort.send(dispatch);
      case InvocationFindByCallerCommand():
        final record = _findInvocationByCaller(
          command.realmUri,
          command.callerSessionId,
          command.requestId,
        );
        command.replyPort.send(record);
      case InvocationGetCommand():
        final record = _getInvocation(command.realmUri, command.invocationId);
        command.replyPort.send(record);
      case InvocationCompleteCommand():
        final record = _completeInvocation(
          command.realmUri,
          command.invocationId,
        );
        command.replyPort?.send(record);
    }
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
    entry.subscribers.remove(sessionId);
    final session = realm.sessions[sessionId];
    session?.subscriptionIds.remove(subscriptionId);
    if (entry.subscribers.isEmpty) {
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
    final registrationId = ids.registration.next();
    final entry = realm.findOrCreateProcedure(procedure, registrationId);
    entry.callees[registrationId] = RegistrationRecord(
      registrationId: registrationId,
      procedure: procedure,
      sessionId: sessionId,
      authRole: session.authRole,
      details: details,
    );
    session.registrationIds.add(registrationId);
    realm.bumpVersion();
    _eventController.add(
      StateChangedEvent(realmUri: realmUri, version: realm.version),
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
    entry.callees.remove(registrationId);
    final session = realm.sessions[sessionId];
    session?.registrationIds.remove(registrationId);
    if (entry.callees.isEmpty) {
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
    final bucket = realm.procedureAtlas[procedure];
    if (bucket == null || bucket.callees.isEmpty) {
      throw StateError('No registration for procedure $procedure');
    }
    final callee = bucket.nextCallee();
    if (callee == null) {
      throw StateError('No available callee for procedure $procedure');
    }
    final invocationId = ids.invocation.next();
    if (!realm.sessions.containsKey(callerSessionId)) {
      throw StateError('Caller session $callerSessionId not found');
    }
    final record = PendingInvocation(
      invocationId: invocationId,
      registrationId: bucket.registrationId,
      callerRequestId: requestId,
      calleeSessionId: callee.sessionId,
      allowProgress: options['receive_progress'] == true,
      callerSessionId: callerSessionId,
    );
    realm.invocations[invocationId] = record;
    callee.lastInvocation = DateTime.now();
    realm.bumpVersion();
    return InvocationDispatchResult(
      invocationId: invocationId,
      registrationId: bucket.registrationId,
      calleeSessionId: callee.sessionId,
      calleeConnectionId: _connectionIdForSession(realm, callee.sessionId),
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

  PublicationRouting _matchSubscriptions(
    String realmUri,
    String topic, {
    required int publisherSessionId,
    required Map<String, Object?> options,
  }) {
    final realm = _getOrCreateRealm(realmUri);
    final matches = <SubscriptionMatch>[];
    final publicationId = ids.publication.next();
    final excludeMe = options['exclude_me'] == true;
    final excludeIds = _decodeIdSet(options['exclude']);
    final eligibleIds = _decodeIdSet(options['eligible']);
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
        matches.add(
          SubscriptionMatch(
            subscriptionId: entry.id,
            sessionId: sessionId,
            connectionId: session.connectionId,
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
  final Map<String, ProcedureEntry> procedureAtlas = {};
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

  ProcedureEntry findOrCreateProcedure(String procedure, int registrationId) {
    final entry = procedureAtlas.putIfAbsent(
      procedure,
      () =>
          ProcedureEntry(registrationId: registrationId, procedure: procedure),
    );
    proceduresById[entry.registrationId] = entry;
    return entry;
  }

  ProcedureEntry? findProcedureByRegistrationId(int registrationId) =>
      proceduresById[registrationId];

  void removeProcedure(ProcedureEntry entry) {
    proceduresById.remove(entry.registrationId);
    procedureAtlas.remove(entry.procedure);
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
  });

  final int invocationId;
  final int registrationId;
  final int calleeSessionId;
  final int calleeConnectionId;
}
