# Exec Plan: MCP Consumer Session Meta Smoke

Status: complete locally; hosted CI evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that router-hosted MCP WAMP
session meta helpers are usable and authorization-filtered through both
initialized Streamable HTTP and lifecycle-free direct JSON calls.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use only public `McpStreamableHttpClient` WAMP meta helper APIs.
  - Assert `wamp.session.count`, `list`, and `get` are internally
    consistent and do not expose the service-side WAMP session.
  - Exercise the assertions through both Streamable HTTP and direct JSON.
- Out of scope:
  - Router meta API behavior changes.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-session-meta-smoke.md`
- `docs/exec-plans/2026-05-07-mcp-client-auth-error-session-clear.md`

## Preconditions

- Latest pushed implementation commit `951ed89` has clean hosted CI evidence.
- Existing docs-only hosted-evidence updates for
  `2026-05-07-mcp-client-auth-error-session-clear.md` remain uncommitted and
  should be bundled with this implementation commit.
- Pre-change `bin/test-fast` passed on 2026-05-07.

## Plan

1. Extend the generated consumer smoke WAMP meta discovery helper to call
   session count/list/get through the public client helper API.
2. Assert visible session count matches visible session IDs, visible sessions
   are non-empty, and the service-side WAMP session is not leaked.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify`.
4. Commit implementation plus state updates, push both remotes, and inspect
   hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all` and
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted CI evidence is pending until this implementation is committed and
  pushed.

## Decision Log

- 2026-05-07: Chose this slice because direct JSON and Streamable HTTP WAMP
  meta access are part of downstream application readiness, and the generated
  consumer smoke previously covered participant lists/counts but only checked
  session count shape.

## Handoff

Complete locally. Hosted CI and deployment-chain audit evidence should be
captured after the implementation commit is pushed.
