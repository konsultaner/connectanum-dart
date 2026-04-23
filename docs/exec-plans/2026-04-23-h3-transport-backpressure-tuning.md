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

## Findings

- The local Darwin `h3_multiplex_scaling` counters confirmed that the reported
  HTTP/3 `backpressure_events` are sourced from
  `ListenerRegistry::enqueue_http_request()` queue depth, not Quinn send-side
  pressure.
- A send-side response chunking experiment was measured and rejected. `32 KiB`
  and `64 KiB` HTTP/3 body-write chunking changed throughput and latency, but
  they did not materially reduce the benchmark's backpressure counters, so that
  path is not the primary bottleneck.
- An HTTP/3 accept-loop backlog gate was also measured and rejected for now.
  `soft_limit = 1` drove backpressure events to zero, proving the queue source,
  but it over-serialized the workload. `soft_limit = 4` capped
  `max_backpressure_depth` at `4` and helped some `s4/s8` and one `s16`
  combination, but it still regressed too many other quadrants to keep.
- The next candidate should target boss-loop request-drain cadence or queue
  handoff scheduling around the native HTTP request backlog rather than QUIC
  body-write chunking.
