# kTLS Repeat Stability

Status: completed

## Context

- Commit `a2e7f81` (`perf(http2): yield on header contention only`) passed the
  visible hosted GitHub push chain:
  - `CI` `24907299479`
  - `kTLS Validation` `24907299524`
  - `WAMP Profile Benchmarks` `24907299451`
- Two focused manual hosted reruns then landed successfully on that same clean
  head with `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` and
  `skip_artifact_gate=true`:
  - `24908173404`
  - `24908372116`
- Those reruns did not converge on a stable decision:
  - `24908173404` showed a baseline collapse on
    `h2_multiplexed_streams_s4`, `threads=4`, making it look like a massive
    kTLS win
  - `24908372116` instead made
    `h2_multiplexed_streams_s2`, `threads=4` the worst throughput and p95 row
  - both runs contradict each other and the local repro closely enough that the
    blocker is now hosted benchmark stability rather than missing HTTP/2
    scheduler instrumentation

## Goals

1. Keep the default single-pass kTLS workflow unchanged for ordinary push/CI use.
2. Add a bounded repeat-run path for manual hosted diagnostics.
3. Make the top-level artifact clearly state whether repeated hosted evidence is
   decision-quality or too noisy to drive the next transport change.

## Planned Changes

1. Add `--repeat-count` to `bin/ktls-http2-bench`.
2. Add matching `repeat_count` input wiring to
   `.github/workflows/ktls-http2-benchmarks.yml`.
3. Generate per-repeat comparison artifacts and a top-level aggregate
   repeat-stability summary.
4. Add focused Python regression coverage for the new aggregation path.
5. Update bench/state/docs so the next rerun uses the repeat-stability report
   instead of a single comparison file.

## Progress

- `bin/ktls-http2-bench` now accepts `--repeat-count <n>`.
- With `repeat_count > 1`, per-repeat artifacts now land under
  `repeats/repeat-XX/{baseline,ktls,comparison.json,comparison.md}` and the
  top-level `comparison.json` / `comparison.md` pair becomes the aggregate
  repeat-stability report.
- The manual GitHub workflow now exposes the same control through the
  `repeat_count` input.
- `tool/ktls_http2_compare_repeats.py` now aggregates repeated comparison JSON
  outputs and reports:
  - worst-row consistency across repeats
  - per-row throughput / p95 delta spans
  - the largest unstable rows
  - whether the repeated evidence is decision-quality under explicit span
    thresholds
- `tool/test_ktls_http2_compare.py` now covers the repeat-stability path.
- Full local verification is now green:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `python3 tool/ktls_http2_compare_repeats.py /tmp/ktls-repeat-summary.json /tmp/ktls-repeat-summary.md /tmp/ktls-run-24908173404/extracted/comparison.json /tmp/ktls-run-24908372116/extracted/comparison.json`
  - `bin/verify`
- The repeat-stability tooling is now pushed as commit `d66a72d`
  (`build(ktls): add repeat stability reporting`).
- The visible GitHub push chain for `d66a72d` completed successfully:
  - `CI` `24910233897`
  - `kTLS Validation` `24910233859`
  - `WAMP Profile Benchmarks` `24910233901`
- Focused manual hosted rerun `24911158486` ran with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That rerun completed successfully, but the aggregate artifact still marked
  the evidence as not decision-quality:
  - worst throughput row changed across all three repeats
  - worst p95 row changed across all three repeats
  - `h2_multiplexed_streams_s4`, `threads=1` spanned `77.77pp` throughput
    delta
  - `h2_multiplexed_streams_s2`, `threads=1` spanned `1174.48pp` p95 delta
- The instability is still on the kTLS side, not on the baseline side:
  - `h2_multiplexed_streams_s2`, `threads=1` baseline throughput only spanned
    `470.25 Mbps`, while kTLS throughput spanned `3470.66 Mbps`
  - `h2_multiplexed_streams_s2`, `threads=1` baseline p95 only spanned
    `2.34 ms`, while kTLS p95 spanned `190.52 ms`
- The current working tree now carries the next bounded stabilization slice:
  - `native/bench/scenarios/h2_ktls_multiplex_stability.toml` keeps the same
    multiplex sweep but raises each workload to `48` iterations with
    `1000 ms` warmup
  - `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` stays unchanged as
    the quick spot-check scenario
  - `native/bench/README.md` now separates quick diagnostic usage from
    decision-quality repeat usage
