# Exec Plan: MCP Tool Result Content Blocks

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Make `connectanum_mcp` tool results cover the MCP `ContentBlock` shapes that
downstream clients expect after the resource slice: text with annotations,
image, audio, resource links, and embedded resources.

## Scope

- In scope:
  - add typed Dart content block classes for MCP tool results
  - keep existing `McpToolResult.text(...)` and error helpers compatible
  - add focused server/tool tests for mixed content JSON output
  - update public MCP docs and project state
- Out of scope:
  - prompt message content blocks
  - MCP `_meta` passthrough
  - task-augmented tool calls
  - router-hosted resource projection or resource subscriptions

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/tools/tool.dart`
- `packages/connectanum_mcp/test/tools_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/mcp_integration_research.md`
- `docs/project_state.md`

## Preconditions

- No product decision or deployment secret is required.
- The branch is clean on hosted GitHub at `b22eee1`.
- Official MCP 2025-11-25 schema/tool docs were rechecked on 2026-05-02 for
  the `CallToolResult.content` and `ContentBlock` shapes.

## Plan

1. Run the required pre-change fast regression.
2. Add typed MCP tool-result content blocks and keep existing helpers stable.
3. Add focused serialization and `tools/call` coverage.
4. Update docs/state and run focused checks plus full verification.

## Verification

- Passed on 2026-05-02 before code edits: `bin/test-fast`
- Passed on 2026-05-02 after the MCP tool-result content-block edits:
  `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`,
  `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp/test/tools_test.dart -r expanded`,
  `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
- Passed on 2026-05-02 after the MCP tool-result content-block implementation
  and docs updates: `bin/verify`
- 2026-05-02: Pushed commit `f31b025`
  (`mcp: add tool result content blocks`) to both remotes. Hosted GitHub `CI`
  run `25257170704` passed with `Fast Checks` in 5m43s and `Full Verify` in
  8m8s. Hosted `Dart Package Publish Dry Run` run `25257170706` passed in 18s
  and covers the checked-out head. The clean deployment-chain audit then passed
  against `f31b025`, including hosted CI log scan, fresh package dry-run
  relevance, and native release dry-run relevance.

## Decision Log

- 2026-05-02: Keep this package-local and transport-neutral. Router-hosted
  resource projection remains a separate future slice.

## Handoff

- Completed locally and verified on hosted GitHub CI/package dry-run.
  `connectanum_mcp` now exposes typed tool result content blocks for text
  annotations, image/audio payloads, resource links, and embedded resources.
