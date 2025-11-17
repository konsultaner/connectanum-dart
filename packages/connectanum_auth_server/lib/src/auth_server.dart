import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectanum_core/authentication.dart' show CraAuthentication;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core show Error;
import 'package:connectanum_router/auth.dart';

part 'selection.dart';

/// Config-driven implementation of [RemoteAuthenticatorDelegate].
///
/// It mirrors the router's in-process authenticators so the same
/// `RouterSettings` (and credential providers) can back a standalone remote
/// authentication service.
class AuthServer implements RemoteAuthenticatorDelegate {
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

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
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

    final tokens = _authTokens;
    if (tokens != null && tokens.isNotEmpty) {
      final provided = request.options['auth_token'];
      if (provided is! String || !tokens.contains(provided)) {
        return _respondWithHelloFailure(
          realm: realm,
          request: request,
          authId: authId,
          method: 'remote',
          failure: const AuthFailure(
            reason: wamp_core.Error.notAuthorized,
            message: 'Remote authenticator token rejected',
          ),
        );
      }
    }

    if (rawAuthId == null || rawAuthId.isEmpty) {
      return _respondWithHelloFailure(
        realm: realm,
        request: request,
        authId: authId,
        method: 'remote',
        failure: const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'authid is required for remote authentication',
        ),
      );
    }

    final clientMethods = _extractClientMethods(helloDetails);
    final selection = _selectAuthenticator(
      settings: _settings,
      realm: realm,
      clientMethods: clientMethods,
    );
    if (selection == null) {
      return _respondWithHelloFailure(
        realm: realm,
        request: request,
        authId: authId,
        method: 'remote',
        failure: const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'No acceptable authentication method',
        ),
      );
    }

    final authenticator = await selection.factory.create(
      realm,
      Map<String, Object?>.from(selection.options),
    );

    final context = AuthenticatorContext(
      realm: realm,
      sessionId: request.context.sessionId,
      transport: request.context.transport,
      helloDetails: helloDetails,
    );

    final result = await authenticator.onHello(context);
    if (result.isSuccess && result.success != null) {
      _recordSuccess(realm, selection.method, result.success!.authId);
      return RemoteHelloResponse.success(result.success!);
    }

    if (result.isFailure && result.failure != null) {
      return _respondWithHelloFailure(
        realm: realm,
        request: request,
        authId: authId,
        method: selection.method,
        failure: result.failure!,
      );
    }

    final challenge = result.challenge;
    if (challenge == null) {
      return _respondWithHelloFailure(
        realm: realm,
        request: request,
        authId: authId,
        method: selection.method,
        failure: const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Authenticator did not produce a challenge',
        ),
      );
    }

    final transactionId = request.transactionId;
    _pending[transactionId] = _PendingSession(
      realm: realm,
      method: selection.method,
      authenticator: authenticator,
      context: context,
      authId: authId,
      issuedAt: _clock(),
    );

    return RemoteHelloResponse.challenge(
      RemoteChallenge(
        authId: authId,
        challenge: challenge.challenge,
        extra: challenge.extra,
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    final pending = _pending.remove(request.transactionId);
    if (pending == null) {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.protocolViolation,
          message: 'AUTHENTICATE received without pending challenge',
        ),
      );
    }

    final authenticator = pending.authenticator;
    if (pending.shouldFail || authenticator == null) {
      return RemoteAuthenticateResponse.failure(
        pending.failure ??
            const AuthFailure(
              reason: wamp_core.Error.authenticationFailed,
              message: 'Remote authentication rejected',
            ),
      );
    }

    final timeout =
        _challengeTimeout ??
        Duration(milliseconds: pending.realm.limits.authTimeoutMs);
    if (timeout.inMilliseconds > 0) {
      final deadline = pending.issuedAt.add(timeout);
      if (_clock().isAfter(deadline)) {
        _recordFailure(pending.realm, pending.authId, method: pending.method);
        return RemoteAuthenticateResponse.failure(
          const AuthFailure(
            reason: wamp_core.Error.authenticationFailed,
            message: 'Remote authentication challenge expired',
          ),
        );
      }
    }

    try {
      final result = await authenticator.onAuthenticate(
        pending.context,
        request.authenticate,
      );
      if (result.isSuccess && result.success != null) {
        _recordSuccess(pending.realm, pending.method, result.success!.authId);
        return RemoteAuthenticateResponse.success(result.success!);
      }
      if (result.isFailure && result.failure != null) {
        _recordFailure(
          pending.realm,
          pending.authId,
          method: pending.method,
          message: result.failure!.message,
        );
        return RemoteAuthenticateResponse.failure(result.failure!);
      }
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.authenticationFailed,
          message: 'Authenticator returned unexpected result',
        ),
      );
    } catch (error) {
      _recordFailure(
        pending.realm,
        pending.authId,
        method: pending.method,
        message: error.toString(),
      );
      return RemoteAuthenticateResponse.failure(
        AuthFailure(
          reason: wamp_core.Error.authenticationFailed,
          message: 'Authenticator threw ${error.runtimeType}',
        ),
      );
    }
  }

  /// Aborts and cleans up any stored challenge for the [transactionId].
  void abort(String transactionId) {
    _pending.remove(transactionId);
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
    required RealmSettings realm,
    required RemoteHelloRequest request,
    required String authId,
    required String method,
    required AuthFailure failure,
  }) {
    _recordFailure(realm, authId, method: method, message: failure.message);
    if (_fakeChallengeOnHelloFailure) {
      final maskedFailure = AuthFailure(
        reason: wamp_core.Error.authenticationFailed,
        message: failure.message,
      );
      final challenge = _fakeRemoteChallenge(
        realm: realm,
        request: request,
        authId: authId,
      );
      _pending[request.transactionId] = _PendingSession(
        realm: realm,
        method: method,
        context: request.context,
        authId: authId,
        issuedAt: _clock(),
        shouldFail: true,
        failure: maskedFailure,
      );
      return RemoteHelloResponse.challenge(challenge);
    }
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

class _PendingSession {
  _PendingSession({
    required this.realm,
    required this.method,
    required this.context,
    required this.authId,
    required this.issuedAt,
    this.authenticator,
    this.shouldFail = false,
    this.failure,
  });

  final RealmSettings realm;
  final String method;
  final Authenticator? authenticator;
  final AuthenticatorContext context;
  final String authId;
  final DateTime issuedAt;
  final bool shouldFail;
  final AuthFailure? failure;
}
