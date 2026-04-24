# HTTP/2 Direct-Stream Completion Hosted Rerun

Status: in_progress

## Context

- Commit `547d6e4` is the last clean hosted head on the branch:
  - `CI` `24884889546`
  - `WAMP Profile Benchmarks` `24884889549`
  - `kTLS Validation` `24884889561`
- GitLab has not surfaced a pipeline for `547d6e4` through the current
  token-backed pipeline query.
- Manual hosted run `24885834166` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  with `skip_artifact_gate=true`.
- That rerun showed the native response-stream slow-path buckets are useful on
  direct response-stream rows, but the current worst p95 row still falls
  outside that measurement boundary:
  - worst throughput row:
    `h2_multiplexed_streams_s2`, `threads=4`
    - `native first chunk channel wait >=1/5/10ms 0/0/0 -> 6/0/0`
    - `native first chunk send call >=1/5/10ms 1/0/0 -> 7/0/0`
  - worst p95 row:
    `h2_multiplexed_streams_s1`, `threads=4`
    - `request round trip p95 13.04 -> 24.95 (+11.90)`
    - `response body first chunk wait avg 1.37 -> 6.12 (+4.75)`
    - no `http_native_response_stream_*` metrics were present for that row
- The current local working tree now carries the next bounded diagnostic fix:
  `HttpResponseStream` exposes `done`, and the bench handlers await that
  direct-stream completion before recording server-emission diagnostics.
- Local verification for that slice is green on 2026-04-24:
  - `bin/test-fast`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `bin/verify`

## Goals

1. Measure server-side direct-stream completion after the async flush actually
   finishes, not while it is still in flight.
2. Make the `h2_multiplexed_streams_s1` rows visible in server-emission
   diagnostics so the current worst p95 hotspot is no longer hidden.
3. Push a clean checkpoint, wait for the branch CI chain to go green, and then
   rerun the focused hosted benchmark on the updated head.

## Planned Changes

1. Keep the current code slice focused on the direct completion boundary:
   `HttpResponseStream.done` plus bench-side awaiting before diagnostics
   capture.
2. Push the verified checkpoint and preserve a clean CI chain.
3. Once the push chain is green, dispatch the focused
   `kTLS HTTP/2 Benchmarks` rerun for
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` with
   `skip_artifact_gate=true`.
4. Use the new artifact to decide whether the missing `s1` hotspot now appears
   in server-emission timing or if another boundary still needs instrumentation.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `bin/verify`
