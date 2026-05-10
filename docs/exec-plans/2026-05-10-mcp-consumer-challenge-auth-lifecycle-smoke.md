# Exec Plan: MCP Consumer Challenge Auth Lifecycle Smoke

Status: complete; hosted CI evidence clean
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
- Commit `5a4249a` (`test: cover mcp consumer challenge auth lifecycle`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25616322616` completed successfully for `5a4249a` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25612812164` remains
  clean/relevant for `5a4249a`; it completed successfully at `3f9c761`, and the
  audit confirmed no publish-sensitive package inputs changed in `5a4249a`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose this slice because MCP auth/session correctness needs a
  consumer-facing proof that challenge-method grants can be refreshed and
  revoked safely, not only issued or rejected.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
