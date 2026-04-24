# HTTP/2 Direct-Stream Shared Reply Channel

Status: completed

## Context

- Commit `d892676` passed the hosted GitHub push chain:
  - `CI` `24895983686`
  - `kTLS Validation` `24895983707`
  - `WAMP Profile Benchmarks` `24895983693`
- Manual hosted rerun `24897078545` then completed successfully on clean head
  `d892676` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `skip_artifact_gate=true`
- That rerun completed the control-path split and narrowed the remaining blind
  spot:
  - worst p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    - `server direct-stream open round trip avg 12.19 -> 19.09 (+6.90)`
    - `server direct-stream request queue delay avg 5.46 -> 6.56 (+1.10)`
    - `server direct-stream reply delivery delay avg 6.70 -> 12.50 (+5.80)`
- The current implementation still creates a fresh `ReceivePort` for every
  direct-stream open request, so the regressing side of the path is also the
  side with per-open reply-port churn.
- The shared reply-channel implementation is now pushed as `3f60a18`
  (`perf(router): reuse direct-stream reply channel`).
- The visible hosted push chain for `3f60a18` completed successfully:
  - `CI` `24897944475`
  - `WAMP Profile Benchmarks` `24897944543`
- Manual hosted rerun `24898979218` on clean head `3f60a18` then stayed
  `in_progress` far beyond the normal ~4 minute runtime while the benchmark
  job remained stuck in `Run HTTP/2 TLS vs kTLS benchmark`.
- A focused local repro on macOS using the same multiplex scenario without
  Linux-only kTLS support wrote the result summary successfully but left the
  `bench_main.dart` helper process running, which showed the regression was in
  helper-process shutdown rather than the measurement loop.
- Root cause: the shared `DirectStreamReplyChannel` kept a top-level
  `RawReceivePort` open for the full isolate lifetime, so the helper isolate
  never became idle enough to exit after the benchmark finished.

## Goals

1. Keep the shared isolate-local reply channel keyed by request id so the
   reply-delivery optimization remains in place.
2. Close the shared receive port automatically when the channel becomes idle so
   helper isolates can exit cleanly after the benchmark finishes.
3. Add focused regression coverage for both out-of-order reply routing and
   reuse after the channel returns to an idle state.
4. Keep local `bin/verify` green before pushing the fix.

## Planned Changes

1. Make `DirectStreamReplyChannel` allocate its `RawReceivePort` lazily and
   close it again automatically once no reply waiters remain.
2. Preserve the current shared-channel request-id routing semantics so multiple
   concurrent direct-stream opens still share one port while the channel is
   busy.
3. Extend the focused router tests to cover reuse after the channel becomes
   idle again.
4. Re-run the focused local HTTP/2 multiplex benchmark command and confirm the
   helper process exits normally after writing the summary.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/direct_stream_reply_channel_test.dart -r expanded`
- `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
- `bin/verify`

## Outcome

- The fix landed as commit `15185ad` (`fix(router): close shared direct-stream
  reply port`).
- Visible hosted GitHub push validation on that head completed successfully:
  - `CI` `24900200506`
  - `WAMP Profile Benchmarks` `24900200444`
- Manual hosted rerun `24901158700` then completed successfully on clean head
  `15185ad` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `skip_artifact_gate=true`
- That rerun confirmed the helper-exit regression was fixed and moved the
  remaining hotspot away from reply-port lifetime management:
  - worst row:
    `h2_multiplexed_streams_s2`, `threads=1`
    - `server direct-stream open round trip avg 3.60 -> 12.21 (+8.61)`
    - `server direct-stream request queue delay avg 1.91 -> 10.54 (+8.63)`
    - `server direct-stream reply delivery delay avg 1.65 -> 1.63 (-0.02)`
- The next bounded slice is therefore the main-isolate direct-stream control
  path, not further reply-channel work.
