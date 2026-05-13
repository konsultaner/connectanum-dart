# Exec Plan: kTLS Hotspot Rollups

Status: completed
Owner: Codex
Created: 2026-04-24
Last updated: 2026-04-24

## Goal

Make the manual kTLS HTTP/2 comparison artifacts point directly at the
remaining hotspot, so one hosted rerun can tell us whether required-kTLS is
losing mainly by workload family, runtime-thread count, or both.

## Scope

- In scope:
  - extend `tool/ktls_http2_compare.py` so `comparison.json` /
    `comparison.md` include grouped rollups by workload family and native
    runtime thread count
  - highlight one current investigation focus for each grouping in the
    generated comparison output
  - fix GNU `time -v` elapsed wall-time parsing so the resource-usage summary
    no longer drops that field
  - add focused Python regression coverage and refresh the checked-in docs/state
- Out of scope:
  - Linux-only kTLS runtime changes in `ct_core`
  - dispatching the manual `kTLS HTTP/2 Benchmarks` workflow from this shell
  - changing the underlying benchmark scenario or CI trigger policy

## Files Expected To Change

- `tool/ktls_http2_compare.py`
- `tool/test_ktls_http2_compare.py`
- `native/bench/README.md`
- `docs/ktls_research.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-24-ktls-hotspot-rollups.md`

## Preconditions

- `bin/test-fast` was green before edits on 2026-04-24.
- Hosted GitHub validation was green through commit `911b208` on `add-router`:
  push `CI` run `24862887602`, `kTLS Validation` run `24862887603`, and
  `WAMP Profile Benchmarks` run `24862887632` all completed successfully.

## Plan

1. Extend the comparison generator so it groups deltas by workload family and
   native runtime thread count instead of only listing raw per-workload rows.
2. Add explicit investigation-focus summaries and fix any missing resource
   fields that weaken the comparison output.
3. Revalidate the reporting path with focused Python checks plus full
   `bin/verify`, then refresh the docs/state so the next session can resume
   from the new comparison contract.

## Verification

- `bin/test-fast`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- focused synthetic comparison generation via `python3 tool/ktls_http2_compare.py ...`
- `bin/verify`

## Decision Log

- 2026-04-24: Hotspot selection now uses a combined severity score from
  average throughput regression and average p95 inflation. That keeps the
  summary focused on the groups that are operationally worst, not just the ones
  with the single-largest throughput drop.
- 2026-04-24: GNU `time -v` prints the elapsed wall-time label with embedded
  colons (`h:mm:ss or m:ss`), so generic `split(":", 1)` parsing silently
  dropped wall time. The parser now matches known field prefixes directly.

## Handoff

- Completed on 2026-04-24.
- `comparison.json` / `comparison.md` now expose grouped rollups by workload
  family and native runtime thread count, plus an investigation focus for each
  grouping.
- Resource-usage summaries now include elapsed wall time correctly.
- The next useful kTLS action is a fresh manual hosted
  `kTLS HTTP/2 Benchmarks` rerun on the branch head so the new rollups can
  confirm whether the remaining required-kTLS penalty still clusters around
  `h2_multiplexed_streams`, `threads=4`, or both.
