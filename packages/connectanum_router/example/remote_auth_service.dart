// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';

const String _edgeRealm = 'demo.realm';
const String _authRealm = 'connectanum.authenticate';
const String _authToken = 'demo-shared-token';
const String _serviceTicket = 'service-ticket';
const String _ticketAuthId = 'ticket-user';
const String _ticketSecret = 'ticket-secret';

Future<void> main(List<String> args) async {
  final smokeAndExit = args.contains('--smoke-and-exit');
  final rawSocketDelegate = args.contains('--rawsocket-delegate');
  String? nativeLibraryPath;
  for (final arg in args) {
    if (!arg.startsWith('--')) {
      nativeLibraryPath = arg;
      break;
    }
  }

  registerDefaultAuthenticators();

  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(libraryPath: nativeLibraryPath);
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Failed to load the native transport runtime: ${error.message}\n'
      'Install Rust so Dart build hooks can compile ct_ffi, set '
      'CONNECTANUM_NATIVE_LIB, or pass the native library path as the first '
      'argument.',
    );
    exitCode = 64;
    return;
  }

  runtime.start();

  final int? authPort = rawSocketDelegate ? await _allocatePort() : null;
  final authRouter = rawSocketDelegate
      ? Router(
          _rawSocketRouterConfig(port: authPort!),
          settings: _buildAuthRouterSettings(port: authPort),
        )
      : null;
  final edgeRouter = Router(
    _webSocketRouterConfig(),
    settings: rawSocketDelegate
        ? _buildEdgeRouterSettings(authPort: authPort!)
        : _buildEmbeddedEdgeRouterSettings(),
  );

  final authServer = AuthServer(
    settings: _buildAuthServerSettings(),
    authTokens: const <String>[_authToken],
    fakeChallengeOnHelloFailure: true,
  );

  RouterBinding? authBinding;
  RouterBinding? edgeBinding;
  RouterSession? authSession;
  RouterSession? serviceSession;
  AuthServerProcedureBinding? authProcedures;
  client_pkg.Client? client;
  client_pkg.Session? userSession;
  try {
    if (rawSocketDelegate) {
      authBinding = authRouter!.start(
        runtime,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      authSession = await authBinding.createInternalSession(
        realmUri: _authRealm,
        authId: 'auth-service',
        authRole: 'internal',
      );
      authProcedures = await AuthServerProcedureBinding.bind(
        server: authServer,
        session: authSession,
      );
      edgeBinding = edgeRouter.start(
        runtime,
        workerPollInterval: const Duration(milliseconds: 1),
      );
    } else {
      edgeBinding = edgeRouter.start(
        runtime,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      authSession = await edgeBinding.createInternalSession(
        realmUri: _authRealm,
        authId: 'auth-service',
        authRole: 'internal',
      );
      authProcedures = await AuthServerProcedureBinding.bind(
        server: authServer,
        session: authSession,
      );
    }
    serviceSession = await edgeBinding.createInternalSession(
      realmUri: _edgeRealm,
      authId: 'edge-service',
      authRole: 'service',
    );
    final registration = await serviceSession.register('demo.echo');
    registration.onInvoke(
      (invocation) => invocation.respondWith(
        arguments: invocation.arguments ?? const <Object?>[],
        argumentsKeywords:
            invocation.argumentsKeywords ?? const <String, Object?>{},
      ),
    );

    final endpoint = _edgeEndpoint(edgeBinding);
    client = _ticketClient(endpoint, _ticketAuthId, _ticketSecret);
    userSession = await client
        .connect(options: client_pkg.ClientConnectOptions(reconnectCount: 0))
        .first
        .timeout(const Duration(seconds: 10));

    final echo = await userSession
        .callSingle('demo.echo', arguments: const <Object?>['remote-auth-ok'])
        .timeout(const Duration(seconds: 10));
    final echoed = echo.arguments?.singleOrNull;
    if (echoed != 'remote-auth-ok') {
      throw StateError('Unexpected demo.echo response: ${echo.arguments}');
    }

    await _assertFakeChallengeRejectsUnknownUser(endpoint);

    if (rawSocketDelegate) {
      print('Remote auth service running at rawsocket://127.0.0.1:$authPort');
    } else {
      print('Remote auth service bound in-process through the edge router.');
    }
    print('Edge router WebSocket endpoint is $endpoint');
    print(
      'Authenticated $_ticketAuthId through the '
      '${rawSocketDelegate ? 'raw-socket' : 'in-process'} '
      'remote WAMP auth service.',
    );
    print('Rejected an unknown user through the fake-challenge path.');

    if (!smokeAndExit) {
      print('Press Ctrl+C to stop.');
      await Future.any([
        ProcessSignal.sigint.watch().first,
        ProcessSignal.sigterm.watch().first,
      ]);
    }
  } finally {
    await userSession?.close();
    await client?.disconnect();
    await serviceSession?.close();
    await authProcedures?.close();
    await authSession?.close();
    await edgeBinding?.dispose();
    await authBinding?.dispose();
    runtime.shutdown();
    runtime.dispose();
    RemoteAuthenticatorRegistry.clear();
    RemoteAuthenticator.resetRateLimiter();
    AuthAuditLogger.clearSink();
  }
}

RouterConfig _rawSocketRouterConfig({required int port}) => RouterConfig(
  endpoints: <Endpoint>[
    Endpoint(
      host: '127.0.0.1',
      port: port,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
    ),
  ],
);

RouterConfig _webSocketRouterConfig() => RouterConfig(
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

RouterSettings _buildAuthRouterSettings({required int port}) {
  final listener = ListenerSettingsBuilder('auth-rawsocket', '127.0.0.1:$port')
    ..addAuthMethod('ticket')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..setRawSocketOptions(
      const RawSocketListenerSettings(maxFrameExponent: 16),
    );

  final builder = RouterSettingsBuilder()
    ..addAuthenticator(
      'auth-service-ticket',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            'auth-service': <String, Object?>{
              'ticket': _serviceTicket,
              'role': 'service',
              'provider': 'remote-auth-service',
            },
          },
        },
      ),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder(_authRealm)
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'auth-service-ticket'},
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

