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

## Next Step

Finish local verification, push the dedicated stability scenario, wait for the
branch push chain to go green again, and then dispatch the manual
`kTLS HTTP/2 Benchmarks` workflow with:

- `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
- `router_worker_counts=1`
- `native_runtime_thread_counts=1,4`
- `repeat_count=3`
- `skip_artifact_gate=true`
