# Exec Plan: kTLS Repeat Stability Follow-up

Status: in_progress
Owner: Codex
Created: 2026-04-30
Last updated: 2026-04-30

## Goal

Make the manual Linux kTLS HTTP/2 benchmark lane produce stable enough evidence
to justify a runtime tuning change, or prove that the next work should stay in
benchmark measurement rather than transport code.

## Scope

- In scope:
  - hosted `kTLS HTTP/2 Benchmarks` repeat-stability runs on the current branch
    head
  - interpretation of aggregate repeat reports, especially throughput/p95 span,
    focus-row consistency, phase signals, server-emission signals, native
    response-stream signals, and transport-counter issues
  - small benchmark/reporting improvements when the hosted evidence is
    incomplete or too unstable to guide runtime changes
  - checked-in state updates with run ids and the next bounded action
- Out of scope:
  - speculative kTLS or HTTP/2 runtime tuning before repeat evidence converges
  - branch protection, GHCR router image publication, RC tag creation, Dart
    package publication, or any other operator-owned deployment-chain mutation

## Preconditions

- GitHub deployment-chain gates are clean on `add-router` head `9dcab42`:
  hosted `CI` run `25175047332` passed, and the clean-CI/log audit passed.
- The GitHub deployment-chain readiness plan is paused because the remaining
  RC blockers are operator/release decisions.
- Local `bin/test-fast` passed on 2026-04-30 before recording this kTLS
  follow-up state.

## Plan

1. Refresh hosted kTLS repeat evidence on the current branch head using the
   focused `h2_multiplexed_streams_s1`, `threads=4` diagnostic shape.
2. If the aggregate report is decision-quality, use its stable hotspot to choose
   the next small runtime or benchmark change.
3. If the aggregate report is not decision-quality, prefer benchmark
   measurement/stability work over transport changes, and record exactly which
   signal stayed unstable.
4. Keep local and hosted CI clean before committing or handing off.

## Progress

- Dispatched GitHub `kTLS HTTP/2 Benchmarks` run `25176887533` on `9dcab42`
  with:
  - `scenario = native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `workloads = h2_multiplexed_streams_s1`
  - `router_worker_counts = 1`
  - `native_runtime_thread_counts = 4`
  - `repeat_count = 3`
  - `repeat_order = alternating`
  - `skip_artifact_gate = true`
- Run `25176887533` passed in 5m31s and uploaded
  `ktls-http2-bench-artifacts`.
- The repeat aggregate is diagnostic but not decision-quality:
  - worst throughput and worst p95 row were stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)` across all three
    repeats
  - throughput regression was consistent enough for the current threshold:
    delta range `-55.01%..-42.00%`, span `13.01pp`
  - p95 was still too unstable for decision-quality evidence:
    delta range `+35.74%..+96.27%`, span `60.53pp` against the `50.00pp`
    threshold
  - focus rows had no transport-counter issues and all transport counters
    stayed zero
  - repeated focus rows showed sign-consistent phase, server-emission, and
    native response-stream deltas, with the strongest repeated server-side
    movement around request-body remaining-tail/data-wait timing on the kTLS
    side
- Hosted log scan for `25176887533` had no actionable warnings, skipped tests,
  resets, broken pipes, panics, or timeout failures. Matches were benign setup
  text: Git default-branch hint, rustup timeout-workaround comments,
  dependency names containing `thiserror`, and upload-artifact
  `if-no-files-found: error` configuration.
- Added repeat-threshold detail reporting to
  `tool/ktls_http2_compare_repeats.py`: each row stability entry now carries
  per-repeat baseline/kTLS throughput, throughput delta, baseline/kTLS p95,
  and p95 delta values, and the markdown report renders them under
  `Stability Threshold Repeat Details` for rows that exceed the stability
  gates.
- Re-rendered run `25176887533` locally into `/tmp` with the reporting change;
  the new table shows the current mixed p95 span directly:
  `repeat-01` `21.70 -> 35.46 ms` (`+63.41%`), `repeat-02`
  `23.81 -> 32.33 ms` (`+35.74%`), and `repeat-03`
  `17.89 -> 35.12 ms` (`+96.27%`) for `h2_multiplexed_streams_s1`,
  `threads=4`.
- Full local `bin/verify` passed after the reporting change on 2026-04-30.

## Verification

- `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 10 --require-clean-latest-ci --require-clean-latest-ci-logs`
- GitHub `kTLS HTTP/2 Benchmarks` run `25176887533`
- Hosted kTLS run log scan for warning/skipped/reset/panic/timeout/connection
  noise
- `bin/test-fast`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`

## Handoff

- Do not tune the HTTP/2 or kTLS runtime from this evidence alone: p95 remains
  outside the decision-quality threshold.
- The next bounded task should make the repeat artifact more actionable around
  the mixed p95 span, or run a narrower follow-up that isolates why repeats 01
  and 03 show large header/body timing movement while repeat 02 stays much
  closer to baseline.
