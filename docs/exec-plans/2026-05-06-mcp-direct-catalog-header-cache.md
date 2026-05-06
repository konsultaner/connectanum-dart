# Exec Plan: MCP Direct Catalog Header Cache

## Goal

Make direct JSON tool discovery compatible with later Streamable MCP tool calls
by having `connectanum.tools.list` populate the same custom parameter header
cache as standard `tools/list`.

## Scope

- Reuse the `x-mcp-header` cache path when
  `McpStreamableHttpClient.listConnectanumToolsDirect()` reads a tool catalog.
- Add client smoke coverage proving a consumer can discover a tool with direct
  JSON, then call it through Streamable MCP with matching `Mcp-Param-*`
  headers.
- Keep the direct JSON helper request shape lifecycle-free and JSON-only.
- Bundle this plan with the implementation and the already pending hosted
  evidence bookkeeping from the previous MCP consumer custom-header slice.

## Non-Goals

- Changing router-hosted MCP dispatch or route-auth semantics.
- Adding private downstream application references.
- Adding public docs before the behavior and verification evidence are clean.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- Focused client verification passed on 2026-05-06:
  - `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "reuses direct JSON tool catalog for later Streamable custom headers"`
  - `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- Post-change `bin/test-fast` passed on 2026-05-06, including the generated
  consumer package smoke.
- Full `bin/verify` passed on 2026-05-06, including formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  and generated consumer package smoke, full router package tests, zero-copy
  router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted evidence pending.

## Status

- 2026-05-06: Started after the MCP consumer custom header smoke reached clean
  hosted CI evidence. The next downstream-readiness gap is direct JSON catalog
  discovery feeding later Streamable custom-header tool calls.
- 2026-05-06: Complete locally. Direct JSON tool catalog discovery now warms
  the same client custom-header cache as standard `tools/list`, and focused,
  fast-suite, and full local verification passed. Hosted evidence is pending.
