# MCP Integration Research

Last checked: 2026-08-14
Driving use case: downstream application integrations

## Sources

- MCP 2026 base protocol and per-request metadata:
  https://modelcontextprotocol.io/specification/2026-07-28/basic/index
- MCP 2026 Streamable HTTP transport:
  https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
- MCP 2026 server discovery:
  https://modelcontextprotocol.io/specification/2026-07-28/server/discover
- MCP 2026 versioning and compatibility:
  https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning
- MCP 2026 TypeScript schema, including `CallToolResult`:
  https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.ts
- MCP argument completion:
  https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/completion
- MCP Tasks extension overview:
  https://modelcontextprotocol.io/extensions/tasks/overview
- Legacy MCP lifecycle retained for compatibility:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- Legacy Streamable HTTP transport retained for compatibility:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- Legacy schema, including the required `InitializeResult.protocolVersion`:
  https://modelcontextprotocol.io/specification/2025-11-25/schema
- MCP tools:
  https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- MCP pagination:
  https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/pagination
- MCP resources:
  https://modelcontextprotocol.io/specification/2025-11-25/server/resources
- MCP prompts:
  https://modelcontextprotocol.io/specification/2025-11-25/server/prompts
- MCP authorization:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization

## Current External Shape

- The current stable protocol revision is `2026-07-28`. It is a stateless
  JSON-RPC protocol: each request carries the protocol version and required
  client capabilities in `params._meta`, with optional client identity. A
  server must not infer those values from a prior request or connection.
- `server/discover` replaces initialization as the modern capability/version
  probe. Servers must implement it; clients may instead try an ordinary modern
  request and handle an `UnsupportedProtocolVersion` error.
- Modern Streamable HTTP uses one POST per JSON-RPC message. Clients advertise
  both JSON and SSE response support, mirror protocol/method/name metadata into
  HTTP headers, and require header/body agreement. Successful results carry a
  recognized `resultType`, normally `complete`, and should carry server
  identity in result `_meta`.
- The modern HTTP protocol has no protocol-level session, standalone GET
  stream, DELETE termination, or `Last-Event-ID` replay. Servers ignore legacy
  session/resume headers on modern requests and never mint or echo a session
  ID. Request-scoped SSE remains available for responses; long-lived change
  delivery uses `subscriptions/listen`.
- A `subscriptions/listen` request carries an explicit notification filter.
  The first SSE JSON-RPC message is
  `notifications/subscriptions/acknowledged` with the supported subset, and
  every acknowledgment, delivered notification, and graceful completion uses
  the request ID as `io.modelcontextprotocol/subscriptionId`. Closing the HTTP
  response stream cancels the listener; there is no cancellation POST or
  replay cursor.
- The specification reserves `-32020` for header mismatch, `-32021` for a
  missing required client capability, and `-32022` for an unsupported protocol
  version. Unknown modern RPC methods use HTTP 404 plus JSON-RPC `-32601`.
- Protocol revisions from `2025-03-26` through `2025-11-25` remain a separate
  compatibility era with `initialize`, optional `MCP-Session-Id`, GET/SSE,
  DELETE, and resume cursors. Connectanum retains that lifecycle explicitly;
  it does not reinterpret a 2025 session as a 2026 request.
  A compatibility client accepts a newly assigned session ID only from the
  response carrying a successful `InitializeResult`; a later response may
  omit that header or echo the active ID, but a different ID is a protocol
  error rather than an implicit session rotation.
  The successful result's required `protocolVersion` is likewise the
  authoritative negotiated version for the session, and clients must send
  that value in the `MCP-Protocol-Version` header on subsequent HTTP requests.
  The legacy transport specifies that request header but does not define a
  response version header. Connectanum accepts an optional response header as
  an interoperability echo only: it must match the successful initialize
  result or the already-active version, and it cannot renegotiate the client
  independently. A caller-supplied one-request compatibility override remains
  a Connectanum extension: its response echo must match that request override,
  but the override does not replace the session's negotiated version.
- Servers advertise capabilities through `server/discover` in the modern era
  and during `initialize` in the legacy era. The relevant server surfaces for
  Connectanum are `tools`, `resources`, `prompts`, and `completions`. Tasks
  remain an opt-in extension; logging is deprecated in the stable 2026 core.
