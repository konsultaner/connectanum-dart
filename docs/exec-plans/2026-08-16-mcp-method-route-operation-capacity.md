# Exec Plan: MCP Method-Route Operation Capacity

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Enforce route-wide router-hosted MCP request-scoped listener and WAMP
subscription limits when MCP is provided by a method-specific HTTP action.

## Problem

Method-specific actions produce structurally equal effective route copies.
Compatibility-session capacity now compares those routes structurally, but
listener and WAMP subscription reservations still group active endpoints by
route object identity. Independent protected principals can therefore exceed
both configured limits on the same method-provided MCP route.

## Plan

1. Add a real native-router fail-first regression with two protected principals
   using one method-provided MCP route.
2. Prove listener rejection, WAMP subscription rejection/recovery, stateless
   direct JSON continuity, and acknowledged self-delivered pub/sub. Keep
   listener disconnect timing in the existing dedicated release regression.
3. Make both route-wide counters use the route type's structural equality
   contract.
4. Run focused, fast, and full verification, then publish and collect exact-head
   deployment-chain evidence.

## Progress

- 2026-08-16: Serena and repository preflight completed with no unrelated
  editor or stale lock. The inherited working-tree changes are the prior MCP
  capacity checkpoint's hosted-evidence notes.
- 2026-08-16: Pre-change `bin/test-fast` passed, including all 97 benchmark
  tests with 37 live WAMP workloads and every maintained MCP consumer/CLI
  smoke.
- 2026-08-16: Symbol-aware inspection found the same route-identity comparison
  in both `_reserveMcpRequestScopedListener` and
  `_reserveMcpWampSubscription`. The protected native-router regression first
  failed because a second principal opened another request-scoped listener at
  a one-listener limit. After fixing only that counter, the same regression
  advanced and failed because the second principal opened another WAMP topic
  subscription at a one-subscription limit.
- 2026-08-16: Both route-wide reservations now use structural
  `HttpRouteSettings` equality. The regression proves HTTP 503 listener
  rejection without MCP session state, direct JSON continuity, tool-level WAMP
  capacity rejection, unsubscribe-driven recovery, and an acknowledged
  self-delivered event after recovery for two router-issued principals.
- 2026-08-16: The new regression passes five consecutive runs. The preceding
  method-route session-capacity regression, ordinary listener-capacity
  regression, ordinary WAMP subscription/queue-capacity regression, and full
  router analysis also pass.
- 2026-08-16: Post-change `bin/test-fast` passed, including all 97 benchmark
  tests with 37 live WAMP workloads and every maintained MCP consumer/CLI
  smoke.
- 2026-08-16: Canonical `bin/verify` passed with zero formatting changes, 117
  Rust core/serializer tests, 52 native FFI tests, the feature-gated native
  metrics snapshot, 366 Dart core tests, 116 MCP tests, the complete 293-case
  MCP/client suite, all 97 benchmark tests including 37 live WAMP workloads,
  all 452 router cases, six remote-auth tests, 13 native follow-ups, every
  maintained consumer/global-activation smoke, Chrome, and Dart2Wasm.
