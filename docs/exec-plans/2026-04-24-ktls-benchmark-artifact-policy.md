# Exec Plan: kTLS Benchmark Artifact Policy

Status: in_progress
Owner: Codex
Created: 2026-04-24
Last updated: 2026-04-24

## Goal

Keep the branch CI chain clean by making the manual `kTLS HTTP/2 Benchmarks`
workflow validate against a scenario-specific artifact policy instead of the
generic zero-counter transport gate, while preserving the stricter
correctness-oriented `kTLS Validation` workflow.

## Scope

- In scope:
  - add a checked-in artifact-gate policy for
    `native/bench/scenarios/h2_ktls_benchmark.toml`
  - wire `bin/ktls-http2-bench` to use that policy during both baseline and
    required-kTLS passes
  - add focused native/bench regression coverage for thread-scoped policy
    matching
  - refresh the kTLS docs/state so the manual workflow contract is explicit
- Out of scope:
  - changing the benchmark workloads or transport implementation
  - weakening `kTLS Validation` or push `CI` correctness coverage
  - broader kTLS performance tuning beyond restoring a meaningful hosted
    comparison run

## Files Expected To Change

- `bin/ktls-http2-bench`
- `native/bench/artifact_gate/h2_ktls_benchmark.json`
- `native/bench/src/artifacts.rs`
- `native/bench/README.md`
- `docs/ktls_research.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-24-ktls-benchmark-artifact-policy.md`

## Preconditions

- `bin/test-fast` passed on 2026-04-24 before this slice.
- Hosted push validation is green through commit `f2b5fe8` on `add-router`:
  `CI` run `24864087129`, `kTLS Validation` run `24864087126`, and
  `WAMP Profile Benchmarks` run `24864087127` all completed successfully.
- Manual workflow run `24864760931` (`kTLS HTTP/2 Benchmarks`) completed both
  comparison passes and uploaded artifacts, but failed because the generic
  zero-counter gate flagged expected `backpressure_events` /
  `backpressure_alerts` in `h2_multiplexed_streams`.

## Plan

1. Add a scenario-specific `h2_ktls_benchmark` artifact policy and wire the
   manual comparison helper to use it.
2. Add focused regression coverage so thread-scoped policy selection stays
   pinned in `native/bench`.
3. Revalidate with targeted native/bench checks plus `bin/verify`, then push
   and rerun the hosted manual workflow on the new head.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml artifact_gate_policy_allows_thread_scoped_thresholds -- --nocapture`
- `bash -n bin/ktls-http2-bench`
- `bin/verify`

## Decision Log

- 2026-04-24: The manual kTLS HTTP/2 comparison workflow is diagnostic and
  performance-oriented. Treating any non-zero backpressure counter as a hard
  failure makes the workflow red even when both comparison passes complete and
  publish usable artifacts, so it needs a scoped scenario policy rather than
  the generic zero-counter default.

## Handoff

- In progress on 2026-04-24.
- The repo-side harness change is staged locally; the remaining work is local
  verification, commit/push, and a fresh hosted manual rerun to confirm the
  branch is green again.
