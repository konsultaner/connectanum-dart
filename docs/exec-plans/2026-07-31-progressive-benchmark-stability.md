# Exec Plan: Progressive Benchmark Stability

Status: active
Owner: Codex
Created: 2026-07-31
Last updated: 2026-07-31

## Goal

Keep the GitHub deployment chain clean by making the final-release progressive
WAMP throughput gate long enough to distinguish a production regression from
hosted-runner setup and scheduling noise.

## Scope

- In scope: progressive workload duration and regression coverage, repeated
  local validation, exact-head hosted WAMP evidence, and deployment-chain
  audit evidence.
- Out of scope: lower throughput floors, looser latency ceilings, protocol
  behavior changes, and unrelated benchmark tuning.

## Files Expected To Change

- `native/bench/scenarios/wamp_final_release_features.toml`
- `native/bench/src/bin/http_stream.rs`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` and `bin/verify` passed before this follow-up.
- The MCP authorization-discovery implementation is already committed and
  pushed; exact-head GitHub CI and package dry-run are green.
- The failing hosted workload completes all calls and router accounting
  correctly, with zero transport or protocol findings.

## Plan

1. Compare failing and successful hosted artifacts for the exact workload.
2. Increase measured progressive samples while preserving all performance
   thresholds and add a regression test for the sample-count contract.
3. Run repeated focused benchmarks, `bin/verify`, exact-head hosted workflows,
   and the strict deployment-chain audit.

## Verification

- `cargo test --release --manifest-path native/bench/Cargo.toml final_release_progressive_workloads_have_stable_sample_counts`
- Repeated focused `wamp_final_release_features` runs against the unchanged
  performance policy.
- `bin/verify`
- Exact-head GitHub CI, package dry-run, and WAMP Profile Benchmarks.
- `bin/audit-github-deployment-chain --branch master --run-limit 8 --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run --show-wamp-profile-benchmarks --require-clean-wamp-profile-benchmarks --strict`

## Decision Log

- 2026-07-31: Eight hosted artifacts measured the affected 24-sample row in
  only 185-273 ms at 0.720-1.063 Mbps; three consecutive failures across two
  commits were 0.707, 0.720, and 0.734 Mbps against the unchanged 0.750 Mbps
  floor.
- 2026-07-31: The workload-level timer includes WAMP client/session setup and
  teardown while throughput counts only response payload bytes. Increasing
  each progressive row from 12 to 64 iterations yields 128 measured samples
  and amortizes that fixed overhead without weakening the release requirement.
- 2026-07-31: The complete native benchmark suite passed with 17 library and
  54 orchestrator tests. Two contended macOS runs measured the affected row at
  0.844 and 0.799 Mbps, both above the unchanged 0.750 Mbps floor, versus
  0.289 Mbps at 24 samples. All throughput floors passed; existing latency
  ceilings remained noisy while multiple scheduled repositories shared the
  host.
- 2026-07-31: Post-change `bin/test-fast` passed, including all benchmark,
  MCP consumer, router CLI consumer, live WAMP transport, and focused
  router/native regressions.
- 2026-07-31: Complete local `bin/verify` passed, including Rust and Dart
  suites, isolated consumer smokes, router integration, and the Chrome
  Dart2Wasm WebSocket test.

## Handoff

- Pending exact-head hosted verification and the strict deployment-chain audit.
