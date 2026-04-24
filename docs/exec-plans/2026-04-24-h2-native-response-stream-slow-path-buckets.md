# HTTP/2 Native Response-Stream Slow-Path Buckets

Status: in_progress

## Context

- Commit `8ed8014` is the last green hosted head on the branch:
  - `WAMP Profile Benchmarks` `24882795293`
  - `kTLS Validation` `24882795301`
  - `CI` `24882795327`
- Manual hosted run `24883756346` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  and proved the average native handoff metrics are still too coarse for the
  worst latency spike:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s2`, `threads=1`
  - client-side hotspot movement on that row:
    - `response headers wait avg +2.21 ms`
    - `response body first chunk wait avg +13.64 ms`
    - `request round trip p95 +201.63 ms`
  - average native handoff movement on that same row:
    - `native first chunk channel wait avg +0.41 ms`
    - `native headers-to-first-chunk-dequeue avg +0.50 ms`
    - `native first chunk send call avg -0.00 ms`
- The current local working tree now carries the next bounded slice:
  bucketed native response-stream slow-path counters at `>=1ms`, `>=5ms`, and
  `>=10ms` for channel wait, headers-to-first-chunk dequeue, and the first
  native send call. Those counters are threaded through `ct_core`, `ct_ffi`,
  the Dart router metrics snapshot, `native/bench`, and
  `tool/ktls_http2_compare.py`.
- Local verification is now green for that slice on 2026-04-24:
  - `bin/test-fast`
  - `dart analyze packages/connectanum_router packages/connectanum_bench`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - rerender hosted artifact `24883756346`
  - `bin/verify`

## Goals

1. Preserve the lightweight cumulative metrics model while exposing native
   handoff tail behavior.
2. Show whether kTLS creates rare multi-millisecond stalls before dequeue or
   inside the first native send call.
3. Push a clean checkpoint and rerun the focused hosted benchmark so the next
   artifact can confirm whether the tail spike is already visible at the
   native handoff boundary.

## Planned Changes

1. Add `>=1ms`, `>=5ms`, and `>=10ms` counters for native response-stream
   channel wait, dequeue, and first send-call timings.
2. Surface those counters through `ct_ffi`, the Dart native runtime, and the
   router transport metrics JSON payload.
3. Summarize the counters in `native/bench` and render a dedicated
   `HTTP Native Response-Stream Slow Paths` section plus worst-row focus lines
   in `tool/ktls_http2_compare.py`.
4. Verify locally, then run full `bin/verify` before the next push.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24883756346`
- `bin/verify`
