import 'dart:io';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';

class RemoteAuthBenchHarness {
  RemoteAuthBenchHarness._({
    required Logger logger,
    required RouterBinding authRouter,
    required RouterSession authSession,
    required AuthServerProcedureBinding procedures,
  }) : _logger = logger,
       _authRouter = authRouter,
       _authSession = authSession,
       _procedures = procedures;

  static const String defaultAuthId = 'ticket-user';
  static const String defaultAuthSecret = 'ticket-secret';
  static const String defaultAuthRole = 'member';
  static const String defaultAuthToken = 'shared-token';
  static const String defaultServiceTicket = 'service-ticket-v1';

  final Logger _logger;
  final RouterBinding _authRouter;
  final RouterSession _authSession;
  final AuthServerProcedureBinding _procedures;

  static Future<RemoteAuthBenchHarness?> maybeStart({
    required RouterSettings settings,
    required NativeTransportRuntime runtime,
    Logger? logger,
  }) async {
    final config = _RemoteAuthBenchConfig.tryParse(settings);
    if (config == null) {
      return null;
    }
    final targetLogger = logger ?? Logger('RemoteAuthBenchHarness');
    targetLogger.info(
      'Starting remote auth bench harness on ${config.authHost}:${config.authPort}',
    );
    config.prepareCredentialFiles();

    final authRouter = Router(
      _buildAuthRouterConfig(config),
      settings: _buildAuthRouterSettings(config),
    ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
    final authSession = await authRouter.createInternalSession(
      realmUri: config.rpcRealm,
      authId: config.serviceAuthId,
      authRole: 'internal',
    );
    final authServer = AuthServer(
      settings: _buildAuthServerSettings(config),
      authTokens: <String>[config.authToken],
      fakeChallengeOnHelloFailure: true,
    );
    final procedures = await AuthServerProcedureBinding.bind(
      server: authServer,
      session: authSession,
    );
    return RemoteAuthBenchHarness._(
      logger: targetLogger,
      authRouter: authRouter,
      authSession: authSession,
      procedures: procedures,
    );
  }

  static bool supports(RouterSettings settings) =>
      _RemoteAuthBenchConfig.tryParse(settings) != null;

  Future<void> close() async {
    _logger.info('Stopping remote auth bench harness');
    await _procedures.close();
    await _authSession.close();
    await _authRouter.dispose();
  }
}

class _RemoteAuthBenchConfig {
  const _RemoteAuthBenchConfig({
    required this.authHost,
    required this.authPort,
    required this.rpcRealm,
    required this.serviceAuthId,
    required this.serviceSecretFile,
    required this.authTokenFile,
    required this.realms,
  });

  final String authHost;
  final int authPort;
  final String rpcRealm;
  final String serviceAuthId;
  final String serviceSecretFile;
  final String authTokenFile;
  final List<String> realms;

  String get authToken => RemoteAuthBenchHarness.defaultAuthToken;

  String get serviceTicket => RemoteAuthBenchHarness.defaultServiceTicket;

  void prepareCredentialFiles() {
    _writeFile(authTokenFile, authToken);
    _writeFile(serviceSecretFile, serviceTicket);
  }

  static _RemoteAuthBenchConfig? tryParse(RouterSettings settings) {
    for (final entry in settings.authenticators.entries) {
      final definition = entry.value;
      if (definition.type != 'remote') {
        continue;
      }
      final rpc = definition.options['rpc'];
      if (rpc is! Map) {
        continue;
      }
      final rpcMap = Map<String, Object?>.from(rpc.cast<Object?, Object?>());
      final transport = rpcMap['transport'];
      if (transport is! Map) {
        continue;
      }
      final transportMap = Map<String, Object?>.from(
        transport.cast<Object?, Object?>(),
      );
      if ((transportMap['type'] as String?) != 'rawsocket') {
        continue;
      }
      final host = transportMap['host'];
      final port = transportMap['port'];
      final rpcRealm = rpcMap['realm'];
      final serviceAuthId = rpcMap['service_auth_id'];
      final serviceSecretFile = rpcMap['service_auth_secret_file'];
      final authTokenFile = definition.options['auth_token_file'];
      if (host is! String ||
          port is! int ||
          rpcRealm is! String ||
          serviceAuthId is! String ||
          serviceSecretFile is! String ||
          authTokenFile is! String) {
        continue;
      }
      final realms = <String>[];
      for (final realm in settings.realms) {
        for (final method in realm.auth.methods) {
          final options = realm.auth.optionsFor(method);
          if (options?['authenticator'] == entry.key && method == 'ticket') {
            realms.add(realm.name);
          }
        }
      }
      if (realms.isEmpty) {
        continue;
      }
      return _RemoteAuthBenchConfig(
        authHost: host,
        authPort: port,
        rpcRealm: rpcRealm,
        serviceAuthId: serviceAuthId,
        serviceSecretFile: serviceSecretFile,
        authTokenFile: authTokenFile,
        realms: List<String>.unmodifiable(realms),
      );
    }
    return null;
  }

  static void _writeFile(String path, String value) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(value);
  }
}

RouterConfig _buildAuthRouterConfig(_RemoteAuthBenchConfig config) =>
    RouterConfig(
      endpoints: <Endpoint>[
        Endpoint(
          host: config.authHost,
          port: config.authPort,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
          sniCertificates: <SniCertificate>[
            SniCertificate(
              hostname: 'localhost',
              certificateChainPem: _readCertFixture(
                'remote_auth_server_cert.pem',
              ),
              privateKeyPem: _readCertFixture('remote_auth_server_key.pem'),
            ),
          ],
          clientAuth: TlsClientAuth(
            mode: TlsClientAuthMode.required,
            caCertificatesPem: _readCertFixture('remote_auth_ca_cert.pem'),
          ),
        ),
      ],
    );

RouterSettings _buildAuthRouterSettings(_RemoteAuthBenchConfig config) {
  final listener =
      ListenerSettingsBuilder(
          'rawsocket',
          '${config.authHost}:${config.authPort}',
        )
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
            config.serviceAuthId: <String, Object?>{
              'ticket': config.serviceTicket,
              'role': 'service',
              'provider': 'bench-remote-auth-router',
            },
          },
        },
      ),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder(config.rpcRealm)
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const <String, Object?>{'authenticator': 'ticket-service'},
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

RouterSettings _buildAuthServerSettings(_RemoteAuthBenchConfig config) {
  final builder = RouterSettingsBuilder()
    ..addAuthenticator(
      'ticket-basic',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            RemoteAuthBenchHarness.defaultAuthId: <String, Object?>{
              'ticket': RemoteAuthBenchHarness.defaultAuthSecret,
              'role': RemoteAuthBenchHarness.defaultAuthRole,
              'provider': 'bench-remote-auth-server',
            },
          },
        },
      ),
    );
  for (final realmName in config.realms) {
    builder.addRealmFromBuilder(
      RealmSettingsBuilder(realmName)
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const <String, Object?>{'authenticator': 'ticket-basic'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(RemoteAuthBenchHarness.defaultAuthRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder('bench.')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const <String>[
                  'subscribe',
                  'unsubscribe',
                  'register',
                  'unregister',
                  'publish',
                  'call',
                ]),
            ),
        ),
    );
  }
  return builder.build();
}

String _readCertFixture(String fileName) =>
    File(_fixturePath(fileName)).readAsStringSync();

String _fixturePath(String fileName) {
  final candidates = <String>[
    'packages/connectanum_router/test/certs/$fileName',
    '../connectanum_router/test/certs/$fileName',
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
