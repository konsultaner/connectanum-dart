# connectanum_mcp

`connectanum_mcp` lets a Dart or Flutter application expose a small MCP server
without taking a dependency on a private bridge protocol. It is designed for the
first production shapes needed by Connectanum apps: local stdio MCP servers,
router-hosted HTTP JSON-RPC endpoints, and MCP tools backed by normal
Connectanum WAMP procedures.

The supported MCP protocol revision is `2025-11-25`. The package intentionally
implements a narrow, stable subset first:

- lifecycle negotiation with `initialize` and `notifications/initialized`
- `tools/list`, including optional cursor pagination for large tool catalogs
- `tools/call`, including structured tool results
- `resources/list`, `resources/read`, and `resources/templates/list` for
  read-only application context
- newline-delimited stdio transport for local MCP clients
- WAMP-backed tool delegation through an existing `connectanum_client` session
- declared WAMP API helpers for procedures, metadata, and pub/sub topics
- router-hosted MCP endpoints through `connectanum_router` `mcp` HTTP routes

The package itself does not ship a standalone full Streamable HTTP transport,
prompts, sampling, or tasks. Router-hosted HTTP MCP endpoints are provided by
`connectanum_router` routes with `type: mcp`; they support the request/response
JSON-RPC subset over HTTP `POST` and return `405` for `GET` because server-push
SSE streams are not implemented yet. Tool execution failures are returned as
MCP tool results with `isError: true`; malformed JSON-RPC messages, unknown
methods, and invalid parameters remain protocol errors.

## Quick Start

Create an in-memory server and register tools:

```dart
import 'package:connectanum_mcp/connectanum_mcp.dart';

final server = McpServer(
  serverInfo: const McpServerInfo(name: 'example', version: '0.1.0'),
  tools: [
    McpTool(
      name: 'echo',
      description: 'Echoes text arguments.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      },
      handler: (request) {
        final text = request.arguments['text'] as String? ?? '';
        return McpToolResult.text(text, structuredContent: {'echo': text});
      },
    ),
  ],
);
```

Transport adapters call `server.handleMessage(...)` with decoded JSON-RPC
objects and serialize the returned map when a response is produced. MCP
notifications return `null`.

Large tool catalogs can be paged by setting `toolListPageSize`:

```dart
final server = McpServer(
  serverInfo: const McpServerInfo(name: 'tools', version: '1.0.0'),
  toolListPageSize: 50,
  tools: tools,
);
```

Clients should pass `nextCursor` back unchanged. Malformed or stale cursors are
rejected with MCP `invalidParams` errors.

## Resources

Use resources for explicit, read-only context that a host or MCP client can
choose to load:

```dart
final server = McpServer(
  serverInfo: const McpServerInfo(name: 'context', version: '1.0.0'),
  resources: [
    McpResource(
      uri: 'app://tasks/open',
      name: 'open-tasks',
      title: 'Open Tasks',
      mimeType: 'application/json',
      read: (request) => [
        McpTextResourceContent(
          uri: request.uri,
          mimeType: 'application/json',
          text: '{"tasks":[]}',
        ),
      ],
    ),
  ],
  resourceTemplates: [
    McpResourceTemplate(
      uriTemplate: 'app://tasks/{id}',
      name: 'task',
      mimeType: 'application/json',
    ),
  ],
);
```

When resources or templates are configured, the server advertises the MCP
`resources` capability during `initialize`. `resources/list` and
`resources/templates/list` support optional cursor pagination through
`resourceListPageSize` and `resourceTemplateListPageSize`. `resources/read`
returns text or base64-encoded binary content and reports unknown URIs with the
MCP resource-not-found error code.

## Stdio Example

Run the example server with:

```bash
dart run packages/connectanum_mcp/example/stdio_echo_server.dart
```

The stdio transport reads one UTF-8 JSON-RPC message per line from `stdin` and
writes one JSON-RPC response per line to `stdout`. Notifications do not produce
response lines.

