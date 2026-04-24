# HTTP/2 Direct-Stream Open-Path Hosted Rerun

Status: completed

## Context

- Commit `33d45f0` passed the visible hosted GitHub push chain:
  - `CI` `24890762043`
  - `kTLS Validation` `24890762101`
  - `WAMP Profile Benchmarks` `24890762044`
- Manual hosted rerun `24891851907` on clean head `33d45f0` closed the
  direct-stream open question:
  - worst throughput and p95 row:
    `h2_multiplexed_streams_s4`, `threads=4`
    - `response headers wait avg 12.91 -> 35.04 (+22.13)`
    - `response body first chunk wait avg 3.79 -> 24.60 (+20.81)`
    - `server direct-stream open round trip avg 5.78 -> 3.98 (-1.80)`
    - `server stream open avg 6.14 -> 4.35 (-1.79)`
    - `native stream-open-to-headers-send avg 0.08 -> 0.12 (+0.04)`
    - `native headers-to-first-chunk-dequeue avg 3.03 -> 2.07 (-0.96)`
- The result means the remaining blind spot is after headers are queued into
  HTTP/2 and before the first actual connection write is observed.
- GitLab still had not surfaced a pipeline for `33d45f0` through the current
  token-backed query at the time this plan closed.

## Goals

1. Push a clean checkpoint that exposes direct-stream open control round-trip
   and descriptor-open-call timing.
2. Preserve a clean push CI chain on that checkpoint.
3. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` with
   `skip_artifact_gate=true`.
4. Use that rerun to determine whether the remaining stream-open regression is
   dominated by control-message round-trip overhead or the router-side
   descriptor-open call itself.

## Planned Changes

1. Keep the implementation limited to direct-stream open-path timing and its
   artifact rendering.
2. Push the verified checkpoint and preserve a clean CI chain.
3. Dispatch the focused hosted rerun once the push chain is green.
4. Use that artifact to choose the next bounded lane.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 tool/test_ktls_http2_compare.py`
- `python3 tool/ktls_http2_compare.py tmp/ktls-run-24889688795/baseline/bench_results.summary.json tmp/ktls-run-24889688795/ktls/bench_results.summary.json tmp/ktls-run-24889688795/rerender/comparison.json tmp/ktls-run-24889688795/rerender/comparison.md`
- `bin/verify`
