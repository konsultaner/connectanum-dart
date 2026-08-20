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
- [x] Progressive chunked file delivery. The public progressive-call contract
  enforces bounded chunks, exact size, optional SHA-256, sink backpressure,
  concurrency/buffer limits, idle timeout, and cancellation cleanup. Linux
  cleartext native RawSocket MessagePack/CBOR sessions use `sendfile`-backed
  frame segments; transformed, masked, secure, non-Linux, and unsupported paths
  use bounded buffering.
- [x] Bounded retry deduplication. Public caller transaction hashes drive
  registration-scoped throttle or trailing-edge debounce policies with bounded
  capacity and expiry. Progressive chunks retain their original lease; all
  completion, cancellation, timeout, disconnect, unregister, expiry, and
  disposal paths release state. Hashes remain router-owned and are not sent to
  callees. OpenMetrics exposes active entries, rejects, replacements, capacity
  pressure, and expirations.
- [x] Negotiated large RawSocket frames. Standard peers remain on exponent 24,
  optional-upgrade prefetched data is preserved, and both Dart and Rust use the
  documented low-nibble exponent encoding. Local 32 MiB and 64 MiB Dart/native
  MessagePack/CBOR workloads pass.
- [x] Full local and hosted release evidence.

The focused analyzer, four cache regressions, live native-router WebSocket
integration, generated client consumer package, 117 Rust core tests, 52 Rust
FFI tests, Linux arm64 all-target compilation and `sendfile` loopback, file
smoke, large-frame throughput matrix, and post-change `bin/test-fast` pass on
2026-08-20. Full `bin/verify` also passes with the 457-test router suite, every
generated consumer smoke, and Chrome/Dart2Wasm coverage. Hosted Linux
throughput evidence remains before the evidence checkbox can close. The first
hosted diagnostic run revealed that inline protocol negotiation could
head-of-line block the listener when concurrent standard peers connected to an
extended endpoint. Negotiation is now backlog-bounded and concurrent; the exact
six-peer native CBOR workload fails before and passes after the fix in Linux
x86_64, with standard-peer fallback regressions and another full `bin/verify`
green locally. Exact-head hosted CI, package publication rehearsal, WAMP
diagnostics and canonical gates, router image/MCP smoke, and five-platform
signed native artifact rehearsal all pass. Hosted native file throughput is
610.0 Mbit/s for MessagePack and 398.0 Mbit/s for CBOR over the 1 GiB workload;
the native 32 MiB MessagePack frame reaches 637.6 Mbit/s one-way and 1.275
Gbit/s aggregate duplex. The complete deployment-content audit passes. Strict
mode is blocked only by the expected lack of protection on this development
branch, not by an exact-head evidence failure.

The retry-deduplication slice passes typed core option tests, eight focused
state-store lifecycle regressions, OpenMetrics and router-metric tests, a real
worker-session WAMP error/privacy regression, the complete 72-test
worker-session suite, and a generated standalone client consumer smoke. Full
`bin/verify` passes on 2026-08-20 with 466 router tests, all native suites,
consumer packages, live MCP checks, and Chrome/Dart2Wasm. Hosted exact-head
evidence for this final slice remains pending until push.
