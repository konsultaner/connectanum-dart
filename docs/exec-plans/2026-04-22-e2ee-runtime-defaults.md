# Exec Plan: e2ee-runtime-defaults

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Thread negotiated `WELCOME.authextra.e2ee` state into the Dart client runtime
so outbound and inbound `ppt_scheme = "wamp"` payloads can default their
serializer, cipher, and key ids from the active session instead of requiring
fully out-of-band per-message configuration.

## Scope

- In scope:
  - Add a session-scoped E2EE runtime wrapper on the Dart client path.
  - Use negotiated session defaults for outbound and inbound WAMP E2EE payloads
    when a provider is attached.
  - Add focused client tests that prove negotiated defaults drive encryption and
    decryption on the live session path.
- Out of scope:
  - Router-side decryption or key distribution changes.
  - `ct_ffi` native keyring or encrypt/decrypt parity.
  - New E2EE ciphers or serializers beyond `wamp` + `cbor` +
    `xsalsa20poly1305`.

## Files Expected To Change

- `packages/connectanum_client/lib/src/protocol/session.dart`
- `packages/connectanum_client/test/client_test.dart`
- `docs/project_state.md`
- `docs/e2ee_ppt_research.md`
- `ROADMAP_NEXT.md`
- `docs/exec-plans/2026-04-22-e2ee-runtime-defaults.md`

## Preconditions

- `bin/test-fast` is green before changing the session runtime contract.
- Existing `WampE2eeProvider` behavior stays explicit: negotiated defaults may
  fill serializer, cipher, and key ids, but they must not silently turn
  plaintext messages into `ppt_scheme = "wamp"` messages.

## Plan

1. Check in this active plan and point `docs/project_state.md` at it.
2. Add a session-scoped provider wrapper that applies negotiated outbound and
   inbound defaults before delegating to the configured `WampE2eeProvider`.
3. Add focused client coverage, refresh the E2EE docs/state, run `bin/verify`,
   and checkpoint the runtime-defaults slice.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_client/test/client_test.dart -r expanded`
- `bin/verify`

## Decision Log

- 2026-04-22: Keep negotiated defaults client-side and session-scoped so the
  router remains blind to payload contents and native parity can target the same
  contract later.
- 2026-04-22: Do not infer `ppt_scheme = "wamp"` from session negotiation
  alone; only apply defaults after the caller or inbound message has already
  selected the WAMP E2EE mode.

## Handoff

- Landed: session-scoped negotiated defaults now wrap attached
  `WampE2eeProvider` instances on the Dart client path, and focused client
  regressions cover both outbound defaulting and inbound native direct-result
  decrypts.
- Landed: the final verify pass also required stabilizing the `ct_ffi`
  HTTP/2 and HTTP/3 body-timeout regressions so they reliably test total-body
  timeout behavior under full-suite load.
- Next: use the same negotiated contract for a session-backed or native-backed
  provider lane before attempting `ct_ffi` keyring/session parity.
