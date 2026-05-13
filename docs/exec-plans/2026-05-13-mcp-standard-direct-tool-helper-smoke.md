# Exec Plan: MCP Standard Direct Tool Helper Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

Consumer application code had named direct helpers for Connectanum-specific
tool/meta calls, resources, prompts, and WAMP helpers, but standard MCP
`ping`, `tools/list`, and `tools/call` direct JSON access still required lower
level request flags or aliases. The generated consumer-package smoke also
exposed that router-hosted direct JSON `tools/list` fell through to the
Streamable lifecycle server and failed before `notifications/initialized`.

## Scope

- Add named standard direct helper wrappers to `McpStreamableHttpClient`:
  `pingDirect`, `listToolsDirect`, and `callToolDirect`.
- Route standard direct JSON `tools/list` and `tools/call` through the router
  direct JSON dispatcher so they remain lifecycle-free.
- Keep existing Streamable and Connectanum-specific helper behavior intact.
- Update focused client, IO export, router integration, and generated
  consumer-package smoke coverage.

## Non-Goals

- Removing the existing `directJson` option from mixed helpers.
- Changing Streamable HTTP lifecycle requirements.
- Changing WAMP meta result shapes or Connectanum-specific direct aliases.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Standard direct MCP client helper wrappers were added.
- Router-hosted direct JSON now handles standard `tools/list` and `tools/call`
  before Streamable initialization.
- Focused client, IO export, router integration, and generated consumer-package
  smoke checks passed locally.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
  on 2026-05-13.
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "hosts MCP over HTTP using the router internal session"`
  passed on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after the router direct JSON fix.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_client_package_smoke'`
  passed on 2026-05-13 after the client-only smoke endpoint was updated for
  standard direct JSON calls.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `e5b965f` (`mcp: add standard direct tool helpers`) was pushed to
  both configured remotes.
- GitHub `CI` run `25779966452` completed successfully for `e5b965f` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25779966513` completed successfully
  for `e5b965f`.
- GitHub `Dart Package Publish Dry Run` run `25779966468` completed
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

- Added named standard direct helpers instead of asking consumer application
  code to remember `streamable: false`, `includeSession: false`, or lower-level
  request helpers.
- Kept direct `tools/list` and `tools/call` inside the router direct dispatcher
  so standard MCP direct JSON behaves like the established direct resources,
  prompts, and Connectanum tool/meta aliases.

## Handoff

Implementation is pushed. Focused local checks, generated consumer-package
smoke, full local verification, hosted CI, WAMP benchmark workflow, package
publish dry-run, hosted CI log scan, and the non-strict deployment-chain audit
are clean for `e5b965f`.
