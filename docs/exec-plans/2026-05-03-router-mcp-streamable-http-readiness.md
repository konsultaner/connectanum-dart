# Exec Plan: Router MCP Streamable HTTP Readiness

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Harden the router-hosted MCP endpoint so MCP clients and browser-fronted
clients can use the router endpoint without a standalone MCP server or shared
anonymous protocol state.

## Scope

- Keep MCP hosted by `HttpRouteActionType.mcp` on the router.
- Validate MCP HTTP ingress for Origin, `Accept`, content type, and protocol
  version headers without weakening route/session-profile authorization.
- Issue per-client `MCP-Session-Id` values for Streamable-HTTP-style
  `initialize` requests and route subsequent calls through that session key.
- Support explicit session termination through HTTP `DELETE`.
- Preserve legacy no-session JSON-RPC `POST` behavior for existing direct JSON
  clients.
- Add native router integration coverage for the new HTTP/session guards.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_mcp`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`

## Progress

- 2026-05-03: Implemented MCP HTTP ingress hardening locally. The router now
  rejects invalid origins, explicit non-JSON `Accept` headers, non-JSON content
  types, unsupported `MCP-Protocol-Version` headers, unknown session IDs, and
  unsupported GET/SSE requests with explicit status/error responses.
- 2026-05-03: Streamable-HTTP-style `initialize` requests that ask for both
  `application/json` and `text/event-stream` now receive `MCP-Session-Id`, and
  subsequent `POST`/`DELETE` requests are keyed by that HTTP session ID in
  addition to the route-authenticated router session.
- 2026-05-03: Focused checks passed before full verification:
  `bin/test-fast`,
  `dart analyze packages/connectanum_router packages/connectanum_mcp`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
  `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the implementation and
  docs updates. The run included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client/native tests, auth-server
  tests, bench integration tests, full router package tests including the new
  MCP Streamable HTTP ingress/session regression, zero-copy router checks, and
  Chrome Dart2Wasm WebSocket transport tests.
- 2026-05-03: Pushed commit `041236e`
  (`mcp: harden router streamable http sessions`) to GitLab and GitHub.
  Hosted GitHub evidence is clean: `CI` run `25278062808`, `WAMP Profile
  Benchmarks` run `25278062809`, and `Dart Package Publish Dry Run` run
  `25278062807` all completed successfully. The strict add-router
  deployment-chain audit passed with a clean CI log scan and the existing
  Native Artifacts dry-run `25192553399` still relevant because no
  native-release-sensitive inputs changed.

## Handoff

This plan is complete. Remaining full MCP Streamable HTTP compatibility work is
GET/SSE stream support and resumable server-to-client event delivery; the
router-hosted request/response path is now guarded and session-keyed.
