# Exec Plan: MCP Notification-Only Batch Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Prove that router-hosted MCP clients can send JSON-RPC notification-only
batches over direct JSON and Streamable HTTP without receiving JSON-RPC
responses or mutating active Streamable session state.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Existing package and generated consumer smokes cover mixed request plus
  notification batches.
- JSON-RPC notification-only batches should resolve to accepted/no-content
  transport behavior because there are no request IDs that can produce
  JSON-RPC responses.

## Scope

- Align fake MCP smoke endpoints with router behavior by returning `202
  Accepted` for notification-only batches.
- Add package-level `McpStreamableHttpClient` coverage for direct JSON and
  Streamable HTTP notification-only batches while an MCP session is active.
- Extend generated neutral client-package and consumer-package smokes so both
  public package use and real router-hosted MCP endpoints pin the no-response
  behavior.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-10.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-10.
- Focused `run_mcp_client_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.

## Decision Log

- 2026-05-10: Chose this slice because direct JSON and Streamable HTTP batch
  compatibility are consumer-facing MCP integration details for agents that
  may send fire-and-forget notification batches.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence are pending.
