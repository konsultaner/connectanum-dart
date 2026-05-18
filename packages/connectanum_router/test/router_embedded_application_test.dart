@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

void main() {
  final libraryPath = resolveOrBuildNativeLib();
  final skipReason = libraryPath == null
      ? 'Native ct_ffi library not found'
      : null;

  test(
    'embedded application sessions use RouterSession helpers for RPC and pubsub',
    () async {
      final runtime = NativeTransportRuntime(libraryPath: libraryPath!);
      RouterBinding? binding;
      RouterSession? serviceSession;
      RouterSession? applicationSession;

      try {
        try {
          runtime.shutdown();
        } catch (_) {}
        runtime.start();

        final router = Router(_routerConfig(), settings: _routerSettings());
        binding = router.start(runtime);

        serviceSession = await binding.createInternalSession(
          realmUri: 'consumer.realm',
          authId: 'service-session',
          authRole: 'service',
        );
        applicationSession = await binding.createInternalSession(
          realmUri: 'consumer.realm',
          authId: 'application-session',
          authRole: 'consumer',
        );

        await serviceSession.registerHandler('consumer.echo', (invocation) {
          invocation.respondWith(
            argumentsKeywords: <String, dynamic>{
              'message': invocation.argumentsKeywords?['message'],
              'servedBy': serviceSession!.authId,
            },
          );
        });

        final eventPayload = Completer<Map<String, dynamic>?>();
        await applicationSession.subscribePayloadHandler('consumer.status', (
          event,
        ) {
          if (!eventPayload.isCompleted) {
            eventPayload.complete(event.argumentsKeywords);
          }
        });

        final result = await applicationSession.callSinglePayload(
          'consumer.echo',
          argumentsKeywords: const <String, dynamic>{'message': 'ready'},
        );
        expect(
          result.argumentsKeywords,
          equals(const <String, dynamic>{
            'message': 'ready',
            'servedBy': 'service-session',
          }),
        );

        await serviceSession.publish(
          'consumer.status',
          argumentsKeywords: const <String, dynamic>{'status': 'ready'},
          options: PublishOptions(acknowledge: true),
        );

        expect(
          await eventPayload.future.timeout(const Duration(seconds: 2)),
          equals(const <String, dynamic>{'status': 'ready'}),
        );
      } finally {
        await applicationSession?.close();
        await serviceSession?.close();
        binding?.dispose();
        try {
          runtime.shutdown();
        } catch (_) {}
        runtime.dispose();
      }
    },
    skip: skipReason,
  );
}

RouterConfig _routerConfig() => RouterConfig(
  endpoints: <Endpoint>[
    Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
    ),
  ],
);

RouterSettings _routerSettings() {
  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(
          RealmSettingsBuilder('consumer.realm')
            ..addAuthMethod('anonymous')
            ..addRoleFromBuilder(
              RoleSettingsBuilder('consumer')
                ..addPermissionFromBuilder(_consumerPermissions()),
            )
            ..addRoleFromBuilder(
              RoleSettingsBuilder('service')
                ..addPermissionFromBuilder(_consumerPermissions()),
            ),
        )
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
            ..addAuthMethod('anonymous')
            ..setRawSocketOptions(
              const RawSocketListenerSettings(maxFrameExponent: 16),
            ),
        )
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        ))
      .build();
}

PermissionSettingsBuilder _consumerPermissions() =>
    PermissionSettingsBuilder('consumer.')
      ..setMatchPolicy(PermissionMatchPolicy.prefix)
      ..allowOperations(const <String>[
        'call',
        'publish',
        'register',
        'subscribe',
        'unregister',
        'unsubscribe',
      ]);
