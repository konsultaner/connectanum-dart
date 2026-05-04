# Exec Plan: MCP Client Bearer Convenience

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make authenticated router-hosted MCP endpoints easier for consumer
applications to use without hand-building authorization headers.

## Scope

In scope:

- Add a typed bearer-token constructor to the Streamable HTTP MCP client.
- Use the constructor in router-hosted secure MCP smoke/example paths.
- Cover the helper in client tests and existing router-hosted MCP smoke tests.
- Refresh public MCP documentation that still described pre-Streamable HTTP
  router behavior.

Out of scope:

- New authentication providers.
- Standalone MCP server processes.
- Private downstream application references.

## Plan

1. Add `McpStreamableHttpClient.withBearerToken(...)`.
2. Prove token trimming and empty-token rejection in client tests.
3. Move the secure router-hosted MCP example and secure router smoke clients to
   the helper.
4. Run focused client/router checks, then full verification.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_client packages/connectanum_router packages/connectanum_mcp`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- Full local `bin/verify` passed on 2026-05-04.

## Handoff

Implementation and local verification are complete. Hosted evidence is pending
for the implementation commit.
