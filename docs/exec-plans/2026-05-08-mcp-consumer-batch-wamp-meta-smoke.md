# Exec Plan: MCP Consumer Batch WAMP Meta Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can call router-provided WAMP meta procedures inside JSON-RPC
batch requests, both through lifecycle-free direct JSON method names and
through Streamable HTTP `tools/call` batches.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add direct JSON batch coverage for WAMP session count/list/get and
    registration lookup/match/list/get/list_callees/count_callees.
  - Add Streamable HTTP batch coverage for the same WAMP session and
    registration meta procedures through `tools/call`.
  - Assert direct batch calls do not mutate any initialized Streamable session
    id or SSE cursor.
  - Assert Streamable batch calls preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the
    generic direct WAMP meta checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-direct-wamp-meta-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-wamp-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `ea63e72` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.

## Plan

1. Extend direct JSON batch smoke with WAMP session/registration meta
   discovery and detail batches.
2. Extend Streamable HTTP batch smoke with equivalent WAMP meta `tools/call`
   batches.
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

## Decision Log

- 2026-05-08: Chose this slice because direct JSON and Streamable batches
  already proved normal tool/resource/prompt paths, while WAMP meta coverage
  was only proven through single requests. Batch coverage closes the next
  consumer application readiness gap for agents that coalesce JSON-RPC work.

## Handoff

Implementation and full local verification are clean. Hosted CI and
deployment-chain audit are pending.
