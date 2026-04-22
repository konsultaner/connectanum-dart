# Exec Plan: ktls-research-spike

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Capture a concrete, source-backed implementation and benchmark plan for Linux
kTLS in the native transport so the next milestone can start from a bounded
prototype instead of open-ended exploration.

## Scope

- In scope:
  - Check the current `ct_core` TLS stack against Linux kTLS prerequisites.
  - Record the exact repo-local blockers for a Linux-only prototype.
  - Define the benchmark order and the current benchmark gaps.
  - Update `docs/project_state.md` so the next session resumes from the
    research checkpoint.
- Out of scope:
  - Shipping a working kTLS runtime path.
  - Changing router configuration shape.
  - Benchmarking on non-Linux hosts.
  - QUIC / HTTP/3 TLS offload work.

## Files Expected To Change

- `docs/ktls_research.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`

## Preconditions

- `bin/test-fast` is green before landing the docs checkpoint.
- The current native TLS path remains `rustls` + `tokio-rustls`; no new runtime
  dependencies are introduced in this spike.

## Plan

1. Confirm the current TLS/runtime baseline in `ct_core`, including where
   `tokio-rustls` handshakes are created and how accepted/connected streams are
   wrapped into `IoStream`.
2. Check primary-source Linux and Rust docs for kTLS handoff requirements,
   especially handshake ownership, key-update handling, and kernel/runtime
   compatibility.
3. Check in the research note and refresh `docs/project_state.md` with the
   resulting next-step implementation order and benchmark plan.

## Verification

- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-04-22: Treat this as a research spike rather than an implementation
  milestone because the current repo has no kTLS dependency, no secret
  extraction enabled in the TLS configs, and no Linux-only benchmark baseline
  recorded yet.
- 2026-04-22: Prefer the modern `dangerous_into_kernel_connection()` path in
  follow-on implementation work rather than the older
  `dangerous_extract_secrets()` helper, because the latter does not cover
  session tickets or TLS key updates.
- 2026-04-22: Start benchmarking with the existing HTTPS / HTTP/2 harness
  before adding secure WAMP listeners, because QUIC / HTTP/3 is out of scope
  for kTLS and the repo already ships a TLS-enabled HTTP bench path.

## Handoff

- `docs/ktls_research.md` now captures the Linux-only feasibility result, the
  current repo-local blockers, the recommended implementation order, and the
  benchmark plan.
- The next concrete milestone is a Linux-only kTLS prototype behind graceful
  fallback to the existing `tokio-rustls` path when kernel or cipher
  prerequisites are not met.
- The benchmark order is now explicit: HTTPS / HTTP/2 first on Linux, then
  secure RawSocket / WebSocket once the bench router grows a TLS WAMP listener.
