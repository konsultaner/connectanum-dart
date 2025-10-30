# Connectanum Auth Server (preview)

This package will host reusable building blocks for running a standalone
remote authentication service that speaks the same WAMP RPC contract as the
router's `RemoteAuthenticatorDelegate` integration.

Roadmap for the next steps:

1. Share realm/credential configuration with the router so both can consume the
   same JSON/YAML settings.
2. Expose a simple CLI (`bin/auth_server.dart`) that boots the remote auth
   realm and wires in credential providers via `AuthCredentialRegistry`.
3. Provide examples, integration tests, and documentation guiding operators on
   how to migrate from in-process authenticators to a remote delegate.

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

  // Wire `server.onHello` / `server.onAuthenticate` into your WAMP RPC layer.
}
```

> **Note:** The current contents are scaffolding only. Functional pieces will be
> added in subsequent iterations.
