# Exec Plan: MCP Streamable Discovery Helpers

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the exported Streamable HTTP MCP client cover the standard resource,
resource-template, and prompt discovery/read flows so consumer applications can
use compatible MCP endpoints without hand-building those JSON-RPC messages.

## Scope

In scope:

- Add typed `McpStreamableHttpClient.listResources(...)`,
  `readResource(...)`, `listResourceTemplates(...)`, `listPrompts(...)`, and
  `getPrompt(...)` helpers.
- Reuse the existing session-aware request path and typed JSON-RPC error
  handling.
- Add focused client tests for successful resource/prompt calls and a JSON-RPC
  prompt error.

Out of scope:

- Changing router-hosted WAMP tool/meta API behavior.
- Adding resource or prompt projection to router-hosted WAMP endpoints.
- Replacing raw JSON-RPC access for future or custom MCP methods.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-streamable-discovery-helpers.md`

## Plan

1. Add fail-first Streamable HTTP client coverage for resources, resource
   templates, prompts, and JSON-RPC prompt errors.
2. Implement the helpers on top of the existing `request(...)` path.
3. Run focused tests/analyzer, `bin/test-fast`, full `bin/verify`, then push
   and collect hosted GitHub deployment-chain evidence.

## Verification

- pre-change `bin/test-fast` passed on 2026-05-04 before this implementation
  slice.
- Fail-first focused test reproduced the missing client helper APIs:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
  and `dart analyze packages/connectanum_client`.
- `bin/test-fast` passed on 2026-05-04 after the helper implementation.
- Full local `bin/verify` passed on 2026-05-04 after the helper
  implementation and project-state updates; it included formatting,
  Rust native/FFI tests, Python package-artifact checks, MCP package tests,
  client tests including the updated `packages/connectanum_client/test/mcp`
  suite, auth-server tests, bench integration tests, the full router package
  tests including MCP router smoke coverage and `remote_auth_integration_test`,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `87226f0` is clean: `CI` run `25294812273`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, `Dart Package Publish Dry Run`
  run `25294812274` completed successfully and covers the checked-out head,
  `WAMP Profile Benchmarks` run `25294812276` completed successfully, and
  Native Artifacts dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-04: Keep the helpers standard-MCP only. Router-hosted WAMP access
  remains exposed through `tools/list` and `tools/call`; resource and prompt
  helpers are generic Streamable HTTP client ergonomics for compatible MCP
  endpoints.

## Handoff

Complete. Commit `87226f0` was pushed to both remotes and the hosted GitHub
deployment-chain evidence is clean. Remaining deployment-chain findings are
operator/setup items: protect the branch, promote `.github/workflows/router-image.yml`
through the default branch for Actions API visibility, and publish the router
container package when that release lane is enabled.
