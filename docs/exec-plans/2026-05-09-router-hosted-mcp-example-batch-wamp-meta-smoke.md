# Exec Plan: Router-Hosted MCP Example Batch WAMP Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can inspect router-provided WAMP session and registration metadata through
batched lifecycle-free direct JSON and initialized Streamable HTTP JSON-RPC
paths.

## Scope

- In scope:
  - Extend `packages/connectanum_router/example/router_hosted_mcp.dart`.
  - Add direct JSON batch coverage for `wamp.session.count`,
    `wamp.session.list`, `wamp.session.get`, `wamp.registration.lookup`,
    `wamp.registration.match`, `wamp.registration.list`,
    `wamp.registration.get`, `wamp.registration.list_callees`, and
    `wamp.registration.count_callees`.
  - Add initialized Streamable HTTP batch coverage for the same WAMP metadata
    procedures through `tools/call`.
  - Assert direct JSON batches do not create or mutate Streamable session/SSE
    state.
  - Assert Streamable batches preserve the initialized session id while
    advancing the SSE cursor.
  - Bundle the previous docs-only hosted-evidence state updates from the
    router-hosted MCP example direct tool/meta checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Consumer-specific application references.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-direct-tool-meta-smoke.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-wamp-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `7c936c9` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.

## Plan

1. Extend the public router-hosted MCP example with lifecycle-free direct JSON
   WAMP session/registration metadata batch checks.
2. Extend the same example with initialized Streamable HTTP `tools/call` WAMP
   metadata batch checks and session/SSE cursor assertions.
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
- Commit `f34fc86` (`test: cover mcp example batch wamp meta`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25588086156` for `f34fc86` completed successfully on
  2026-05-09 with `Fast Checks` (5m59s) and `Full Verify` (8m20s) green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
  hosted CI logs, and a clean Dart package publish dry-run covering checked-out
  head (`25588086170`).
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-09: Chose this slice because generated consumer-package smoke already
  proves batch WAMP metadata access, while the runnable public example still
  stopped at tool/API metadata and pub/sub helper checks.

## Handoff

Implementation, local verification, hosted CI, and standard deployment-chain
audit evidence are clean for `f34fc86`. Remaining strict audit failures are
operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
