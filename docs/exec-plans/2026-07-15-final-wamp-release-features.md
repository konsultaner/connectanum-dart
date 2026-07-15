# Exec Plan: Final WAMP Release Features

## Status

Complete.

## Goal

Complete the remaining WAMP capabilities required for the final release:
progressive call invocations, call timeouts, routed Meta APIs needed for
operational statistics, and production-ready payload end-to-end encryption.

## Release Contract

- Progressive invocation callers reuse one `CALL.Request` ID, finish with a
  non-progressive chunk, and freeze all initiating options except `progress`.
- Dealers pin every chunk to the initially selected callee and reject invalid
  capability/state transitions without leaking pending invocations.
- Dealer-owned call timeouts use milliseconds, return `wamp.error.timeout`,
  cancel pending callees, and reset between progressive results where required
  by the current Advanced Profile draft.
- `REGISTER.Options.forward_timeout` allows a capable callee to own timeout
  handling; Dealer-owned timeout remains the safe default.
- The router serves the standard statistics-oriented Session, Registration,
  and Subscription Meta API read procedures and Registration/Subscription
  lifecycle events in the caller's realm, subject to realm authorization and
  visibility rules. It announces only the Meta API feature groups whose full
  advertised contract is implemented.
- Payload E2EE remains router-opaque and uses a versioned Connectanum profile
  over standard WAMP PPT fields. Release support includes CBOR,
  XSalsa20-Poly1305, AES-256-GCM, deterministic key selection/rotation rules,
  Dart/native parity, and explicit failure behavior. FlatBuffers is not part of
  this release because the workspace has no FlatBuffers serializer.

## Work Slices

1. Port the already-tested routed read-only Meta API implementation from the
   post-RC branch, reconcile it with current authorization/state APIs, add
   lifecycle meta events, and enable feature announcements only after routed
   integration tests pass.
2. Add core wire fields and client/router state for progressive call
   invocations, including repeated-request handling, callee pinning, option
   freezing, cancellation/disconnect cleanup, mixed serializers, and public
   caller/callee APIs.
3. Add Dealer and optional Callee timeout lifecycles, timer cleanup, progressive
   result inactivity semantics, cancellation interaction, metrics, and
   deterministic tests with short controlled durations.
4. Define and implement the release E2EE profile, add AES-256-GCM and key
   rotation support in Dart and native providers, validate negotiation and PPT
   capability combinations, and add interop/negative/benchmark evidence.
5. Extend the canonical WAMP benchmark gate with progressive invocation,
   timeout-control, Meta API, and encrypted RPC/pub/sub workloads plus explicit
   budgets and hosted evidence.

## Verification

- Run `bin/test-fast` before substantial implementation.
- Add a failing focused regression before each behavior change.
- Run focused core, client, router, native, conformance, and benchmark tests per
  slice.
- Run package analysis, formatting, public-artifact checks, and
  `bin/verify` before each implementation handoff.
- Push implementation/config/benchmark-sensitive commits only with their
  project-state evidence, then watch the GitHub deployment chain and run the
  strict audit when release evidence changes.

## Progress

- 2026-07-15: User confirmed all four capabilities as final-release
  requirements.
- 2026-07-15: Current WAMP Advanced Profile draft reviewed. Progressive
  invocation and timeout wire/state rules are usable but alpha; the E2EE
  chapter remains unspecified, so the release must document a versioned
  Connectanum crypto profile over the standardized PPT fields.
- 2026-07-15: Pre-change `bin/test-fast` passed on the existing profile-audit
  worktree.
- 2026-07-15: Located commit `c474136` on the post-RC branch containing a
  tested routed read-only Meta API implementation suitable for porting; it is
  not an ancestor of `add-router` and must be reconciled rather than blindly
  cherry-picked.
- 2026-07-15: Completed the routed statistics Meta API slice with all fifteen
  Session, Registration, and Subscription read procedures, stable creation
  timestamps, authorization-aware visibility, and all ten Registration and
  Subscription lifecycle events. Live WebSocket consumer tests verify the
  standard positional wire shapes and event ordering.
