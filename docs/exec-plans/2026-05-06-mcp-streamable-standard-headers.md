# Exec Plan: MCP Streamable Standard Headers

## Objective

Close the Streamable HTTP compatibility gap introduced by the current MCP
standard request-header draft so consumer applications can rely on
router-hosted MCP through intermediaries that inspect `Mcp-Method` and
`Mcp-Name`.

## Scope

- Emit `Mcp-Method` on public `McpStreamableHttpClient` single-message POSTs.
- Emit `Mcp-Name` for `tools/call`, `resources/read`, and `prompts/get` when
  the body contains the corresponding `params.name` or `params.uri`.
- Reject Streamable HTTP single-message POSTs with missing or mismatched
  standard headers using the MCP `HeaderMismatch` server-error code.
- Preserve direct JSON compatibility by allowing missing standard headers for
  JSON-only direct calls while still rejecting mismatches when callers send the
  headers.
- Add focused client/router coverage and keep the generated consumer smoke on
  public package APIs.

## Spec Inputs

- Official MCP draft Streamable HTTP transport:
  `https://modelcontextprotocol.io/specification/draft/basic/transports`
- MCP SEP-2243 HTTP header standardization:
  `https://modelcontextprotocol.io/seps/2243-http-standardization`

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- Focused client/router tests passed on 2026-05-06:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "guards MCP Streamable HTTP ingress and sessions"`,
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "isolates MCP Streamable HTTP sessions by route and bearer principal"`.
- Generated consumer smoke passed on 2026-05-06:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-06. A follow-up
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`
  passed after the style cleanup for the new test helper.
- Full local `bin/verify` passed on 2026-05-06.

## Status

- 2026-05-06: Started. The current MCP draft transport requires standard POST
  headers mirrored from the JSON-RPC body. This slice updates the package client
  and router-hosted endpoint together so downstream applications get compliant
  client behavior plus router-side mismatch protection.
- 2026-05-06: Complete locally. Hosted evidence is pending for the next
  implementation push.
