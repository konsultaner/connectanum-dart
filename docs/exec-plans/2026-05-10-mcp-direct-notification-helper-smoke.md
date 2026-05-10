# Exec Plan: MCP Direct Notification Helper Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make the public MCP client notification helper usable by downstream
applications for direct JSON-RPC and Streamable HTTP notifications without
private project assumptions or accidental Streamable session mutation.

## Scope

- In scope: public `McpStreamableHttpClient.notification` transport/session
  controls, package-level notification helper coverage, generated client-only
  and consumer package smoke coverage, and neutral project-state handoff notes.
- Out of scope: new MCP notification semantics, non-notification JSON-RPC
  behavior, or release/deployment policy changes.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-direct-notification-helper-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Existing docs-only hosted-evidence updates for the previous notification-only
  batch plan are uncommitted and will be bundled with this implementation.

## Plan

1. Add direct JSON/session/header controls to the public notification helper.
2. Extend fake endpoints and package tests for direct JSON and Streamable single
   notifications that return `202 Accepted` without mutating active session
   state.
3. Extend generated neutral client and consumer package smokes so consumer
   applications can prove the helper works through public package APIs and a
   real router-hosted MCP endpoint.
4. Run focused tests, full local verification, commit, push, and collect hosted
   deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format
  packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-10.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-10 with isolated `TMPDIR`.
- Focused `run_mcp_client_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Commit `7e9226f` (`test: cover mcp direct notifications`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25620848947` completed successfully for `7e9226f` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25620848943` completed
  successfully for `7e9226f`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25620848945` completed successfully
  for `7e9226f`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean CI
  log scan, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose to extend the existing public `notification` helper instead
  of adding a separate direct-notification API so consumers can use the same
  Streamable/direct JSON controls already exposed by `request` and `post`.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
