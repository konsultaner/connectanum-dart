# Exec Plan: MCP Consumer Active Resource Prompt Auth Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated neutral consumer package that standard Streamable
`resources/list` and `prompts/list` POSTs made on an already initialized secure
session reject an invalidated bearer token and clear stale Streamable session
state.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Exercise public `McpStreamableHttpClient.listResources` and
    `McpStreamableHttpClient.listPrompts` on an already initialized secure
    Streamable client after its bearer token has been rotated or revoked.
  - Assert each active-session Streamable POST is rejected with HTTP 401.
  - Assert the public client clears stale Streamable session id and SSE cursor
    state after each rejected request.
  - Keep the existing direct JSON batch, direct JSON single, Streamable batch,
    notification-only POST, Streamable `tools/list`, Streamable `tools/call`,
    GET/SSE, and DELETE rejection checks.
  - Bundle existing hosted-evidence docs updates from the previous MCP active
    tool-call auth smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-active-resource-prompt-auth-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP active
  tool-call auth smoke plan.

## Preconditions

- Latest pushed implementation commit `5a37705` has clean hosted CI evidence.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.

## Plan

1. Add active-session Streamable `resources/list` and `prompts/list` auth
   rejection assertions to the generated neutral consumer package.
2. Reuse the existing active Streamable rejected-bearer harness so direct JSON
   batch, direct JSON single, Streamable batch, notification-only POST,
   Streamable `tools/list`, Streamable `tools/call`, Streamable
   `resources/list`, Streamable `prompts/list`, GET/SSE, and DELETE are covered
   together.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused syntax checks passed on 2026-05-08: `bash -n bin/common.sh
  bin/test-fast bin/test-all` and `git diff --check`.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-08 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit `13c5909` (`test: cover mcp active resource prompt auth`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25543715782` completed successfully on 2026-05-08
  with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports only operator-side gaps: branch
  protection is absent, `.github/workflows/router-image.yml` is not
  discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because resources and prompts are standard MCP
  application-context surfaces, distinct from tool catalog, tool invocation,
  batch, notification, poll, and delete request shapes.

## Handoff

Complete. Local and hosted CI evidence are clean; strict deployment audit is
blocked only by known operator-side GitHub settings/package visibility gaps.
