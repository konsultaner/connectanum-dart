# Exec Plan: MCP Consumer CORS Session Auth Smoke

Status: implementation and local verification complete; hosted evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers receive CORS-readable
Streamable HTTP session/auth failures that preserve active session context and
do not create accidental session state.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes reject missing Streamable session headers and
  invalid `Last-Event-ID` values with readable CORS JSON errors.
- Extend the same smoke so active secure Streamable sessions reject missing or
  invalid bearer tokens on raw POST/GET/DELETE paths while preserving the
  active `MCP-Session-Id`.
- Fix the router MCP route auth wrapper so route-level auth failures include
  the request `MCP-Session-Id` when present.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Initial focused generated consumer smoke caught the missing active-session
  header on secure MCP route auth failures.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after the router/session fix.
- Full local `bin/verify` passed on 2026-05-12.

## Handoff

Implementation and local verification are complete. Push, hosted CI, hosted
log scan, and deployment-chain audit evidence are still pending.
