# Exec Plan: MCP Method-Route Session Capacity

Status: completed
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Enforce router-hosted MCP `max_session_count` for method-specific MCP route
actions, while preserving ordinary compatibility sessions, direct JSON access,
and cleanup.

## Problem

Method-specific HTTP actions are materialized as structurally equal effective
route copies on each request. MCP session-capacity accounting currently groups
active endpoints by route object identity, so a `POST` MCP method action can
create more compatibility sessions than its configured per-route limit.

## Scope

- Add a real native-router regression for a method-specific MCP action with a
  one-session limit.
- Count active compatibility sessions by the effective route's structural
  identity rather than transient Dart object identity.
- Prove the active session remains usable, direct JSON remains sessionless,
  and DELETE or router teardown releases retained state.
- Add neutral consumer-package evidence only if the existing public smoke can
  cover the method-action route without distorting its production contract.

## Verification

- `bin/test-fast` before implementation.
- Focused fail-first and passing native-router regression.
- Router package analysis and relevant session-capacity coverage.
- `bin/verify` before handoff.
- Exact-head GitHub deployment-chain evidence after publication.

## Progress

- 2026-08-16: Repository workflow and Serena preflight completed. No unrelated
  repository editor or stale lock is present, and the inherited working-tree
  changes are the prior implementation's hosted-evidence notes.
- 2026-08-16: Symbol-aware inspection found that effective method actions are
  reconstructed per request while MCP capacity accounting uses route object
  identity. The required pre-change `bin/test-fast` passed, including the
  maintained source, installed-package, and globally activated MCP smokes.
- 2026-08-16: A real native-router regression now configures MCP as the
  method-specific `POST`/`DELETE` action behind an ordinary base action. Before
  the implementation change, a second client initialized successfully despite
  `max_session_count: 1`, reproducing the capacity bypass.
- 2026-08-16: MCP capacity accounting now groups effective routes with the
  existing structural `HttpRouteSettings` equality contract. The regression
  proves the rejected contender receives no session state, direct JSON remains
  sessionless, the active session remains usable, and DELETE frees capacity.
  The focused native regression passes five consecutive runs and router package
  analysis is clean.
- 2026-08-16: Post-change `bin/test-fast` passed, including all 97 benchmark
  tests with 37 live WAMP workloads and every maintained router-hosted MCP
  consumer/global-activation smoke.
- 2026-08-16: Canonical `bin/verify` passed formatting, 117 Rust
  core/serializer tests, 52 native FFI tests, the feature-gated native metrics
  snapshot, 366 Dart core tests, 116 MCP tests, the complete 293-case
  MCP/client suite, all 97 benchmark tests including 37 live WAMP workloads,
  all 451 router cases, six remote-auth tests, 13 native follow-ups, every
  maintained consumer/global-activation smoke, Chrome, and Dart2Wasm.
