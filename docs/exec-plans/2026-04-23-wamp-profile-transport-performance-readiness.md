# Exec Plan: WAMP Profile Transport Performance Readiness

## Status

Active after the first usable MCP stdio bridge path landed in
`packages/connectanum_mcp`.

## Goal

After the first usable MCP server/bridge path is complete, make the
WAMP-profile transport benchmark surface production-ready enough to support
release decisions for real RawSocket/WebSocket WAMP users.

## Priority

- Keep the CI chain green first.
- The first usable MCP stdio bridge path is complete; Streamable HTTP MCP
  remains conditional on a `groli/app` network-endpoint decision.
- Treat this as production-readiness work, not speculative performance
  exploration.
- Defer unrelated HTTP/3, kTLS, E2EE, and broad benchmark exploration until the
  WAMP-profile transport gates are credible.

## Scope

- Define the canonical WAMP transport scenarios that count for release
  readiness: RawSocket, WebSocket, cleartext, TLS, native client, Dart client,
  JSON, MessagePack, CBOR, RPC, pub/sub, auth/session setup, mixed serializer,
  PPT payload mode, and representative fan-out/control paths.
- Decide which existing scenarios should be smoke gates versus throughput
  gates, and remove or rename ambiguous artifacts that look meaningful but are
  not release-decision inputs.
- Add explicit scenario-specific throughput and latency budgets through the
  bench artifact gate rather than relying on raw summaries.
- Record local Darwin and hosted Linux baselines for the canonical scenarios.
- Make regressions actionable: every failed budget should point to a transport,
  serializer, workload family, and likely owner path.
- Keep docs human-readable so users can understand what "production-ready WAMP
  transport performance" means without reading raw JSON artifacts.

## Non-Goals

- Reopening speculative HTTP/3 queue-depth experiments.
- Treating every benchmark scenario as a CI gate.
- Optimizing rare WAMP profile edge cases before the canonical RawSocket and
  WebSocket release paths have credible budgets.
- Replacing WAMP conformance work; this plan is performance and benchmark
  readiness, not protocol-correctness coverage.

## Candidate Inputs

- `native/bench/scenarios/wamp_transport_throughput.toml`
- `native/bench/scenarios/wamp_client_impl_throughput.toml`
- `native/bench/scenarios/wamp_secure_throughput.toml`
- `native/bench/scenarios/wamp_payload_mode_throughput.toml`
- `native/bench/scenarios/wamp_mixed_serializer_throughput.toml`
- `native/bench/scenarios/wamp_publish_fanout_throughput.toml`
- `native/bench/scenarios/wamp_control_smoke.toml`
- `native/bench/artifact_gate/`

## Verification Plan

- Run `bin/test-fast` before code or benchmark-gate changes.
- Validate artifact policy parsing with focused `native/bench` tests.
- Run canonical WAMP bench scenarios locally when budgets change.
- Dispatch hosted Linux validation for the canonical scenario set before
  declaring the plan complete.
- Run `bin/verify` before handoff and watch hosted CI after pushes.

## First Slice

- Inventory existing WAMP scenarios and mark each as smoke, throughput,
  diagnostic, or obsolete.
- Pick the smallest release-decision gate set.
- Add or adjust artifact policies for that gate set, starting with budgets that
  reflect current known local and hosted baselines rather than aspirational
  targets.

## Progress

- 2026-04-23: Confirmed latest hosted branch CI is green on GitHub Actions run
  `24826431486` for `7ca6798`.
- 2026-04-23: Ran `bin/test-fast` before benchmark-readiness edits; it passed
  on Darwin arm64.
- 2026-04-23: Captured local Darwin arm64 baselines for
  `wamp_transport_throughput` and `wamp_secure_throughput` with
  `router_workers=1` and `native_runtime_threads=1`; both passed the default
  zero transport-counter artifact gate.
- 2026-04-23: Added `docs/wamp_profile_benchmarks.md` to classify WAMP
  scenarios into release gates, diagnostic scenarios, and smoke-only checks.
- 2026-04-23: Added initial per-workload artifact policies for
  `wamp_transport_throughput` and `wamp_secure_throughput`. These are
  conservative release floors based on current local/known hosted baselines,
  not aspirational performance targets.
