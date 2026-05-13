# HTTP/2 First-Body Gap Diagnostics

Status: completed

## Context

- Commit `ce55324` is green on the hosted push chain:
  - `kTLS Validation` `24876283985`
  - `WAMP Profile Benchmarks` `24876284006`
  - `CI` `24876283996`
- Manual hosted run `24876728695` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` with the new
  response-body diagnostics enabled.
- That rerun narrowed the remaining regression again:
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
    (`response body first chunk wait avg +2.57 ms`,
    `response body tail read avg +0.99 ms`)
  - worst p95 row:
    `h2_multiplexed_streams_s8` at `threads=1`
    (`response body first chunk wait avg +16.98 ms`,
    `response body tail read avg +2.90 ms`)
  - `response body chunks avg` and `response body first chunk bytes avg`
    stayed flat on the hotspot rows
- The next unanswered question is therefore no longer chunk shape. It is where
  the header-to-first-body delay is being introduced: server response
  emission, transport scheduling, or client-side post-header handling.

## Goals

1. Separate server/body-emission delay from client-side first-body receipt.
2. Keep the push CI chain green on the next instrumentation checkpoint.
3. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow and determine
   whether the remaining regression is primarily upstream of the first body
   write or between first write and first client receipt.

## Planned Changes

1. Add targeted timing or counters around HTTP response emission for the
   benchmark stream path, especially the interval from headers to first body
   chunk production.
2. Thread the new signals through artifact summaries and comparison output.
3. Push the clean checkpoint and rerun the focused hosted multiplex benchmark.

## Outcome

- The repo now captures server-side HTTP response emission timing for the
  benchmark stream path:
  - response-stream open timing
  - first body write timing
  - headers-to-first-body-write timing
  - queue-to-first-body-write timing
  - request-body drain timing
- `packages/connectanum_router` now exposes response-stream callbacks so the
  bench can observe native stream-open and first-body-write events without
  changing payload behavior.
- `packages/connectanum_bench` now aggregates those timings into the
  `bench_http_stream` metrics payload, `native/bench` summarizes them into
  `http_server_emission_timing`, and `tool/ktls_http2_compare.py` renders an
  `HTTP Server Emission Timing` section plus hotspot focus lines.
- Focused local verification passed for the changed Dart, Rust, and Python
  paths, and rerendering historical hosted artifact `24876728695` stayed
  backward compatible: the new section renders, but the old bundle correctly
  reports no server-emission metrics because that artifact predates the new
  instrumentation.
- The next active step is no longer more implementation. It is the hosted
  rerun that uses this new signal to determine whether the remaining
  first-body-byte gap is already present between stream open and first body
  write on the server side or only after the first body write leaves it.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24876728695`
- `bin/verify`
