# Exec Plan: transport-mbit-matrix-throughput

Status: completed
Owner: Codex
Created: 2026-04-21
Last updated: 2026-04-21

## Goal

Promote the existing cross-transport/auth/authz smoke matrix into a throughput-grade scenario so CI and artifact reporting can consume one canonical Mbps-oriented table per run.

## Scope

- In scope: a new sustained benchmark scenario under `native/bench/scenarios/`, bench README and roadmap updates that document the canonical matrix, and startup-state refreshes that close the prior CI-alignment milestone.
- Out of scope: bench-harness protocol changes, new metrics/export formats, or E2EE/PPT prototype work.

## Files Expected To Change

- `native/bench/scenarios/transport_mbit_matrix_throughput.toml`
- `native/bench/README.md`
- `ROADMAP.md`
- `ROADMAP_NEXT.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-21-ci-alignment.md`

## Preconditions

- The existing `transport_mbit_matrix_smoke.toml` shape is already valid and covers the right auth/authz/public/protected dimensions.
- Bench artifacts already emit stable per-workload throughput labels, so the new milestone should not need a harness refactor.

## Plan

1. Confirm the latest GitHub Actions result for the CI-alignment work, then close that plan in the checked-in startup docs.
2. Add a throughput-grade sibling of the existing transport/auth/authz smoke matrix by reusing the same workload topology with heavier sustained settings.
3. Refresh bench docs and roadmap/state files so the new canonical matrix is discoverable, then run repository verification before handoff.

## Verification

- `bin/test-fast`
- `python3 - <<'PY'` with `tomllib.load(...)` against `native/bench/scenarios/transport_mbit_matrix_throughput.toml`
- `bin/verify`

## Decision Log

- 2026-04-21: Chose to clone the proven smoke-matrix workload topology into a heavier throughput scenario instead of changing the orchestrator, because the artifact bundle already exports per-workload Mbps summaries with stable labels.
- 2026-04-21: Kept ACL-off versus ACL-on WAMP rows and WebSocket continuation-size rows intact so the new scenario stays directly comparable to the smoke artifact set rather than becoming a different benchmark family.
- 2026-04-21: Added 64 KiB protected HTTP ticket/JWT rows to the throughput scenario so the authenticated HTTP side includes both small and larger-payload samples, not just the 4 KiB smoke shape.
- 2026-04-21: `bin/verify` exposed a flaky `ct_ffi` HTTP/3 idle-timeout test; stabilized it by asserting directly on the emitted HTTP/3 connection event instead of depending on a separate accepted-connection callback that could race under full-suite load.

## Handoff

- The new scenario is now the canonical cross-transport/auth/authz throughput table for CI/reporting work.
- The next roadmap milestone after this is the E2EE/PPT research spike built on the shared lazy-payload contract.
