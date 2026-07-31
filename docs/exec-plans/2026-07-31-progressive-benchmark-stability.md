# Exec Plan: Progressive Benchmark Stability

Status: complete
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
- 2026-07-31: Exact-head GitHub CI `30594250222`, kTLS Validation
  `30594250179`, and WAMP Profile Benchmarks `30594250184` passed on
  `acc7724`. Artifact `8779614698` measured all four progressive rows with
  128 samples at 1.055-1.928 Mbps and 10.354-18.250 ms p95, with no transport,
  metric, or policy findings.
- 2026-07-31: The strict deployment-chain audit passed. Package dry run
  `30590681999` remains clean and relevant because this change did not touch
  publish-sensitive paths.

## Handoff

- Complete. Resume the next MCP downstream-application readiness slice from
  project state and the roadmap.
