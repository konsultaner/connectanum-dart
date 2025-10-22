import '../models/router_listener.dart';

/// Lightweight summary of a connected WAMP session.
class SessionInfo {
  SessionInfo({
    required this.id,
    required this.authId,
    required this.authRole,
    required this.roles,
    required this.workerId,
    required this.connectionId,
    required this.lastActivity,
  });

  final int id;
  final String? authId;
  final String? authRole;
  final Map<String, Object?> roles;
  final int workerId;
  final int connectionId;
  final DateTime lastActivity;
}

/// Internal record stored in [RealmRecord.sessions].
class SessionRecord extends SessionInfo {
  SessionRecord({
    required super.id,
    required super.authId,
    required super.authRole,
    required super.roles,
    required super.workerId,
    required super.connectionId,
    required super.lastActivity,
    required this.listener,
  });

  final RouterListener listener;

  final Set<int> subscriptionIds = <int>{};
  final Set<int> registrationIds = <int>{};
  final Map<int, PendingCall> pendingCalls = {};
  final Map<int, PendingInvocation> pendingInvocations = {};
}

/// Tracks an outstanding CALL request awaiting invocation dispatch.
class PendingCall {
  PendingCall({
    required this.requestId,
    required this.procedure,
    required this.callerSessionId,
    required this.options,
  });

  final int requestId;
  final String procedure;
  final int callerSessionId;
  final Map<String, Object?> options;
}

/// Tracks an invocation issued to a callee awaiting completion/cancellation.
class PendingInvocation {
  PendingInvocation({
    required this.invocationId,
    required this.registrationId,
    required this.callerRequestId,
    required this.calleeSessionId,
    required this.allowProgress,
  });

  final int invocationId;
  final int registrationId;
  final int callerRequestId;
  final int calleeSessionId;
  final bool allowProgress;
}
