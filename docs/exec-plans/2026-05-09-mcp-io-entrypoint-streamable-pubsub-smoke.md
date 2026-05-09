# Exec Plan: MCP IO Entrypoint Streamable Pub/Sub Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use the public
Streamable HTTP client for WAMP-backed MCP pub/sub helpers without reaching
through private package internals.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The generated external client-only package smoke already covers public
  pub/sub helpers and direct JSON batches from a generated package.
- The checked-in `connectanum_mcp` IO entrypoint test proved direct WAMP helper
  exports plus Streamable resource/prompt helpers, but it did not yet prove
  Streamable pub/sub helper usage through the same package boundary.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Reuse a neutral fake MCP HTTP endpoint that returns initialized Streamable
  session headers, SSE response events, direct JSON responses, and JSON-RPC
  batch responses.
- Cover public `subscribeWampTopic`, `publishWampEvent`, `pollWampEvents`, and
  `unsubscribeWampTopic` helpers imported through `connectanum_mcp_io.dart`.
- Cover direct JSON pub/sub helper calls without session headers while an
  initialized Streamable session remains active.
- Cover lifecycle-free direct JSON batch pub/sub tool calls with neighboring
  success entries and a recoverable tool-level missing-subscription result.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because package-boundary IO coverage had
  already reached resources/prompts, while pub/sub helpers still relied on
  lower-level client-package tests and generated consumer smokes.

## Handoff

Implementation and full local verification are complete. Commit/push and hosted
CI/deployment-chain evidence remain.
