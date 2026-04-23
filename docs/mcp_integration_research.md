# MCP Integration Research

Last checked: 2026-04-23
Driving downstream: `groli/app`

## Sources

- MCP lifecycle, protocol version, and capability negotiation:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- MCP transports:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- MCP tools:
  https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- MCP resources:
  https://modelcontextprotocol.io/specification/2025-11-25/server/resources
- MCP prompts:
  https://modelcontextprotocol.io/specification/2025-06-18/server/prompts
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
- `resources/list`, `resources/read`, and `resources/templates/list` expose
  context objects by URI. Resource subscriptions and list-change notifications
  are optional.
- `prompts/list` and `prompts/get` expose user-selectable prompt templates.
  This is useful later, but not required for the first `groli/app`-driven tool
  path.

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
- Add a Streamable HTTP adapter as the app/server path. This can later sit on
  top of `connectanum_router` HTTP routes so `groli/app` can embed or expose an
  MCP endpoint without a separate server stack.
- Map Connectanum WAMP procedures to MCP tools. A tool registration should be
  able to call a Dart callback directly or delegate to a WAMP procedure through
  `connectanum_client`.
- Map read-only application context to MCP resources only after the tool path is
  stable. Resource URIs need explicit access control, especially for filesystem
  or project data.
- Treat prompts as a second-phase feature unless `groli/app` needs prompt
  templates immediately.

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
- Keep `connectanum_router` integration optional. A router-backed HTTP adapter
  can be added once the standalone MCP core is tested.
- Provide a tiny public API around these concepts:
  `McpServer`, `McpServerInfo`, `McpTool`, `McpToolRegistry`,
  `McpToolRequest`, `McpToolResult`, `McpResourceProvider`, and transport
  adapters for `stdio` and Streamable HTTP.

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
   tool.
6. Add a WAMP-backed tool delegate that calls a configured procedure through a
   `connectanum_client` session.
7. Add a Streamable HTTP adapter and then wire it into router HTTP routes if
   `groli/app` needs a network endpoint instead of stdio.
8. Add resource support only after tool calls are stable and access-control
   rules are documented.

## Open Decisions for groli/app

- Whether `groli/app` needs to run as an MCP server over stdio, expose an HTTP
  MCP endpoint, or support both.
- Which application actions should become tools, and which should remain
  private WAMP procedures.
- Whether the initial MCP endpoint is local-only or network-accessible.
- What authentication is expected for network-accessible MCP over HTTP.
- Whether `groli/app` needs resources/prompts in the first launch, or only
  tools.

## Verification Expectations

- Run `bin/test-fast` before MCP code changes.
- Keep in-memory MCP protocol tests independent from network transports.
- Add focused stdio adapter tests before adding HTTP.
- Add router-backed HTTP tests only after the standalone server core is green.
- Run `bin/verify` before handoff and watch hosted CI after pushes.
