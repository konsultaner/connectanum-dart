# Exec Plan: MCP Consumer Challenge Auth Rejection Smoke

Status: complete; local verification clean; hosted evidence pending
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
- Hosted CI/deployment-chain evidence pending after push.

## Decision Log

- 2026-05-10: Chose this slice because MCP auth/session correctness needs a
  consumer-facing proof that failed challenge-method auth attempts are rejected
  safely through the public package API, not only by lower-level router tests.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence are pending.