- That stabilization slice is now pushed as commit `c0e9171`
  (`build(ktls): add stability benchmark scenario`).
- Local verification was green before that push:
  - `bin/test-fast`
  - `bin/verify`
- The visible GitHub push chain for `c0e9171` completed successfully:
  - `CI` `24911914621`
  - `kTLS Validation` `24911914629`
  - `WAMP Profile Benchmarks` `24911914617`
- Focused manual hosted rerun `24912748466` completed successfully with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That larger-sample rerun still did not reach decision quality, but it
  narrowed the instability sharply:
  - every remaining row that exceeded the stability thresholds used
    `native_runtime_threads=4`
  - the `native_runtime_threads=1` rows now fit within the current
    throughput/p95 span thresholds
  - `h2_multiplexed_streams_s16`, `threads=4` stayed the worst p95 row in
    `2/3` repeats, with p95 delta spanning `641.63pp`
  - `h2_multiplexed_streams_s4`, `threads=4` showed a baseline collapse in one
    repeat, producing a `228.53pp` throughput-delta span
- Focused manual hosted rerun `24913116550` then completed successfully with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That isolated `threads=4` rerun still did not reach decision quality:
  - `h2_multiplexed_streams_s16`, `threads=4` remained the worst p95 row in
    `2/3` repeats, with p95 delta spanning `460.16pp`
  - `h2_multiplexed_streams_s2`, `threads=4` still showed a baseline collapse
    in one repeat, producing a `216.79pp` throughput-delta span
  - `h2_multiplexed_streams_s1`, `threads=4` also still showed baseline-side
    instability, with throughput delta spanning `124.79pp`
- The current branch head now carries a bounded repeat-analysis slice:
  - `tool/ktls_http2_compare_repeats.py` labels unstable rows as
    baseline-side, kTLS-side, or mixed for throughput and p95 span sources
  - the repeat summary markdown now emits an `Instability source highlights`
    section and source columns in the threshold table
  - `tool/test_ktls_http2_compare.py` pins the new classification and markdown
    output
- Local verification is green on that slice:
  - `bin/test-fast`
  - focused Python compile/tests and repeat-summary rerenders against hosted
    runs `24912748466` and `24913116550`
  - `bin/verify`
- The new source labeling confirms the remaining blocker is mixed hosted noise:
  - `h2_multiplexed_streams_s16`, `threads=4` still skews kTLS-side
  - `h2_multiplexed_streams_s2`, `threads=4` and `s1`, `threads=4` skew
    baseline-side for throughput instability
- That repeat-analysis slice is now pushed as commit `a2a66ea`
  (`build(ktls): label repeat instability sources`).
- The current branch head now carries the next bounded methodology slice:
  - `bin/ktls-http2-bench` accepts `--repeat-order` and
    `--cooldown-seconds`
  - repeated runs emit `repeat-plan.txt`, recording the exact pass order and
    cooldown used for each repeat
  - `.github/workflows/ktls-http2-benchmarks.yml` exposes the same controls and
    defaults manual repeats to `repeat_order=alternating` plus
    `cooldown_seconds=15`
  - `native/bench/README.md` documents those runner-control defaults
- Local verification is green on that slice:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `bin/ktls-http2-bench --help | rg 'repeat-order|cooldown-seconds|repeat-count'`
  - `bin/verify`
- That runner-control slice is now pushed as commit `45fcba8`
  (`build(ktls): add repeat cooldown controls`).
- Its visible GitHub push chain completed successfully:
  - `CI` `24914678995`
  - `kTLS Validation` `24914678987`
  - `WAMP Profile Benchmarks` `24914678985`
