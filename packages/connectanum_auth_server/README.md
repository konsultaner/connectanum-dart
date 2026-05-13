# connectanum_auth_server

`connectanum_auth_server` provides the reusable pieces for running a standalone
remote authentication service for Connectanum routers.

It implements the same WAMP RPC contract used by the router's
`RemoteAuthenticatorDelegate` integration, so you can move authentication out
of the main router process without changing the protocol boundary.

Status: workspace package, currently `publish_to: none`.

## What It Provides

- `AuthServer`
  Config-driven remote authenticator implementation backed by
  `RouterSettings`.
- `AuthServerProcedureBinding`
  Registers the WAMP procedures that expose the remote-auth contract on a
  router session.

The default procedure names are:

- `authenticate.hello`
- `authenticate.authenticate`
- `authenticate.abort`

## Quick Start

```dart
import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main() async {
  final settings = (RouterSettingsBuilder()
        ..addRealmFromBuilder(
          RealmSettingsBuilder('demo.realm')
            ..addAuthMethod(
              'ticket',
              options: {'authenticator': 'ticket-basic'},
            ),
        )
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
        ))
      .build();

  final authServer = AuthServer(settings: settings);

  final runtime = NativeTransportRuntime()..start();
  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 8085,
          webSocketPath: '/ws',
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
    settings: (RouterSettingsBuilder()
          ..addRealmFromBuilder(
            RealmSettingsBuilder('connectanum.authenticate'),
          ))
        .build(),
  );

  final binding = router.start(runtime);
  final session = await binding.createInternalSession(
    realmUri: 'connectanum.authenticate',
    authId: 'auth-service',
    authRole: 'internal',
  );

  await AuthServerProcedureBinding.bind(
    server: authServer,
    session: session,
  );
}
```

## Operational Notes

- Pair the auth service listener with TLS or mTLS in production.
- Use shared `auth_token` or service credentials when the edge router calls the
  remote authenticator.
- The package is designed to consume the same `RouterSettings` and credential
  providers as the in-process router auth path.

## Examples And Related Docs

- remote auth demo:
  [../connectanum_router/example/remote_websocket.dart](../connectanum_router/example/remote_websocket.dart)
- repo deployment guide: [../../docs/deployment.md](../../docs/deployment.md)
- repo overview: [../../README.md](../../README.md)
