# HTTP/2 Response-Stream Driver Yield

Status: completed

## Context

- Commit `25b2b7a` (`perf(router): use raw control port for internal
  sessions`) passed the visible hosted GitHub push chain:
  - `CI` `24902101047`
  - `WAMP Profile Benchmarks` `24902101976`
- Manual hosted rerun `24903103241` then completed successfully on clean head
  `25b2b7a` with the focused multiplex scenario and `skip_artifact_gate=true`.
- That rerun confirmed the main-isolate control-port optimization worked:
  the old `direct_stream_request_queue_delay` hotspot on
  `h2_multiplexed_streams_s2`, `threads=1` collapsed from the earlier
  `+8.63 ms` regression on `15185ad` to `-0.23 ms`.
- The remaining worst p95 row moved to `h2_multiplexed_streams_s8`,
  `threads=1`, where the server-side direct-stream timings improved while the
  client still regressed on first-byte delivery:
  - `response headers wait avg 23.75 -> 30.65 (+6.90)`
  - `response body first chunk wait avg 11.09 -> 23.94 (+12.84)`
  - `native headers-to-first-connection-write avg 0.06 -> 2.35 (+2.29)`
  - `native first chunk channel wait avg 0.42 -> 1.00 (+0.58)`
- In the current HTTP/2 server implementation, the connection driver
  (`serve_http2_connection`) and per-response streaming tasks share the same
  Tokio runtime workers. Once a streaming response task has ready chunks, it
  can queue headers plus several body chunks without yielding, which can delay
  the connection driver from actually flushing the first bytes on the
  single-thread hotspot path.

## Goals

1. Let the HTTP/2 connection driver flush queued headers earlier on the
   `threads=1` multiplex hotspot path.
2. Let the connection driver flush the first queued body chunk before the
   response task drains the rest of an already-buffered stream.
3. Preserve existing HTTP/2 response-stream correctness and keep the repo on a
   clean local verification path before pushing.

## Planned Changes

1. Update `send_http2_response_from_dispatch` so it yields once after
   `send_response(..., false)` queues the headers for a streaming response.
2. Yield once more after the first `send_data(...)` call queues the first
   body chunk for a streaming response.
3. Re-run focused HTTP/2 streaming regressions plus the local multiplex bench
   repro before the full `bin/verify` gate.
4. Refresh `docs/project_state.md` with the hosted rerun result and the new
   bounded fix so continuation resumes from the current hotspot instead of the
   old control-port investigation.

## Progress

- The implementation was pushed as commit `c21172f`
  (`perf(http2): yield streamed response driver turns`).
- Visible hosted GitHub push validation on that head completed successfully:
  - `CI` `24903966470`
  - `kTLS Validation` `24903966478`
  - `WAMP Profile Benchmarks` `24903966456`
- Focused verification was green on that checkpoint:
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

## Outcome

- Manual hosted rerun `24904942758` completed successfully on clean head
  `c21172f` with the focused multiplex scenario and `skip_artifact_gate=true`.
- The first-chunk-side part of the change materially improved the old hotspot:
  - `h2_multiplexed_streams_s8`, `threads=1` moved from
    `-57.58%` throughput / `+407.14%` p95 on rerun `24903103241`
    to `-13.12%` throughput / `+11.40%` p95
  - `response body first chunk wait avg` on that row improved from
    `13.57 ms` to `9.80 ms`
  - `headers_to_first_connection_write avg` improved from `0.025 ms`
    baseline to `0.020 ms` under kTLS instead of regressing
- The unconditional headers-side yield was too broad and created a new worst
  row at `h2_multiplexed_streams_s1`, `threads=1`:
  - `-60.21%` throughput
  - `+124.86%` p95
  - `response headers wait avg 5.92 -> 19.35 (+13.43)`
  - `response body first chunk wait avg 1.81 -> 1.38 (-0.43)`
- That result narrows the next action: remove the unconditional header yield,
  keep the first-chunk yield, and rerun the same focused hosted benchmark.
