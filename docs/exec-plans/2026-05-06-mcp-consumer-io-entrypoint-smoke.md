# Exec Plan: MCP Consumer IO Entrypoint Smoke

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-06
Last updated: 2026-05-06

## Goal

Prove that a generated consumer application can use the public
`package:connectanum_mcp/connectanum_mcp_io.dart` entrypoint for router-hosted
MCP client behavior without importing or declaring `connectanum_client` as an
application dependency.

## Scope

- In scope:
  - Generated consumer package smoke imports.
  - Generated consumer package direct dependencies.
  - Local verification evidence.
- Out of scope:
  - Public API redesign.
  - Router protocol behavior changes.
  - Documentation-only expansion.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-06-mcp-consumer-io-entrypoint-smoke.md`

## Preconditions

- `bin/test-fast` is green before implementation.
- Existing hosted-evidence project-state edits remain docs-only until bundled
  with this implementation commit.

## Plan

1. Switch the generated consumer package smoke application code to import
   `package:connectanum_mcp/connectanum_mcp_io.dart` for both MCP primitives
   and the Streamable HTTP/direct JSON client surface.
2. Remove the generated application’s direct `connectanum_client` dependency
   while keeping path overrides and hook user-defines for transitive package
   resolution and native build-hook behavior.
3. Run the generated consumer package smoke, `bin/test-fast`, and `bin/verify`;
   then push and collect hosted evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `bash -n bin/common.sh` passed on 2026-05-06.
- `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'` passed on 2026-05-06.
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full local `bin/verify` passed on 2026-05-06.
- Pending: hosted GitHub evidence after push.

## Decision Log

- 2026-05-06: Chose this slice because the generated smoke already proved
  direct JSON, Streamable HTTP, auth, resources/prompts, WAMP meta, pub/sub,
  and session lifecycle behavior, but its application code still imported the
  lower-level client package directly instead of proving the intended MCP IO
  entrypoint.

## Handoff

- Consumer IO entrypoint smoke is complete locally. Push the implementation
  commit and collect hosted GitHub evidence.
