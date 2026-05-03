# Exec Plan: MCP Direct JSON Pub/Sub Smoke

Status: locally complete; hosted evidence pending
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Prove that frontend-style HTTP clients can use router-hosted MCP pub/sub tools
through direct dotted JSON-RPC methods without running the MCP lifecycle or
wrapping calls in `connectanum.tool.call`.

## Scope

- Extend the router-native MCP smoke test to call
  `connectanum.pubsub.subscribe`, `connectanum.pubsub.publish`,
  `connectanum.pubsub.poll`, and `connectanum.pubsub.unsubscribe` directly on
  the router-hosted MCP route.
- Keep the calls on the same route-authenticated router MCP session and tool
  registry as MCP `tools/call` and Streamable HTTP clients.
- Verify direct JSON pub/sub can observe an event published by the application
  WAMP session.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_mcp -r expanded`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push

## Progress

- 2026-05-03: Started after a clean branch-head hosted audit for `7933c71` and
  a passing pre-change `bin/test-fast`.
- 2026-05-03: Added router-native MCP smoke coverage for direct dotted JSON
  pub/sub subscribe, publish, poll, and unsubscribe calls. Focused checks
  passed: `dart analyze packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_mcp -r expanded`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`.
- 2026-05-03: Full local `bin/verify` passed after the direct JSON pub/sub
  smoke addition and project-state updates.

## Decision Log

- 2026-05-03: Use dotted direct JSON method names instead of
  `connectanum.tool.call` for this smoke because the consumer-readiness gap is
  frontend-style JSON access to the MCP tool surface.

## Handoff

Pending commit, push, and hosted deployment-chain evidence.
