# Exec Plan: MCP Streamable Standard Meta Helpers

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the standard router-hosted WAMP meta API easier to consume from Dart
applications through the exported Streamable HTTP MCP client without adding a
standalone MCP server path.

## Scope

In scope:

- Add named helpers for the standard `wamp.session.*`,
  `wamp.registration.*`, and `wamp.subscription.*` meta procedures.
- Keep all helpers delegated to the existing authenticated `tools/call` path
  through `callWampMetaProcedure(...)`.
- Preserve the lossless WAMP result envelope so applications can inspect
  `arguments`, `argumentsKeywords`, and raw structured content.
- Cover the helpers in client tests and use representative helpers in the real
  router-hosted MCP smoke.

Out of scope:

- Changing router authorization, session identity, or meta filtering semantics.
- Adding a standalone MCP-only server.
- Replacing the generic `callWampMetaProcedure(...)` escape hatch.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/wamp_tools.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-streamable-standard-meta-helpers.md`

## Plan

1. Add fail-first client coverage for named standard WAMP meta helpers.
2. Implement the helpers on top of `callWampMetaProcedure(...)`.
3. Update the real router-hosted MCP smoke to use representative registration
   and subscription helpers against the authenticated route/session path.
4. Run focused checks, `bin/test-fast`, full `bin/verify`, then push and gather
   hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04 before this implementation
  slice.
- Fail-first focused coverage reproduced the missing helper API:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses standard WAMP meta convenience helpers"`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses standard WAMP meta convenience helpers"`,
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

- 2026-05-04: Keep these as named helpers over the existing lossless
  `McpStreamableWampMetaCallResult` instead of new per-procedure result
  objects. That removes magic procedure strings and argument-envelope boilerplate
  while preserving the full router/WAMP meta response.

## Handoff

Local implementation is complete and full local verification is clean. Commit,
push, and hosted GitHub evidence are still pending.
