# Exec Plan: MCP Consumer IO Entrypoint Smoke

Status: complete; hosted CI evidence clean
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
- Hosted GitHub evidence for `5d5c18f` is clean:
  - `CI` run `25456751385` completed successfully with `Fast Checks` and
    `Full Verify`.
  - Public check-run annotation audit found zero GitHub annotations for both
    check runs.
  - Standard deployment-chain audit passed; `Dart Package Publish Dry Run`
    run `25454447229` remains clean and relevant because no publish-sensitive
    paths changed since `acb0ed8`.
  - Strict audit failed only on the known operator-owned branch protection,
    default-branch workflow visibility, and GHCR package visibility gaps.

## Decision Log

- 2026-05-06: Chose this slice because the generated smoke already proved
  direct JSON, Streamable HTTP, auth, resources/prompts, WAMP meta, pub/sub,
  and session lifecycle behavior, but its application code still imported the
  lower-level client package directly instead of proving the intended MCP IO
  entrypoint.

## Handoff

- Consumer IO entrypoint smoke is complete with local and hosted evidence.
  Remaining deployment-chain findings are operator-owned.
