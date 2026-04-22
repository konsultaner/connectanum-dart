## Goal

Extend the shared Dart/native WAMP E2EE provider lane with richer per-message
runtime context so providers can make policy and key-selection decisions from
message family, URI/topic/procedure, session auth identity, negotiated E2EE
state, and disclosed peer metadata without adding router-side decryption.

## Scope

- add a runtime context value object to the core E2EE provider contract
- preserve that context across lazy/materialized payload views
- attach session + message metadata on outbound `CALL` / `PUBLISH`
- attach session + message metadata on inbound `RESULT` / `EVENT` /
  `INVOCATION`, including pending-call procedure context and disclosed peer
  details when available
- keep the current Dart and native providers behaviorally compatible unless a
  caller explicitly inspects the new context

## Non-goals

- router-side payload decryption
- new cipher or serializer support
- changing the negotiated `authextra.e2ee` wire shape
- moving key-selection logic into `connectanum_core`

## Verification

- `bin/test-fast`
- focused Dart tests for context propagation on outbound publish and inbound
  call/invocation flows
- `bin/verify`

## Status

- completed

## Handoff

- The next E2EE slice should be policy-aware providers that actually consume
  the new runtime context for key selection and enforcement, not more transport
  plumbing.
