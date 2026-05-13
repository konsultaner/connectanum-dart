# Exec Plan: kTLS Linux TLS-Stat Instrumentation

Status: completed
Last updated: 2026-04-24

## Goal

Extend the manual Linux HTTP/2 kTLS comparison flow so hosted runs capture and
summarize `/proc/net/tls_stat` deltas per pass. The next hosted comparison
should answer whether required-kTLS is actually opening kernel TLS sessions and
whether decrypt/rekey counters stay quiet while the current
`h2_sustained_transfer` / `native_runtime_threads = 1` hotspot persists.

## Scope

- Capture `/proc/net/tls_stat` before and after each pass in
  `bin/ktls-http2-bench` when the proc file is readable.
- Parse those sidecars in `tool/ktls_http2_compare.py` and add a concise
  comparison summary to `comparison.json` and `comparison.md`.
- Add focused Python regression coverage for the parser and markdown summary.
- Refresh `docs/project_state.md`, `docs/ktls_research.md`, and
  `native/bench/README.md`.

## Non-goals

- Changing the kTLS runtime itself or claiming a performance fix.
- Expanding the prototype beyond the existing Linux-only HTTP/2 path.
- Adding heavyweight profiling that would distort the benchmark timing path.

## Files Expected To Change

- `bin/ktls-http2-bench`
- `tool/ktls_http2_compare.py`
- `tool/test_ktls_http2_compare.py`
- `docs/project_state.md`
- `docs/ktls_research.md`
- `native/bench/README.md`

## Preconditions

- Hosted GitHub validation is green through `db2ff96`.
- The next slice should add Linux-side signal without requiring local macOS
  execution of the kTLS runtime path.

## Plan

1. Add best-effort `/proc/net/tls_stat` capture before and after each pass and
   write sidecars into the pass artifact directories.
2. Teach the comparison tool to parse the proc-format counters, compute
   per-pass deltas, and summarize the most relevant kTLS session/error signals.
3. Add focused Python tests that exercise missing, partial, and non-zero
   TLS-stat captures.
4. Update the checked-in kTLS docs so the next hosted rerun has a documented
   interpretation path.

## Verification

- `bin/test-fast`
- `bash -n bin/ktls-http2-bench`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- A focused synthetic comparison run for the new TLS-stat sidecars
- `bin/verify`

## Decision Log

- 2026-04-24: Prefer low-overhead kernel TLS counters over ptrace/perf-style
  diagnostics for the next slice, because the manual comparison workflow needs
  signal that survives hosted runs without materially distorting throughput.

## Handoff

- Completed. `bin/ktls-http2-bench` now writes `tls-stat-before.txt` /
  `tls-stat-after.txt` sidecars when `/proc/net/tls_stat` is readable, and the
  comparison bundle now surfaces kernel TLS session-open plus decrypt/rekey
  deltas alongside the existing throughput, latency, resource-usage, and
  transport-counter summaries.
- Local verification passed via `bin/test-fast`, `bash -n
  bin/ktls-http2-bench`, `python3 -m py_compile
  tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a focused synthetic
  `tool/ktls_http2_compare.py` run with TLS-stat sidecars, and `bin/verify`.
