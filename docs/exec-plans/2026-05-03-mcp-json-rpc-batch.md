# Exec Plan: MCP JSON-RPC Batch Support

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Make router-hosted MCP and the standalone MCP server accept JSON-RPC batch
requests so frontend and agent clients can group direct JSON tool/meta calls
without needing a separate MCP server or client-specific workaround.

## Scope

- Add batch handling to `McpServer.handleMessage`, preserving response order
  and omitting notification-only entries.
- Keep empty batches invalid with a JSON-RPC invalid-request response.
- Let stdio transport write batch responses as one JSON line.
- Let router-hosted MCP direct JSON batches mix direct tool/meta methods and
  normal MCP JSON-RPC methods on the route-owned session.
- Add focused package and native router smoke coverage.
- Expose batch posting from `McpStreamableHttpClient`, including JSON and SSE
  batch response parsing.

## Progress

- 2026-05-03: Pre-change `bin/test-fast` passed.
- 2026-05-03: Added failing MCP server, stdio transport, and router-hosted MCP
  smoke coverage for JSON-RPC batch requests.
- 2026-05-03: Implemented batch dispatch in `McpServer`, stdio response
  writing, router-hosted direct JSON dispatch, and `McpStreamableHttpClient`
  `postBatch(...)`.
- 2026-05-03: Added router-hosted coverage that nested batch entries are
  rejected as invalid request objects instead of being treated as a second
  top-level batch.
- 2026-05-03: Focused checks passed:
  `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart packages/connectanum_mcp/test/stdio_transport_test.dart -r expanded`,
  `dart test packages/connectanum_client/test/mcp -r expanded`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- 2026-05-03: Full local `bin/verify` passed after the JSON-RPC batch
  implementation.
- 2026-05-03: Pushed `f42d06d` and watched the hosted GitHub deployment
  chain. `CI`, `Dart Package Publish Dry Run`, and `WAMP Profile Benchmarks`
  completed successfully for the branch head. The strict deployment-chain
  audit passed required clean latest CI, CI-log, Dart package dry-run, and
  native release dry-run checks.

## Decision Log

- 2026-05-03: Batch support is scoped to JSON-RPC response batching only. It
  does not change authorization, session ownership, or route principal
  semantics; every individual entry still executes through the same route MCP
  endpoint/session path as a single request.

## Handoff

Complete. Remaining audit findings are unchanged deployment/operator items:
branch protection is not enabled, `.github/workflows/router-image.yml` is not
discoverable until promoted through the default branch, and the router GHCR
package is not visible yet.
