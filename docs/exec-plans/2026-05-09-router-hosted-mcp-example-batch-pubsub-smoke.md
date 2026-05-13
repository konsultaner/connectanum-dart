# Exec Plan: Router-Hosted MCP Example Batch Pub/Sub Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can batch MCP pub/sub helper calls through both lifecycle-free direct JSON and
initialized Streamable HTTP JSON-RPC paths.

## Scope

- In scope:
  - Extend `packages/connectanum_router/example/router_hosted_mcp.dart`.
  - Add direct JSON batch coverage for
    `connectanum.pubsub.subscribe/publish/poll/unsubscribe`.
  - Add Streamable HTTP batch coverage for the same MCP pub/sub helpers via
    `tools/call`.
  - Mix pub/sub calls with direct tool/meta API discovery calls in the same
    batches.
  - Assert direct JSON batches do not create or mutate Streamable session/SSE
    state.
  - Assert Streamable batches preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the
    router-hosted MCP example batch resource/prompt checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Consumer-specific application references.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-resource-prompt-smoke.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-pubsub-smoke.md`

## Preconditions

- Latest pushed implementation commit `87050c8` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.

## Plan

1. Extend the public router-hosted MCP example with lifecycle-free direct JSON
   batch pub/sub checks.
2. Extend the same example with Streamable HTTP batch pub/sub checks and
   session/SSE cursor assertions.
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
- Commit `7162b1c` (`test: cover mcp example batch pubsub`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25585415804` for `7162b1c` completed successfully on
  2026-05-09 with `Fast Checks` (6m12s) and `Full Verify` (8m32s) green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
  hosted CI logs, and a clean Dart package publish dry-run covering checked-out
  head (`25585415814`).
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-09: Chose this slice because the generated router-hosted consumer
  smoke already covers batched pub/sub access, while the runnable public
  example only used pub/sub helpers one call at a time.

## Handoff

Implementation, local verification, hosted CI, and standard deployment-chain
audit evidence are clean for `7162b1c`. Remaining strict audit failures are
operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
