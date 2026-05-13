# Exec Plan: MCP Streamable Initialize Header Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Streamable HTTP polling and session deletion now accept per-call consumer
headers. The higher-level initialization helpers should expose the same API
shape so consumer applications can attach short-lived auth, trace, or routing
metadata to the full MCP session bootstrap path without relying on
constructor-wide headers.

This plan completes the Streamable HTTP session header surface for
initialization and initialized notifications, then proves the behavior through
package tests, IO entrypoint coverage, and neutral generated consumer smokes.

## Implementation Plan

1. Add optional `headers` parameters to `McpStreamableHttpClient.initialize`
   and `notifyInitialized`, forwarding through the existing POST request path.
2. Extend focused client package tests to assert per-call headers reach the
   initialization request without a session and the initialized notification
   with the active session.
3. Extend the `connectanum_mcp` IO entrypoint test so re-exported initialization
   helpers compile and forward the same headers from public API.
4. Extend generated neutral consumer smokes and the router-hosted MCP public
   example so package consumers exercise initialization headers against fake and
   router-hosted endpoints.
5. Run focused tests, package smokes, `bin/test-fast`, and `bin/verify`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/test/io_client_export_test.dart packages/connectanum_router/example/router_hosted_mcp.dart` completed cleanly.
- `bash -n bin/common.sh` passed.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart` passed.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed.
- Focused `run_mcp_client_package_smoke` passed.
- Focused `run_mcp_consumer_package_smoke` passed.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `86bb901` (`test: cover mcp streamable initialize headers`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25623601714` completed successfully for `86bb901` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25623601724` completed
  successfully for `86bb901`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25623601711` completed successfully for
  `86bb901`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean CI
  log scan, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Keep initialization headers as optional per-call maps, matching `request`,
  `post`, `notification`, `postBatch`, `poll`, and `deleteSession`. This keeps
  the public client API consistent while preserving constructor-wide default
  headers for stable metadata.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
