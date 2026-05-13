# Exec Plan: MCP IO Entrypoint Standard WAMP Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use standard WAMP
session and subscription meta helpers over lifecycle-free direct JSON requests.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Lower-level client tests already cover the broader WAMP meta helper set, but
  the IO package-boundary smoke only proved direct registration matching.
- The previous IO entrypoint slices covered direct WAMP API listing, direct
  Connectanum tool/meta calls, auth/session helpers, Streamable
  resources/prompts, and Streamable pub/sub helpers.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Add public-import coverage for session meta helpers:
  `countWampSessions`, `listWampSessions`, and `getWampSession`.
- Add public-import coverage for subscription meta helpers:
  `matchWampSubscription`, `getWampSubscription`, and
  `countWampSubscriptionSubscribers`.
- Assert that all requests stay lifecycle-free direct JSON `connectanum.tool.call`
  POSTs without `MCP-Session-Id`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `8e9e5c6` (`test: cover mcp io standard wamp meta helpers`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-09.
- GitHub `CI` run `25607975655` completed successfully for `8e9e5c6` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25607975654` completed
  successfully for `8e9e5c6`.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-09: Chose this slice because standard WAMP session/subscription meta
  helpers are important for downstream agent/app diagnostics, and public IO
  entrypoint evidence still lacked that package-boundary proof.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
