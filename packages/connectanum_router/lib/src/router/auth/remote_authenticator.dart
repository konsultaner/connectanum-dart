import 'dart:convert';
import 'dart:math';

import 'package:connectanum_core/connectanum_core.dart' as wamp_core;

import '../config/authenticator.dart';
import '../config/router_settings.dart';

/// Delegate invoked for remote authentication decisions.
abstract class RemoteAuthenticatorDelegate {
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request);
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  );
}

class RemoteDelegateUnavailableException implements Exception {
  RemoteDelegateUnavailableException([this.message]);

  final String? message;

  @override
  String toString() =>
      message == null ? 'RemoteDelegateUnavailableException' : message!;
}

class RemoteAuthenticatorRegistry {
  RemoteAuthenticatorRegistry._();

  static const String defaultDelegateId = 'default';

  static final Map<String, RemoteAuthenticatorDelegate> _delegates = {};

  static void register(
    RemoteAuthenticatorDelegate delegate, {
    String id = defaultDelegateId,
  }) {
    _delegates[id] = delegate;
  }

  static void unregister(String id) => _delegates.remove(id);

  static RemoteAuthenticatorDelegate? delegateFor(String id) => _delegates[id];

  static Map<String, RemoteAuthenticatorDelegate> get delegates =>
      Map.unmodifiable(_delegates);

  static void clear() {
    _delegates.clear();
  }
}

class RemoteAuthenticatorFactory extends AuthenticatorFactory {
  const RemoteAuthenticatorFactory();

  @override
  String get method => 'remote';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    final config = RemoteAuthenticatorConfig.parse(options, realm);
    final delegates = <RemoteAuthenticatorDelegate>[];
    for (final id in config.delegateIds) {
      final delegate = RemoteAuthenticatorRegistry.delegateFor(id);
      if (delegate == null) {
        throw StateError(
          'Remote authenticator delegate "$id" not registered. '
          'Call RemoteAuthenticatorRegistry.register(..., id: "$id") first.',
        );
      }
      delegates.add(delegate);
    }
    return RemoteAuthenticator(config, delegates);
  }
}

class RemoteAuthenticator extends Authenticator {
  RemoteAuthenticator(
    RemoteAuthenticatorConfig config,
    List<RemoteAuthenticatorDelegate> delegates,
  ) : _config = config,
      _random = Random.secure(),
      _handles = delegates
          .asMap()
          .entries
          .map(
            (entry) => _DelegateHandle(
              id: config.delegateIds[entry.key],
              delegate: entry.value,
            ),
          )
          .toList(growable: false) {
    if (_handles.isEmpty) {
      throw StateError('RemoteAuthenticator requires at least one delegate');
    }
  }

  final RemoteAuthenticatorConfig _config;
  final List<_DelegateHandle> _handles;
  _RemotePendingSession? _pending;
  final Random _random;
  static final Map<String, _RateLimitState> _rateLimitStates =
      <String, _RateLimitState>{};

