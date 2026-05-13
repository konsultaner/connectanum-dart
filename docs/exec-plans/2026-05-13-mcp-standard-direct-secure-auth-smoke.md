# Exec Plan: MCP Standard Direct Secure Auth Smoke

Status: complete; local verification clean, hosted evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

Router-hosted MCP secure-route smokes had broad bearer and session coverage,
but some downstream-facing direct JSON auth checks still proved package-specific
aliases or non-tool methods before the standard MCP `tools/list` and
`tools/call` paths. Consumer applications and agents should be able to rely on
standard direct JSON tool methods for secure endpoints without inheriting
project-specific assumptions.

## Scope

- Make generated consumer-package missing-bearer coverage reject standard direct
  JSON `tools/list`, standard direct JSON `tools/call`, and a standard direct
  JSON batch containing both methods.
- Make generated consumer-package active-session rejected-bearer coverage reject
  standard direct JSON `tools/list`, `tools/call`, and a standard direct JSON
  batch while preserving the existing Streamable session state until a
  Streamable request is rejected.
- Update the public router-hosted MCP example smoke so missing-bearer,
  rotated-token, revoked-token, active-session rejection, and refreshed-grant
  success paths all prove standard direct JSON tool access.
- Keep WAMP meta/pubsub and compatibility alias coverage in their existing
  dedicated smoke paths.

## Non-Goals

- Removing Connectanum-specific compatibility aliases.
- Changing Streamable HTTP lifecycle or session header semantics.
- Changing auth token issuance, refresh, or revocation behavior.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Generated consumer-package secure missing-bearer checks now cover standard
  direct JSON single and batch tool methods.
- Generated consumer-package active rejected-bearer checks now cover standard
  direct JSON single and batch tool methods without losing the active
  Streamable session state.
- Router-hosted example secure auth smokes now demonstrate standard direct JSON
  tool listing, tool calling, and batch tool access for missing, invalidated,
  and refreshed bearer paths.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `dart format packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `git diff --check` passed on 2026-05-13.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.

## Decision Log

- Standard direct JSON `tools/list` and `tools/call` are now the primary
  secure-route auth smoke surface because they are the protocol-level methods
  consumer applications can call without a Streamable session.
- Direct JSON active rejected-bearer checks intentionally preserve
  `sessionId`/`lastEventId`; Streamable rejected-bearer checks still clear them.

## Handoff

Implementation is locally complete. Focused local checks and full local
`bin/verify` are clean; push the implementation and collect hosted evidence.
