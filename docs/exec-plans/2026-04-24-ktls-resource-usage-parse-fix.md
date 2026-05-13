# Exec Plan: kTLS Resource Usage Parse Fix

Status: completed
Owner: Codex
Created: 2026-04-24
Last updated: 2026-04-24

## Goal

Make the hosted `kTLS HTTP/2 Benchmarks` comparison summary report the real
per-pass CPU, wall-time, and RSS data from GNU `time -v`, so the manual kTLS
benchmark lane answers performance questions directly instead of claiming the
resource sidecars are missing.

## Scope

- In scope:
  - fix `tool/ktls_http2_compare.py` so it parses the real tab-indented GNU
    `time -v` output emitted by hosted Linux runs
  - add a focused regression that matches the hosted artifact format
  - refresh `docs/ktls_research.md` and `docs/project_state.md` with the
    corrected hosted `24865337582` interpretation
- Out of scope:
  - new transport/runtime tuning in `ct_core`
  - changing the benchmark scenario or workflow trigger policy
  - claiming offload gains from GitHub-hosted Linux

## Files Expected To Change

- `tool/ktls_http2_compare.py`
- `tool/test_ktls_http2_compare.py`
- `docs/ktls_research.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-24-ktls-resource-usage-parse-fix.md`

## Preconditions

- `bin/test-fast` passed on 2026-04-24 before this slice.
- Hosted runs for commit `706d8b8` are green:
  push `CI` `24865318342`, push `kTLS Validation` `24865318343`,
  push `WAMP Profile Benchmarks` `24865318353`, and manual
  `kTLS HTTP/2 Benchmarks` `24865337582`.
- Artifact `ktls-http2-bench-artifacts` from run `24865337582` contains
  `baseline/resource-usage.txt` and `ktls/resource-usage.txt`, but the current
  generated `comparison.md` still says `Resource usage: no per-pass usage
  artifacts were present.`

## Plan

1. Update the resource-usage parser to match real GNU `time -v` output instead
   of only the simplified unindented test fixture shape.
2. Add a focused regression that uses the hosted tab-indented format and proves
   the generated summary now includes the resource-usage delta section.
3. Revalidate with focused Python checks plus `bin/verify`, then refresh the
   kTLS docs/state with the corrected hosted benchmark interpretation.

## Verification

- `bin/test-fast`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`

## Decision Log

- 2026-04-24: The latest hosted kTLS comparison already exposed the exact bug
  shape. Fixing the parser is higher-value than inventing another benchmark or
  transport change, because the current artifact set already contains the data
  needed for the next kTLS decision.

## Handoff

- Completed on 2026-04-24.
- Local verification passed via `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a rerender of the hosted `24865337582` artifact bundle through
  `tool/ktls_http2_compare.py`, and `bin/verify`.
- The hosted comparison from run `24865337582` now renders CPU, wall-time, and
  RSS deltas correctly, confirming the remaining kTLS penalty is primarily
  throughput/p95 on `h2_sustained_transfer` and `native_runtime_threads = 1`.
