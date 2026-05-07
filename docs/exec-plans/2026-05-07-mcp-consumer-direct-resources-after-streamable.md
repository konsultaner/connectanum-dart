# Exec Plan: MCP Consumer Direct Resources After Streamable

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Extend the generated router-hosted consumer package smoke so a consumer
application proves direct JSON resource and prompt helpers remain lifecycle-free
after the same `McpStreamableHttpClient` has initialized a Streamable MCP
session against a real router-hosted endpoint.

## Scope

- In scope:
  - Expand `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Reuse the existing real router-hosted public and bearer-protected MCP
    endpoint smoke.
  - Assert direct JSON resource and prompt helper calls do not mutate the
    active Streamable session id or SSE cursor.
  - Local and hosted verification evidence.
- Out of scope:
  - Router runtime behavior changes.
  - Public API changes.
  - Package publishing policy changes.

## Plan

1. Call the existing direct JSON resource and prompt helper smoke after
   Streamable initialization in the generated consumer package program.
2. Keep the existing direct JSON pre-Streamable no-session assertion on the
   overall direct helper smoke instead of embedding it in the reusable
   resource/prompt helper.
3. Run focused smoke checks, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed on 2026-05-07.
- `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`
  passed on 2026-05-07 after the smoke expansion.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.

## Handoff

- Local verification is clean. Pending commit, push, and hosted evidence.
