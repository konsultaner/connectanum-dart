# HTTP/2 Isolated Regression Diagnosis

Status: in_progress

Resumed after `docs/exec-plans/2026-04-25-ci-noise-and-skip-cleanup.md`
completed on clean branch checkpoint `17697ae`. Paused on 2026-04-28 after
the project priority shifted to the GitHub deployment chain. Resumed on
2026-04-29 after the deployment-chain work reached a clean evidence checkpoint
and its remaining blockers became explicit operator/product/deployment
decisions.

## Context

- Commit `b551a6d` (`build(bench): split h2 response header receive timing`)
  passed the visible GitHub push chain:
  - `CI` `24920276210`
  - `kTLS Validation` `24920276202`
  - `WAMP Profile Benchmarks` `24920276214`
- Commit `355a117` (`build(bench): split h2 header-wait write timing`)
  also passed the visible GitHub push chain:
  - `CI` `24921028426`
  - `kTLS Validation` `24921028397`
  - `WAMP Profile Benchmarks` `24921028403`
- Commit `5f79e40` (`build(ktls): render header-write diagnostics`)
  passed the branch `CI` run:
  - `CI` `24921840775`
  - `kTLS Validation` and `WAMP Profile Benchmarks` were correctly skipped by
    their `push.paths` filters because that change only touched report tooling
- Commit `17697ae` (`ci: move artifact actions to node24`) passed the visible
  GitHub push chain after the CI-cleanup detour completed:
  - `CI` `25039426534`
  - `kTLS Validation` `25039426508`
  - `WAMP Profile Diagnostics` `25039426526`
  - `WAMP Profile Benchmarks` `25039426501`
- Commit `649afcb` (`docs: resume ktls diagnosis after ci cleanup`) passed
  hosted GitHub `CI` run `25041573952`.
- Manual hosted rerun `24917876488` isolated
  `h2_multiplexed_streams_s4`, `threads=4` into a decision-quality result:
  - throughput delta `-17.35%..-12.20%`
  - p95 delta `+4.19%..+12.00%`
  - stable backpressure increase: `71 -> 82 (+11)` events,
    `2 -> 3 (+1)` alerts
  - stable header-wait increase: `17.55 -> 21.16 (+3.61)` ms
- Manual hosted rerun `24917873323` isolated
  `h2_multiplexed_streams_s1`, `threads=4` and still showed wide kTLS-side
  throughput spread without transport counters or connection churn.
- Manual hosted rerun `24918088324` retried isolated `s1` with
  `repeat_count=5` and failed in the benchmark step, but the completed repeats
  converged to decision-quality spans before a long-repeat baseline stall on
  partial `repeat-04`.
- That means the broad repeat-stability question is no longer the blocker.
  The blocker is now diagnosis:
  - `s4` is a real multiplex/backpressure regression shape.
  - `s1` is likely a real low-contention first-body-delivery regression shape.
  - the long-repeat baseline stall is a separate harness issue.
- Manual hosted rerun `24919870963` then reran isolated `s1` on clean head
  `4228983` with the same stability settings as `24917873323`.
- That rerun ruled out the post-header first-body hypothesis:
  - the new post-header receive-side metrics stayed flat or improved in all
    repeats
  - the instability remained on `response_headers_wait`, not on
    `post_header_connection_read_wait` or
    `connection_read_to_first_chunk`
  - the next missing split is therefore on the header path rather than the
    body path
- Manual hosted rerun `24920655184` then reran isolated `s1` on clean head
  `b551a6d` with the same stability settings.
- That rerun resolved the new header-read branch of the diagnosis:
  - throughput span stayed within the decision threshold, but p95 span stayed
    kTLS-side and far above threshold
  - `response_headers_connection_read_wait` moved with the unstable repeats
  - `response_headers_connection_read_to_headers` stayed nearly flat
  - post-header body metrics also stayed flat enough that the next missing
    split is now on the write side of the header-wait phase
