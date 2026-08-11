import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

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
    if (!_trackingEnabled(limits)) {
      _realmFailures.remove(realmUri);
      return null;
    }
    final now = DateTime.now();
    _removeExpiredRecords(realmUri, now);
    final realmMap = _realmFailures[realmUri];
    final record = realmMap?[_authIdKey(authId)];
    final lockedUntil = record?.lockedUntil;
    if (lockedUntil == null) {
      return null;
    }
    if (lockedUntil.isAfter(now)) {
      return lockedUntil.difference(now);
    }
    realmMap!.remove(_authIdKey(authId));
    if (realmMap.isEmpty) {
      _realmFailures.remove(realmUri);
    }
    return null;
  }

  static Duration? capacityRetryAfter(
    String realmUri,
    String authId,
    RealmLimitSettings limits,
  ) {
    if (!_trackingEnabled(limits)) {
      _realmFailures.remove(realmUri);
      return null;
    }
    if (limits.maxFailedAuthRecords <= 0) {
      return Duration(
        milliseconds: limits.lockoutMs.clamp(1, 0x7fffffff).toInt(),
      );
    }
    final now = DateTime.now();
    _removeExpiredRecords(realmUri, now);
    final realmMap = _realmFailures[realmUri];
    final authIdKey = _authIdKey(authId);
    if (realmMap == null ||
        realmMap.containsKey(authIdKey) ||
        realmMap.length < limits.maxFailedAuthRecords) {
      return null;
    }

    DateTime? earliestExpiry;
    for (final record in realmMap.values) {
      if (earliestExpiry == null ||
          record.retainedUntil.isBefore(earliestExpiry)) {
        earliestExpiry = record.retainedUntil;
      }
    }
    if (earliestExpiry == null) {
      return null;
    }
    final retryAfter = earliestExpiry.difference(now);
    return retryAfter.isNegative ? Duration.zero : retryAfter;
  }

  static void recordFailure(
    String realmUri,
    String authId,
    RealmLimitSettings limits,
  ) {
    if (!_trackingEnabled(limits) || limits.maxFailedAuthRecords <= 0) {
      return;
    }
    final now = DateTime.now();
    _removeExpiredRecords(realmUri, now);
    var realmMap = _realmFailures[realmUri];
    if (realmMap == null) {
      realmMap = HashMap<String, _FailureRecord>();
      _realmFailures[realmUri] = realmMap;
    }
    final authIdKey = _authIdKey(authId);
    var record = realmMap[authIdKey];
    if (record == null) {
      if (realmMap.length >= limits.maxFailedAuthRecords) {
        return;
      }
      record = _FailureRecord(now);
      realmMap[authIdKey] = record;
    }

    final retainedUntil = now.add(Duration(milliseconds: limits.lockoutMs));
    record.count++;
    record.retainedUntil = retainedUntil;
    if (record.count >= limits.maxFailedAuth) {
      record.lockedUntil = retainedUntil;
      record.count = 0;
    }
  }

  static void recordSuccess(String realmUri, String authId) {
    final realmMap = _realmFailures[realmUri];
    if (realmMap == null) {
      return;
    }
    realmMap.remove(_authIdKey(authId));
    if (realmMap.isEmpty) {
      _realmFailures.remove(realmUri);
    }
  }

  static void reset() {
    _realmFailures.clear();
  }

  static bool _trackingEnabled(RealmLimitSettings limits) {
    return limits.maxFailedAuth > 0 && limits.lockoutMs > 0;
  }

  static String _authIdKey(String authId) {
    return sha256.convert(utf8.encode(authId)).toString();
  }

  static void _removeExpiredRecords(String realmUri, DateTime now) {
    final realmMap = _realmFailures[realmUri];
    if (realmMap == null) {
      return;
    }
    realmMap.removeWhere((_, record) => !record.retainedUntil.isAfter(now));
    if (realmMap.isEmpty) {
      _realmFailures.remove(realmUri);
    }
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
  _FailureRecord(this.retainedUntil);

  int count = 0;
  DateTime retainedUntil;
  DateTime? lockedUntil;
}
