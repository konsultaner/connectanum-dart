# HTTP/2 Server Emission Hosted Rerun

Status: completed

## Context

- Commit `ce55324` is the last green hosted head on the branch:
  - `kTLS Validation` `24876283985`
  - `WAMP Profile Benchmarks` `24876284006`
  - `CI` `24876283996`
- Manual hosted run `24876728695` established that the remaining regression is
  dominated by the first-body-byte gap, not by response-body tail drain or
  chunk-shape drift.
- The repo now has a new instrumentation slice on the local working tree:
  - `packages/connectanum_router` exposes stream-open and first-body-write
    callbacks on HTTP response streams
  - `packages/connectanum_bench` aggregates server-side stream timing into
    `bench_http_stream`
  - `native/bench` summarizes those counters into
    `http_server_emission_timing`
  - `tool/ktls_http2_compare.py` renders `HTTP Server Emission Timing`
- Historical rerender of hosted artifact `24876728695` stayed backward
  compatible and correctly reported no server-emission metrics because that
  bundle predates the new counters.

## Goals

1. Push the new server-emission instrumentation on a clean CI chain.
2. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`.
3. Determine whether the remaining regression is already visible in
   server-side `headers_to_first_body_write_avg_ms` or whether the gap still
   opens only after the first body write leaves the server stream path.

## Planned Changes

1. Keep the implementation changes limited to the current instrumentation slice.
2. Wait for the push CI chain to go green on the new checkpoint.
3. Dispatch the focused hosted rerun and capture the result in
   `docs/project_state.md` and `docs/ktls_research.md`.

## Outcome

- Commit `7755828` passed the hosted push chain cleanly:
  - `kTLS Validation` `24878452943`
  - `WAMP Profile Benchmarks` `24878452920`
  - `CI` `24878452921`
- Manual workflow run `24879483421` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  with `skip_artifact_gate = true` and completed successfully.
- The rerun answered the active question directly:
  - client-side hotspot signals still moved materially:
    - worst throughput row:
      `h2_multiplexed_streams_s4`, `threads=4`
      (`response headers wait avg +6.71 ms`,
      `first chunk wait avg +4.83 ms`)
    - worst p95 row:
      `h2_multiplexed_streams_s1`, `threads=4`
      (`response body read avg +3.21 ms`,
      `request round trip p95 +14.95 ms`)
  - the current server-emission boundary stayed flat:
    - every comparable row held
      `headers_to_first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
    - every comparable row held
      `queue_to_first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_avg_ms` also stayed `0.00 -> 0.00 (+0.00)`
- That means the remaining gap still opens after the current
  `onFirstBodyWrite` callback point. The next bounded slice is therefore to
  instrument the first write after the native response-stream call returns,
  not to add more pre-write handler timing.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_bench/lib/src/http_stream_handler.dart packages/connectanum_bench/tool/bench_main.dart packages/connectanum_router/lib/src/router/http/http_context.dart packages/connectanum_bench/test/http_stream_handler_test.dart`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name "streams HTTP/2 response chunks using native streams" -r expanded`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name "HTTP/2 stream response callbacks fire once in open-then-write order" -r expanded`
- `cargo test --manifest-path native/bench/Cargo.toml -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24876728695`
- `bin/verify`
