# Exec Plan: kTLS Benchmark Resource Usage

Status: completed
Owner: Codex
Created: 2026-04-24
Last updated: 2026-04-24

## Goal

Make the manual Linux `bin/ktls-http2-bench` comparison artifacts capture and
summarize per-pass resource-usage evidence, so hosted runs expose not only
throughput/latency deltas but also the CPU and memory cost of required kTLS.

## Scope

- In scope:
  - capture per-pass resource-usage outputs for the baseline TLS pass and the
    required-kTLS pass in `bin/ktls-http2-bench`
  - extend `tool/ktls_http2_compare.py` so `comparison.json` and
    `comparison.md` summarize the captured resource-usage deltas alongside the
    existing throughput/latency findings
  - keep the resource-usage path testable from this macOS host with synthetic
    inputs and shell-validation rather than a real Linux kTLS run
  - refresh `docs/project_state.md`, `docs/ktls_research.md`, and this plan if
    the artifact contract changes materially
- Out of scope:
  - Linux-only runtime tuning inside `ct_core`
  - new hosted benchmark claims before a fresh Linux rerun exists
  - broad bench-metadata refactors unrelated to the kTLS comparison runner

## Files Expected To Change

- `bin/ktls-http2-bench`
- `tool/ktls_http2_compare.py`
- `docs/project_state.md`
- `docs/ktls_research.md` if the interpretation contract changes materially
- `docs/exec-plans/2026-04-24-ktls-benchmark-resource-usage.md`

## Preconditions

- `bin/test-fast` is green before edits. Confirmed on 2026-04-24.
- Hosted GitHub validation is green through commit `8da3602` on `add-router`:
  push `CI` run `24860616844` and `WAMP Profile Benchmarks` run `24860616860`
  both completed successfully.

## Plan

1. Add per-pass resource-usage capture to the Linux kTLS HTTP/2 comparison
   runner without changing the existing benchmark workload contract.
2. Extend the comparison artifact generator so it summarizes CPU and memory
   deltas in both machine-readable and human-readable form.
3. Revalidate the shell/tooling path locally with synthetic inputs, then update
   checked-in state and close the plan if the slice stays bounded.

## Verification

- `bin/test-fast`
- `bash -n bin/ktls-http2-bench`
- focused synthetic comparison generation for the updated resource-usage path
- `bin/verify`

## Handoff

- Completed on 2026-04-24.
- `bin/ktls-http2-bench` now records GNU `time -v` output per pass in
  `baseline/resource-usage.txt` and `ktls/resource-usage.txt` after prebuilding
  the release HTTP bench binary for more stable runtime measurements.
- `tool/ktls_http2_compare.py` now reads those sidecars automatically and adds
  CPU-total, wall-time, and max-RSS deltas to both `comparison.json` and
  `comparison.md`, alongside the existing throughput and p95-latency summary.
- The next useful kTLS-specific action after this slice is a fresh hosted Linux
  comparison run so the new resource-usage summary can identify whether the
  remaining required-kTLS gap is mostly CPU cost, wall-time blocking, or
  memory pressure.
