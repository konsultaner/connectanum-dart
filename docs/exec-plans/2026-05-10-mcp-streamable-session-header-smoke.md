# Exec Plan: MCP Streamable Session Header Smoke

Status: complete; hosted CI evidence clean
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
- Commit `020980a` (`test: cover mcp streamable session headers`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25622672504` completed successfully for `020980a` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25622672496` completed
  successfully for `020980a`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25622672501` completed successfully for
  `020980a`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean CI
  log scan, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Keep lifecycle headers as per-call optional maps, matching the existing
  `request`, `post`, `notification`, and `postBatch` API shape. This avoids a
  separate lifecycle-specific hook while still letting downstream applications
  send short-lived auth or trace metadata.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
