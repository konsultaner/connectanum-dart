# Exec Plan: MCP Consumer Generic Direct WAMP Meta Smoke

Status: complete locally; hosted CI pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can call router-provided WAMP meta procedures through generic
direct JSON-RPC method names without typed helper APIs, Streamable lifecycle
headers, or private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add generic direct JSON-RPC coverage for `wamp.session.count`,
    `wamp.session.list`, `wamp.session.get`, `wamp.registration.lookup`,
    `wamp.registration.match`, `wamp.registration.list`,
    `wamp.registration.get`, `wamp.registration.list_callees`, and
    `wamp.registration.count_callees`.
  - Add generic direct JSON-RPC coverage for live pub/sub meta through
    `wamp.subscription.lookup`, `wamp.subscription.match`,
    `wamp.subscription.list`, `wamp.subscription.get`,
    `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers`.
  - Assert direct JSON meta calls preserve any initialized Streamable session id
    and SSE cursor and keep service sessions out of visible metadata.
  - Bundle the previous docs-only hosted-evidence state updates from the
    generic Streamable registration/session checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-registration-session-meta-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-direct-wamp-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `3b28363` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Extend the generic direct JSON smoke section with raw WAMP session and
   registration meta method calls.
2. Extend the generic direct JSON pub/sub section with raw WAMP subscription
   meta method calls while a direct subscription is active.
3. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh` and `git diff --check` passed on 2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit/push and hosted GitHub CI evidence are pending.

## Decision Log

- 2026-05-08: Chose this slice because generic Streamable raw WAMP meta and
  typed direct JSON WAMP helper coverage were already clean, while generic
  direct JSON method-name access to router-provided WAMP meta remained the next
  downstream application readiness gap for agents that discover and call MCP
  surfaces without typed helper APIs.

## Handoff

Implementation and full local verification are clean. Commit/push, hosted CI,
and deployment-chain audit evidence are pending.
