# Exec Plan: MCP Consumer CORS Error Session Smoke

Status: implementation complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove router-hosted MCP browser clients can read auth and header-validation
failures through configured CORS policy, and that rejected Streamable HTTP
requests do not corrupt the active MCP session.

## Scope

- Keep MCP route auth failures in the Dart binding path so route-specific MCP
  CORS policy is available before responding.
- Extend the generated consumer package smoke with raw secure missing-bearer
  CORS checks for direct JSON and Streamable initialize.
- Add raw Streamable HTTP header-error checks for missing `Mcp-Method`,
  mismatched `Mcp-Name`, missing `Mcp-Param-TaskId`, and invalid
  `Mcp-Param-Note`, followed by a valid request proving the session still works.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- Focused pre-fix smoke reproduced missing CORS on secure direct JSON missing
  bearer: native listener-side transport auth returned only
  `WWW-Authenticate`.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after the implementation.
- `dart test packages/connectanum_router/test/http_route_transport_auth_test.dart`
  passed on 2026-05-12.
- `dart analyze packages/connectanum_router` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.

## Handoff

Implementation and local verification are complete. Hosted CI and
deployment-chain evidence are pending until the implementation commit is pushed.
