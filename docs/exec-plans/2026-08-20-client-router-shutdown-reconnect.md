# Exec Plan: Client Router-Shutdown Reconnect

Status: completed
Owner: Codex
Created: 2026-08-20
Last updated: 2026-08-20

## Goal

Make established Connectanum client sessions complete the WAMP `GOODBYE`
handshake and reconnect after a router announces
`wamp.close.system_shutdown`, so downstream applications receive a fresh
session and can recreate their registrations.

## Scope

- In scope:
  - handle router-initiated `GOODBYE` on established sessions;
  - reply with the standard `wamp.close.goodbye_and_out` reason;
  - reconnect only for `wamp.close.system_shutdown` when reconnects are
    configured;
  - emit one fresh `Session` and avoid duplicate reconnect scheduling;
  - reset per-connection transport closing state;
  - cover real WebSocket shutdown/reconnect behavior.
- Out of scope:
  - replaying registrations or subscriptions across sessions;
  - preserving router-assigned registration or session IDs;
  - changing application-specific registration supervision.

## Files Expected To Change

- `packages/connectanum_core/lib/src/message/goodbye.dart`
- `packages/connectanum_client/lib/src/protocol/session.dart`
- `packages/connectanum_client/lib/src/client.dart`
- `packages/connectanum_client/lib/src/transport/`
- `packages/connectanum_client/test/client_on_transport_io_events_test.dart`
- `packages/connectanum_client/CHANGELOG.md`
- `docs/project_state.md`

## Preconditions

- No unrelated Codex process is editing this repository.
- The working tree is clean at `ba6c0f48`.
- Pre-change `bin/test-fast` passes.
- A downstream application reproduction confirms that restarting only the
  router leaves the old client session without its registrations.

## Plan

1. Add a fail-first real-WebSocket regression for a router-initiated system
   shutdown.
2. Implement the established-session closing handshake and expose its reason
   to the client lifecycle.
3. Add selective, deduplicated reconnect handling and reset transport-local
   closing state when opening a new connection.
4. Run focused tests, `bin/verify`, local review, and update project state.

## Verification

- focused client WebSocket event tests
- focused core/client tests for WAMP closing reasons
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-20: WAMP removes registrations with the old session; reconnecting
  creates a new session and applications must register again on that emitted
  session. Connectanum must not replay stale router-assigned registration IDs.
- 2026-08-20: Treat only `wamp.close.system_shutdown` as recoverable. Realm
  closure, administrative termination, and application-initiated closure stay
  terminal.

## Progress

- 2026-08-20: Serena preflight, overlap checks, official WAMP behavior review,
  downstream reproduction review, and pre-change `bin/test-fast` pass.
- 2026-08-20: Added a fail-first real WebSocket regression. Before the fix,
  the client replied to neither the router `GOODBYE` nor emitted a replacement
  session before the test timed out.
- 2026-08-20: Established sessions now complete the closing handshake, expose
  the peer reason, reconnect once for system shutdown, and stop for terminal
  reasons. Reused WebSocket and RawSocket transports reset connection-local
  closing state and isolate stale socket callbacks from replacement sockets.
- 2026-08-20: The regression passes two immediate shutdown/reconnect cycles,
  verifies three fresh sessions and three `goodbye_and_out` replies, then
  verifies `close_realm` ends the client without a fourth connection.
- 2026-08-20: Focused serializer and client lifecycle tests pass. Final
  `bin/test-fast` and `bin/verify` pass on Dart 3.13.1, including native/FFI,
  router, benchmark, consumer-package, remote-auth, and Chrome Dart2Wasm
  coverage. Local companion review identified the duplicate close-signal retry
  race; reconnect accounting is now guarded before options are decremented.

## Handoff

- Complete. Consumer applications should continue registering and subscribing
  whenever the client emits a fresh `Session`; no router-assigned IDs are
  retained across reconnects.
