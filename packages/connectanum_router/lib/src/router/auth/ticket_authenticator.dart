import 'package:connectanum_core/authentication.dart' show TicketAuthentication;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:meta/meta.dart';

import '../config/authenticator.dart';
import '../config/router_settings.dart';
import 'credentials.dart';

/// Built-in ticket authenticator that validates static secrets from config.
class TicketAuthenticatorFactory extends AuthenticatorFactory {
  const TicketAuthenticatorFactory();

  @override
  String get method => 'ticket';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    final config = TicketAuthenticatorConfig.parse(options, realm);
    return TicketAuthenticator(config);
  }
}

class TicketAuthenticator extends Authenticator {
  TicketAuthenticator(this._config);

  final TicketAuthenticatorConfig _config;
  _PendingSession? _pending;

  @override
  String get method => 'ticket';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    final authId =
        context.helloDetails['authid'] as String? ??
        context.helloDetails['authId'] as String?;
    if (authId == null || authId.isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'authid is required for ticket authentication',
        ),
      );
    }

    TicketPrincipal? principal = _config.principalFor(authId);
    if (principal == null) {
      try {
        final external = await AuthCredentialRegistry.loadTicket(
          realmUri: context.realm.name,
          authId: authId,
        );
        if (external != null) {
          principal = TicketPrincipal(
            authId: authId,
            ticket: external.ticket,
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

    _pending = _PendingSession(
      authId: authId,
      principal: principal,
      sessionId: context.sessionId,
    );

    if (!_config.sendChallenge) {
      return AuthResult.success(_config.buildSuccess(principal, authId));
    }

    return AuthResult.challenge(
      AuthChallenge(
        challenge: Map<String, Object?>.from(_config.challenge)
          ..addAll(principal.challenge),
        extra: const {},
      ),
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
    final expected = principal.ticket ?? _config.defaultTicket;
    if (expected == null) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'No ticket registered for principal',
        ),
      );
    }

    final isValid = TicketAuthentication.verify(
      expectedTicket: expected,
      providedSignature: message.signature,
    );
    if (!isValid) {
      return AuthResult.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'Invalid ticket',
        ),
      );
    }

    final success = _config.buildSuccess(principal, pending.authId);
    return AuthResult.success(success);
  }
}

class TicketAuthenticatorConfig {
  TicketAuthenticatorConfig({
    required this.realm,
    required this.principals,
    required this.defaultTicket,
    required this.defaultRole,
    required this.defaultProvider,
    required this.defaultExtra,
    required this.challenge,
    required this.sendChallenge,
  });

  final RealmSettings realm;
  final Map<String, TicketPrincipal> principals;
  final String? defaultTicket;
  final String defaultRole;
  final String defaultProvider;
  final Map<String, Object?> defaultExtra;
  final Map<String, Object?> challenge;
  final bool sendChallenge;

  factory TicketAuthenticatorConfig.parse(
    Map<String, Object?> options,
    RealmSettings realm,
  ) {
    final sendChallenge = options['send_challenge'] is bool
        ? options['send_challenge'] as bool
        : true;
    final challenge = _asStringObjectMap(options['challenge']);
    final principalEntries = <String, TicketPrincipal>{};
    final secretsNode = options['secrets'];
    if (secretsNode is Map) {
      secretsNode.forEach((key, value) {
        if (key is! String) {
          throw ArgumentError.value(key, 'secrets key', 'must be string');
        }
        principalEntries[key] = TicketPrincipal.parse(key, value);
      });
    }

    final principalsNode = options['principals'];
    if (principalsNode is List) {
      for (final entry in principalsNode) {
        if (entry is! Map) {
          throw ArgumentError('Each principal must be a map');
        }
        final authId = entry['authid'] as String?;
        if (authId == null || authId.isEmpty) {
          throw ArgumentError('principal.authid is required');
        }
        principalEntries[authId] = TicketPrincipal.parse(authId, entry);
      }
    }

    final defaultTicket = options['default_ticket'] as String?;
    final defaultRole = options['default_role'] as String? ?? 'anonymous';
    final defaultProvider = options['default_provider'] as String? ?? 'static';
    final defaultExtra = _asStringObjectMap(options['default_extra']);

    return TicketAuthenticatorConfig(
      realm: realm,
      principals: principalEntries,
      defaultTicket: defaultTicket,
      defaultRole: defaultRole,
      defaultProvider: defaultProvider,
      defaultExtra: defaultExtra,
      challenge: challenge,
      sendChallenge: sendChallenge,
    );
  }

  TicketPrincipal? principalFor(String authId) {
    final principal = principals[authId];
    if (principal != null) {
      return principal;
    }
    if (defaultTicket != null) {
      return TicketPrincipal(authId: authId, ticket: defaultTicket);
    }
    return null;
  }

  AuthSuccess buildSuccess(TicketPrincipal principal, String authId) {
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

@immutable
class TicketPrincipal {
  const TicketPrincipal({
    required this.authId,
    this.ticket,
    this.role,
    this.provider,
    this.authExtra,
    Map<String, Object?>? challenge,
  }) : challenge = challenge ?? const {};

  final String authId;
  final String? ticket;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
  final Map<String, Object?> challenge;

  factory TicketPrincipal.parse(String authId, Object? value) {
    if (value is String) {
      return TicketPrincipal(authId: authId, ticket: value);
    }
    if (value is Map<String, Object?>) {
      return TicketPrincipal(
        authId: authId,
        ticket: value['ticket'] as String?,
        role: value['role'] as String?,
        provider: value['provider'] as String?,
        authExtra: _asStringObjectMap(value['authextra']),
        challenge: _asStringObjectMap(value['challenge']),
      );
    }
    throw ArgumentError.value(
      value,
      'principal',
      'Expected string or map for ticket principal',
    );
  }
}

class _PendingSession {
  _PendingSession({
    required this.authId,
    required this.principal,
    required this.sessionId,
  });

  final String authId;
  final TicketPrincipal principal;
  final int sessionId;
}

Map<String, Object?> _asStringObjectMap(Object? value) {
  if (value == null) {
    return const {};
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  throw ArgumentError.value(value, 'map', 'Expected a string-keyed map');
}
