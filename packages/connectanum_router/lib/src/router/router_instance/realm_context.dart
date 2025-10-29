part of '../router_instance.dart';

/// Provides cached access to realm state and forwards mutations to the boss
/// isolate via the router state store.
class RealmContext {
  RealmContext({required this.realmUri, required this.statePort});

  final String realmUri;
  final SendPort statePort;
  RealmSnapshot? _snapshot;
  int? _version;

  Future<RealmSnapshot> ensureSnapshot({bool forceRefresh = false}) async {
    if (!forceRefresh && _snapshot != null) {
      return _snapshot!;
    }
    final response = await _requestSnapshot(
      knownVersion: forceRefresh ? null : _version,
    );
    if (response.isNew || _snapshot == null) {
      _snapshot = response.snapshot;
      _version = response.snapshot.version;
    }
    return _snapshot!;
  }

  Future<int> addSubscription({
    required int sessionId,
    required String topic,
    required TopicMatchPolicy matchPolicy,
    Map<String, Object?> details = const {},
  }) async {
    final completer = Completer<int>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as int);
    });
    statePort.send(
      SubscriptionAddCommand(
        realmUri: realmUri,
        sessionId: sessionId,
        topic: topic,
        matchPolicy: matchPolicy,
        details: details,
        replyPort: replyPort.sendPort,
      ),
    );
    final id = await completer.future;
    await ensureSnapshot(forceRefresh: true);
    return id;
  }

  Future<void> removeSubscription({
    required int sessionId,
    required int subscriptionId,
  }) async {
    statePort.send(
      SubscriptionRemoveCommand(
        realmUri: realmUri,
        sessionId: sessionId,
        subscriptionId: subscriptionId,
      ),
    );
    await ensureSnapshot(forceRefresh: true);
  }

  Future<int> registerProcedure({
    required int sessionId,
    required String procedure,
    Map<String, Object?> details = const {},
  }) async {
    final completer = Completer<int>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      if (message is int) {
        completer.complete(message);
      } else if (message is StoreErrorResponse) {
        completer.completeError(StateError(message.message));
      } else if (message is Exception) {
        completer.completeError(message);
      } else if (message is Error) {
        completer.completeError(message);
      } else {
        completer.completeError(
          StateError('Unexpected register response: $message'),
        );
      }
    });
    statePort.send(
      ProcedureRegisterCommand(
        realmUri: realmUri,
        sessionId: sessionId,
        procedure: procedure,
        details: details,
        replyPort: replyPort.sendPort,
      ),
    );
    final registrationId = await completer.future;
    await ensureSnapshot(forceRefresh: true);
    return registrationId;
  }

  Future<void> unregisterProcedure({
    required int sessionId,
    required int registrationId,
  }) async {
    statePort.send(
      ProcedureUnregisterCommand(
        realmUri: realmUri,
        sessionId: sessionId,
        registrationId: registrationId,
      ),
    );
    await ensureSnapshot(forceRefresh: true);
  }

  Future<PublicationRouting> matchSubscriptions({
    required int publisherSessionId,
    required String topic,
    Map<String, Object?> options = const {},
  }) async {
    final completer = Completer<PublicationRouting>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as PublicationRouting);
    });
    statePort.send(
      SubscriptionMatchCommand(
        realmUri: realmUri,
        topic: topic,
        publisherSessionId: publisherSessionId,
        options: options,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  Future<InvocationDispatchResult> dispatchInvocation({
    required int callerSessionId,
    required int requestId,
    required String procedure,
    Map<String, Object?> options = const {},
  }) async {
    final completer = Completer<InvocationDispatchResult>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      if (message is InvocationDispatchResult) {
        completer.complete(message);
      } else if (message is StoreErrorResponse) {
        completer.completeError(StateError(message.message));
      } else if (message is Error) {
        completer.completeError(message);
      } else {
        completer.completeError(
          StateError('Unexpected invocation response: $message'),
        );
      }
    });
    statePort.send(
      InvocationDispatchCommand(
        realmUri: realmUri,
        callerSessionId: callerSessionId,
        requestId: requestId,
        procedure: procedure,
        options: options,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  Future<PendingInvocation?> getInvocation(int invocationId) async {
    final completer = Completer<PendingInvocation?>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as PendingInvocation?);
    });
    statePort.send(
      InvocationGetCommand(
        realmUri: realmUri,
        invocationId: invocationId,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  Future<PendingInvocation?> findInvocationByCaller({
    required int callerSessionId,
    required int requestId,
  }) async {
    final completer = Completer<PendingInvocation?>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as PendingInvocation?);
    });
    statePort.send(
      InvocationFindByCallerCommand(
        realmUri: realmUri,
        callerSessionId: callerSessionId,
        requestId: requestId,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  Future<bool> cancelInvocation({
    required int invocationId,
    required String mode,
    required bool waitForAck,
  }) async {
    final completer = Completer<bool>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as bool);
    });
    statePort.send(
      InvocationCancelCommand(
        realmUri: realmUri,
        invocationId: invocationId,
        mode: mode,
        waitForAck: waitForAck,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  Future<PendingInvocation?> completeInvocation(int invocationId) async {
    final completer = Completer<PendingInvocation?>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as PendingInvocation?);
    });
    statePort.send(
      InvocationCompleteCommand(
        realmUri: realmUri,
        invocationId: invocationId,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  Future<RealmSnapshotResponse> _requestSnapshot({int? knownVersion}) async {
    final completer = Completer<RealmSnapshotResponse>();
    final replyPort = ReceivePort();
    replyPort.listen((dynamic message) {
      replyPort.close();
      completer.complete(message as RealmSnapshotResponse);
    });
    statePort.send(
      RealmSnapshotCommand(
        realmUri: realmUri,
        knownVersion: knownVersion,
        replyPort: replyPort.sendPort,
      ),
    );
    return completer.future;
  }

  void invalidate() {
    _snapshot = null;
  }
}

/// Simple cache that manages [RealmContext] instances per realm.
class RealmContextCache {
  RealmContextCache({required this.statePort});

  final SendPort statePort;
  final Map<String, RealmContext> _contexts = {};

  RealmContext contextFor(String realmUri) => _contexts.putIfAbsent(
    realmUri,
    () => RealmContext(realmUri: realmUri, statePort: statePort),
  );

  void invalidate(String realmUri) {
    _contexts[realmUri]?.invalidate();
  }

  void dispose() {
    _contexts.clear();
  }
}
