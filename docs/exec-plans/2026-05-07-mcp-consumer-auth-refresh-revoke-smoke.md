# Exec Plan: MCP Consumer Auth Refresh/Revoke Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Extend the generated router-hosted consumer package smoke so a consumer
application proves the public HTTP auth helper can refresh, rotate, and revoke
credentials against a real router-hosted MCP endpoint without relying on
workspace-private assumptions.

## Scope

- In scope:
  - Expand `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use `ConnectanumHttpAuthClient` from the public MCP entrypoint against the
    generated router auth route.
  - Prove refresh rotation invalidates the initial access and refresh tokens.
  - Prove refreshed credentials work with both direct JSON helpers and
    Streamable MCP before revocation.
  - Prove revocation invalidates refreshed access and refresh tokens.
  - Local and hosted verification evidence.
- Out of scope:
  - Router auth bridge behavior changes.
  - Public API changes.
  - Package publishing policy changes.

## Plan

1. Enable refresh-token rotation in the generated consumer auth route.
2. Keep the existing initial secure MCP direct JSON and Streamable smoke using
   the first ticket grant.
3. Refresh the grant through `ConnectanumHttpAuthClient`, assert stale access
   and refresh credentials are rejected, then smoke the secure MCP route with
   the refreshed bearer.
4. Revoke the refreshed grant and assert both access and refresh credentials
   are rejected.
5. Run focused smoke checks, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed on 2026-05-07.
- `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`
  passed on 2026-05-07 after the auth refresh/revoke smoke expansion.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted evidence is pending.

## Handoff

- Implementation and local verification are clean. Hosted CI/deployment-chain
  evidence is pending after push.
