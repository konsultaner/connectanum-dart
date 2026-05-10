# Exec Plan: MCP Streamable Session Header Smoke

Status: complete; local verification clean, hosted evidence pending after push
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Direct JSON-RPC MCP calls already expose per-call header controls for consumer
auth, trace, and routing metadata. Streamable HTTP session lifecycle operations
also need the same public control surface so consumer applications can attach
per-call metadata to GET/SSE polling and DELETE cleanup without relying on
constructor-wide headers.

This plan extends the public Streamable HTTP client lifecycle API and proves the
behavior through package tests, IO entrypoint coverage, and neutral generated
consumer smokes.

## Implementation Plan

1. Add optional `headers` parameters to `McpStreamableHttpClient.poll` and
   `deleteSession`, forwarding them through the existing `_applyHeaders`
   request path.
2. Extend focused client package tests to assert per-call headers reach GET and
   DELETE requests while preserving session and Last-Event-ID behavior.
3. Extend the `connectanum_mcp` IO entrypoint test so re-exported lifecycle
   calls compile and forward the same headers from public API.
4. Extend generated neutral consumer smokes so a package consumer can poll and
   delete Streamable sessions with per-call metadata against both fake and
   router-hosted endpoints.
5. Run focused tests, package smokes, `bin/test-fast`, and `bin/verify`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/test/io_client_export_test.dart packages/connectanum_router/example/router_hosted_mcp.dart` completed cleanly.
- `bash -n bin/common.sh` passed.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart` passed.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed.
- Focused `run_mcp_client_package_smoke` passed.
- Focused `run_mcp_consumer_package_smoke` passed.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Hosted deployment-chain evidence is pending until the implementation commit is
  pushed.

## Decision Log

- Keep lifecycle headers as per-call optional maps, matching the existing
  `request`, `post`, `notification`, and `postBatch` API shape. This avoids a
  separate lifecycle-specific hook while still letting downstream applications
  send short-lived auth or trace metadata.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence still need to be collected for the implementation
commit.
