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
- A steady-state tracked-connection round-robin drain is the first keeper
  under this plan. `_RouterBoss._drainHttp3Requests()` now drains one request
  per HTTP/3 connection per pass before cycling again, and
  `router_runtime_test.dart` now asserts `/a1, /b1, /a2, /b2` ordering across
  two queued HTTP/3 connections instead of draining one connection to
  exhaustion first.
- Local Darwin reruns in `out/h3-http3-round-robin/` beat the last clean
  `out/h3-followup-direction/` baseline in `12/20` throughput quadrants and
  `13/20` p95-latency quadrants. The strongest wins were `s4` at
  `threads=1, workers=1` (`423.07 -> 681.74 Mbps`, `411.66 -> 246.33 ms`),
  `s4` at `threads=1, workers=4` (`406.87 -> 682.61 Mbps`,
  `438.29 -> 238.25 ms`), `s8` at `threads=1, workers=4`
  (`438.08 -> 658.33 Mbps`, `753.53 -> 482.78 ms`), and `s16` at
  `threads=4, workers=4` (`465.43 -> 627.92 Mbps`, `1350.94 -> 980.68 ms`).
- The remaining problem is now absolute queue depth, not just fairness.
  `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json`
  still fails because the shipped gate treats any `backpressure_events` as a
  finding, and the `s2+` workloads still exceed that zero-threshold floor even
  after the round-robin improvement. The next candidate should therefore focus
  on reducing queue depth further rather than reverting the new fair drain.
- A top-level boss-loop priority change was then measured and rejected too.
  Moving `_drainHttp3Requests()` ahead of `_dispatchMessages()` and the other
  maintenance passes in `_loop()` looked plausible as a wake-latency reduction,
  but `out/h3-http3-priority/` regressed `14/20` throughput quadrants and
  `19/20` p95 quadrants versus the kept `out/h3-http3-round-robin/` baseline.
  The worst losses were `s4` at `threads=1, workers=1`
  (`681.74 -> 471.56 Mbps`, `246.33 -> 409.33 ms`), `s8` at
  `threads=1, workers=4` (`658.33 -> 389.74 Mbps`, `482.78 -> 787.97 ms`),
  and `s16` at `threads=1, workers=4` (`678.72 -> 500.11 Mbps`,
  `1104.96 -> 1346.36 ms`).
- A bounded follow-up burst inside `_drainHttp3Requests()` was measured and
  rejected next. Keeping the first fair pass at one request per connection but
  allowing two per connection on later passes reduced some backpressure counts,
  but `out/h3-http3-followup-burst2/` still lost `11/20` throughput quadrants
  and `12/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline. The worst losses were `s4` at
  `threads=1, workers=1` (`681.74 -> 285.04 Mbps`, `246.33 -> 873.80 ms`),
  `s1` at `threads=1, workers=1` (`683.91 -> 435.95 Mbps`,
  `66.64 -> 121.99 ms`), and `s16` at `threads=1, workers=1`
  (`620.66 -> 385.13 Mbps`, `884.91 -> 1449.49 ms`).
- A lighter-weight HTTP/3 request-handle staging experiment was measured and
  rejected next. Draining raw native request handles into a staged Dart list
  before materializing them into `NativeHttpHandshake` objects produced
  `out/h3-http3-handle-stage/`, which won `12/20` throughput quadrants but
  still lost `12/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline while barely moving queue depth. The
  worst losses were `s2` at `threads=4, workers=1`
  (`732.93 -> 659.55 Mbps`, `116.86 -> 132.12 ms`), `s8` at
  `threads=1, workers=1` (`712.03 -> 654.72 Mbps`, `435.16 -> 495.72 ms`),
  and `s16` at `threads=1, workers=4` (`678.72 -> 609.39 Mbps`,
  `1104.96 -> 1114.05 ms`). `bin/check-bench-artifacts --summary out/h3-http3-handle-stage/bench_results.summary.json`
  still failed with `32` findings because the `s2+` quadrants remained above
  the zero-threshold `backpressure_events`/`backpressure_alerts` gate.
- The next candidate should therefore move away from Dart-side handle staging
  and back toward a real native wake/handoff or queue-depth reduction path
  rather than more boss-loop reshaping.
