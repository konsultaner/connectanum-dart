# Exec Plan: ktls-prototype

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Land the first Linux-only native kTLS prototype in `ct_core` behind an explicit
runtime opt-in, without widening the public router config surface before the
runtime path is validated on Linux.

## Scope

- In scope:
  - Add a Linux-only kTLS dependency path in `ct_core`.
  - Add an env-gated kTLS runtime toggle for the native TLS server path.
  - Enable Rustls secret extraction when the kTLS path is requested.
  - Add a post-handshake `IoStream` variant for Linux kTLS handoff.
  - Keep non-Linux hosts and non-opt-in runs on the current `tokio-rustls`
    path.
  - Refresh checked-in state/docs to describe the prototype and its remaining
    validation gap.
- Out of scope:
  - Expanding the Dart/router config model with a kTLS field.
  - Secure RawSocket / WebSocket benchmark coverage.
  - QUIC / HTTP/3 kTLS work.
  - Claiming Linux runtime success without Linux verification.

## Files Expected To Change

- `native/transport/ct_core/Cargo.toml`
- `native/transport/ct_core/src/lib.rs`
- `native/transport/ct_core/src/io_stream.rs`
- `native/transport/ct_core/src/tls.rs`
- `native/transport/ct_core/src/ktls.rs`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-prototype.md`
- `docs/ktls_research.md` if the implementation shape needs to be clarified

## Preconditions

- `bin/test-fast` is green before landing the prototype.
- Existing non-Linux verification stays green after the change.

## Plan

1. Add a Linux-only `ktls-stream` integration layer plus an env-gated runtime
   toggle so the default path remains `tokio-rustls`.
2. Thread Rustls secret extraction and Linux-only handoff through the accepted
   TLS server stream, while preserving the current path on hosts/runs where
   kTLS is unavailable or not requested.
3. Update the checked-in state with the prototype boundary, the exact opt-in
   contract, and the remaining Linux validation requirement.

## Verification

- `bin/test-fast`
- `bin/verify`
- If available, a Linux-target `cargo check` for the gated `ct_core` path

## Decision Log

- 2026-04-22: Keep the prototype env-gated instead of adding a public router
  config field before the Linux runtime path is validated.
- 2026-04-22: Scope the first implementation to the native TLS server path;
  outbound secure client connections can keep the existing userspace TLS path
  until the Linux benchmark path proves the server-side handoff is sound.
- 2026-04-22: Use `CONNECTANUM_ENABLE_KTLS=1` as the prototype opt-in so the
  default repo/runtime behaviour stays unchanged while Linux validation is
  still pending.

## Handoff

- This milestone landed one explicit opt-in path for Linux kTLS in `ct_core`,
  with non-Linux and default runs unchanged.
- The prototype is server-side only for now: accepted native TLS listeners with
  HTTP or HTTP/2 can attempt kTLS handoff when `CONNECTANUM_ENABLE_KTLS=1` is
  set on Linux.
- The expected follow-up is Linux validation and HTTP/2 benchmarking, then TLS
  WAMP listener expansion for secure RawSocket / WebSocket measurements.
