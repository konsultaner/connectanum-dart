# connectanum_mcp

`connectanum_mcp` lets a Dart or Flutter application expose MCP servers and
consume router-hosted MCP endpoints without taking a dependency on a private
bridge protocol. It covers local stdio MCP servers, router-hosted HTTP
JSON-RPC and Streamable HTTP endpoints, and MCP tools backed by normal
Connectanum WAMP procedures.

The package supports two MCP HTTP protocol eras:

- `2025-11-25` session-oriented Streamable HTTP with initialize, GET/SSE
  polling, resume cursors, and DELETE teardown
- the `2026-07-28` stateless core with `server/discover`, per-request client
  metadata, ordinary tool/resource/prompt and direct JSON calls, plus
  request-scoped `subscriptions/listen` SSE delivery and form-elicitation
  multi round-trip tool calls

The implementation intentionally keeps a narrow, stable subset:

- lifecycle negotiation with `initialize` and `notifications/initialized`
- `tools/list`, including optional cursor pagination for large tool catalogs
- `tools/call`, including structured tool results
- `prompts/list` and `prompts/get` for user-selected prompt templates
- `completion/complete` for prompt arguments and resource-template variables
- `resources/list`, `resources/read`, and `resources/templates/list` for
  read-only application context
- icon metadata for implementations, tools, prompts, resources, and resource
  templates
- newline-delimited stdio transport for local MCP clients
- WAMP-backed tool delegation through an existing `connectanum_client` session
- declared WAMP API helpers for procedures, metadata, and pub/sub topics
- router-hosted MCP endpoints through `connectanum_router` `mcp` HTTP routes
- direct router-hosted JSON-RPC calls for the same tool/meta API catalog
- modern filtered notifications for tool-list changes and configured dynamic
  resource updates
- bounded form-mode `elicitation/create` retries for tools that need
  non-sensitive consumer input

The package does not ship sampling or tasks yet. Network MCP endpoints are
hosted by `connectanum_router` routes with
`type: mcp`; they support Streamable HTTP `POST`, optional SSE responses,
`GET`/SSE polling, `DELETE` session teardown, and direct JSON-RPC tool/meta API
calls for frontend clients that do not need the MCP `initialize` lifecycle.
Consumer clients can use `McpStreamableHttpClient` from
`package:connectanum_mcp/connectanum_mcp_io.dart`, including
`ConnectanumHttpAuthClient` plus `McpStreamableHttpClient.withAuthGrant(...)`
for bearer-protected routes that issue HTTP auth bridge grants. Use the
explicit `stateless` constructors for `2026-07-28`; this keeps the modern
request-scoped lifecycle separate from session-era initialize/poll/delete. HTTP
auth issue, challenge, refresh, and revoke operations have one configurable
total deadline and accept only a configurable number of raw response bytes
before UTF-8/JSON decoding; overflow errors do not include the response body.
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

For a modern router-hosted endpoint, discover capabilities and open a filtered
request-scoped listener without creating an MCP session:

```dart
import 'package:connectanum_mcp/connectanum_mcp_io.dart';

final client = McpStreamableHttpClient.stateless(
  Uri.parse('http://127.0.0.1:8080/mcp'),
  clientInfo: const {'name': 'consumer-application', 'version': '1.0.0'},
);
final discovery = await client.discover();
final listener = await client.listen(
  toolsListChanged: true,
  resourceSubscriptions: const ['app://example/context/live'],
);

await for (final notification in listener.notifications) {
  // Refresh the advertised tool catalog or reread the updated resource.
  print(notification['method']);
}
```

Call `listener.close()` to cancel by closing its HTTP response stream. Multiple
listeners can be active concurrently. If an application needs custom proxy or
TLS settings, pass a `subscriptionHttpClientFactory` that returns a fresh
configured `HttpClient` for each listener so each stream remains independently
cancellable.

