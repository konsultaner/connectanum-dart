# Exec Plan: MCP Active Session Method Auth Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Extend the generated router-hosted consumer package smoke so a consumer
application proves protected active Streamable MCP sessions reject stale or
revoked bearers across POST, GET/SSE polling, and DELETE session requests.

## Scope

- In scope:
  - Expand `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Keep using only public `connectanum_mcp` / `connectanum_router` / MCP
    client APIs from the generated consumer package.
  - Assert an active initial-bearer Streamable MCP session is rejected on POST,
    GET/SSE, and DELETE after refresh rotation.
  - Assert an active refreshed-bearer Streamable MCP session is rejected on
    POST, GET/SSE, and DELETE after revocation.
  - Local and hosted verification evidence.
- Out of scope:
  - Router auth bridge behavior changes.
  - Public API changes.
  - Package publishing policy changes.

## Plan

1. Generalize the active Streamable session rejection helper so it can exercise
   POST `tools/list`, GET/SSE polling, and DELETE session requests.
2. Reuse the existing refresh-rotation and revocation smoke flow against the
   real bearer-protected router MCP endpoint.
3. Run focused smoke checks, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed on 2026-05-07.
- Focused consumer smoke passed on 2026-05-07:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted evidence is pending.

## Handoff

- Implementation and local verification are clean. Hosted CI/deployment-chain
  evidence is pending after push.
