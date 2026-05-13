# Exec Plan: e2ee-session-provider-lane

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Add a public session-scoped E2EE provider resolver on the Dart client path so a
session can derive its actual `WampE2eeProvider` from negotiated/authenticated
runtime state instead of only from a static `Client.e2eeProvider`.

## Scope

- In scope:
  - Add a client/session-facing resolver context for session-scoped E2EE
    provider creation.
  - Keep the existing static `Client.e2eeProvider` path working as the fallback
    and compatibility surface.
  - Resolve the provider after `WELCOME`, then feed it through the existing
    negotiated-defaults wrapper for outbound and inbound `ppt_scheme = "wamp"`
    payloads.
  - Add focused client tests for resolver-backed outbound encryption and native
    direct inbound decryption on the negotiated contract.
- Out of scope:
  - Router-side E2EE handling or payload decryption.
  - `ct_ffi` keyring/session handles or native encrypt/decrypt parity.
  - New cipher/serializer support beyond `wamp` + `cbor` +
    `xsalsa20poly1305`.

## Files Expected To Change

- `packages/connectanum_client/lib/src/client.dart`
- `packages/connectanum_client/lib/src/protocol/session.dart`
- `packages/connectanum_client/test/client_test.dart`
- `docs/project_state.md`
- `docs/e2ee_ppt_research.md`
- `ROADMAP_NEXT.md`
- `docs/exec-plans/2026-04-22-e2ee-session-provider-lane.md`

## Preconditions

- `bin/test-fast` is green before changing the session E2EE contract.
- The new resolver must not break existing callers that only use
  `Client.e2eeProvider`.

## Plan

1. Add a public resolver context and client/session configuration surface for
   session-scoped E2EE provider creation.
2. Resolve the provider after `WELCOME`, fall back cleanly to the existing
   static provider, and keep negotiated runtime defaults layered on top of the
   resolved provider.
3. Add focused coverage for resolver-backed outbound and inbound WAMP E2EE
   flows, then refresh docs/state and run `bin/verify`.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_client/test/client_test.dart -r expanded`
- `bin/verify`

## Decision Log

- 2026-04-22: Keep the new lane on the client/session boundary so future native
  parity can plug in without changing router trust boundaries.
- 2026-04-22: Preserve `Client.e2eeProvider` as the compatibility fallback and
  layer the new resolver on top of it rather than replacing it.

## Handoff

- Landed: `Client.e2eeProviderResolver` and `SessionE2eeProviderContext` now
  let the Dart client resolve a concrete `WampE2eeProvider` per session from
  authenticated/negotiated runtime state after `WELCOME`.
- Landed: the resolved provider remains compatible with the existing
  negotiated-defaults wrapper, so resolver-backed sessions cover both outbound
  and inbound `ppt_scheme = "wamp"` flows without router changes.
- Next: add `ct_ffi` keyring/session handles and native encrypt/decrypt parity
  on top of this session-provider contract.
