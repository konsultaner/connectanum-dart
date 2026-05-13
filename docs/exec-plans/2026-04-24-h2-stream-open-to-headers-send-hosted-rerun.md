# HTTP/2 Stream-Open to Headers-Send Hosted Rerun

Status: completed

## Context

- Commit `a12227d` passed the visible hosted GitHub push chain:
  - `CI` `24886626863`
  - `WAMP Profile Benchmarks` `24886626856`
- `kTLS Validation` still did not surface for `a12227d` through the GitHub
  API, and GitLab also did not surface a pipeline for that head through the
  current token-backed query.
- Manual hosted run `24887510264` confirmed that the direct-stream completion
  fix worked: the missing `h2_multiplexed_streams_s1` rows now appear in
  server-emission diagnostics.
- That rerun also made the next blind spot explicit:
  - worst throughput row:
    `h2_multiplexed_streams_s8`, `threads=4`
    - `response headers wait avg 24.33 -> 37.67 (+13.34)`
    - `server stream open avg 11.88 -> 14.12 (+2.24)`
    - `server first body write completed avg 11.93 -> 14.17 (+2.24)`
    - `native headers-to-first-chunk-send-call avg 6.26 -> 9.46 (+3.20)`
- The current pushed checkpoint is `fbc5566` (`build(ktls): capture http2
  header dispatch timing`), now on both `origin` and `github`.
- The visible GitHub push chain for `fbc5566` completed successfully:
  - `CI` `24888660106`
  - `kTLS Validation` `24888660101`
  - `WAMP Profile Benchmarks` `24888660111`
- GitLab has not surfaced a pipeline for `fbc5566` through the current
  token-backed query.
- Manual hosted rerun `24889688795` (`kTLS HTTP/2 Benchmarks`) then completed
  successfully on `fbc5566` with
  `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml` and
  `skip_artifact_gate=true`.
- That rerun answered the header-dispatch question directly:
  - worst throughput and p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    - `response headers wait avg 26.45 -> 41.65 (+15.20)`
    - `server stream open avg 14.09 -> 18.45 (+4.36)`
    - `native stream-open-to-headers-send avg 0.09 -> 0.63 (+0.54)`
    - `native headers send call avg 0.00 -> 0.00 (-0.00)`
    - `native headers-to-first-chunk-dequeue avg 7.85 -> 12.43 (+4.59)`
- That means the remaining hotspot is not inside `send_response(...)`.
  The next bounded lane is to split the direct-stream open path itself.
- The completed checkpoint carried the native header-dispatch metric slice:
  - `ct_core` records:
    - `stream_open_to_headers_send`
    - `headers_send_call`
  - `ct_ffi` and `connectanum_router` export those fields through the native
    router metrics snapshot
  - `native/bench` summarizes them into
    `http_native_response_stream_timing`
  - `tool/ktls_http2_compare.py` renders them in the native response-stream
    focus lines and timing table

## Goals

1. Push a clean checkpoint that exposes the native response-stream
   open-to-headers boundary.
2. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`.
3. Determine whether the remaining response-header regression is opening
   before `send_response(...)` returns, inside that call, or only after that
   boundary.

## Planned Changes

1. Keep the implementation limited to the new native response-stream header
   dispatch metrics and their artifact rendering.
2. Push the verified checkpoint and preserve a clean CI chain.
3. Once the push chain is green, dispatch the focused hosted rerun with
   `skip_artifact_gate=true`.
4. Use the new artifact to decide whether the next lane is deeper native
   header-dispatch queueing or downstream transport flush instrumentation.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`
