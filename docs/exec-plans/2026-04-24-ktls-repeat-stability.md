# kTLS Repeat Stability

Status: in_progress

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

## Next Step

The hosted `threads=4` lane is still unstable even in isolation, but the
runner now supports bounded pass-order and cooldown controls. The next useful
step is to rerun the manual `kTLS HTTP/2 Benchmarks` workflow on the clean head
with:

- `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
- `router_worker_counts=1`
- `native_runtime_thread_counts=4`
- `repeat_count=3`
- `skip_artifact_gate=true`
- workflow defaults `repeat_order=alternating` and `cooldown_seconds=15`
