# Exec Plan: ktls-http2-benchmarks

Status: completed
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
  - Make focused `ct_core` kTLS-path adjustments when the hosted benchmark
    shows a concrete Linux blocker on the required-kTLS path.
  - Refresh checked-in state/docs with the benchmark contract and first hosted
    result.
- Out of scope:
  - Broad TLS/runtime refactors outside the required-kTLS HTTP/2 blocker.
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

## Current Status

- GitHub Actions run `24768909306` on Ubuntu 24.04 produced the first usable
  hosted benchmark artifact bundle for this milestone and identified the
  receive-path failure cluster on the required-kTLS path.
- Follow-up hosted runs `24772627167` (`kTLS HTTP/2 Benchmarks`) and
  `24772627180` (`kTLS Validation`) showed that the first unbuffered handoff
  patch regressed earlier in the flow with
  `received fatal alert: UnexpectedMessage` /
  `got ApplicationData when expecting Handshake`.
- The final hosted confirmation landed on commit `6d18344`:
  - `24773860109` (`CI`) passed
  - `24773860116` (`kTLS Validation`) passed
  - `24773860158` (`kTLS HTTP/2 Benchmarks`) passed
- The completed benchmark run confirmed that the earlier handshake regression
  and the older multiplexed `EINVAL` / `EMSGSIZE` / `unexpected frame type`
  failure cluster are gone.
- The remaining caveat is now performance rather than correctness. Required
  kTLS still underperforms baseline TLS in the hosted benchmark, especially in
  the 4-thread multiplexed HTTP/2 shape.
- `bin/ktls-http2-bench` now keeps writing per-pass summaries and the
  comparison files even when one pass exits non-zero, so future hosted runs
  remain diagnosable without manually reconstructing partial benchmark output.

## Decision Log

- 2026-04-22: The next useful question is comparative HTTP/2 throughput and
  latency under the already-validated TLS listener, not more kTLS prototype
  expansion.
- 2026-04-22: The benchmark should compare baseline TLS and required kTLS under
  the same scenario because a single kTLS-only number is not actionable on its
  own.
- 2026-04-22: Hosted run `24768800167` showed the buffered-plaintext handoff
  patch was directionally correct but exposed a Linux-only compile miss
  (`session` needed to stay mutable through `drain_buffered_plaintext`).
- 2026-04-22: Hosted run `24768909306` showed the buffered-plaintext handoff
  fix materially improved the required-kTLS path: single-stream HTTP/2 now
  completes, but multiplexed HTTP/2 still fails and remains the next blocker.
- 2026-04-22: The `24768909306` job log shows intermittent required-kTLS
  handshake failures before multiplexing is even involved, so the next bounded
  mitigation is to stop advertising TLS 1.3 session tickets on the dummy-server
  handoff path before attempting a deeper unbuffered-handshake refactor.
- 2026-04-22: The buffered `tokio-rustls` server handoff was no longer a
  defensible place to keep iterating once the hosted log showed receive-path
  `EINVAL` / `EMSGSIZE`, so the next bounded change switched the Linux kTLS
  accept path to rustls's unbuffered handshake and real kernel-connection API.
- 2026-04-22: Hosted runs `24772627167` and `24772627180` proved that the
  first unbuffered handoff patch still mishandled handshake bytes before the
  benchmark workload even started, so the next bounded fix had to buffer every
  unbuffered `EncodeTlsData` fragment and refuse kTLS conversion while partial
  post-handshake TLS record bytes remained buffered in userspace.
- 2026-04-22: Hosted runs `24773860109`, `24773860116`, and `24773860158`
  closed the milestone: the required-kTLS benchmark now completes end to end,
  so the next kTLS-specific task is secure WAMP TLS coverage and performance
  tuning rather than more HTTP/2 correctness debugging.
