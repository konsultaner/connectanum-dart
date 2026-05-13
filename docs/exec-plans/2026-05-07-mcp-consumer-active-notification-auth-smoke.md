# Exec Plan: MCP Consumer Active Notification Auth Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that Streamable MCP
notification-only POSTs made on an already initialized secure session reject an
invalidated bearer token and clear stale Streamable session state.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Exercise `notifications/initialized` on an already initialized secure
    Streamable client after its bearer token has been rotated or revoked.
  - Assert the notification-only Streamable POST is rejected with HTTP 401.
  - Assert the public client clears stale Streamable session id and SSE cursor
    state after the rejected notification.
  - Keep the existing direct JSON batch, direct JSON single, Streamable
    response POST, GET/SSE, and DELETE rejection checks.
  - Bundle existing hosted-evidence docs updates from the previous MCP active
    direct JSON batch auth smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-active-notification-auth-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP active
  direct JSON batch auth smoke plan.

## Preconditions

- Latest pushed implementation commit `59c6103` has clean hosted CI evidence.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.

## Plan

1. Add an active-session Streamable notification auth rejection assertion to
   the generated neutral consumer package.
2. Reuse the existing active Streamable rejected-bearer harness so direct JSON
   batch, direct JSON single, notification-only POST, Streamable response POST,
   GET/SSE, and DELETE are covered together.
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
- Commit `1bcb6c9` (`test: cover mcp active notification auth`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-07.
- Hosted GitHub `CI` run `25517332569` completed successfully on 2026-05-07
  with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports only operator-side gaps: branch
  protection is absent, `.github/workflows/router-image.yml` is not
  discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-07: Chose this slice because lifecycle notifications are a distinct
  Streamable HTTP request shape from JSON-RPC requests that return response
  bodies, and downstream agents commonly send `notifications/initialized`
  during MCP session startup.

## Handoff

Complete. Local and hosted CI evidence are clean; strict deployment audit is
blocked only by known operator-side GitHub settings/package visibility gaps.
