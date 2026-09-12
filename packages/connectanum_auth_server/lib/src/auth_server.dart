import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';

part 'selection.dart';
part 'pending_transaction.dart';
part 'wamp_procedures_impl.dart';

/// Config-driven implementation of [RemoteAuthenticatorDelegate].
///
/// It mirrors the router's in-process authenticators so the same
/// `RouterSettings` (and credential providers) can back a standalone remote
/// authentication service.
/// Executes router authentication challenges outside the router process.
class AuthServer implements RemoteAuthenticatorDelegate {
  /// Creates a remote authenticator backed by [settings].
  ///
  /// When [authTokens] is non-empty, every remote request must include one of
  /// those shared tokens. [fakeChallengeOnHelloFailure] masks early identity
  /// failures with a challenge to reduce account-enumeration signals, but only
  /// after the caller's service token has been accepted.
  ///
  /// The per-realm pending limit includes factory creation, HELLO,
  /// AUTHENTICATE, and deferred abort cleanup. A positive [challengeTimeout]
  /// (or realm auth timeout) covers the whole attempt starting at admission.
  /// Nonpositive limits/timeouts retain the configured opt-out semantics.
  AuthServer({
    required RouterSettings settings,
    Iterable<String>? authTokens,
    bool fakeChallengeOnHelloFailure = false,
    Duration? challengeTimeout,
    DateTime Function()? clock,
  }) : _settings = settings,
       _authTokens = authTokens == null
           ? null
           : Set<String>.unmodifiable(authTokens),
       _fakeChallengeOnHelloFailure = fakeChallengeOnHelloFailure,
       _challengeTimeout = challengeTimeout,
       _clock = clock ?? DateTime.now,
       _random = Random.secure() {
    // Ensure built-in authenticators are available.
    registerDefaultAuthenticators();
  }

  final RouterSettings _settings;
  final Set<String>? _authTokens;
  final bool _fakeChallengeOnHelloFailure;
  final Duration? _challengeTimeout;
  final DateTime Function() _clock;
  final Random _random;
  final Map<String, _PendingSession> _pending = {};
  final Map<String, int> _pendingCounts = {};
  bool _closed = false;

  /// Router realm and authenticator settings used for challenge processing.
  RouterSettings get settings => _settings;

  /// Occupied slots by realm, including cancelled callbacks still settling.
  Map<String, int> get pendingAuthenticationCounts =>
      Map<String, int>.unmodifiable(_pendingCounts);

