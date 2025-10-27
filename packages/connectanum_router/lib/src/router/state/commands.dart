import 'dart:isolate';

import 'session.dart';
import 'subscription.dart';

/// Base type for all commands handled by [RouterStateStore].
abstract class RouterStateCommand {}

class RealmEnsureCommand extends RouterStateCommand {
  RealmEnsureCommand({required this.realmUri, required this.options});

  final String realmUri;
  final Map<String, Object?> options;
}

class RealmSnapshotCommand extends RouterStateCommand {
  RealmSnapshotCommand({
    required this.realmUri,
    required this.knownVersion,
    required this.replyPort,
  });

  final String realmUri;
  final int? knownVersion;
  final SendPort replyPort;
}

class SessionOpenCommand extends RouterStateCommand {
  SessionOpenCommand({required this.realmUri, required this.session});

  final String realmUri;
  final SessionRecord session;
}

class SessionAllocateIdCommand extends RouterStateCommand {
  SessionAllocateIdCommand({required this.replyPort});

  final SendPort replyPort;
}

class SessionCloseCommand extends RouterStateCommand {
  SessionCloseCommand({required this.realmUri, required this.sessionId});

  final String realmUri;
  final int sessionId;
}

class SubscriptionAddCommand extends RouterStateCommand {
  SubscriptionAddCommand({
    required this.realmUri,
    required this.sessionId,
    required this.topic,
    required this.matchPolicy,
    required this.details,
    required this.replyPort,
  });

  final String realmUri;
  final int sessionId;
  final String topic;
  final TopicMatchPolicy matchPolicy;
  final Map<String, Object?> details;
  final SendPort replyPort;
}

class SubscriptionRemoveCommand extends RouterStateCommand {
  SubscriptionRemoveCommand({
    required this.realmUri,
    required this.sessionId,
    required this.subscriptionId,
  });

  final String realmUri;
  final int sessionId;
  final int subscriptionId;
}

class SubscriptionMatchCommand extends RouterStateCommand {
  SubscriptionMatchCommand({
    required this.realmUri,
    required this.topic,
    required this.publisherSessionId,
    required this.options,
    required this.replyPort,
  });

  final String realmUri;
  final String topic;
  final int publisherSessionId;
  final Map<String, Object?> options;
  final SendPort replyPort;
}

class ProcedureRegisterCommand extends RouterStateCommand {
  ProcedureRegisterCommand({
    required this.realmUri,
    required this.sessionId,
    required this.procedure,
    required this.details,
    required this.replyPort,
  });

  final String realmUri;
  final int sessionId;
  final String procedure;
  final Map<String, Object?> details;
  final SendPort replyPort;
}

class ProcedureUnregisterCommand extends RouterStateCommand {
  ProcedureUnregisterCommand({
    required this.realmUri,
    required this.sessionId,
    required this.registrationId,
  });

  final String realmUri;
  final int sessionId;
  final int registrationId;
}

class InvocationDispatchCommand extends RouterStateCommand {
  InvocationDispatchCommand({
    required this.realmUri,
    required this.callerSessionId,
    required this.requestId,
    required this.procedure,
    required this.options,
    required this.replyPort,
  });

  final String realmUri;
  final int callerSessionId;
  final int requestId;
  final String procedure;
  final Map<String, Object?> options;
  final SendPort replyPort;
}

class InvocationGetCommand extends RouterStateCommand {
  InvocationGetCommand({
    required this.realmUri,
    required this.invocationId,
    required this.replyPort,
  });

  final String realmUri;
  final int invocationId;
  final SendPort replyPort;
}

class InvocationFindByCallerCommand extends RouterStateCommand {
  InvocationFindByCallerCommand({
    required this.realmUri,
    required this.callerSessionId,
    required this.requestId,
    required this.replyPort,
  });

  final String realmUri;
  final int callerSessionId;
  final int requestId;
  final SendPort replyPort;
}

class InvocationCompleteCommand extends RouterStateCommand {
  InvocationCompleteCommand({
    required this.realmUri,
    required this.invocationId,
    this.replyPort,
  });

  final String realmUri;
  final int invocationId;
  final SendPort? replyPort;
}

class StateChangedEvent {
  StateChangedEvent({required this.realmUri, required this.version});

  final String realmUri;
  final int version;
}
