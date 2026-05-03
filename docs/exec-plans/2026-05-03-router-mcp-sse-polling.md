# Exec Plan: Router MCP SSE Polling

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Close the next router-hosted MCP Streamable HTTP compatibility gap for
consumer applications and MCP clients by supporting session-scoped GET/SSE
polling without weakening route auth or direct JSON compatibility.

## Scope

- Keep MCP hosted by router `type: mcp` HTTP routes.
- Preserve legacy direct JSON-RPC POST clients that do not opt into
  Streamable-HTTP-style session handling.
- Require `MCP-Session-Id` on stateful Streamable HTTP follow-up requests after
  the router has issued one during `initialize`.
- Allow initialized sessions to open a GET `text/event-stream` polling response
  with a priming event ID and retry hint.
- Keep GET/SSE tied to the same route-authenticated MCP endpoint key as POST
  and DELETE.
- Add router integration coverage proving the session requirement and SSE
  polling behavior.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_mcp`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`

## Progress

- 2026-05-03: Started after a clean branch-head deployment-chain audit at
  `041236e` and a passing pre-change `bin/test-fast`.
- 2026-05-03: Implemented session-scoped GET/SSE polling for router-hosted MCP
  endpoints. GET now requires `Accept: text/event-stream` plus a known
  `MCP-Session-Id`, opens a native HTTP response stream, emits a priming SSE
  event with an event ID and retry hint, and keeps POST/DELETE keyed to the
  same route-authenticated endpoint state.
- 2026-05-03: Tightened stateful Streamable HTTP POST semantics. Follow-up
  requests that opt into the `application/json, text/event-stream` contract now
  fail with `400` when they omit `MCP-Session-Id`, while legacy no-session
  direct JSON-RPC POST remains supported.
- 2026-05-03: Focused checks passed:
  `dart analyze packages/connectanum_router packages/connectanum_mcp`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
  `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the implementation and docs
  updates. It included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client/native tests, auth-server
  tests, bench integration tests, full router package tests including the new
  MCP GET/SSE polling regression, zero-copy router checks, and Chrome
  Dart2Wasm WebSocket transport tests.

## Handoff

Complete locally. This is a polling/priming SSE compatibility slice; the next
larger MCP transport feature would be a durable server-to-client outbox with
`Last-Event-ID` replay for true resumable server-initiated messages.
