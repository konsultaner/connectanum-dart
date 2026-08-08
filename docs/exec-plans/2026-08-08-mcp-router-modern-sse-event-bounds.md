# MCP Router Modern SSE Event Bounds

Status: active; implementation and complete local verification green,
publication and hosted evidence pending

## Goal

Make router-hosted MCP `max_response_bytes` bound each complete encoded event
on modern `2026-07-28` request-scoped SSE streams, including the initial
subscription acknowledgment before the native response stream opens, while
preserving listener-capacity accounting and endpoint reuse on rejection.

## Scope

- In scope: exact request-scoped SSE event-byte accounting, pre-stream
  acknowledgment rejection, established-listener notification/final-event
  containment, listener-capacity recovery, focused native coverage, public
  configuration wording, and normal local plus hosted verification.
- Out of scope: a lifetime byte ceiling for long-lived streams, changing the
  route option/default, adding notification buffering, changing compatibility
  GET/SSE or POST/SSE behavior, or adding demand-driven MCP extensions.

## Preconditions

- Both maintained `master` branches and the local feature branch start at
  `d90c5d14`.
- The preceding compatibility POST/SSE wire-bound checkpoint passed complete
  local verification, exact-head hosted workflows, and the comprehensive
  strict deployment-chain audit.
- Its final hosted-evidence bookkeeping remains intentionally uncommitted for
  bundling with this implementation commit.

## Plan

1. Run pre-change `bin/test-fast`, then add a fail-first native-router
   regression whose modern `subscriptions/listen` acknowledgment exceeds the
   route ceiling only after exact SSE framing.
2. Encode the acknowledgment before opening the native response stream,
   reject it with the bounded HTTP JSON-RPC error, release all listener and
   resource-preparation ownership, and reuse the encoded body on success.
3. Apply the same per-event ceiling to later notifications and graceful final
   events so established streams cannot emit one unbounded event; close only
   the affected listener when an event cannot fit.
4. Prove a smaller listener can be admitted after rejection, receives its
   acknowledgment, and closes cleanly; run focused checks, `bin/test-fast`,
   and `bin/verify`, then publish and collect exact-head hosted evidence.

## Verification

- focused `router_integration_native_test.dart` regression
- `dart analyze packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-08: Source audit found that modern request-scoped SSE opens the
  native response stream before encoding and writing its acknowledgment.
  Unlike buffered JSON, compatibility POST/SSE, and compatibility GET/SSE,
  this path does not consult `max_response_bytes`; a large request ID or
  granted filter can therefore exceed the route response policy immediately.
  The public client already treats `maxResponseBytes` as a per-complete-event
  bound for long-lived listeners, so the router will enforce the matching
  server-side boundary without imposing a lifetime stream limit.
- 2026-08-08: Complete pre-change `bin/test-fast` passed before adding the
  regression or changing implementation. It covered 360 Dart core tests, all
  96 MCP tests, the complete 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, every generated and globally activated
  consumer smoke, and the focused native/router follow-ups.
- 2026-08-08: The fail-first native regression constructed a 4096-byte JSON
  acknowledgment whose exact `data: ...\n\n` SSE encoding required 4104
  bytes. The router admitted the listener, confirming that the route policy
  did not cover modern SSE framing.
- 2026-08-08: The router now encodes and bounds the acknowledgment before
  opening the native stream, releases listener and dynamic-resource
  preparation ownership on rejection, reuses the accepted encoding, and
  applies the same per-event check to established notifications and graceful
  completion. An oversized later event closes only that listener. Focused
  native regressions prove pre-stream HTTP `500`, capacity recovery, bounded
  graceful-close containment, sessionless state, and same-client direct JSON
  reuse; router analysis passes.
- 2026-08-08: Post-change `bin/test-fast` passed. It covered 360 Dart core
  tests, all 96 MCP tests, the complete 280-case MCP/client suite, all 96
  benchmark cases including 36 live WAMP workloads, every generated and
  globally activated consumer smoke, the router CLI lifecycle matrix, and the
  focused native/router follow-ups.
- 2026-08-08: Final exact-code `bin/verify` passed with zero formatting
  changes. It covered 114 Rust core tests plus serializer integrations, 52
  Rust FFI tests plus the focused metrics check, 360 Dart core tests, all 96
  MCP tests, the complete 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, all 395 router tests, the 6-case
  remote-auth process, the 13-case native follow-up, every generated and
  globally activated consumer smoke, and Chrome/Dart2Wasm.

## Handoff

- Publish the verified implementation and collect exact-head hosted deployment
  evidence.
