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
- Three boss-side queue-drain variants were then measured locally and all
  rejected after remeasurement on the shipped
  `native/bench/scenarios/h3_multiplex_scaling.toml` matrix:
  `out/h3-boss-drain-cadence/` (full extra boss-loop queue pass),
  `out/h3-boss-connection-local/` (drain all queued requests on newly accepted
  connections), and `out/h3-boss-http3-burst1/` (drain one immediate HTTP/3
  request on accept).
- The full extra boss-loop queue pass was the worst variant. It improved a few
  `s4/s8` points, but it severely regressed the low-depth `s1` quadrants and
  still did not cleanly reduce deep-queue pressure.
- Draining whole accepted connections immediately helped some deep multi-worker
  points, but it created fairness regressions elsewhere because one connection
  could monopolize the boss loop before later accepted connections were polled.
- The burst-1 HTTP/3 accept drain was the best of the three experiments, but
  it was still too mixed to keep. It improved most `s1` points and some `s16`
  throughput, but it regressed every `s2` quadrant and enough `s4/s8` cases to
  leave the overall matrix worse than the current baseline.
- The next candidate should move inside the steady-state tracked HTTP/3 drain
  path instead of the accept path: a round-robin or bounded-per-connection
  drain budget across already tracked HTTP/3 connections is more likely to
  improve fairness than more accept-time special-casing.
