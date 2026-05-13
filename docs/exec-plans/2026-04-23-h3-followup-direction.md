## Goal

Choose the next HTTP/3 implementation target from data instead of intuition:
determine whether the next milestone should focus on transport/backpressure
tuning or on application response scheduling.

## Scope

- reuse the shipped `native/bench/scenarios/h3_multiplex_scaling.toml`
  workload instead of inventing a new synthetic shape
- run a small local sweep across router-worker and native-runtime-thread
  combinations so the results separate boss/runtime transport pressure from
  application-side scheduling
- capture the conclusion in checked-in docs and reduce the roadmap ambiguity

## Non-goals

- implementing the chosen HTTP/3 optimization in this same step
- changing the benchmark workload contract unless the existing one is
  insufficient to answer the scheduling-vs-transport question
- making claims about hosted Linux behavior without local evidence first

## Verification

- `bin/test-fast`
- targeted local `cargo run --bin http_stream -- --scenario native/bench/scenarios/h3_multiplex_scaling.toml ...`
- `bin/verify`

## Status

- completed

## Conclusion

- Completed with a local Darwin sweep of the shipped
  `native/bench/scenarios/h3_multiplex_scaling.toml` scenario across
  `router_workers = 1,4` and `native_runtime_threads = 1,4`.
- The resulting direction is to target HTTP/3 transport/backpressure tuning
  next, not application response scheduling.
- Extra router workers only helped the lowest-multiplex `s1` point
  (`721.60 Mbps`, p95 `54.61 ms` at `threads=1, workers=4`) and were neutral
  or harmful at the higher-depth `s4/s8/s16` points.
- The higher-depth regressions still line up with H3 backpressure pressure, not
  router-worker starvation:
  `s16` stayed at `103-117` backpressure events across all combinations and
  fell as low as `465.43 Mbps` / p95 `1350.94 ms`.