  /// Selects an authenticator and returns success, failure, or a challenge.
  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) =>
      _onHello(request, owner: null);

  Future<RemoteHelloResponse> _onHello(
    RemoteHelloRequest request, {
    required Object? owner,
  }) async {
    final tokenFailure = validateAuthToken(request.options);
    if (tokenFailure != null) return RemoteHelloResponse.failure(tokenFailure);
    if (_closed) return const RemoteHelloResponse.failure(_closedFailure);
    final realmName = request.realmSettings.name;
    final realm = _settings.realms.firstWhere(
      (entry) => entry.name == realmName,
      orElse: () => throw StateError('Realm "$realmName" not configured'),
    );
    final helloDetails = Map<String, Object?>.from(
      request.context.helloDetails,
    );
    final rawAuthId = helloDetails['authid'] as String?;
    final authId = rawAuthId == null || rawAuthId.isEmpty
        ? 'unknown'
        : rawAuthId;
    if (_pending.containsKey(request.transactionId)) {
      return const RemoteHelloResponse.failure(_stateFailure);
    }
    final count = _pendingCounts[realm.name] ?? 0;
    if (realm.limits.maxPendingAuth > 0 &&
        count >= realm.limits.maxPendingAuth) {
      return const RemoteHelloResponse.failure(_capacityFailure);
    }
    final timeout =
        _challengeTimeout ?? Duration(milliseconds: realm.limits.authTimeoutMs);
    final pending = _PendingSession(
      id: request.transactionId,
      owner: owner,
      realm: realm,
      context: AuthenticatorContext(
        realm: realm,
        sessionId: request.context.sessionId,
        transport: request.context.transport,
        helloDetails: Map<String, Object?>.unmodifiable(helloDetails),
      ),
      authId: authId,
      deadline: timeout > Duration.zero ? _clock().add(timeout) : null,
    );
    _pending[pending.id] = pending;
    _pendingCounts[realm.name] = count + 1;
    if (timeout > Duration.zero) {
      pending.timer = Timer(timeout, () => _finish(pending, _expiredFailure));
    }
    return _run(
      pending,
      () => _hello(pending, request),
      RemoteHelloResponse.failure,
    );
  }

  Future<RemoteHelloResponse> _hello(
    _PendingSession pending,
    RemoteHelloRequest request,
  ) async {
    final realm = pending.realm;
    final authId = pending.authId;
    final helloDetails = pending.context.helloDetails;
    final rawAuthId = helloDetails['authid'] as String?;
    if (rawAuthId == null || rawAuthId.isEmpty) {
      return _respondWithHelloFailure(
        pending: pending,
        request: request,
        failure: const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'authid is required for remote authentication',
        ),
      );
    }
    final selection = _selectAuthenticator(
      settings: _settings,
      realm: realm,
      clientMethods: _extractClientMethods(helloDetails),
    );
    if (selection == null) {
      return _respondWithHelloFailure(
        pending: pending,
        request: request,
        failure: const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'No acceptable authentication method',
        ),
      );
    }
    pending.method = selection.method;
    final authenticator = pending.authenticator = await selection.factory
        .create(
          realm,
          Map<String, Object?>.from(selection.options),
        );
    var stopped = _stopped(pending);
    if (stopped != null) return RemoteHelloResponse.failure(stopped);
    final result = await authenticator.onHello(pending.context);
    stopped = _stopped(pending);
    if (stopped != null) return RemoteHelloResponse.failure(stopped);
    if (result.isSuccess && result.success != null) {
      _finish(pending);
      _recordSuccess(realm, selection.method, result.success!.authId);
      return RemoteHelloResponse.success(result.success!);
    }
    if (result.isFailure && result.failure != null) {
      return _respondWithHelloFailure(
        pending: pending,
        request: request,
        failure: result.failure!,
      );
    }
    final challenge = result.challenge;
    if (challenge == null) {
      return _respondWithHelloFailure(
        pending: pending,
        request: request,
        failure: const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Authenticator did not produce a challenge',
        ),
      );
    }
    pending.phase = _AuthPhase.challenge;
    return RemoteHelloResponse.challenge(
      RemoteChallenge(
        authId: authId,
        challenge: challenge.challenge,
        extra: challenge.extra,
      ),
    );
  }

  /// Validates the response against its original, still-live challenge.
  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) => _onAuthenticate(request, owner: null);

  Future<RemoteAuthenticateResponse> _onAuthenticate(
    RemoteAuthenticateRequest request, {
    required Object? owner,
  }) async {
    final tokenFailure = validateAuthToken(request.options);
    if (tokenFailure != null) {
      return RemoteAuthenticateResponse.failure(tokenFailure);
    }
    final pending = _owned(request.transactionId, owner);
    if (pending == null ||
        pending.phase != _AuthPhase.challenge ||
        !_matches(
          pending,
          request.realmSettings,
          request.context,
          request.authId,
        )) {
      return const RemoteAuthenticateResponse.failure(_stateFailure);
    }
    final stopped = _stopped(pending);
    if (stopped != null) return RemoteAuthenticateResponse.failure(stopped);
    pending.phase = _AuthPhase.authenticate;
    return _run(
      pending,
      () => _authenticate(pending, request.authenticate),
      RemoteAuthenticateResponse.failure,
    );
  }

  Future<RemoteAuthenticateResponse> _authenticate(
    _PendingSession pending,
    AuthenticateMessage message,
  ) async {
    final authenticator = pending.authenticator;
    if (pending.shouldFail || authenticator == null) {
      final failure = pending.failure ?? _rejectedFailure;
      _finish(pending, failure);
      return RemoteAuthenticateResponse.failure(failure);
    }
    final result = await authenticator.onAuthenticate(pending.context, message);
    final stopped = _stopped(pending);
    if (stopped != null) return RemoteAuthenticateResponse.failure(stopped);
    if (result.isSuccess && result.success != null) {
      _finish(pending);
      _recordSuccess(pending.realm, pending.method, result.success!.authId);
      return RemoteAuthenticateResponse.success(result.success!);
    }
    final failure = result.failure ?? _rejectedFailure;
    _finish(pending, failure);
    _recordFailure(
      pending.realm,
      pending.authId,
      method: pending.method,
      message: failure.message,
    );
    return RemoteAuthenticateResponse.failure(failure);
  }

  /// Invalidates a router-aborted attempt, including an active callback.
  @override
  Future<void> onAbort(RemoteAbortRequest request) async {
    if (validateAuthToken(request.options) != null) return;
    final pending = _owned(request.transactionId, null);
    if (pending != null &&
        _matches(
          pending,
          request.realmSettings,
          request.context,
          request.authId,
        )) {
      _finish(pending, _abortedFailure);
    }
  }

  /// Trusted local cancellation of the identified authentication attempt.
  void abort(String transactionId) {
    final pending = _pending[transactionId];
    if (pending != null) _finish(pending, _abortedFailure);
  }

  /// Stops admission and invalidates all unfinished authentication attempts.
  ///
  /// Provider futures cannot be forcibly cancelled. Cleanup is best effort and
  /// runs after each active callback settles; this method does not wait for an
  /// uncooperative provider. Capacity stays occupied until cleanup finishes.
  Future<void> close() async {
    _closed = true;
    for (final pending in _pending.values.toList()) {
      _finish(pending, _closedFailure);
    }
  }

  /// Checks service admission without reading or changing challenge state.
  ///
  /// Returns null for an accepted token, including intentionally token-free
  /// configurations. Adapters must call this before accessing their own pending
  /// state. Rejected service credentials are not failures of the claimed user.
  AuthFailure? validateAuthToken(Map<String, Object?> options) {
    final tokens = _authTokens;
    if (tokens == null || tokens.isEmpty) {
      return null;
    }
    final provided = options['auth_token'];
    if (provided is String && tokens.contains(provided)) return null;
    return const AuthFailure(
      reason: wamp_core.Error.notAuthorized,
      message: 'Remote authenticator token rejected',
    );
  }

  List<String> _extractClientMethods(Map<String, Object?> details) {
    final methods = <String>[];
    final value = details['authmethods'];
    if (value is Iterable) {
      for (final entry in value) {
        if (entry is String && entry.isNotEmpty) {
          methods.add(entry);
        }
      }
    }
    final single = details['authmethod'];
    if (single is String && single.isNotEmpty) {
      methods.add(single);
    }
    return methods;
  }

  void _recordSuccess(RealmSettings realm, String method, String authId) {
    AuthSecurityTracker.recordSuccess(realm.name, authId);
    AuthAuditLogger.success(
      realmUri: realm.name,
      method: method,
      authId: authId,
    );
  }

  void _recordFailure(
    RealmSettings realm,
    String? authId, {
    required String method,
    String? message,
  }) {
    if (authId != null && authId.isNotEmpty) {
      AuthSecurityTracker.recordFailure(realm.name, authId, realm.limits);
    }
    AuthAuditLogger.failure(
      realmUri: realm.name,
      method: method,
      authId: authId,
      message: message,
    );
  }

  RemoteHelloResponse _respondWithHelloFailure({
    required _PendingSession pending,
    required RemoteHelloRequest request,
    required AuthFailure failure,
  }) {
    _recordFailure(
      pending.realm,
      pending.authId,
      method: pending.method,
      message: failure.message,
    );
    if (_fakeChallengeOnHelloFailure) {
      pending.phase = _AuthPhase.challenge;
      pending.shouldFail = true;
      pending.failure = AuthFailure(
        reason: wamp_core.Error.authenticationFailed,
        message: failure.message,
      );
      return RemoteHelloResponse.challenge(
        _fakeRemoteChallenge(
          realm: pending.realm,
          request: request,
          authId: pending.authId,
        ),
      );
    }
    _finish(pending, failure);
    return RemoteHelloResponse.failure(failure);
  }

  RemoteChallenge _fakeRemoteChallenge({
    required RealmSettings realm,
    required RemoteHelloRequest request,
    required String authId,
  }) {
    final nonce = base64UrlEncode(_randomBytes(32));
    final salt = base64UrlEncode(_randomBytes(16));
    final challengeJson = jsonEncode({
      'authid': authId,
      'realm': realm.name,
      'timestamp': _clock().toUtc().toIso8601String(),
      'session': request.context.sessionId,
      'nonce': nonce,
    });
    return RemoteChallenge(
      authId: authId,
      challenge: {
        'challenge': challengeJson,
        'salt': salt,
        'iterations': 2000,
        'keylen': CraAuthentication.defaultKeyLength,
      },
      extra: const {'fake': true},
    );
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
