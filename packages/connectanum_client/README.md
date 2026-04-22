# connectanum_client

`connectanum_client` is the Dart and Flutter WAMP client package from the
Connectanum workspace.

It supports:

- WebSocket and RawSocket transports
- JSON, MessagePack, and CBOR serializers
- ticket, WAMP-CRA, SCRAM, and cryptosign authentication
- progressive RPC and advanced pub/sub features
- optional native RawSocket and native WebSocket transports on Linux and macOS

Status: active development. The API is usable, but the wider project is still
settling release and packaging conventions.

## Install

```bash
dart pub add connectanum_client
```

## Quick Start

```dart
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/json.dart';

Future<void> main() async {
  final client = Client(
    realm: 'demo.realm',
    transport: WebSocketTransport(
      'ws://127.0.0.1:8080/ws',
      Serializer(),
      WebSocketSerialization.serializationJson,
    ),
  );

  final session = await client.connect().first;

  final registration = await session.register('demo.ping');
  registration.onInvoke(
    (invocation) => invocation.respondWith(arguments: ['pong']),
  );

  final result = await session.callSingle('demo.ping');
  print(result.arguments?.first);

  await session.close();
  await client.disconnect();
}
```

More examples live under [example/](example).

## Transport Options

Use `WebSocketTransport` for standard WAMP-over-WebSocket and
`SocketTransport` for WAMP-over-RawSocket.

For the native client path on Linux and macOS, use
`NativeRawSocketTransport` or `NativeWebSocketTransport`. Those transports use
the Rust `ct_ffi` runtime through FFI and are intended for higher-throughput
or lower-allocation deployments.

## Native Runtime Setup

During `dart run` and `dart test`, the build hook can compile `ct_ffi`
automatically when a Rust toolchain is available.

If you want to use a published prebuilt bundle instead, install it explicitly:

```bash
export CONNECTANUM_NATIVE_LIB="$(
  dart run connectanum_client:tool/install_native.dart --tag <release-tag>
)"
```

The package also supports:

- `CONNECTANUM_NATIVE_LIB`
  Use an already-installed shared library.
- `CONNECTANUM_NATIVE_RELEASE_TAG`
  Let the build hook download a hosted prebuilt bundle.
- `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`
  Override the default GitHub Releases source.
- `CONNECTANUM_SKIP_NATIVE_BUILD=1`
  Skip Cargo entirely when your deployment provides `ct_ffi` itself.

For the complete deployment flow, see the repo-level
[deployment guide](../../docs/deployment.md).

## Authentication And Advanced Features

The client supports the current Connectanum feature set for:

- ticket authentication
- WAMP-CRA
- SCRAM
- cryptosign
- progressive call results
- call canceling
- shared registrations
- pattern-based subscriptions
- payload passthrough mode

The shared protocol and serializer primitives live in
[`connectanum_core`](../connectanum_core/README.md).

## Project Context

This package is part of the main Connectanum monorepo:

- repo overview: [../../README.md](../../README.md)
- router package: [../connectanum_router/README.md](../connectanum_router/README.md)
- auth server package:
  [../connectanum_auth_server/README.md](../connectanum_auth_server/README.md)
