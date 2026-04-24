# HTTP/2 Native Response-Stream Handoff Metrics

Status: in_progress

## Context

- Commit `b8645af` is the last green hosted head on the branch:
  - `kTLS Validation` `24880362805`
  - `WAMP Profile Benchmarks` `24880362819`
  - `CI` `24880362829`
- Manual hosted run `24881249566` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  and proved the current Dart-side completion boundary is still too early:
  - client-side hotspot signals still moved materially on the worst row
    `h2_multiplexed_streams_s4`, `threads=4`
    - `response headers wait avg +8.38 ms`
    - `response body first chunk wait avg +19.33 ms`
    - `response body tail read avg +3.00 ms`
  - server-side completion metrics stayed flat:
    - `headers_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `queue_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_call_avg_ms 0.00 -> 0.00 (+0.00)`
- The current local working tree now carries the next bounded instrumentation
  slice:
  - `ct_core` timestamps streamed response frames and records first-chunk
    native handoff timings
  - `ct_ffi` and `connectanum_router` expose those counters through the
    existing transport metrics snapshot
  - `native/bench` summarizes the counter deltas into
    `http_native_response_stream_timing`
  - `tool/ktls_http2_compare.py` renders the new focus lines and markdown
    section
- Local verification is now green for that slice on 2026-04-24:
  - `bin/test-fast`
  - `dart analyze packages/connectanum_router packages/connectanum_bench`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `bin/verify`

## Goals

1. Capture the first measurable native-side boundary after the Dart write
   returns.
2. Distinguish channel/dequeue delay from the first native `send_data` call.
3. Push the clean checkpoint and rerun the focused hosted
   `kTLS HTTP/2 Benchmarks` workflow so the next artifact can show whether the
   remaining hotspot appears before or after the first native handoff.

## Planned Changes

1. Timestamp streamed response frames in `ct_core` and record cumulative
   first-chunk native handoff counters.
2. Surface those counters through `ct_ffi`, the Dart native runtime, and the
   router transport metrics JSON payload.
3. Summarize the counters in `native/bench` and render them in
   `tool/ktls_http2_compare.py`.
4. Verify locally, then push and wait for the push CI chain before running the
   next focused hosted rerun.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`
