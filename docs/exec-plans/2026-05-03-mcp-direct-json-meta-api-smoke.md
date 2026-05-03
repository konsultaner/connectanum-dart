# Exec Plan: MCP Direct JSON Meta API Smoke

Status: locally complete; hosted evidence pending
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Make router-hosted MCP safer and easier to use from direct JSON consumer
clients by exposing standard WAMP meta API procedures on the route-hosted JSON
facade while preserving the route session's authorization boundaries.

## Scope

- Expose configured standard WAMP meta procedures when a router `type: mcp`
  route has `include_standard_meta_api` enabled.
- Filter registration and subscription meta API results through the same
  route-authenticated principal used for router-hosted MCP calls.
- Extend the router-native MCP smoke test so anonymous direct JSON can inspect
  visible safe registrations but cannot discover protected/unsafe
  registrations, while a bearer-authenticated route can discover the protected
  registration.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `git diff --check`
- `bin/verify`
- Hosted GitHub deployment-chain audit after push

## Progress

- 2026-05-03: Started after completing and pushing the Streamable protected
  pub/sub smoke slice. The working tree only had docs-only hosted-evidence
  carryover before this code change.
- 2026-05-03: Pre-change `bin/test-fast` passed before the direct JSON meta
  API edits.
- 2026-05-03: Added direct JSON smoke assertions for `wamp.registration.list`
  and `wamp.registration.match`. The first run reproduced the direct JSON
  gap: `wamp.registration.list` returned `Unknown MCP method`.
- 2026-05-03: Updated router-hosted MCP API projection so standard WAMP meta
  procedures are exposed by the route when enabled, then filtered
  registration/subscription meta results through the current route session's
  authorization.
- 2026-05-03: Focused checks passed: `dart analyze packages/connectanum_mcp
  packages/connectanum_router`, `dart test
  packages/connectanum_router/test/router_integration_native_test.dart -r
  expanded --name "MCP"`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the direct JSON meta API
  implementation and project-state updates.

## Decision Log

- 2026-05-03: Treat standard WAMP meta procedures as router-provided MCP
  route functionality controlled by `include_standard_meta_api`, not as app
  WAMP procedures that must have separate `wamp.*` role permissions. The data
  returned by those procedures still must be filtered by the route principal.

## Handoff

Pending full local verification, commit, push, and hosted deployment-chain
evidence.