Ordinary buffered `POST`, `GET`, and `DELETE` responses plus request-scoped
listener setup bodies have a 16 MiB raw-byte limit by default. Set
`maxResponseBytes` on any client constructor when an endpoint needs a different
bound. Long-lived listener streams remain incremental; the same limit applies
separately to each complete SSE event, not to the total lifetime response.

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
  meta: {
    'com.example/trace': {'id': 'trace-1'},
  },
);
```

The package serializes MCP text, image, audio, resource-link, and embedded
resource content blocks. `McpImageContent.bytes(...)`,
`McpAudioContent.bytes(...)`, and `McpBlobResourceContent.bytes(...)` encode
binary payloads as base64. `structuredContent` accepts any JSON-compatible
value: an object, array, string, number, boolean, or explicit null. Use
`hasStructuredContent` when explicit null must be distinguished from an
omitted field, and validate the value against the tool's `outputSchema`. Use
`meta` for optional MCP result `_meta`; it is also available on the text,
error, and `inputRequired` constructors. The lossless WAMP mapper mirrors
JSON-compatible WAMP result details into `_meta` while retaining them under
`structuredContent.details`.

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
      read: (request, variables) => [
        McpTextResourceContent(
          uri: request.uri,
          mimeType: 'application/json',
          text: '{"taskId":"${variables['id']}"}',
        ),
      ],
    ),
  ],
  onSubscribeResource: (request) async {
    await subscribeApplicationUpdates(request.uri);
  },
  onUnsubscribeResource: (request) async {
    await unsubscribeApplicationUpdates(request.uri);
  },
);
```

When resources or templates are configured, the server advertises the MCP
`resources` capability during `initialize`. `resources/list` and
`resources/templates/list` support optional cursor pagination through
`resourceListPageSize` and `resourceTemplateListPageSize`. `resources/read`
returns text or base64-encoded binary content and reports unknown URIs with the
MCP resource-not-found error code. A template with `read` resolves concrete
URIs through simple RFC 6570 Level 1 `{variable}` expressions and passes
percent-decoded variables to its callback. Exact resources take precedence
over matching templates. Metadata-only templates remain listable but do not
handle reads.

The IO client keeps catalog entries as extension-friendly JSON maps, while the
shared `McpResourceUriTemplate` handles the security-sensitive parsing and
escaping needed to construct a concrete URI from an advertised template:

```dart
final page = await client.listResourceTemplates();
final entry = page.resourceTemplates.firstWhere(
  (template) => template['name'] == 'task',
);
final template = McpResourceUriTemplate(entry['uriTemplate']! as String);
final uri = template.expand({'id': 'task 7/primary'});
final contents = await client.readResource(uri);
```

Expansion requires every declared variable and percent-encodes decoded string
values as UTF-8. The bounded helper deliberately rejects RFC 6570 operators and
modifiers beyond simple Level 1 expressions.

Providing both resource subscription handlers advertises
`resources.subscribe: true` and enables `resources/subscribe` plus
`resources/unsubscribe`. The handlers own the application subscription
lifecycle; the transport or host remains responsible for sending
`notifications/resources/updated`. Configure both handlers together. An IO
client can own the corresponding Streamable HTTP lifecycle without hand-built
JSON-RPC:

```dart
await client.subscribeResource('app://tasks/open');
for (final event in await client.poll()) {
  final message = event.jsonData;
  if (message?['method'] == 'notifications/resources/updated') {
    final uri = (message!['params'] as Map)['uri'] as String;
    final contents = await client.readResource(uri);
    // Consume the refreshed contents.
  }
}
await client.unsubscribeResource('app://tasks/open');
```

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
      complete: (request) {
        const taskIds = ['TASK-100', 'TASK-101', 'ARCHIVE-900'];
        final prefix = request.argument.value.toLowerCase();
        return McpCompletionResult(
          values: taskIds.where(
            (taskId) => taskId.toLowerCase().startsWith(prefix),
          ),
        );
      },
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

Prompt arguments and resource-template variables can opt into
`completion/complete` with an `McpCompletionHandler`. The server advertises
`completions` when at least one configured prompt or resource template has a
handler. Completion results are limited to 100 values and can report `total`
and `hasMore` when a larger candidate set exists.

An IO consumer uses the same typed request for session-backed Streamable HTTP
or lifecycle-free direct JSON:

```dart
final request = McpCompletionRequest(
  reference: McpPromptReference(name: 'task.summary'),
  argument: McpCompletionArgument(name: 'task_id', value: 'TASK-1'),
  context: McpCompletionContext(arguments: {'project': 'active'}),
);
final sessionResult = await client.complete(request);
final directResult = await client.completeDirect(request);
```

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

## Router-Hosted Client Example

Run the router-hosted client example against a `connectanum_router` MCP route:

```bash
dart run packages/connectanum_mcp/example/router_hosted_client.dart \
  --endpoint http://127.0.0.1:8080/mcp \
  --resource-uri app://example/context/live \
  --resource-update-topic example.events.context.updated
```

From a consumer package, run the packaged executable directly. Select the
stateless protocol to exercise discovery, direct JSON tools, WAMP metadata,
and pub/sub without creating an MCP session:

```bash
dart run connectanum_mcp:router_hosted_client \
  --endpoint http://127.0.0.1:8080/mcp \
  --protocol-version 2026-07-28 \
  --wamp-procedure wamp.session.count \
  --wamp-topic example.events \
  --pubsub-topic example.events \
  --pubsub-event '{"source":"consumer-application"}'
```

The example imports only `package:connectanum_mcp/connectanum_mcp_io.dart` and
shows direct JSON tool/catalog calls, optional bearer or ticket auth-grant
client construction, direct JSON pub/sub helpers, session-era Streamable HTTP
`initialize` and deletion, or stateless `server/discover`. The optional
resource-update arguments are session-era only and run the complete typed
lifecycle against an explicitly mapped dynamic resource:
subscribe, publish an acknowledged WAMP update, poll the resumable GET/SSE
channel for `notifications/resources/updated`, read changed resource content,
and unsubscribe. Use `--resource-update-event` to replace the default JSON
event kwargs. The update topic must be declared by the route and authorized for
the route principal.

Use `--resource-template URI_TEMPLATE` with
`--resource-template-variables JSON_OBJECT` to require that the endpoint
advertises a selected Level 1 template, expand its decoded string variables,
and read the resulting URI through both direct JSON and compatibility
Streamable HTTP. Selected `--tool`, `--resource-uri`, `--prompt`, and
resource-template entries are resolved across opaque catalog cursors rather
than being limited to the first advertised page.

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

For MCP `2026-07-28` multi round-trip tool calls, the default mapping also
forwards request-scoped capabilities, input responses, and opaque request state
through WAMP call details. A WAMP callee can request form input by returning
`x_mcp_result_type: input_required`, `x_mcp_input_requests`, and an optional
`x_mcp_request_state` in its `YIELD` details. The retry arrives with
`x_mcp_input_responses` and the exact state value. The public constants live in
`McpWampMrtrFields`.

Consumers can complete that exchange without handling raw JSON-RPC:

```dart
final client = McpStreamableHttpClient.stateless(
  Uri.parse('https://router.example/mcp'),
  clientInfo: const {'name': 'consumer-app', 'version': '1.0.0'},
);

final result = await client.callToolDirectWithFormElicitation(
  'app.deploy',
  arguments: const {'release': '1.2.3'},
  onElicitation: (request) async {
    // Render request.message and request.requestedSchema in application UI.
    return McpFormElicitationResponse.accept(
      const {'region': 'eu', 'replicas': 3},
    );
  },
);
```

Use `callToolWithFormElicitation(...)` for the normal Streamable HTTP request
shape. Both helpers advertise form support only on that call, keep the original
tool arguments, use a fresh JSON-RPC ID for every retry, echo opaque state
unchanged, validate accepted values against the restricted flat schema, and
enforce a bounded round count. Form elicitation is for non-secret values; use a
separate authorization or URL-mode flow for credentials, payment data, or
other sensitive input. A server that requires form input from a caller that did
not advertise it returns MCP error `-32021` and HTTP 400 on a modern stateless
route.

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
  listPageSize: 50,
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
calling application-specific tools. When `listPageSize` is configured,
`connectanum.api.list` returns an opaque `nextCursor`; pass it back as
`cursor` with the same `kind` and `tag` filters. Unfiltered pages order
procedures first and topics second, with each catalog sorted by URI.

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