- Manual hosted rerun `24921433741` then reran isolated `s1` on clean head
  `355a117` with the same stability settings.
- That rerun resolved the write-side branch of the diagnosis:
  - the rerun is decision-quality instead of another noisy partial signal
  - throughput span narrowed to `20.81pp`
  - p95 span narrowed to `15.55pp`
  - `response_headers_connection_write_wait` and
    `response_headers_connection_write_span` stayed small and flat across all
    repeats, so request-flush activity is no longer the lead suspect

## Goals

1. Use the isolated `s1` and `s4` evidence to choose the next transport
   diagnosis path instead of repeating broad methodology work.
2. Reproduce or instrument the `s1` low-contention path so the missing
   client-side response-header gap becomes visible.
3. Keep the `s4` stable backpressure/header-wait result as the reference shape
   for multiplex-path work.
4. Track the long-repeat baseline stall as a harness issue without letting it
   blur the stable transport evidence.
5. Split the remaining `response_headers_wait` instability into a client-side
   connection-read phase and a post-read headers-parse phase.
6. Narrow the remaining `response_headers_connection_read_wait` gap now that
   both post-header body timing and header-wait write activity are ruled out.

## Planned Changes

1. Inspect the existing client-side and native HTTP/2 receive-side timing path
   around first body delivery for isolated `s1`.
2. Add the smallest missing metric or repro needed to expose where the `s1`
   gap appears after server emission has already improved.
3. Keep the current kTLS manual workflow unchanged unless the harness stall
   blocks diagnosis again.
4. Update project state and docs only when the diagnosis path or verification
   state changes.

## Progress

- The smallest missing metric is now implemented in the native bench H2 client
  path:
  - `native/bench/src/bin/http_stream.rs` now wraps the HTTP/2 client
    transport and records the first successful socket read after response
    headers arrive
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` now carry
    and summarize:
    `response_body_post_header_connection_read_wait_*` and
    `response_body_connection_read_to_first_chunk_*`
  - `tool/ktls_http2_compare.py` now renders those fields in the response-body
    diagnostics table and focus line output
- That split is intentionally narrow:
  - if isolated hosted `s1` shows the regression in
    `post_header_connection_read_wait`, the remaining gap is before the next
    socket read
  - if it instead shows up in
    `connection_read_to_first_chunk`, bytes are reaching the client promptly
    and the delay is inside the HTTP/2 body path after read completion
- Hosted rerun `24919870963` resolved that branch of the diagnosis:
  - `post-header connection read wait avg` improved or stayed flat in all
    repeats
  - `connection read-to-first-chunk avg` also stayed flat in all repeats
  - `response headers wait avg` carried the remaining instability instead
- Hosted rerun `24921433741` resolved that write-side branch of the diagnosis:
  - worst throughput and worst p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)` across all repeats
  - `response_headers_connection_write_wait` stayed around `0.04..0.07 ms`
  - `response_headers_connection_write_span` stayed around `0.18..0.19 ms`
  - those write-side metrics did not move with the repeat-level throughput or
    p95 deltas
- The artifact-readability follow-up is now pushed and CI-cleared on `5f79e40`,
  so the next blocker is no longer visibility.
- The next bounded split inside `response_headers_connection_read_wait` is
  committed and hosted-clean through `17697ae`:
  - `native/bench/src/bin/http_stream.rs` now records the gap from the last
    request-side connection write to the first response-side connection read
    during `response_headers_wait`
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` now carry
    and summarize `response_headers_last_write_to_first_read_*`
  - `tool/ktls_http2_compare.py` now renders those fields in the markdown
    focus lines and `## HTTP Header-Receive Diagnostics` table
  - `tool/test_ktls_http2_compare.py` pins those new human-readable fields
- That split is intentionally narrow:
  - if isolated hosted `s1` moves on
    `response_headers_last_write_to_first_read`, the remaining gap is after
    client flush completion and before the first response-side read
  - if it stays flat, the next missing split is deeper inside
    `response_headers_connection_read_wait` before the first read completes
