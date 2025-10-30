# connectanum-dart

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
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';

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
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';

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


## Network‑aware reconnect (example)

Enable optional network‑aware reconnect and observe connectivity while the client waits to reconnect. On IO platforms, set a probe target via `connectivityTestAddress` to avoid false negatives.

```dart
import 'package:connectanum/src/client.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';

final transport =
    WebSocketTransport.withJsonSerializer('ws://wamp.example.com:8080/ws');
final client = Client(realm: 'com.my.realm', transport: transport);

final options = ClientConnectOptions(
  reconnectTime: const Duration(seconds: 2),
  reconnectCount: -1, // infinite retries
  waitForNetwork: true, // wait until network is back before retrying
  networkCheckInterval: const Duration(seconds: 1),
  networkWaitTimeout: const Duration(seconds: 30),
  // IO only: probe target for connectivity checks (host:port)
  connectivityTestAddress: 'wamp.example.com:8080',
);

// Observe online/offline while the client is waiting to reconnect
client.onOnlineState.listen((online) {
  print('Network online: $online');
});

client.connect(options: options).listen(
  (session) {
    // connected
  },
  onError: (e) {
    // out of retries or unrecoverable error
  },
);
```

### IO defaults and `connectivityTestAddress`

- On IO platforms, the connectivity check performs a TCP connect to a target (host:port).
- If you don’t specify `connectivityTestAddress`, a generic host is used, which can be blocked or unreliable on some networks.
- Recommended:
  - Set `connectivityTestAddress` to your WAMP server’s host:port for the most relevant signal.
  - If that’s not possible, choose a highly available TCP endpoint (e.g., an HTTPS port on a reliable host in your environment).
  - Keep the `networkCheckInterval` modest (e.g., 1–2s) to balance responsiveness and network load.
- Note: The current implementation accepts a single probe target. If you need higher resilience, prefer using your own backend endpoint or handle multi‑target probing at the application layer.

## Running tests (VM and Web)

This project ships tests for both the Dart VM and the browser (Chrome).

- Run the full suite on VM and Chrome (Chrome will be launched headlessly by the test runner):
  - dart test

- Run only Chrome tests:
  - dart test -p chrome

If Chrome is not detected automatically, set the CHROME_EXECUTABLE environment variable to the absolute path of your Chrome/Chromium binary.

Typical paths:
- macOS: /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
- Linux (Debian/Ubuntu): /usr/bin/google-chrome or /usr/bin/chromium
- Windows (PowerShell): C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe

Examples:
- macOS/Linux (bash/zsh):
  - export CHROME_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  - dart test -p chrome test/network/network_connectivity_web_test.dart
- Linux (Chromium):
  - export CHROME_EXECUTABLE=/usr/bin/chromium
  - dart test -p chrome
- Windows (PowerShell):
  - $env:CHROME_EXECUTABLE = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
  - dart test -p chrome

Notes:
- The test runner is configured for Chrome in dart_test.yaml (platforms: [vm, chrome]).
- Browser tests compile with the dart2wasm compiler by default; ensure you’re on Dart >= 3.4.
- If tests appear flaky due to network status, try re-running them or ensuring your system is online.
