import 'dart:convert';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/src/message/challenge.dart' show Extra;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/auth.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    AuthCredentialRegistry.reset();
    AuthenticatorRegistry.clear();
    registerDefaultAuthenticators();
    AuthSecurityTracker.reset();
    AuthAuditLogger.clearSink();
  });

  group('AuthServer', () {
    test('handles ticket authenticator success path', () async {
      final settings = _buildSettings(
        authenticators: {
          'ticket-basic': const AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                'ticket-user': {
                  'ticket': 'ticket-secret',
                  'role': 'member',
                  'provider': 'static',
                },
              },
              'send_challenge': false,
            },
          ),
        },
        realmAuthMethods: ['ticket'],
        realmAuthOptions: {
          'ticket': {'authenticator': 'ticket-basic'},
        },
      );

      final server = AuthServer(settings: settings);
      final response = await server.onHello(
        RemoteHelloRequest(
          realmSettings: settings.realms.first,
          context: _helloContext(
            realm: settings.realms.first,
            authId: 'ticket-user',
            methods: ['ticket'],
          ),
          options: const {},
          transactionId: 'tx-1',
        ),
      );

      expect(response.status, RemoteHelloStatus.success);
      expect(response.success?.authId, equals('ticket-user'));
    });

    test('performs CRA challenge and authentication', () async {
      final saltBytes = List<int>.generate(16, (i) => i + 1);
      final salt = base64.encode(saltBytes);
      final settings = _buildSettings(
        authenticators: {
          'cra-basic': const AuthenticatorDefinition(
            type: 'wampcra',
            options: {
              'challenge': {'info': 'demo'},
            },
          ),
        },
        realmAuthMethods: ['wampcra'],
        realmAuthOptions: {
          'wampcra': {'authenticator': 'cra-basic'},
        },
      );

      AuthCredentialRegistry.registerProvider(
        _MapCredentialProvider(
          cra: {
            _MapCredentialProvider.key(
              settings.realms.first.name,
              'cra-user',
            ): CraCredential(
              secret: 'cra-secret',
              salt: salt,
              iterations: 1500,
              keyLen: CraAuthentication.defaultKeyLength,
              role: 'member',
            ),
          },
        ),
      );

      final server = AuthServer(settings: settings);
      final helloContext = _helloContext(
        realm: settings.realms.first,
        authId: 'cra-user',
        methods: ['wampcra'],
        extra: {'nonce': 'client-nonce'},
      );

      final helloResponse = await server.onHello(
        RemoteHelloRequest(
          realmSettings: settings.realms.first,
          context: helloContext,
          options: const {},
          transactionId: 'tx-cra',
        ),
      );

      expect(helloResponse.status, RemoteHelloStatus.challenge);
      final challenge = helloResponse.challenge!;

      final cra = CraAuthentication('cra-secret');
      final extra = Extra(
        challenge: challenge.challenge['challenge'] as String?,
        salt: challenge.challenge['salt'] as String?,
        keyLen: challenge.challenge['keylen'] as int?,
        iterations: challenge.challenge['iterations'] as int?,
      );
      final authenticate = await cra.challenge(extra);

      expect(
        CraAuthentication.verifySignature(
          secret: 'cra-secret',
          challenge: extra,
          signature: authenticate.signature ?? '',
        ),
        isTrue,
      );

      final authResponse = await server.onAuthenticate(
        RemoteAuthenticateRequest(
          realmSettings: settings.realms.first,
          context: helloContext,
          authId: 'cra-user',
          authenticate: AuthenticateMessage(
            signature: authenticate.signature ?? '',
            extra: authenticate.extra ?? const {},
          ),
          options: const {},
          transactionId: 'tx-cra',
        ),
      );

      // Debug helper in case the assertion fails.
      expect(authResponse.status, RemoteAuthenticateStatus.success);
      expect(authResponse.success?.authRole, equals('member'));
    });

    test('propagates credential rejection from provider', () async {
      final settings = _buildSettings(
        authenticators: {
          'ticket-basic': const AuthenticatorDefinition(
            type: 'ticket',
            options: {'secrets': {}},
          ),
        },
        realmAuthMethods: ['ticket'],
        realmAuthOptions: {
          'ticket': {'authenticator': 'ticket-basic'},
        },
      );

      AuthCredentialRegistry.registerProvider(
        _MapCredentialProvider(
          ticketRejections: {
            _MapCredentialProvider.key(
              settings.realms.first.name,
              'locked-user',
            ): CredentialRejection(
              reason: 'wamp.error.not_authorized',
              message: 'account locked',
              arguments: const ['LOCKED'],
              argumentsKeywords: const {'retry_after_ms': 60000},
            ),
          },
        ),
      );

      final server = AuthServer(settings: settings);
      final response = await server.onHello(
        RemoteHelloRequest(
          realmSettings: settings.realms.first,
          context: _helloContext(
            realm: settings.realms.first,
            authId: 'locked-user',
            methods: ['ticket'],
          ),
          options: const {},
          transactionId: 'tx-locked',
        ),
      );

      expect(response.status, RemoteHelloStatus.failure);
      expect(response.failure?.reason, 'wamp.error.not_authorized');
      expect(response.failure?.arguments, contains('LOCKED'));
    });

    test('requires auth token when configured', () async {
      final settings = _buildSettings(
        authenticators: {
          'ticket-basic': const AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                'token-user': {'ticket': 'token-secret', 'role': 'member'},
              },
              'send_challenge': false,
            },
          ),
        },
        realmAuthMethods: const ['ticket'],
        realmAuthOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
      );

      final server = AuthServer(
        settings: settings,
        authTokens: const ['expected'],
      );
      final failure = await server.onHello(
        RemoteHelloRequest(
          realmSettings: settings.realms.first,
          context: _helloContext(
            realm: settings.realms.first,
            authId: 'token-user',
            methods: const ['ticket'],
          ),
          options: const {},
          transactionId: 'tx-token',
        ),
      );

      expect(failure.status, RemoteHelloStatus.failure);
      expect(failure.failure?.message, contains('token rejected'));

      final ok = await server.onHello(
        RemoteHelloRequest(
          realmSettings: settings.realms.first,
          context: _helloContext(
            realm: settings.realms.first,
            authId: 'token-user',
            methods: const ['ticket'],
          ),
          options: const {'auth_token': 'expected'},
          transactionId: 'tx-token-ok',
        ),
      );

      expect(ok.status, RemoteHelloStatus.success);
    });

    test('emits fake challenge on denial when enabled', () async {
      final settings = _buildSettings(
        authenticators: {
          'ticket-basic': const AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                'ticket-user': {'ticket': 'ticket-secret', 'role': 'member'},
              },
            },
          ),
        },
        realmAuthMethods: const ['ticket'],
        realmAuthOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
      );

      final server = AuthServer(
        settings: settings,
        authTokens: const ['expected'],
        fakeChallengeOnHelloFailure: true,
      );

      final helloResponse = await server.onHello(
        RemoteHelloRequest(
          realmSettings: settings.realms.first,
          context: _helloContext(
            realm: settings.realms.first,
            authId: 'ticket-user',
            methods: const ['ticket'],
          ),
          options: const {'auth_token': 'wrong'},
          transactionId: 'tx-fake',
        ),
      );

      expect(helloResponse.status, RemoteHelloStatus.challenge);

      final authResponse = await server.onAuthenticate(
        RemoteAuthenticateRequest(
          realmSettings: settings.realms.first,
          context: _helloContext(
            realm: settings.realms.first,
            authId: 'ticket-user',
            methods: const ['ticket'],
          ),
          authId: 'ticket-user',
          authenticate: AuthenticateMessage(signature: 'ignored'),
          options: const {},
          transactionId: 'tx-fake',
        ),
      );

      expect(authResponse.status, RemoteAuthenticateStatus.failure);
      expect(
        authResponse.failure?.reason,
        wamp_core.Error.authenticationFailed,
      );
    });
  });
}

