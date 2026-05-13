# Exec Plan: MCP Consumer Direct WAMP Meta Helper Smoke

Status: complete; hosted CI/log/dry-run evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The generated consumer-package router-hosted MCP smoke proves raw direct
JSON-RPC access to WAMP session, registration, and subscription metadata, but
it does not yet prove that a neutral consumer application can use the public
dedicated direct WAMP meta helper APIs against the router-provided MCP
endpoint. That leaves downstream application readiness dependent on example
coverage instead of package-boundary smoke evidence.

## Scope

- Add generated consumer-package smoke coverage for direct WAMP session,
  registration, and subscription meta helper APIs.
- Assert those direct helper calls remain lifecycle-free and do not mutate an
  active Streamable HTTP session id or SSE cursor.
- Keep the existing raw direct JSON-RPC and batch metadata coverage in place.

## Non-Goals

- Changing MCP wire protocol behavior.
- Removing raw JSON-RPC access coverage.
- Changing public package metadata or release automation.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Generated consumer-package router-hosted MCP smoke now calls the dedicated
  direct WAMP session, registration, and subscription meta helper APIs while
  keeping raw generic direct JSON-RPC and batch coverage.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `run_mcp_consumer_package_smoke` passed on 2026-05-13, including generated
  package `dart analyze` and router-hosted MCP runtime smoke.
- `git diff --check` passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `18d3378`
  (`mcp: smoke consumer direct wamp meta helpers`) was pushed to both
  configured remotes.
- GitHub `CI` run `25794202291` completed successfully for `18d3378` with
  `Fast Checks` and `Full Verify` green.
- The `Dart Package Publish Dry Run` workflow did not rerun for `18d3378`
  because the commit did not touch package publish-sensitive paths. The latest
  run `25792246592` at `ee009e1` remains clean and relevant for checked-out
  package inputs.
- The `WAMP Profile Benchmarks` workflow did not rerun for `18d3378` because
  the commit did not touch benchmark-sensitive paths. The latest run
  `25792246590` at `ee009e1` remains green.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: required-check
  branch protection is not ready, `.github/workflows/router-image.yml` is not
  yet visible from the default branch through the Actions API, and the router
  GHCR package is not visible.

## Decision Log

- Generated consumer-package smokes should prove public helper APIs from a
  package-boundary app, while raw direct JSON-RPC coverage remains responsible
  for envelope, batch, and generic JSON-RPC behavior.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, hosted CI log scan, and the non-strict deployment-chain audit are
clean for `18d3378`.
