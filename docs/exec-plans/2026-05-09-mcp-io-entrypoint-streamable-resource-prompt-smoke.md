# Exec Plan: MCP IO Entrypoint Streamable Resource/Prompt Smoke

Status: complete; hosted CI evidence clean
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
- Commit `92abba9` (`test: cover mcp io streamable resources`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25603294674` completed successfully for `92abba9`
  on 2026-05-09 with `Fast Checks` and `Full Verify` green.
- Hosted `Dart Package Publish Dry Run` run `25603294668` completed
  successfully for `92abba9` on 2026-05-09.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-09: Chose this slice because router-hosted and generated external
  package smokes already prove the runtime behavior, while the checked-in
  `connectanum_mcp` package test still needed a direct public-entrypoint proof
  for resource/prompt Streamable HTTP and lifecycle-free direct JSON batches.

## Handoff

Implementation, full local workspace verification, push, hosted CI evidence,
and required deployment-chain audit evidence are complete. Remaining strict
audit findings are operator-side release controls.
