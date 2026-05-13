# HTTP/2 Request-Path Phase Split

Status: completed

## Context

- Commit `3d85b51` is green on the hosted push chain:
  - `CI` `24873599372`
  - `kTLS Validation` `24873599375`
  - `WAMP Profile Benchmarks` `24873599379`
- Manual hosted run `24874338657` closed the first two multiplex hypotheses on
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`:
  - connection reuse stayed flat (`connections_opened 4 -> 4 (+0)`)
  - stream acquire wait stayed effectively flat on the hotspot rows
- The visible regression is now inside the post-acquire HTTP/2 request path:
  `request_round_trip_*` inflated materially while the new acquire-wait timing
  stayed near zero.
- The local working tree now carries the next diagnostic slice:
  - HTTP/2 bench samples record request enqueue, response-header wait, and
    response-body drain timing
  - transformed artifact summaries expose those new sub-phases
  - `tool/ktls_http2_compare.py` renders the deeper request-path timing in the
    phase summary and worst-row focus lines

## Goals

1. Split the HTTP/2 request path into narrower sub-phases on the benchmark
   path.
2. Keep the push CI chain green on the next instrumentation checkpoint.
3. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow and decide
   whether the remaining regression is concentrated in request upload,
   response-header wait, or response-body drain.

## Planned Changes

1. Extend the HTTP phase timing model and artifact summaries with deeper
   request-path timing.
2. Render those new signals in `tool/ktls_http2_compare.py` and its test
   coverage.
3. Push the new checkpoint on a clean head and rerun the focused hosted
   multiplex benchmark.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24874338657`
- `bin/verify`

## Outcome

- Commit `a88a8b7` (`build(ktls): split http2 request path timing`) cleared
  the hosted push chain:
  - `CI` `24874851886`
  - `kTLS Validation` `24874851872`
  - `WAMP Profile Benchmarks` `24874851879`
- Manual hosted run `24875528924` (`kTLS HTTP/2 Benchmarks`) then reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head.
- The new request-path split ruled out request upload and response-header wait
  as the primary regression source:
  - worst throughput row and worst p95 row were both
    `h2_multiplexed_streams_s8` at `threads=1`
  - `stream acquire wait avg 0.05 -> 0.02`
  - `request enqueue avg 0.04 -> 0.06`
  - `response headers wait avg 28.65 -> 28.52`
- The visible regression is concentrated in the response-body drain instead:
  - `response body read avg 7.86 -> 58.91`
  - `response body read p95 14.11 -> 467.44`
  - `request round trip p95 52.96 -> 512.05`
- The next bounded diagnostic slice is therefore response-body-drain
  instrumentation that can separate first-body-byte delay from sustained body
  drain and record the observed body chunk shape.
