# Exec Plan: MCP Public Example IO Entrypoint

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-06
Last updated: 2026-05-06

## Goal

Make the runnable public router-hosted MCP example use the same
`package:connectanum_mcp/connectanum_mcp_io.dart` consumer entrypoint that
downstream applications should use for MCP primitives, Streamable HTTP,
direct JSON-RPC helpers, and HTTP auth bridge helpers.

## Scope

- In scope:
  - Router-hosted MCP example imports.
  - MCP package README entrypoint wording tied to the runnable example.
  - Local and hosted verification evidence.
- Out of scope:
  - Public API redesign.
  - Package publishability changes.
  - Router protocol behavior changes.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `packages/connectanum_mcp/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-06-mcp-public-example-io-entrypoint.md`

## Preconditions

- Existing hosted-evidence updates for the prior MCP consumer IO entrypoint
  smoke are docs-only and must be bundled with this implementation commit.
- Pre-change `bin/test-fast` is green.

## Plan

1. Switch the runnable router-hosted MCP example from the lower-level
   `package:connectanum_client/mcp.dart` import to
   `package:connectanum_mcp/connectanum_mcp_io.dart`.
2. Align the MCP README consumer-client wording with that public entrypoint.
3. Run focused example/package checks, `bin/test-fast`, and `bin/verify`; then
   push and collect hosted evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-06.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-06.
- `rg -n "package:connectanum_client/mcp.dart" packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_mcp/README.md`
  returned no matches on 2026-05-06.
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full local `bin/verify` passed on 2026-05-06.
- Pending: hosted GitHub evidence after push.

## Decision Log

- 2026-05-06: Chose this slice because the generated consumer smoke already
  proves the intended IO entrypoint, but the public router-hosted MCP example
  still imported the lower-level client package directly.

## Handoff

- Public example IO entrypoint work is complete locally. Push the implementation
  commit and collect hosted GitHub evidence.
