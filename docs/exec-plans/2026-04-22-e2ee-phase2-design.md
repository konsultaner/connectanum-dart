# Exec Plan: e2ee-phase2-design

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Capture the phase-2 design for WAMP E2EE so the next implementation work has a
clear contract for:

- native/off-Dart encrypt/decrypt parity
- backward-compatible `HELLO` / `CHALLENGE` / `AUTHENTICATE` / `WELCOME`
  negotiation
- router/client/native trust boundaries

## Scope

- In scope:
  - Extend `docs/e2ee_ppt_research.md` with the phase-2 architecture.
  - Define the recommended handshake metadata shape using the repo's existing
    auth message surfaces.
  - Refresh `docs/project_state.md` and `ROADMAP_NEXT.md` so the next session
    does not rediscover the same design task.
- Out of scope:
  - Runtime implementation changes.
  - Rust-native encrypt/decrypt parity.
  - New wire-format support beyond the existing CBOR +
    `xsalsa20poly1305` phase-1 baseline.

## Files Changed

- `docs/e2ee_ppt_research.md`
- `docs/project_state.md`
- `ROADMAP_NEXT.md`
- `docs/exec-plans/2026-04-22-e2ee-phase2-design.md`

## Verification

- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-04-22: The packaging/release prerequisite is now satisfied, so the next
  E2EE milestone can move from “whether” to “how”.
- 2026-04-22: The repo already exposes the right negotiation surfaces through
  `HELLO.details.authextra`, `CHALLENGE.extra`, `AUTHENTICATE.extra`, and
  `WELCOME.details.authextra`; phase 2 should use one optional `e2ee` object
  inside those maps rather than inventing new top-level WAMP fields.
- 2026-04-22: Native parity should accelerate client-boundary crypto only. The
  router remains a blind forwarder of ciphertext plus `ppt_*` metadata.

## Handoff

- The next implementation slice is negotiation metadata pass-through plus a
  contextual client-side E2EE runtime contract.
- Do not implement Rust-native crypto before the negotiated session contract is
  exercised on the Dart path end-to-end.
