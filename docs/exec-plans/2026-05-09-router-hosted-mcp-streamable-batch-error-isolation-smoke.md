# Exec Plan: Router-Hosted MCP Streamable Batch Error Isolation Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that router-hosted MCP Streamable HTTP batches preserve JSON-RPC
error-isolation semantics for consumer applications on both public and
bearer-protected router-provided MCP endpoints.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Existing router integration coverage proved successful Streamable HTTP
  batches on `/mcp/public` and `/mcp/secure`.
- The previous router-hosted direct JSON smoke proved mixed success/error
  batches on `/mcp/public`, but the real Streamable HTTP route smoke did not
  yet cover mixed batch error behavior.

## Scope

- Extend `packages/connectanum_router/test/router_integration_native_test.dart`.
- In the existing Streamable HTTP batch route smoke, send a second batch for
  each public and secure client containing a successful `tools/list` request,
  an unknown MCP method request, and a notification-only
  `notifications/initialized` request.
- Assert the Streamable response keeps the successful result, returns the
  `-32601` unknown-method error for the failed request, omits a notification
  response, and preserves the active MCP session id while advancing the SSE
  cursor.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "serves Streamable HTTP batch responses on router MCP routes"`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because Streamable HTTP batch error isolation is
  part of the router-hosted MCP compatibility contract, and the router
  integration test only covered successful Streamable batches while direct JSON
  already covered mixed error batches.

## Handoff

Implementation and full local verification are complete. Commit/push and
hosted CI/deployment-chain evidence remain.