Minimal manual request sequence:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"demo","version":"0.1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hello"}}}
{"jsonrpc":"2.0","id":4,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{"uri":"app://example/context"}}
```

## WAMP Tool Delegation

Use `McpWampToolDelegate.session(...)` when an MCP tool should call an existing
Connectanum WAMP procedure:

```dart
final tool = McpWampToolDelegate.session(
  session: session,
  procedure: 'app.echo',
).toTool(
  name: 'echo',
  description: 'Calls app.echo through the current WAMP session.',
);
```

By default, MCP tool arguments are forwarded as WAMP keyword arguments. WAMP
results are returned as a lossless JSON-shaped MCP tool result containing
`arguments`, `argumentsKeywords`, and `details` when present. Custom argument
builders and result mappers can override that mapping for application-specific
tool contracts.

That default mapping is useful for application integrations because the MCP
surface can stay stable while the application keeps its existing WAMP procedure
names and authorization model. An application can expose a curated set of tools
by connecting a normal `Session`, wrapping selected procedures with
`McpWampToolDelegate`, and serving them over stdio to the local MCP client.

## Declared WAMP APIs

Use `McpWampApi` when an application wants to expose a larger, human-readable
WAMP surface instead of hand-registering each MCP tool:

```dart
final api = McpWampApi(
  name: 'app',
  procedures: [
    McpWampProcedure(
      procedure: 'app.task.create',
      toolName: 'app.task.create',
      title: 'Create Task',
      description: 'Creates an application task.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
        'required': ['title'],
      },
      metadata: const McpWampApiMetadata(
        domain: 'app',
        entity: 'task',
        verbs: ['create'],
        tags: ['task'],
      ),
    ),
  ],
  topics: [
    McpWampTopic(
      topic: 'app.task.changed',
      title: 'Task Changed',
      description: 'Emitted when a task changes.',
    ),
  ],
);

final tools = api.toSessionTools(session: session);
```

Declared procedures become normal MCP tools backed by WAMP `CALL`. The helper
also adds `connectanum.api.list` and `connectanum.api.describe` so MCP clients
can inspect procedure/topic metadata, schemas, tags, and descriptions before
calling application-specific tools.

Procedure metadata can also declare topics through
`McpWampApiMetadata.publishesEvents`. Those topics are added to the declared
topic catalog automatically, which lets an API registration advertise the
events an agent can publish, subscribe to, and poll.

Declared topics can optionally expose `connectanum.pubsub.publish`,
`connectanum.pubsub.subscribe`, `connectanum.pubsub.poll`, and
`connectanum.pubsub.unsubscribe`. MCP does not provide a server-push event
channel in this package yet, so topic events are buffered per subscription and
read through `connectanum.pubsub.poll`. Use `queueLimit` on subscribe requests
to bound memory for local agents.

## Router-Hosted MCP Endpoint

`connectanum_router` can host an MCP endpoint directly. Add an HTTP route with
`HttpRouteActionType.mcp`; the router creates or reuses its internal WAMP
session for that route, exposes exact procedure registrations as MCP tools,
adds the standard WAMP meta API tools, and enables the declared pub/sub helper
tools:

```dart
const HttpRouteSettings(
  match: HttpRouteMatch(path: '/mcp'),
  action: HttpRouteAction(
    type: HttpRouteActionType.mcp,
    realm: 'realm1',
    options: {
      'include_registered_procedures': true,
      'include_subscribed_topics': true,
      'include_standard_meta_api': true,
      'include_pubsub_tools': true,
    },
  ),
);
```

Registered procedures can provide human-readable MCP metadata by passing custom
WAMP registration details:

```dart
await session.register(
  'app.task.create',
  options: RegisterOptions(
    custom: {
      '_ai_meta_data': {
        'short_description': 'Create a task.',
        'domain': 'app',
        'entity': 'task',
        'verbs': ['create'],
        'tags': ['task'],
        'publishes_events': ['app.task.changed'],
        'input_json_schema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
          },
          'required': ['title'],
        },
      },
    },
  ),
);
```

The router-hosted endpoint means applications do not need to start a second MCP
server process when the router is already running. Network hardening still
belongs in the route/session profile configuration: bind local-only endpoints to
localhost, require bearer or stronger auth for network-visible routes, and
expose only procedures/topics whose realm permissions are intended for agents.

## Compatibility Notes

The package follows MCP JSON-RPC semantics instead of WAMP semantics at the
public MCP boundary. WAMP is only an optional backend used by
`McpWampToolDelegate` and `McpWampApi`.

Use stdio for local agent integrations. Use `connectanum_router` HTTP routes
with `type: mcp` when an application needs a router-hosted network MCP endpoint.
That route shape is intentionally narrower than full Streamable HTTP: it is
ready for normal JSON-RPC `POST` request/response clients, while GET/SSE server
push, explicit MCP session IDs, and router-hosted resource/prompt surfaces
remain future work.