- The clean-CI detour is complete:
  - the CI cleanup landed as `ce05721`
  - artifact actions moved to Node 24-backed versions in `17697ae`
  - the hosted push chain for `17697ae` is green, and log inspection confirmed
    the prior artifact-action Node 20 deprecation warning is gone
- Manual hosted rerun `25042279631` completed successfully on clean head
  `649afcb` with the isolated `h2_multiplexed_streams_s1`, `threads=4`
  settings:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `workloads=h2_multiplexed_streams_s1`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=baseline-first`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That rerun is decision-quality:
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)` across all repeats
  - throughput delta span narrowed to `13.11pp`, with kTLS at
    `-47.86%..-34.75%`
  - p95 delta span narrowed to `22.98pp`, with kTLS at `-6.28%..+16.70%`
  - no non-zero transport counters, no connection churn, and samples per
    connection stayed stable
- The new post-flush `response_headers_last_write_to_first_read` split only
  moved materially in repeat 02:
  - repeat 02 showed `4.09 -> 7.97 ms`, matching the temporary header-wait
    and p95 movement
  - repeats 01 and 03 stayed flat or improved on that metric
  - the stable throughput regression therefore is not explained by the header
    post-flush wait alone
- The stable remaining `s1` throughput gap now sits in the response-body tail
  after the first body chunk:
  - first-chunk wait stayed flat or improved across repeats
  - post-header connection read wait stayed flat or improved across repeats
  - `connection_read_to_first_chunk` stayed small
  - `response_body_tail_read_avg_ms` regressed by about `+1.52..+2.39 ms`
    across all repeats, while chunk count and first-chunk bytes stayed stable
- The next bounded body-tail split is implemented locally:
  - `native/bench/src/bin/http_stream.rs` now starts a second H2 client read
    probe after the first response-body chunk
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` now carry
    and summarize `response_body_tail_connection_read_wait_*` and
    `response_body_tail_connection_read_to_end_*`
  - `tool/ktls_http2_compare.py` renders those fields in the focus lines and
    `## HTTP Response-Body Diagnostics`
  - `tool/test_ktls_http2_compare.py` pins the JSON deltas and markdown output
- Commit `20dbc9a` (`bench: split h2 response body tail timing`) passed the
  hosted GitHub push chain:
  - `CI` `25043856689`
  - `kTLS Validation` `25043856696`
  - `WAMP Profile Benchmarks` `25043856615`
- Manual hosted rerun `25044549578` completed successfully on clean head
  `20dbc9a` with the same isolated `s1`, `threads=4` settings, but did not
  reach decision quality:
  - throughput delta span widened to `66.64pp`, with deltas
    `-53.21%`, `+13.43%`, and `-15.07%`
  - p95 delta span stayed within threshold at `25.96pp`
  - the worst throughput and p95 rows were still stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the spread source was mixed rather than cleanly baseline-side or kTLS-side
- The new body-tail fields were still useful inside the per-repeat artifacts:
  - repeat 01 showed body-side kTLS delay around first body connection-read and
    tail connection-read wait
  - repeat 02 was dominated by a bad baseline header wait
    (`response_headers_last_write_to_first_read` `7.95 -> 3.37 ms`)
  - repeat 03 was dominated by a bad kTLS header wait
    (`response_headers_last_write_to_first_read` `3.62 -> 8.52 ms`)
  - that means `25044549578` is a mixed hosted-noise run, not a clean answer to
    the body-tail diagnosis
- The current follow-up slice makes non-decision repeat artifacts more
  human-readable:
  - `tool/ktls_http2_compare_repeats.py` now lifts per-repeat phase timing for
    the worst throughput/p95 rows into the top-level repeat-stability report
  - the new `## Repeat Phase-Timing Focus` table includes header wait,
    last-write-to-first-read, body read, first-chunk, tail-read,
    read-to-first-chunk, tail connection-read wait, and tail read-to-end
    metrics