  @override
  String get method => _config.method;

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    final authId = _extractAuthId(context.helloDetails);
    final rateLimitFailure = _guardRateLimit(authId);
    if (rateLimitFailure != null) {
      return AuthResult.failure(rateLimitFailure);
    }
    final transactionId = _generateTransactionId();
    final issuedAt = DateTime.now();
    final selected = await _invokeHello(
      context: context,
      transactionId: transactionId,
      issuedAt: issuedAt,
    );
    if (selected == null) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Remote authentication service unavailable',
        ),
      );
    }
    final (_DelegateHandle handle, RemoteHelloResponse response) = selected;

    switch (response.status) {
      case RemoteHelloStatus.success:
        final failure = _validateSuccess(response.success!, authId);
        if (failure != null) {
          _registerFailure(authId);
          return AuthResult.failure(failure);
        }
        _registerSuccess(authId);
        handle.markSuccess();
        return AuthResult.success(response.success!);
      case RemoteHelloStatus.failure:
        _registerFailure(authId);
        handle.markSuccess();
        return AuthResult.failure(response.failure!);
      case RemoteHelloStatus.challenge:
        _pending = _RemotePendingSession(
          authId: response.challenge!.authId,
          sessionId: context.sessionId,
          transactionId: transactionId,
          issuedAt: issuedAt,
          delegateId: handle.id,
        );
        handle.markSuccess();
        return AuthResult.challenge(
          AuthChallenge(
            challenge: response.challenge!.challenge,
            extra: response.challenge!.extra,
          ),
        );
    }
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    final pending = _pending;
    _pending = null;
    if (pending == null) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.protocolViolation,
          message: 'AUTHENTICATE received without remote challenge',
        ),
      );
    }

    if (_config.challengeTimeoutMs > 0) {
      final expiresAt = pending.issuedAt.add(
        Duration(milliseconds: _config.challengeTimeoutMs),
      );
      if (DateTime.now().isAfter(expiresAt)) {
        return AuthResult.failure(
          const AuthFailure(
            reason: wamp_core.Error.authenticationFailed,
            message: 'Remote authentication challenge expired',
          ),
        );
      }
    }

    final rateLimitFailure = _guardRateLimit(pending.authId);
    if (rateLimitFailure != null) {
      return AuthResult.failure(rateLimitFailure);
    }

    final handle = _handleForId(pending.delegateId);
    if (handle == null) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Remote authenticator delegate no longer available',
        ),
      );
    }
    if (!handle.isAvailable(DateTime.now())) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Remote authenticator delegate temporarily unavailable',
        ),
      );
    }

    RemoteAuthenticateResponse response;
    try {
      response = await handle.delegate.onAuthenticate(
        RemoteAuthenticateRequest(
          realmSettings: _config.realm,
          context: context,
          authId: pending.authId,
          authenticate: message,
          options: _config.options,
          transactionId: pending.transactionId,
        ),
      );
      handle.markSuccess();
    } on RemoteDelegateUnavailableException catch (_) {
      handle.markFailure(DateTime.now(), _config.delegateRetryDelay);
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Remote authenticator delegate unavailable',
        ),
      );
    } catch (_) {
      handle.markFailure(DateTime.now(), _config.delegateRetryDelay);
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Remote authenticator invocation failed',
        ),
      );
    }

    switch (response.status) {
      case RemoteAuthenticateStatus.success:
        final success = response.success!;
        final failure = _validateSuccess(success, pending.authId);
        if (failure != null) {
          _registerFailure(pending.authId);
          return AuthResult.failure(failure);
        }
        _registerSuccess(pending.authId);
        return AuthResult.success(success);
      case RemoteAuthenticateStatus.failure:
        _registerFailure(pending.authId);
        return AuthResult.failure(response.failure!);
    }
  }

  Future<(_DelegateHandle, RemoteHelloResponse)?> _invokeHello({
    required AuthenticatorContext context,
    required String transactionId,
    required DateTime issuedAt,
  }) async {
    final now = DateTime.now();
    for (final handle in _handles) {
      if (!handle.isAvailable(now)) {
        continue;
      }
      try {
        final response = await handle.delegate.onHello(
          RemoteHelloRequest(
            context: context,
            realmSettings: _config.realm,
            options: _config.options,
            transactionId: transactionId,
          ),
        );
        return (handle, response);
      } on RemoteDelegateUnavailableException {
        handle.markFailure(now, _config.delegateRetryDelay);
      } catch (_) {
        handle.markFailure(now, _config.delegateRetryDelay);
      }
    }
    return null;
  }

  _DelegateHandle? _handleForId(String id) {
    for (final handle in _handles) {
      if (handle.id == id) {
        return handle;
      }
    }
    return null;
  }

  String _generateTransactionId() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  AuthFailure? _validateSuccess(AuthSuccess success, String? authId) {
    if (_config.allowedRoles.isNotEmpty &&
        !_config.allowedRoles.contains(success.authRole)) {
      return const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Remote authenticator rejected role',
      );
    }
    final providerValue =
        success.details['authprovider'] ?? success.details['provider'];
    if (_config.allowedProviders.isNotEmpty) {
      if (providerValue is! String ||
          !_config.allowedProviders.contains(providerValue)) {
        return const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Remote authenticator rejected provider',
        );
      }
    }
    return null;
  }

  String? _extractAuthId(Map<String, Object?> helloDetails) {
    final raw = helloDetails['authid'];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    return null;
  }

  AuthFailure? _guardRateLimit(String? authId) {
    if (authId == null || authId.isEmpty || _config.rateLimitMaxAttempts <= 0) {
      return null;
    }
    final key = _rateLimitKey(authId);
    final state = _rateLimitStates[key];
    if (state == null) {
      return null;
    }
    final now = DateTime.now();
    final window = Duration(milliseconds: _config.rateLimitWindowMs);
    if (now.difference(state.windowStart) > window) {
      state.failures = 0;
      state.windowStart = now;
      state.nextAllowed = null;
      return null;
    }
    if (state.nextAllowed != null && now.isBefore(state.nextAllowed!)) {
      final waitMs = state.nextAllowed!.difference(now).inMilliseconds;
      return AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Remote authentication rate limited. Retry in ${waitMs}ms',
      );
    }
    return null;
  }

  void _registerFailure(String? authId) {
    if (authId == null || authId.isEmpty || _config.rateLimitMaxAttempts <= 0) {
      return;
    }
    final key = _rateLimitKey(authId);
    final now = DateTime.now();
    final state = _rateLimitStates.putIfAbsent(
      key,
      () => _RateLimitState(windowStart: now),
    );
    final window = Duration(milliseconds: _config.rateLimitWindowMs);
    if (now.difference(state.windowStart) > window) {
      state.failures = 0;
      state.windowStart = now;
      state.nextAllowed = null;
    }
    state.failures++;
    if (state.failures >= _config.rateLimitMaxAttempts) {
      final backoffStep = state.failures - _config.rateLimitMaxAttempts + 1;
      final rawDelay =
          _config.backoffBaseMs * pow(_config.backoffFactor, backoffStep - 1);
      final delayMs = rawDelay.clamp(0, _config.backoffMaxMs).toInt();
      state.nextAllowed = now.add(Duration(milliseconds: delayMs));
    }
  }

  void _registerSuccess(String? authId) {
    if (authId == null || authId.isEmpty) {
      return;
    }
    _rateLimitStates.remove(_rateLimitKey(authId));
  }

  String _rateLimitKey(String authId) => '${_config.realm.name}::$authId';

  static void resetRateLimiter() => _rateLimitStates.clear();
}

