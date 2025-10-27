import 'dart:math';

import 'package:connectanum_core/authentication.dart'
    show CryptosignAuthentication;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;

import '../config/authenticator.dart';
import '../config/router_settings.dart';

class CryptosignAuthenticatorFactory extends AuthenticatorFactory {
  const CryptosignAuthenticatorFactory();

  @override
  String get method => 'cryptosign';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    final config = CryptosignAuthenticatorConfig.parse(options, realm);
    return CryptosignAuthenticator(config);
  }
}

class CryptosignAuthenticator extends Authenticator {
  CryptosignAuthenticator(this._config);

  final CryptosignAuthenticatorConfig _config;
  _CryptosignPendingSession? _pending;

  @override
  String get method => 'cryptosign';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    final authId =
        context.helloDetails['authid'] as String? ??
        context.helloDetails['authId'] as String?;
    if (authId == null || authId.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'authid is required for cryptosign',
        ),
      );
    }

    final principal = _config.principalFor(authId);
    if (principal == null) {
      return AuthResult.failure(
        AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Unknown principal "$authId"',
        ),
      );
    }

    final helloExtra =
        context.helloDetails['authextra'] as Map<String, Object?>?;
    final clientPubKey = helloExtra?['pubkey'] as String?;
    if (clientPubKey == null ||
        clientPubKey.toLowerCase() != principal.publicKey.toLowerCase()) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Client public key mismatch',
        ),
      );
    }

    final challenge = _randomHex(64);
    _pending = _CryptosignPendingSession(
      authId: authId,
      principal: principal,
      challenge: challenge,
      sessionId: context.sessionId,
    );

    final challengeFields = <String, Object?>{
      'challenge': challenge,
      'channel_binding': principal.channelBinding,
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
          message: 'AUTHENTICATE received without cryptosign challenge',
        ),
      );
    }

    final Map<String, Object?>? extra = message.extra;
    final channelBinding = extra == null
        ? null
        : extra['channel_binding'] as String?;
    if (pending.principal.channelBinding != channelBinding) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Channel binding mismatch',
        ),
      );
    }

    final signatureHex = message.signature;
    if (signatureHex.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Missing cryptosign signature',
        ),
      );
    }

    final isValid = CryptosignAuthentication.verifySignature(
      publicKeyHex: pending.principal.publicKey,
      signatureHex: signatureHex,
      challengeHex: pending.challenge,
    );
    if (!isValid) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Invalid cryptosign signature',
        ),
      );
    }

    return AuthResult.success(
      _config.buildSuccess(pending.principal, pending.authId),
    );
  }
}

class CryptosignAuthenticatorConfig {
  CryptosignAuthenticatorConfig({
    required this.realm,
    required this.principals,
    required this.defaultRole,
    required this.defaultProvider,
    required this.defaultExtra,
  });

  final RealmSettings realm;
  final Map<String, CryptosignPrincipal> principals;
  final String defaultRole;
  final String defaultProvider;
  final Map<String, Object?> defaultExtra;

  factory CryptosignAuthenticatorConfig.parse(
    Map<String, Object?> options,
    RealmSettings realm,
  ) {
    final entryMap = <String, CryptosignPrincipal>{};
    final principalsNode = options['principals'];
    if (principalsNode is Map<String, Object?>) {
      for (final entry in principalsNode.entries) {
        entryMap[entry.key] = CryptosignPrincipal.parse(entry.key, entry.value);
      }
    }
    final listNode = options['principals_list'];
    if (listNode is List) {
      for (final item in listNode) {
        if (item is! Map<String, Object?>) {
          throw ArgumentError('Each principal must be a map');
        }
        final authId = item['authid'] as String?;
        if (authId == null || authId.isEmpty) {
          throw ArgumentError('principal.authid is required');
        }
        entryMap[authId] = CryptosignPrincipal.parse(authId, item);
      }
    }

    final defaultRole = options['default_role'] as String? ?? 'anonymous';
    final defaultProvider = options['default_provider'] as String? ?? 'static';
    final defaultExtra = _asMap(options['default_extra']);

    return CryptosignAuthenticatorConfig(
      realm: realm,
      principals: Map<String, CryptosignPrincipal>.unmodifiable(entryMap),
      defaultRole: defaultRole,
      defaultProvider: defaultProvider,
      defaultExtra: defaultExtra,
    );
  }

  CryptosignPrincipal? principalFor(String authId) => principals[authId];

  AuthSuccess buildSuccess(CryptosignPrincipal principal, String authId) {
    final role = principal.role ?? defaultRole;
    final provider = principal.provider ?? defaultProvider;
    final authextra = Map<String, Object?>.from(defaultExtra);
    if (principal.authExtra != null) {
      authextra.addAll(principal.authExtra!);
    }
    authextra['pubkey'] = principal.publicKey;
    if (principal.channelBinding != null) {
      authextra['channel_binding'] = principal.channelBinding;
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

class CryptosignPrincipal {
  const CryptosignPrincipal({
    required this.authId,
    required this.publicKey,
    this.channelBinding,
    this.role,
    this.provider,
    this.authExtra,
  });

  final String authId;
  final String publicKey;
  final String? channelBinding;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;

  factory CryptosignPrincipal.parse(String authId, Object? value) {
    if (value is String) {
      return CryptosignPrincipal(authId: authId, publicKey: value);
    }
    if (value is Map<String, Object?>) {
      final pubkey = value['pubkey'] as String?;
      if (pubkey == null || pubkey.isEmpty) {
        throw ArgumentError('principal.pubkey is required for cryptosign');
      }
      return CryptosignPrincipal(
        authId: authId,
        publicKey: pubkey,
        channelBinding: value['channel_binding'] as String?,
        role: value['role'] as String?,
        provider: value['provider'] as String?,
        authExtra: _asMap(value['authextra']),
      );
    }
    throw ArgumentError.value(
      value,
      'principal',
      'Expected string or map for cryptosign principal',
    );
  }
}

class _CryptosignPendingSession {
  _CryptosignPendingSession({
    required this.authId,
    required this.principal,
    required this.challenge,
    required this.sessionId,
  });

  final String authId;
  final CryptosignPrincipal principal;
  final String challenge;
  final int sessionId;
}

String _randomHex(int length) {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(random.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
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
