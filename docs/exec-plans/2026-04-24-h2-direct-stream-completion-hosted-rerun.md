# HTTP/2 Direct-Stream Completion Hosted Rerun

Status: completed

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
- Commit `a12227d` passed the visible hosted GitHub push chain cleanly:
  - `CI` `24886626863`
  - `WAMP Profile Benchmarks` `24886626856`
- `kTLS Validation` still did not surface for `a12227d` through the GitHub
  API, and GitLab also did not surface a pipeline for that head through the
  current token-backed query.

## Outcome

1. Manual hosted run `24887510264` reran
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on clean head
   `a12227d` with `skip_artifact_gate=true` and completed successfully.
2. The direct-stream completion fix worked:
   - `h2_multiplexed_streams_s1` rows now appear in `HTTP Server Emission Timing`
   - the earlier missing-row blind spot was a bench sampling bug, not a
     transport-path absence
3. The hotspot moved back to the deeper multiplex rows:
   - worst throughput row:
     `h2_multiplexed_streams_s8`, `threads=4`
     - `response headers wait avg 24.33 -> 37.67 (+13.34)`
     - `response body first chunk wait avg 7.40 -> 15.76 (+8.35)`
     - `server stream open avg 11.88 -> 14.12 (+2.24)`
     - `server first body write completed avg 11.93 -> 14.17 (+2.24)`
     - `native first chunk channel wait avg 0.22 -> 0.37 (+0.16)`
     - `native headers-to-first-chunk-dequeue avg 5.93 -> 8.59 (+2.66)`
     - `native first chunk send call avg 0.32 -> 0.87 (+0.54)`
     - `native headers-to-first-chunk-send-call avg 6.26 -> 9.46 (+3.20)`
4. That result closes this plan. The next missing boundary is no longer
   direct-stream completion. It is the native gap from response-stream open to
   HTTP/2 header dispatch, because the client-visible header delay is still
   materially larger than the current server-emission and first-chunk handoff
   deltas.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `bin/verify`
