# connectanum-dart

This is a wamp client implementation for dart or flutter projects. The projects aims to 
provide a simple an extensible structure.

## Start the client

To start a client you need to choose a transport module and connect it to the desired endpoint.
When the connection has been established you can start to negotiate a client session by calling
the `client.connect()` method from the client instance. On success the client will return a
session object.

If your transport disconnects the session will invalidate. If a reconnect is configured, the session
will try to authenticate an revalidate the session again. All subscriptions and registrations will
be recovered if possible.

```dart
final transport = new WebSocketTransport("wss://localhost:8443");
final client = new Client(
    realm: "my.realm",
    transport: transport
);
await transport.open();
final session await client.connect();
```

## RPC

to work with RPCs you need to have an established session. 

```dart
final client = new Client();
// ...
final session await client.connect();

// Register a procedure
final registered = await session.register("my.procedure");
registered.invocationStream.listen(/*Your endpoint goes here*/)

// Call a procedure
final result = await session.call("my.procedure");
```
