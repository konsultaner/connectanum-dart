# Exec Plan: MCP Streamable WAMP Tool Helpers

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make router-hosted Connectanum WAMP MCP tools easier to consume from Dart
applications by exposing typed helpers over the existing Streamable HTTP client
session path.

## Scope

In scope:

- Add exported `McpStreamableHttpClient` extension helpers for
  `connectanum.api.list`, `connectanum.api.describe`,
  `connectanum.pubsub.publish`, `connectanum.pubsub.subscribe`,
  `connectanum.pubsub.poll`, and `connectanum.pubsub.unsubscribe`.
- Keep auth/session behavior delegated to the existing Streamable HTTP client
  and router-hosted MCP endpoint; do not add a standalone MCP server path.
- Surface tool-level MCP errors from the typed WAMP helpers as a dedicated
  exception while leaving raw `callTool(...)` behavior unchanged.
- Add focused client coverage for API listing/description, pub/sub
  subscribe/publish/poll/unsubscribe, and tool-level authorization errors.

Out of scope:

- Changing router authorization or WAMP meta API filtering semantics.
- Projecting WAMP APIs as MCP resources/prompts.
- Replacing raw JSON-RPC or generic `callTool(...)` escape hatches.

## Files Expected To Change

- `packages/connectanum_client/lib/mcp.dart`
- `packages/connectanum_client/lib/src/mcp/wamp_tools.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-streamable-wamp-tools.md`

## Plan

1. Add fail-first client coverage for the missing WAMP helper API.
2. Implement exported typed helpers on top of `McpStreamableHttpClient.callTool`.
3. Run focused tests/analyzer, `bin/test-fast`, full `bin/verify`, then push
   and collect hosted GitHub deployment-chain evidence.

## Verification

- pre-change `bin/test-fast` passed on 2026-05-04 before this implementation
  slice.
- Fail-first focused test reproduced the missing helper APIs:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP tool helpers for API and pubsub"`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP tool helpers for API and pubsub"`,
  `dart analyze packages/connectanum_client`, and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
- `bin/test-fast` passed on 2026-05-04 after the helper implementation.
- Full local `bin/verify` passed on 2026-05-04 after the helper
  implementation; it included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests including the
  updated `packages/connectanum_client/test/mcp` suite, auth-server tests,
  bench integration tests, the full router package tests including MCP router
  smoke coverage and `remote_auth_integration_test`, zero-copy router checks,
  and Chrome Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `9bace00` is clean: `CI` run `25296034697`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, `Dart Package Publish Dry Run`
  run `25296034699` completed successfully and covers the checked-out head,
  `WAMP Profile Benchmarks` run `25296034701` completed successfully, and
  Native Artifacts dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-04: Keep the new API as consumer-side helper ergonomics over
  existing MCP tools. The router remains the MCP server endpoint and continues
  to enforce route/session authorization.
- 2026-05-04: Typed helpers throw `McpStreamableWampToolException` for
  tool-level `isError` responses. The generic `callTool(...)` helper still
  returns the raw successful MCP tool result so tests and advanced clients can
  inspect tool errors directly.

## Handoff

Complete. Commit `9bace00` was pushed to both remotes and the hosted GitHub
deployment-chain evidence is clean. Remaining deployment-chain findings are
operator/setup items: protect the branch, promote `.github/workflows/router-image.yml`
through the default branch for Actions API visibility, and publish the router
container package when that release lane is enabled.
