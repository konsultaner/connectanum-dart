# Exec Plan: kTLS Benchmark Workflow Summary

Status: completed
Owner: Codex
Created: 2026-04-24
Last updated: 2026-04-24

## Goal

Make the manual GitHub Actions `kTLS HTTP/2 Benchmarks` workflow expose the
comparison result directly in the run summary, so operators can read the
throughput, latency, and resource-usage deltas without downloading the
artifact bundle first.

## Scope

- In scope:
  - update `.github/workflows/ktls-http2-benchmarks.yml` so successful and
    partial benchmark runs publish a concise summary from the generated
    comparison artifacts into the Actions job summary
  - align the checked-in benchmark docs with that new workflow-summary contract
  - refresh `docs/project_state.md` and this exec plan as the active milestone
    changes
- Out of scope:
  - dispatching the manual workflow from this shell
  - Linux-only runtime tuning inside `ct_core`
  - changing the underlying benchmark scenario or artifact schema again unless
    the workflow-summary step requires it

## Files Expected To Change

- `.github/workflows/ktls-http2-benchmarks.yml`
- `native/bench/README.md`
- `docs/ktls_research.md` if the operator guidance changes materially
- `docs/project_state.md`
- `docs/exec-plans/2026-04-24-ktls-benchmark-workflow-summary.md`

## Preconditions

- `bin/test-fast` is green before edits. Confirmed on 2026-04-24.
- Hosted GitHub validation is green through commit `7bf3d8a` on `add-router`:
  push `CI` run `24861886418`, `WAMP Profile Benchmarks` run `24861886401`,
  and `kTLS Validation` run `24861886408` all completed successfully.

## Plan

1. Add a workflow step that writes the generated kTLS comparison summary into
   the GitHub Actions job summary in both success and failure/partial-artifact
   cases.
2. Refresh the checked-in docs so the manual benchmark contract points at the
   run summary as the first read and the uploaded artifact bundle as the full
   detail.
3. Revalidate the workflow syntax and project verification baseline, then close
   the plan if the slice stays bounded.

## Verification

- `bin/test-fast`
- focused workflow syntax/readability validation for
  `.github/workflows/ktls-http2-benchmarks.yml`
- `bin/verify`

## Handoff

- Completed on 2026-04-24.
- `.github/workflows/ktls-http2-benchmarks.yml` now mirrors the generated
  `comparison.md` and `host-info.txt` content into `$GITHUB_STEP_SUMMARY` on
  both successful and partial benchmark runs.
- The operator-first read for a fresh manual Linux rerun is now the Actions run
  summary; the uploaded `ktls-http2-bench-artifacts` bundle remains the full
  detail source.
- The next useful kTLS action after this slice is to dispatch one fresh hosted
  `kTLS HTTP/2 Benchmarks` run on `add-router` and inspect the new summary to
  decide whether the remaining required-kTLS penalty looks CPU-bound, wall-time
  bound, or memory-heavy.
