@TestOn('vm')
@Tags(['remote_auth_integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_client/socket.dart' as client_socket;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:connectanum_router/auth.dart';
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
      'RPC deadline cancels active provider creation and rejects late success',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);
        final factory = _LifecycleFactory();
        AuthenticatorRegistry.registerFactory(factory);
        addTearDown(
          () => AuthenticatorRegistry.unregisterFactory(factory.method),
        );
        final server = _lifecycleServer(
          challengeTimeout: const Duration(milliseconds: 500),
        );
        addTearDown(server.close);
        await harness.bindAuthServer(server);
        final caller = await harness.connectAuthService();
        addTearDown(caller.close);
        final creation = Completer<Authenticator>();
        factory.creation = creation.future;
        final pending = _authRpc(caller, 'hello', 'inflight', {
          'hello': _lifecycleHello,
        });
        await factory.entered.future.timeout(const Duration(seconds: 5));
        expect((await pending)['status'], 'failure');
        expect(server.pendingAuthenticationCounts, {'demo.realm': 1});
        creation.complete(factory.authenticator);
        await factory.authenticator.aborted.future.timeout(
          const Duration(seconds: 5),
        );
        factory.creation = null;
        expect(
          (await _authRpc(caller, 'hello', 'retry', {
            'hello': _lifecycleHello,
          }))['status'],
          'challenge',
        );
        expect(
          (await _authRpc(caller, 'authenticate', 'retry', {
            'authenticate': {'signature': 'proof'},
          }))['status'],
          'success',
        );
        expect(factory.authenticator.helloCalls, 1);
      },
      skip: skipReason,
    );

    test('RPC duplicate HELLO preserves the original challenge', () async {
      final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
      addTearDown(harness.dispose);
      final factory = _LifecycleFactory();
      AuthenticatorRegistry.registerFactory(factory);
      addTearDown(
        () => AuthenticatorRegistry.unregisterFactory(factory.method),
      );
      final server = _lifecycleServer();
      addTearDown(server.close);
      await harness.bindAuthServer(server);
      final caller = await harness.connectAuthService();
      addTearDown(caller.close);
      expect(
        (await _authRpc(caller, 'hello', 'duplicate', {
          'hello': _lifecycleHello,
        }))['status'],
        'challenge',
      );
      expect(
        (await _authRpc(caller, 'hello', 'duplicate', {
          'hello': _lifecycleHello,
        }))['status'],
        'failure',
      );
      expect(
        (await _authRpc(caller, 'authenticate', 'duplicate', {
          'authenticate': {'signature': 'proof'},
        }))['status'],
        'success',
      );
      expect(factory.authenticator.helloCalls, 1);
    }, skip: skipReason);

    test(
      'binding close cancels active AUTHENTICATE but not another binding',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);
        final factory = _LifecycleFactory();
        AuthenticatorRegistry.registerFactory(factory);
        addTearDown(
          () => AuthenticatorRegistry.unregisterFactory(factory.method),
        );
        final server = _lifecycleServer();
        addTearDown(server.close);
        await harness.bindAuthServer(server);
        final second = await AuthServerProcedureBinding.bind(
          server: server,
          session: harness.authSession,
          helloProcedure: 'authenticate.other.hello',
          authenticateProcedure: 'authenticate.other.authenticate',
          abortProcedure: 'authenticate.other.abort',
        );
        addTearDown(second.close);
        final caller = await harness.connectAuthService();
        addTearDown(caller.close);
        expect(
          (await _authRpc(caller, 'hello', 'first', {
            'hello': _lifecycleHello,
          }))['status'],
          'challenge',
        );
        expect(
          (await _authRpc(caller, 'other.hello', 'second', {
            'hello': _lifecycleHello,
          }))['status'],
          'challenge',
        );
        expect(
          (await _authRpc(caller, 'other.authenticate', 'first', {
            'authenticate': {'signature': 'proof'},
          }))['status'],
          'failure',
        );
        final response = Completer<AuthResult>();
        factory.authenticator.response = response.future;
        final first = _authRpc(caller, 'authenticate', 'first', {
          'authenticate': {'signature': 'proof'},
        });
        await factory.authenticator.authEntered.future.timeout(
          const Duration(seconds: 5),
        );
        await harness._procedures!.close();
        harness._procedures = null;
        expect((await first)['status'], 'failure');
        response.complete(
          AuthResult.success(
            const AuthSuccess(authId: 'user', authRole: 'member'),
          ),
        );
        await factory.authenticator.aborted.future.timeout(
          const Duration(seconds: 5),
        );
        factory.authenticator.response = null;
        expect(
          (await _authRpc(caller, 'other.authenticate', 'second', {
            'authenticate': {'signature': 'proof'},
          }))['status'],
          'success',
        );
        expect(server.pendingAuthenticationCounts, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'rejects untrusted RPCs without consuming pending challenges',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);
        await harness.bindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['shared-token'],
            fakeChallengeOnHelloFailure: true,
          ),
        );
        final caller = await harness.connectAuthService();
        addTearDown(caller.close);
        const hello = <String, Object?>{
          'realm': 'demo.realm',
          'sessionId': 42,
          'transport': {'connectionId': 42},
          'details': {
            'authid': 'ticket-user',
            'authmethods': ['ticket'],
          },
        };
        var sequence = 0;
        for (final method in ['hello', 'authenticate', 'abort']) {
          for (final token in [null, 'wrong', 42]) {
            final id = 'token-guard-${sequence++}';
            final challenge = await caller
                .call(
                  'authenticate.hello',
                  argumentsKeywords: {
                    'transactionId': id,
                    'hello': hello,
                    'auth_token': 'shared-token',
                  },
                )
                .first;
            expect(challenge.argumentsKeywords?['status'], 'challenge');
            final rejected = await caller
                .call(
                  'authenticate.$method',
                  argumentsKeywords: {
                    'transactionId': id,
                    'auth_token': ?token,
                    if (method == 'hello') 'hello': hello,
                    if (method == 'authenticate')
                      'authenticate': {'signature': 'ticket-secret'},
                  },
                )
                .first;
            expect(
              rejected.argumentsKeywords?['status'],
              'failure',
              reason: '$method $token',
            );
            expect(
              rejected.argumentsKeywords?['reason'],
              wamp_core.Error.notAuthorized,
            );
            final success = await caller
                .call(
                  'authenticate.authenticate',
                  argumentsKeywords: {
                    'transactionId': id,
                    'auth_token': 'shared-token',
                    'authenticate': {'signature': 'ticket-secret'},
                  },
                )
                .first;
            expect(
              success.argumentsKeywords?['status'],
              'success',
              reason: '$method $token',
            );
          }
        }
      },
      skip: skipReason,
    );

    test('malformed admitted RPCs do not consume pending challenges', () async {
      final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
      addTearDown(harness.dispose);
      await harness.bindAuthServer(
        AuthServer(
          settings: _buildAuthServerSettings(),
          authTokens: const ['shared-token'],
        ),
      );
      final caller = await harness.connectAuthService();
      addTearDown(caller.close);
      final malformed = <(String, Map<String, Object?>)>[
        ('authenticate', {}),
        ('authenticate', {'authenticate': {}}),
        (
          'authenticate',
          {
            'authenticate': {'signature': 42},
          },
        ),
        (
          'authenticate',
          {
            'authenticate': {'signature': 'ticket-secret', 'extra': []},
          },
        ),
        ('abort', {'reason': 42}),
      ];
      for (var index = 0; index < malformed.length; index++) {
        final id = 'schema-guard-$index';
        final challenge = await caller
            .call(
              'authenticate.hello',
              argumentsKeywords: {
                'transactionId': id,
                'auth_token': 'shared-token',
                'hello': {
                  'realm': 'demo.realm',
                  'sessionId': 42,
                  'transport': {'connectionId': 42},
                  'details': {
                    'authid': 'ticket-user',
                    'authmethods': ['ticket'],
                  },
                },
              },
            )
            .first;
        expect(challenge.argumentsKeywords?['status'], 'challenge');
        final (method, payload) = malformed[index];
        await expectLater(
          caller
              .call(
                'authenticate.$method',
                argumentsKeywords: {
                  'transactionId': id,
                  'auth_token': 'shared-token',
                  ...payload,
                },
              )
              .first,
          throwsA(
            isA<wamp_core.Error>().having(
              (error) => error.error,
              'error',
              wamp_core.Error.invalidArgument,
            ),
          ),
        );
        final success = await caller
            .call(
              'authenticate.authenticate',
              argumentsKeywords: {
                'transactionId': id,
                'auth_token': 'shared-token',
                'authenticate': {'signature': 'ticket-secret'},
              },
            )
            .first;
        expect(
          success.argumentsKeywords?['status'],
          'success',
          reason: '$method $payload',
        );
      }
    }, skip: skipReason);

    test(
      'authenticates ticket clients through the remote auth RPC service over mTLS',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);

        await harness.bindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['shared-token'],
          ),
        );

        final session = await harness.connectTicketUser();
        addTearDown(session.close);

        expect(session.authId, equals('ticket-user'));
        expect(session.authRole, equals('member'));
        expect(session.authProvider, equals('remote-auth-server'));
      },
      skip: skipReason,
    );

    test(
      'applies realm permissions after remote authentication succeeds',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);

        await harness.bindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['shared-token'],
          ),
        );

        final session = await harness.connectTicketUser();
        addTearDown(session.close);

        await expectLater(
          session.publish(
            'demo.restricted.topic',
            arguments: const <Object?>['payload'],
            options: client_pkg.PublishOptions(acknowledge: true),
          ),
          throwsA(
            isA<wamp_core.Error>().having(
              (error) => error.error,
              'error',
              wamp_core.Error.notAuthorized,
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'picks up auth_token_file rotation on subsequent remote auth RPCs',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);

        await harness.bindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['shared-token'],
          ),
        );

        final firstSession = await harness.connectTicketUser();
        await firstSession.close();

        await harness.rebindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['rotated-token'],
          ),
        );
        await harness.authTokenFile.writeAsString('rotated-token');

        final secondSession = await harness.connectTicketUser();
        addTearDown(secondSession.close);

        expect(secondSession.authRole, equals('member'));
        expect(secondSession.authProvider, equals('remote-auth-server'));
      },
      skip: skipReason,
    );

    test(
      'reconnects to the remote auth service when service credentials rotate',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);

        await harness.bindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['shared-token'],
          ),
        );

        final firstSession = await harness.connectTicketUser();
        await firstSession.close();

        await harness.serviceSecretFile.writeAsString('service-ticket-v2');
        await harness.restartAuthRouter(serviceTicket: 'service-ticket-v2');
        await harness.bindAuthServer(
          AuthServer(
            settings: _buildAuthServerSettings(),
            authTokens: const ['shared-token'],
          ),
        );

        final secondSession = await harness.connectTicketUser();
        addTearDown(secondSession.close);

        expect(secondSession.authRole, equals('member'));
      },
      skip: skipReason,
    );

    test(
      'fails closed when the remote auth service returns malformed hello payload',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);

        final helloRegistration = await harness.authSession.register(
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

        await expectLater(
          harness.connectTicketUser(),
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
      final harness = await _RemoteAuthHarness.start(
        nativeLib: nativeLib!,
        callTimeoutMs: 75,
      );
      addTearDown(harness.dispose);

      final helloRegistration = await harness.authSession.register(
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

      await expectLater(
        harness.connectTicketUser(),
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

class _RemoteAuthHarness {
  _RemoteAuthHarness._({
    required this.runtime,
    required this.authRouter,
    required this.edgeRouter,
    required this.authSession,
    required this.authTokenFile,
    required this.serviceSecretFile,
    required this.workingDirectory,
    required this.authPort,
  });

  final NativeTransportRuntime runtime;
  dynamic authRouter;
  final dynamic edgeRouter;
  dynamic authSession;
  final File authTokenFile;
  final File serviceSecretFile;
  final Directory workingDirectory;
  final int authPort;
  final List<client_pkg.Client> _clients = <client_pkg.Client>[];
  AuthServerProcedureBinding? _procedures;
  AuthServer? _boundAuthServer;

  static Future<_RemoteAuthHarness> start({
    required String nativeLib,
    int callTimeoutMs = 1000,
  }) async {
    final workingDirectory = await Directory.systemTemp.createTemp(
      'connectanum_remote_auth_',
    );
    final authTokenFile = File('${workingDirectory.path}/auth_token.txt')
      ..writeAsStringSync('shared-token');
    final serviceSecretFile = File(
      '${workingDirectory.path}/service_ticket.txt',
    )..writeAsStringSync('service-ticket-v1');

    final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
    final authPort = await _allocatePort();
    final authRouter = Router(
      _webSocketConfig(
        enableTls: true,
        requireClientAuth: true,
        port: authPort,
      ),
      settings: _buildAuthRouterSettings(
        serviceTicket: 'service-ticket-v1',
        endpoint: '127.0.0.1:$authPort',
      ),
    ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
    final authSession = await authRouter.createInternalSession(
      realmUri: 'connectanum.authenticate',
      authId: 'auth-service',
      authRole: 'internal',
    );

    final edgeRouter = Router(
      _webSocketConfig(),
      settings: _buildEdgeRouterSettings(
        authHost: '127.0.0.1',
        authPort: authPort,
        authTokenFile: authTokenFile.path,
        serviceSecretFile: serviceSecretFile.path,
        callTimeoutMs: callTimeoutMs,
      ),
    ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));

    return _RemoteAuthHarness._(
      runtime: runtime,
      authRouter: authRouter,
      edgeRouter: edgeRouter,
      authSession: authSession,
      authTokenFile: authTokenFile,
      serviceSecretFile: serviceSecretFile,
      workingDirectory: workingDirectory,
      authPort: authPort,
    );
  }

  Future<void> bindAuthServer(AuthServer server) async {
    _boundAuthServer = server;
    await _procedures?.close();
    _procedures = await AuthServerProcedureBinding.bind(
      server: server,
      session: authSession,
    );
  }

  Future<void> rebindAuthServer(AuthServer server) => bindAuthServer(server);

  Future<void> restartAuthRouter({required String serviceTicket}) async {
    await _procedures?.close();
    _procedures = null;
    await authSession.close();
    await authRouter.dispose();
    authRouter = Router(
      _webSocketConfig(
        enableTls: true,
        requireClientAuth: true,
        port: authPort,
      ),
      settings: _buildAuthRouterSettings(
        serviceTicket: serviceTicket,
        endpoint: '127.0.0.1:$authPort',
      ),
    ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
    authSession = await authRouter.createInternalSession(
      realmUri: 'connectanum.authenticate',
      authId: 'auth-service',
      authRole: 'internal',
    );
    final server = _boundAuthServer;
    if (server != null) {
      await bindAuthServer(server);
    }
  }

  Future<client_pkg.Session> connectTicketUser() async {
    final listener = edgeRouter.listeners.single;
    final client = client_pkg.Client(
      realm: 'demo.realm',
      authId: 'ticket-user',
      authenticationMethods: <client_pkg.AbstractAuthentication>[
        client_pkg.TicketAuthentication('ticket-secret'),
      ],
      transport: client_pkg.WebSocketTransport.withJsonSerializer(
        'ws://127.0.0.1:${listener.port}/ws',
      ),
    );
    _clients.add(client);
    return client.connect().first.timeout(const Duration(seconds: 10));
  }

  Future<client_pkg.Session> connectAuthService() async {
    final tls = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(_fixturePath('remote_auth_ca_cert.pem'))
      ..useCertificateChain(_fixturePath('remote_auth_client_cert.pem'))
      ..usePrivateKey(_fixturePath('remote_auth_client_key.pem'));
    final client = client_pkg.Client(
      realm: 'connectanum.authenticate',
      authId: 'auth-service',
      authenticationMethods: [
        client_pkg.TicketAuthentication('service-ticket-v1'),
      ],
      transport: client_socket.SocketTransport(
        '127.0.0.1',
        authPort,
        json_serializer.Serializer(),
        1,
        ssl: true,
        tlsSecurityContext: tls,
      ),
    );
    _clients.add(client);
    return client.connect().first;
  }

  Future<void> dispose() async {
    for (final client in _clients) {
      await client.disconnect();
    }
    await _procedures?.close();
    await authSession.close();
    await edgeRouter.dispose();
    await authRouter.dispose();
    runtime.shutdown();
    runtime.dispose();
    if (workingDirectory.existsSync()) {
      await workingDirectory.delete(recursive: true);
    }
  }
}

RouterConfig _webSocketConfig({
  bool enableTls = false,
  bool requireClientAuth = false,
  int port = 0,
}) => RouterConfig(
  endpoints: <Endpoint>[
    Endpoint(
      host: '127.0.0.1',
      port: port,
      tlsMode: enableTls ? TlsMode.native : TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
      webSocketPath: '/ws',
      sniCertificates: enableTls
          ? <SniCertificate>[
              SniCertificate(
                hostname: 'localhost',
                certificateChainPem: _readCertFixture(
                  'remote_auth_server_cert.pem',
                ),
                privateKeyPem: _readCertFixture('remote_auth_server_key.pem'),
              ),
            ]
          : const <SniCertificate>[],
      clientAuth: requireClientAuth
          ? TlsClientAuth(
              mode: TlsClientAuthMode.required,
              caCertificatesPem: _readCertFixture('remote_auth_ca_cert.pem'),
            )
          : null,
    ),
  ],
);

const _lifecycleHello = <String, Object?>{
  'realm': 'demo.realm',
  'sessionId': 42,
  'transport': {'connectionId': 42},
  'details': {
    'authid': 'user',
    'authmethods': ['lifecycle'],
  },
};

Future<Map<String, Object?>> _authRpc(
  client_pkg.Session caller,
  String method,
  String id,
  Map<String, Object?> payload,
) async {
  final result = await caller
      .call(
        'authenticate.$method',
        argumentsKeywords: {
          'transactionId': id,
          'auth_token': 'shared-token',
          ...payload,
        },
      )
      .first
      .timeout(const Duration(seconds: 5));
  return Map<String, Object?>.from(result.argumentsKeywords ?? {});
}

AuthServer _lifecycleServer({Duration? challengeTimeout}) => AuthServer(
  challengeTimeout: challengeTimeout,
  settings:
      (RouterSettingsBuilder()..addRealmFromBuilder(
            RealmSettingsBuilder('demo.realm')
              ..addAuthMethod('lifecycle')
              ..setLimits(const RealmLimitSettings(maxPendingAuth: 2)),
          ))
          .build(),
  authTokens: const ['shared-token'],
);

class _LifecycleFactory extends AuthenticatorFactory {
  final authenticator = _LifecycleAuthenticator();
  final entered = Completer<void>();
  Future<Authenticator>? creation;

  @override
  String get method => 'lifecycle';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    if (!entered.isCompleted) entered.complete();
    return creation ?? authenticator;
  }
}

class _LifecycleAuthenticator extends Authenticator {
  final aborted = Completer<void>();
  final authEntered = Completer<void>();
  Future<AuthResult>? response;
  int helloCalls = 0;

  @override
  String get method => 'lifecycle';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    helloCalls++;
    return AuthResult.challenge(const AuthChallenge(extra: {}));
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    if (!authEntered.isCompleted) authEntered.complete();
    return response ??
        AuthResult.success(
          const AuthSuccess(authId: 'user', authRole: 'member'),
        );
  }

  @override
  Future<void> onAbort(AuthenticatorContext context, {String? reason}) async {
    if (!aborted.isCompleted) aborted.complete();
  }
}

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

RouterSettings _buildAuthRouterSettings({
  required String serviceTicket,
  required String endpoint,
}) {
  final listener = ListenerSettingsBuilder('rawsocket', endpoint)
    ..addAuthMethod('ticket')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..setRawSocketOptions(
      const RawSocketListenerSettings(maxFrameExponent: 16),
    );

  final builder = RouterSettingsBuilder()
    ..addAuthenticator(
      'ticket-service',
      AuthenticatorDefinition(
        type: 'ticket',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            'auth-service': <String, Object?>{
              'ticket': serviceTicket,
              'role': 'service',
              'provider': 'remote-auth-router',
            },
          },
        },
      ),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder('connectanum.authenticate')
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'ticket-service'},
        )
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
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}

