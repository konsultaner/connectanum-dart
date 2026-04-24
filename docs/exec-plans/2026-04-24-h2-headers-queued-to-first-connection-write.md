# HTTP/2 Headers-Queued to First-Connection-Write

Status: in_progress

## Context

- Commit `33d45f0` passed the visible hosted GitHub push chain:
  - `CI` `24890762043`
  - `kTLS Validation` `24890762101`
  - `WAMP Profile Benchmarks` `24890762044`
- Manual hosted rerun `24891851907` on clean head `33d45f0` proved the
  remaining hotspot is not the direct-stream open path:
  - worst throughput and p95 row:
    `h2_multiplexed_streams_s4`, `threads=4`
    - `response headers wait avg 12.91 -> 35.04 (+22.13)`
    - `response body first chunk wait avg 3.79 -> 24.60 (+20.81)`
    - `server direct-stream open round trip avg 5.78 -> 3.98 (-1.80)`
    - `server stream open avg 6.14 -> 4.35 (-1.79)`
    - `native stream-open-to-headers-send avg 0.08 -> 0.12 (+0.04)`
    - `native headers-to-first-chunk-dequeue avg 3.03 -> 2.07 (-0.96)`
- The current local working tree carries the next bounded diagnostic slice:
  - native `headers_to_first_connection_write` averages and slow-path buckets
  - FFI and router metrics plumbing for those counters
  - bench artifact summaries and comparison rendering for the new metric
- GitLab still has not surfaced a pipeline for `33d45f0` through the current
  token-backed query.

## Goals

1. Push a clean checkpoint that exposes the gap between queued HTTP/2 headers
   and the first actual connection write.
2. Preserve a clean push CI chain on that checkpoint.
3. Once the push chain is green, rerun the focused hosted
   `kTLS HTTP/2 Benchmarks` workflow on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` with
   `skip_artifact_gate=true`.
4. Determine whether the remaining multiplex regression is dominated by the
   transport-write path after `send_response(...)` returns.

## Planned Changes

1. Keep the implementation limited to the new connection-write timing and
   matching slow-path counters.
2. Thread the metric through the native snapshot, Dart metrics model, bench
   summaries, and comparison output.
3. Preserve backward compatibility when rerendering older hosted artifacts
   that do not contain the new counters.
4. Use the next hosted rerun to decide whether the follow-up should stay in
   HTTP/2 write-path instrumentation or move into runtime tuning.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/transport/ct_core/Cargo.toml http2_connection_write_tracker_records_headers_to_first_connection_write -- --nocapture`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `python3 tool/ktls_http2_compare.py tmp/ktls-run-24891851907/extracted/baseline/bench_results.summary.json tmp/ktls-run-24891851907/extracted/ktls/bench_results.summary.json tmp/ktls-run-24891851907/rerender/comparison.json tmp/ktls-run-24891851907/rerender/comparison.md`
- `bin/verify`
