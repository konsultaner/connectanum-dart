# Exec Plan: MCP Standard Direct Router Happy Path Smoke

Status: complete; hosted CI/log/dry-run evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

Router-hosted MCP direct JSON coverage now proves standard tool methods in
many generic and auth paths, but a few consumer-facing router smoke paths still
used Connectanum-specific aliases or raw procedure methods as the primary happy
path. That makes the public example and generated consumer smoke less useful as
evidence that an application or agent can use standard MCP `tools/list` and
`tools/call` directly against router-provided endpoints.

## Scope

- Move the router-hosted example's main direct JSON tool catalog and tool call
  path to `listToolsDirect` and `callToolDirect`.
- Move the router-hosted example direct error-recovery path to standard direct
  JSON `tools/call` and `tools/list`.
- Move generated consumer smoke generic direct catalog pagination to standard
  `tools/list`.
- Move the generated consumer smoke direct batch primary catalog and tool call
  paths to standard `tools/list` and `tools/call`, while preserving existing
  raw procedure and Connectanum alias compatibility checks.

## Non-Goals

- Removing Connectanum-specific compatibility aliases.
- Changing WAMP meta/pubsub tool names or result shapes.
- Changing Streamable HTTP lifecycle semantics.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Router-hosted example primary direct JSON happy path now uses standard MCP
  tool helpers.
- Generated consumer package smoke primary direct JSON batch and generic
  catalog paths now use standard MCP tool methods.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `dart format packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `git diff --check` passed on 2026-05-13.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `c0ad0de` (`mcp: make router direct smoke standard`) was pushed to
  both configured remotes.
- GitHub `CI` run `25785392079` completed successfully for `c0ad0de` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25785392096` completed successfully
  for `c0ad0de`.
- GitHub `Dart Package Publish Dry Run` run `25785392093` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: branch protection /
  required checks are absent and `.github/workflows/router-image.yml` is not
  yet visible from the default branch through the Actions API. The audit also
  continues to report that the router GHCR package is not visible.

## Decision Log

- Standard direct JSON `tools/list` and `tools/call` are the primary
  application-facing smoke surface. Alias and raw procedure methods remain
  covered as compatibility checks, but they should not be the first proof path.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, WAMP benchmark workflow, package publish dry-run, hosted CI log
scan, and the non-strict deployment-chain audit are clean for `c0ad0de`.
