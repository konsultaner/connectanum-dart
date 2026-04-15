@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('Remote auth integration', () {
    test(
      'authenticates ticket clients through the remote auth RPC service',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final authRouter = Router(
          _webSocketConfig(),
          settings: _buildAuthRouterSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(authRouter.dispose);

        final authServer = AuthServer(
          settings: _buildAuthServerSettings(),
          authTokens: const ['shared-token'],
        );
        final authSession = await authRouter.createInternalSession(
          realmUri: 'connectanum.authenticate',
          authId: 'auth-service',
          authRole: 'internal',
        );
        addTearDown(authSession.close);

        final procedures = await AuthServerProcedureBinding.bind(
          server: authServer,
          session: authSession,
        );
        addTearDown(procedures.close);

        final authListener = authRouter.listeners.single;
        final authUrl = 'ws://127.0.0.1:${authListener.port}/ws';

        final edgeRouter = Router(
          _webSocketConfig(),
          settings: _buildEdgeRouterSettings(
            authUrl: authUrl,
            nativeLib: nativeLib!,
          ),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(edgeRouter.dispose);

        final edgeListener = edgeRouter.listeners.single;
        final client = client_pkg.Client(
          realm: 'demo.realm',
          authId: 'ticket-user',
          authenticationMethods: <client_pkg.AbstractAuthentication>[
            client_pkg.TicketAuthentication('ticket-secret'),
          ],
          transport: client_pkg.WebSocketTransport.withJsonSerializer(
            'ws://127.0.0.1:${edgeListener.port}/ws',
          ),
        );
        addTearDown(client.disconnect);

        final session = await client.connect().first.timeout(
          const Duration(seconds: 10),
        );
        addTearDown(session.close);

        expect(session.authId, equals('ticket-user'));
        expect(session.authRole, equals('member'));
        expect(session.authProvider, equals('remote-auth-server'));
      },
      skip: skipReason,
    );

    test(
      'fails closed when the remote auth service returns malformed hello payload',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final authRouter = Router(
          _webSocketConfig(),
          settings: _buildAuthRouterSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(authRouter.dispose);

        final authSession = await authRouter.createInternalSession(
          realmUri: 'connectanum.authenticate',
          authId: 'auth-service',
          authRole: 'internal',
        );
        addTearDown(authSession.close);

        final helloRegistration = await authSession.register(
          'authenticate.hello',
        );
        helloRegistration.onLazyInvokePayload((invocation) {
          invocation.respondWith(
            argumentsKeywords: const <String, Object?>{
              'status': 'success',
              'authId': 'ticket-user',
            },
          );
        });

        final authListener = authRouter.listeners.single;
        final edgeRouter = Router(
          _webSocketConfig(),
          settings: _buildEdgeRouterSettings(
            authUrl: 'ws://127.0.0.1:${authListener.port}/ws',
            nativeLib: nativeLib!,
          ),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(edgeRouter.dispose);

        final edgeListener = edgeRouter.listeners.single;
        final client = client_pkg.Client(
          realm: 'demo.realm',
          authId: 'ticket-user',
          authenticationMethods: <client_pkg.AbstractAuthentication>[
            client_pkg.TicketAuthentication('ticket-secret'),
          ],
          transport: client_pkg.WebSocketTransport.withJsonSerializer(
            'ws://127.0.0.1:${edgeListener.port}/ws',
          ),
        );
        addTearDown(client.disconnect);

        await expectLater(
          client.connect().first.timeout(const Duration(seconds: 10)),
          throwsA(
            isA<client_pkg.Abort>().having(
              (abort) => abort.reason,
              'reason',
              wamp_core.Error.notAuthorized,
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test('fails closed when the remote auth service times out', () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });

      final authRouter = Router(
        _webSocketConfig(),
        settings: _buildAuthRouterSettings(),
      ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
      addTearDown(authRouter.dispose);

      final authSession = await authRouter.createInternalSession(
        realmUri: 'connectanum.authenticate',
        authId: 'auth-service',
        authRole: 'internal',
      );
      addTearDown(authSession.close);

      final helloRegistration = await authSession.register(
        'authenticate.hello',
      );
      helloRegistration.onLazyInvokePayload((invocation) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        invocation.respondWith(
          argumentsKeywords: const <String, Object?>{
            'status': 'failure',
            'reason': wamp_core.Error.notAuthorized,
            'message': 'late response',
          },
        );
      });

      final authListener = authRouter.listeners.single;
      final edgeRouter = Router(
        _webSocketConfig(),
        settings: _buildEdgeRouterSettings(
          authUrl: 'ws://127.0.0.1:${authListener.port}/ws',
          nativeLib: nativeLib!,
          callTimeoutMs: 75,
        ),
      ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
      addTearDown(edgeRouter.dispose);

      final edgeListener = edgeRouter.listeners.single;
      final client = client_pkg.Client(
        realm: 'demo.realm',
        authId: 'ticket-user',
        authenticationMethods: <client_pkg.AbstractAuthentication>[
          client_pkg.TicketAuthentication('ticket-secret'),
        ],
        transport: client_pkg.WebSocketTransport.withJsonSerializer(
          'ws://127.0.0.1:${edgeListener.port}/ws',
        ),
      );
      addTearDown(client.disconnect);

      await expectLater(
        client.connect().first.timeout(const Duration(seconds: 10)),
        throwsA(
          isA<client_pkg.Abort>().having(
            (abort) => abort.reason,
            'reason',
            wamp_core.Error.notAuthorized,
          ),
        ),
      );
    }, skip: skipReason);
  });
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

RouterSettings _buildAuthServerSettings() {
  final builder = RouterSettingsBuilder()
    ..addAuthenticator(
      'ticket-basic',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            'ticket-user': <String, Object?>{
              'ticket': 'ticket-secret',
              'role': 'member',
              'provider': 'remote-auth-server',
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
          options: const {'authenticator': 'ticket-basic'},
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
    );
  return builder.build();
}

RouterSettings _buildAuthRouterSettings() {
  final listener = ListenerSettingsBuilder('websocket', '127.0.0.1:0')
    ..setPath('/ws')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: <String>['wamp.2.json']),
    );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('connectanum.authenticate')
        ..setLimits(const RealmLimitSettings())
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
            PermissionSettingsBuilder('authenticate.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const <String>['call']),
          ),
        ),
    )
    ..addListenerFromBuilder(listener)
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}

RouterSettings _buildEdgeRouterSettings({
  required String authUrl,
  required String nativeLib,
  int callTimeoutMs = 1000,
}) {
  final listener = ListenerSettingsBuilder('websocket', '127.0.0.1:0')
    ..setPath('/ws')
    ..addAuthMethod('ticket')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: <String>['wamp.2.json']),
    );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('demo.realm')
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'remote-ticket'},
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
    )
    ..addListenerFromBuilder(listener)
    ..addAuthenticator(
      'remote-ticket',
      AuthenticatorDefinition(
        type: 'remote',
        options: <String, Object?>{
          'method': 'remote',
          'allowed_roles': const <String>['member'],
          'challenge_timeout_ms': 1000,
          'auth_token': 'shared-token',
          'rpc': <String, Object?>{
            'realm': 'connectanum.authenticate',
            'call_timeout_ms': callTimeoutMs,
            'connect_timeout_ms': 1000,
            'transport': <String, Object?>{
              'type': 'websocket',
              'url': authUrl,
              'serializer': 'json',
              'library_path': nativeLib,
            },
          },
        },
      ),
    )
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}
