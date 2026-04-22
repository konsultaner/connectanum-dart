# Exec Plan: ktls-http2-benchmarks

Status: in_progress
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Turn the validated Linux kTLS prototype into a reproducible benchmark milestone
by running the existing TLS HTTP/2 listener through the same sustained workload
both with normal userspace TLS and with kTLS required, then archiving a direct
comparison artifact.

## Scope

- In scope:
  - Add one focused HTTP/2-only benchmark scenario for the kTLS comparison.
  - Add a repo runner that executes baseline TLS and required-kTLS passes with
    the same bench inputs and emits a machine-readable plus human-readable
    comparison summary.
  - Add a manual GitHub Actions workflow for the Linux benchmark run and its
    artifacts.
  - Refresh checked-in state/docs with the benchmark contract and first hosted
    result.
- Out of scope:
  - New transport/runtime behavior changes in `ct_core`.
  - Secure RawSocket / WebSocket TLS benchmarks.
  - Claiming NIC-offload wins from hosted CI.

## Files Expected To Change

- `native/bench/scenarios/*.toml`
- `bin/common.sh` if shared helper logic is warranted
- `bin/*.sh` or a new `bin/*` benchmark entrypoint
- `.github/workflows/*.yml`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-http2-benchmarks.md`
- `docs/ktls_research.md` if the benchmark contract changes materially
- `native/bench/README.md` if the new runner needs explicit operator guidance

## Preconditions

- `bin/test-fast` is green before changing the benchmark path.
- The strict Linux validation workflow remains the gate for correctness; this
  milestone only adds comparative performance measurement on top.

## Plan

1. Check in this active plan and point `docs/project_state.md` at it.
2. Add a reproducible HTTP/2 comparison runner that executes the same workload
   with baseline TLS and required kTLS and writes a comparison artifact bundle.
3. Add a manual GitHub Actions workflow, run it on `add-router`, and update the
   checked-in state with the hosted benchmark result and remaining caveats.

## Verification

- `bin/test-fast`
- Local syntax/entrypoint checks for the new benchmark script and workflow
- `bin/verify`
- One hosted Linux run of the new HTTP/2 kTLS benchmark workflow on
  `add-router`

## Decision Log

- 2026-04-22: The next useful question is comparative HTTP/2 throughput and
  latency under the already-validated TLS listener, not more kTLS prototype
  expansion.
- 2026-04-22: The benchmark should compare baseline TLS and required kTLS under
  the same scenario because a single kTLS-only number is not actionable on its
  own.
