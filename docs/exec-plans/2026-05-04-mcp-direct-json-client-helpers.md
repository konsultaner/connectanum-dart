# Exec Plan: MCP Direct JSON Client Helpers

Status: local complete; commit/push pending
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make router-hosted MCP direct JSON usable from Dart consumer applications
without requiring the full MCP initialize/initialized lifecycle, while keeping
the router as the only MCP endpoint provider.

## Scope

In scope:

- Add `McpStreamableHttpClient` helpers for `connectanum.tools.list`,
  `connectanum.tool.call`, and dotted direct JSON method calls.
- Keep the helpers JSON-only by default so they do not negotiate or attach an
  MCP Streamable HTTP session ID.
- Prove the helpers with client tests and representative real router-hosted MCP
  smoke coverage for anonymous and bearer-authenticated routes.

Out of scope:

- Adding a standalone MCP-only server.
- Changing router authorization, route-principal, session, or direct JSON
  filtering semantics.
- Replacing the standard MCP `initialize`, `tools/list`, and `tools/call`
  helpers.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-direct-json-client-helpers.md`

## Plan

1. Add fail-first client coverage for lifecycle-free direct JSON helper calls.
2. Implement direct JSON helpers on `McpStreamableHttpClient`.
3. Update real router-hosted MCP smoke coverage to use representative helpers
   against public and authenticated routes.
4. Run focused checks, `bin/test-fast`, full `bin/verify`, then push and gather
   hosted GitHub deployment-chain evidence when needed.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Fail-first focused coverage reproduced the missing helper API:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum direct JSON helpers without MCP lifecycle"`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum direct JSON helpers without MCP lifecycle"`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart analyze packages/connectanum_client packages/connectanum_router`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- Post-change `bin/test-fast` passed on 2026-05-04.
- Full local `bin/verify` passed on 2026-05-04 after the helper
  implementation; it included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests including the updated
  `packages/connectanum_client/test/mcp` suite, auth-server tests, bench
  integration tests, the full router package tests including the updated
  router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy router
  checks, and Chrome Dart2Wasm WebSocket transport tests.

## Decision Log

- 2026-05-04: Keep direct JSON helpers on the existing Streamable HTTP client
  instead of creating a separate client/server type. The router remains the MCP
  endpoint and these helpers are explicit escape hatches for frontend-style JSON
  calls that intentionally skip MCP session negotiation.

## Handoff

Local implementation is complete. Commit, push, and hosted deployment-chain
evidence are pending.
