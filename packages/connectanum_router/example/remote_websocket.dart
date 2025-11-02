// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main(List<String> args) async {
  // Ensure built-in authenticators are available.
  registerDefaultAuthenticators();
  AuthSecurityTracker.reset();
  AuthAuditLogger.registerSink(
    (event) => print(
      '[audit:${event.outcome.name}] ${event.realmUri} ${event.authId ?? '-'} ${event.method} ${event.message ?? ''}',
    ),
  );

  // Configure credential provider used by the remote auth server.
  AuthCredentialRegistry.registerProvider(_DemoCredentialProvider());

  const sharedToken = 'demo-shared-token';

  final remoteSettings = _buildRemoteRealmSettings();
  final authServer = AuthServer(
    settings: remoteSettings,
    authTokens: const [sharedToken],
    fakeChallengeOnHelloFailure: true,
  );
  RemoteAuthenticatorRegistry.register(authServer, id: 'local-auth-server');

  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(
      libraryPath: args.isNotEmpty ? args.first : null,
    );
  } on ArgumentError catch (error) {
    stderr.writeln('Failed to load native runtime: ${error.message}');
    return;
  }

  runtime.setListenerCallbacks(
    onStarted: (listenerId, status) {
      print('listener $listenerId status=$status');
    },
    onConnection: (listenerId, connectionId) {
      print('listener $listenerId accepted connection $connectionId');
    },
  );

  runtime.start();
  print('native runtime started');

  final routerSettings = _buildRouterSettings(sharedToken);
  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 8085,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
          webSocketPath: '/ws',
        ),
      ],
    ),
    settings: routerSettings,
  );

  final binding = router.start(runtime);
  for (final listener in binding.listeners) {
    print(
      'listener ${listener.listenerId} bound to ${listener.endpoint.host}:${listener.port} (ws path: ${listener.endpoint.webSocketPath ?? '/ws'})',
    );
  }

  print('''Remote auth demo ready. Try connecting a WAMP client using:
  • WebSocket URL: ws://127.0.0.1:${binding.listeners.first.port}${binding.listeners.first.endpoint.webSocketPath ?? '/ws'}
  • Realm: demo.realm
  • Auth methods: ticket / wampcra / scram / remote
  • Example users:
      - ticket.alice  (ticket="ticket-alice-secret")
      - cra.alice     (secret="cra-secret", send nonce)
      - scram.alice   (secret="scram-secret", send nonce)
      - remote.user   (delegated user, send signature "delegate-token")''');

  final subscription = binding
      .watchNativeMessages(
        pollInterval: const Duration(milliseconds: 10),
        maxMessagesPerTick: 128,
      )
      .listen((routerMessage) {
        routerMessage.message.dispose();
      });

  final sigint = ProcessSignal.sigint.watch().first;
  final sigterm = ProcessSignal.sigterm.watch().first;
  await Future.any([sigint, sigterm]);

  await subscription.cancel();
  await binding.dispose();
  runtime.shutdown();
  runtime.dispose();
  AuthCredentialRegistry.reset();
  RemoteAuthenticatorRegistry.clear();
  RemoteAuthenticator.resetRateLimiter();
  AuthAuditLogger.clearSink();
}

RouterSettings _buildRemoteRealmSettings() {
  final builder = RouterSettingsBuilder()
    ..addAuthenticator(
      'ticket-remote',
      const AuthenticatorDefinition(type: 'ticket', options: {'secrets': {}}),
    )
    ..addAuthenticator(
      'cra-remote',
      const AuthenticatorDefinition(
        type: 'wampcra',
        options: {
          'challenge': {'motd': 'remote demo'},
        },
      ),
    )
    ..addAuthenticator(
      'scram-remote',
      const AuthenticatorDefinition(type: 'scram'),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder('demo.realm')
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod('ticket', options: {'authenticator': 'ticket-remote'})
        ..addAuthMethod('wampcra', options: {'authenticator': 'cra-remote'})
        ..addAuthMethod('scram', options: {'authenticator': 'scram-remote'})
        ..addAuthMethod('remote', options: {'authenticator': 'remote-delegate'})
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['subscribe', 'call', 'register']),
          ),
        ),
    )
    ..addAuthenticator(
      'remote-delegate',
      const AuthenticatorDefinition(
        type: 'remote',
        options: {
          'method': 'remote',
          'delegates': ['local-auth-server'],
        },
      ),
    );

  return builder.build();
}

RouterSettings _buildRouterSettings(String sharedToken) {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('demo.realm')
        ..setLimits(
          const RealmLimitSettings(maxFailedAuth: 3, lockoutMs: 15000),
        )
        ..addAuthMethod(
          'remote',
          options: {
            'authenticator': 'remote-delegate',
            'delegates': ['local-auth-server'],
            'delegate_retry_ms': 5000,
            'auth_token': sharedToken,
          },
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('remote-member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const [
                'subscribe',
                'call',
                'register',
                'publish',
              ]),
          ),
        ),
    )
    ..addAuthenticator(
      'remote-delegate',
      const AuthenticatorDefinition(
        type: 'remote',
        options: {
          'method': 'remote',
          'delegates': ['local-auth-server'],
          'allowed_roles': ['remote-member'],
          'delegate_retry_ms': 5000,
        },
      ),
    );

  return builder.build();
}

class _DemoCredentialProvider extends AuthCredentialProvider {
  _DemoCredentialProvider() {
    _ticket[_key('demo.realm', 'ticket.alice')] = TicketCredential(
      ticket: 'ticket-alice-secret',
      role: 'remote-member',
      provider: 'demo',
    );

    final craSalt = base64.encode(List<int>.generate(16, (i) => i + 1));
    _cra[_key('demo.realm', 'cra.alice')] = CraCredential(
      secret: 'cra-secret',
      salt: craSalt,
      iterations: 2000,
      keyLen: CraAuthentication.defaultKeyLength,
      role: 'remote-member',
    );

    final scramSalt = base64.encode(List<int>.generate(16, (i) => i + 33));
    final secrets = ScramAuthentication.deriveServerSecrets(
      secret: 'scram-secret',
      salt: scramSalt,
      iterations: 4096,
    );
    _scram[_key('demo.realm', 'scram.alice')] = ScramCredential(
      storedKey: secrets.storedKey,
      serverKey: secrets.serverKey,
      salt: scramSalt,
      iterations: 4096,
      role: 'remote-member',
    );
  }

  final Map<String, TicketCredential> _ticket = {};
  final Map<String, CraCredential> _cra = {};
  final Map<String, ScramCredential> _scram = {};

  static String _key(String realm, String authId) => '$realm::$authId';

  @override
  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async => _ticket[_key(realmUri, authId)];

  @override
  Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async => _cra[_key(realmUri, authId)];

  @override
  Future<ScramCredential?> loadScram({
    required String realmUri,
    required String authId,
  }) async => _scram[_key(realmUri, authId)];
}
