# Exec Plan: MCP Consumer Batch Error Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that router-hosted MCP
JSON-RPC batches isolate error responses from neighboring successful entries
for both lifecycle-free direct JSON and initialized Streamable HTTP clients.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use only public consumer-facing `McpStreamableHttpClient.postBatch(...)`
    APIs.
  - Assert mixed batches preserve response-producing entry order, omit
    notifications, return a JSON-RPC error for an unknown tool, and keep the
    successful neighboring entries usable.
  - Assert direct JSON batches remain lifecycle-free and initialized
    Streamable batches keep the session id while advancing the SSE cursor.
- Out of scope:
  - Changing router batch semantics.
  - Changing public client APIs.
  - Adding private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-batch-error-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Existing docs-only hosted-evidence updates for the invalid `Last-Event-ID`
  smoke remain uncommitted and should be bundled with this implementation
  commit.

## Plan

1. Add generated consumer-app direct JSON batch error-isolation assertions.
2. Add generated consumer-app initialized Streamable HTTP batch
   error-isolation assertions.
3. Run focused smoke and formatting checks.
4. Run `bin/verify`, commit implementation plus state updates, push both
   remotes, and inspect hosted CI evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub `CI` run `25478356531` for `b1f805e` completed
  successfully with `Fast Checks` and `Full Verify`, both with zero
  annotations.
- The Dart Package Publish Dry Run workflow did not trigger for `b1f805e`
  because no publish-sensitive paths changed. The latest relevant package
  dry-run remains `25463696541` for `3a0bbf0`, which completed successfully
  and still covers checked-out package inputs.
- The deployment-chain audit
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed against `b1f805e`; the strict variant correctly failed only on the
  known operator-owned gaps: `add-router` branch protection, router image
  workflow visibility from the default branch, and GHCR router package
  visibility.

## Decision Log

- 2026-05-07: Chose this slice because the generated consumer package already
  proved successful JSON-RPC batches and notification omission, but did not
  prove that a consumer application sees a recoverable JSON-RPC error entry in
  mixed direct JSON and Streamable batches without losing neighboring success
  responses or session state.

## Handoff

Complete with hosted CI evidence. Remaining strict audit findings are
operator-owned deployment-chain gaps.
