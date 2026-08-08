# Examples

This page points at the shortest public examples in the repo and fills the
current gaps with copyable snippets for the APIs that matter most in practice.

## Runnable entrypoints

- [examples/quickstart](../examples/quickstart/README.md)
  - smallest end-to-end router and Dart client example, covering Publisher,
    Subscriber, Caller, and Callee
- [packages/connectanum_client/example/main.dart](../packages/connectanum_client/example/main.dart)
  - basic client connect, register, call, subscribe, and publish flow
- [packages/connectanum_router/example/main.dart](../packages/connectanum_router/example/main.dart)
  - local router with ticket, WAMP-CRA, SCRAM, and remote-auth demo providers
- [packages/connectanum_router/example/remote_websocket.dart](../packages/connectanum_router/example/remote_websocket.dart)
  - router with a WebSocket listener and an in-process remote auth delegate
- [packages/connectanum_router/example/router_hosted_mcp.dart](../packages/connectanum_router/example/router_hosted_mcp.dart)
  - router-hosted MCP endpoint that exposes a WAMP procedure over Streamable
    HTTP and direct JSON-RPC
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

When the router-native OpenMetrics HTTP routes are enabled, `/healthz` returns
`503 draining` while the router is draining so a load balancer can stop sending
new traffic.

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
`type: mcp`. The router-hosted endpoint supports MCP JSON-RPC `POST`,
Streamable HTTP session IDs, POST/SSE responses, GET/SSE polling, DELETE
session teardown, and direct JSON-RPC calls for frontend clients. It uses the
route-authenticated WAMP principal for calls and pub/sub, and should be
deployed behind the same TLS/auth controls as other protected HTTP routes.

```dart
const HttpRouteSettings(
  match: HttpRouteMatch(path: '/mcp'),
  action: HttpRouteAction(
    type: HttpRouteActionType.mcp,
    realm: 'realm1',
    options: {
      'max_request_bytes': 16 * 1024 * 1024,
      'max_response_bytes': 16 * 1024 * 1024,
      'max_sse_history_bytes': 16 * 1024 * 1024,
      'max_session_count': 1024,
      'max_request_scoped_listener_count': 1024,
      'max_wamp_subscription_count': 1024,
      'max_wamp_subscription_queue_limit': 100,
      'max_wamp_subscription_queue_bytes': 256 * 1024,
      'call_timeout_ms': 30000,
      'session_idle_timeout_ms': 600000,
      'resources': [
        {
          'uri': 'app://example/context',
          'name': 'example-context',
          'mime_type': 'text/plain',
          'text': 'Read-only context for the agent.',
        },
        {
          'uri': 'app://example/live-context',
          'name': 'example-live-context',
          'mime_type': 'application/json',
          'read_procedure': 'app.context.read',
          'update_topic': 'app.events.context.updated',
        },
      ],
      'resource_templates': [
        {'uri_template': 'app://example/task/{taskId}', 'name': 'task'},
      ],
      'prompts': [
        {
          'name': 'summarize-task',
          'arguments': [
            {'name': 'taskId', 'required': true},
          ],
          'messages': [
            {'role': 'user', 'text': 'Summarize task {{taskId}}.'},
          ],
        },
      ],
    },
  ),
);
```

Exact WAMP registrations become MCP tools automatically. WAMP meta API tools
and `connectanum.pubsub.*` helpers are enabled by default, then filtered by the
route-authenticated principal's realm permissions before they are advertised.
Configured resources, resource templates, and prompts are served by the
standard MCP `resources/*` and `prompts/*` methods.

Compatibility Streamable HTTP sessions expire after 10 minutes without MCP
traffic by default. Set `session_idle_timeout_ms` (or
`sessionIdleTimeoutMs`) per route to choose another non-negative millisecond
budget; `0` disables idle expiry. Expiry disposes the session's endpoint state
and subscriptions, and later requests carrying that stale session identifier
receive `404` so a conforming client can initialize a replacement session.
Modern `2026-07-28` and direct JSON requests remain sessionless.

Each route admits up to 1024 active compatibility sessions by default. Set
the positive `max_session_count` (or `maxSessionCount`) route option to choose
another bound. When the route is full, a new initialize request receives HTTP
`503` without an MCP session identifier; authenticated existing sessions and
sessionless direct JSON requests remain usable. DELETE and idle expiry release
capacity.

Modern `2026-07-28` request-scoped listeners are independently limited to 1024
per listener and route by default. Set the positive
`max_request_scoped_listener_count` (or
`maxRequestScopedListenerCount`) option to choose another bound. A request
above the limit receives HTTP `503`; closing a listener releases capacity,
while direct JSON and compatibility Streamable HTTP requests remain usable.

