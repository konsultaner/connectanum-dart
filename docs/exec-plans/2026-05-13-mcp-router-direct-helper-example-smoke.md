# Exec Plan: MCP Router Direct Helper Example Smoke

Status: complete; hosted CI/log/dry-run evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The router-hosted MCP public example already proves direct JSON WAMP meta and
pub/sub behavior, but some example paths still use the generic Streamable
helper API with `directJson: true`. Consumer applications should be able to copy
the dedicated direct helper calls directly when they do not want Streamable
HTTP session state.

## Scope

- Move the example's direct WAMP API/topic metadata checks to
  `listWampApiDirect` and `describeWampApiDirect`.
- Move the example's direct pub/sub happy path to
  `subscribeWampTopicDirect`, `publishWampEventDirect`,
  `pollWampEventsDirect`, and `unsubscribeWampTopicDirect`.
- Preserve existing Streamable helper coverage and batch compatibility checks.

## Non-Goals

- Changing MCP route behavior or wire protocol semantics.
- Removing the generic helpers with `directJson: true`.
- Changing generated consumer-package smoke semantics.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Public router-hosted MCP example direct WAMP metadata and pub/sub paths now
  use dedicated direct helper APIs.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `dart format packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `git diff --check` passed on 2026-05-13.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `7d2ad41` (`mcp: use direct helpers in router example`) was pushed
  to both configured remotes.
- GitHub `CI` run `25787514378` completed successfully for `7d2ad41` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25787514395` completed successfully
  for `7d2ad41`.
- GitHub `Dart Package Publish Dry Run` run `25787514440` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: protected release
  branches do not require `Fast Checks` and `Full Verify`, and
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API. The audit also continues to report that the
  router GHCR package is not visible.

## Decision Log

- Public examples should favor dedicated direct helper methods when they are
  demonstrating lifecycle-free direct JSON usage. The generic `directJson: true`
  flag remains supported for callers that need one code path for both modes.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, WAMP benchmark workflow, package publish dry-run, hosted CI log
scan, and the non-strict deployment-chain audit are clean for `7d2ad41`.
