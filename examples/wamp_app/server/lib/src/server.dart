import 'dart:convert';
import 'dart:math';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_credential_provider.dart';
import 'account_store.dart';
import 'registration_service.dart';
import 'server_config.dart';
import 'wamp_app_worker.dart';

class WampAppServer {
  WampAppServer._({
    required this.websocketUri,
    required NativeTransportRuntime runtime,
    required RouterBinding binding,
    required Client serviceClient,
    required Session serviceSession,
  }) : _runtime = runtime,
       _binding = binding,
       _serviceClient = serviceClient,
       _serviceSession = serviceSession;

  final Uri websocketUri;
  final NativeTransportRuntime _runtime;
  final RouterBinding _binding;
  final Client _serviceClient;
  final Session _serviceSession;
  bool _closed = false;

  static Future<WampAppServer> start(WampAppServerConfig config) async {
    final store = AccountStore(config.accountStorePath);
    await store.initialize();
    final random = Random.secure();
    final serviceTicket = base64Url.encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );

    registerDefaultAuthenticators();
    AuthCredentialRegistry.registerProvider(
      AccountCredentialProvider(store: store, serviceTicket: serviceTicket),
    );

    final runtime = NativeTransportRuntime()..start();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: config.host,
            port: config.port,
            tlsMode: TlsMode.disabled,
            maxRawSocketSizeExponent: 18,
            webSocketPath: config.websocketPath,
          ),
        ],
      ),
      settings: _buildSettings(config, serviceTicket),
    );
    final binding = router.start(
      runtime,
      workerEntryPoint: wampAppRouterWorkerEntryPoint,
    );
    try {
      final listener = binding.listeners.single;
      final connectHost = switch (config.host) {
        '0.0.0.0' || '::' => '127.0.0.1',
        _ => config.host,
      };
      final websocketUri = Uri(
        scheme: 'ws',
        host: connectHost,
        port: listener.port,
        path: config.websocketPath,
      );
      final serviceClient = Client(
        transport: WebSocketTransport.withCborSerializer(
          websocketUri.toString(),
        ),
        realm: WampAppProtocol.registrationRealm,
        authId: WampAppProtocol.serviceAuthId,
        authenticationMethods: [TicketAuthentication(serviceTicket)],
      );
      final serviceSession = await serviceClient
          .connect(
            options: ClientConnectOptions(
              reconnectCount: 0,
              reconnectTime: const Duration(milliseconds: 100),
            ),
          )
          .first
          .timeout(const Duration(seconds: 15));
      final registrations = RegistrationService(
        store: store,
        iterations: config.argonIterations,
        memoryKiB: config.argonMemoryKiB,
      );
      await serviceSession.registerHandler(WampAppProtocol.accountRegister, (
        invocation,
      ) async {
        try {
          final request = AccountRegistration.fromWampKeywords(
            invocation.argumentsKeywords,
          );
          final receipt = await registrations.register(request);
          invocation.respondWith(argumentsKeywords: receipt.toWampKeywords());
        } on AccountAlreadyExists {
          invocation.respondWith(
            isError: true,
            errorUri: WampAppProtocol.errorUsernameTaken,
            arguments: const ['That username is already registered.'],
          );
        } on FormatException catch (error) {
          invocation.respondWith(
            isError: true,
            errorUri: WampAppProtocol.errorInvalidRegistration,
            arguments: [error.message],
          );
        } catch (_) {
          invocation.respondWith(
            isError: true,
            errorUri: WampAppProtocol.errorRegistrationUnavailable,
            arguments: const ['Registration is temporarily unavailable.'],
          );
        }
      });
      return WampAppServer._(
        websocketUri: websocketUri,
        runtime: runtime,
        binding: binding,
        serviceClient: serviceClient,
        serviceSession: serviceSession,
      );
    } catch (_) {
      await binding.dispose();
      runtime.shutdown();
      runtime.dispose();
      AuthCredentialRegistry.reset();
      rethrow;
    }
  }

  static RouterSettings _buildSettings(
    WampAppServerConfig config,
    String serviceTicket,
  ) {
    final settings = RouterSettingsBuilder()
      ..addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
      ..addAuthenticator(
        'ticket-service',
        AuthenticatorDefinition(
          type: 'ticket',
          options: wampAppWorkerOptions(
            accountStorePath: config.accountStorePath,
            serviceTicket: serviceTicket,
          ),
        ),
      )
      ..addAuthenticator(
        'scram-account',
        const AuthenticatorDefinition(type: 'scram'),
      );

    settings.addRealmFromBuilder(
      RealmSettingsBuilder(WampAppProtocol.registrationRealm)
        ..addAuthMethod('anonymous', options: {'authenticator': 'anonymous'})
        ..addAuthMethod('ticket', options: {'authenticator': 'ticket-service'})
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.anonymousRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.accountRegister)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['call']),
            ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.serviceRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.accountRegister)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['register', 'unregister']),
            ),
        )
        ..setLimits(
          const RealmLimitSettings(
            maxPendingAuth: 64,
            maxFailedAuth: 5,
            lockoutMs: 30000,
            callTimeoutMs: 65000,
          ),
        ),
    );
    settings.addRealmFromBuilder(
      RealmSettingsBuilder(WampAppProtocol.appRealm)
        ..addAuthMethod(
          WampAppProtocol.scramAuthMethod,
          options: {'authenticator': 'scram-account'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.memberRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder('com.wampapp.')
                ..setMatchPolicy(PermissionMatchPolicy.prefix),
            ),
        )
        ..setLimits(
          const RealmLimitSettings(
            maxPendingAuth: 128,
            maxFailedAuth: 5,
            lockoutMs: 30000,
            callTimeoutMs: 30000,
          ),
        ),
    );
    settings.addListenerFromBuilder(
      ListenerSettingsBuilder('websocket', '${config.host}:${config.port}')
        ..setPath(config.websocketPath)
        ..addProtocol(ListenerProtocol.websocket)
        ..addAuthMethod('anonymous')
        ..addAuthMethod('ticket')
        ..addAuthMethod(WampAppProtocol.scramAuthMethod)
        ..setWebSocketOptions(
          const WebSocketListenerSettings(
            subprotocols: ['wamp.2.cbor', 'wamp.2.json'],
          ),
        ),
    );
    return settings.build();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _serviceSession.close(timeout: Duration.zero);
    await _serviceClient.disconnect();
    await _binding.dispose();
    _runtime.shutdown();
    _runtime.dispose();
    AuthCredentialRegistry.reset();
  }
}