If an application regenerates its declared API when WAMP registrations or
topics change, pass the same endpoint-owned `McpWampPubSubState` to successive
`toTools` or `toSessionTools` calls. This keeps existing poll/unsubscribe
handles and buffered events while metadata and invokers rebind to the refreshed
catalog. Do not share one state object across endpoints, sessions, or
authorization principals.

When a refreshed catalog makes topics unsubscribable, call
`reconcileSubscribedTopics` on the retained state with the new subscribable
topic set. It releases only handles for removed permissions and keeps a handle
available for retry if cleanup fails. Hosts performing mandatory security
cleanup can supply a `release` callback that bypasses ordinary user-facing
unsubscribe authorization. A subscribe that is still awaiting its physical
WAMP acknowledgment is revoked irrevocably by the same reconciliation: its
buffered and later events are discarded, its eventual physical subscription
is released with the mandatory callback, and no logical handle is exposed.
Failed mandatory cleanup remains tracked for a later reconciliation retry.

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
      'wamp_api_list_page_size': 50,
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

The same route `options` map can expose static or explicitly procedure-backed
MCP resources, resource templates, and prompts without creating a separate
`McpServer`:

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
    {
      'uri': 'app://example/live-context',
      'name': 'example-live-context',
      'mime_type': 'application/json',
      'read_procedure': 'app.context.read',
      'update_topic': 'app.events.context.updated',
      'completions': {
        'taskId': ['TASK-100', 'TASK-101', 'ARCHIVE-900'],
      },
    },
  ],
  'resource_templates': [
    {
      'uri_template': 'app://example/task/{taskId}',
      'name': 'task',
      'read_procedure': 'app.context.read',
      'update_topic': 'app.events.context.updated',
    },
  ],
  'prompts': [
    {
      'name': 'summarize-task',
      'arguments': [
        {'name': 'taskId', 'required': true},
      ],
      'completions': {
        'taskId': ['TASK-100', 'TASK-101', 'ARCHIVE-900'],
      },
      'messages': [
        {'role': 'user', 'text': 'Summarize task {{taskId}}.'},
      ],
    },
  ],
}
```

Configured resources are served by `resources/list` and `resources/read`;
templates are served by `resources/templates/list`, and templates with a
`read_procedure` also resolve concrete `resources/read` URIs. Prompts are
served by `prompts/list` and `prompts/get`. Prompt text replaces
`{{argumentName}}` placeholders with string arguments supplied by the MCP
client. A prompt or resource template can also declare explicit `completions`
for its argument or URI-template variable names. The router filters those
candidates by case-insensitive prefix, accepts at most 1000 configured values
per argument, returns at most 100 values, and exposes them through standard
Streamable HTTP, modern stateless requests, and direct
JSON without creating a session. Completion access follows the same catalog
refresh and route-principal authorization as the referenced prompt or readable
resource template. A `read_procedure` receives the concrete resource URI as its first
positional WAMP argument. Template reads additionally receive percent-decoded
template variables as keyword arguments. Its final result is returned as
`application/json` text with
lossless `arguments`, `argumentsKeywords`, and `details` fields. An optional
`update_topic` on a procedure-backed resource or readable resource template
enables both session-era Streamable HTTP resource subscriptions and modern
`subscriptions/listen` resource filters. Template subscriptions use the
concrete URI selected by the consumer, not the URI-template expression. Each
authorized WAMP event delivers `notifications/resources/updated` with that
concrete resource URI, and the consumer reads the procedure-backed resource
again. Update event payloads are not treated as resource contents. Ordinary
direct JSON remains lifecycle-free; the modern listener is the dedicated
long-lived request.

Both the dynamic read procedure and update-topic subscription are checked
against the route-authenticated principal's WAMP permissions. Static resources
and templates without `read_procedure` cannot declare `update_topic`, and
dynamic resources cannot combine `read_procedure` with static `text`,
`content`, or `blob`. Resource and prompt auto-discovery remains intentionally
separate so applications keep explicit control over context and prompt surface
area.

Dynamic-resource and readable-template catalog visibility follows the
principal's current permission to call `read_procedure`, while update ownership
follows current permission to subscribe to `update_topic`. Each successful
catalog refresh revokes existing
Streamable and modern update grants when either permission is lost and releases
the shared WAMP update-topic subscription when it is no longer used. Losing
only update-topic access leaves the resource listed and readable.
Resource-list listeners remain open and receive
`notifications/resources/list_changed` when visibility changes. If a later
refresh restores access, the consumer must explicitly subscribe again or open
a new modern listener; an earlier update grant is not restored automatically.

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
registered as callable MCP tools. Each endpoint also releases existing generic
pub/sub handles when its next catalog refresh finds that their topic is no
longer subscribe-authorized. Restoring permission does not revive those
handles or allow an older pending subscribe to publish a new handle; the
consumer must subscribe again.

The same HTTP `POST` endpoint also accepts direct JSON-RPC tool calls for
frontend clients. These calls use the same catalog and authorization path as MCP
`tools/list` and `tools/call`, but they do not require `initialize` first. The
configured resource and prompt methods can be used the same way:

```json
{"jsonrpc":"2.0","id":1,"method":"connectanum.api.list","params":{"kind":"procedure"}}
{"jsonrpc":"2.0","id":2,"method":"connectanum.api.list","params":{"kind":"procedure","cursor":"opaque-next-cursor"}}
{"jsonrpc":"2.0","id":3,"method":"app.task.create","params":{"title":"Ship docs"}}
{"jsonrpc":"2.0","id":4,"method":"connectanum.tool.call","params":{"name":"app.task.create","arguments":{"title":"Ship docs"}}}
{"jsonrpc":"2.0","id":5,"method":"connectanum.pubsub.publish","params":{"topic":"app.task.changed","argumentsKeywords":{"id":"T-1"},"acknowledge":true}}
{"jsonrpc":"2.0","id":6,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":7,"method":"prompts/get","params":{"name":"summarize-task","arguments":{"taskId":"T-1"}}}
{"jsonrpc":"2.0","id":8,"method":"wamp.registration.lookup","params":{"procedure":"app.task.create","match":"exact"}}
{"jsonrpc":"2.0","id":9,"method":"wamp.registration.get","params":{"registrationId":123}}
```

`connectanum.tools.list` returns the current tool definitions. Dotted tool
names such as `app.task.create`, `connectanum.api.describe`, and
`connectanum.pubsub.publish` can be used directly as JSON-RPC methods with the
method `params` becoming the tool arguments. `connectanum.tool.call` is the
generic by-name form. Direct calls return the same MCP tool result JSON shape as
`tools/call`, including `structuredContent` and `isError`. Direct
`resources/*` and `prompts/*` calls return the same JSON result shapes as the
standard MCP methods, without creating or requiring an `MCP-Session-Id`.

When standard WAMP Meta APIs are enabled, `tools/list` advertises their named
parameters: `sessionId`, `procedure`, `registrationId`, `topic`, and
`subscriptionId`, with `match` on lookup operations. The same parameters work
as direct JSON-RPC method `params` and as `tools/call.arguments`. Existing raw
`arguments`/`argumentsKeywords` payloads remain supported, as do the legacy
`id`, `uri`, `session`, `registration`, and `subscription` aliases. A call must
select one identifier form rather than supplying conflicting aliases or both a
named identifier and raw WAMP arguments. Results use the advertised lossless
`arguments`, `argumentsKeywords`, and `details` envelope.

## Compatibility Notes

The package follows MCP JSON-RPC semantics instead of WAMP semantics at the
public MCP boundary. WAMP is only an optional backend used by
`McpWampToolDelegate` and `McpWampApi`.

Use stdio for local agent integrations. Use `connectanum_router` HTTP routes
with `type: mcp` when an application needs a router-hosted network MCP endpoint.
The router-hosted route supports MCP JSON-RPC `POST`, Streamable HTTP session
IDs, POST responses that may arrive as JSON or SSE, GET/SSE polling with resume
cursors, DELETE-based session teardown, direct JSON-RPC frontend clients,
`2026-07-28` stateless discovery and request-scoped listeners, configured
resources, configured resource templates, configured prompts, and bounded
form-elicitation tool retries.
