# HTTP/2 Connection Usage Hosted Rerun

Status: in_progress

## Context

- The connection-usage metrics slice is now complete locally:
  - HTTP bench reports include optional `http_connection_usage`
  - transformed artifact bundles derive `samples_per_connection_avg`
  - `tool/ktls_http2_compare.py` renders per-row connection views
- The focused hosted baseline remains manual run `24870980724` on commit
  `257f9aa`, which showed every multiplex-scaling row regressing under
  required-kTLS even when `streams_per_connection = 1`.
- The next decision point is no longer schema or local coverage. It is whether
  the hosted rerun shows extra connection churn under required-kTLS or confirms
  that reuse/open behavior stays stable and the hotspot is elsewhere.

## Goals

1. Push the connection-usage instrumentation on a clean branch head.
2. Keep the push CI chain green before dispatching more speculative work.
3. Dispatch a focused hosted `kTLS HTTP/2 Benchmarks` rerun once that head is
   clean and use the new connection section to decide the next diagnostic lane.

## Planned Changes

1. Commit and push the connection-usage instrumentation with updated state/docs.
2. Watch the push `CI`, `kTLS Validation`, and `WAMP Profile Benchmarks` runs.
3. After the push chain is green, rerun the manual kTLS benchmark on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`.
4. Record whether required-kTLS opens more HTTP connections or whether the new
   connection metrics stay flat across passes.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`
