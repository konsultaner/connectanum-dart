# connectanum_mcp

`connectanum_mcp` lets a Dart or Flutter application expose MCP servers and
consume router-hosted MCP endpoints without taking a dependency on a private
bridge protocol. It covers local stdio MCP servers, router-hosted HTTP
JSON-RPC and Streamable HTTP endpoints, and MCP tools backed by normal
Connectanum WAMP procedures.

The supported MCP protocol revision is `2025-11-25`. The package intentionally
implements a narrow, stable subset first:

- lifecycle negotiation with `initialize` and `notifications/initialized`
- `tools/list`, including optional cursor pagination for large tool catalogs
- `tools/call`, including structured tool results
- `prompts/list` and `prompts/get` for user-selected prompt templates
- `resources/list`, `resources/read`, and `resources/templates/list` for
  read-only application context
- icon metadata for implementations, tools, prompts, resources, and resource
  templates
- newline-delimited stdio transport for local MCP clients
- WAMP-backed tool delegation through an existing `connectanum_client` session
- declared WAMP API helpers for procedures, metadata, and pub/sub topics
- router-hosted MCP endpoints through `connectanum_router` `mcp` HTTP routes
- direct router-hosted JSON-RPC calls for the same tool/meta API catalog

The package itself does not ship prompt argument completions, sampling, or
tasks yet. Network MCP endpoints are hosted by `connectanum_router` routes with
`type: mcp`; they support Streamable HTTP `POST`, optional SSE responses,
`GET`/SSE polling, `DELETE` session teardown, and direct JSON-RPC tool/meta API
calls for frontend clients that do not need the MCP `initialize` lifecycle.
Consumer clients can use `McpStreamableHttpClient` from
`package:connectanum_mcp/connectanum_mcp_io.dart`, including
`McpStreamableHttpClient.withBearerToken(...)` for bearer-protected routes.
Tool execution failures are returned as MCP tool results with `isError: true`;
malformed JSON-RPC messages, unknown methods, and invalid parameters remain
protocol errors.

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

## Icons and Display Metadata

Tools, prompts, resources, resource templates, and `McpServerInfo` can carry
MCP icon metadata:

```dart
McpTool(
  name: 'task.create',
  icons: const [
    McpIcon(
      src: 'https://example.com/icons/task.png',
      mimeType: 'image/png',
      sizes: ['48x48'],
      theme: McpIconTheme.light,
    ),
  ],
  handler: (_) => McpToolResult.text('created'),
);
```

`McpIcon.src` accepts `http`, `https`, and `data` URI schemes and serializes the
optional `mimeType`, `sizes`, and `theme` fields. The package does not fetch,
cache, or render icons; consumers should treat icon metadata and bytes as
untrusted display hints.

## Tool Results

Use `McpToolResult.text(...)` for the common text-plus-structured-data case.
When a tool needs richer unstructured output, return typed MCP content blocks
from `McpToolResult.content`:

```dart
McpToolResult(
  content: [
    McpTextContent(
      'Open task context is available.',
      annotations: McpContentAnnotations(audience: ['assistant']),
    ),
    McpResourceLinkContent(
      uri: 'app://tasks/open',
      name: 'open-tasks',
      title: 'Open Tasks',
      mimeType: 'application/json',
    ),
    const McpEmbeddedResourceContent(
      resource: McpTextResourceContent(
        uri: 'app://tasks/open',
        mimeType: 'application/json',
        text: '{"tasks":[]}',
      ),
    ),
  ],
  structuredContent: {'count': 0},
);
```

The package serializes MCP text, image, audio, resource-link, and embedded
resource content blocks. `McpImageContent.bytes(...)`,
`McpAudioContent.bytes(...)`, and `McpBlobResourceContent.bytes(...)` encode
binary payloads as base64. Use `structuredContent` for JSON-shaped output that
should be validated against a tool `outputSchema`.

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

## Prompts

Use prompts for user-selected templates that a host or MCP client can present
as commands:

```dart
final server = McpServer(
  serverInfo: const McpServerInfo(name: 'prompts', version: '1.0.0'),
  promptListPageSize: 50,
  prompts: [
    McpPrompt(
      name: 'task.summary',
      title: 'Task Summary',
      description: 'Summarizes an application task.',
      arguments: [
        McpPromptArgument(
          name: 'task_id',
          description: 'Application task identifier.',
          required: true,
        ),
      ],
      handler: (request) {
        final taskId = request.arguments['task_id']!;
        return McpPromptResult.text(
          'Summarize task $taskId for the current user.',
          description: 'Task summary prompt for $taskId.',
        );
      },
    ),
  ],
);
```

