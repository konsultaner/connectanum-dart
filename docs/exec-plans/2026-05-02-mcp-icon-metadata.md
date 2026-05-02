# Exec Plan: MCP Icon Metadata

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Add transport-independent MCP icon metadata support to `packages/connectanum_mcp`
so downstream applications can expose display identifiers on server
implementations, tools, prompts, resources, and resource templates without
changing transport behavior.

## Scope

- In scope:
  - add a typed `McpIcon` model for MCP `icons` entries
  - serialize icons from `McpServerInfo`, `McpTool`, `McpPrompt`,
    `McpResource`, and `McpResourceTemplate`
  - validate icon source URI shape, optional MIME type, size strings, and theme
    values
  - add focused package-local serialization and validation coverage
  - update public MCP docs/research/state docs with the latest icon support
- Out of scope:
  - fetching, caching, validating, or rendering icon bytes
  - router-hosted projection of WAMP metadata into MCP icons
  - task-augmented tool execution, `_meta` passthrough, sampling, and
    completions

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/protocol/icons.dart`
- `packages/connectanum_mcp/lib/src/protocol/capabilities.dart`
- `packages/connectanum_mcp/lib/src/tools/tool.dart`
- `packages/connectanum_mcp/lib/src/prompts/prompt.dart`
- `packages/connectanum_mcp/lib/src/resources/resource.dart`
- `packages/connectanum_mcp/lib/connectanum_mcp.dart`
- `packages/connectanum_mcp/test/icons_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/mcp_integration_research.md`
- `docs/project_state.md`

## Preconditions

- No product decision or deployment secret is required.
- The branch is clean on hosted GitHub at `46295d5`.
- Official MCP 2025-11-25 overview, tools, prompts, and resources docs were
  rechecked on 2026-05-02 before implementation.

## Plan

1. Run the required pre-change fast regression.
2. Add the shared MCP icon model and wire it into definition serializers.
3. Add focused package-local icon serialization and validation tests.
4. Update public MCP docs/state and run focused checks plus full verification.

## Verification

- Passed on 2026-05-02 before code edits: `bin/test-fast`
- Focused checks passed on 2026-05-02 after code/docs edits:
  `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`,
  `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp/test/icons_test.dart -r expanded`,
  `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
- Passed on 2026-05-02 after the MCP icon-metadata implementation and docs
  updates: `bin/verify`
- 2026-05-02: Pushed commit `8df2224` (`mcp: add icon metadata`) to both
  remotes. Hosted GitHub `CI` run `25262576057` passed with `Fast Checks` in
  4m50s and `Full Verify` in 8m11s. Hosted `Dart Package Publish Dry Run` run
  `25262576056` passed in 22s and covers the checked-out head. The clean
  deployment-chain audit then passed against `8df2224`, including hosted CI
  log scan, fresh package dry-run coverage, and native release dry-run
  relevance.

## Decision Log

- 2026-05-02: Keep this package-local and transport-neutral. Icon metadata is
  serialized for MCP clients, but Connectanum does not fetch or trust the icon
  bytes.

## Handoff

- Completed locally and verified on hosted GitHub CI/package dry-run. No icon
  fetching/rendering, WAMP metadata projection, `_meta`, sampling, completions,
  or tasks have been added.
