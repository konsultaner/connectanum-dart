# Exec Plan: MCP Authenticated Streamable Router Smoke

Status: completed locally
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Prove that the shipped Dart IO Streamable HTTP client can use a router-hosted
MCP endpoint with deployment auth, router-side sessions, advertised safe and
unsafe tool metadata, and protected tool calls.

## Scope

- Extend the router-native MCP smoke test so `McpStreamableHttpClient` connects
  to the protected `/mcp/secure` route with a bearer token.
- Verify the Streamable HTTP initialize flow stores the router MCP session.
- Verify `tools/list` on the protected route exposes both safe and unsafe
  router-backed tools.
- Verify a protected unsafe tool call succeeds through the Streamable HTTP
  client and records an SSE event id.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_mcp -r expanded`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push

## Progress

- 2026-05-03: Started after a clean branch-head hosted audit for `9906d69` and
  a passing pre-change `bin/test-fast`.
- 2026-05-03: Added router-native MCP smoke coverage for authenticated
  Streamable HTTP client initialization, protected tool discovery, protected
  unsafe tool calls, MCP session tracking, and SSE event id tracking on
  `/mcp/secure`.
- 2026-05-03: Focused checks passed:
  `dart analyze packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_mcp -r expanded`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`.
- 2026-05-03: Full local `bin/verify` passed after the authenticated
  Streamable HTTP router smoke addition and project-state updates.

## Decision Log

- 2026-05-03: Keep this as router-native smoke coverage instead of a fake
  endpoint unit test because the gap is session/auth propagation through the
  actual router-hosted MCP route.

## Handoff

Complete locally. Commit and push the test/readiness checkpoint, then inspect
hosted GitHub deployment-chain evidence because this is router integration test
coverage on a shipped MCP path.
