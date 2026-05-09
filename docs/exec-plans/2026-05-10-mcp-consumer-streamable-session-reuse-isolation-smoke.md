# Exec Plan: MCP Consumer Streamable Session Reuse Isolation Smoke

Status: complete; local verification clean; hosted evidence pending
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

## Decision Log

- 2026-05-10: Chose this slice because session isolation is part of the MCP
  auth/session correctness contract, and the next readiness gap was proving it
  from a neutral consumer application rather than only from router-private
  integration tests.

## Handoff

Implementation and local verification are complete. Commit/push and hosted
CI/deployment-chain evidence remain.
