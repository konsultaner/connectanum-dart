# Exec Plan: e2ee-research-spike

Status: completed
Owner: Codex
Created: 2026-04-21
Last updated: 2026-04-22

## Goal

Define and then implement the first transport-neutral WAMP E2EE prototype on
top of the existing lazy-payload and payload-passthru contract, without
breaking current router/client forwarding behavior.

## Scope

- In scope:
  - capture the current spec/issues and repo constraints in checked-in docs
  - choose a phase-1 prototype boundary
  - add the runtime/provider plumbing needed for CBOR-based WAMP E2EE
  - add focused client/router/core tests for the first prototype
- Out of scope:
  - handshake-based key negotiation
  - flatbuffers support
  - Rust-native encrypt/decrypt parity
  - benchmark/reporting work before the Dart prototype exists

## Files Expected To Change

- `docs/e2ee_ppt_research.md`
- `docs/project_state.md`
- `packages/connectanum_core/lib/src/message/e2ee_payload.dart`
- `packages/connectanum_core/lib/src/message/abstract_message_with_payload.dart`
- `packages/connectanum_core/lib/src/message/invocation.dart`
- `packages/connectanum_core/test/message_result_test.dart`
- `packages/connectanum_core/test/message_invocation_test.dart`
- `packages/connectanum_core/test/message_e2ee_payload_test.dart`
- `packages/connectanum_client/lib/src/client.dart`
- `packages/connectanum_client/lib/src/protocol/session.dart`
- `packages/connectanum_client/lib/src/transport/native/message_binding.dart`
- `packages/connectanum_client/test/client_test.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- other focused config/test files needed for provider plumbing

## Preconditions

- The repo already carries the lazy-payload and PPT forwarding contract.
- `ppt_scheme = "wamp"` is already part of the public message/config surface.
- The first prototype should stay Dart-side and avoid new transport changes.

## Plan

1. Capture the current spec references, open WAMP issues, and repo constraints
   in a checked-in research note so the prototype boundary is explicit.
2. Add a runtime E2EE provider abstraction and an explicit failure surface for
   undecryptable encrypted payloads instead of silently materializing empty
   args/kwargs.
3. Implement CBOR + `xsalsa20poly1305` outbound packing and inbound unpacking
   for `ppt_scheme = "wamp"` on the Dart path.
4. Add focused client/router/core coverage, then run repository verification and
   refresh startup docs before closing the plan.

## Verification

- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `dart test packages/connectanum_client/test/client_test.dart`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart`
  - `dart test packages/connectanum_core/test/serializer/json/serializer_test.dart`

## Decision Log

- 2026-04-21: Chose the first prototype boundary to be transport-neutral,
  Dart-side, CBOR-only WAMP E2EE with an application-supplied key/provider
  abstraction. This matches the repo's current `ppt_scheme = "wamp"` guard and
  avoids protocol-extension work before the message-layer contract is proven.
- 2026-04-21: Deferred handshake-based key negotiation and router-assisted key
  distribution to later work, because the current roadmap item is explicitly a
  research/prototype spike and the relevant WAMP spec text is still unsettled.
- 2026-04-22: Landed the provider plumbing first instead of jumping straight to
  crypto implementation. `connectanum_core` now throws an explicit
  missing-provider exception for WAMP payload decode/pack, and the client
  threads an optional provider through outbound publish/call/yield paths plus
  native direct-result/event/invocation materialization without regressing lazy
  wrapped-byte passthrough.
- 2026-04-22: Completed the first Dart-side prototype with a built-in
  `WampCborXsalsa20Poly1305Provider`, explicit missing-key / unsupported-cipher
  / invalid-payload / decryption errors, provider-backed client tests, and
  router runtime assertions that `ppt_cipher` / `ppt_keyid` survive internal
  session forwarding without forcing router-side decrypts.

## Handoff

- This milestone is complete. `docs/e2ee_ppt_research.md` now captures the
  phase-1 boundary and the implementation outcome.
- The next coding session should choose a new milestone from `ROADMAP_NEXT.md`.
- If E2EE work resumes immediately, the remaining slices are handshake/key
  distribution, key rotation/discovery policy, or Rust/native parity; do not
  reopen the payload-layer contract that now has passing core/client/router
  coverage.