- Commit `d97d34f` (`bench: summarize repeat phase timing`) passed hosted
  GitHub `CI` run `25045630570`, so the repeat phase-timing focus table is
  available on a clean branch checkpoint.
- Manual hosted rerun `25124797087` reran isolated
  `h2_multiplexed_streams_s1`, `threads=4`, one router worker, on clean head
  `b338d58` with `repeat_count=3`, `repeat_order=baseline-first`,
  `cooldown_seconds=15`, and `skip_artifact_gate=true`.
- That baseline-first rerun completed successfully but was not
  decision-quality:
  - throughput delta span was `123.16pp`
  - p95 delta span was `77.26pp`
  - baseline-side header wait noise made the aggregate look kTLS-favorable
  - body-tail read and tail read-to-end deltas were still kTLS-higher in all
    repeats
- Manual hosted rerun `25125095595` reran the same isolated workload with
  `repeat_order=alternating`.
- That alternating rerun completed successfully but was not decision-quality:
  - throughput delta span was `57.05pp`
  - p95 delta span was `368.11pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the p95 spread was kTLS-side while the throughput spread was mixed
  - body read, tail read, and tail connection read-to-end were kTLS-higher in
    all three repeats despite the noisy aggregate result
- The current reporting slice makes that stable phase signal explicit:
  - `tool/ktls_http2_compare_repeats.py` now computes sign-consistent phase
    deltas across repeated focus rows
  - the new `## Repeat Phase Signals` table renders the metric, repeat count,
    direction, baseline range, kTLS range, and signed delta range
  - `tool/test_ktls_http2_compare.py` pins that repeated phase-signal behavior
  - rerendering the `25125095595` artifact shows six sign-consistent repeated
    phase deltas, including kTLS-higher body read, tail read, and tail
    connection read-to-end timing

## Current Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml h2_last_write_to_first_read_gap_uses_last_write_boundary --bin http_stream -- --nocapture`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `tmpdir=$(mktemp -d /tmp/connectanum-ktls-rerender-XXXXXX) && python3 tool/ktls_http2_compare.py /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/baseline/bench_results.summary.json /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/ktls/bench_results.summary.json "$tmpdir/comparison.json" "$tmpdir/comparison.md"`
- Hosted GitHub push runs on `17697ae`: `CI` `25039426534`,
  `kTLS Validation` `25039426508`, `WAMP Profile Diagnostics` `25039426526`,
  and `WAMP Profile Benchmarks` `25039426501`
- Hosted GitHub `CI` run `25041573952` completed successfully on `649afcb`
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25042279631` completed
  successfully and produced decision-quality isolated `s1`, `threads=4`
  evidence
- Hosted GitHub push runs on `20dbc9a`: `CI` `25043856689`,
  `kTLS Validation` `25043856696`, and `WAMP Profile Benchmarks`
  `25043856615`
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25044549578` completed
  successfully but was not decision-quality because throughput delta span was
  `66.64pp`
- Current body-tail split local verification:
  - `bin/test-fast`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `bin/verify`
- Current repeat-report focus verification:
  - `bin/test-fast`
  - `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - rerendered `25044549578` repeat artifacts with
    `tool/ktls_http2_compare_repeats.py`
  - `bin/verify`
  - hosted GitHub `CI` run `25045630570` completed successfully on `d97d34f`
- Current repeat-phase signal verification:
  - `bin/test-fast`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25124797087`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25125095595`
  - `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - rerendered `25125095595` repeat artifacts with
    `tool/ktls_http2_compare_repeats.py`
  - `git diff --check`
  - `bin/verify`

## Next Step

Commit this repeat-phase signal slice and push it. After the hosted `CI` run is
clean, rerun the same isolated hosted `s1` workload on the new head with
`repeat_order=alternating`. Use the next decision-quality run to decide whether
the stable throughput loss is mostly waiting for connection reads after first
chunk or processing/draining after those reads. If the run is still
non-decision-quality, use the `## Repeat Phase Signals` table to classify which
phase deltas remain sign-consistent across repeats before adding any more
instrumentation.
