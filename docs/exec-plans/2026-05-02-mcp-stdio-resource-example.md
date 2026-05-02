# Exec Plan: MCP Stdio Resource Example

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Make the runnable `connectanum_mcp` stdio example demonstrate the newly
supported MCP resource list/read path, not only the existing tool path, so
downstream app integrations have a minimal local reference for tools plus
read-only context.

## Scope

- In scope:
  - add one static package-local MCP resource to the stdio echo example
  - exercise `resources/list` and `resources/read` through the stdio transport
    regression test
  - update public MCP/example docs with the resource request sequence
- Out of scope:
  - router-hosted resource projection
  - resource subscriptions or list-change notifications
  - prompts, sampling, tasks, or full Streamable HTTP GET/SSE support

## Files Expected To Change

- `packages/connectanum_mcp/example/stdio_echo_server.dart`
- `packages/connectanum_mcp/test/stdio_transport_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/examples.md`
- `docs/project_state.md`

## Preconditions

- No product decision or deployment secret is required.
- The prior MCP resource read support slice is already implemented and locally
  plus hosted verified at commit `da6bb32`.

## Plan

1. Run the required pre-change fast regression.
2. Add the stdio example resource and transport-level regression coverage.
3. Update the public docs and project state.
4. Run focused MCP checks and full `bin/verify` before handoff.

## Verification

- 2026-05-02: Pre-change `bin/test-fast` passed before edits.
- 2026-05-02: Focused checks passed after edits:
  - `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`
  - `dart analyze packages/connectanum_mcp`
  - `dart test packages/connectanum_mcp/test/stdio_transport_test.dart -r expanded`
  - `dart test packages/connectanum_mcp -r expanded`
  - `git diff --check`
- 2026-05-02: Full local `bin/verify` passed after the stdio resource example
  implementation and docs updates.
- 2026-05-02: Pushed commit `b22eee1` (`mcp: add stdio resource example`) to
  both remotes. Hosted GitHub `CI` run `25256013125` passed with `Fast Checks`
  in 5m37s and `Full Verify` in 8m13s. Hosted `Dart Package Publish Dry Run`
  run `25256013131` passed in 19s and covers the checked-out head. The clean
  deployment-chain audit then passed against `b22eee1`, including hosted CI log
  scan, fresh package dry-run relevance, and native release dry-run relevance.

## Decision Log

- 2026-05-02: Kept the resource package-local and static. Router-hosted
  resource projection remains deferred until a downstream application needs a
  network-visible resource catalog.

## Handoff

- Completed locally and verified on hosted GitHub CI/package dry-run. The stdio
  example now demonstrates a package-local MCP resource, and stdio transport
  coverage exercises resource capability advertisement plus `resources/list`
  and `resources/read`.
