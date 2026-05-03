# Exec Plan: MCP Direct JSON Session Meta Scope

Status: locally complete; hosted evidence pending
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Prevent router-hosted MCP direct JSON session meta calls from exposing unrelated
realm sessions. `wamp.session.count`, `wamp.session.list`, and
`wamp.session.get` should execute in the context of the MCP route's internal
session identity.

## Scope

- Scope router-hosted MCP session meta results to the route session that is
  handling the request.
- Keep registration and subscription meta filtering unchanged.
- Extend the native MCP smoke test so anonymous and bearer-authenticated routes
  can inspect their own route session details but cannot read the service
  session used by the test fixture.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_mcp/test/streamable_http_client_test.dart -r expanded`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push, if committed and pushed

## Progress

- 2026-05-03: Started after hosted evidence for `4a0a877` was clean and the
  active direct JSON subscription meta plan was marked complete.
- 2026-05-03: Pre-change `bin/test-fast` passed.
- 2026-05-03: Scoped MCP session meta calls to the route session and added
  anonymous plus bearer route smoke coverage for session list/get visibility.
- 2026-05-03: Moved the IO-only `McpStreamableHttpClient` implementation from
  `src/transport/` to `src/client/` so the package layout reflects that it is a
  consumer-facing MCP client/session helper, not router/client transport-layer
  plumbing.
- 2026-05-03: Focused checks passed: targeted native MCP smoke,
  `dart analyze packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_mcp/test/streamable_http_client_test.dart -r
  expanded`,
  full `--name "MCP"` native router integration subset, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the session meta scoping
  implementation and project-state updates.

## Decision Log

- 2026-05-03: Use a conservative session-meta visibility rule for router-hosted
  MCP: a route can see its own MCP route session. This avoids leaking internal
  service sessions while preserving the route-principal behavior needed by
  direct JSON clients and agents.

## Handoff

Pending commit, push, and hosted deployment-chain evidence.
