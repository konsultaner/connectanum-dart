# Java Capability Successor Extensions

Status: active
Started: 2026-08-20

## Goal

Add the useful application-facing capabilities identified in the legacy Java
implementation without copying its protocol bugs or turning proprietary
behavior into an implicit WAMP compatibility claim:

- race-safe buffered state for the standard WAMP Session, Registration, and
  Subscription Meta APIs;
- high-level progressive file delivery with bounded chunking and lazy/native
  payload reuse where the transport permits it;
- bounded retry deduplication compatible with the legacy `transaction_hash`
  option and explicit throttle/debounce policies;
- an opt-in large RawSocket frame extension for trusted Connectanum peers.

Pattern-matching behavior from the Java implementation is explicitly excluded.

## Compatibility Boundaries

- The Meta cache uses only standard WAMP Meta API procedures and lifecycle
  topics. It subscribes before taking snapshots, queues lifecycle events while
  hydrating, and replays them in receive order before becoming live.
- File delivery is a high-level application contract layered over standard
  progressive RPC and Payload Passthru Mode. Peers without the helper can still
  implement the same procedure contract directly.
- Retry deduplication uses custom WAMP option/detail fields, which WAMP permits,
  but remains opt-in and bounded by capacity plus expiry. It must never use the
  Java implementation's unbounded process-lifetime maps.
- Frames beyond the standard RawSocket maximum are disabled by default and may
  only be used after explicit Connectanum peer negotiation. Standard peers
  continue to use the standard framing limit and high-level chunking.

## Plan

1. Make direct subscription handlers atomic with `SUBSCRIBED` processing, then
   implement immutable buffered Meta API snapshots and lifecycle updates.
2. Define and implement the progressive file-transfer sender/receiver contract,
   including checksum/size validation, cancellation, timeout, and bounded
   memory behavior across Dart and native transports.
3. Add caller transaction hashes and bounded callee-side retry deduplication
   with explicit reject, throttle, and debounce behavior plus eviction metrics.
4. Add explicit large-frame capability negotiation and guarded Dart/Rust
   RawSocket framing support, keeping the standard path unchanged.
5. Add focused interoperability, consumer-package, and benchmark evidence;
   update profile documentation and release state; run `bin/verify` and the
   strict hosted deployment audit when the implementation is pushed.

## Verification

- `bin/test-fast` before implementation slices
- focused client/core/router/native tests for each slice
- generated consumer-package smoke for every new public API
- standard-peer interoperability tests proving extensions remain off by default
- file throughput/memory and large-frame/chunked baseline scenarios
- `bin/verify` before handoff

## Progress

- [x] Router-shutdown reconnect prerequisite committed and pushed as `e6412b9b`.
- [x] Buffered standard WAMP Meta API client state. Direct subscription
  handlers are attached while `SUBSCRIBED` is processed; hydration subscribes
  to all ten standard lifecycle topics before bounded snapshot queries, replays
  queued events, tolerates `no_such_*` churn, deep-freezes snapshots, follows
  membership changes, and cannot hang cleanup after a session disconnect.
- [ ] Progressive chunked file delivery.
- [ ] Bounded retry deduplication.
- [ ] Negotiated large RawSocket frames.
- [ ] Full local and hosted release evidence.

The focused analyzer, four cache regressions, live native-router WebSocket
integration, and post-change `bin/test-fast` pass on 2026-08-20.