- The standard transports remain `stdio` and Streamable HTTP. The older
  HTTP+SSE transport remains a compatibility concern for older clients, but it
  is not a primary new design target.
- `tools/list` discovers tools and `tools/call` invokes them. Tool definitions
  carry JSON Schema input metadata, and tool results can include text, media,
  resource links, embedded resources, and structured JSON content.
- In the 2026 schema, `CallToolResult.structuredContent` may contain any JSON
  value, including an explicit null. Field presence therefore cannot be
  inferred from a nullable value alone. A tool's `outputSchema` defines its
  application-specific contract; a generic transport must not impose an
  object-only result shape.
- `tools/list` supports cursor pagination. The server chooses page size,
  clients treat returned cursors as opaque tokens, and invalid cursors should
  fail with `invalidParams`.
- `resources/list`, `resources/read`, and `resources/templates/list` expose
  context objects by URI. In the legacy era, resource subscriptions and
  list-change notifications are optional. A server that advertises
  `resources.subscribe` accepts
  `resources/subscribe` and `resources/unsubscribe`; after subscription it may
  send `notifications/resources/updated` with the resource URI, and the client
  reads that resource again. In the modern era, change delivery maps to the
  request-scoped `subscriptions/listen` resource filter rather than reusing
  legacy protocol sessions.
- `prompts/list` and `prompts/get` expose user-selectable prompt templates.
  `prompts/list` supports cursor pagination, `prompts/get` accepts
  string-valued arguments, and prompt messages use `user` or `assistant` roles
  with typed MCP content blocks. `completion/complete` can target either a
  prompt argument (`ref/prompt`) or a resource-template variable
  (`ref/resource`); returned values are bounded to 100 and can report `total`
  plus `hasMore`. Prompt list-change notifications remain optional.
- MCP `icons` metadata can be attached to server/client implementations, tools,
  prompts, resources, and resource templates. Icon entries carry a required
  source URI plus optional MIME type, size strings, and a light/dark theme hint.
  Connectanum should serialize icon metadata for clients but should not fetch
  or trust icon bytes inside the MCP package.
- Authorization remains optional for MCP servers, but protected HTTP MCP
  servers need OAuth 2.0 Protected Resource Metadata discovery. A `401`
  challenge should identify the metadata URL through the
  `resource_metadata` parameter, and bearer credentials remain required on
  every protected MCP request.

## Connectanum Fit

- Use `packages/connectanum_core` as a design reference for the MCP package.
  The useful patterns are typed protocol objects, serializer-independent public
  APIs, lazy payload boundaries, explicit error types, and focused conformance
  tests. Do not copy WAMP semantics directly into MCP, but reuse the style that
  made the WAMP core small, testable, and transport-neutral.
- Do not expose WAMP itself as the public MCP transport in the first slice.
  MCP clients expect standard MCP transports, while Connectanum can remain the
  internal routing and service bus.
- Add a transport-independent Dart MCP server core first. The core should own
  JSON-RPC parsing, lifecycle state, capability negotiation, registry lookups,
  request cancellation/timeouts, and MCP error mapping.
- Add a `stdio` transport adapter early because most local agent/IDE MCP clients
  support it and it keeps the first smoke tests simple.
- Add router-hosted HTTP support as the application/server path. The first
  router slice can support JSON-RPC request/response over HTTP `POST` by
  dispatching through the route-authenticated WAMP principal or session, then
  grow into the full Streamable HTTP GET/SSE/session-header surface when
  server-push and explicit MCP HTTP session management are needed.
- Map Connectanum WAMP procedures to MCP tools. A tool registration should be
  able to call a Dart callback directly or delegate to a WAMP procedure through
  `connectanum_client`.
- Map read-only application context to MCP resources now that the tool path is
  stable. Resource URIs need explicit access control, especially for filesystem
  or project data. The package-local server remains transport-neutral but now
  exposes paired subscription lifecycle hooks. The router-hosted endpoint
  supports explicitly configured static resources and templates plus explicit
  WAMP read-procedure/update-topic mappings. Dynamic reads and subscriptions
  use the route principal's WAMP permissions, update event payloads are not
  trusted as resource contents, and automatic application-data discovery
  remains a separate product decision.
- Treat prompts as a transport-neutral MCP server primitive now that the
  package-local tools/resources path is stable. Prompt templates are
  user-selected surface area, so automatic projection from WAMP APIs should
  remain a separate product decision.
