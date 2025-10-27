import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core show Error;
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/auth/default_authenticators.dart';
import 'package:connectanum_router/src/router/auth/remote_authenticator.dart';
import 'package:connectanum_router/src/router/auth/security.dart';
import 'package:connectanum_router/src/router/config/auth_registry.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';

void main() {
  final serializer = json_serializer.Serializer();

  setUp(() {
    AuthenticatorRegistry.clear();
    registerDefaultAuthenticators();
    AuthAuditLogger.clearSink();
    AuthSecurityTracker.reset();
    AuthCredentialRegistry.reset();
    RemoteAuthenticatorRegistry.clear();
    RemoteAuthenticator.resetRateLimiter();
  });

  tearDown(() {
    AuthenticatorRegistry.clear();
    RemoteAuthenticatorRegistry.clear();
    AuthAuditLogger.clearSink();
    AuthCredentialRegistry.reset();
    RemoteAuthenticator.resetRateLimiter();
  });

  group('Ticket authenticator', () {
    test('accepts correct ticket', () async {
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['ticket'],
        realmOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: const ['ticket'],
        authenticators: const {
          'ticket-basic': AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                'user-1': {
                  'ticket': 'signed-token',
                  'role': 'member',
                  'provider': 'ticket-db',
                  'authextra': {'source': 'config'},
                },
              },
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'ticket', authId: 'user-1');
      final ticketAuth = TicketAuthentication('signed-token');
      final authenticate = await ticketAuth.challenge(
        context.lastChallenge!.extra,
      );
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isA<Welcome>());
      expect(context.lastWelcome!.details.authprovider, equals('ticket-db'));
      expect(context.openedSessions.single.authId, equals('user-1'));
    });

    test('rejects invalid ticket', () async {
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['ticket'],
        realmOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: const ['ticket'],
        authenticators: const {
          'ticket-basic': AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {'user-1': 'expected'},
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'ticket', authId: 'user-1');
      final wrongAuth = Authenticate(signature: 'wrong');
      await context.performAuthenticate(wrongAuth);

      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });

    test('resolves ticket via credential provider', () async {
      AuthCredentialRegistry.registerProvider(
        _InMemoryCredentialProvider(
          ticketCredentials: {
            _InMemoryCredentialProvider.key(
              'realm1',
              'user-db',
            ): TicketCredential(
              ticket: 'external-secret',
              role: 'member',
              provider: 'db',
              authExtra: {'source': 'database'},
            ),
          },
        ),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['ticket'],
        realmOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: const ['ticket'],
        authenticators: const {
          'ticket-basic': AuthenticatorDefinition(
            type: 'ticket',
            options: {'secrets': {}},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'ticket', authId: 'user-db');
      final ticketAuth = TicketAuthentication('external-secret');
      final authenticate = await ticketAuth.challenge(
        context.lastChallenge!.extra,
      );
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isA<Welcome>());
      expect(context.openedSessions.single.authId, equals('user-db'));
      expect(
        context.lastWelcome!.details.authextra?['source'],
        equals('database'),
      );
    });

    test('emits repo rejection as abort with arguments', () async {
      final events = <CredentialLookupEvent>[];
      AuthCredentialRegistry.registerListener(events.add);
      AuthCredentialRegistry.registerProvider(
        _InMemoryCredentialProvider(
          ticketRejections: {
            _InMemoryCredentialProvider.key(
              'realm1',
              'user-locked',
            ): CredentialRejection(
              reason: 'wamp.error.payment_required',
              message: 'Subscription inactive',
              arguments: const ['PAYWALL'],
              argumentsKeywords: const {'retry_after_ms': 60000},
            ),
          },
        ),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['ticket'],
        realmOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: const ['ticket'],
        authenticators: const {
          'ticket-basic': AuthenticatorDefinition(
            type: 'ticket',
            options: {'secrets': {}},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'ticket', authId: 'user-locked');

      final abort = context.lastAbort;
      expect(abort, isNotNull);
      expect(abort!.reason, equals('wamp.error.payment_required'));
      expect(abort.message?.message, contains('Subscription inactive'));
      expect(abort.arguments, equals(['PAYWALL']));
      expect(abort.argumentsKeywords?['retry_after_ms'], equals(60000));

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.hit, isFalse);
      expect(event.reason, equals('wamp.error.payment_required'));
      expect(event.argumentsKeywords?['retry_after_ms'], equals(60000));
    });
  });

  group('WAMP-CRA authenticator', () {
    test('validates HMAC signature', () async {
      final salt = base64.encode(List<int>.generate(8, (i) => i + 1));
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['wampcra'],
        realmOptions: const {
          'wampcra': {'authenticator': 'cra-basic'},
        },
        listenerMethods: const ['wampcra'],
        authenticators: {
          'cra-basic': AuthenticatorDefinition(
            type: 'wampcra',
            options: {
              'secrets': {
                'user-1': {
                  'secret': 'secret-1',
                  'salt': salt,
                  'iterations': 1000,
                  'keylen': 32,
                  'role': 'member',
                },
              },
              'challenge': {'hello': 'world'},
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final cra = CraAuthentication('secret-1');
      final helloDetails = Details.forHello()
        ..authmethods = ['wampcra']
        ..authid = 'user-1';
      await cra.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await cra.challenge(context.lastChallenge!.extra);
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isA<Welcome>());
      expect(context.openedSessions.single.authRole, equals('member'));
    });

    test('fails invalid signature', () async {
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['wampcra'],
        realmOptions: const {
          'wampcra': {'authenticator': 'cra-basic'},
        },
        listenerMethods: const ['wampcra'],
        authenticators: const {
          'cra-basic': AuthenticatorDefinition(
            type: 'wampcra',
            options: {
              'secrets': {'user-1': 'secret-1'},
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final cra = CraAuthentication('secret-1');
      final helloDetails = Details.forHello()
        ..authmethods = ['wampcra']
        ..authid = 'user-1';
      await cra.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final wrong = CraAuthentication('wrong');
      final authenticate = await wrong.challenge(context.lastChallenge!.extra);
      await context.performAuthenticate(authenticate);

      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });

    test('loads credentials from provider without plain secret', () async {
      const salt = 'static-salt';
      AuthCredentialRegistry.registerProvider(
        _InMemoryCredentialProvider(
          craCredentials: {
            _InMemoryCredentialProvider.key(
              'realm1',
              'user-db',
            ): _craCredentialFromSecret(
              secret: 'secret-1',
              salt: salt,
              iterations: 1000,
              keyLen: 32,
              role: 'member',
              provider: 'db',
              challenge: const {'hello': 'world'},
            ),
          },
        ),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['wampcra'],
        realmOptions: const {
          'wampcra': {'authenticator': 'cra-basic'},
        },
        listenerMethods: const ['wampcra'],
        authenticators: const {
          'cra-basic': AuthenticatorDefinition(
            type: 'wampcra',
            options: {'secrets': {}},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final cra = CraAuthentication('secret-1');
      final helloDetails = Details.forHello()
        ..authmethods = ['wampcra']
        ..authid = 'user-db';
      await cra.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await cra.challenge(context.lastChallenge!.extra);
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isA<Welcome>());
      expect(context.openedSessions.single.authRole, equals('member'));
    });
  });

  group('SCRAM authenticator', () {
    test('accepts valid proof', () async {
      final salt = base64.encode(List<int>.generate(16, (i) => i + 10));
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['scram'],
        realmOptions: const {
          'scram': {'authenticator': 'scram-basic'},
        },
        listenerMethods: const ['scram'],
        authenticators: {
          'scram-basic': AuthenticatorDefinition(
            type: 'scram',
            options: {
              'secrets': {
                'user-1': {
                  'secret': 'pencil',
                  'salt': salt,
                  'iterations': 4096,
                  'role': 'member',
                },
              },
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final scram = ScramAuthentication('pencil');
      final helloDetails = Details.forHello()
        ..authmethods = ['scram']
        ..authid = 'user-1';
      await scram.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await scram.challenge(context.lastChallenge!.extra);
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions.single.authRole, equals('member'));
    });

    test('rejects invalid proof', () async {
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['scram'],
        realmOptions: const {
          'scram': {'authenticator': 'scram-basic'},
        },
        listenerMethods: const ['scram'],
        authenticators: const {
          'scram-basic': AuthenticatorDefinition(
            type: 'scram',
            options: {
              'secrets': {
                'user-1': {'secret': 'pencil'},
              },
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final scram = ScramAuthentication('pencil');
      final helloDetails = Details.forHello()
        ..authmethods = ['scram']
        ..authid = 'user-1';
      await scram.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await scram.challenge(context.lastChallenge!.extra);
      final tampered = Authenticate(
        signature: '${authenticate.signature}-tampered',
      )..extra = authenticate.extra;
      await context.performAuthenticate(tampered);

      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });

    test('loads credentials from provider', () async {
      AuthCredentialRegistry.registerProvider(
        _InMemoryCredentialProvider(
          scramCredentials: {
            _InMemoryCredentialProvider.key(
              'realm1',
              'user-db',
            ): _scramCredentialFromSecret(
              password: 'pencil',
              salt: base64.encode(List<int>.generate(16, (i) => i + 10)),
              iterations: 4096,
              role: 'member',
              provider: 'db',
            ),
          },
        ),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['scram'],
        realmOptions: const {
          'scram': {'authenticator': 'scram-basic'},
        },
        listenerMethods: const ['scram'],
        authenticators: const {
          'scram-basic': AuthenticatorDefinition(
            type: 'scram',
            options: {'secrets': {}},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final scram = ScramAuthentication('pencil');
      final helloDetails = Details.forHello()
        ..authmethods = ['scram']
        ..authid = 'user-db';
      await scram.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await scram.challenge(context.lastChallenge!.extra);
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions.single.authRole, equals('member'));
    });
  });

  group('Cryptosign authenticator', () {
    test('accepts correct signature', () async {
      final signingKey = SigningKey.generate();
      final pubKey = signingKey.publicKey.encode(Base16Encoder.instance);

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['cryptosign'],
        realmOptions: const {
          'cryptosign': {'authenticator': 'cs-basic'},
        },
        listenerMethods: const ['cryptosign'],
        authenticators: {
          'cs-basic': AuthenticatorDefinition(
            type: 'cryptosign',
            options: {
              'principals': {
                'user-1': {
                  'pubkey': pubKey,
                  'role': 'member',
                  'provider': 'cs-db',
                },
              },
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final client = CryptosignAuthentication.fromBase64(
        base64.encode(signingKey.seed),
      );
      final helloDetails = Details.forHello()
        ..authmethods = ['cryptosign']
        ..authid = 'user-1';
      await client.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await client.challenge(context.lastChallenge!.extra);
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions.single.authRole, equals('member'));
    });

    test('rejects wrong signature', () async {
      final signingKey = SigningKey.generate();
      final pubKey = signingKey.publicKey.encode(Base16Encoder.instance);

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['cryptosign'],
        realmOptions: const {
          'cryptosign': {'authenticator': 'cs-basic'},
        },
        listenerMethods: const ['cryptosign'],
        authenticators: {
          'cs-basic': AuthenticatorDefinition(
            type: 'cryptosign',
            options: {
              'principals': {
                'user-1': {'pubkey': pubKey},
              },
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      final client = CryptosignAuthentication.fromBase64(
        base64.encode(signingKey.seed),
      );
      final helloDetails = Details.forHello()
        ..authmethods = ['cryptosign']
        ..authid = 'user-1';
      await client.hello('realm1', helloDetails);
      await context.performHelloWithDetails(helloDetails);
      final authenticate = await client.challenge(context.lastChallenge!.extra);
      final tamperedSignature = 'ff${authenticate.signature!.substring(2)}';
      final tampered = Authenticate(signature: tamperedSignature)
        ..extra = authenticate.extra;
      await context.performAuthenticate(tampered);

      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });
  });

  group('Remote authenticator', () {
    test('aborts when no delegate is registered', () async {
      RemoteAuthenticatorRegistry.clear();

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {'method': 'remote'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');

      expect(context.lastAbort, isNotNull);
      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
      expect(
        context.lastAbort?.message?.message,
        contains('Remote authenticator delegate "default" not registered'),
      );
    });

    test('delegates to registered handler', () async {
      final delegate = _TestRemoteDelegate();
      RemoteAuthenticatorRegistry.register(delegate);

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: const {'method': 'remote'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');
      final authenticate = Authenticate(signature: 'delegate-token')
        ..extra = {'nonce': context.lastChallenge!.extra.nonce};
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions.single.authRole, equals('member'));
    });

    test('aborts when delegate rejects authenticate', () async {
      final delegate = _TestRemoteDelegate();
      RemoteAuthenticatorRegistry.register(delegate);

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {'method': 'remote'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');
      final authenticate = Authenticate(signature: 'invalid-token')
        ..extra = {'nonce': context.lastChallenge!.extra.nonce};
      await context.performAuthenticate(authenticate);

      expect(context.lastAbort, isNotNull);
      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
      expect(context.lastAbort?.message?.message, equals('delegate rejection'));
    });

    test('fails when delegate rejects hello', () async {
      RemoteAuthenticatorRegistry.register(_FailingRemoteDelegate());

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: const {'method': 'remote'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');

      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });

    test('supports direct success without challenge', () async {
      RemoteAuthenticatorRegistry.register(_ImmediateRemoteDelegate());

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {'method': 'remote'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');

      expect(context.lastChallenge, isNull);
      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions, hasLength(1));
      expect(context.openedSessions.single.authId, equals('user-1'));
    });

    test('rejects success with disallowed role', () async {
      RemoteAuthenticatorRegistry.register(
        _RoleOverridingDelegate(disallowedRole: 'admin'),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {
              'method': 'remote',
              'allowed_roles': ['member'],
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');
      final authenticate = Authenticate(signature: 'delegate-token')
        ..extra = {'nonce': context.lastChallenge!.extra.nonce};
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNull);
      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });

    test('rejects success with disallowed provider', () async {
      RemoteAuthenticatorRegistry.register(
        _ImmediateRemoteDelegate(provider: 'other-provider'),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {
              'method': 'remote',
              'allowed_providers': ['remote'],
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');

      expect(context.lastWelcome, isNull);
      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
    });

    test('applies rate limiting and backoff', () async {
      RemoteAuthenticator.resetRateLimiter();
      final delegate = _CountingFailingRemoteDelegate();
      RemoteAuthenticatorRegistry.register(delegate);

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {
              'method': 'remote',
              'allowed_roles': ['member'],
              'rate_limit_max_attempts': 1,
              'rate_limit_window_ms': 60000,
              'backoff_base_ms': 500,
              'backoff_factor': 2,
              'backoff_max_ms': 60000,
            },
          ),
        },
      );

      final first = _HandshakeHarness(routerSettings, serializer);
      await first.performHello(authMethod: 'remote', authId: 'user-rl');
      expect(first.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
      expect(delegate.helloCount, equals(1));

      final second = _HandshakeHarness(routerSettings, serializer);
      await second.performHello(authMethod: 'remote', authId: 'user-rl');
      expect(second.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
      expect(
        second.lastAbort?.message?.message ?? '',
        contains('rate limited'),
      );
      expect(delegate.helloCount, equals(1));
    });

    test('passes auth token to delegate', () async {
      RemoteAuthenticatorRegistry.clear();
      RemoteAuthenticatorRegistry.register(
        _TokenAwareRemoteDelegate(expectedToken: 'secret-token'),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {'method': 'remote', 'auth_token': 'secret-token'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-token');
      final authenticate = Authenticate(signature: 'delegate-token')
        ..extra = {'nonce': context.lastChallenge!.extra.nonce};
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions.single.authRole, equals('member'));
    });

    test('rejects when auth token mismatches', () async {
      RemoteAuthenticatorRegistry.clear();
      RemoteAuthenticatorRegistry.register(
        _TokenAwareRemoteDelegate(expectedToken: 'secret-token'),
      );

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {'method': 'remote', 'auth_token': 'wrong-token'},
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-token');

      expect(context.lastWelcome, isNull);
      expect(context.lastAbort?.reason, equals(wamp_core.Error.notAuthorized));
      expect(context.lastAbort?.message?.message, contains('token rejected'));
    });

    test('fails over to secondary delegate when primary unavailable', () async {
      RemoteAuthenticatorRegistry.clear();
      RemoteAuthenticatorRegistry.register(
        _UnavailableRemoteDelegate(),
        id: 'primary',
      );
      final secondary = _TestRemoteDelegate();
      RemoteAuthenticatorRegistry.register(secondary, id: 'secondary');

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['remote'],
        realmOptions: const {
          'remote': {'authenticator': 'remote-basic'},
        },
        listenerMethods: const ['remote'],
        authenticators: const {
          'remote-basic': AuthenticatorDefinition(
            type: 'remote',
            options: {
              'method': 'remote',
              'delegates': ['primary', 'secondary'],
              'delegate_retry_ms': 60000,
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'remote', authId: 'user-1');
      final authenticate = Authenticate(signature: 'delegate-token')
        ..extra = {'nonce': context.lastChallenge!.extra.nonce};
      await context.performAuthenticate(authenticate);

      expect(context.lastWelcome, isNotNull);
      expect(context.openedSessions.single.authRole, equals('member'));
      expect(secondary.lastTransactionId, isNotNull);
    });
  });

  group('Authentication security', () {
    test('enforces lockout after consecutive failures', () async {
      final routerSettings = _buildRouterSettings(
        realmMethods: const ['ticket'],
        realmOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: const ['ticket'],
        authenticators: const {
          'ticket-basic': AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {'user-1': 'secret'},
            },
          ),
        },
        limits: const RealmLimitSettings(maxFailedAuth: 2, lockoutMs: 5000),
      );

      Future<void> _attempt(String signature) async {
        final context = _HandshakeHarness(routerSettings, serializer);
        await context.performHello(authMethod: 'ticket', authId: 'user-1');
        await context.performAuthenticate(Authenticate(signature: signature));
        expect(context.lastAbort, isNotNull);
      }

      await _attempt('wrong');
      await _attempt('wrong');

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'ticket', authId: 'user-1');
      expect(context.lastAbort?.message?.message, contains('Too many'));
    });

    test('emits audit events for success and failure', () async {
      final events = <AuthAuditEvent>[];
      AuthAuditLogger.registerSink(events.add);

      final routerSettings = _buildRouterSettings(
        realmMethods: const ['ticket'],
        realmOptions: const {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: const ['ticket'],
        authenticators: const {
          'ticket-basic': AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {'user-1': 'secret'},
            },
          ),
        },
      );

      final context = _HandshakeHarness(routerSettings, serializer);
      await context.performHello(authMethod: 'ticket', authId: 'user-1');
      await context.performAuthenticate(Authenticate(signature: 'secret'));

      expect(
        events.any((event) => event.outcome == AuthAuditOutcome.success),
        isTrue,
      );

      events.clear();

      final failContext = _HandshakeHarness(routerSettings, serializer);
      await failContext.performHello(authMethod: 'ticket', authId: 'user-1');
      await failContext.performAuthenticate(Authenticate(signature: 'bad'));

      expect(
        events.any((event) => event.outcome == AuthAuditOutcome.failure),
        isTrue,
      );
    });
  });
}

class _HandshakeHarness {
  _HandshakeHarness(this.settings, this.serializer) {
    AuthenticatorRegistry.clear();
    registerDefaultAuthenticators();
    final listener = _buildListener();
    state =
        createWorkerStateForTest(
              listener: listener,
              listenerSettings: settings.listeners.first,
            )
            as WorkerConnectionState;
    state.serializer = NativeMessageSerializer.json;
    bossPort = ReceivePort();
    bossPort.listen((dynamic message) {
      if (message is Map<String, Object?>) {
        bossMessages.add(message);
      }
    });
    statePort = ReceivePort();
    statePort.listen((dynamic message) {
      if (message is SessionAllocateIdCommand) {
        message.replyPort.send(allocatedSessionId++);
        return;
      }
      if (message is RouterStateCommand) {
        switch (message) {
          case SessionOpenCommand(:final session):
            openedSessions.add(session);
        }
      }
    });
  }

  final RouterSettings settings;
  final json_serializer.Serializer serializer;
  late final WorkerConnectionState state;
  late final ReceivePort bossPort;
  late final ReceivePort statePort;
  final List<Map<String, Object?>> bossMessages = [];
  final List<SessionRecord> openedSessions = [];
  Challenge? lastChallenge;
  Welcome? lastWelcome;
  Abort? lastAbort;
  int allocatedSessionId = 100;

  Future<void> performHello({
    required String authMethod,
    required String authId,
  }) async {
    final details = Details.forHello()
      ..authmethods = [authMethod]
      ..authid = authId;
    await performHelloWithDetails(details);
  }

  Future<void> performHelloWithDetails(Details details) async {
    final hello = Hello('realm1', details);
    await handleHelloForTest(
      bossPort.sendPort,
      statePort.sendPort,
      settings,
      state,
      hello,
      10,
      null,
      11,
    );
    await Future<void>.delayed(Duration.zero);
    final workerSend = _extractWorkerSend(bossMessages);
    final frame = serializer.deserialize(workerSend['payload'] as Uint8List);
    if (frame is Challenge) {
      lastChallenge = frame;
    } else if (frame is Welcome) {
      lastWelcome = frame;
    } else if (frame is Abort) {
      lastAbort = frame;
    }
    bossMessages.clear();
  }

  Future<void> performAuthenticate(Authenticate authenticate) async {
    await handleAuthenticateForTest(
      bossPort.sendPort,
      statePort.sendPort,
      null,
      state,
      authenticate,
      10,
      11,
    );
    await Future<void>.delayed(Duration.zero);
    if (bossMessages.isEmpty) {
      return;
    }
    final workerSend = _extractWorkerSend(bossMessages);
    final frame = serializer.deserialize(workerSend['payload'] as Uint8List);
    if (frame is Welcome) {
      lastWelcome = frame;
    } else if (frame is Abort) {
      lastAbort = frame;
    }
    bossMessages.clear();
  }
}

ScramCredential _scramCredentialFromSecret({
  required String password,
  required String salt,
  int iterations = 4096,
  int? memory,
  String kdf = ScramAuthentication.kdfPbkdf2,
  String? role,
  String? provider,
  Map<String, Object?>? authExtra,
}) {
  final secrets = ScramAuthentication.deriveServerSecrets(
    secret: password,
    salt: salt,
    kdf: kdf,
    iterations: iterations,
    memory: memory,
  );
  return ScramCredential(
    storedKey: secrets.storedKey,
    serverKey: secrets.serverKey,
    salt: salt,
    iterations: iterations,
    memory: memory,
    kdf: kdf,
    role: role,
    provider: provider,
    authExtra: authExtra,
  );
}

CraCredential _craCredentialFromSecret({
  required String secret,
  String? salt,
  int iterations = CraAuthentication.defaultIterations,
  int keyLen = CraAuthentication.defaultKeyLength,
  String? role,
  String? provider,
  Map<String, Object?>? authExtra,
  Map<String, Object?>? challenge,
}) {
  final derivedKey = salt == null
      ? base64.encode(secret.codeUnits)
      : base64.encode(
          CraAuthentication.deriveKey(
            secret,
            salt.codeUnits,
            iterations: iterations,
            keylen: keyLen,
          ),
        );
  return CraCredential(
    derivedKey: derivedKey,
    salt: salt,
    iterations: iterations,
    keyLen: keyLen,
    role: role,
    provider: provider,
    authExtra: authExtra,
    challenge: challenge,
  );
}

class _InMemoryCredentialProvider extends AuthCredentialProvider {
  _InMemoryCredentialProvider({
    Map<String, TicketCredential>? ticketCredentials,
    Map<String, CredentialRejection>? ticketRejections,
    Map<String, CraCredential>? craCredentials,
    Map<String, CredentialRejection>? craRejections,
    Map<String, ScramCredential>? scramCredentials,
    Map<String, CredentialRejection>? scramRejections,
    Map<String, CryptosignCredential>? cryptosignCredentials,
    Map<String, CredentialRejection>? cryptosignRejections,
  }) : ticketCredentials = ticketCredentials ?? const {},
       ticketRejections = ticketRejections ?? const {},
       craCredentials = craCredentials ?? const {},
       craRejections = craRejections ?? const {},
       scramCredentials = scramCredentials ?? const {},
       scramRejections = scramRejections ?? const {},
       cryptosignCredentials = cryptosignCredentials ?? const {},
       cryptosignRejections = cryptosignRejections ?? const {};

  static String key(String realm, String authId) => '$realm::$authId';

  final Map<String, TicketCredential> ticketCredentials;
  final Map<String, CredentialRejection> ticketRejections;
  final Map<String, CraCredential> craCredentials;
  final Map<String, CredentialRejection> craRejections;
  final Map<String, ScramCredential> scramCredentials;
  final Map<String, CredentialRejection> scramRejections;
  final Map<String, CryptosignCredential> cryptosignCredentials;
  final Map<String, CredentialRejection> cryptosignRejections;

  @override
  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = ticketRejections[key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return ticketCredentials[key(realmUri, authId)];
  }

  @override
  Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = craRejections[key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return craCredentials[key(realmUri, authId)];
  }

  @override
  Future<ScramCredential?> loadScram({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = scramRejections[key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return scramCredentials[key(realmUri, authId)];
  }

  @override
  Future<CryptosignCredential?> loadCryptosign({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = cryptosignRejections[key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return cryptosignCredentials[key(realmUri, authId)];
  }
}

Map<String, Object?> _extractWorkerSend(List<Map<String, Object?>> messages) {
  final workerSend = messages
      .where((message) => message['type'] == 'worker_send')
      .toList();
  expect(workerSend, isNotEmpty);
  return workerSend.last;
}

RouterSettings _buildRouterSettings({
  required List<String> realmMethods,
  required Map<String, Map<String, Object?>> realmOptions,
  required List<String> listenerMethods,
  required Map<String, AuthenticatorDefinition> authenticators,
  RealmLimitSettings limits = const RealmLimitSettings(),
}) {
  final realm = RealmSettings(
    name: 'realm1',
    autoCreate: false,
    auth: RealmAuthSettings(methods: realmMethods, methodOptions: realmOptions),
    roles: const [],
    limits: limits,
  );

  final listener = ListenerSettings(
    type: 'rawsocket',
    endpoint: '127.0.0.1:7000',
    authmethods: listenerMethods,
    options: const {},
  );

  return RouterSettings(
    realms: [realm],
    listeners: [listener],
    metrics: null,
    authenticators: authenticators,
  );
}

RouterListener _buildListener() => RouterListener(
  listenerId: 1,
  endpoint: Endpoint(
    host: '127.0.0.1',
    port: 7000,
    tlsMode: TlsMode.disabled,
    maxRawSocketSizeExponent: 16,
  ),
  port: 7000,
);

class _UnavailableRemoteDelegate implements RemoteAuthenticatorDelegate {
  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    throw RemoteDelegateUnavailableException('primary unavailable');
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    throw RemoteDelegateUnavailableException('primary unavailable');
  }
}

class _TestRemoteDelegate implements RemoteAuthenticatorDelegate {
  String? lastTransactionId;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    final authId =
        request.context.helloDetails['authid'] as String? ?? 'unknown';
    lastTransactionId = request.transactionId;
    return RemoteHelloResponse.challenge(
      RemoteChallenge(
        challenge: const {'challenge': 'remote'},
        extra: const {'nonce': 'delegate'},
        authId: authId,
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    if (request.transactionId != lastTransactionId) {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'transaction mismatch',
        ),
      );
    }
    if (request.authenticate.signature != 'delegate-token') {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'delegate rejection',
        ),
      );
    }
    return RemoteAuthenticateResponse.success(
      AuthSuccess(
        authId: request.authId,
        authRole: 'member',
        details: const {'authprovider': 'remote'},
      ),
    );
  }
}

class _FailingRemoteDelegate implements RemoteAuthenticatorDelegate {
  String? lastTransactionId;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    lastTransactionId = request.transactionId;
    return RemoteHelloResponse.failure(
      const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Denied',
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    if (request.transactionId != lastTransactionId) {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'transaction mismatch',
        ),
      );
    }
    return RemoteAuthenticateResponse.failure(
      const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Denied',
      ),
    );
  }
}

class _ImmediateRemoteDelegate implements RemoteAuthenticatorDelegate {
  _ImmediateRemoteDelegate({this.provider = 'remote'});

  final String provider;
  String? lastTransactionId;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    final authId =
        request.context.helloDetails['authid'] as String? ?? 'anonymous';
    lastTransactionId = request.transactionId;
    return RemoteHelloResponse.success(
      AuthSuccess(
        authId: authId,
        authRole: 'member',
        details: {'authprovider': provider},
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    throw StateError('AUTHENTICATE should not be called for immediate success');
  }
}

class _RoleOverridingDelegate implements RemoteAuthenticatorDelegate {
  _RoleOverridingDelegate({required this.disallowedRole});

  final String disallowedRole;
  String? _transactionId;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    _transactionId = request.transactionId;
    final authId =
        request.context.helloDetails['authid'] as String? ?? 'unknown';
    return RemoteHelloResponse.challenge(
      RemoteChallenge(
        challenge: const {'challenge': 'remote'},
        extra: const {'nonce': 'delegate'},
        authId: authId,
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    if (request.transactionId != _transactionId) {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'transaction mismatch',
        ),
      );
    }
    if (request.authenticate.signature != 'delegate-token') {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'delegate rejection',
        ),
      );
    }
    return RemoteAuthenticateResponse.success(
      AuthSuccess(
        authId: request.authId,
        authRole: disallowedRole,
        details: const {'authprovider': 'remote'},
      ),
    );
  }
}

class _CountingFailingRemoteDelegate implements RemoteAuthenticatorDelegate {
  int helloCount = 0;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    helloCount++;
    return RemoteHelloResponse.failure(
      const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Denied',
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    return RemoteAuthenticateResponse.failure(
      const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Denied',
      ),
    );
  }
}

class _TokenAwareRemoteDelegate implements RemoteAuthenticatorDelegate {
  _TokenAwareRemoteDelegate({required this.expectedToken});

  final String expectedToken;
  String? lastTransactionId;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    final provided = request.options['auth_token'];
    if (provided != expectedToken) {
      return RemoteHelloResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'remote token rejected',
        ),
      );
    }
    lastTransactionId = request.transactionId;
    final authId = request.context.helloDetails['authid'] as String? ?? 'user';
    return RemoteHelloResponse.challenge(
      RemoteChallenge(
        authId: authId,
        challenge: const {'challenge': 'delegate-challenge'},
        extra: const {'nonce': 'delegate-nonce'},
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    if (request.transactionId != lastTransactionId) {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'transaction mismatch',
        ),
      );
    }
    if (request.authenticate.signature != 'delegate-token') {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: wamp_core.Error.notAuthorized,
          message: 'invalid delegate token',
        ),
      );
    }
    return RemoteAuthenticateResponse.success(
      AuthSuccess(
        authId: request.authId,
        authRole: 'member',
        details: const {'authprovider': 'remote-token'},
      ),
    );
  }
}
