## Goal

Extend the shipped HTTP/3 multiplex scaling benchmark beyond the current
single `streams_per_connection = 4` workload so the repo has a checked-in
ceiling-mapping sweep and an updated local baseline.

## Scope

- expand `native/bench/scenarios/h3_multiplex_scaling.toml` into a real
  streams-per-connection sweep instead of a single point measurement
- keep the workload shape stable enough that results remain comparable to the
  existing HTTP/2 and runtime-thread scaling baselines
- run the expanded scenario locally to capture an updated Darwin baseline
- refresh checked-in state/docs when the new benchmark slice lands

## Non-goals

- redesigning the HTTP benchmark orchestrator
- changing the transport implementation unless the expanded sweep exposes a
  clear bug in the already-shipped HTTP/3 multiplex path
- broadening the same slice into HTTP/2 scenario changes unless parity work is
  trivial and directly useful for comparison

## Verification

- `bin/test-fast`
- focused scenario/config parsing checks
- focused local `cargo run --bin http_stream -- --scenario native/bench/scenarios/h3_multiplex_scaling.toml ...`
- `bin/verify`

## Status

- completed

## Handoff

- Completed. `native/bench/scenarios/h3_multiplex_scaling.toml` now sweeps
  `streams_per_connection = 1, 2, 4, 8, 16`, the bench docs and roadmap note
  now describe it as the shipped H3 multiplex ceiling map, and a focused local
  Darwin run with `router_workers = 1` plus native runtime threads `1,4`
  recorded the current baseline. The best response-throughput points were
  `643.73 Mbps` / p95 `463.68 ms` at `8` streams for `1` native runtime
  thread and `672.77 Mbps` / p95 `58.37 ms` at `1` stream for `4` native
  runtime threads; `16` streams raised latency and backpressure more than
  throughput. `bin/verify` passed on the final tree.
