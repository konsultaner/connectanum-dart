# HTTP/2 Main-Isolate Control-Port Hosted Rerun

Status: completed

## Context

- Commit `25b2b7a` (`perf(router): use raw control port for internal
  sessions`) passed the visible hosted GitHub push chain:
  - `CI` `24902101047`
  - `WAMP Profile Benchmarks` `24902101976`
- The completed implementation slice replaced the internal-session
  main-isolate control listener with a zone-bound `RawReceivePort` handler,
  which is the concrete path measured by
  `direct_stream_request_queue_delay`.
- The previous hosted multiplex rerun on clean head `15185ad`
  (`24901158700`) showed the remaining worst row at
  `h2_multiplexed_streams_s2`, `threads=1` with:
  - `server direct-stream open round trip avg 3.60 -> 12.21 (+8.61)`
  - `server direct-stream request queue delay avg 1.91 -> 10.54 (+8.63)`
  - `server direct-stream reply delivery delay avg 1.65 -> 1.63 (-0.02)`
- With `25b2b7a` now green, the next release-relevant question is whether the
  control-path optimization actually improves that hosted Linux kTLS delta.

## Goals

1. Dispatch a focused hosted `kTLS HTTP/2 Benchmarks` rerun on clean head
   `25b2b7a` using the multiplex-only scenario and `skip_artifact_gate=true`.
2. Compare the new hotspot row against run `24901158700`, with attention to
   `direct_stream_request_queue_delay`, `direct_stream_open_round_trip`, and
   the related headers/first-body timings.
3. Record the new measurement boundary in `docs/project_state.md` and choose
   the next bounded action from the result.

## Planned Steps

1. Trigger `kTLS HTTP/2 Benchmarks` on ref `add-router` with:
   - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
   - `router_worker_counts=1`
   - `native_runtime_thread_counts=1,4`
   - `skip_artifact_gate=true`
2. Wait for the manual run to complete and download/extract the benchmark
   artifact bundle.
3. Inspect `comparison.md` / `comparison.json` for the new worst row and note
   whether the queue-delay hotspot shrank, moved, or stayed flat.
4. Update the active plan and `docs/project_state.md` with the hosted result.

## Verification

- Manual GitHub workflow `kTLS HTTP/2 Benchmarks` on commit `25b2b7a`

## Outcome

- Manual hosted rerun `24903103241` completed successfully on clean head
  `25b2b7a` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `skip_artifact_gate=true`
- The main-isolate control-port optimization closed the old queue-delay
  hotspot on `h2_multiplexed_streams_s2`, `threads=1`:
  - `server direct-stream open round trip avg 3.60 -> 12.21 (+8.61)` on
    `15185ad` rerun `24901158700` became `3.46 -> 4.13 (+0.67)`
  - `server direct-stream request queue delay avg 1.91 -> 10.54 (+8.63)` on
    `15185ad` rerun `24901158700` became `1.69 -> 1.46 (-0.23)`
- The remaining worst p95 row moved deeper into the native HTTP/2 response
  path on `h2_multiplexed_streams_s8`, `threads=1`:
  - `response headers wait avg 23.75 -> 30.65 (+6.90)`
  - `response body first chunk wait avg 11.09 -> 23.94 (+12.84)`
  - `native headers-to-first-connection-write avg 0.06 -> 2.35 (+2.29)`
  - `native first chunk channel wait avg 0.42 -> 1.00 (+0.58)`
- The next bounded implementation slice is therefore to let the HTTP/2
  connection driver run after headers and the first queued body chunk, instead
  of staying on the old control-path investigation lane.
