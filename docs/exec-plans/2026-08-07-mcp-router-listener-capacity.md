# MCP Router Request-Scoped Listener Capacity

Status: implementation complete; local verification clean, hosted verification pending

## Goal

Bound router-hosted MCP `2026-07-28` request-scoped listener admission so a
client bug or hostile caller cannot retain arbitrarily many long-lived SSE
streams, notification filters, and shared WAMP resource-subscription owners.

## Scope

- In scope: positive snake/camel route options, a safe default capacity,
  atomic admission across preparation and active listener lifetimes, listener-
  and route-scoped accounting across authenticated MCP endpoint instances,
  authorization and request-validation precedence, HTTP/JSON-RPC overload
  behavior without MCP session state, existing-listener continuity, direct
  JSON and compatibility-session independence, and capacity recovery after
  setup failure or listener close.
- Out of scope: compatibility MCP session admission, WAMP realm-session
  limits, per-principal quotas, distributed limits across router processes,
  changing heartbeat cadence, and replay for request-scoped listeners.

## Preconditions

- Both maintained `master` branches and the local branch start at `47ad042e`.
- The preceding router-hosted MCP session-capacity checkpoint passed local
  verification, exact-head hosted workflows, and the comprehensive strict
  deployment audit.
- The preceding checkpoint's hosted-evidence bookkeeping is intentionally
  uncommitted and will accompany this implementation.

## Plan

1. Run the pre-change fast gate and add fail-first route-validation and native-
   router regressions showing that listener admission is unbounded.
2. Add positive `max_request_scoped_listener_count` and
   `maxRequestScopedListenerCount` route options with a bounded default.
3. Reserve capacity synchronously after listener request validation and before
   asynchronous resource authorization, count preparations plus active streams
   across endpoint instances for the same listener and route, and release the
   reservation on every setup-failure and close path.
4. Prove public and protected overload behavior, missing-bearer precedence,
   route isolation, existing-listener continuity, sessionless direct JSON and
   compatibility-session independence, concurrent-setup admission, and close-
   driven recovery.
5. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_json_test.dart`
- focused `router_integration_native_test.dart` regressions
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source audit found that every admitted request-scoped listener
  retains a native SSE response stream and notification filter; filtered
  resource listeners may additionally retain shared WAMP subscription
  ownership. Client disconnect is detected by subsequent notification or
  heartbeat writes and already converges through the existing close path.
- 2026-08-07: Capacity must include both in-flight preparations and active
  streams. A synchronous reservation before the first asynchronous resource
  authorization prevents concurrent setup requests from oversubscribing the
  route. Accounting is per HTTP listener and route across the stateless
  endpoints created for different authenticated WAMP sessions.
- 2026-08-07: The pre-change `bin/test-fast` gate passed the complete fast
  regression, benchmark/live-router, neutral consumer, global activation,
  Router CLI consumer, and focused native/router matrix. Fail-first route
  validation then accepted a zero limit, and the native router admitted a
  second listener while the first was blocked in resource authorization.
- 2026-08-07: MCP routes now accept positive
  `max_request_scoped_listener_count` and
  `maxRequestScopedListenerCount` values with a default of 1024. Admission
  counts in-flight preparations plus active streams on the same HTTP listener
  and route across authenticated endpoint instances. Capacity is released on
  preparation failure, stream-open failure, active-stream write failure, and
  endpoint disposal through the established cleanup paths.
- 2026-08-07: Focused router analysis, route-validation tests, and both native
  listener-capacity regressions pass. Coverage proves public and protected
  overload behavior, malformed-request and missing-bearer precedence,
  sessionless rejection, route isolation, continued notification delivery,
  direct JSON and compatibility-session independence, concurrent preparation
  admission, and close-driven recovery.
- 2026-08-07: Post-change `bin/test-fast` and `bin/verify` both exited zero.
  Full verification included formatting and analysis, 113 Rust core tests, 52
  Rust FFI tests, 360 Dart core tests, all 95 MCP tests, the complete 280-case
  MCP/client suite, all 96 benchmark tests and live WAMP workloads, every
  generated and globally activated consumer smoke, the complete 387-case
  router suite, the 6-case remote-auth process, the 13-case native follow-up,
  and Chrome/Dart2Wasm WebSocket coverage.

## Handoff

- Implementation and local verification are complete. Commit and push both
  maintained branches, then audit exact-head hosted evidence.
