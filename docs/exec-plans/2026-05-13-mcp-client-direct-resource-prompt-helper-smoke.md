# Exec Plan: MCP Client Direct Resource Prompt Helper Smoke

Status: complete; full local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Complete the typed direct JSON helper surface for router-hosted MCP resources
and prompts so a consumer application can use lifecycle-free context/prompt
access without manually pairing Streamable HTTP flags.

## Scope

- Add named `McpStreamableHttpClient` direct helpers for `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, and
  `prompts/get`.
- Prove the helpers use `Accept: application/json`, omit MCP session headers,
  preserve active Streamable HTTP session state, and forward consumer headers.
- Update generated consumer-package smoke coverage to use named direct helpers
  for resource and prompt access.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_mcp/test/io_client_export_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-client-direct-resource-prompt-helper-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-13.
- Raw direct JSON request, notification, post, and batch helpers are complete
  and hosted-clean at branch checkpoint `dbe712e`.

## Plan

1. Add named direct resource and prompt helpers to the client.
2. Switch focused client and IO export tests to exercise those named helpers.
3. Switch generated consumer-package resource/prompt direct smokes to the
   named helper API.
4. Run focused checks, full local verification, then push and collect hosted
   evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Hosted CI and deployment-chain evidence are pending.

## Decision Log

- 2026-05-13: Chose this slice because typed direct JSON resources/prompts
  still required callers to know the lower-level `directJson` flag, while
  tools, WAMP helpers, and raw JSON-RPC paths already had named direct helpers.

## Handoff

Implementation, focused local checks, generated consumer-package smoke, and
full local verification are complete. Hosted evidence is pending.
