# HTTP/2 Direct-Stream Shared Reply Channel

Status: in_progress

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

## Goals

1. Replace the per-open direct-stream reply port with a shared isolate-local
   reply channel keyed by request id.
2. Preserve the existing benchmark metrics so the next hosted rerun can show
   whether reply-delivery delay improved.
3. Add focused regression coverage for reply routing, including out-of-order
   replies on the shared channel.
4. Keep local `bin/verify` green before pushing.

## Planned Changes

1. Add a shared direct-stream reply channel helper in the router HTTP layer
   that owns one receive port and routes replies back to pending completers by
   request id.
2. Update `HttpResponseStream` direct-stream opens to use that helper instead
   of allocating a one-shot `ReceivePort` per request.
3. Thread the request id through the control reply map in the internal session
   handler, including error replies.
4. Add a focused router test for out-of-order reply routing and keep the
   existing benchmark diagnostics intact.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/direct_stream_reply_channel_test.dart -r expanded`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded`
- `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`
