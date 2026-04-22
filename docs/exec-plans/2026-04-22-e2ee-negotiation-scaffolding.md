# Exec Plan: e2ee-negotiation-scaffolding

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Land the first runtime-facing phase-2 E2EE slice on the Dart path:

- preserve `authextra.e2ee` and `CHALLENGE.extra.e2ee` metadata end to end
- expose negotiated session E2EE state through the public client/session API
- keep the router and transport layers blind to payload contents

## Scope

- In scope:
  - Forward `Client.authExtra` into the actual `HELLO` handshake path.
  - Preserve unknown/custom `CHALLENGE.extra` fields across core serializers and
    native message binding.
  - Add a minimal typed negotiated-session E2EE view on `Session`.
  - Add focused tests for serializer, native binding, and client/session
    negotiation behavior.
- Out of scope:
  - Rust-native encrypt/decrypt or keyring parity.
  - New E2EE ciphers or serializers.
  - Router-side payload inspection.

## Files Expected To Change

- `packages/connectanum_core/lib/src/message/challenge.dart`
- `packages/connectanum_core/lib/src/serializer/json/serializer.dart`
- `packages/connectanum_core/lib/src/serializer/msgpack/serializer.dart`
- `packages/connectanum_core/lib/src/serializer/cbor/serializer.dart`
- `packages/connectanum_client/lib/src/client.dart`
- `packages/connectanum_client/lib/src/protocol/session.dart`
- `packages/connectanum_client/lib/src/transport/native/message_binding.dart`
- `packages/connectanum_core/test/*`
- `packages/connectanum_client/test/*`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-e2ee-negotiation-scaffolding.md`

## Preconditions

- `bin/test-fast` is green before changing the auth/session surfaces.
- The existing phase-1 E2EE provider contract remains the only encryption path;
  this slice is metadata and session-state scaffolding only.

## Plan

1. Check in this active plan and point `docs/project_state.md` at it.
2. Preserve handshake E2EE metadata on the Dart path:
   - forward `Client.authExtra` into `Session.start`
   - keep unknown/custom `CHALLENGE.extra` fields intact
   - expose negotiated `WELCOME.authextra.e2ee` through `Session`
3. Add focused regressions, run `bin/verify`, and refresh project state with
   the validated milestone status.

## Verification

- `bin/test-fast`
- Targeted serializer/client/native tests
- `bin/verify`
- `dart test packages/connectanum_core/test/custom_fields_test.dart packages/connectanum_core/test/serializer_challenge_welcome_test.dart -r expanded`
- `dart test packages/connectanum_client/test/client_test.dart packages/connectanum_client/test/transport/native/message_binding_test.dart -r expanded`

## Decision Log

- 2026-04-22: `HELLO.details.authextra` and `WELCOME.details.authextra` already
  preserve arbitrary maps, so the missing wire-shape work is primarily
  `CHALLENGE.extra` plus the public client/session handshake surface.
- 2026-04-22: The smallest defensible negotiated-session scaffold is a typed
  session view over `WELCOME.authextra.e2ee`, not a broader provider redesign.
- 2026-04-22: This slice should not invent router-side E2EE handling; the
  router remains a ciphertext forwarder.

## Handoff

- The next E2EE implementation step is to thread the negotiated session state
  into a richer client-side runtime/provider context before adding `ct_ffi`
  parity.
