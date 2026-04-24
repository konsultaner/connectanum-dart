# HTTP/2 First-Chunk Yield Only

Status: in_progress

## Context

- Commit `c21172f` (`perf(http2): yield streamed response driver turns`)
  passed the visible hosted GitHub push chain:
  - `CI` `24903966470`
  - `kTLS Validation` `24903966478`
  - `WAMP Profile Benchmarks` `24903966456`
- Manual hosted rerun `24904942758` then completed successfully on clean head
  `c21172f` with the focused multiplex scenario and `skip_artifact_gate=true`.
- That rerun proved the first-chunk-side scheduler yield was useful on the old
  hotspot:
  - `h2_multiplexed_streams_s8`, `threads=1` improved from
    `-57.58%` throughput / `+407.14%` p95 on rerun `24903103241`
    to `-13.12%` throughput / `+11.40%` p95
  - `response body first chunk wait avg` on that row improved from
    `13.57 ms` to `9.80 ms`
  - `native headers-to-first-connection-write avg` no longer regressed
- The same rerun also showed the unconditional headers-side yield is too broad
  at low multiplex:
  - new worst row `h2_multiplexed_streams_s1`, `threads=1`
  - `-60.21%` throughput / `+124.86%` p95
  - `response headers wait avg 5.92 -> 19.35 (+13.43)`
  - `response body first chunk wait avg 1.81 -> 1.38 (-0.43)`
- That signature points at the header yield itself, not the first-chunk yield:
  the client waits much longer for headers even though the first body-chunk
  wait improved.

## Goals

1. Remove the low-contention header-delay regression introduced by the
   unconditional headers-side yield.
2. Preserve the multiplex improvement from yielding after the first body chunk.
3. Keep the HTTP/2 response-stream path functionally unchanged and revalidate
   locally before the next hosted rerun.

## Planned Changes

1. Remove the post-`send_response(..., false)` yield from the HTTP/2 streaming
   response path.
2. Keep the post-first-chunk yield in place so the connection driver still gets
   a turn before the task drains a buffered stream.
3. Re-run focused HTTP/2 regressions plus the local multiplex bench repro.
4. Re-run `bin/verify`, then push and repeat the focused hosted `kTLS HTTP/2
   Benchmarks` rerun once the push chain is green.

## Progress

- The local working tree now carries the narrower follow-up in
  `native/transport/ct_core/src/lib.rs`: the headers-side yield is removed,
  and the first-chunk yield remains.
- Local verification is green on this in-progress checkpoint:
  - `bin/test-fast`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
  - `bin/verify`

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
- `bin/verify`
