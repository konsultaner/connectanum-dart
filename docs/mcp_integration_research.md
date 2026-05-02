# MCP Integration Research

Last checked: 2026-05-02
Driving use case: downstream application integrations

## Sources

- MCP lifecycle, protocol version, and capability negotiation:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- MCP transports:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- MCP tools:
  https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- MCP pagination:
  https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/pagination
- MCP resources:
  https://modelcontextprotocol.io/specification/2025-11-25/server/resources
- MCP prompts:
  https://modelcontextprotocol.io/specification/2025-11-25/server/prompts
- MCP 2026 roadmap:
  https://blog.modelcontextprotocol.io/posts/2026-mcp-roadmap/

## Current External Shape

- MCP is a JSON-RPC protocol with a session lifecycle: `initialize`,
  normal operation after `notifications/initialized`, and transport-level
  shutdown.
- The current stable protocol revision is `2025-11-25`. Recheck the `latest`
  spec before implementation slices because MCP is still evolving.
- Servers advertise capabilities during initialization. The relevant server
  surfaces for Connectanum are `tools`, `resources`, `prompts`, `logging`, and
  eventually `tasks` or `completions`.
- The current standard transports are `stdio` and Streamable HTTP. The older
  HTTP+SSE transport remains a compatibility concern for older clients, but it
  should not be the primary new design target.
- HTTP clients send the negotiated protocol version in the
  `MCP-Protocol-Version` header on subsequent requests. Stateful Streamable
  HTTP servers may issue an `MCP-Session-Id` during initialization and require
  that header for later requests.
- `tools/list` discovers tools and `tools/call` invokes them. Tool definitions
  carry JSON Schema input metadata, and tool results can include text, media,
  resource links, embedded resources, and structured JSON content.
- `tools/list` supports cursor pagination. The server chooses page size,
  clients treat returned cursors as opaque tokens, and invalid cursors should
  fail with `invalidParams`.
- `resources/list`, `resources/read`, and `resources/templates/list` expose
  context objects by URI. Resource subscriptions and list-change notifications
  are optional.
- `prompts/list` and `prompts/get` expose user-selectable prompt templates.
  `prompts/list` supports cursor pagination, `prompts/get` accepts
  string-valued arguments, and prompt messages use `user` or `assistant` roles
  with typed MCP content blocks. Prompt list-change notifications and argument
  completion are optional.
- MCP `icons` metadata can be attached to server/client implementations, tools,
  prompts, resources, and resource templates. Icon entries carry a required
  source URI plus optional MIME type, size strings, and a light/dark theme hint.
  Connectanum should serialize icon metadata for clients but should not fetch
  or trust icon bytes inside the MCP package.

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
  reusing the router's internal WAMP session, then grow into the full
  Streamable HTTP GET/SSE/session-header surface when server-push and explicit
  MCP HTTP session management are needed.
- Map Connectanum WAMP procedures to MCP tools. A tool registration should be
  able to call a Dart callback directly or delegate to a WAMP procedure through
  `connectanum_client`.
- Map read-only application context to MCP resources now that the tool path is
  stable. Resource URIs need explicit access control, especially for filesystem
  or project data. The first package-local slice should stay transport-neutral:
  list/read/template-list only, no resource subscriptions or router-hosted
  resource projection until an application needs those semantics.
- Treat prompts as a transport-neutral MCP server primitive now that the
  package-local tools/resources path is stable. Prompt templates are
  user-selected surface area, so automatic projection from WAMP APIs should
  remain a separate product decision.

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
8. Add a router-hosted MCP HTTP route that reuses the router internal session
   and auto-exposes exact WAMP registrations, WAMP meta API procedures, and
   declared pub/sub topics. Done for the JSON-RPC `POST` request/response
   subset in `connectanum_router` with `HttpRouteActionType.mcp`.
9. Add full Streamable HTTP compatibility on top of the router endpoint when
   needed: GET/SSE server push, explicit `MCP-Session-Id` handling, strict
   `Accept`/`MCP-Protocol-Version` validation, Origin validation policy, and
   DELETE session termination semantics.
10. Add package-local resource support only after tool calls are stable and
   access-control rules are documented. Done for transport-independent
   `resources/list`, `resources/read`, and `resources/templates/list`; resource
   subscriptions and router-hosted resource projection remain future slices.
11. Add full package-local `CallToolResult.content` block helpers. Done for
   text annotations, image, audio, resource links, and embedded resources;
   `_meta`, tasks, and router-hosted resource projection remain future slices.
12. Add package-local prompt support after resources/tool result content blocks
    are stable. Done for transport-independent `prompts/list` and
    `prompts/get`, required string-argument validation, prompt messages using
    existing typed content blocks, and stdio example coverage; prompt
    list-change notifications, completions, sampling, tasks, and router-hosted
    prompt projection remain future slices.
13. Add package-local icon metadata after tools/resources/prompts are stable.
    Done for transport-independent `icons` serialization on `McpServerInfo`,
    tools, prompts, resources, and resource templates; icon fetching/rendering,
    WAMP metadata projection, `_meta`, tasks, sampling, and completions remain
    future slices.

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
