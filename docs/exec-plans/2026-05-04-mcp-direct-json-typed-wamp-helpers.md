# Exec Plan: MCP Direct JSON Typed WAMP Helpers

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the typed WAMP API, meta, and pub/sub helpers usable against
router-hosted MCP direct JSON endpoints without requiring MCP lifecycle or
session negotiation.

## Scope

In scope:

- Add an explicit `directJson` option to the existing typed
  `McpStreamableHttpClient` WAMP helper extension.
- Route direct JSON helper calls through `connectanum.tool.call` while keeping
  the existing session-aware `tools/call` behavior as the default.
- Prove lifecycle-free direct JSON helper usage in client tests and the real
  router-hosted MCP smoke.

Out of scope:

- Adding a standalone MCP-only server.
- Changing router endpoint ownership, route authentication, or meta API
  visibility semantics.
- Replacing the existing generic direct JSON helpers or session-aware MCP
  helpers.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/wamp_tools.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_mcp/test/io_client_export_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-direct-json-typed-wamp-helpers.md`

## Plan

1. Add fail-first client coverage for typed WAMP helper calls over direct JSON
   without MCP lifecycle.
2. Add `directJson` options to typed WAMP API, pub/sub, and meta helpers.
3. Update the real router-hosted MCP smoke to use representative typed direct
   JSON helpers against public and bearer-authenticated routes.
4. Run focused checks, `bin/test-fast`, full `bin/verify`, then push and gather
   hosted GitHub deployment-chain evidence when needed.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Fail-first focused coverage reproduced the missing typed direct JSON helper
  option:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses typed WAMP helpers through direct JSON without lifecycle"`.
- Focused checks passed after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart analyze packages/connectanum_client packages/connectanum_router`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- An initial post-change `bin/test-fast` hit a local native runtime lock
  collision while another local test child was still holding
  `connectanum_native_runtime.lock`; the focused rerun of the affected bench
  files then passed:
  `dart test test/bench_router_config_test.dart test/wamp_transport_integration_test.dart -r expanded`
  from `packages/connectanum_bench`.
- The clean post-change `bin/test-fast` rerun passed on 2026-05-04.
- Full local `bin/verify` passed on 2026-05-04 after the helper
  implementation; it included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests including the
  updated `packages/connectanum_client/test/mcp` suite, auth-server tests,
  bench integration tests, the full router package tests including the updated
  router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy router
  checks, and Chrome Dart2Wasm WebSocket transport tests.
- Follow-up package-entrypoint smoke coverage now lives in
  `packages/connectanum_mcp/test/io_client_export_test.dart`. It imports only
  `package:connectanum_mcp/connectanum_mcp_io.dart` and proves a downstream IO
  consumer sees MCP tool primitives, `McpStreamableHttpClient`, and typed WAMP
  helper calls routed through `directJson: true` without MCP lifecycle or
  session negotiation. Focused checks passed:
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`
  and `dart analyze packages/connectanum_mcp packages/connectanum_client`.
  Post-change `bin/test-fast` and full local `bin/verify` passed again on
  2026-05-04 with the new smoke included.
- Hosted GitHub evidence for `126d274` is clean: `CI` run `25301180475`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, `Dart Package Publish Dry Run`
  run `25301180495` completed successfully and covers the checked-out head,
  `WAMP Profile Benchmarks` run `25301180479` completed successfully, and
  Native Artifacts dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.
- Hosted GitHub evidence for the follow-up IO entrypoint smoke commit
  `a4e32dd` is clean: `CI` run `25302428144` completed successfully with
  `Fast Checks` and `Full Verify`, the hosted CI log scan found no warning,
  deprecation, skipped-test, reset, connection-noise, panic, or failure
  patterns, and `Dart Package Publish Dry Run` run `25302428154` completed
  successfully and covers the checked-out head. `WAMP Profile Benchmarks` run
  `25301180479` remains clean and relevant because the follow-up changed only
  package smoke coverage and docs, and Native Artifacts dry-run `25192553399`
  remains clean and relevant because no native-release-sensitive paths changed.

## Decision Log

- 2026-05-04: Keep direct JSON support as an explicit option on the existing
  typed WAMP helpers. This preserves backward-compatible MCP session-aware
  defaults while allowing frontend-style JSON clients to use the same typed
  API surface against router-hosted direct JSON endpoints.

## Handoff

Complete. Commits `126d274` and follow-up `a4e32dd` were pushed to both
remotes and the hosted GitHub deployment-chain evidence is clean. Remaining
deployment-chain findings are operator/setup items: protect the branch, promote
`.github/workflows/router-image.yml` through the default branch for Actions API
visibility, and publish the router container package when that release lane is
enabled.
