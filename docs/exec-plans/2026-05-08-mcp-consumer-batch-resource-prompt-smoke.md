# Exec Plan: MCP Consumer Batch Resource/Prompt Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can batch MCP resource and prompt detail operations through both
lifecycle-free direct JSON and Streamable HTTP JSON-RPC paths.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add direct JSON batch coverage for `resources/read`,
    `resources/templates/list`, and `prompts/list`.
  - Add Streamable HTTP batch coverage for the same MCP resource/prompt
    operations.
  - Assert direct JSON batches remain lifecycle-free and do not mutate any
    initialized Streamable session id or SSE cursor.
  - Assert Streamable batches preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the batch
    pub/sub checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-pubsub-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-resource-prompt-smoke.md`

## Preconditions

- Latest pushed implementation commit `5af0f56` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.

## Plan

1. Add direct JSON batch resource/prompt detail coverage to the generated
   consumer smoke.
2. Add equivalent Streamable HTTP batch coverage with session/cursor
   assertions.
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
- `git diff --check` passed on 2026-05-08.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit `f75c16e` (`test: cover mcp batch resource prompts`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25582129000` for `f75c16e` completed successfully on
  2026-05-08 with `Fast Checks` (5m49s) and `Full Verify` (8m34s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI, clean
  hosted CI logs, and a relevant clean Dart package publish dry-run
  (`25485027779`, no publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because single-request resource/prompt access
  and batch pub/sub are covered, but batched `resources/read`,
  `resources/templates/list`, and `prompts/list` detail access remained
  unproven for consumer applications and agents.

## Handoff

Implementation, local verification, hosted CI, and standard deployment-chain
audit evidence are clean for `f75c16e`. Remaining strict audit failures are
operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
