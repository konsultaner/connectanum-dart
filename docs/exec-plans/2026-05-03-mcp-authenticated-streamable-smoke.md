# Exec Plan: MCP Authenticated Streamable Router Smoke

Status: completed
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
- Verify the Streamable HTTP client can use router-backed MCP pub/sub tools for
  subscribe, publish, poll, and unsubscribe on a real router-hosted route.

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
- 2026-05-03: Pushed commit `b7b0348`
  (`mcp: smoke authenticated streamable route`) to GitLab and GitHub. Hosted
  GitHub evidence is clean: `CI` run `25283148543` completed successfully with
  `Fast Checks` in 5m38s and `Full Verify` in 8m06s, hosted CI log scan found
  no warning, deprecation, skipped-test, reset, connection-noise, panic, or
  failure patterns, `WAMP Profile Benchmarks` run `25283148557` completed
  successfully in 7m41s, `Dart Package Publish Dry Run` run `25283148560`
  completed successfully and covers the checked-out head, and Native Artifacts
  dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.
- 2026-05-03: Added public-route Streamable HTTP client coverage for
  `connectanum.pubsub.subscribe`, `connectanum.pubsub.publish`,
  `connectanum.pubsub.poll`, and `connectanum.pubsub.unsubscribe` against a
  real router-hosted MCP route. Focused checks passed:
  `dart analyze packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_mcp -r expanded`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`.
- 2026-05-03: Full local `bin/verify` passed after the Streamable HTTP pub/sub
  router smoke addition and project-state updates.
- 2026-05-03: Pushed commit `7933c71`
  (`mcp: smoke streamable pubsub tools`) to GitLab and GitHub. Hosted GitHub
  evidence is clean: `CI` run `25283791303` completed successfully with
  `Fast Checks` in 5m36s and `Full Verify` in 8m05s, hosted CI log scan found
  no warning, deprecation, skipped-test, reset, connection-noise, panic, or
  failure patterns, `WAMP Profile Benchmarks` run `25283791165` completed
  successfully in 7m49s, `Dart Package Publish Dry Run` run `25283791166`
  completed successfully and covers the checked-out head, and Native Artifacts
  dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-03: Keep this as router-native smoke coverage instead of a fake
  endpoint unit test because the gap is session/auth propagation through the
  actual router-hosted MCP route.

## Handoff

Complete. Remaining MCP work should target concrete consumer-readiness gaps in
router-hosted auth/session behavior, direct JSON meta/tool access, pub/sub
coverage, or agent smoke compatibility.
