# connectanum_dart

> Work in progress: this package supersedes the historical `connectanum` client
> and will grow a router implementation alongside it. Until the next release is
> published on pub.dev, the legacy package remains available under the original
> name.

[![pub](https://img.shields.io/pub/v/connectanum.svg)](https://pub.dev/packages/connectanum)
[![travis](https://api.travis-ci.com/konsultaner/connectanum-dart.svg)](https://travis-ci.com/github/konsultaner/connectanum-dart)
[![codecov](https://codecov.io/gh/konsultaner/connectanum-dart/branch/master/graph/badge.svg)](https://codecov.io/gh/konsultaner/connectanum-dart)

This is a WAMP client implementation for the [dart language](https://dart.dev/) and [flutter](https://flutter.dev/) projects.
The project aims to provide a simple and extensible structure that is easy to use.
With this project I want return something to the great WAMP-Protocol community.

WAMP is trademark of [Crossbar.io Technologies GmbH](https://crossbario.com/).

Find install instructions on [pub.dev](https://pub.dev/packages/connectanum).

## Other Projects

- [Connectanum java router, web and WebSocket server](https://connectanum.com), MVC-like framework, based on WAMP-Protocol
- [jsonOdm](https://github.com/konsultaner/jsonOdm), a JavaScript mongodb like in memory data(base) handler.

## TODOs

- Multithreading for callee invocations
  - callee interrupt thread on incoming cancellations
- support auto switch auth methods for methods that need to define fields in the hello. At the moment this is only wamp scram.
- get the auth id that called a method

## Known Issues

If multiple authentication methods are used and wamp scram is one of it, wamp scram
needs to be the first one. If not wamp scram will not modify the hello as needed and will
eventually fail.

## Supported WAMP features

### Authentication

- ☑ [WAMP-CRA](https://wamp-proto.org/_static/gen/wamp_latest.html#wampcra)
- ☑ [TICKET](https://wamp-proto.org/_static/gen/wamp_latest.html#ticketauth)
- ☑ [CRYPTOSIGN](https://github.com/wamp-proto/wamp-proto/issues/230)
  - ☑ Load putty files
    - ☑ MAC validation
    - ☑ password support
  - ☑ Load open ssh files
    - ☐ file validation
    - ☑ password support
  - ☑ Create pkcs8 file from Seed
  - ☑ Load pkcs8 files
    - ☐ password support
  - ☐ Load PGP files
    - ☐ password support
  - ☑ Load base64 encoded ed25519 private key
  - ☑ Load hex encoded ed25519 private key
- ☑ [WAMP-SCRAM](https://wamp-proto.org/_static/gen/wamp_latest.html#wamp-scram)
  - ☑ Argon2
  - ☑ PBKDF2
  - ☑ reuse client key to save computation time

### Advanced RPC features

- ☑ Progressive Call Results
- ☑ Progressive Calls
- ☐ Call Timeouts
- ☑ Call Canceling
- ☑ Caller Identification
- ☐ Call Trust Levels
- ☑ Shared Registration
- ☐ Sharded Registration
- ☑ Payload PassThru Mode

### Advanced PUB/SUB features

- ☑ Subscriber Black- and Whitelisting
- ☑ Publisher Exclusion
- ☑ Publisher Identification
- ☐ Publication Trust Levels
- ☑ Pattern-based Subscriptions
- ☐ Sharded Subscriptions
- ☑ Subscription Revocation
- ☑ Event Retention
- ☑ Payload PassThru Mode

### Transport

- ☑ WebSockets
- ☑ RawSockets
- ☑ RawSockets with large data support (connectanum router only)
- ☑ LocalTransport for unit testing
- ☐ E2E encryption

### Transport Encoding

- ☑ JSON
- ☑ msgpack
- ☑ CBOR
- ☐ UBJSON
- ☐ FlatBuffer

## Stream model

The transport contains an incoming stream that is usually a single subscribe stream. A session will internally
open a new broadcast stream as soon as the authentication process is successful. The transport stream subscription
passes all incoming messages to the broadcast stream. If the transport stream is done, the broadcast stream will close
as well. The broadcast stream is used to handle all session methods. The user will never touch the transport stream
directly.

## Start the client

To start a client you need to choose a transport module and connect it to the desired endpoint.
When the connection has been established you can start to negotiate a client session by calling
the `client.connect()` method from the client instance. On success the client will return a
session object.

If your transport disconnects the session will invalidate. If reconnect is configured, the session
will try to authenticate an revalidate the session again. All subscriptions and registrations will
be recovered if possible.

```dart
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/json.dart';

final client = Client(
  realm: "my.realm",
  transport: WebSocketTransport(
    "ws://localhost:8080/wamp",
    new Serializer(),
    WebSocketSerialization.serializationJson
  )
);
final session = await client.connect().first;
```

## RPC

to work with RPCs you need to have an established session.

```dart
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/json.dart';

final client = Client(
  realm: "my.realm",
  transport: WebSocketTransport(
    "ws://localhost:8080/wamp",
    new Serializer(),
    WebSocketSerialization.serializationJson
  )
);
final session = await client.connect().first;

// Register a procedure
final registered = await session.register("my.procedure");
registered.onInvoke((invocation) {
  // to something with the invocation
})

// Call a procedure
await for (final result in session.call("my.procedure")) {
  // do something with the result
}
```

## Native runtime

To run the native integration tests or the native client transports you need
`ct_ffi` available. During `dart run` / `dart test`, the package build hook
compiles `ct_ffi` automatically on Linux and macOS as long as a Rust toolchain
is available. You can also build the Rust workspace yourself:

```bash
cd native/transport
cargo build -p ct_ffi --release
```

Point the Dart bindings to the produced shared library by setting the
`CONNECTANUM_NATIVE_LIB` environment variable or by placing the build output in
`native/transport/target/debug` (the default lookup path during development).
If `CONNECTANUM_NATIVE_LIB` is already set to a prebuilt library, the build
hook reuses that library instead of invoking Cargo. If your deployment provides
`ct_ffi` as a system/shared library, set `CONNECTANUM_SKIP_NATIVE_BUILD=1` to
disable Cargo in the build hook and rely on `CONNECTANUM_NATIVE_LIB` or the
platform loader search path.

The published Dart package does not ship prebuilt binaries; consumers are
expected to compile the native library for their platform following the steps
above. Tests that depend on the shared library (e.g.
`test/transport/native/native_transports_test.dart`) automatically skip when
the library is missing or when the platform is unsupported.
