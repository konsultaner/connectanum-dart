## Goal

Add policy-aware key-selection surfaces to the shared WAMP E2EE provider lane
so both the pure Dart and native providers can choose `ppt_keyid` from
`WampE2eeRuntimeContext` instead of relying only on explicit message options,
negotiated defaults, or one provider-wide fallback key.

## Scope

- add a small provider-level key-selection policy hook to
  `connectanum_core`
- wire that hook into `WampCborXsalsa20Poly1305Provider`
- mirror the same hook in
  `NativeWampCborXsalsa20Poly1305Provider`
- add focused tests that prove runtime-context-driven key selection works on
  the direct provider APIs and through the client session path

## Non-goals

- router-side payload decryption
- new cipher or serializer support
- changing the FFI wire format or adding router/native policy callbacks
- replacing negotiated session defaults; this slice only adds a more specific
  provider-level override surface

## Verification

- `bin/test-fast`
- focused Dart tests for direct provider and client-session key selection
- `bin/verify`

## Status

- completed

## Handoff

- The next E2EE step is broader policy enforcement: negotiated descriptor
  validation, per-peer trust constraints, and rotation-friendly policy adapters
  on top of the new key-selection hook.