- 2026-07-15: Dealer `registration_meta_api` and Broker
  `subscription_meta_api` announcements are enabled after verification.
  `session_meta_api` remains disabled because the broader Session Meta API
  administration contract includes destructive `kill*` procedures that are
  not part of the statistics requirement and are not implemented.
- 2026-07-15: Post-slice `bin/test-fast` passed, including router-hosted MCP,
  direct JSON, Streamable HTTP, authentication, pub/sub, Meta API, package
  consumer, and router CLI smoke coverage.
- 2026-07-15: Completed progressive call invocations across core wire models,
  the public client API, router worker and internal sessions, native metadata,
  mixed serializers, cancellation cleanup, and live WebSocket routing. The
  Dealer pins the original callee and invocation ID, freezes initiating
  options, and accepts repeated `CALL.Request` IDs until the final chunk.
- 2026-07-15: Completed Dealer-owned and Callee-forwarded call timeout
  lifecycles. Dealer timers return `wamp.error.timeout`, interrupt the callee
  with `killnowait`, reset on progressive results, and use atomic completion
  claims to avoid result/timeout races. `forward_timeout` transfers inactivity
  timeout ownership to the client responder, including native invocation
  metadata and progressive-result resets.
- 2026-07-15: Full core (344 tests), serialized client (254 tests), router
  (373 tests with 13 environment skips), focused Rust FFI metadata, native
  binding, and live cross-serializer WebSocket suites passed. Post-feature
  `bin/test-fast` also passed, including package-consumer, router-hosted MCP,
  and live WAMP transport smoke coverage.
- 2026-07-15: Completed the versioned Connectanum v1 payload E2EE profile over
  standard PPT fields. Release support includes CBOR,
  XSalsa20-Poly1305/AES-256-GCM, negotiated and policy-driven key selection and
  rotation, pure Dart and native providers, router-opaque forwarding, and
  fail-closed validation of unsupported or inconsistent combinations.
- 2026-07-15: Live E2EE RPC/pub-sub correctness coverage passed, and the new
  sixteen-row `wamp_e2ee_throughput.json` policy gate passed across
  RawSocket/WebSocket, Dart/native clients, and both release ciphers. Response
  throughput was 1.77-13.90 Mbps with 262.73-2824.47 ms p95 latency.
- 2026-07-15: A minimal live native-client regression exposed a progressive
  invocation fast-path defect: native metadata carried `progress`, but the
  lazy invocation object did not. Propagating the metadata flag into
  `LazyInvocationPayload.progress` restored all chunks; the focused client
  unit test and all 26 live WAMP transport integration tests pass.
- 2026-07-15: The new twelve-row
  `wamp_final_release_features.json` policy gate passed for progressive
  invocation, a 50 ms timeout lifecycle, and all fifteen statistics Meta API
  procedures over RawSocket/WebSocket with Dart/native clients. Progressive
  p95 was 8.12-25.41 ms, timeout p95 was 55.38-59.49 ms, full Meta sweep p95
  was 11.17-33.22 ms, and all transport/protocol/internal counters were zero.
- 2026-07-15: Full `bin/verify` passed after the final cross-serializer binary
  payload regressions. The run covered formatting, Rust/FFI, all Dart packages,
  isolated package consumers, live router-hosted MCP and benchmark workloads,
  the complete 374-test router suite, and Chrome/Dart2Wasm WebSocket coverage.
  The implementation was committed as `232018a` and pushed to GitHub.
- 2026-07-15: Hosted WAMP Profile Benchmarks run `29415984452` exposed a native
  JSON client-binding defect in the mixed MessagePack-to-JSON E2EE pub/sub row:
  JSON WAMP binary sentinel strings were not restored to byte sequences before
  E2EE handling. The native binder now normalizes binary sentinels recursively
  for full and lazy payload fragments. Its focused 31-test suite, the complete
  canonical WAMP profile validator, and a second full `bin/verify` all pass.
  Replacement hosted deployment-chain evidence is pending after the correction
  is pushed.
