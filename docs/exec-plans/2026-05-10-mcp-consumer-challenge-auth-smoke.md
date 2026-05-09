# Exec Plan: MCP Consumer Challenge Auth Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Prove from the generated neutral consumer package that a downstream
application can issue WAMP-CRA and SCRAM grants through the public HTTP auth
client helpers, then use those bearer grants against the secure router-hosted
MCP direct JSON and Streamable HTTP endpoints.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The generated consumer package smoke already proved ticket grants, secure MCP
  refresh/revocation, and Streamable session reuse isolation.
- WAMP-CRA and SCRAM bridge behavior was covered by lower-level router/auth
  tests, but not yet by a neutral consumer package using public package APIs
  against a real router-hosted MCP endpoint.

## Scope

- Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
- Configure the generated secure MCP session profile to accept `ticket`,
  `wampcra`, and `scram` auth methods.
- Add WAMP-CRA and SCRAM authenticators with generated smoke credentials.
- Issue challenge-method grants with
  `ConnectanumHttpAuthClient.issueWampCraToken` and
  `ConnectanumHttpAuthClient.issueScramToken`.
- Validate returned grant metadata, including bearer token shape and principal
  auth method/provider fields.
- Use each grant on the secure router-hosted MCP direct JSON tool catalog/call
  path and on an initialized Streamable HTTP tool catalog/call path.
- Delete Streamable sessions after use and keep direct JSON calls lifecycle-free.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Focused `run_mcp_consumer_package_smoke` initially reached the secure WAMP-CRA
  direct MCP call, then failed because the new assertion input did not include
  the wrapped-note argument required by the shared direct payload assertion.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR` after adding the wrapped-note argument to the new direct and
  Streamable challenge-auth tool calls.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Hosted CI/deployment-chain evidence is pending until the implementation is
  committed and pushed.

## Decision Log

- 2026-05-10: Chose this slice because MCP auth/session correctness needs a
  consumer-facing proof that challenge-method HTTP auth grants work with the
  secure router-hosted MCP surface, not only router-private tests.

## Handoff

Implementation and full local verification are complete. Hosted
deployment-chain evidence is pending until the implementation is pushed.
