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
- `AuthServerRouterBinding`
  Starts or attaches to a router binding, creates the internal service session,
  registers auth procedures, and owns shutdown for embedded auth services.

The default procedure names are:

- `authenticate.hello`
- `authenticate.authenticate`
- `authenticate.abort`

## Quick Start

For a packaged service, provide a router configuration that contains the auth
service listener, the `connectanum.authenticate` service realm, and the
authenticators/realms the service should evaluate. The CLI starts the native
runtime, binds the remote-auth WAMP procedures, and stays running until
SIGINT/SIGTERM:

```bash
dart run connectanum_auth_server:auth_server --config auth_service.yaml
```

Use `--check` in deployment smoke tests to start the runtime, bind procedures,
report readiness, and exit:

```bash
dart run connectanum_auth_server:auth_server --config auth_service.yaml --check
```

For embedded use, wire the same primitives directly:

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

  final binding = await AuthServerRouterBinding.start(
    server: authServer,
    config: RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 8085,
          tlsMode: TlsMode.disabled,
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
  // Keep `binding` alive while the embedded auth service should run.
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