- Keep Connectanum's existing challenge-auth grant bridge as a supported
  application integration path, but do not present it as an OAuth 2.1
  authorization server. Protected router-hosted MCP routes can instead publish
  validated Protected Resource Metadata that points standards-aware clients to
  an operator-provided OAuth authorization server. Metadata retrieval is
  public and credential-free; its initial probe, response headers and body,
  challenged or well-known metadata, and authorization-server fallbacks share
  one configurable ten-second default deadline. Normal MCP POST, SSE GET, and
  DELETE traffic still revalidates bearer authorization. Credential-, session-,
  resume-, or grant-bearing MCP and router HTTP-auth requests do not follow
  redirects: a 3xx response remains a typed failure from the configured
  endpoint and cannot replace client session or resume state.

## MCP 2026 Implementation Direction

- Keep `McpServer` initialization and stdio behavior on the latest supported
  session-era revision until the transport-neutral core gains a deliberate
  multi-era dispatcher. Do not let a new HTTP constant silently change stdio
  or legacy Streamable HTTP behavior.
- Expose `2026-07-28` through explicit stateless HTTP client constructors.
  Those clients own request `_meta` and mirrored headers, never capture session
  or resume state, reject batches and legacy GET/DELETE helpers locally, and
  validate modern response `resultType` values.
- Let router-hosted MCP select the era per request. Modern POST requests use
  the same route principal and route-filtered tools/resources/prompts/WAMP
  helpers as legacy traffic, but validate modern metadata, return protocol-
  reserved errors, stamp successful results, and never create protocol session
  state.
- Advertise only capabilities implemented for the modern era. With
  `subscriptions/listen` available, router discovery may truthfully expose
  tool list-change and configured resource-subscription flags while leaving
  unsupported prompt/resource list-change flags absent.
- Keep each modern listener on its own HTTP client connection so consumer-side
  cancellation does not close ordinary request traffic or another listener.
  Router resource-update WAMP subscriptions can be shared, but preparation and
  active-listener references must prevent one concurrent listener from
  unsubscribing another.
- Treat MRTR input requests and cache metadata as the next compatibility layer.
  The router path remains a modern compatibility subset rather than a claim of
  complete `2026-07-28` conformance.

## Recommended First Package Shape

- Add `packages/connectanum_mcp` rather than putting MCP code into
  `connectanum_router` directly. That keeps the public MCP API usable by apps
  that only need a client/session bridge.
- Depend on `connectanum_core` for shared message/payload utilities and
  optionally on `connectanum_client` for WAMP-backed tool delegates.
- Mirror `connectanum_core`'s public shape where it helps readability: one
  small barrel library, narrowly named protocol model files, serializer/codec
  boundaries hidden behind typed methods, and tests that prove one protocol
  behavior per file instead of a single large integration-only suite.
- Keep the standalone `connectanum_mcp` server core transport-independent, and
  let `connectanum_router` consume it for hosted HTTP endpoints. Applications
  that already run a router should not have to start a second MCP server
  process.
- Provide a tiny public API around these concepts:
  `McpServer`, `McpServerInfo`, `McpTool`, `McpToolRegistry`,
  `McpToolRequest`, `McpToolResult`, `McpPrompt`, `McpPromptRegistry`,
  `McpResourceProvider`, `McpIcon`, and transport adapters for `stdio` plus
  router-hosted HTTP.

## First Implementation Slices

1. Create `packages/connectanum_mcp` with JSON-RPC request/response models,
   protocol constants, capability data classes, and lifecycle state.
2. Model the package structure after `packages/connectanum_core`: public barrel
   export, typed protocol data classes, explicit errors, and focused tests for
   lifecycle, tools, resources, and transport adapters.
3. Implement in-memory server tests for `initialize`,
   `notifications/initialized`, `tools/list`, unknown method errors,
   malformed request errors, and shutdown behavior.
4. Implement the tool registry and `tools/call` with text and structured JSON
   results, including `isError` tool-execution failures versus protocol errors.
5. Add a stdio adapter and a small CLI example that exposes one callback-backed
   tool. Done in `packages/connectanum_mcp` with `McpStdioTransport` and
   `example/stdio_echo_server.dart`.