When prompts are configured, the server advertises the MCP `prompts`
capability during `initialize`. `prompts/list` supports optional cursor
pagination through `promptListPageSize`. `prompts/get` accepts string-valued
arguments, validates required prompt arguments before calling the handler, and
returns prompt messages with typed MCP content blocks.

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
{"jsonrpc":"2.0","id":6,"method":"prompts/list","params":{}}
{"jsonrpc":"2.0","id":7,"method":"prompts/get","params":{"name":"echo.summary","arguments":{"text":"hello"}}}
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
`HttpRouteActionType.mcp`; the router executes calls through the
route-authenticated WAMP principal or session, exposes exact procedure
registrations as MCP tools, adds permitted WAMP meta API tools, and enables the
declared pub/sub helper tools:

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
server process when the router is already running. Anonymous routes use a
route-scoped anonymous principal; bearer-protected routes execute as the token
principal. Network hardening still belongs in the route/session profile
configuration: bind local-only endpoints to localhost, require bearer or
stronger auth for network-visible routes, and expose only procedures/topics
whose realm permissions are intended for agents.

The same route `options` map can expose static MCP resources, resource
templates, and prompts without creating a separate `McpServer`:

```dart
options: {
  'resource_list_page_size': 50,
  'resource_template_list_page_size': 50,
  'prompt_list_page_size': 50,
  'resources': [
    {
      'uri': 'app://example/context',
      'name': 'example-context',
      'mime_type': 'text/plain',
      'text': 'Read-only context for the agent.',
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
}
```

Configured resources are served by `resources/list` and `resources/read`;
templates are served by `resources/templates/list`; prompts are served by
`prompts/list` and `prompts/get`. Prompt text replaces `{{argumentName}}`
placeholders with string arguments supplied by the MCP client. Dynamic
application-specific resource and prompt projection is intentionally separate
from WAMP procedure/topic auto-discovery so applications keep explicit control
over context and prompt surface area.

Malformed MCP route options are rejected while the router native config is
built or the router starts. That includes invalid configured procedures,
topics, resources, resource templates, prompts, and prompt arguments, so a
network-visible MCP route does not defer these errors until the first client
request.

Tool and topic catalogs are filtered for the effective route principal before
they are exposed through MCP or direct JSON-RPC. Callable procedures are listed
only when the principal may `call` them; topics are listed only for the allowed
`publish` and/or `subscribe` operations. Procedures declared with
`allowCall: false` can still appear in `connectanum.api.list` and
`connectanum.api.describe` as documentation-only metadata, but they are not
registered as callable MCP tools.

The same HTTP `POST` endpoint also accepts direct JSON-RPC tool calls for
frontend clients. These calls use the same catalog and authorization path as MCP
`tools/list` and `tools/call`, but they do not require `initialize` first. The
configured resource and prompt methods can be used the same way:

```json
{"jsonrpc":"2.0","id":1,"method":"connectanum.api.list","params":{"kind":"procedure"}}
{"jsonrpc":"2.0","id":2,"method":"app.task.create","params":{"title":"Ship docs"}}
{"jsonrpc":"2.0","id":3,"method":"connectanum.tool.call","params":{"name":"app.task.create","arguments":{"title":"Ship docs"}}}
{"jsonrpc":"2.0","id":4,"method":"connectanum.pubsub.publish","params":{"topic":"app.task.changed","argumentsKeywords":{"id":"T-1"},"acknowledge":true}}
{"jsonrpc":"2.0","id":5,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":6,"method":"prompts/get","params":{"name":"summarize-task","arguments":{"taskId":"T-1"}}}
```

`connectanum.tools.list` returns the current tool definitions. Dotted tool
names such as `app.task.create`, `connectanum.api.describe`, and
`connectanum.pubsub.publish` can be used directly as JSON-RPC methods with the
method `params` becoming the tool arguments. `connectanum.tool.call` is the
generic by-name form. Direct calls return the same MCP tool result JSON shape as
`tools/call`, including `structuredContent` and `isError`. Direct
`resources/*` and `prompts/*` calls return the same JSON result shapes as the
standard MCP methods, without creating or requiring an `MCP-Session-Id`.

## Compatibility Notes

The package follows MCP JSON-RPC semantics instead of WAMP semantics at the
public MCP boundary. WAMP is only an optional backend used by
`McpWampToolDelegate` and `McpWampApi`.

Use stdio for local agent integrations. Use `connectanum_router` HTTP routes
with `type: mcp` when an application needs a router-hosted network MCP endpoint.
The router-hosted route supports MCP JSON-RPC `POST`, Streamable HTTP session
IDs, POST responses that may arrive as JSON or SSE, GET/SSE polling with resume
cursors, DELETE-based session teardown, direct JSON-RPC frontend clients,
configured resources, configured resource templates, and configured prompts.
