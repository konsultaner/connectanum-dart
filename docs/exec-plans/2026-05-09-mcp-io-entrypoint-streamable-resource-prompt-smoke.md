# Exec Plan: MCP IO Entrypoint Streamable Resource/Prompt Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use the public
Streamable HTTP client for MCP resource and prompt operations without reaching
through private package internals.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The generated external client-only package smoke already covers public
  `postBatch(...)` resource and prompt operations from a generated package.
- The checked-in `connectanum_mcp` IO entrypoint test only proved direct WAMP
  helpers through the public export; it did not yet prove resource/prompt
  helpers, Streamable POST/SSE responses, or direct JSON batches through that
  same package boundary.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Add a fake neutral MCP HTTP endpoint that returns initialized Streamable
  session headers, SSE response events, direct JSON responses, and JSON-RPC
  batch responses.
- Cover public `McpStreamableHttpClient` resource and prompt helpers imported
  through `connectanum_mcp_io.dart`.
- Cover direct JSON resource and prompt calls without session headers while an
  initialized Streamable session remains active.
- Cover direct JSON batch resource/prompt success and JSON-RPC error isolation.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because router-hosted and generated external
  package smokes already prove the runtime behavior, while the checked-in
  `connectanum_mcp` package test still needed a direct public-entrypoint proof
  for resource/prompt Streamable HTTP and lifecycle-free direct JSON batches.

## Handoff

Implementation and full local workspace verification are complete.
Commit/push and hosted CI/deployment-chain evidence remain.
