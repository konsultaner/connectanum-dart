# Exec Plan: Router-Hosted MCP Example Batch Resource/Prompt Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can batch MCP resource and prompt operations through both lifecycle-free direct
JSON and initialized Streamable HTTP JSON-RPC paths.

## Scope

- In scope:
  - Extend `packages/connectanum_router/example/router_hosted_mcp.dart`.
  - Add direct JSON batch coverage for `resources/read`,
    `resources/templates/list`, and `prompts/list`.
  - Add Streamable HTTP batch coverage for the same MCP resource/prompt
    operations.
  - Assert direct JSON batches do not create or mutate Streamable session/SSE
    state.
  - Assert Streamable batches preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the
    generated consumer batch resource/prompt checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-batch-resource-prompt-smoke.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-resource-prompt-smoke.md`

## Preconditions

- Latest pushed implementation commit `f75c16e` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.

## Plan

1. Extend the public router-hosted MCP example with direct JSON batch
   resource/prompt checks.
2. Extend the same example with Streamable HTTP batch resource/prompt checks
   and session/SSE cursor assertions.
3. Run focused example smoke, post-change `bin/test-fast`, and full
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke
  (`source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke`)
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- `git diff --check` passed on 2026-05-09.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `87050c8` (`test: cover mcp example batch resources`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25583860224` for `87050c8` completed successfully on
  2026-05-09 with `Fast Checks` (6m09s) and `Full Verify` (8m40s) green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
  hosted CI logs, and a clean Dart package publish dry-run covering checked-out
  head (`25583860221`).
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-09: Chose this slice because the generated router-hosted consumer
  smoke already covers batched resource/prompt access, while the runnable
  public example only batched Streamable tool operations.

## Handoff

Implementation, local verification, hosted CI, and standard deployment-chain
audit evidence are clean for `87050c8`. Remaining strict audit failures are
operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
