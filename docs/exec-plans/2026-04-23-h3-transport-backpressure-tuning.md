## Goal

Reduce the HTTP/3 multiplex regressions that still appear at deeper reused
connection depths by targeting the transport/backpressure path directly.

## Scope

- use the shipped `native/bench/scenarios/h3_multiplex_scaling.toml` scenario
  as the primary benchmark and regression surface
- inspect the current native HTTP/3 response path and Quinn transport tuning
  for sources of unfair or bursty write pressure under `streams_per_connection`
  `4/8/16`
- land one transport-side improvement and remeasure it against the current
  `router_workers = 1,4` and `native_runtime_threads = 1,4` baseline where
  needed
- keep the checked-in roadmap and project state aligned with the measured
  outcome

## Non-goals

- changing the application-level router worker scheduling model first
- redesigning the benchmark workloads or changing their semantics
- making hosted Linux claims before local verification is green again

## Verification

- `bin/test-fast`
- focused local HTTP/3 benchmark reruns via
  `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --scenario native/bench/scenarios/h3_multiplex_scaling.toml ...`
- `bin/verify`

## Status

- in_progress
