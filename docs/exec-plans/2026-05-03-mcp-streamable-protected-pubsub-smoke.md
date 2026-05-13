# Exec Plan: MCP Streamable Protected Pub/Sub Smoke

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Prove router-hosted MCP applies the same protected-topic authorization through
Streamable HTTP as it already does through direct JSON calls. Anonymous
Streamable HTTP clients must not discover or subscribe to member-only topics,
while bearer-authenticated Streamable HTTP clients can list, subscribe,
publish, poll, and unsubscribe the same protected topic.

## Scope

- Extend the router-native MCP smoke fixture for Streamable HTTP topic catalog
  filtering.
- Verify public Streamable HTTP `connectanum.api.list` hides the protected
  topic.
- Verify public Streamable HTTP pub/sub subscribe to the protected topic
  returns a tool-level error.
- Verify bearer-authenticated Streamable HTTP can list, subscribe, publish,
  poll, and unsubscribe the protected topic.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push

## Progress

- 2026-05-03: Started after a clean branch-head GitHub deployment-chain audit
  for `3d4fac6` and a passing pre-change `bin/test-fast`.
- 2026-05-03: Added Streamable HTTP protected-topic smoke coverage for public
  catalog filtering, public subscribe denial, and bearer-authenticated
  topic list/subscribe/publish/poll/unsubscribe.
- 2026-05-03: Focused checks passed: `dart analyze
  packages/connectanum_mcp packages/connectanum_router` and `dart test
  packages/connectanum_router/test/router_integration_native_test.dart -r
  expanded --name "MCP"`.
- 2026-05-03: Full local `bin/verify` passed after the Streamable protected
  pub/sub smoke addition and project-state updates.
- 2026-05-03: Pushed as `2bc49ce` (`mcp: smoke streamable protected
  pubsub`). Hosted GitHub evidence is clean: `CI` run `25286547478`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
  `25286547473` completed successfully, and `Dart Package Publish Dry Run`
  run `25286547477` completed successfully and covers the checked-out head.
  Native Artifacts dry-run `25192553399` remains clean and relevant because
  no native-release-sensitive paths changed.

## Decision Log

- 2026-05-03: Keep this as a test-backed readiness slice. Direct JSON already
  pinned protected pub/sub behavior; consumer applications and agents also need
  the same guarantee through the Streamable HTTP client path used for
  router-hosted MCP sessions.

## Handoff

Complete. Continue with the next roadmap-selected production-readiness slice.
