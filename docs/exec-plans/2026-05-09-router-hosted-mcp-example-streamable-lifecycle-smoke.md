# Exec Plan: Router-Hosted MCP Example Streamable Lifecycle Smoke

Status: complete; local verification clean
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

## Decision Log

- Keep this in the runnable public example because GET/SSE notification and
  resume semantics are endpoint-level integration behavior, not only a package
  helper contract.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
deployment-chain evidence are pending.