RouterSettings _buildEdgeRouterSettings({
  required String authHost,
  required int authPort,
  required String authTokenFile,
  required String serviceSecretFile,
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
          'auth_token_file': authTokenFile,
          'rpc': <String, Object?>{
            'realm': 'connectanum.authenticate',
            'call_timeout_ms': callTimeoutMs,
            'connect_timeout_ms': 1000,
            'service_auth_method': 'ticket',
            'service_auth_id': 'auth-service',
            'service_auth_secret_file': serviceSecretFile,
            'transport': <String, Object?>{
              'type': 'rawsocket',
              'host': authHost,
              'port': authPort,
              'ssl': true,
              'serializer': 'json',
              'tls': <String, Object?>{
                'ca_certificates_file': _fixturePath('remote_auth_ca_cert.pem'),
                'client_certificate_file': _fixturePath(
                  'remote_auth_client_cert.pem',
                ),
                'client_private_key_file': _fixturePath(
                  'remote_auth_client_key.pem',
                ),
              },
            },
          },
        },
      ),
    )
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}

String _readCertFixture(String fileName) =>
    File(_fixturePath(fileName)).readAsStringSync();

String _fixturePath(String fileName) {
  final candidates = <String>[
    'packages/connectanum_router/test/certs/$fileName',
    'test/certs/$fileName',
    fileName,
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  throw StateError('Missing router test certificate $fileName');
}

Future<int> _allocatePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
