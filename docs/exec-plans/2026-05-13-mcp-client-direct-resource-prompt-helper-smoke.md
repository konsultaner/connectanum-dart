# Exec Plan: MCP Client Direct Resource Prompt Helper Smoke

Status: complete; hosted CI and deployment-chain evidence clean
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
- Commit `ac55e05` (`mcp: add direct resource prompt helpers`) was pushed to
  both configured remotes.
- GitHub `CI` run `25776927696` completed successfully for `ac55e05` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25776927681` completed successfully
  for `ac55e05`.
- GitHub `Dart Package Publish Dry Run` run `25776927676` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
  is not visible in GitHub Packages.

## Decision Log

- 2026-05-13: Chose this slice because typed direct JSON resources/prompts
  still required callers to know the lower-level `directJson` flag, while
  tools, WAMP helpers, and raw JSON-RPC paths already had named direct helpers.

## Handoff

Implementation is pushed. Focused local checks, generated consumer-package
smoke, full local verification, hosted CI, WAMP benchmark workflow, package
publish dry-run, hosted CI log scan, and the non-strict deployment-chain audit
are clean for `ac55e05`.
