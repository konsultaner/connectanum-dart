# Exec Plan: MCP Client Direct JSON Ping Helper Smoke

Status: complete; local verification clean, hosted evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Make lifecycle-free router-hosted MCP `ping` practical through the public
client helper API, including active Streamable HTTP sessions and
bearer-protected routes.

## Scope

- Add an explicit direct JSON mode to `McpStreamableHttpClient.ping(...)` so
  consumers can probe a router-hosted MCP endpoint without sending or mutating
  Streamable HTTP session state.
- Extend client tests to prove direct JSON `ping` omits `MCP-Session-Id` and
  `Last-Event-ID` while a Streamable session is active.
- Extend the generated neutral consumer package smoke so active Streamable
  sessions can use direct JSON `ping`, and protected routes reject missing or
  invalid bearer credentials for that helper path.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-client-direct-json-ping-helper-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-13.
- Router direct JSON `ping` support is complete and hosted-clean at branch
  checkpoint `e156708`.

## Plan

1. Add a `directJson` option to the public `ping(...)` helper that forces a
   direct JSON POST and suppresses Streamable session headers.
2. Pin the header/session behavior in the client fake-endpoint test.
3. Pin the active-session and protected-route behavior in the generated
   consumer package smoke.
4. Run focused tests, full local verification, then push and watch hosted
   evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed with no file changes after formatting.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Hosted CI and deployment-chain evidence are pending.

## Decision Log

- 2026-05-13: Chose this slice because the router already supports
  lifecycle-free direct JSON `ping`, but the public client helper still lacked
  a direct JSON mode that suppresses active Streamable session headers.

## Handoff

Implementation is complete locally. Focused local checks and full local
verification are clean; hosted deployment-chain evidence remains pending.