RouterSettings _buildAuthServerSettings() {
  final builder = RouterSettingsBuilder()
    ..addAuthenticator(
      'ticket-basic',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            _ticketAuthId: <String, Object?>{
              'ticket': _ticketSecret,
              'role': 'member',
              'provider': 'remote-auth-service',
            },
          },
        },
      ),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder(_edgeRealm)
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'ticket-basic'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const <String>['call']),
          ),
        ),
    );
  return builder.build();
}

RouterSettings _buildEmbeddedEdgeRouterSettings() {
  final listener = ListenerSettingsBuilder('edge-websocket', '127.0.0.1:0')
    ..setPath('/ws')
    ..addAuthMethod('ticket')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: <String>['wamp.2.json']),
    );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder(_authRealm)
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
    ..addRealmFromBuilder(
      RealmSettingsBuilder(_edgeRealm)
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'remote-ticket'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const <String>['call']),
          ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('service')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const <String>['register', 'unregister']),
          ),
        ),
    )
    ..addListenerFromBuilder(listener)
    ..addAuthenticator(
      'remote-ticket',
      const AuthenticatorDefinition(
        type: 'remote',
        options: <String, Object?>{
          'method': 'remote',
          'allowed_roles': <String>['member'],
          'auth_token': _authToken,
          'challenge_timeout_ms': 1000,
          'rpc': <String, Object?>{
            'realm': _authRealm,
            'call_timeout_ms': 2000,
            'connect_timeout_ms': 2000,
            'service_auth_id': 'auth-client',
            'service_auth_role': 'service',
            'transport': <String, Object?>{'type': 'internal'},
          },
        },
      ),
    )
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}

RouterSettings _buildEdgeRouterSettings({required int authPort}) {
  final listener = ListenerSettingsBuilder('edge-websocket', '127.0.0.1:0')
    ..setPath('/ws')
    ..addAuthMethod('ticket')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: <String>['wamp.2.json']),
    );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder(_edgeRealm)
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'remote-ticket'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const <String>['call']),
          ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('service')..addPermissionFromBuilder(
            PermissionSettingsBuilder('demo.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const <String>['register', 'unregister']),
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
          'auth_token': _authToken,
          'challenge_timeout_ms': 1000,
          'rpc': <String, Object?>{
            'realm': _authRealm,
            'call_timeout_ms': 2000,
            'connect_timeout_ms': 2000,
            'service_auth_method': 'ticket',
            'service_auth_id': 'auth-service',
            'service_auth_secret': _serviceTicket,
            'transport': <String, Object?>{
              'type': 'rawsocket',
              'host': '127.0.0.1',
              'port': authPort,
              'ssl': false,
              'serializer': 'json',
              'tls': const <String, Object?>{'allow_insecure_transport': true},
            },
          },
        },
      ),
    )
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}

Uri _edgeEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'ws',
    host: '127.0.0.1',
    port: listener.port,
    path: listener.endpoint.webSocketPath ?? '/ws',
  );
}

client_pkg.Client _ticketClient(Uri endpoint, String authId, String ticket) {
  return client_pkg.Client(
    realm: _edgeRealm,
    authId: authId,
    authenticationMethods: <client_pkg.AbstractAuthentication>[
      client_pkg.TicketAuthentication(ticket),
    ],
    transport: client_pkg.WebSocketTransport.withJsonSerializer(
      endpoint.toString(),
    ),
  );
}

Future<void> _assertFakeChallengeRejectsUnknownUser(Uri endpoint) async {
  final client = _ticketClient(endpoint, 'unknown-user', 'wrong-ticket');
  try {
    await client
        .connect(options: client_pkg.ClientConnectOptions(reconnectCount: 0))
        .first
        .timeout(const Duration(seconds: 10));
    throw StateError('Unknown remote-auth user unexpectedly authenticated.');
  } on client_pkg.Abort {
    // Expected: fake challenge prevents user enumeration, then authenticate
    // fails closed after the bogus ticket is submitted.
  } finally {
    await client.disconnect();
  }
}

Future<int> _allocatePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
