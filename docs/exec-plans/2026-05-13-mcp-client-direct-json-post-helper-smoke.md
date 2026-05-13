# Exec Plan: MCP Client Direct JSON Post Helper Smoke

Status: implemented; full local verification passed, hosted evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Complete the public direct JSON helper surface for router-hosted MCP by adding
a raw single-message `postDirect` API, then prove neutral consumer-package
smokes can use direct helpers without paired Streamable HTTP lifecycle flags.

## Scope

- Add `McpStreamableHttpClient.postDirect` for raw JSON-RPC messages that must
  use `Accept: application/json` and omit MCP session headers.
- Extend focused client tests so raw direct posts preserve active Streamable
  session state, custom headers, and response-session isolation.
- Update generated consumer-package smoke coverage to prefer
  `requestDirect`, `postDirect`, `postBatchDirect`, and
  `notificationDirect` for direct JSON-RPC paths.
- Keep remaining `streamable: false` usage limited to typed Streamable session
  JSON response checks where no direct lifecycle-free helper is intended.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-client-direct-json-post-helper-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-13.
- Client direct JSON request, notification, and batch helpers are complete and
  hosted-clean at branch checkpoint `09c5ce7`.

## Plan

1. Add `postDirect` on `McpStreamableHttpClient`.
2. Pin lifecycle-free raw post behavior in focused client tests.
3. Switch generated consumer direct JSON-RPC smokes from manual lifecycle flag
   pairs to direct helper calls where the helper surface covers the operation.
4. Run focused checks, full local verification, then push and collect hosted
   evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Hosted CI and deployment-chain evidence pending.

## Decision Log

- 2026-05-13: Chose this slice because generic direct JSON-RPC access had
  helper APIs for typed requests, notifications, and batches, but raw
  single-message direct posts still required consumers to remember
  Streamable HTTP lifecycle flags manually.

## Handoff

Implementation is ready for handoff after local verification. Hosted CI and
deployment-chain evidence are pending.
