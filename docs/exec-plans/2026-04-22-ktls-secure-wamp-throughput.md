# Exec Plan: ktls-secure-wamp-throughput

Status: in_progress
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Promote secure WAMP TLS coverage from smoke-only validation to a throughput-grade
benchmark so the repo has a repeatable baseline for secure RawSocket and secure
WebSocket performance on the same harness that already measures cleartext WAMP.

## Scope

- In scope:
  - Add a throughput-grade secure WAMP scenario that mirrors the existing
    large-payload WAMP transport sweep.
  - Validate that the new scenario parses and runs locally on the current macOS
    environment.
  - Capture the first local secure-WAMP throughput baseline in checked-in docs.
  - Refresh `docs/project_state.md` after the baseline is recorded.
- Out of scope:
  - New transport/runtime behavior changes beyond what is needed to support the
    benchmark scenario.
  - Hosted Linux performance tuning or kTLS transport changes.
  - Reworking the generic HTTP/2 benchmark helpers.

## Files Expected To Change

- `native/bench/scenarios/wamp_secure_throughput.toml`
- `native/bench/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-secure-wamp-benchmarks.md`
- `docs/exec-plans/2026-04-22-ktls-secure-wamp-throughput.md`

## Preconditions

- Commit `0b4f1e7` is the current local baseline.
- GitHub Actions run `24785214332` (`kTLS Validation`, `workflow_dispatch`)
  passed on `0b4f1e7`, confirming the secure WAMP smoke path on hosted Linux.
- GitHub Actions run `24785189137` (`CI`) passed on `0b4f1e7`.
- `bin/verify` is green on the current tree before adding the new benchmark
  scenario.

## Plan

1. Add a secure throughput scenario that mirrors
   `native/bench/scenarios/wamp_transport_throughput.toml` but routes through
   the TLS WAMP listener and `bench.secure` ticket auth.
2. Run the native bench orchestrator locally against that scenario and capture
   the first secure throughput numbers.
3. Refresh the checked-in state docs and decide whether the next step should be
   a hosted Linux throughput run or benchmark tuning.

## Verification

- `python3` `tomllib` parsing for the new scenario
- Local `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --scenario native/bench/scenarios/wamp_secure_throughput.toml`
- `bin/verify`

## Decision Log

- 2026-04-22: The secure-WAMP smoke milestone is complete after hosted runs
  `24785214332` (`kTLS Validation`) and `24785189137` (`CI`) passed on
  commit `0b4f1e7`.
- 2026-04-22: The next missing piece is performance characterization; secure
  WAMP currently has only smoke coverage while cleartext WAMP already has a
  throughput-grade matrix.
- 2026-04-22: The first local throughput run exposed that the direct
  orchestrator default `https://localhost:8080/bench` can hit the wrong socket
  on this macOS host; the CLI now defaults to
  `https://127.0.0.1:8080/bench`, which matches the shipped bench router's
  IPv4 TLS listener and makes direct local runs work without an override.

## Handoff

- This plan assumes the secure transport-selection and certificate-handling
  fixes are done; the next work is measurement, not more transport debugging.
- If the throughput scenario cannot complete locally, capture the failing
  workload and stop at the minimal repro before changing harness behavior.
