# Exec Plan: MCP Client Package Batch Error Isolation Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated client-only consumer package smoke prove that a downstream
application can use public `McpStreamableHttpClient.postBatch(...)` calls when
some JSON-RPC batch entries fail, without relying on router-private helpers or
losing the active Streamable HTTP session.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Router-hosted examples already cover mixed success/error batch behavior.
- The generated client-only smoke covered successful public generic direct JSON
  and Streamable batch calls, but did not yet prove that mixed success/error
  batch responses and notification omission are visible from a normal consumer
  package layout.

## Scope

- Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
- Add direct JSON `postBatch(...)` coverage with tool listing, a missing tool
  error, a successful tool call after the error, and a notification entry that
  must not produce a response.
- Add Streamable `postBatch(...)` coverage with tool listing, a missing tool
  error, a successful `ping` after the error, and a notification entry that
  must not produce a response.
- Prove the active Streamable HTTP session remains usable after mixed batch
  errors by sending a recovery `ping`.
- Extend the neutral fake MCP endpoint just enough to return JSON-RPC errors
  for missing fake tools and omit batch notification responses.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated client-only consumer package smoke passed on 2026-05-09
  with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Keep this in generated client-only smoke because the risk is normal consumer
  applications handling public `postBatch(...)` responses, including mixed
  JSON-RPC success/error entries, from a package boundary.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
deployment-chain evidence remain pending.
