import 'dart:isolate';

import '../models/router_listener.dart';
import '../config/router_settings.dart';

/// Lightweight summary of a connected WAMP session.
class SessionInfo {
  SessionInfo({
    required this.id,
    required this.authId,
    required this.authRole,
    this.authMethod,
    this.authProvider,
    required this.roles,
    required this.workerId,
    required this.connectionId,
    required this.lastActivity,
    this.protocol,
  });

  final int id;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final Map<String, Object?> roles;
  final int workerId;
  final int connectionId;
  final DateTime lastActivity;
  final ListenerProtocol? protocol;
}

/// Internal record stored in [RealmRecord.sessions].
class SessionRecord extends SessionInfo {
  SessionRecord({
    required super.id,
    required super.authId,
    required super.authRole,
    super.authMethod,
    super.authProvider,
    required super.roles,
    required super.workerId,
    required super.connectionId,
    required super.lastActivity,
    required this.listener,
    super.protocol,
    this.internalSendPort,
  });

  final RouterListener listener;
  final SendPort? internalSendPort;

  final Set<int> subscriptionIds = <int>{};
  final Set<int> registrationIds = <int>{};
  final Map<int, PendingCall> pendingCalls = {};
  final Map<int, PendingInvocation> pendingInvocations = {};

  bool get isInternal => internalSendPort != null;
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
    required this.procedure,
    required this.callerRequestId,
    required this.calleeSessionId,
    required this.calleeConnectionId,
    required this.allowProgress,
    required this.callerSessionId,
    this.calleeInternalSendPort,
    this.callerInternalSendPort,
    this.initiatingOptions = const {},
    this.progressiveInvocation = false,
    this.progressiveInvocationOpen = false,
    this.timeout,
    this.timeoutForwarded = false,
    this.disclosedCallerSessionId,
    this.disclosedCallerAuthId,
    this.disclosedCallerAuthRole,
    this.cancelRequested = false,
    this.cancelMode,
    this.waitForCancelAck = false,
  });

  final int invocationId;
  final int registrationId;
  final String procedure;
  final int callerRequestId;
  final int calleeSessionId;
  final int? calleeConnectionId;
  final bool allowProgress;
  final int callerSessionId;
  final SendPort? calleeInternalSendPort;
  final SendPort? callerInternalSendPort;
  final Map<String, Object?> initiatingOptions;
  final bool progressiveInvocation;
  bool progressiveInvocationOpen;
  final int? timeout;
  final bool timeoutForwarded;
  final int? disclosedCallerSessionId;
  final String? disclosedCallerAuthId;
  final String? disclosedCallerAuthRole;
  bool cancelRequested;
  String? cancelMode;
  bool waitForCancelAck;
}
