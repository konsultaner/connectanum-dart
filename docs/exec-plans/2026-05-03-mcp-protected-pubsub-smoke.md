# Exec Plan: MCP Protected Pub/Sub Smoke

Status: locally complete; hosted evidence pending
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Prove router-hosted MCP applies route-authenticated principal filtering to
pub/sub topics, not only RPC tools. Anonymous direct JSON clients must not see
or use member-only topics, while authenticated clients can discover and use the
same topic through the direct JSON MCP facade.

## Scope

- Extend the router-native MCP smoke fixture with a member-only topic.
- Verify public direct JSON `connectanum.api.list` topic metadata hides the
  protected topic.
- Verify public direct JSON pub/sub access to the protected topic is rejected.
- Verify bearer-authenticated direct JSON can list, subscribe, publish, poll,
  and unsubscribe the protected topic on the router-hosted MCP route.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push

## Progress

- 2026-05-03: Started after hosted deployment-chain evidence for `ac9125e`
  was clean and pre-change `bin/test-fast` passed.
- 2026-05-03: Added protected-topic config and direct JSON smoke coverage for
  anonymous denial plus bearer-authenticated topic list/subscribe/publish/poll
  and unsubscribe.
- 2026-05-03: Focused checks passed: `dart analyze packages/connectanum_mcp
  packages/connectanum_router`, `dart test
  packages/connectanum_router/test/router_integration_native_test.dart -r
  expanded --name "MCP"`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the protected pub/sub
  smoke addition and project-state updates.

## Decision Log

- 2026-05-03: Keep this as test-backed consumer-readiness work. The existing
  router MCP implementation already has principal filtering; this slice pins
  the protected pub/sub behavior so future MCP/catalog changes cannot regress
  it while downstream consumers start depending on direct JSON access.

## Handoff

Pending commit, push, and hosted deployment-chain evidence.
