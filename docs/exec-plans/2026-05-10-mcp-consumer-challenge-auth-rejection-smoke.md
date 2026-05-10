# Exec Plan: MCP Consumer Challenge Auth Rejection Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Prove from the generated neutral consumer package that invalid WAMP-CRA and
SCRAM credentials fail cleanly through the public HTTP auth client helpers
before a downstream application issues valid grants and uses secure
router-hosted MCP endpoints.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The previous consumer package smoke proved successful WAMP-CRA and SCRAM
  grants against the secure router-hosted MCP direct JSON and Streamable HTTP
  endpoints.
- Lower-level router/auth tests covered rejected WAMP-CRA and SCRAM attempts,
  but the neutral consumer package did not yet prove public API failure
  behavior against a real router-hosted MCP auth bridge.

## Scope

- Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
- Before issuing valid WAMP-CRA and SCRAM grants, try each method with an
  invalid secret through `ConnectanumHttpAuthClient.issueWampCraToken` and
  `ConnectanumHttpAuthClient.issueScramToken`.
- Assert the public client reports `ConnectanumHttpAuthException` with HTTP
  `401 Unauthorized`.
- Assert rejected bridge responses do not include token material.
- Keep the existing valid grant flow and secure MCP direct JSON/Streamable HTTP
  checks after the rejection assertions.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Commit `64ab570` (`test: cover mcp consumer challenge auth rejection`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25615480764` completed successfully for `64ab570` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25612812164` remains
  clean/relevant for `64ab570`; it completed successfully at `3f9c761`, and the
  audit confirmed no publish-sensitive package inputs changed in `64ab570`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose this slice because MCP auth/session correctness needs a
  consumer-facing proof that failed challenge-method auth attempts are rejected
  safely through the public package API, not only by lower-level router tests.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
