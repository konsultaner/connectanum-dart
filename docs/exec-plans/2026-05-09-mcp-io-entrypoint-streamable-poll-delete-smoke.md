# Exec Plan: MCP IO Entrypoint Streamable Poll/Delete Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use the public
Streamable HTTP client for notification polling, cursor resume, and session
deletion without reaching through private package internals.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Lower-level client and generated consumer smokes already cover Streamable
  lifecycle behavior, but the checked-in IO package-boundary smoke did not yet
  prove GET/SSE notification polling or DELETE session cleanup through the same
  public import surface.
- The previous IO entrypoint slices covered direct WAMP API listing, direct
  Connectanum tool/meta calls, auth/session helpers, Streamable
  resources/prompts, Streamable pub/sub helpers, and standard WAMP meta helpers.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Reuse the neutral fake MCP HTTP endpoint for Streamable POST lifecycle calls.
- Add GET/SSE notification polling that emits event ids, an event name, a retry
  hint, and JSON-RPC notifications.
- Add cursor resume coverage through `Last-Event-ID`.
- Add DELETE session cleanup coverage and assert the client clears both the MCP
  session id and SSE cursor.
- Assert POST/GET/DELETE request methods, accept headers, session headers, and
  resume headers through the public IO import.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because Streamable HTTP notification polling and
  session deletion are core downstream application readiness behavior, and the
  public IO entrypoint still needed a direct package-boundary proof for those
  lifecycle operations.

## Handoff

Implementation and full local verification are complete. Commit/push and hosted
CI/deployment-chain evidence remain.
