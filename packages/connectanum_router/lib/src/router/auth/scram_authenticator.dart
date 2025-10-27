import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart' show ScramAuthentication;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/src/message/challenge.dart' show Extra;

import '../config/authenticator.dart';
import '../config/router_settings.dart';
import 'credentials.dart';

class ScramAuthenticatorFactory extends AuthenticatorFactory {
  const ScramAuthenticatorFactory();

  @override
  String get method => 'scram';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    final config = ScramAuthenticatorConfig.parse(options, realm);
    return ScramAuthenticator(config);
  }
}

class ScramAuthenticator extends Authenticator {
  ScramAuthenticator(this._config);

  final ScramAuthenticatorConfig _config;
  _ScramPendingSession? _pending;

  @override
  String get method => 'scram';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    final helloDetails = context.helloDetails;
    final authId = helloDetails['authid'] as String?;
    if (authId == null || authId.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'authid is required for SCRAM',
        ),
      );
    }

    ScramPrincipal? principal = _config.principalFor(authId);
    if (principal == null) {
      try {
        final external = await AuthCredentialRegistry.loadScram(
          realmUri: _config.realm.name,
          authId: authId,
        );
        if (external != null) {
          principal = ScramPrincipal(
            authId: authId,
            secret: external.secret,
            storedKey: external.storedKey,
            serverKey: external.serverKey,
            salt: external.salt,
            iterations: external.iterations ?? 4096,
            memory: external.memory,
            kdf: external.kdf ?? ScramAuthentication.kdfPbkdf2,
            role: external.role,
            provider: external.provider,
            authExtra: external.authExtra,
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

    final helloExtra = helloDetails['authextra'] as Map<String, Object?>?;
    final clientNonce = helloExtra?['nonce'] as String?;
    if (clientNonce == null || clientNonce.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.protocolViolation,
          message: 'SCRAM client must send authextra.nonce',
        ),
      );
    }

    final serverNonce = _randomNonce();
    final combinedNonce = '$clientNonce$serverNonce';

    final challengeExtra = Extra(
      nonce: combinedNonce,
      salt: principal.salt,
      iterations: principal.iterations,
      memory: principal.memory,
      kdf: principal.kdf,
    );

    _pending = _ScramPendingSession(
      authId: authId,
      principal: principal,
      clientNonce: clientNonce,
      combinedNonce: combinedNonce,
      challenge: challengeExtra,
      sessionId: context.sessionId,
    );

    final challengeFields = <String, Object?>{
      'nonce': challengeExtra.nonce,
      'salt': challengeExtra.salt,
      'iterations': challengeExtra.iterations,
      'memory': challengeExtra.memory,
      'kdf': challengeExtra.kdf,
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
          message: 'AUTHENTICATE received without SCRAM challenge',
        ),
      );
    }

    final principal = pending.principal;
    final extra = Map<String, Object?>.from(message.extra);
    if (!extra.containsKey('nonce')) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'SCRAM nonce missing',
        ),
      );
    }
    final nonceEntry = extra['nonce'];
    if (nonceEntry is! String) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'SCRAM nonce missing',
        ),
      );
    }
    if (nonceEntry != pending.combinedNonce) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'SCRAM nonce mismatch',
        ),
      );
    }

    final signature = message.signature;
    if (signature.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'SCRAM signature missing',
        ),
      );
    }

    final authExtra = HashMap<String, Object?>.from(extra);
    final isValid = principal.verifySignature(
      clientSignature: signature,
      clientNonce: pending.clientNonce,
      authExtra: authExtra,
      challenge: pending.challenge,
    );

    if (!isValid) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Invalid SCRAM signature',
        ),
      );
    }

    return AuthResult.success(_config.buildSuccess(principal, pending.authId));
  }
}

class ScramAuthenticatorConfig {
  ScramAuthenticatorConfig({
    required this.realm,
    required this.principals,
    required this.defaultSecret,
    required this.defaultRole,
    required this.defaultProvider,
    required this.defaultExtra,
  });

  final RealmSettings realm;
  final Map<String, ScramPrincipal> principals;
  final String? defaultSecret;
  final String defaultRole;
  final String defaultProvider;
  final Map<String, Object?> defaultExtra;

