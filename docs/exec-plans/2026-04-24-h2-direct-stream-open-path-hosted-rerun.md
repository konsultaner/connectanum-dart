# HTTP/2 Direct-Stream Open-Path Hosted Rerun

Status: in_progress

## Context

- Commit `fbc5566` passed the visible hosted GitHub push chain:
  - `CI` `24888660106`
  - `kTLS Validation` `24888660101`
  - `WAMP Profile Benchmarks` `24888660111`
- Manual hosted rerun `24889688795` on clean head `fbc5566` proved that the
  header-send call itself is not the hotspot:
  - worst throughput and p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    - `response headers wait avg 26.45 -> 41.65 (+15.20)`
    - `server stream open avg 14.09 -> 18.45 (+4.36)`
    - `native stream-open-to-headers-send avg 0.09 -> 0.63 (+0.54)`
    - `native headers send call avg 0.00 -> 0.00 (-0.00)`
    - `native headers-to-first-chunk-dequeue avg 7.85 -> 12.43 (+4.59)`
- The current local working tree carries the next bounded metric slice:
  - `HttpResponseStream` now records direct-stream open control round-trip
    time from control message send to descriptor reply
  - the router-side control reply now includes `descriptorOpenUs`, measured
    around `_openDirectResponseStream(...)`
  - `packages/connectanum_bench` aggregates both timings into
    `http_server_emission_timing`
  - `tool/ktls_http2_compare.py` renders those new values in the server
    emission focus lines and timing table
- GitLab still has not surfaced a pipeline for `fbc5566` through the current
  token-backed query.

## Goals

1. Push a clean checkpoint that exposes direct-stream open control round-trip
   and descriptor-open-call timing.
2. Preserve a clean push CI chain on that checkpoint.
3. Once the push chain is green, rerun the focused hosted
   `kTLS HTTP/2 Benchmarks` workflow on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` with
   `skip_artifact_gate=true`.
4. Determine whether the remaining stream-open regression is dominated by
   control-message round-trip overhead or the router-side descriptor-open
   call itself.

## Planned Changes

1. Keep the implementation limited to direct-stream open-path timing and its
   artifact rendering.
2. Push the verified checkpoint and preserve a clean CI chain.
3. Once the push chain is green, dispatch the focused hosted rerun.
4. Use that artifact to choose between deeper control-port/isolate queueing
   instrumentation and descriptor-open/native stream-creation instrumentation.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_bench`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 tool/test_ktls_http2_compare.py`
- `python3 tool/ktls_http2_compare.py tmp/ktls-run-24889688795/baseline/bench_results.summary.json tmp/ktls-run-24889688795/ktls/bench_results.summary.json tmp/ktls-run-24889688795/rerender/comparison.json tmp/ktls-run-24889688795/rerender/comparison.md`
- `bin/verify`
