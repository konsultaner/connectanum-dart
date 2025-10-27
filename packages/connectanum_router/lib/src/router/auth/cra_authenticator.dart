import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart' show CraAuthentication;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/connectanum_core.dart' show Extra;

import '../config/authenticator.dart';
import '../config/router_settings.dart';
import 'credentials.dart';

class CraAuthenticatorFactory extends AuthenticatorFactory {
  const CraAuthenticatorFactory();

  @override
  String get method => 'wampcra';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    final config = CraAuthenticatorConfig.parse(options, realm);
    return CraAuthenticator(config);
  }
}

class CraAuthenticator extends Authenticator {
  CraAuthenticator(this._config);

  final CraAuthenticatorConfig _config;
  _CraPendingSession? _pending;

  @override
  String get method => 'wampcra';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    final authId =
        context.helloDetails['authid'] as String? ??
        context.helloDetails['authId'] as String?;
    if (authId == null || authId.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'authid is required for WAMP-CRA',
        ),
      );
    }

    CraPrincipal? principal = _config.principalFor(authId);
    if (principal == null) {
      try {
        final external = await AuthCredentialRegistry.loadCra(
          realmUri: _config.realm.name,
          authId: authId,
        );
        if (external != null) {
          principal = CraPrincipal(
            authId: authId,
            secret: external.secret,
            derivedKey: external.derivedKey,
            salt: external.salt,
            iterations:
                external.iterations ?? CraAuthentication.defaultIterations,
            keyLen: external.keyLen ?? CraAuthentication.defaultKeyLength,
            role: external.role,
            provider: external.provider,
            authExtra: external.authExtra,
            challenge: external.challenge,
          );
        }
      } on CredentialRejection catch (rejection) {
        return AuthResult.failure(authFailureFromRejection(rejection));
      }
    }
    if (principal == null) {
      return AuthResult.failure(
        AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Unknown principal "$authId"',
        ),
      );
    }

    final challengeMap = <String, Object?>{
      'authid': authId,
      'realm': _config.realm.name,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'session': context.sessionId,
      'nonce': _generateNonce(),
      ..._config.challengeTemplate,
      ...principal.challenge,
    };
    final challengeJson = jsonEncode(challengeMap);
    final challengeExtra = Extra(
      challenge: challengeJson,
      salt: principal.salt,
      iterations: principal.iterations,
      keyLen: principal.keyLen,
    );

    _pending = _CraPendingSession(
      authId: authId,
      principal: principal,
      challenge: challengeExtra,
      sessionId: context.sessionId,
    );

    final challengeFields = <String, Object?>{
      ...principal.challenge,
      'challenge': challengeJson,
      'salt': principal.salt,
      'keylen': principal.keyLen,
      'iterations': principal.iterations,
    }..removeWhere((_, value) => value == null);

    return AuthResult.challenge(
      AuthChallenge(challenge: challengeFields, extra: const {}),
    );
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
          message: 'AUTHENTICATE received without pending challenge',
        ),
      );
    }

    final principal = pending.principal;
    final isValid = principal.verifySignature(
      pending.challenge,
      message.signature,
    );
    if (!isValid) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Invalid CRA signature',
        ),
      );
    }

    return AuthResult.success(_config.buildSuccess(principal, pending.authId));
  }
}

class CraAuthenticatorConfig {
  CraAuthenticatorConfig({
    required this.realm,
    required this.principals,
    required this.defaultSecret,
    required this.challengeTemplate,
    required this.defaultRole,
    required this.defaultProvider,
    required this.defaultExtra,
  });

  final RealmSettings realm;
  final Map<String, CraPrincipal> principals;
  final String? defaultSecret;
  final Map<String, Object?> challengeTemplate;
  final String defaultRole;
  final String defaultProvider;
  final Map<String, Object?> defaultExtra;

