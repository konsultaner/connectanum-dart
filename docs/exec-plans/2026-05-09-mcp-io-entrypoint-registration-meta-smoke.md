# Exec Plan: MCP IO Entrypoint Registration Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use direct JSON WAMP
registration meta helpers without reaching through private package internals.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Previous IO standard WAMP meta smoke covered session and subscription helpers,
  but the package boundary still lacked direct registration list, lookup, get,
  and callee helper proof.
- Lower-level client tests already covered standard registration helpers; this
  slice pins neutral public IO entrypoint usage.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Add public-import coverage for `listWampRegistrations`,
  `lookupWampRegistration`, `matchWampRegistration`, `getWampRegistration`,
  `listWampRegistrationCallees`, and `countWampRegistrationCallees`.
- Extend the neutral `_DirectWampEndpoint` fake endpoint with registration meta
  responses.
- Assert lifecycle-free direct JSON `connectanum.tool.call` POSTs with JSON
  accept headers and no `MCP-Session-Id`.
- Assert helper tool names and direct meta argument shapes for lookup, get, and
  callee-count.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `f4bb186` (`test: cover mcp io registration meta helpers`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-09.
- GitHub `CI` run `25609860610` completed successfully for `f4bb186` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25609860588` completed
  successfully for `f4bb186`.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-09: Chose this slice because direct JSON WAMP registration metadata is
  part of the MCP downstream diagnostics surface, and only session/subscription
  registration matching had package-boundary proof.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
