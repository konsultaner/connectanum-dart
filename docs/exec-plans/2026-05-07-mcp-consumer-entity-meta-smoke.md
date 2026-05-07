# Exec Plan: MCP Consumer Entity Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that router-hosted MCP WAMP
registration and subscription entity meta helpers are usable through both
initialized Streamable HTTP and lifecycle-free direct JSON calls.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use only public `McpStreamableHttpClient` WAMP meta helper APIs.
  - Assert `wamp.registration.list`, `lookup`, `match`, and `get` agree on
    the exposed procedure registration ID.
  - Assert `wamp.subscription.list`, `lookup`, `match`, and `get` agree on
    the consumer-created subscription ID.
  - Exercise the assertions through direct JSON, initialized Streamable HTTP,
    and direct JSON after Streamable initialization.
- Out of scope:
  - Router meta API behavior changes.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-entity-meta-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP session meta
  smoke plan.

## Preconditions

- Latest pushed implementation commit `19c7e27` has clean hosted CI evidence.
- Existing docs-only hosted-evidence updates for
  `2026-05-07-mcp-consumer-session-meta-smoke.md` remain uncommitted and
  should be bundled with this implementation commit.
- Pre-change `bin/test-fast` passed on 2026-05-07.

## Plan

1. Extend the generated consumer smoke WAMP meta helpers to assert
   registration list/lookup/match/get consistency.
2. Extend the generated consumer smoke subscription meta helper to assert
   subscription list/lookup/match/get consistency.
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
- Commit `586801e` (`test: cover mcp entity meta smoke`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-07.
- Hosted GitHub `CI` run `25490897809` for `586801e` completed successfully on
  2026-05-07 with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports only known operator-side gaps: branch
  protection is absent, `.github/workflows/router-image.yml` is not
  discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-07: Chose this slice because direct JSON and Streamable HTTP WAMP
  meta access are part of downstream application readiness, and the generated
  consumer smoke already covered session and participant meta helpers but did
  not prove the public registration/subscription entity list helpers in the
  same neutral package.

## Handoff

Complete with local and hosted evidence. Implementation commit `586801e` was
pushed to both remotes. This hosted-evidence docs update is intentionally left
uncommitted until it can be bundled with the next code/config implementation
commit.
