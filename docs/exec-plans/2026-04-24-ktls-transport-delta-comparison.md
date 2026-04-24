# Exec Plan: kTLS Transport Delta Comparison

Status: completed
Owner: Codex
Created: 2026-04-24
Last updated: 2026-04-24

## Goal

Extend the kTLS HTTP/2 comparison artifact so it summarizes existing
transport-counter deltas alongside throughput and latency hotspots, making it
obvious when a slowdown is already explained by current bench telemetry versus
when the hotspot remains invisible to the existing counters.

## Scope

- In scope:
  - extend `tool/ktls_http2_compare.py` to compare transport-counter fields
    from the per-workload benchmark summaries
  - render those deltas in `comparison.json` and `comparison.md`
  - add focused regression coverage for the new transport-delta summary
  - refresh `docs/ktls_research.md` and `docs/project_state.md`
- Out of scope:
  - changing the Linux kTLS runtime itself
  - adding new low-level kernel instrumentation in `ct_core`
  - changing the benchmark scenario or artifact-gate policy

## Files Expected To Change

- `tool/ktls_http2_compare.py`
- `tool/test_ktls_http2_compare.py`
- `docs/ktls_research.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-24-ktls-transport-delta-comparison.md`

## Preconditions

- `bin/test-fast` passed on 2026-04-24 before this slice.
- Hosted GitHub `CI` run `24866820516` passed on commit `6deaabe`.
- Hosted kTLS benchmark artifact `24865337582` currently shows:
  - the worst throughput/p95 hotspot is `h2_sustained_transfer` with
    `native_runtime_threads = 1`
  - existing transport counters for both `h2_sustained_transfer` rows remain
    zero across baseline and required-kTLS
  - only the multiplexed rows show bounded `backpressure_events` /
    `backpressure_alerts` differences

## Plan

1. Add transport-counter delta comparison data to the existing per-workload
   comparison model.
2. Render a compact transport-delta summary in the markdown artifact so a
   hosted rerun immediately shows whether the hotspot correlates with existing
   transport telemetry.
3. Revalidate with focused Python checks plus `bin/verify`, then refresh the
   kTLS docs/state with the new interpretation path.

## Verification

- `bin/test-fast`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`

## Decision Log

- 2026-04-24: The hosted artifact already shows the current hotspot and the
  underlying transport counters. Surfacing those counters directly in the
  comparison artifact is the smallest useful next step before inventing deeper
  Linux-only probes.

## Handoff

- Completed on 2026-04-24.
- Local verification passed via `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a rerender of the hosted `24865337582` artifact bundle through
  `tool/ktls_http2_compare.py`, and `bin/verify`.
- The resulting comparison artifact now shows the current worst p95 hotspot
  (`h2_sustained_transfer`, `threads=1`) with no non-zero transport counters,
  while the multiplexed rows remain the only ones with bounded backpressure
  differences.
