# Exec Plan: MCP Consumer Active Resource Prompt Detail Auth Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated neutral consumer package that active secure
Streamable sessions reject invalidated bearer tokens for standard MCP
resource/prompt detail POSTs, not only catalog/list requests.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Exercise public `McpStreamableHttpClient.readResource`,
    `McpStreamableHttpClient.listResourceTemplates`, and
    `McpStreamableHttpClient.getPrompt` on an already initialized secure
    Streamable client after its bearer token has been rotated or revoked.
  - Assert each active-session Streamable POST is rejected with HTTP 401.
  - Assert the public client clears stale Streamable session id and SSE cursor
    state after each rejected request.
  - Keep the existing direct JSON batch, direct JSON single, Streamable batch,
    notification-only POST, Streamable `tools/list`, Streamable `tools/call`,
    Streamable `resources/list`, Streamable `prompts/list`, GET/SSE, and DELETE
    rejection checks.
  - Bundle existing hosted-evidence docs updates from the previous MCP active
    resource/prompt auth smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-active-resource-prompt-detail-auth-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP active
  resource/prompt auth smoke plan.

## Preconditions

- Latest pushed implementation commit `13c5909` has clean hosted CI evidence.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.

## Plan

1. Add active-session Streamable `resources/read`,
   `resources/templates/list`, and `prompts/get` auth rejection assertions to
   the generated neutral consumer package.
2. Reuse the existing active Streamable rejected-bearer harness so direct JSON
   batch, direct JSON single, Streamable batch, notification-only POST,
   Streamable `tools/list`, Streamable `tools/call`, Streamable
   `resources/list`, Streamable `resources/read`, Streamable
   `resources/templates/list`, Streamable `prompts/list`, Streamable
   `prompts/get`, GET/SSE, and DELETE are covered together.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all` passed on
  2026-05-08.
- Focused generated consumer smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`)
  passed on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Pushed implementation commit `6797337`
  (`test: cover mcp active resource prompt detail auth`) to `origin/add-router`
  and `github/add-router` on 2026-05-08.
- GitHub CI run `25545836377` passed on 2026-05-08: `Fast Checks` passed in
  5m58s and `Full Verify` passed in 8m32s.
- Deployment-chain audit passed with latest clean CI and relevant Dart package
  publish dry-run evidence on 2026-05-08.
- Strict deployment-chain audit still fails only the known operator-owned gaps:
  no branch protection, `.github/workflows/router-image.yml` not discoverable
  from the default branch, and `ghcr.io/konsultaner/connectanum-router` not
  visible.

## Decision Log

- 2026-05-08: Chose this slice because resource reads, resource template
  catalog reads, and prompt execution are standard MCP application-context
  requests with parameters, distinct from resource/prompt catalog listing.

## Handoff

Complete. Implementation passed focused and fast local verification, full local
`bin/verify`, hosted GitHub CI, and the normal deployment-chain audit. Strict
audit remains blocked only on the known operator-owned GitHub deployment gaps.
