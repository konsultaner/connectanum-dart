# Exec Plan: MCP Consumer Active Direct JSON Batch Auth Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that lifecycle-free direct
JSON batch tool/meta API calls made on an already initialized secure Streamable
MCP client reject invalid bearer tokens and clear stale Streamable session
state.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Exercise a direct JSON batch containing `connectanum.api.list` on an
    initialized secure Streamable client after its bearer token has been
    rotated or revoked.
  - Assert the direct JSON batch is rejected with HTTP 401 before any JSON-RPC
    response body is accepted.
  - Assert the public client clears stale Streamable session id and SSE cursor
    state after the direct JSON batch auth rejection.
  - Keep the existing direct JSON single request plus Streamable POST, GET/SSE,
    and DELETE rejection checks.
  - Bundle existing hosted-evidence docs updates from the previous MCP active
    direct JSON auth smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-active-direct-json-batch-auth-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP active
  direct JSON auth smoke plan.

## Preconditions

- Latest pushed implementation commit `6b48a82` has clean hosted CI evidence.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.

## Plan

1. Add an active-session direct JSON batch auth rejection assertion to the
   generated neutral consumer package.
2. Reuse the existing active Streamable rejected-bearer harness so direct JSON
   batch, direct JSON single, Streamable POST, GET/SSE, and DELETE are covered
   together.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed.
- `git diff --check` passed.
- Focused `run_mcp_consumer_package_smoke` passed with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed with isolated `TMPDIR`.
- Full local `bin/verify` passed with isolated `TMPDIR`.
- Commit `59c6103` (`test: cover mcp active direct json batch auth`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-07.
- Hosted GitHub `CI` run `25514845144` completed successfully on 2026-05-07
  with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports only operator-side gaps: branch
  protection is absent, `.github/workflows/router-image.yml` is not
  discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-07: Chose this slice because active secure Streamable sessions now
  prove invalidated bearer rejection for direct JSON single requests and
  Streamable request shapes, while direct JSON batches are also part of the
  consumer-facing tool/meta API surface.

## Handoff

Complete. Local and hosted CI evidence are clean; strict deployment audit is
blocked only by known operator-side GitHub settings/package visibility gaps.