class RemoteAuthenticatorConfig {
  RemoteAuthenticatorConfig({
    required this.realm,
    required this.options,
    required this.method,
    required this.delegateIds,
    required this.challengeTimeoutMs,
    required this.allowedRoles,
    required this.allowedProviders,
    required this.rateLimitMaxAttempts,
    required this.rateLimitWindowMs,
    required this.backoffBaseMs,
    required this.backoffFactor,
    required this.backoffMaxMs,
    required this.delegateRetryDelay,
  });

  final RealmSettings realm;
  final Map<String, Object?> options;
  final String method;
  final List<String> delegateIds;
  final int challengeTimeoutMs;
  final Set<String> allowedRoles;
  final Set<String> allowedProviders;
  final int rateLimitMaxAttempts;
  final int rateLimitWindowMs;
  final int backoffBaseMs;
  final double backoffFactor;
  final int backoffMaxMs;
  final Duration delegateRetryDelay;

  factory RemoteAuthenticatorConfig.parse(
    Map<String, Object?> options,
    RealmSettings realm,
  ) {
    final method = options['method'] as String? ?? 'remote';
    final timeoutMs =
        (options['challenge_timeout_ms'] as num?)
            ?.clamp(0, 10 * 60 * 1000)
            .toInt() ??
        realm.limits.authTimeoutMs;
    final copy = Map<String, Object?>.from(options)..remove('method');
    copy.remove('challenge_timeout_ms');
    final delegateIds = _parseDelegateIds(copy.remove('delegates'));
    final allowedRoles = _parseStringSet(copy.remove('allowed_roles'));
    final allowedProviders = _parseStringSet(copy.remove('allowed_providers'));
    final rateLimitMaxAttempts = _parsePositiveInt(
      copy.remove('rate_limit_max_attempts'),
      5,
    );
    final rateLimitWindowMs = _parsePositiveInt(
      copy.remove('rate_limit_window_ms'),
      10000,
    );
    final backoffBaseMs = _parsePositiveInt(
      copy.remove('backoff_base_ms'),
      500,
    );
    final backoffMaxMs = _parsePositiveInt(
      copy.remove('backoff_max_ms'),
      30000,
    );
    final backoffFactor = _parsePositiveDouble(
      copy.remove('backoff_factor'),
      2.0,
    );
    final delegateRetryMs = _parsePositiveInt(
      copy.remove('delegate_retry_ms'),
      5000,
    );
    return RemoteAuthenticatorConfig(
      realm: realm,
      options: Map<String, Object?>.unmodifiable(copy),
      method: method,
      delegateIds: delegateIds,
      challengeTimeoutMs: timeoutMs,
      allowedRoles: allowedRoles,
      allowedProviders: allowedProviders,
      rateLimitMaxAttempts: rateLimitMaxAttempts,
      rateLimitWindowMs: rateLimitWindowMs,
      backoffBaseMs: backoffBaseMs,
      backoffFactor: backoffFactor,
      backoffMaxMs: backoffMaxMs,
      delegateRetryDelay: Duration(milliseconds: delegateRetryMs),
    );
  }