  factory ScramAuthenticatorConfig.parse(
    Map<String, Object?> options,
    RealmSettings realm,
  ) {
    final principalEntries = <String, ScramPrincipal>{};
    final secretsNode = options['secrets'];
    if (secretsNode is Map) {
      secretsNode.forEach((key, value) {
        if (key is! String) {
          throw ArgumentError.value(key, 'secrets key', 'must be string');
        }
        principalEntries[key] = ScramPrincipal.parse(key, value);
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
        principalEntries[authId] = ScramPrincipal.parse(authId, entry);
      }
    }

    final defaultSecret = options['default_secret'] as String?;
    final defaultRole = options['default_role'] as String? ?? 'anonymous';
    final defaultProvider = options['default_provider'] as String? ?? 'static';
    final defaultExtra = _asMap(options['default_extra']);

    return ScramAuthenticatorConfig(
      realm: realm,
      principals: Map<String, ScramPrincipal>.unmodifiable(principalEntries),
      defaultSecret: defaultSecret,
      defaultRole: defaultRole,
      defaultProvider: defaultProvider,
      defaultExtra: defaultExtra,
    );
  }

  ScramPrincipal? principalFor(String authId) {
    final principal = principals[authId];
    if (principal != null) {
      return principal;
    }
    if (defaultSecret != null) {
      return ScramPrincipal(authId: authId, secret: defaultSecret!);
    }
    return null;
  }

  AuthSuccess buildSuccess(ScramPrincipal principal, String authId) {
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

class ScramPrincipal {
  ScramPrincipal({
    required this.authId,
    this.secret,
    this.storedKey,
    this.serverKey,
    String? salt,
    this.iterations = 4096,
    this.memory,
    this.kdf = 'pbkdf2',
    this.role,
    this.provider,
    this.authExtra,
  }) : assert(
         secret != null || storedKey != null,
         'SCRAM principal must provide secret or storedKey',
       ),
       assert(
         storedKey == null || salt != null,
         'SCRAM principal with storedKey must supply salt',
       ),
       salt = salt ?? _generateSalt();

  final String authId;
  final String? secret;
  final String? storedKey;
  final String? serverKey;
  final String salt;
  final int iterations;
  final int? memory;
  final String kdf;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
  Uint8List? get _storedKeyBytes =>
      storedKey != null ? Uint8List.fromList(base64.decode(storedKey!)) : null;

  factory ScramPrincipal.parse(String authId, Object? value) {
    if (value is String) {
      return ScramPrincipal(authId: authId, secret: value);
    }
    if (value is Map<String, Object?>) {
      final secret = value['secret'] as String?;
      final storedKey = value['stored_key'] as String?;
      final serverKey = value['server_key'] as String?;
      if (secret == null && storedKey == null) {
        throw ArgumentError(
          'SCRAM principal requires either secret or stored_key',
        );
      }
      final salt = value['salt'] as String?;
      if (storedKey != null && salt == null) {
        throw ArgumentError(
          'SCRAM principal with stored_key must provide salt',
        );
      }
      return ScramPrincipal(
        authId: authId,
        secret: secret,
        storedKey: storedKey,
        serverKey: serverKey,
        salt: salt,
        iterations: value['iterations'] as int? ?? 4096,
        memory: value['memory'] as int?,
        kdf: value['kdf'] as String? ?? ScramAuthentication.kdfPbkdf2,
        role: value['role'] as String?,
        provider: value['provider'] as String?,
        authExtra: _asMap(value['authextra']),
      );
    }
    throw ArgumentError.value(
      value,
      'principal',
      'Expected string or map for SCRAM principal',
    );
  }

  bool verifySignature({
    required String clientSignature,
    required String clientNonce,
    required Map<String, Object?> authExtra,
    required Extra challenge,
  }) {
    if (storedKey != null) {
      final proofBytes = base64.decode(clientSignature);
      final storedKeyBytes = _storedKeyBytes!;
      final authMessage = ScramAuthentication.createAuthMessage(
        authId,
        clientNonce,
        HashMap<String, Object?>.from(authExtra),
        challenge,
      );
      return ScramAuthentication.verifyClientProof(
        proofBytes,
        storedKeyBytes,
        authMessage,
      );
    }
    if (secret != null) {
      return ScramAuthentication.verifySignature(
        secret: secret!,
        authId: authId,
        clientNonce: clientNonce,
        authExtra: authExtra,
        challenge: challenge,
        clientSignature: clientSignature,
      );
    }
    return false;
  }
}

class _ScramPendingSession {
  _ScramPendingSession({
    required this.authId,
    required this.principal,
    required this.clientNonce,
    required this.combinedNonce,
    required this.challenge,
    required this.sessionId,
  });

  final String authId;
  final ScramPrincipal principal;
  final String clientNonce;
  final String combinedNonce;
  final Extra challenge;
  final int sessionId;
}

String _randomNonce([int length = 24]) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64Url.encode(bytes);
}

String _generateSalt([int length = 16]) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64.encode(bytes);
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
