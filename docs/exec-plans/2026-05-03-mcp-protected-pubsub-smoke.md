# Exec Plan: MCP Protected Pub/Sub Smoke

Status: complete; hosted evidence clean
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
- 2026-05-03: Pushed as `3d4fac6` (`mcp: smoke protected pubsub route`).
  Hosted GitHub evidence is clean: `CI` run `25285593843` completed
  successfully with `Fast Checks` and `Full Verify`, the hosted CI log scan
  found no warning, deprecation, skipped-test, reset, connection-noise, panic,
  or failure patterns, `WAMP Profile Benchmarks` run `25285593814` completed
  successfully, and `Dart Package Publish Dry Run` run `25285593815`
  completed successfully and covers the checked-out head. Native Artifacts
  dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-03: Keep this as test-backed consumer-readiness work. The existing
  router MCP implementation already has principal filtering; this slice pins
  the protected pub/sub behavior so future MCP/catalog changes cannot regress
  it while downstream consumers start depending on direct JSON access.

## Handoff

Complete. Continue with the next roadmap-selected production-readiness slice
after a fresh branch-head audit.
