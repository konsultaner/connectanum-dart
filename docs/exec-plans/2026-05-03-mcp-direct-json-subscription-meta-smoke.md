# Exec Plan: MCP Direct JSON Subscription Meta Smoke

Status: locally complete; hosted evidence pending
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Pin direct JSON access to standard WAMP subscription meta API procedures on
router-hosted MCP routes, including route-principal filtering for protected
topics.

## Scope

- Extend the router-native MCP smoke test with direct JSON
  `wamp.subscription.list`, `wamp.subscription.lookup`, and
  `wamp.subscription.match` calls.
- Verify anonymous direct JSON can discover subscriptions for public topics.
- Verify anonymous direct JSON cannot discover protected-topic subscriptions.
- Verify bearer-authenticated direct JSON can discover protected-topic
  subscriptions through the same route-hosted MCP endpoint.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push

## Progress

- 2026-05-03: Started after direct JSON registration meta API work completed
  and hosted evidence for `8bb74f8` was clean. The working tree only had
  docs-only hosted-evidence carryover before this test change.
- 2026-05-03: Pre-change `bin/test-fast` passed.
- 2026-05-03: Added router-native MCP smoke coverage for direct JSON
  subscription meta API calls on public and protected topics.
- 2026-05-03: Focused checks passed: `dart analyze
  packages/connectanum_mcp packages/connectanum_router`, `dart test
  packages/connectanum_router/test/router_integration_native_test.dart -r
  expanded --name "MCP"`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the subscription meta API
  smoke coverage and project-state updates.

## Decision Log

- 2026-05-03: Keep this as test-backed consumer-readiness coverage. The
  router implementation already filters subscription meta results through the
  route principal; the smoke test now prevents direct JSON pub/sub meta access
  from regressing while consumer applications start relying on it.

## Handoff

Pending commit, push, and hosted deployment-chain evidence.
