# HTTP/2 Native Response-Stream Handoff Metrics

Status: completed

## Context

- Commit `b8645af` was the prior clean hosted head on the branch:
  - `kTLS Validation` `24880362805`
  - `WAMP Profile Benchmarks` `24880362819`
  - `CI` `24880362829`
- Manual hosted run `24881249566` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  and proved the Dart-side completion boundary was still too early:
  - client-side hotspot signals still moved materially on
    `h2_multiplexed_streams_s4`, `threads=4`
  - the completion metrics stayed flat at `0.00 -> 0.00`
- The next bounded slice added native first-chunk handoff counters in
  `ct_core`, surfaced them through `ct_ffi` and `connectanum_router`,
  summarized them in `native/bench`, and rendered them in
  `tool/ktls_http2_compare.py`.

## Goals

1. Capture the first measurable native-side boundary after the Dart write
   returns.
2. Distinguish channel/dequeue delay from the first native `send_data` call.
3. Push the clean checkpoint and rerun the focused hosted
   `kTLS HTTP/2 Benchmarks` workflow so the next artifact can show whether the
   remaining hotspot appears before or after the first native handoff.

## Outcome

- The local implementation was verified with:
  - `bin/test-fast`
  - `dart analyze packages/connectanum_router packages/connectanum_bench`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `bin/verify`
- Commit `8ed8014` (`build(ktls): capture native response-stream handoff timing`)
  was pushed to both `origin` and `github`.
- The hosted GitHub push chain for `8ed8014` completed cleanly:
  - `WAMP Profile Benchmarks` `24882795293`
  - `kTLS Validation` `24882795301`
  - `CI` `24882795327`
- GitLab still did not surface a pipeline for `8ed8014` through the current
  token-backed pipeline query.
- Manual hosted run `24883756346` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on `8ed8014` with
  `skip_artifact_gate=true` and completed successfully.
- That rerun answered the current question:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s2`, `threads=1`
    - `response headers wait avg +2.21 ms`
    - `response body first chunk wait avg +13.64 ms`
    - `request round trip p95 +201.63 ms`
  - average native handoff movement on that same row stayed much smaller:
    - `native first chunk channel wait avg +0.41 ms`
    - `native headers-to-first-chunk-dequeue avg +0.50 ms`
    - `native first chunk send call avg -0.00 ms`
    - `native headers-to-first-chunk-send-call avg +0.50 ms`
- That means the native handoff averages are useful but still too coarse for
  the worst latency spike. The next bounded slice is tail-oriented native
  response-stream slow-path buckets, not more average-only timing.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24883756346`
- `bin/verify`
