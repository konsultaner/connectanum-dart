import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    AuthCredentialRegistry.reset();
    AuthenticatorRegistry.clear();
    registerDefaultAuthenticators();
    AuthSecurityTracker.reset();
    AuthAuditLogger.clearSink();
  });

  test(
    'AuthServerRouterBinding owns router and internal auth procedures',
    () async {
      final authSettings = _buildAuthServerSettings();
      final binding = await AuthServerRouterBinding.start(
        server: AuthServer(
          settings: authSettings,
          authTokens: const <String>['shared-token'],
        ),
        config: _webSocketConfig(),
        settings: _buildAuthServiceRouterSettings(),
      );

      RouterSession? callerSession;
      try {
        expect(binding.router.listeners.single.port, isPositive);

        callerSession = await binding.router.createInternalSession(
          realmUri: 'connectanum.authenticate',
          authId: 'auth-client',
          authRole: 'service',
        );
        final delegate = callerSession.createRemoteWampAuthenticatorDelegate(
          callTimeout: const Duration(seconds: 2),
        );

        const transactionId = 'auth-server-router-binding-1';
        final realm = authSettings.realms.singleWhere(
          (realm) => realm.name == 'demo.realm',
        );
        final context = AuthenticatorContext(
          realm: realm,
          sessionId: 1001,
          transport: const TransportMetadata(connectionId: 1001),
          helloDetails: const <String, Object?>{
            'authid': 'ticket-user',
            'authmethods': <String>['ticket'],
          },
        );

        final hello = await delegate.onHello(
          RemoteHelloRequest(
            realmSettings: realm,
            context: context,
            options: const <String, Object?>{'auth_token': 'shared-token'},
            transactionId: transactionId,
          ),
        );

        expect(hello.status, RemoteHelloStatus.challenge);
        expect(hello.challenge?.authId, equals('ticket-user'));

        final authenticate = await delegate.onAuthenticate(
          RemoteAuthenticateRequest(
            realmSettings: realm,
            context: context,
            authId: hello.challenge?.authId ?? 'ticket-user',
            authenticate: AuthenticateMessage(signature: 'ticket-secret'),
            options: const <String, Object?>{'auth_token': 'shared-token'},
            transactionId: transactionId,
          ),
        );

        expect(authenticate.status, RemoteAuthenticateStatus.success);
        expect(authenticate.success?.authRole, equals('member'));
      } finally {
        await callerSession?.close();
        await binding.close();
      }

      await binding.close();
    },
  );
}

RouterConfig _webSocketConfig() => RouterConfig(
  endpoints: <Endpoint>[
    Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
      webSocketPath: '/ws',
    ),
  ],
);

RouterSettings _buildAuthServiceRouterSettings() {
  final listener = ListenerSettingsBuilder('websocket', '127.0.0.1:0')
    ..setPath('/ws')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: <String>['wamp.2.json']),
    );

  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(
          RealmSettingsBuilder('connectanum.authenticate')
            ..setLimits(const RealmLimitSettings())
            ..addRoleFromBuilder(
              RoleSettingsBuilder('service')..addPermissionFromBuilder(
                PermissionSettingsBuilder('authenticate.')
                  ..setMatchPolicy(PermissionMatchPolicy.prefix)
                  ..allowOperations(const <String>['call']),
              ),
            )
            ..addRoleFromBuilder(
              RoleSettingsBuilder('internal')..addPermissionFromBuilder(
                PermissionSettingsBuilder('authenticate.')
                  ..setMatchPolicy(PermissionMatchPolicy.prefix)
                  ..allowOperations(const <String>['register', 'unregister']),
              ),
            ),
        )
        ..addListenerFromBuilder(listener)
        ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1)))
      .build();
}

RouterSettings _buildAuthServerSettings() {
  return (RouterSettingsBuilder()
        ..addAuthenticator(
          'ticket-basic',
          const AuthenticatorDefinition(
            type: 'ticket',
            options: <String, Object?>{
              'secrets': <String, Object?>{
                'ticket-user': <String, Object?>{
                  'ticket': 'ticket-secret',
                  'role': 'member',
                  'provider': 'auth-server-binding-test',
                },
              },
            },
          ),
        )
        ..addRealmFromBuilder(
          RealmSettingsBuilder('demo.realm')
            ..setLimits(const RealmLimitSettings())
            ..addAuthMethod(
              'ticket',
              options: const <String, Object?>{'authenticator': 'ticket-basic'},
            )
            ..addRoleFromBuilder(
              RoleSettingsBuilder('member')..addPermissionFromBuilder(
                PermissionSettingsBuilder('demo.')
                  ..setMatchPolicy(PermissionMatchPolicy.prefix)
                  ..allowOperations(const <String>[
                    'subscribe',
                    'call',
                    'register',
                  ]),
              ),
            ),
        ))
      .build();
}
