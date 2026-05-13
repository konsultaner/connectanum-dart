# HTTP/2 Multiplex-Aware Header Yield

Status: completed

## Context

- Commit `070b229` (`perf(http2): keep yield on first streamed chunk only`)
  passed the visible hosted GitHub push chain:
  - `CI` `24905612643`
  - `kTLS Validation` `24905612638`
  - `WAMP Profile Benchmarks` `24905612662`
- Manual hosted rerun `24906538797` then completed successfully on clean head
  `070b229` with the focused multiplex scenario and `skip_artifact_gate=true`.
- That rerun proved the low-contention `s1` regression came from the
  unconditional header yield:
  - `h2_multiplexed_streams_s1`, `threads=1` improved from
    `-60.21%` throughput / `+124.86%` p95 on `24904942758`
    to `-14.98%` throughput / `+13.38%` p95
- But removing the header yield entirely re-opened the multiplex regressions:
  - `h2_multiplexed_streams_s2`, `threads=1` fell to `-60.98%` throughput
  - `h2_multiplexed_streams_s16`, `threads=1` rose to `+73.72%` p95
  - `h2_multiplexed_streams_s8`, `threads=1` regressed back to
    `-31.10%` throughput / `+42.83%` p95
- The regression signature points back at actual contention on the shared HTTP/2
  writer:
  - `queue_to_first_body_write`, `direct_stream_reply_delivery_delay`, and
    `headers_to_first_chunk_dequeue` rose again on `s8` and `s16`
  - `s1` stayed much better
- That combination suggests the header yield is still useful, but only when
  multiple streamed responses are contending on the same connection.

## Goals

1. Preserve the `s1` recovery from `070b229`.
2. Restore the multiplex benefit of letting the shared HTTP/2 writer make
   progress when multiple response headers are queued.
3. Keep the change bounded to the native HTTP/2 streamed-response scheduler
   path and revalidate locally before the next hosted rerun.

## Planned Changes

1. Make `Http2ConnectionWriteTracker` report how many header sends are pending
   before the first connection write.
2. Yield after `send_response(..., false)` only when more than one response has
   queued headers on the connection.
3. Add focused tracker coverage for the pending-header count behavior.
4. Re-run focused native/Dart regressions plus the local multiplex bench repro.
5. Re-run `bin/verify`, then push and repeat the focused hosted
   `kTLS HTTP/2 Benchmarks` rerun once the push chain is green.

## Progress

- The multiplex-aware follow-up is now pushed as commit `a2e7f81`
  (`perf(http2): yield on header contention only`).
- The change in `native/transport/ct_core/src/lib.rs` is:
  - `note_headers_sent(...)` now returns the current pending-header count
  - the header-side yield now triggers only when `pending_headers > 1`
  - the first-chunk yield remains unchanged
- New focused tracker coverage is in place:
  - `http2_connection_write_tracker_counts_pending_headers`
- Local verification is green on this in-progress checkpoint:
  - `bin/test-fast`
  - `cargo test --manifest-path native/transport/ct_core/Cargo.toml http2_connection_write_tracker -- --nocapture`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
  - `bin/verify`
- Visible hosted GitHub push validation completed on that head:
  - `CI` `24907299479`
  - `kTLS Validation` `24907299524`
  - `WAMP Profile Benchmarks` `24907299451`
- GitLab has not surfaced an `add-router` pipeline for `a2e7f81` through the
  current token-backed API query.

## Hosted Checkpoint

- Hosted GitHub push validation on `a2e7f81` completed successfully:
  - `CI` `24907299479`
  - `kTLS Validation` `24907299524`
  - `WAMP Profile Benchmarks` `24907299451`
- Manual hosted rerun `24908173404` completed successfully on clean head
  `a2e7f81`, but the result is not decision-quality:
  - `h2_multiplexed_streams_s4`, `threads=4` showed a baseline collapse to
    `868 Mbps`
  - `h2_multiplexed_streams_s8`, `threads=4` swung the other way to
    `-66.89%` throughput / `+423.33%` p95
  - those outliers contradict the prior hosted reruns and the local repro, so
    they are more consistent with host instability than with a coherent
    scheduler regression
- Confirmatory rerun `24908372116` also completed successfully on the same
  clean head, but it did not converge on the same hotspot shape:
  - worst throughput row moved to
    `h2_multiplexed_streams_s2`, `threads=4` at `-83.11%`
  - worst p95 row also moved to
    `h2_multiplexed_streams_s2`, `threads=4` at `+1316.65%`
  - the earlier `s4`, `threads=4` baseline collapse did not repeat, while
    `s2`, `threads=4` became the new outlier
- That means the scheduler change itself reached a real evidence-quality
  boundary: the next blocker is hosted benchmark stability, not another blind
  HTTP/2 scheduler tweak on top of `a2e7f81`.
- Follow-up continuation moved to
  `docs/exec-plans/2026-04-24-ktls-repeat-stability.md`.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/transport/ct_core/Cargo.toml http2_connection_write_tracker -- --nocapture`
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
- `bin/verify`
