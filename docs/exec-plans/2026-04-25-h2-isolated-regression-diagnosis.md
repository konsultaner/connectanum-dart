# HTTP/2 Isolated Regression Diagnosis

Status: in_progress

Resumed after `docs/exec-plans/2026-04-25-ci-noise-and-skip-cleanup.md`
completed on clean branch checkpoint `17697ae`.

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

## Next Step

Run the next isolated hosted `s1` rerun on clean head `17697ae` to check
whether the remaining instability moves on the post-flush write-to-read gap or
stays deeper inside `response_headers_connection_read_wait`.
