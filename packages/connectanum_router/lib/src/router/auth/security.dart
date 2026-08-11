import 'dart:collection';

import '../config/router_settings.dart';

class AuthSecurityTracker {
  AuthSecurityTracker._();

  static final Map<String, Map<String, _FailureRecord>> _realmFailures =
      <String, Map<String, _FailureRecord>>{};

  static bool isLocked(
    String realmUri,
    String authId,
    RealmLimitSettings limits,
  ) {
    return lockoutRemaining(realmUri, authId, limits) != null;
  }

  static Duration? lockoutRemaining(
    String realmUri,
    String authId,
    RealmLimitSettings limits,
  ) {
    if (limits.maxFailedAuth <= 0) {
      return null;
    }
    final realmMap = _realmFailures[realmUri];
    final record = realmMap?[authId];
    final lockedUntil = record?.lockedUntil;
    if (lockedUntil == null) {
      return null;
    }
    final now = DateTime.now();
    if (lockedUntil.isAfter(now)) {
      return lockedUntil.difference(now);
    }
    realmMap!.remove(authId);
    if (realmMap.isEmpty) {
      _realmFailures.remove(realmUri);
    }
    return null;
  }

  static void recordFailure(
    String realmUri,
    String authId,
    RealmLimitSettings limits,
  ) {
    if (limits.maxFailedAuth <= 0) {
      return;
    }
    final realmMap = _realmFailures.putIfAbsent(
      realmUri,
      () => HashMap<String, _FailureRecord>(),
    );
    final record = realmMap.putIfAbsent(authId, _FailureRecord.new);
    record.count++;
    if (record.count >= limits.maxFailedAuth) {
      record.lockedUntil = DateTime.now().add(
        Duration(milliseconds: limits.lockoutMs),
      );
      record.count = 0;
    }
  }

  static void recordSuccess(String realmUri, String authId) {
    final realmMap = _realmFailures[realmUri];
    if (realmMap == null) {
      return;
    }
    realmMap.remove(authId);
    if (realmMap.isEmpty) {
      _realmFailures.remove(realmUri);
    }
  }

  static void reset() {
    _realmFailures.clear();
  }
}

class AuthAuditLogger {
  AuthAuditLogger._();

  static void Function(AuthAuditEvent event)? _sink;

  static void registerSink(void Function(AuthAuditEvent event) sink) {
    _sink = sink;
  }

  static void clearSink() {
    _sink = null;
  }

  static void success({
    required String realmUri,
    required String method,
    required String authId,
  }) {
    _sink?.call(
      AuthAuditEvent(
        outcome: AuthAuditOutcome.success,
        realmUri: realmUri,
        method: method,
        authId: authId,
      ),
    );
  }

  static void failure({
    required String realmUri,
    required String method,
    String? authId,
    String? message,
  }) {
    _sink?.call(
      AuthAuditEvent(
        outcome: AuthAuditOutcome.failure,
        realmUri: realmUri,
        method: method,
        authId: authId,
        message: message,
      ),
    );
  }
}

class AuthAuditEvent {
  AuthAuditEvent({
    required this.outcome,
    required this.realmUri,
    required this.method,
    this.authId,
    this.message,
  });

  final AuthAuditOutcome outcome;
  final String realmUri;
  final String method;
  final String? authId;
  final String? message;
}

enum AuthAuditOutcome { success, failure }

class _FailureRecord {
  int count = 0;
  DateTime? lockedUntil;
}
