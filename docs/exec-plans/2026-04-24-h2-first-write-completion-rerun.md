# HTTP/2 First-Write Completion Rerun

Status: completed

## Context

- Commit `7755828` is the last green hosted head on the branch:
  - `kTLS Validation` `24878452943`
  - `WAMP Profile Benchmarks` `24878452920`
  - `CI` `24878452921`
- Manual hosted run `24879483421` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  and showed that the current server-emission signal is too early:
  - client-side `response_headers_wait_avg_ms` and
    `response_body_first_chunk_wait_avg_ms` still regressed materially
  - server-side `headers_to_first_body_write_avg_ms`,
    `queue_to_first_body_write_avg_ms`, and `first_body_write_avg_ms`
    stayed flat at `0.00 -> 0.00`
- The current `onFirstBodyWrite` callback fires immediately before the
  synchronous `stream.add(...)` call into the native response stream, so it
  cannot distinguish native write blocking from downstream transport delay.
- The local working tree now carries that post-write instrumentation slice
  across the router callback boundary, `bench_http_stream`, native artifact
  summaries, and comparison rendering. The remaining work in this plan is to
  verify the slice, push it cleanly, and capture the next hosted rerun.

## Goals

1. Add a post-write callback boundary after the first response-stream write
   call returns.
2. Thread that signal through `bench_http_stream`, native artifact summaries,
   and comparison output.
3. Push the clean checkpoint and rerun the focused hosted
   `kTLS HTTP/2 Benchmarks` workflow so the next artifact can show whether the
   remaining gap appears before or after the first write returns.

## Planned Changes

1. Extend the HTTP response-stream instrumentation with
   `onFirstBodyWriteCompleted`.
2. Add aggregate metrics for:
   - `first_body_write_completed`
   - `headers_to_first_body_write_completed`
   - `queue_to_first_body_write_completed`
   - `first_body_write_call`
3. Update the comparison focus lines and server-emission table to render the
   new completion boundary.
4. Verify locally, then push and wait for the push CI chain before running the
   next focused hosted rerun.

## Outcome

- Commit `b8645af` passed the hosted push chain cleanly:
  - `kTLS Validation` `24880362805`
  - `WAMP Profile Benchmarks` `24880362819`
  - `CI` `24880362829`
- Manual workflow run `24881249566` reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head
  with `skip_artifact_gate = true` and completed successfully.
- The rerun answered the current question directly:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s4`, `threads=4`
    - `response headers wait avg +8.38 ms`
    - `response body first chunk wait avg +19.33 ms`
    - `response body tail read avg +3.00 ms`
  - the first-write-completion boundary stayed flat across comparable rows:
    - `headers_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `queue_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_call_avg_ms 0.00 -> 0.00 (+0.00)`
- That means the remaining delay still opens after the first native
  response-stream write returns. The next bounded slice is therefore native
  response-stream handoff timing, not more Dart-side write timing.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_bench/lib/src/http_stream_handler.dart packages/connectanum_bench/tool/bench_main.dart packages/connectanum_router/lib/src/router/http/http_context.dart packages/connectanum_bench/test/http_stream_handler_test.dart packages/connectanum_router/test/router_runtime_test.dart`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name "HTTP/2 stream response callbacks fire once in open-write-complete order" -r expanded`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24879483421`
- `bin/verify`
