# Exec Plan: e2ee-native-provider-parity

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Add the first native `ct_ffi` E2EE parity lane so the Dart client can resolve a
session-scoped provider backed by native key storage and native
encrypt/decrypt operations while keeping the router blind to payload contents.

## Scope

- In scope:
  - Add `ct_ffi` handle storage for native E2EE key material and
    session-default state.
  - Add synchronous FFI entrypoints for WAMP E2EE `xsalsa20poly1305`
    encrypt/decrypt over already-framed PPT bytes.
  - Add a Dart IO-only `WampE2eeProvider` adapter backed by the native runtime.
  - Keep the negotiated-session defaults contract on the Dart path and make the
    native provider compatible with `Client.e2eeProviderResolver`.
  - Add focused Rust and Dart coverage for native key lookup, default-key
    behavior, and native encrypt/decrypt interoperability.
- Out of scope:
  - Router-side payload decryption or key awareness.
  - New PPT serializers or ciphers beyond `wamp` + `cbor` +
    `xsalsa20poly1305`.
  - A new auth-handshake shape beyond the already-landed
    `authextra.e2ee` negotiation metadata.

## Files Expected To Change

- `native/transport/ct_ffi/Cargo.toml`
- `native/transport/ct_ffi/src/runtime/constants.rs`
- `native/transport/ct_ffi/src/runtime/ffi.rs`
- `native/transport/ct_ffi/src/runtime/state.rs`
- `native/transport/ct_ffi/src/tests/...`
- `packages/connectanum_client/lib/connectanum.dart`
- `packages/connectanum_client/lib/src/transport/native/ffi_bindings.dart`
- `packages/connectanum_client/lib/src/transport/native/runtime.dart`
- `packages/connectanum_client/lib/src/transport/native/e2ee_provider_io.dart`
- `packages/connectanum_client/lib/src/transport/native/e2ee_provider_none.dart`
- `packages/connectanum_client/test/...`
- `docs/project_state.md`
- `docs/e2ee_ppt_research.md`
- `ROADMAP_NEXT.md`
- `docs/exec-plans/2026-04-22-e2ee-native-provider-parity.md`

## Preconditions

- `bin/test-fast` is green before touching the native E2EE surface.
- The native provider must stay compatible with the existing pure-Dart
  provider contract and preserve explicit failure modes for missing keys,
  unsupported ciphers, malformed payloads, and decryption failures.

## Plan

1. Add native keyring/session handle storage in `ct_ffi` and expose minimal
   encrypt/decrypt entrypoints for WAMP E2EE ciphertext bytes.
2. Add a Dart native provider adapter that serializes the PPT envelope with the
   existing core framing, delegates crypto to `ct_ffi`, and plugs cleanly into
   `Client.e2eeProviderResolver`.
3. Add focused Rust and Dart regression coverage, then refresh docs/state and
   run `bin/verify`.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi -- --nocapture`
- `dart test packages/connectanum_client/test/client_test.dart -r expanded`
- `bin/verify`

## Decision Log

- 2026-04-22: Keep framing in Dart/core and move only key storage plus crypto
  into `ct_ffi` for the first parity slice so the FFI contract stays small and
  aligned with the existing `WampE2eeProvider` API.
- 2026-04-22: Use native keyring and session handles rather than one global
  native key map so the provider lane stays compatible with negotiated
  per-session defaults.

## Handoff

- Landed: `ct_ffi` now exposes native E2EE keyring/session handles and
  `xsalsa20poly1305` encrypt/decrypt entrypoints for already-framed PPT bytes.
- Landed: `connectanum_client` now exports
  `NativeWampCborXsalsa20Poly1305Provider`, and session teardown releases
  resolver-scoped native providers through the shared
  `DisposableWampE2eeProvider` contract.
- Next: extend the provider contract from negotiated session defaults to richer
  per-message runtime context for key selection and policy.
