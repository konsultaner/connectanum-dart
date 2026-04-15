# Connectanum Auth Server (preview)

This package provides the reusable pieces for running a standalone remote
authentication service that speaks the same WAMP RPC contract as the router's
`RemoteAuthenticatorDelegate` integration.

Roadmap for the next steps:

1. Share realm/credential configuration with the router so both can consume the
   same JSON/YAML settings.
2. Expose a simple CLI (`bin/auth_server.dart`) that boots the remote auth
   realm and wires in credential providers via `AuthCredentialRegistry`.
3. Provide CLI/examples/documentation guiding operators on how to migrate from
   in-process authenticators to a remote delegate.

### Quick start (library usage)

```dart
import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main() async {
  final settings = RouterSettingsBuilder()
    ..addRealmFromBuilder(RealmSettingsBuilder('demo')
      ..addAuthMethod('ticket', options: {'authenticator': 'ticket-basic'}))
    ..addAuthenticator(
      'ticket-basic',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: {
          'secrets': {
            'alice': {'ticket': 's3cr3t', 'role': 'member'},
          },
        },
      ),
    );

  final server = AuthServer(settings: settings.build());
  final authRealmSettings = (RouterSettingsBuilder()
        ..addRealmFromBuilder(RealmSettingsBuilder('connectanum.authenticate'))
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('websocket', '127.0.0.1:8085')
            ..setPath('/ws')
            ..addProtocol(ListenerProtocol.websocket),
        ))
      .build();
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
    settings: authRealmSettings,
  );
  final runtime = NativeTransportRuntime()..start();
  final binding = router.start(runtime);
  final session = await binding.createInternalSession(
    realmUri: 'connectanum.authenticate',
    authId: 'auth-service',
    authRole: 'internal',
  );
  final procedures = await AuthServerProcedureBinding.bind(
    server: server,
    session: session,
  );
}
```

`AuthServerProcedureBinding` registers `authenticate.hello`,
`authenticate.authenticate`, and `authenticate.abort` on the given internal
session, performs strict request-shape validation, and forwards the calls into
`AuthServer`.