  static List<String> _parseDelegateIds(Object? value) {
    if (value == null) {
      return const [RemoteAuthenticatorRegistry.defaultDelegateId];
    }
    if (value is List) {
      final ids = value.whereType<String>().map((e) => e.trim()).toList();
      if (ids.isEmpty) {
        throw ArgumentError('delegates must contain at least one id');
      }
      return List.unmodifiable(ids);
    }
    if (value is String && value.trim().isNotEmpty) {
      final ids = value
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (ids.isEmpty) {
        throw ArgumentError('delegates must contain at least one id');
      }
      return List.unmodifiable(ids);
    }
    throw ArgumentError.value(value, 'delegates', 'Expected a list of strings');
  }

  static Set<String> _parseStringSet(Object? value) {
    if (value == null) {
      return const <String>{};
    }
    if (value is List) {
      return value
          .whereType<String>()
          .map((e) => e.trim())
          .where((element) => element.isNotEmpty)
          .toSet();
    }
    throw ArgumentError.value(
      value,
      'allowed list',
      'Expected a list of strings',
    );
  }

  static int _parsePositiveInt(Object? value, int defaultValue) {
    if (value == null) {
      return defaultValue;
    }
    if (value is num) {
      final result = value.toInt();
      return result > 0 ? result : defaultValue;
    }
    throw ArgumentError.value(value, 'int option', 'Expected a number');
  }

  static double _parsePositiveDouble(Object? value, double defaultValue) {
    if (value == null) {
      return defaultValue;
    }
    if (value is num) {
      final result = value.toDouble();
      return result > 0 ? result : defaultValue;
    }
    throw ArgumentError.value(value, 'double option', 'Expected a number');
  }
}

class RemoteHelloRequest {
  RemoteHelloRequest({
    required this.realmSettings,
    required this.context,
    required this.options,
    required this.transactionId,
  });

  final RealmSettings realmSettings;
  final AuthenticatorContext context;
  final Map<String, Object?> options;
  final String transactionId;
}

enum RemoteHelloStatus { success, failure, challenge }

class RemoteHelloResponse {
  const RemoteHelloResponse._({
    required this.status,
    this.success,
    this.failure,
    this.challenge,
  });

  const RemoteHelloResponse.success(AuthSuccess success)
    : this._(status: RemoteHelloStatus.success, success: success);

  const RemoteHelloResponse.failure(AuthFailure failure)
    : this._(status: RemoteHelloStatus.failure, failure: failure);

  const RemoteHelloResponse.challenge(RemoteChallenge challenge)
    : this._(status: RemoteHelloStatus.challenge, challenge: challenge);

  final RemoteHelloStatus status;
  final AuthSuccess? success;
  final AuthFailure? failure;
  final RemoteChallenge? challenge;
}

class RemoteChallenge {
  RemoteChallenge({
    required this.challenge,
    required this.extra,
    required this.authId,
  });

  final Map<String, Object?> challenge;
  final Map<String, Object?> extra;
  final String authId;
}

class RemoteAuthenticateRequest {
  RemoteAuthenticateRequest({
    required this.realmSettings,
    required this.context,
    required this.authId,
    required this.authenticate,
    required this.options,
    required this.transactionId,
  });

  final RealmSettings realmSettings;
  final AuthenticatorContext context;
  final String authId;
  final AuthenticateMessage authenticate;
  final Map<String, Object?> options;
  final String transactionId;
}

enum RemoteAuthenticateStatus { success, failure }

class RemoteAuthenticateResponse {
  const RemoteAuthenticateResponse._({
    required this.status,
    this.success,
    this.failure,
  });

  const RemoteAuthenticateResponse.success(AuthSuccess success)
    : this._(status: RemoteAuthenticateStatus.success, success: success);

  const RemoteAuthenticateResponse.failure(AuthFailure failure)
    : this._(status: RemoteAuthenticateStatus.failure, failure: failure);

  final RemoteAuthenticateStatus status;
  final AuthSuccess? success;
  final AuthFailure? failure;
}

class _RemotePendingSession {
  _RemotePendingSession({
    required this.authId,
    required this.sessionId,
    required this.transactionId,
    required this.issuedAt,
    required this.delegateId,
  });

  final String authId;
  final int sessionId;
  final String transactionId;
  final DateTime issuedAt;
  final String delegateId;
}

class _RateLimitState {
  _RateLimitState({required this.windowStart});

  int failures = 0;
  DateTime windowStart;
  DateTime? nextAllowed;
}

class _DelegateHandle {
  _DelegateHandle({required this.id, required this.delegate});

  final String id;
  final RemoteAuthenticatorDelegate delegate;
  DateTime? _nextRetry;

  bool isAvailable(DateTime now) =>
      _nextRetry == null || now.isAfter(_nextRetry!);

  void markFailure(DateTime now, Duration delay) {
    _nextRetry = now.add(delay);
  }

  void markSuccess() {
    _nextRetry = null;
  }
}