- Manual hosted rerun `24915345703` completed successfully on that clean head
  with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=alternating`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That first controlled rerun did not reach decision quality, but it improved
  throughput stability materially versus `24913116550`:
  - largest throughput span dropped from `216.79pp` on
    `h2_multiplexed_streams_s2` to `47.32pp` on `s1`
  - the old `h2_multiplexed_streams_s16` p95 outlier disappeared
  - the only `ktls-first` repeat (`repeat-02`) was also the clear outlier,
    with `h2_multiplexed_streams_s8` jumping to `+457.45%` p95
- Manual hosted rerun `24915629218` then completed successfully with the same
  settings except `repeat_order=baseline-first`.
- That confirmation rerun still did not reach decision quality, but it
  narrowed the blocker further:
  - `h2_multiplexed_streams_s8`, `s16`, and `s2` all stabilized into
    in-family ranges
  - the remaining blocker is now concentrated in a baseline-side
    `h2_multiplexed_streams_s4` spike and a kTLS-side
    `h2_multiplexed_streams_s1` throughput spread
  - `s4` now drives the largest spans: `64.53pp` throughput and `119.62pp`
    p95, with one baseline repeat reaching `216.48 ms` p95 while kTLS stayed
    near `32-35 ms`

- Manual hosted rerun `24916589841` then completed successfully with the same
  settings as `24915629218` except `cooldown_seconds=60`.
- That longer-cooldown rerun made the lane less stable again:
  - `h2_multiplexed_streams_s2` returned as the worst throughput and p95 row
    with a `76.69pp` throughput span and `981.77pp` p95 span, both kTLS-side
  - `h2_multiplexed_streams_s8` and `s16` also became unstable again on the
    baseline side
  - the result is materially worse than the `15s` baseline-first run, so
    larger sleeps are not a monotonic fix
- The current working tree now carries the next structural methodology slice:
  - `tool/filter_bench_scenario.py` materializes a temporary focused scenario
    by keeping only named workloads from an existing checked-in scenario
  - `bin/ktls-http2-bench` now accepts `--workloads <csv>` and records both
    `scenario_source` and `scenario_effective` in `host-info.txt`
  - the manual `kTLS HTTP/2 Benchmarks` workflow exposes the same workload
    filter as the `workloads` input
  - `native/bench/README.md` now documents hotspot-isolated reruns instead of
    only full-scenario stability reruns
- Focused local verification is green on that slice:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `python3 -m py_compile tool/filter_bench_scenario.py tool/test_filter_bench_scenario.py tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_filter_bench_scenario.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `python3 tool/filter_bench_scenario.py native/bench/scenarios/h2_ktls_multiplex_stability.toml /tmp/connectanum-ktls-filtered.toml h2_multiplexed_streams_s4,h2_multiplexed_streams_s8`
  - `bin/ktls-http2-bench --help | rg 'workloads|repeat-order|cooldown-seconds|repeat-count'`
  - `bin/verify`
- That workload-isolation slice is now pushed as commit `1fa0c45`
  (`build(ktls): isolate hotspot stability reruns`).
- Its GitHub push chain completed successfully:
  - `CI` `24917321434`
  - `kTLS Validation` `24917321426`
  - `WAMP Profile Benchmarks` `24917321423`
- Manual hosted rerun `24917873323` then completed successfully on that clean
  head with the planned isolated `s1` settings:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `workloads=h2_multiplexed_streams_s1`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=baseline-first`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That isolated `s1` rerun still did not become decision-quality:
  - throughput delta spanned `46.95pp`, from `-62.63%` to `-15.68%`
  - p95 delta stayed within threshold at `42.53pp`
  - there were no non-zero transport counters, no connection churn, and
    server-emission timings improved while client-side first-chunk/body-read
    timings regressed
- Manual hosted rerun `24917876488` then completed successfully on the same
  clean head with the same settings except
  `workloads=h2_multiplexed_streams_s4`.
- That isolated `s4` rerun is decision-quality:
  - throughput delta stayed within `5.15pp`, from `-17.35%` to `-12.20%`
  - p95 delta stayed within `7.81pp`, from `+4.19%` to `+12.00%`
  - the stable regression shape includes `Backpressure events 71 -> 82 (+11)`,
    `Backpressure alerts 2 -> 3 (+1)`, and
    `response headers wait avg 17.55 -> 21.16 (+3.61)`
- Manual hosted rerun `24918088324` then retried isolated `s1` with
  `repeat_count=5`.
- That longer `s1` rerun failed in the benchmark step, but the uploaded
  artifact still narrowed the picture:
  - the completed repeats converged into decision-quality spans:
    throughput `11.85pp`, p95 `21.75pp`
  - `repeat-04` is partial and baseline-only summary output is missing
  - the partial comparison reports `baseline` elapsed wall time `308.65s`
    versus `9.17s` for the `kTLS` pass, which points to a long-repeat
    baseline stall rather than another wide spread in the completed samples

## Next Step

Repeat stability is now good enough to stop broad methodology tuning. The next
useful step is a transport-diagnosis plan driven by isolated evidence:
`s4` is a stable multiplex/backpressure regression shape, `s1` is likely a
stable low-contention first-body-delivery regression shape, and the
`repeat_count=5` baseline stall should be tracked separately as a harness
issue.