Each route also admits up to 1024 router-hosted WAMP subscription owners by
default, aggregated across direct JSON, compatibility Streamable HTTP, and
configured dynamic-resource subscriptions on the same listener and route. Set
the positive `max_wamp_subscription_count` (or
`maxWampSubscriptionCount`) option to choose another bound. Each logical
subscription holds at most 100 queued events by default; set the positive
`max_wamp_subscription_queue_limit` (or
`maxWampSubscriptionQueueLimit`) option to permit another caller-selected
ceiling. Each logical subscription also retains at most 256 KiB of UTF-8
JSON-encoded events by default; set the positive
`max_wamp_subscription_queue_bytes` (or
`maxWampSubscriptionQueueBytes`) option to choose another byte ceiling. The
subscribe result exposes the effective `queueByteLimit`; poll results expose
`remainingBytes`. Count or byte overflow drops the oldest buffered events,
while a single event larger than the byte ceiling is dropped immediately, and
the cumulative `dropped` count remains observable. An over-limit subscription
request returns an MCP tool error without disturbing an admitted subscription.
Explicit unsubscribe, session deletion or expiry, and endpoint shutdown
release capacity.

MCP POST bodies are limited to 16 MiB by default and rejected with HTTP `413`
before UTF-8 or JSON decoding. Set the positive `max_request_bytes` (or
`maxRequestBytes`) route option to choose another raw-byte limit. Bearer
authentication still runs first on protected routes, so an oversized request
without valid credentials receives the normal authentication challenge.

Encoded MCP JSON-RPC responses are also limited to 16 MiB by default. Set the
positive `max_response_bytes` (or `maxResponseBytes`) route option to choose
another bound. Oversized responses fail with HTTP `500` without an MCP session
identifier, while an established compatibility session remains reusable.

Compatibility Streamable HTTP replay history is limited to 128 events and, by
default, the route's response-byte ceiling. Set the positive
`max_sse_history_bytes` (or `maxSseHistoryBytes`) route option to choose a
larger encoded-SSE byte budget; it must be at least `max_response_bytes` so the
latest complete response can remain replayable. The router evicts oldest
events first. A cursor for an evicted event receives HTTP `400`, while the
compatibility session and sessionless direct JSON access remain usable.

Router-hosted MCP tool calls and WAMP-backed dynamic resource reads carry a
protocol-level 30-second CALL timeout by default. Set the positive
`call_timeout_ms` (or `callTimeoutMs`) route option to choose another bound.
When the route omits the option, a positive realm `call_timeout_ms` value is
used before the 30-second fallback. The router preserves a stricter timeout
already attached to the call and clamps longer or disabled timeouts to the
route bound; established request-scoped SSE streams are not timed out by this
setting.

Procedure-backed resources call the configured WAMP procedure with the
resource URI as the first positional argument and return its final result as
lossless JSON text. When `update_topic` is present, Streamable HTTP clients can
use `subscribeResource(...)`, receive `notifications/resources/updated` over
GET/SSE, re-read the resource, and later call `unsubscribeResource(...)`.
Authorization uses the route principal for both the procedure call and topic
subscription. Direct JSON supports resource list/read but not subscriptions.

The same endpoint also accepts direct JSON-RPC calls for frontend clients
without the MCP `initialize` lifecycle:

```json
{"jsonrpc":"2.0","id":1,"method":"connectanum.api.list","params":{"kind":"procedure"}}
{"jsonrpc":"2.0","id":2,"method":"app.echo","params":{"text":"hello"}}
{"jsonrpc":"2.0","id":3,"method":"connectanum.tool.call","params":{"name":"app.echo","arguments":{"text":"hello"}}}
```

For a protected endpoint used by standard MCP clients, configure OAuth
Protected Resource Metadata in the route options:

```yaml
protected_resource_metadata:
  metadata_url: https://mcp.example.com/mcp
  resource: https://mcp.example.com/mcp
  authorization_servers:
    - https://auth.example.com
  scopes_supported:
    - mcp:read
    - mcp:write
  resource_name: Example MCP
```

The router serves that document from the MCP route for JSON `GET` requests and
adds its URL to `WWW-Authenticate` on missing or invalid bearer credentials.
The configured authorization server must provide the OAuth 2.1 discovery and
token flows; Connectanum's ticket, WAMP-CRA, and SCRAM HTTP grant bridge remains
available as a separate application-specific authentication path.

Direct calls use the same route authentication, filtered catalog, and
authorization path as MCP `tools/call`. Procedures or topics that the route
principal may not use are not advertised as tools. Run the checked example with
`--smoke-and-exit` to verify the local toolchain path:

```bash
dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit
```