6. Add a WAMP-backed tool delegate that calls a configured procedure through a
   `connectanum_client` session. Done in `packages/connectanum_mcp` with
   `McpWampToolDelegate`; the default mapping sends MCP arguments as WAMP
   kwargs and returns a lossless JSON-shaped MCP tool result.
7. Add cursor-safe `tools/list` pagination for larger tool catalogs. Done in
   `packages/connectanum_mcp` with `McpServer.toolListPageSize`, opaque
   `nextCursor` responses, and `invalidParams` for malformed or stale cursors.
8. Add a router-hosted MCP HTTP route that executes as the route-authenticated
   WAMP principal or session and auto-exposes exact WAMP registrations, WAMP
   meta API procedures, and declared pub/sub topics. Done for the MCP
   JSON-RPC `POST` request/response subset in `connectanum_router` with
   `HttpRouteActionType.mcp`; catalogs are filtered by the effective route
   principal's realm permissions before MCP or direct JSON-RPC clients see
   callable tools or pub/sub operations. The same route also accepts direct
   JSON-RPC tool and meta API calls for frontend clients through
   `connectanum.tools.list`, `connectanum.tool.call`, and dotted tool names
   such as `connectanum.api.list` or `app.task.create`.
9. Add full Streamable HTTP compatibility on top of the router endpoint when
   needed: GET/SSE server push, explicit `MCP-Session-Id` handling, strict
   `Accept`/`MCP-Protocol-Version` validation, Origin validation policy, and
   DELETE session termination semantics.
10. Add package-local resource support only after tool calls are stable and
   access-control rules are documented. Done for transport-independent
   `resources/list`, `resources/read`, `resources/templates/list`, and paired
   resource-subscription lifecycle hooks. The router-hosted endpoint serves
   explicitly configured static resources and resource templates plus
   procedure-backed resources with authorized update-topic subscriptions over
   Streamable HTTP. Automatic resource discovery and implicit application-data
   projection remain future slices.
11. Add full package-local `CallToolResult.content` block helpers. Done for
   text annotations, image, audio, resource links, and embedded resources.
   Optional result `_meta` is also implemented for ordinary, error, and
   `input_required` results, with lossless WAMP detail projection, typed client
   validation, and router-authoritative modern server identity. Arbitrary JSON
   `structuredContent`, including explicit null with separate field-presence
   semantics, is implemented across the public result API, installed-package
   smoke, and standard/direct Streamable HTTP client paths. Tasks remain a
   demand-driven opt-in extension.
12. Add package-local prompt support after resources/tool result content blocks
    are stable. Done for transport-independent `prompts/list` and
    `prompts/get`, required string-argument validation, prompt messages using
    existing typed content blocks, and stdio example coverage. The
    router-hosted endpoint now serves explicitly configured static prompt
    templates from route options. Prompt list-change notifications, sampling,
    tasks, and automatic prompt projection remain future slices.
13. Add package-local icon metadata after tools/resources/prompts are stable.
   Done for transport-independent `icons` serialization on `McpServerInfo`,
   tools, prompts, resources, and resource templates; icon fetching/rendering,
   WAMP catalog metadata projection, tasks, and sampling remain future slices.
14. Add package-local completion after prompts and resource templates are
    stable. Done for typed prompt/resource references, arguments, context,
    bounded results, server capability/dispatch, standard and direct HTTP
    client helpers, and router-configured static candidate sets. Router
    completions reuse authorization-filtered catalog visibility and are
    covered by neutral installed-package plus pinned official-client Router
    Image smokes. Dynamic ranking and application-data projection remain
    consumer-owned.

## Open Decisions for Application Integrations

- Whether an application needs stdio only, the router-hosted HTTP endpoint, or
  both.
- Which application actions should become tools, and which should remain
  private WAMP procedures.
- Whether the initial MCP endpoint is local-only or network-accessible.
- What authentication is expected for network-accessible MCP over HTTP.
- Which prompt templates should be exposed by each downstream application, and
  whether they should remain explicit registrations or be derived from WAMP API
  metadata later.

## Verification Expectations

- Run `bin/test-fast` before MCP code changes.
- Keep in-memory MCP protocol tests independent from network transports.
- Add focused stdio adapter tests before adding HTTP.
- Add router-backed HTTP tests only after the standalone server core is green.
- Run `bin/verify` before handoff and watch hosted CI after pushes.
