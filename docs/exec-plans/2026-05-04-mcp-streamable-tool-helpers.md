# Exec Plan: MCP Streamable Tool Helpers

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the exported Streamable HTTP MCP client easier and safer for consumer
applications to use by providing typed helpers for the standard tool discovery
and invocation flow while preserving the raw JSON-RPC escape hatches.

## Scope

In scope:

- Add typed `McpStreamableHttpClient.listTools(...)` and
  `McpStreamableHttpClient.callTool(...)` helpers.
- Surface JSON-RPC tool-call errors as a typed client exception instead of
  requiring consumers to manually inspect raw response maps.
- Use the helpers in router-hosted MCP smoke coverage for public and protected
  routes.

Out of scope:

- Replacing raw `request(...)`, `post(...)`, or direct JSON meta API access.
- Adding higher-level wrappers for every router-hosted WAMP meta method.
- Changing router auth/session semantics.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-streamable-tool-helpers.md`

## Preconditions

- Router-hosted MCP Streamable HTTP sessions already negotiate
  `MCP-Session-Id`, preserve auth headers, and support POST/SSE responses.
- `package:connectanum_client/mcp.dart` remains the consumer-facing IO MCP
  client entrypoint.

## Plan

1. Add fail-first client coverage for listing tools, calling a tool, and
   surfacing a JSON-RPC tool error through a typed exception.
2. Add the typed helper API on top of the existing session-aware request path.
3. Update router-native MCP smoke coverage to use the helpers against public
   and protected router-hosted MCP routes.
4. Run focused checks, `bin/test-fast`, full `bin/verify`, and hosted GitHub
   evidence after pushing the implementation commit.

## Verification

- Initial fail-first `bin/test-fast` reproduced the missing helper API and the
  in-progress duplicate router smoke patch.
- Focused checks passed after implementation:
  `dart analyze packages/connectanum_client packages/connectanum_router`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`,
  and `git diff --check`.
- `bin/test-fast` passed on 2026-05-04 after the helper implementation and
  router smoke cleanup.
- Full local `bin/verify` passed on 2026-05-04 after the helper implementation
  and project-state updates; it included formatting, Rust native/FFI tests,
  Python package-artifact checks, MCP package tests, client tests including the
  updated `packages/connectanum_client/test/mcp` suite, auth-server tests,
  bench integration tests, the full router package tests including the updated
  router-hosted MCP helper smoke, zero-copy router checks, and Chrome
  Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `bb44ecc` is clean: `CI` run `25293893587`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, `Dart Package Publish Dry Run`
  run `25293893582` completed successfully and covers the checked-out head,
  `WAMP Profile Benchmarks` run `25293893591` completed successfully, and
  Native Artifacts dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-04: Keep typed helpers narrow: standard `tools/list` and
  `tools/call` get ergonomic wrappers, while raw JSON-RPC remains available for
  direct router meta API and future MCP methods.

## Handoff

Complete. Commit `bb44ecc` was pushed to both remotes and the hosted GitHub
deployment-chain evidence is clean. Remaining deployment-chain findings are
operator/setup items: protect the branch, promote `.github/workflows/router-image.yml`
through the default branch for Actions API visibility, and publish the router
container package when that release lane is enabled.
