part of 'auth_server.dart';

const _stateFailure = AuthFailure(
  reason: wamp_core.Error.protocolViolation,
  message: 'Remote authentication transaction is not in the expected state',
);
const _capacityFailure = AuthFailure(
  reason: wamp_core.Error.authenticationFailed,
  message: 'Remote authentication capacity exhausted',
);
const _expiredFailure = AuthFailure(
  reason: wamp_core.Error.authenticationFailed,
  message: 'Remote authentication challenge expired',
);
const _abortedFailure = AuthFailure(
  reason: wamp_core.Error.authenticationFailed,
  message: 'Remote authentication aborted',
);
const _closedFailure = AuthFailure(
  reason: wamp_core.Error.authenticationFailed,
  message: 'Remote authentication service closed',
);
const _rejectedFailure = AuthFailure(
  reason: wamp_core.Error.authenticationFailed,
  message: 'Remote authentication rejected',
);

enum _AuthPhase { hello, challenge, authenticate, finished }

class _PendingSession {
  _PendingSession({
    required this.id,
    required this.owner,
    required this.realm,
    required this.context,
    required this.authId,
    required this.deadline,
  });

  final String id;
  final Object? owner;
  final RealmSettings realm;
  final AuthenticatorContext context;
  final String authId;
  final DateTime? deadline;
  final cancelled = Completer<AuthFailure>();
  _AuthPhase phase = _AuthPhase.hello;
  String method = 'remote';
  Authenticator? authenticator;
  Timer? timer;
  bool busy = false;
  bool releasing = false;
  bool shouldFail = false;
  AuthFailure? failure;
  AuthFailure? terminalFailure;
}

extension _Transactions on AuthServer {
  _PendingSession? _owned(String id, Object? owner) {
    final pending = _pending[id];
    return pending != null && identical(pending.owner, owner) ? pending : null;
  }

  bool _matches(
    _PendingSession pending,
    RealmSettings realm,
    AuthenticatorContext context,
    String authId,
  ) =>
      pending.realm.name == realm.name &&
      pending.realm.name == context.realm.name &&
      pending.authId == authId &&
      pending.context.sessionId == context.sessionId &&
      pending.context.transport.connectionId ==
          context.transport.connectionId &&
      pending.context.transport.peerAddress == context.transport.peerAddress &&
      pending.context.transport.isEncrypted == context.transport.isEncrypted;

  AuthFailure? _stopped(_PendingSession pending) {
    if (pending.phase != _AuthPhase.finished &&
        pending.deadline != null &&
        !_clock().isBefore(pending.deadline!)) {
      _finish(pending, _expiredFailure);
    }
    return pending.terminalFailure;
  }

  Future<T> _run<T>(
    _PendingSession pending,
    Future<T> Function() callback,
    T Function(AuthFailure) rejected,
  ) {
    pending.busy = true;
    Future<T> work() async {
      try {
        return await callback();
      } catch (_) {
        final stopped = _stopped(pending);
        final failure = stopped ?? _rejectedFailure;
        _finish(pending, failure);
        if (stopped == null) {
          _recordFailure(
            pending.realm,
            pending.authId,
            method: pending.method,
            message: failure.message,
          );
        }
        return rejected(failure);
      } finally {
        pending.busy = false;
        if (pending.phase == _AuthPhase.finished) unawaited(_release(pending));
      }
    }

    return Future.any([work(), pending.cancelled.future.then(rejected)]);
  }

  void _finish(_PendingSession pending, [AuthFailure? failure]) {
    if (pending.phase == _AuthPhase.finished) return;
    pending.phase = _AuthPhase.finished;
    pending.terminalFailure = failure;
    pending.timer?.cancel();
    pending.timer = null;
    if (failure != null) pending.cancelled.complete(failure);
    if (!pending.busy) unawaited(_release(pending));
  }

  Future<void> _release(_PendingSession pending) async {
    if (pending.releasing) return;
    pending.releasing = true;
    try {
      if (pending.terminalFailure != null) {
        await pending.authenticator?.onAbort(
          pending.context,
          reason: pending.terminalFailure!.reason,
        );
      }
    } catch (_) {
      // Cleanup errors must not resurrect a transaction or expose credentials.
    } finally {
      pending.authenticator = null;
      if (identical(_pending[pending.id], pending)) {
        _pending.remove(pending.id);
        final count = _pendingCounts[pending.realm.name]! - 1;
        if (count == 0) {
          _pendingCounts.remove(pending.realm.name);
        } else {
          _pendingCounts[pending.realm.name] = count;
        }
      }
    }
  }

  void _closeOwner(Object owner) {
    for (final pending in _pending.values.toList()) {
      if (identical(pending.owner, owner)) _finish(pending, _closedFailure);
    }
  }
}
