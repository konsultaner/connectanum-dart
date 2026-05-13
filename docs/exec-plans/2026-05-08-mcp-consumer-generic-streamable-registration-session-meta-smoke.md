# Exec Plan: MCP Consumer Generic Streamable Registration Session Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use generic Streamable JSON-RPC `tools/call` requests to
inspect router-provided WAMP session and registration meta procedures without
typed helper APIs or private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add generic Streamable JSON-RPC coverage for `wamp.session.get`,
    `wamp.registration.lookup`, `wamp.registration.list`,
    `wamp.registration.get`, `wamp.registration.list_callees`, and
    `wamp.registration.count_callees`.
  - Keep existing generic Streamable `wamp.registration.match` coverage and
    assert it agrees with lookup.
  - Assert each raw meta call preserves the initialized MCP session id and
    advances the Streamable SSE cursor.
  - Assert visible registration metadata stays consumer-facing and does not
    expose service-session callees.
  - Bundle the previous docs-only hosted-evidence state updates from the
    generic Streamable subscription meta checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-subscription-meta-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-registration-session-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `89a97ec` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Extend the active generic Streamable smoke section with raw WAMP session get
   and registration meta tool calls.
2. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
3. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all bin/verify` passed
  on 2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit `3b28363`
  (`test: cover mcp generic streamable registration meta`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25570306015` for `3b28363` completed successfully
  on 2026-05-08 with `Fast Checks` (5m57s) and `Full Verify` (8m39s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side gaps: branch protection
  and required status checks are absent, `.github/workflows/router-image.yml`
  is not discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because generic Streamable JSON-RPC consumer
  smoke already covers API describe, session count/list, registration match,
  resource templates, and subscription meta, while full raw session and
  registration meta coverage is the next downstream application readiness gap
  for agents that discover router MCP surfaces through generic JSON-RPC only.

## Handoff

Implementation, hosted GitHub CI, and the standard deployment-chain audit are
clean. Remaining strict deployment audit findings are release-operations gaps
outside this implementation slice.
