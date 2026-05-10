# Exec Plan: MCP Consumer Challenge Auth Lifecycle Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Prove from the generated neutral consumer package that WAMP-CRA and SCRAM
HTTP auth bridge grants support the same public refresh/revoke lifecycle as
ticket grants before a downstream application relies on those grants for secure
router-hosted MCP direct JSON and Streamable HTTP access.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Previous consumer package smoke coverage proved ticket refresh/revocation,
  successful WAMP-CRA/SCRAM grants, and clean WAMP-CRA/SCRAM rejection.
- The neutral consumer package did not yet prove that challenge-method grants
  can be refreshed, rotated, revoked, and then rejected after revocation through
  the public package API against a real router-hosted MCP endpoint.

## Scope

- Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
- Reuse the secure MCP refresh/revocation smoke for ticket, WAMP-CRA, and
  SCRAM grants.
- Assert refreshed grants preserve principal realm/auth metadata and include
  complete bearer/refresh token material.
- Assert refresh rotation invalidates the old active Streamable MCP session,
  old direct bearer token, and old refresh token.
- Assert revoked rotated refresh tokens invalidate active Streamable sessions,
  direct bearer access, and later refresh attempts.
- Keep the existing direct JSON and Streamable HTTP secure MCP checks for each
  refreshed grant.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Initial focused `run_mcp_consumer_package_smoke` failed at generated Dart
  analysis because the new named-parameter signature omitted the closing `}`.
- `bash -n bin/common.sh` passed on 2026-05-10 after fixing the embedded Dart
  signature.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Hosted CI/deployment-chain evidence pending after push.

## Decision Log

- 2026-05-10: Chose this slice because MCP auth/session correctness needs a
  consumer-facing proof that challenge-method grants can be refreshed and
  revoked safely, not only issued or rejected.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence are pending.
