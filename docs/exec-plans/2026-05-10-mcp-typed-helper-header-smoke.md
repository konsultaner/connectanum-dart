# Exec Plan: MCP Typed Helper Header Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Streamable HTTP lifecycle, generic request, batch, notification, poll, and
delete paths already accept per-call consumer headers. The typed MCP helpers
for ping, tools, direct JSON tool access, resources, and prompts should expose
the same surface so downstream applications can attach short-lived auth, trace,
or routing metadata without dropping down to raw JSON-RPC calls.

This plan keeps the helper API backward-compatible while proving the new header
surface through package tests, IO entrypoint coverage, generated neutral
consumer smokes, and the router-hosted MCP public example.

## Implementation Plan

1. Add optional `headers` parameters to typed helper methods on
   `McpStreamableHttpClient`: `ping`, `listTools`, `callTool`,
   `listConnectanumToolsDirect`, `callConnectanumToolDirect`,
   `callConnectanumMethodDirect`, `listResources`, `readResource`,
   `listResourceTemplates`, `listPrompts`, and `getPrompt`.
2. Preserve existing MCP tool-argument header behavior by merging caller
   headers with cached tool parameter headers for `callTool`.
3. Extend focused client package tests to assert typed helper headers reach
   Streamable and direct JSON requests without changing session semantics.
4. Extend the `connectanum_mcp` IO entrypoint test so the re-exported helper
   API compiles and forwards custom headers.
5. Extend generated neutral consumer smokes and the router-hosted MCP public
   example so package consumers exercise typed helper headers against fake and
   router-hosted endpoints.
6. Run focused tests, package smokes, `bin/test-fast`, and `bin/verify`.

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
- Commit `c2e8b31` (`test: cover mcp typed helper headers`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25624621207` completed successfully for `c2e8b31` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25624621223` completed
  successfully for `c2e8b31`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25624621210` completed successfully for
  `c2e8b31`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean CI
  log scan, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Keep typed helper headers as optional per-call maps, matching existing generic
  request helpers and preserving constructor-wide default headers for stable
  metadata.
- Let MCP tool parameter headers override caller-provided keys on `callTool`
  merge collisions so the existing tool-argument header contract remains
  authoritative.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
