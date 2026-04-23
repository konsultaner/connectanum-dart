# Exec Plan: Bench Artifact Performance Budgets

Status: completed
Owner: Codex
Created: 2026-04-23
Last updated: 2026-04-23

## Goal

Extend the bench artifact gate from transport-counter regressions to explicit
policy-driven performance budgets, so CI can fail on throughput or p95-latency
drift when a scenario owner supplies those thresholds.

## Scope

- In scope:
  - Add optional artifact-gate policy entries for minimum throughput and
    maximum p95 latency.
  - Keep the default gate strict for transport counters and unchanged for
    summaries without performance budgets.
  - Surface metric findings in JSON, Markdown, and CLI output.
  - Document the policy shape and verification state.
- Out of scope:
  - Choosing production budgets for every shipped scenario.
  - Changing benchmark workloads or benchmark measurement semantics.

## Files Expected To Change

- `native/bench/src/artifacts.rs`
- `native/bench/src/bin/check_artifact_gate.rs`
- `native/bench/README.md`
- `docs/router_metrics.md`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` must pass before substantial changes.
- No secrets, credentials, or deployment access are required.

## Plan

1. Add policy parsing and evaluator support for
   `throughput_mbps_min` / `latency_p95_ms_max` metric thresholds.
2. Extend report rendering and CLI output to include performance findings.
3. Add focused unit coverage for both passing and failing performance budgets.
4. Run targeted bench artifact tests and `bin/verify`.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`
- `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json`
- `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json`
- `bin/verify`

## Decision Log

- 2026-04-23: Keep performance budgets opt-in. The mechanism should land
  without guessing scenario-specific throughput or latency thresholds.
- 2026-04-23: Keep performance findings separate from transport counter
  findings in the report schema. Existing strict counter behavior remains the
  default, and metric budgets only apply when a policy defines them.

## Handoff

- Implemented and verified. Remaining work is a benchmark-owner decision:
  choose scenario-specific `throughput_mbps_min` and `latency_p95_ms_max`
  thresholds before broad CI performance drift enforcement is enabled.
