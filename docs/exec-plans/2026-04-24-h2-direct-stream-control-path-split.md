# HTTP/2 Direct-Stream Control-Path Split

Status: completed

## Context

- Commit `0a9c3c8` passed the visible hosted GitHub push chain:
  - `CI` `24893449385`
  - `kTLS Validation` `24893449381`
  - `WAMP Profile Benchmarks` `24893449378`
- The control-path split is now implemented and pushed as `d892676`
  (`build(ktls): split direct-stream control timing`).
- The current hosted push chain for `d892676` is in progress:
  - `CI` `24895983686`
  - `kTLS Validation` `24895983707`
  - `WAMP Profile Benchmarks` `24895983693`
- Manual hosted rerun `24894437415` on clean head `0a9c3c8` ruled out the
  post-header transport-write path:
  - worst throughput and p95 row:
    `h2_multiplexed_streams_s8`, `threads=4`
    - `response headers wait avg 24.10 -> 211.03 (+186.93)`
    - `response body first chunk wait avg 8.92 -> 72.21 (+63.29)`
    - `native headers-to-first-connection-write avg 0.16 -> 0.12 (-0.04)`
    - `server direct-stream open round trip avg 12.29 -> 104.83 (+92.53)`
    - `server direct-stream descriptor-open call avg 0.05 -> 0.03 (-0.01)`
- That leaves one bounded blind spot: `direct_stream_open_round_trip` is still
  moving sharply, but the existing `descriptorOpenUs` signal is flat.

## Goals

1. Split the direct-stream control path into request-side queue delay and
   reply-side delivery delay.
2. Thread both metrics through the bench summaries and kTLS comparison output
   without breaking rerenders of older hosted artifacts.
3. Preserve a clean local `bin/verify` result before pushing.
4. Use the next hosted rerun to decide whether the hotspot is request-side
   control queueing, reply delivery, or a deeper path still not instrumented.

## Planned Changes

1. Timestamp the sender-side control message in `HttpResponseStream`, then
   capture worker receive time plus reply send time in the internal session
   handler.
2. Export request-queue and reply-delivery durations through the Dart bench
   diagnostics and Rust artifact summaries as part of
   `http_server_emission_timing`.
3. Extend `tool/ktls_http2_compare.py` and its regression coverage so the new
   metrics appear in both the focus lines and the markdown timing table.
4. Keep the existing `direct_stream_open_round_trip` and
   `direct_stream_descriptor_open_call` metrics intact so the new split can be
   compared against the prior hosted results.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`

## Outcome

- Manual hosted rerun `24897078545` on clean head `d892676` completed
  successfully with the focused multiplex scenario and `skip_artifact_gate=true`.
- The worst p95 row stayed `h2_multiplexed_streams_s8`, `threads=1`, and the
  direct-stream control-path split showed the movement is mostly on reply
  delivery rather than request queueing:
  - `server direct-stream open round trip avg 12.19 -> 19.09 (+6.90)`
  - `server direct-stream request queue delay avg 5.46 -> 6.56 (+1.10)`
  - `server direct-stream reply delivery delay avg 6.70 -> 12.50 (+5.80)`
- The worst throughput row `h2_multiplexed_streams_s2`, `threads=1` did not
  regress on the direct-stream control path, so that row remains explained by
  the native first-chunk path rather than the control handshake itself.
