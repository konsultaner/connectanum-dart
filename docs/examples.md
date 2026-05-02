# Examples

This page points at the shortest public examples in the repo and fills the
current gaps with copyable snippets for the APIs that matter most in practice.

## Runnable entrypoints

- [packages/connectanum_client/example/main.dart](../packages/connectanum_client/example/main.dart)
  - basic client connect, register, call, subscribe, and publish flow
- [packages/connectanum_router/example/main.dart](../packages/connectanum_router/example/main.dart)
  - local router with ticket, WAMP-CRA, SCRAM, and remote-auth demo providers
- [packages/connectanum_router/example/remote_websocket.dart](../packages/connectanum_router/example/remote_websocket.dart)
  - router with a WebSocket listener and an in-process remote auth delegate
- [packages/connectanum_mcp/example/stdio_echo_server.dart](../packages/connectanum_mcp/example/stdio_echo_server.dart)
  - local MCP stdio server example for agentic integrations
- [router_example.yaml](router_example.yaml)
  - minimal config starter for the router CLI

## Progressive RPC results

Use `Session.call(...)` with `CallOptions(receiveProgress: true)` when you need
intermediate results before the final reply:

```dart
final stream = session.call(
  'bench.progressive',
  options: CallOptions(receiveProgress: true),
);

await for (final result in stream) {
  if (result.progress) {
    print('partial result: ${result.arguments}');
  } else {
    print('final result: ${result.arguments}');
  }
}
```

If you only want the final result, use `callSingle(...)`,
`callSinglePayload(...)`, or `callSingleLazyPayload(...)` instead.

## Call cancellation

`Session.call(...)` and the `callSingle...(...)` variants accept
`cancelCompleter`. Completing it sends a WAMP `CANCEL` (`dart:async`):

```dart
final cancel = Completer<String>();

final stream = session.call(
  'bench.slow',
  cancelCompleter: cancel,
);

cancel.complete(CancelOptions.modeKillNoWait);
```

Supported modes today:

- `CancelOptions.modeSkip`
  - stop waiting locally without interrupting the callee
- `CancelOptions.modeKillNoWait`
  - interrupt the callee and complete the caller immediately
- `CancelOptions.modeKill`
  - interrupt the callee and wait for the callee-side cancellation/error
    acknowledgement

`killall` is not part of the current public contract.

## Lazy payload APIs

Use the lazy variants when your application wants to keep encoded args / kwargs
bytes intact for as long as possible:

```dart
final lazyResult = await session.callSingleLazyPayload(
  'bench.echo',
  arguments: const ['payload'],
);

print(lazyResult.argumentsBytes);
print(lazyResult.arguments);
```

The most important lazy/public entrypoints are:

- `Session.publishLazyPayload(...)`
- `Session.callSingleLazyPayload(...)`
- `Session.subscribeLazyPayloadHandler(...)`
- `Session.registerLazyPayloadHandler(...)`
- `LazyMessagePayload`

These APIs preserve encoded payload bytes when the transport, serializer, and
route support it. Mixed serializers or materialized APIs may still decode and
re-encode payloads.

## Graceful router shutdown

For library usage, `RouterBinding.drain()` is the explicit graceful-shutdown
entrypoint:

```dart
await binding.drain();
await binding.dispose();
runtime.shutdown();
runtime.dispose();
```

`dispose()` already calls `drain()`, so explicit `drain()` is only needed when
you want to separate “stop accepting traffic” from final teardown.

When the OpenMetrics HTTP server is enabled, `/healthz` returns `503 draining`
while the router is draining so a load balancer can stop sending new traffic.

## MCP bridge

Use `packages/connectanum_mcp` when a local agent or app needs a narrow MCP
server surface on top of Connectanum procedures. The first supported transport
is newline-delimited stdio; the bundled example exposes both an `echo` tool and
a small read-only `app://example/context` resource:

```bash
dart run packages/connectanum_mcp/example/stdio_echo_server.dart
```

For app integrations, wrap an existing WAMP session procedure as an MCP tool:

```dart
final tool = McpWampToolDelegate.session(
  session: session,
  procedure: 'app.echo',
).toTool(
  name: 'echo',
  description: 'Calls app.echo through the current WAMP session.',
);
```

For a network endpoint, configure a `connectanum_router` HTTP route with
`type: mcp`. The router-hosted endpoint accepts MCP JSON-RPC over HTTP POST,
uses the route-authenticated WAMP principal for calls and pub/sub, and should
be deployed behind the same TLS/auth controls as other protected HTTP routes.

```dart
const HttpRouteSettings(
  match: HttpRouteMatch(path: '/mcp'),
  action: HttpRouteAction(type: HttpRouteActionType.mcp, realm: 'realm1'),
);
```

Exact WAMP registrations become MCP tools automatically. WAMP meta API tools
and `connectanum.pubsub.*` helpers are enabled by default. The same endpoint
also accepts direct JSON-RPC calls for frontend clients without the MCP
`initialize` lifecycle:

```json
{"jsonrpc":"2.0","id":1,"method":"connectanum.api.list","params":{"kind":"procedure"}}
{"jsonrpc":"2.0","id":2,"method":"app.echo","params":{"text":"hello"}}
{"jsonrpc":"2.0","id":3,"method":"connectanum.tool.call","params":{"name":"app.echo","arguments":{"text":"hello"}}}
```

Direct calls use the same route authentication, catalog, and authorization path
as MCP `tools/call`. Full Streamable HTTP GET/SSE server push remains future
work.
