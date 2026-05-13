# Exec Plan: MCP Client Direct WAMP Helper Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

Direct JSON MCP access to router-provided WAMP API, meta, and pub/sub helpers
still required typed helper callers to remember `directJson: true`. That made
consumer application code easier to get wrong than the direct tool, method,
resource, and prompt helper paths.

## Scope

- Add named direct WAMP helper wrappers on
  `McpStreamableConnectanumWampTools` for API discovery, WAMP meta procedures,
  session/registration/subscription convenience helpers, and pub/sub helpers.
- Keep the existing Streamable-capable helper signatures intact so current
  callers can continue selecting direct JSON through `directJson`.
- Update focused MCP client and IO entrypoint tests to prove the direct WAMP
  helper names are exported and lifecycle-free.
- Update the generated consumer-package smoke so a consumer application can use
  the named direct WAMP helpers without project-private assumptions.

## Non-Goals

- Changing router-hosted MCP protocol behavior.
- Changing WAMP meta result shapes.
- Removing the lower-level `directJson` option from the mixed Streamable helper
  surface.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Direct WAMP API/meta/pubsub helper wrappers were added.
- Focused MCP client and IO export tests were updated to use the new direct
  helper names.
- Generated consumer-package smoke direct WAMP sections were updated to use the
  new direct helper names.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/wamp_tools.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
  on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `02449fa` (`mcp: add direct wamp helper wrappers`) was pushed to
  both configured remotes.
- GitHub `CI` run `25778272810` completed successfully for `02449fa` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25778272808` completed successfully
  for `02449fa`.
- GitHub `Dart Package Publish Dry Run` run `25778272819` completed
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

- Chose named `*Direct` wrappers that delegate to the existing helpers with
  `directJson: true`. This preserves the established request encoding and
  session-lifecycle behavior while giving consumer application code an obvious
  direct JSON entrypoint.
- Kept the original `directJson` parameter on the mixed helpers so tests and
  advanced callers can still exercise both Streamable and direct modes through
  one path when that is useful.

## Handoff

Implementation is pushed. Focused local checks, generated consumer-package
smoke, full local verification, hosted CI, WAMP benchmark workflow, package
publish dry-run, hosted CI log scan, and the non-strict deployment-chain audit
are clean for `02449fa`.
