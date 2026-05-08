# Exec Plan: MCP Consumer Batch Subscription Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can inspect active WAMP subscription metadata through JSON-RPC
batch requests, both through lifecycle-free direct JSON method names and
through Streamable HTTP `tools/call` batches.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add direct JSON batch coverage for WAMP subscription
    lookup/match/list/get/list_subscribers/count_subscribers while a consumer
    pub/sub subscription is active.
  - Add Streamable HTTP batch coverage for the same WAMP subscription metadata
    procedures through `tools/call`.
  - Assert direct batch calls do not mutate any initialized Streamable session
    id or SSE cursor.
  - Assert Streamable batch calls preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the batch
    WAMP session/registration meta checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-wamp-meta-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-subscription-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `3746b94` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.

## Plan

1. Extend direct JSON pub/sub smoke with batch WAMP subscription metadata
   discovery and detail checks.
2. Extend Streamable HTTP pub/sub smoke with equivalent WAMP subscription
   metadata `tools/call` batches.
3. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh` passed on 2026-05-08.
- `git diff --check` passed on 2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit `d43c963` (`test: cover mcp batch subscription meta`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25577673308` for `d43c963` completed successfully
  on 2026-05-08 with `Fast Checks` (6m6s) and `Full Verify` (8m40s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI, clean
  hosted CI logs, and a relevant clean Dart package publish dry-run
  (`25485027779`, no publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side gaps: branch protection
  and required status checks are absent, `.github/workflows/router-image.yml`
  is not discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because single-request direct JSON and
  Streamable calls already proved WAMP subscription metadata, while batch
  clients could still lose active subscription metadata coverage. This closes
  the next pub/sub and direct JSON batch readiness gap for consumer
  applications and agents.

## Handoff

Implementation, hosted GitHub CI, and the standard deployment-chain audit are
clean. Remaining strict deployment audit findings are release-operations gaps
outside this implementation slice.
