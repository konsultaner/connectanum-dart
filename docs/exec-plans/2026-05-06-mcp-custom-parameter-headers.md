# Exec Plan: MCP Custom Parameter Headers

## Goal

Finish the next Streamable HTTP compatibility slice for router-hosted MCP by
supporting SEP-2243 custom tool-parameter headers. Consumer applications and
agents should be able to use MCP tools whose `inputSchema` marks primitive
arguments with `x-mcp-header`, and router-hosted endpoints should reject
Streamable tool calls when mirrored `Mcp-Param-*` headers are missing,
malformed, or inconsistent with the JSON-RPC body.

## References

- Official Streamable HTTP transport:
  https://modelcontextprotocol.io/specification/latest/basic/transports
- SEP-2243 HTTP header standardization:
  https://modelcontextprotocol.io/seps/2243-http-standardization

## Scope

- Teach `McpStreamableHttpClient` to remember valid `x-mcp-header` mappings
  from `tools/list`, filter malformed tool definitions from typed tool-list
  results, and emit encoded `Mcp-Param-*` headers on cached `tools/call`
  requests.
- Preserve direct JSON compatibility: JSON-only callers that do not send
  custom parameter headers continue to work, while supplied mismatched
  `Mcp-Param-*` headers are rejected.
- Validate router-hosted MCP `tools/call` parameter headers for Streamable
  requests before dispatching the tool.
- Cover the behavior with focused client and native router integration tests,
  plus the generated consumer-package smoke.

## Non-Goals

- Adding route-specific header-size policy. HTTP infrastructure can continue to
  enforce deployment-specific header limits.
- Extending custom parameter headers beyond `tools/call`; resources and prompts
  already expose their routing key through `Mcp-Name`.
- Changing direct Connectanum JSON helper method names or body shapes.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- Focused verification passed on 2026-05-06:
  - `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
  - `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`
  - `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "guards MCP Streamable HTTP ingress and sessions"`
  - `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  - `dart analyze packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`
  - `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full `bin/verify` passed on 2026-05-06, including formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  and generated consumer package smoke, full router package tests, zero-copy
  router checks, and Chrome Dart2Wasm WebSocket transport tests.

## Status

- 2026-05-06: Implementation and full local verification are complete. Hosted
  evidence is pending after push.