- 2026-04-23: Validated the new policies against local summaries with
  `bin/check-bench-artifacts`, then ran `bin/verify` successfully on Darwin
  arm64.
- 2026-04-23: Added `bin/wamp-profile-validate` and the dedicated `WAMP
  Profile Benchmarks` GitHub Actions workflow so hosted Linux uses the same
  canonical cleartext and secure WAMP policy gates as local release
  validation.
- 2026-04-23: Ran `bash -n bin/wamp-profile-validate` and then
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-local
  --router-worker-counts 1 --native-runtime-thread-counts 1
  --workload-timeout-ms 300000`; both canonical WAMP policy gates passed on
  Darwin arm64.
- 2026-04-23: Ran final local handoff verification. A first `bin/verify`
  attempt hit a transient `ct_ffi` connection-poll timeout, but the failing
  test passed in isolation, the full `ct_ffi` suite passed, and the full
  `bin/verify` rerun passed.
- 2026-04-23: Pushed the verified checkpoint and confirmed manual GitHub
  `CI` dispatch works on `add-router`. The branch-added dedicated WAMP
  workflow is not dispatchable until it exists on the default branch, so the
  existing `CI` workflow now has a `workflow_dispatch`-only `WAMP Profile
  Gates` job for branch-hosted WAMP evidence.
- 2026-04-23: Investigated hosted `WAMP Profile Benchmarks` failure on
  `3acbf94`. The WAMP workloads completed and throughput budgets were fine,
  but the artifact gate caught HTTP/2 control-plane TLS close/protocol alerts
  from `/bench/metrics`. The Rust bench control client now forces HTTP/1.1 so
  the WAMP gate does not mix control-channel shutdown noise into WAMP
  transport deltas.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml --bin http_stream http_endpoint_accepts_https_control_base -- --nocapture`,
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-http1-control-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`,
  and `bin/verify` passed on Darwin arm64 after the HTTP/1.1 control-plane
  fix.
- 2026-04-23: Hosted `WAMP Profile Benchmarks` run `24843390575` passed on
  commit `67bcf2f`. The separate `kTLS HTTP/2 Benchmarks` push run
  `24843390566` failed after both benchmark passes completed because its
  generic zero-counter artifact gate flagged multiplexing backpressure in a
  completed research benchmark. The kTLS comparison workflow is being moved to
  manual dispatch only; `kTLS Validation` remains the push correctness gate.
- 2026-04-23: Confirmed `50faaa0` restored the hosted branch CI chain:
  GitHub Actions push run `24844042608` passed `CI`, and manual dispatch run
  `24844047555` passed `Fast Checks`, `Full Verify`, and `WAMP Profile Gates`.
- 2026-04-23: Expanded `bin/wamp-profile-validate` so the canonical
  release-gate entrypoint runs the three default-counter smoke gates
  (`wamp_smoke`, `wamp_secure_smoke`, `wamp_control_smoke`) before the two
  policy-backed throughput gates. Local Darwin arm64 validation passed all
  five gates with 64 workloads using
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-smoke-release-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`,
  and final `bin/verify` passed after the script/docs update.
- 2026-04-23: Hosted Linux evidence for the expanded WAMP release gate is now
  green too. GitHub Actions run `24846498743` passed the dedicated `WAMP
  Profile Benchmarks` workflow on commit `a2eef0f`, and push `CI` run
  `24846498753` passed `Fast Checks` and `Full Verify` on the same commit.
- 2026-04-23: Added `bin/wamp-profile-diagnostics` and a hosted `WAMP Profile
  Diagnostics` workflow for the diagnostic WAMP throughput scenarios. These
  runs use the default transport-counter gate only; they are not release
  throughput budgets until repeated hosted baselines justify explicit
  policies. `bash -n bin/wamp-profile-diagnostics` and
  `bin/wamp-profile-diagnostics --out-dir out/wamp-profile-diagnostics-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`
  passed locally on Darwin arm64 with zero gate findings.

## Next Slice

- Push the diagnostic runner/workflow and confirm hosted Linux passes the new
  `WAMP Profile Diagnostics` workflow plus the normal `CI` chain.
- After hosted diagnostic evidence lands, decide whether any diagnostic WAMP
  scenarios should become explicit release gates before tightening existing
  throughput policy floors.
