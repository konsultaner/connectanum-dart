@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

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

    test(
      'keeps remote hello failures behind the fake challenge path',
      () async {
        final harness = await _RemoteAuthHarness.start(nativeLib: nativeLib!);
        addTearDown(harness.dispose);

        final helloRegistration = await harness.authSession.register(
          'authenticate.hello',
        );
        helloRegistration.onLazyInvokePayload((invocation) {
          invocation.respondWith(
            argumentsKeywords: const <String, Object?>{
              'status': 'failure',
              'reason': wamp_core.Error.notAuthorized,
              'message': 'remote hello rejected',
            },
          );
        });
        var authenticateCalls = 0;
        final authenticateRegistration = await harness.authSession.register(
          'authenticate.authenticate',
        );
        authenticateRegistration.onLazyInvokePayload((invocation) {
          authenticateCalls += 1;
          invocation.respondWith(
            argumentsKeywords: const <String, Object?>{
              'status': 'failure',
              'reason': wamp_core.Error.notAuthorized,
              'message': 'unexpected authenticate',
            },
          );
        });

        await expectLater(
          harness.connectTicketUser(),
          throwsA(
            isA<client_pkg.Abort>().having(
              (abort) => abort.reason,
              'reason',
              wamp_core.Error.authenticationFailed,
            ),
          ),
        );
        expect(authenticateCalls, isZero);
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
