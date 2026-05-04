# Exec Plan: MCP Streamable Meta Helpers

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make router-hosted WAMP meta procedures easier to consume from Dart
applications through the exported Streamable HTTP MCP client, while preserving
the router endpoint as the only MCP server path.

## Scope

In scope:

- Add an exported `McpStreamableHttpClient` helper for standard
  `wamp.*` meta procedure tools exposed by router-hosted MCP routes.
- Return typed access to lossless WAMP `arguments`, `argumentsKeywords`, and
  raw `structuredContent`.
- Keep authorization and session identity delegated to the existing
  Streamable HTTP `tools/call` path.
- Cover registration and subscription meta calls in client tests and the real
  router-hosted MCP smoke.

Out of scope:

- Changing router authorization or WAMP meta filtering semantics.
- Adding a standalone MCP server path.
- Replacing raw `request(...)` or `callTool(...)` escape hatches.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/wamp_tools.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-streamable-meta-helpers.md`

## Plan

1. Add fail-first client coverage for missing Streamable WAMP meta helpers.
2. Implement the exported helper/result API on top of `callTool(...)`.
3. Extend the real router MCP smoke so the helper proves route-session
   visibility and filtering against `/mcp/public`.
4. Run focused checks, `bin/test-fast`, full `bin/verify`, then push and gather
   hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04 before this implementation
  slice.
- Fail-first focused coverage reproduced the missing helper:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP meta procedure helpers"`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP meta procedure helpers"`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart analyze packages/connectanum_client packages/connectanum_router`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- Post-change `bin/test-fast` passed on 2026-05-04.
- Full local `bin/verify` passed on 2026-05-04 after the helper
  implementation; it included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests including the
  updated `packages/connectanum_client/test/mcp` suite, auth-server tests,
  bench integration tests, the full router package tests including the updated
  router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy router
  checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `06c7a5f` is clean: `CI` run `25297227105`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, `Dart Package Publish Dry Run`
  run `25297227117` completed successfully and covers the checked-out head,
  `WAMP Profile Benchmarks` run `25297227103` completed successfully, and
  Native Artifacts dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-04: Keep meta access as a client helper over router-hosted MCP
  `tools/call`. This preserves the user's requirement that the router endpoint
  provides MCP and avoids adding a separate MCP-only server.
- 2026-05-04: Return a generic `McpStreamableWampMetaCallResult` instead of
  per-procedure result classes because WAMP meta procedures intentionally share
  the same lossless `arguments` / `argumentsKeywords` envelope.

## Handoff

Complete. Commit `06c7a5f` was pushed to both remotes and the hosted GitHub
deployment-chain evidence is clean. Remaining deployment-chain findings are
operator/setup items: protect the branch, promote `.github/workflows/router-image.yml`
through the default branch for Actions API visibility, and publish the router
container package when that release lane is enabled.
