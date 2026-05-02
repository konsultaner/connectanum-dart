# Exec Plan: MCP Prompt Support

Status: local_verify_passed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Add transport-independent MCP prompt discovery and retrieval support to
`packages/connectanum_mcp` so downstream applications can expose user-selected
prompt templates alongside existing tools and resources.

## Scope

- In scope:
  - add typed prompt definitions, arguments, messages, and registry pagination
  - advertise the MCP `prompts` capability when prompts are configured
  - implement `prompts/list` and `prompts/get` in `McpServer`
  - extend the stdio example and package docs with one prompt template
  - update the MCP research/state docs with the latest prompt source check
- Out of scope:
  - prompt list-change notifications
  - completions for prompt arguments
  - sampling, elicitation, and task-augmented prompts
  - router-hosted prompt projection from WAMP registrations

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/prompts/prompt.dart`
- `packages/connectanum_mcp/lib/src/protocol/capabilities.dart`
- `packages/connectanum_mcp/lib/src/server/mcp_server.dart`
- `packages/connectanum_mcp/lib/connectanum_mcp.dart`
- `packages/connectanum_mcp/example/stdio_echo_server.dart`
- `packages/connectanum_mcp/test/prompts_test.dart`
- `packages/connectanum_mcp/test/stdio_transport_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/mcp_integration_research.md`
- `docs/project_state.md`

## Preconditions

- No product decision or deployment secret is required.
- The branch is clean on hosted GitHub at `19d554b`.
- Official MCP 2025-11-25 prompt docs and schema were rechecked on
  2026-05-02 before implementation.

## Plan

1. Run the required pre-change fast regression.
2. Add package-local prompt protocol classes and registry pagination.
3. Wire `prompts/list` and `prompts/get` through `McpServer` and stdio tests.
4. Update public MCP docs/state and run focused checks plus full verification.

## Verification

- Passed on 2026-05-02 before code edits: `bin/test-fast`
- Passed on 2026-05-02 after the MCP prompt-support edits:
  `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`,
  `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp/test/prompts_test.dart -r expanded`,
  focused stdio transport test, full MCP package test, and `git diff --check`
- Passed on 2026-05-02 after the MCP prompt-support implementation and docs
  updates: `bin/verify`

## Decision Log

- 2026-05-02: Keep this package-local and transport-neutral. Prompt templates
  are user-selected MCP primitives; automatic projection from WAMP APIs remains
  a separate future product decision.

## Handoff

- Local verification passed. Hosted GitHub CI/package dry-run evidence is still
  pending.
