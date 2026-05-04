# Exec Plan: MCP Streamable Batch Smoke

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Prove consumer applications can send JSON-RPC batches through router-hosted MCP
Streamable HTTP sessions and receive batched SSE responses from both public and
bearer-protected router MCP routes.

## Scope

In scope:

- Add router integration coverage for stateful Streamable HTTP batch `POST`
  requests against `/mcp/public` and `/mcp/secure`.
- Exercise the public consumer `McpStreamableHttpClient.postBatch(...)` API
  against real router-hosted MCP endpoints.
- Extend the runnable router-hosted MCP example smoke to prove the same batch
  path without consumer-specific project assumptions.

Out of scope:

- New JSON-RPC batch semantics.
- New auth providers or token issuance flows.
- Consumer-specific application references.

## Plan

1. Reuse the existing MCP smoke router settings and neutral ticket fixture.
2. Register a route-visible WAMP procedure for a batch `tools/call` request.
3. Initialize Streamable MCP sessions on public and secure routes.
4. Send a batch containing `tools/list`, `tools/call`, and a notification, then
   assert only the response-producing entries are returned in order.
5. Add the same batch check to the runnable example smoke.
6. Run focused router/example checks and full workspace verification.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "serves Streamable HTTP batch responses on router MCP routes"`,
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- Full local `bin/verify` passed on 2026-05-04.
- Commit `c754772` was pushed to both remotes. Hosted GitHub evidence for
  `c754772` is clean: `CI` run `25322481688` completed successfully with
  `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
  `25322481294` completed successfully, and `WAMP Profile Benchmarks` run
  `25322481349` completed successfully. The deployment-chain audit with
  required clean latest CI, clean hosted CI logs, and clean Dart package
  publish dry-run passed for branch head `c754772`; the remaining audit
  findings are the existing operator/deployment items around branch
  protection, default-branch router workflow visibility, and GHCR router
  package visibility.

## Handoff

Implementation, local verification, and hosted GitHub deployment-chain evidence
are complete.
