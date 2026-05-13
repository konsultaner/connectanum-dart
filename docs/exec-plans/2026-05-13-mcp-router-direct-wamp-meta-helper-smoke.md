# Exec Plan: MCP Router Direct WAMP Meta Helper Smoke

Status: complete; hosted CI/log/dry-run evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The router-hosted MCP public example proves direct WAMP session,
registration, and subscription metadata through raw JSON-RPC batch calls, but
it does not yet demonstrate the dedicated direct WAMP meta helper methods
against the real router-hosted endpoint. Consumer applications should be able
to copy those helper calls without relying on private project assumptions or
Streamable HTTP session state.

## Scope

- Add router-hosted smoke coverage that calls dedicated direct WAMP session,
  registration, and subscription meta helper APIs.
- Assert those calls remain lifecycle-free and do not mutate the active
  Streamable HTTP session id or SSE cursor.
- Preserve raw direct JSON-RPC batch WAMP meta coverage for envelope and batch
  isolation behavior.

## Non-Goals

- Changing MCP wire protocol behavior.
- Removing generic WAMP meta or raw batch coverage.
- Changing generated consumer-package smoke semantics.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Public router-hosted MCP example direct WAMP
  session/registration/subscription meta helper smoke is implemented while raw
  batch metadata coverage remains in place.

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
- Commit `ee009e1`
  (`mcp: smoke direct wamp meta helpers in router example`) was pushed to both
  configured remotes.
- GitHub `CI` run `25792246559` completed successfully for `ee009e1` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25792246590` completed successfully
  for `ee009e1`.
- GitHub `Dart Package Publish Dry Run` run `25792246592` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: protected release
  branches do not require `Fast Checks` and `Full Verify`,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and the router GHCR package is not visible.

## Decision Log

- Public examples should prefer dedicated direct helper APIs for copy-paste
  lifecycle-free direct JSON usage, while keeping raw JSON-RPC calls where the
  smoke intentionally verifies batch envelopes or error shape.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, WAMP benchmark workflow, package publish dry-run, hosted CI log
scan, and the non-strict deployment-chain audit are clean for `ee009e1`.
