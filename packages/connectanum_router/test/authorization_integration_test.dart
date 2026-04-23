@TestOn('vm')
library authorization_integration_test;

import 'dart:async';

import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_client/src/transport/websocket/websocket_transport_io.dart'
    as ws_transport;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  test(
    'dynamic authorization provider applies to worker-isolate sessions',
    () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });

      final binding = Router(_buildConfig(), settings: _buildSettings()).start(
        runtime,
        workerEntryPoint: _authorizationWorkerEntryPoint,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);

      final url = 'ws://127.0.0.1:${binding.listeners.single.port}/ws';
      final client = client_pkg.Client(
        realm: 'realm1',
        transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
      );
      final session = await client.connect().first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('client connect timeout'),
      );
      addTearDown(session.close);

      await expectLater(
        session
            .publish(
              'com.example.authz.blocked',
              options: wamp_core.PublishOptions(acknowledge: true),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('publish timeout'),
            ),
        throwsA(
          isA<wamp_core.Error>()
              .having(
                (error) => error.error,
                'error',
                wamp_core.Error.notAuthorized,
              )
              .having(
                (error) => error.requestTypeId,
                'requestTypeId',
                wamp_core.MessageTypes.codePublish,
              ),
        ),
      );
    },
    skip: skipReason,
  );
}

RouterConfig _buildConfig() => RouterConfig(
  endpoints: [
    Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 18,
      webSocketPath: '/ws',
    ),
  ],
);

RouterSettings _buildSettings() {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..setAuthorizationProvider('deny-publish')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const ['publish']),
      ),
    );

  final listener = ListenerSettingsBuilder('websocket', '127.0.0.1:0')
    ..addAuthMethod('anonymous')
    ..setPath('/ws')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: ['wamp.2.json']),
    );

  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(realmBuilder)
        ..addListenerFromBuilder(listener)
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        )
        ..addAuthorizationProvider(
          'deny-publish',
          const AuthorizationProviderDefinition(
            type: 'deny-topic',
            options: {
              'topic': 'com.example.authz.blocked',
              'action': 'publish',
            },
          ),
        )
        ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1)))
      .build();
}

void _authorizationWorkerEntryPoint(Map<String, Object?> init) {
  AuthorizationProviderFactoryRegistry.registerFactory(
    const _DenyTopicAuthorizationProviderFactory(),
  );
  defaultRouterWorkerEntryPoint(init);
}

class _DenyTopicAuthorizationProviderFactory
    extends AuthorizationProviderFactory {
  const _DenyTopicAuthorizationProviderFactory();

  @override
  String get type => 'deny-topic';

  @override
  Future<AuthorizationProvider> create(Map<String, Object?> options) async {
    final topic = options['topic'] as String? ?? '';
    final actionName = options['action'] as String? ?? 'publish';
    return _DenyTopicAuthorizationProvider(
      topic: topic,
      action: _authorizationActionFromName(actionName),
    );
  }
}

class _DenyTopicAuthorizationProvider implements AuthorizationProvider {
  _DenyTopicAuthorizationProvider({required this.topic, required this.action});

  final String topic;
  final AuthorizationAction action;

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    if (request.action == action && request.uri == topic) {
      return const AuthorizationDecision.deny(message: 'blocked by provider');
    }
    return null;
  }
}

AuthorizationAction _authorizationActionFromName(String name) => switch (name) {
  'subscribe' => AuthorizationAction.subscribe,
  'unsubscribe' => AuthorizationAction.unsubscribe,
  'publish' => AuthorizationAction.publish,
  'call' => AuthorizationAction.call,
  'cancel' => AuthorizationAction.cancel,
  'register' => AuthorizationAction.register,
  'unregister' => AuthorizationAction.unregister,
  _ => throw ArgumentError.value(name, 'name', 'Unknown authorization action'),
};
