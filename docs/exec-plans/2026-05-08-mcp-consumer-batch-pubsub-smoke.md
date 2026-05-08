# Exec Plan: MCP Consumer Batch Pub/Sub Smoke

Status: complete; local verification clean; hosted CI pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use WAMP pub/sub helper operations inside JSON-RPC batches,
both through lifecycle-free direct JSON method names and through Streamable
HTTP `tools/call` batches.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add direct JSON batch coverage for
    `connectanum.pubsub.subscribe/publish/poll/unsubscribe`.
  - Add Streamable HTTP batch coverage for the same helper operations through
    `tools/call`.
  - Use a distinct declared smoke topic for temporary batch
    subscribe/unsubscribe checks so the active task-event subscription remains
    valid for downstream poll checks.
  - Assert direct batch calls do not mutate any initialized Streamable session
    id or SSE cursor.
  - Assert Streamable batch calls preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the batch
    subscription metadata checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-subscription-meta-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-pubsub-smoke.md`

## Preconditions

- Latest pushed implementation commit `d43c963` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.

## Plan

1. Extend the direct JSON pub/sub smoke with batched subscribe, publish, poll,
   and unsubscribe operations plus sibling WAMP API catalog checks.
2. Extend the Streamable HTTP pub/sub smoke with equivalent batched
   `tools/call` operations and SSE cursor assertions.
3. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh` passed on 2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Hosted GitHub CI pending.

## Decision Log

- 2026-05-08: Chose this slice because generic single-request pub/sub and
  batch WAMP metadata were covered, but batched pub/sub helper operations
  remained unproven for consumer applications and agents.
- 2026-05-08: The focused smoke showed that a temporary batch
  subscribe/unsubscribe on the primary task-event topic can invalidate the
  active handle used by the rest of the smoke. The batch subscribe/unsubscribe
  proof now uses a second declared smoke topic while publish/poll delivery
  still uses the primary task-event topic.
- 2026-05-08: Sibling batch WAMP API checks target the declared WAMP
  procedure. The WAMP API catalog is separate from the `connectanum.pubsub.*`
  helper-tool catalog.

## Handoff

Implementation and local verification are clean. Commit, push, and hosted
evidence remain.
