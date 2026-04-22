## Goal

Make the transformed bench artifact outputs enforceable in CI so existing
transport-regression signals fail benchmark workflows automatically instead of
only being visible in uploaded `.prom` / `.summary.json` artifacts.

## Scope

- add a summary-based bench artifact validator in `native/bench`
- expose a root-level entrypoint for validating transformed bench artifacts
- wire the validator into the existing kTLS validation / benchmark runners so
  regressions fail the run while artifacts still upload
- cover the validator with focused Rust tests
- document the new gate contract in the repo state and bench metrics docs

## Non-goals

- defining long-term throughput or latency performance budgets
- replacing Prometheus alert rules or Grafana dashboards
- changing the bench result schema produced by `http_stream`
- adding new benchmark scenarios in this slice

## Verification

- `bin/test-fast`
- focused Rust tests for the bench artifact validator
- focused shell checks for the updated kTLS runner scripts
- `bin/verify`

## Status

- completed

## Handoff

- The initial gate should stay aligned with the already-shipped bench artifact
  alert semantics: active throttles, transport alerts, transport error alerts,
  and backpressure deltas are all CI failures.
- The gate now runs through `bin/check-bench-artifacts`, and the current kTLS
  validation / benchmark scripts invoke that root entrypoint directly after
  each transformed summary is written.
- If later milestones need tolerated warnings or scenario-specific budgets,
  extend the validator/config surface instead of re-encoding ad hoc shell
  checks in individual workflows.
- There is no follow-on exec plan queued right now. The next session should
  choose the next unfinished milestone from `ROADMAP_NEXT.md`.