RouterSettings _buildSettings({
  required Map<String, AuthenticatorDefinition> authenticators,
  required List<String> realmAuthMethods,
  required Map<String, Map<String, Object?>> realmAuthOptions,
}) {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..setLimits(const RealmLimitSettings())
    ..addRoleFromBuilder(
      RoleSettingsBuilder('member')..addPermissionFromBuilder(
        PermissionSettingsBuilder('com.example')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const ['subscribe', 'call', 'register']),
      ),
    );

  for (final method in realmAuthMethods) {
    realmBuilder.addAuthMethod(
      method,
      options: realmAuthOptions[method] ?? const {},
    );
  }

  final settingsBuilder = RouterSettingsBuilder()
    ..addRealmFromBuilder(realmBuilder);

  authenticators.forEach(settingsBuilder.addAuthenticator);

  return settingsBuilder.build();
}

AuthenticatorContext _helloContext({
  required RealmSettings realm,
  required String authId,
  required List<String> methods,
  Map<String, Object?> extra = const {},
}) {
  final details = <String, Object?>{'authid': authId, 'authmethods': methods};
  if (extra.isNotEmpty) {
    details['authextra'] = extra;
  }
  return AuthenticatorContext(
    realm: realm,
    sessionId: 1,
    transport: const TransportMetadata(connectionId: 1),
    helloDetails: details,
  );
}

class _MapCredentialProvider extends AuthCredentialProvider {
  _MapCredentialProvider({
    Map<String, TicketCredential>? ticket,
    Map<String, CredentialRejection>? ticketRejections,
    Map<String, CraCredential>? cra,
  }) : ticket = ticket ?? const {},
       ticketRejections = ticketRejections ?? const {},
       cra = cra ?? const {};

  final Map<String, TicketCredential> ticket;
  final Map<String, CredentialRejection> ticketRejections;
  final Map<String, CraCredential> cra;

  static String key(String realm, String authId) => '$realm::$authId';

  @override
  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = ticketRejections[key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return ticket[key(realmUri, authId)];
  }

  @override
  Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async => cra[key(realmUri, authId)];
}
