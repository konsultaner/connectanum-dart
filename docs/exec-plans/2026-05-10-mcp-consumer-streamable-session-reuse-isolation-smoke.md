# Exec Plan: MCP Consumer Streamable Session Reuse Isolation Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Prove from the generated neutral consumer package that router-hosted MCP
Streamable HTTP sessions cannot be reused across bearer principals or route
boundaries, and that rejected stale-session attempts do not invalidate the
original secure session.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The router integration suite already covers cross-principal and cross-route
  Streamable MCP session isolation.
- The generated consumer package smoke exercises auth refresh/revocation and
  active-session rejection paths, but it did not yet prove this reuse-isolation
  behavior through the public package APIs available to consumer applications.

## Scope

- Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
- Add a second ticket-authenticated principal to the generated consumer router
  settings.
- Issue primary and secondary ticket grants through the HTTP auth bridge.
- Open a secure Streamable MCP session with the primary token, then attempt to
  reuse that session id with the secondary bearer token and across the public
  route.
- Assert rejected stale-session attempts return HTTP 404, clear the stale
  client-side session state, and leave the original primary secure session
  usable.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Commit `d86a82b` (`test: cover mcp consumer session reuse isolation`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25613768490` completed successfully for `d86a82b` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25612812164` remains
  clean/relevant for `d86a82b`; it completed successfully at `3f9c761`, and the
  audit confirmed no publish-sensitive package inputs changed in `d86a82b`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose this slice because session isolation is part of the MCP
  auth/session correctness contract, and the next readiness gap was proving it
  from a neutral consumer application rather than only from router-private
  integration tests.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
