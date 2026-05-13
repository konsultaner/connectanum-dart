# Exec Plan: MCP Standard Direct Batch Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

Router-hosted MCP now supports standard direct JSON `tools/list` and
`tools/call`, but key consumer-facing smoke paths still used
Connectanum-specific tool aliases for generic direct JSON batches and batch
pub/sub helper calls. That left downstream application readiness dependent on
remembering package-specific method names even when the standard MCP methods
would work lifecycle-free.

## Scope

- Update generated consumer-package smoke coverage so generic direct JSON
  single requests, batches, batch error isolation, and batch pub/sub helper
  calls use standard `tools/list` and `tools/call`.
- Keep Connectanum alias coverage in the dedicated direct tool API smoke.
- Update the router-hosted MCP example smoke to use public direct helpers and
  standard direct JSON batch `tools/call` for pub/sub helpers.
- Preserve Streamable HTTP session invariants for lifecycle-free direct JSON.

## Non-Goals

- Removing Connectanum-specific tool/meta aliases.
- Changing Streamable HTTP lifecycle requirements.
- Changing router-hosted WAMP meta API result shapes.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Generated client-only and router-hosted consumer smoke now exercise standard
  direct JSON `tools/list` and `tools/call` batch paths.
- Router-hosted example smoke now demonstrates standard direct tool calls,
  standard direct tool listing, and standard batch pub/sub tool calls while
  retaining alias and direct WAMP meta coverage.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `dart format packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_client_package_smoke'`
  passed on 2026-05-13.
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "hosts MCP over HTTP using the router internal session"`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `ea53861` (`mcp: cover standard direct batch tools`) was pushed to
  both configured remotes.
- GitHub `CI` run `25781537704` completed successfully for `ea53861` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25781537731` completed successfully
  for `ea53861`.
- GitHub `Dart Package Publish Dry Run` run `25781537746` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI and a clean relevant Dart package publish
  dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: branch protection /
  required checks are absent, `.github/workflows/router-image.yml` is not yet
  visible from the default branch through the Actions API, and the router GHCR
  package is not visible.

## Decision Log

- Moved generic direct JSON smoke coverage to standard MCP `tools/list` and
  `tools/call` because those are the public protocol methods consumer
  applications should be able to use without a Streamable session.
- Left alias coverage in the dedicated direct tool API smoke so compatibility
  remains pinned without making aliases the generic-path example.
- Used `postBatchDirect` in the router-hosted example instead of low-level
  `streamable: false` / `includeSession: false` flags for lifecycle-free batch
  calls.

## Handoff

Implementation is pushed. Focused local checks, full local verification, hosted
CI, WAMP benchmark workflow, package publish dry-run, hosted CI log scan, and
the non-strict deployment-chain audit are clean for `ea53861`.
