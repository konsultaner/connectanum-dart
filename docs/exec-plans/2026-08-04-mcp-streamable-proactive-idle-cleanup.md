# Exec Plan: MCP Streamable Proactive Idle Cleanup

## Status

Active.

## Goal

Make the router-hosted compatibility-session timeout release endpoint state and
WAMP subscriptions without requiring a later MCP request to trigger the lazy
expiry sweep. A quiet router must not retain an abandoned Streamable HTTP
session indefinitely.

## Scope

- Arm an endpoint-owned idle deadline only for compatibility endpoints with an
  MCP session identifier and a non-zero configured timeout.
- Reset the deadline when valid session traffic reaches the endpoint.
- Remove an expired endpoint only when it is still the current map owner, then
  dispose its resource and WAMP subscriptions.
- Retain request-time expiry checks as a race-safe fallback so stale session
  identifiers still receive `404`.
- Cancel expiry work during explicit DELETE, internal-session teardown, router
  shutdown, and disabled-timeout operation.
- Prove autonomous subscription cleanup through a router state snapshot,
  without sending another MCP request to trigger expiry, then prove stale-client
  recovery and replacement initialization.

## Non-Goals

- Change the 600000 millisecond default or the existing route option names.
- Add session state to modern `2026-07-28` or direct JSON requests.
- Add durable cross-process session persistence.
- Change bearer, OAuth, or router-issued grant behavior.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first native-router regression observed through the router state store,
  independently of MCP request dispatch.
- Focused synthetic activity-reset, disabled-timeout, stale-session recovery,
  and native subscription-cleanup tests.
- Dart formatting and targeted analysis.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected immediately after bounded session idle expiry landed.
  The shipped implementation removes expired endpoints only from later MCP
  lookup/removal paths, so an abandoned session and its subscriptions can
  remain indefinitely when the route receives no further MCP traffic. The next
  checkpoint closes that production-correctness gap without changing modern or
  direct JSON lifecycle semantics.
- 2026-08-04: Pre-change `bin/test-fast` passed. The fail-first checkpoint now
  observes the abandoned subscription through the router state store, so the
  assertion cannot accidentally invoke the existing MCP request-time expiry
  sweep.
- 2026-08-04: The focused native regression failed before implementation with
  one subscriber still present after the deadline, confirming that the current
  request-time sweep leaves quiet sessions resident.
- 2026-08-04: Each compatibility endpoint now owns a cancellable idle timer.
  Activity rearms the timer, expiry removes only the identical current map
  owner before idempotent disposal, and request-time sweeping remains as a
  fallback. Focused native cleanup/stale recovery and synthetic activity-reset
  plus disabled-timeout tests pass, as does targeted analysis.
- 2026-08-04: Full `bin/verify` passed, including formatting, Rust/native FFI,
  all 382 router cases, 96 benchmark cases with live WAMP workloads, package
  and CLI consumer smokes, native-forwarding follow-ups, and Chrome/Dart2Wasm.
  Exact-head hosted evidence and the strict deployment-chain audit remain
  pending.
