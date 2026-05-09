# Exec Plan: Router-Hosted MCP Example Streamable Lifecycle Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove the Streamable HTTP session
lifecycle contract a consumer application needs: GET/SSE server notifications,
resume cursors, invalid `Last-Event-ID` rejection without session loss, DELETE
cleanup, stale-session 404 clearing, and reinitialization.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The generated consumer package smoke already proves this lifecycle behavior
  against a router-hosted MCP endpoint.
- The public example has broad direct JSON, WAMP/meta, resource/prompt, auth,
  and pub/sub coverage, but it did not yet prove the GET/SSE lifecycle behavior
  directly in the runnable example.

## Scope

- Add a Streamable lifecycle smoke helper to
  `packages/connectanum_router/example/router_hosted_mcp.dart`.
- Trigger `notifications/tools/list_changed` by registering a dynamic WAMP
  procedure after MCP initialization.
- Poll GET/SSE, assert the event cursor advances, assert resume does not replay
  the consumed event, and assert malformed resume cursors return `400` without
  clearing the active session.
- DELETE the session, assert local client state clears, assert a stale session
  receives `404` and clears local state, then reinitialize and delete again.
- Run the helper for both public and bearer-protected MCP example endpoints.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke passed on 2026-05-09 with isolated
  `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `2563553` (`test: cover mcp streamable lifecycle example`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25597333837` for `2563553` completed successfully on
  2026-05-09 with `Fast Checks` (4m17s) and `Full Verify` (5m57s) green.
- Hosted GitHub `WAMP Profile Benchmarks` run `25597333824` for `2563553`
  completed successfully on 2026-05-09 with `Linux WAMP profile gates` (7m18s)
  green.
- Hosted GitHub `Dart Package Publish Dry Run` run `25597333839` for
  `2563553` completed successfully on 2026-05-09 with `Publish Dry Run` green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep this in the runnable public example because GET/SSE notification and
  resume semantics are endpoint-level integration behavior, not only a package
  helper contract.

## Handoff

Implementation, local verification, push, and hosted deployment-chain evidence
are complete. Remaining strict-audit findings are operator-side release gaps
outside this MCP Streamable lifecycle smoke slice.
