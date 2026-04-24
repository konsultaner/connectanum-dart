# HTTP/2 Main-Isolate Control-Port Optimization

Status: completed

## Context

- Commit `15185ad` passed the visible hosted GitHub push chain:
  - `CI` `24900200506`
  - `WAMP Profile Benchmarks` `24900200444`
- Manual hosted rerun `24901158700` then completed successfully on clean head
  `15185ad` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `skip_artifact_gate=true`
- That rerun fixed the old reply-channel lifetime regression and narrowed the
  remaining multiplex hotspot to the direct-stream open control path on the
  main isolate.
- Worst throughput and p95 row:
  `h2_multiplexed_streams_s2`, `threads=1`
  - `server direct-stream open round trip avg 3.60 -> 12.21 (+8.61)`
  - `server direct-stream request queue delay avg 1.91 -> 10.54 (+8.63)`
  - `server direct-stream reply delivery delay avg 1.65 -> 1.63 (-0.02)`
- The measured descriptor-open call itself stayed cheap, so the next
  production-relevant optimization target is the main-isolate control listener
  that receives invocation/control messages from internal sessions.

## Goals

1. Reduce direct-stream control-path overhead on the main isolate without
   changing the internal-session protocol shape.
2. Preserve zone-aware behavior for invocation handlers and tests while moving
   the hot control path off `ReceivePort.listen(...)` stream dispatch.
3. Keep local streaming/invocation regressions green before pushing.
4. Maintain a clean `bin/verify` result before handoff.

## Planned Changes

1. Switch `RouterSession` internal control-message delivery from a
   `ReceivePort.listen(...)` subscription to a zone-bound `RawReceivePort`
   handler.
2. Keep the existing response-command port unchanged so request/command reply
   behavior is isolated from the control-path optimization.
3. Re-run focused HTTP/2 and HTTP/3 native streaming regressions plus the
   local multiplex bench repro to confirm no functional drift on the optimized
   path.
4. Refresh `docs/project_state.md` after verification so continuation resumes
   from the new active plan and last-known clean checkpoint.

## Progress

- The implementation is now pushed as commit `25b2b7a`
  (`perf(router): use raw control port for internal sessions`).
- Visible hosted GitHub push validation on that head is currently in progress:
  - `CI` `24902101047`
  - `WAMP Profile Benchmarks` `24902101976`
- GitLab has not surfaced a pipeline for `25b2b7a` through the current
  token-backed API query.
- The local working tree now replaces the internal-session main-isolate
  control listener with a zone-bound `RawReceivePort` handler in
  `RouterSession`, while leaving the command-response port on `ReceivePort`.
- The zone binding is required: the first raw-port attempt delivered
  invocation callbacks outside the current zone and surfaced
  `OutsideTestException` in `router_runtime_test.dart`, so the final version
  preserves existing zone semantics while removing stream-subscription
  dispatch from the hot control path.
- Focused local verification is currently green on this in-progress checkpoint:
  - `bin/test-fast`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/3 response chunks using native streams' -r expanded`
  - `dart analyze packages/connectanum_router`
  - `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
  - `bin/verify`

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
- `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/3 response chunks using native streams' -r expanded`
- `dart analyze packages/connectanum_router`
- `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
- `bin/verify`

## Outcome

- The optimization landed as commit `25b2b7a`
  (`perf(router): use raw control port for internal sessions`).
- Visible hosted GitHub push validation on that head completed successfully:
  - `CI` `24902101047`
  - `WAMP Profile Benchmarks` `24902101976`
- GitLab still did not surface a pipeline for `25b2b7a` through the current
  token-backed API query.
- The next bounded step is a focused hosted rerun of
  `kTLS HTTP/2 Benchmarks` on clean head `25b2b7a` with the multiplex-only
  scenario, so the repo can verify whether the main-isolate control-path
  change reduced the `direct_stream_request_queue_delay` hotspot on the real
  Linux kTLS comparison path.
