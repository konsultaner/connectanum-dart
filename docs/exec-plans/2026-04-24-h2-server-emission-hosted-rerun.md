# HTTP/2 Server Emission Hosted Rerun

Status: in_progress

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
