# HTTP/2 Isolated Regression Diagnosis

Status: in_progress

## Context

- Commit `1fa0c45` (`build(ktls): isolate hotspot stability reruns`) passed the
  visible GitHub push chain:
  - `CI` `24917321434`
  - `kTLS Validation` `24917321426`
  - `WAMP Profile Benchmarks` `24917321423`
- Manual hosted rerun `24917876488` isolated
  `h2_multiplexed_streams_s4`, `threads=4` into a decision-quality result:
  - throughput delta `-17.35%..-12.20%`
  - p95 delta `+4.19%..+12.00%`
  - stable backpressure increase: `71 -> 82 (+11)` events,
    `2 -> 3 (+1)` alerts
  - stable header-wait increase: `17.55 -> 21.16 (+3.61)` ms
- Manual hosted rerun `24917873323` isolated
  `h2_multiplexed_streams_s1`, `threads=4` and still showed wide kTLS-side
  throughput spread without transport counters or connection churn.
- Manual hosted rerun `24918088324` retried isolated `s1` with
  `repeat_count=5` and failed in the benchmark step, but the completed repeats
  converged to decision-quality spans before a long-repeat baseline stall on
  partial `repeat-04`.
- That means the broad repeat-stability question is no longer the blocker.
  The blocker is now diagnosis:
  - `s4` is a real multiplex/backpressure regression shape.
  - `s1` is likely a real low-contention first-body-delivery regression shape.
  - the long-repeat baseline stall is a separate harness issue.

## Goals

1. Use the isolated `s1` and `s4` evidence to choose the next transport
   diagnosis path instead of repeating broad methodology work.
2. Reproduce or instrument the `s1` low-contention path so the missing
   client-side first-body delivery gap becomes visible.
3. Keep the `s4` stable backpressure/header-wait result as the reference shape
   for multiplex-path work.
4. Track the long-repeat baseline stall as a harness issue without letting it
   blur the stable transport evidence.

## Planned Changes

1. Inspect the existing client-side and native HTTP/2 receive-side timing path
   around first body delivery for isolated `s1`.
2. Add the smallest missing metric or repro needed to expose where the `s1`
   gap appears after server emission has already improved.
3. Keep the current kTLS manual workflow unchanged unless the harness stall
   blocks diagnosis again.
4. Update project state and docs only when the diagnosis path or verification
   state changes.

## Progress

- The smallest missing metric is now implemented in the native bench H2 client
  path:
  - `native/bench/src/bin/http_stream.rs` now wraps the HTTP/2 client
    transport and records the first successful socket read after response
    headers arrive
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` now carry
    and summarize:
    `response_body_post_header_connection_read_wait_*` and
    `response_body_connection_read_to_first_chunk_*`
  - `tool/ktls_http2_compare.py` now renders those fields in the response-body
    diagnostics table and focus line output
- That split is intentionally narrow:
  - if isolated hosted `s1` shows the regression in
    `post_header_connection_read_wait`, the remaining gap is before the next
    socket read
  - if it instead shows up in
    `connection_read_to_first_chunk`, bytes are reaching the client promptly
    and the delay is inside the HTTP/2 body path after read completion
- Focused local verification is now green on the diagnosis slice.

## Current Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records_post_header_read_split -- --nocapture`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`

## Next Step

Run the next isolated hosted `s1` rerun on the clean branch head with the same
stability settings as `24917873323`, then use the new receive-side split to
decide whether the remaining first-body gap appears before the first
post-header connection read or inside the HTTP/2 client body path after that
read completes.
