# Connectanum Quick Start

This example starts an anonymous local WebSocket router and uses one Dart
client session as Publisher, Subscriber, Caller, and Callee.

## Requirements

- Dart 3.9.2 or newer
- Rust stable when a compatible `ct_ffi` native library is not already
  available

From the repository root, prepare the workspace and start the router:

```bash
bin/bootstrap
bin/connectanum-router --config examples/quickstart/router.yaml
```

The first run may compile the native transport runtime. Leave the router
running and execute the client in a second terminal:

```bash
dart run examples/quickstart/client.dart
```

Expected client output:

```text
Pub/Sub: Hello from Connectanum
RPC: 2 + 3 = 5
```

Stop the router with `Ctrl+C`.

Continue with the [example catalog](../../docs/examples.md) for progressive
results and invocations, call cancellation, lazy payload APIs, authentication,
router-hosted MCP, resources, prompts, Pub/Sub, and WAMP Meta APIs.
