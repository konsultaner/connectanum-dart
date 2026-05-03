# Exec Plan: MCP Ping Readiness

Status: completed locally; hosted evidence pending
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the router-hosted MCP path and exported Streamable HTTP client respond to
standard MCP `ping` liveness requests so consumer applications and agents can
verify an established MCP session without calling a tool.

## Scope

In scope:

- Add `ping` request handling to the package-local MCP server primitive used by
  stdio and router-hosted MCP.
- Add a small `McpStreamableHttpClient.ping(...)` helper over the existing
  session-aware request path.
- Cover direct server, client, and router-hosted HTTP/Streamable HTTP behavior
  with focused tests.

Out of scope:

- Periodic automatic keepalive scheduling.
- Transport-level SSE keepalive changes.
- New authorization semantics; `ping` is a session liveness check after the
  existing MCP lifecycle has initialized.

## Implementation

- `McpServer` now handles `method: "ping"` after initialization and returns the
  required empty JSON-RPC result object.
- `McpStreamableHttpClient` exposes `ping({id, streamable})`, preserving the
  current negotiated protocol, session id, auth headers, and SSE/JSON response
  behavior.
- Router-native integration coverage now checks both direct HTTP MCP `ping`
  and Streamable HTTP client `ping` against router-hosted MCP routes.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Fail-first focused checks failed as expected before implementation:
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart -r expanded --plain-name "responds to ping requests after initialization"`
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "tracks Streamable HTTP sessions, SSE responses, polling, and auth headers"`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart -r expanded --plain-name "responds to ping requests after initialization"`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "tracks Streamable HTTP sessions, SSE responses, polling, and auth headers"`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`, and
  `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`.
- Full local `bin/verify` passed on 2026-05-04 after the MCP ping
  implementation and project-state updates.

## Decision Log

- 2026-05-04: The current MCP ping utility spec says `ping` is a JSON-RPC
  liveness request and the receiver responds with an empty result object:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/ping
- 2026-05-04: Keep `ping` behind the existing initialized-operation phase for
  now because this server already requires `initialize` plus
  `notifications/initialized` before operation requests, and router-hosted MCP
  session headers are negotiated during initialization.

## Handoff

Local implementation and full verification are complete. Commit, push, and
watch hosted GitHub deployment-chain evidence before treating this as the next
reviewed branch checkpoint.
