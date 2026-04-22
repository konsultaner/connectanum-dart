# Exec Plan: ktls-secure-wamp-benchmarks

Status: in_progress
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Extend the existing benchmark harness so secure RawSocket and secure WebSocket
WAMP workloads can run on the same TLS-enabled Linux bench path that now works
for the HTTP/2 kTLS prototype.

## Scope

- In scope:
  - Add a TLS-enabled WAMP listener to the shipped bench router config.
  - Ensure the bench target-resolution path can deliberately select secure WAMP
    targets instead of always preferring the current cleartext listener.
  - Add at least one secure WAMP smoke/benchmark scenario that proves the new
    listener path works for the existing harness.
  - Refresh `docs/project_state.md` and related kTLS notes with the secure-WAMP
    benchmark contract.
- Out of scope:
  - Broad kTLS performance tuning beyond what is needed to get secure WAMP
    measurements running.
  - New non-WAMP transport benchmarks.
  - Declaring production-ready TLS 1.3 key-update handling on the kTLS path.

## Files Expected To Change

- `native/bench/bench_router.json`
- `native/bench/scenarios/*.toml`
- `packages/connectanum_bench/lib/src/wamp_transport_targets.dart`
- `packages/connectanum_bench/tool/bench_main.dart` and/or
  `packages/connectanum_bench/tool/wamp_client_main.dart` if secure-target
  selection needs to become explicit
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-secure-wamp-benchmarks.md`
- `docs/ktls_research.md` if the benchmark contract changes materially

## Preconditions

- The hosted HTTP/2 kTLS correctness milestone is already closed on commit
  `6d18344`.
- `bin/test-fast` is green before changing the bench path again.

## Plan

1. Add a TLS-enabled WAMP bench listener and confirm it advertises the same
   protocol and serializer surface the current WAMP bench scenarios need.
2. Make secure-target selection explicit in the bench runner so a secure WAMP
   benchmark does not silently fall back to the current higher-scored cleartext
   listener.
3. Add a secure WAMP smoke or benchmark scenario, run local verification, and
   then update the checked-in state before scheduling hosted Linux runs.

## Verification

- `bin/test-fast`
- Targeted bench-harness tests for secure WAMP target resolution
- `bin/verify`

## Decision Log

- 2026-04-22: The HTTP/2 kTLS prototype is now correct enough to shift from
  transport-handshake debugging to expanding benchmark coverage.
- 2026-04-22: The current bench target scorer prefers non-HTTP, non-secure
  listeners, so secure WAMP benchmarking needs an explicit selection path
  rather than relying on listener ordering.
- 2026-04-22: Used an explicit `secure_transport = true` workload flag instead
  of inventing a second secure-only WAMP protocol family, because the existing
  protocol names already describe the wire transport and serializer surface.
- 2026-04-22: Extended the shipped bench router config with a TLS WAMP listener
  on `127.0.0.1:8083` and aligned both the cleartext and TLS WebSocket
  listeners to advertise `wamp.2.json`, `wamp.2.msgpack`, and `wamp.2.cbor`.

## Handoff

- This plan starts with harness/config work, not more low-level kTLS handoff
  changes.
- After the secure WAMP path is running, the remaining question becomes
  hosted Linux validation and then performance characterization rather than
  basic TLS-path correctness.