  factory CraAuthenticatorConfig.parse(
    Map<String, Object?> options,
    RealmSettings realm,
  ) {
    final challengeTemplate = _asMap(options['challenge']);

    final principalEntries = <String, CraPrincipal>{};
    final secretsNode = options['secrets'];
    if (secretsNode is Map) {
      secretsNode.forEach((key, value) {
        if (key is! String) {
          throw ArgumentError.value(key, 'secrets key', 'must be string');
        }
        principalEntries[key] = CraPrincipal.parse(key, value);
      });
    }

    final principalsNode = options['principals'];
    if (principalsNode is List) {
      for (final entry in principalsNode) {
        if (entry is! Map<String, Object?>) {
          throw ArgumentError('Each principal must be a map');
        }
        final authId = entry['authid'] as String?;
        if (authId == null || authId.isEmpty) {
          throw ArgumentError('principal.authid is required');
        }
        principalEntries[authId] = CraPrincipal.parse(authId, entry);
      }
    }

    final defaultSecret = options['default_secret'] as String?;
    final defaultRole = options['default_role'] as String? ?? 'anonymous';
    final defaultProvider = options['default_provider'] as String? ?? 'static';
    final defaultExtra = _asMap(options['default_extra']);

    return CraAuthenticatorConfig(
      realm: realm,
      principals: Map<String, CraPrincipal>.unmodifiable(principalEntries),
      defaultSecret: defaultSecret,
      challengeTemplate: challengeTemplate,
      defaultRole: defaultRole,
      defaultProvider: defaultProvider,
      defaultExtra: defaultExtra,
    );
  }

  CraPrincipal? principalFor(String authId) {
    final principal = principals[authId];
    if (principal != null) {
      return principal;
    }
    if (defaultSecret != null) {
      return CraPrincipal(authId: authId, secret: defaultSecret!);
    }
    return null;
  }

  AuthSuccess buildSuccess(CraPrincipal principal, String authId) {
    final role = principal.role ?? defaultRole;
    final provider = principal.provider ?? defaultProvider;
    final authextra = Map<String, Object?>.from(defaultExtra);
    if (principal.authExtra != null) {
      authextra.addAll(principal.authExtra!);
    }
    return AuthSuccess(
      authId: authId,
      authRole: role,
      details: Map<String, Object?>.unmodifiable({
        'authprovider': provider,
        if (authextra.isNotEmpty) 'authextra': authextra,
      }),
    );
  }
}

class CraPrincipal {
  const CraPrincipal({
    required this.authId,
    this.secret,
    this.derivedKey,
    this.salt,
    this.iterations = CraAuthentication.defaultIterations,
    this.keyLen = CraAuthentication.defaultKeyLength,
    this.role,
    this.provider,
    this.authExtra,
    Map<String, Object?>? challenge,
  }) : assert(
         secret != null || derivedKey != null,
         'CRA principal must provide secret or derivedKey',
       ),
       challenge = challenge ?? const {};

  final String authId;
  final String? secret;
  final String? derivedKey;
  final String? salt;
  final int iterations;
  final int keyLen;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
  final Map<String, Object?> challenge;

  bool verifySignature(Extra challenge, String signature) {
    if (derivedKey != null) {
      if (challenge.challenge == null) {
        return false;
      }
      final resolvedKeyLen = challenge.keyLen == null || challenge.keyLen! <= 0
          ? keyLen
          : challenge.keyLen!;
      final expected = CraAuthentication.encodeHmac(
        Uint8List.fromList(derivedKey!.codeUnits),
        resolvedKeyLen,
        Uint8List.fromList(challenge.challenge!.codeUnits),
      );
      return expected == signature;
    }
    if (secret != null) {
      return CraAuthentication.verifySignature(
        secret: secret!,
        challenge: challenge,
        signature: signature,
      );
    }
    return false;
  }

  factory CraPrincipal.parse(String authId, Object? value) {
    if (value is String) {
      return CraPrincipal(authId: authId, secret: value);
    }
    if (value is Map<String, Object?>) {
      final secret = value['secret'] as String?;
      final derivedKey = value['derived_key'] as String?;
      if (secret == null && derivedKey == null) {
        throw ArgumentError(
          'principal.secret or principal.derived_key is required for CRA',
        );
      }
      return CraPrincipal(
        authId: authId,
        secret: secret,
        derivedKey: derivedKey,
        salt: value['salt'] as String?,
        iterations:
            value['iterations'] as int? ?? CraAuthentication.defaultIterations,
        keyLen: value['keylen'] as int? ?? CraAuthentication.defaultKeyLength,
        role: value['role'] as String?,
        provider: value['provider'] as String?,
        authExtra: _asMap(value['authextra']),
        challenge: _asMap(value['challenge']),
      );
    }
    throw ArgumentError.value(
      value,
      'principal',
      'Expected string or map for CRA principal',
    );
  }
}

class _CraPendingSession {
  _CraPendingSession({
    required this.authId,
    required this.principal,
    required this.challenge,
    required this.sessionId,
  });

  final String authId;
  final CraPrincipal principal;
  final Extra challenge;
  final int sessionId;
}

String _generateNonce([int length = 32]) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64Url.encode(bytes);
}

Map<String, Object?> _asMap(Object? value) {
  if (value == null) {
    return const {};
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  throw ArgumentError.value(value, 'map', 'Expected a string-keyed map');
}
