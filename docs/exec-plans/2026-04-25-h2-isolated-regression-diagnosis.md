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
- Documentation checkpoint `90fbbb9` (`docs: record repeat phase signal ci`)
  passed hosted GitHub `CI` run `25126752936`.
- Manual hosted rerun `25127431552` retried the same isolated `s1`,
  `threads=4`, one-router-worker workload on `90fbbb9` with
  `repeat_order=alternating`.
- That rerun failed during repeat 01 when the kTLS pass hit an HTTP/2 body
  total timeout after the baseline pass completed:
  - the partial artifact contained one baseline-only row and zero comparable
    rows
  - this is a harness/timeout signal, not transport decision evidence
  - the failure exposed a reporter bug where a no-comparable-row repeat could
    be labeled decision-quality
- The repeat reporter now treats partial artifacts as inconclusive:
  - repeats with zero comparable rows are explicit instability reasons
  - repeats with any unmatched baseline-only or kTLS-only rows are explicit
    instability reasons
  - the top-level markdown now includes a `## Repeat Completeness` table with
    comparable, baseline-only, and kTLS-only row counts
- Commit `f85c70e` (`bench: mark partial repeats inconclusive`) passed hosted
  GitHub `CI` run `25128558792`.
- Documentation checkpoint `7878467`
  (`docs: record partial repeat reporter ci`) passed hosted GitHub `CI` run
  `25129245463`.
- Manual hosted rerun `25129905513` retried the isolated `s1`, `threads=4`,
  one-router-worker workload on clean head `7878467` with
  `repeat_order=alternating`.
- That rerun completed successfully with matched baseline/kTLS rows in all
  three repeats, but was not decision-quality:
  - throughput delta span was `57.64pp`
  - p95 delta span was `1390.49pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the spread source was kTLS-side for both throughput and p95
  - repeat 02 had a severe kTLS p95 outlier, and the hosted log contained one
    `http/2 accept error ... broken pipe` line around a completed warm-up path
- Rerendering `25129905513` with the current repeat reporter keeps the result
  inconclusive but materially narrows the signal:
  - client phase signals are kTLS-higher across all three repeats for header
    last-write-to-first-read, headers wait, body read, tail read, tail
    connection read-to-end, and tail connection read-wait timing
  - server-emission signals have no material sign-consistent repeated deltas
    after a `0.10 ms` median filter
  - native response-stream signals have no material sign-consistent repeated
    deltas
  - the per-repeat server-emission focus table still exposes the repeat-02
    server/direct-stream outlier without promoting it to a stable signal
- The repeat reporter now separates repeated focus signals by source:
  - `## Repeat Phase Signals` remains the client-side phase signal table
  - new `## Repeat Server-Emission Signals` and
    `## Repeat Native Response-Stream Signals` tables show material
    sign-consistent server/native deltas only
  - new `## Repeat Server-Emission Focus` and
    `## Repeat Native Response-Stream Focus` tables keep per-repeat outliers
    visible even when they are not stable repeated signals
- The first full local `bin/verify` rerun exposed a separate CI-clean blocker:
  - `http3_multiple_connections_handshake` timed out after the runtime logged
    `failed to start http3 listener ... Address already in use`
  - the root cause is the HTTP/3 FFI tests binding TCP on port `0` and then
    assuming QUIC/UDP can always bind the same numeric ephemeral port
  - on macOS that TCP-selected port can already be occupied for UDP, so this
    is a real test harness race rather than a reporter regression
- The HTTP/3 FFI network tests now use the split listener API explicitly:
  - test router configs set `http3.port: 0` so QUIC gets its own ephemeral UDP
    port
  - clients connect through `ct_listener_http3_port`
  - the normal TCP local port remains covered by the non-HTTP/3 listener tests
- Commit `1400ce1` (`bench: split repeat server signals`) passed hosted
  GitHub `CI` run `25131284776`, and the same push passed hosted
  `WAMP Profile Benchmarks` run `25131284793`.
- Manual hosted rerun `25132037358` reran isolated `s1`, `threads=4`, one
  router worker on `1400ce1` with `repeat_order=alternating`.
- That hosted rerun completed and all repeats had matched rows, but it was not
  decision-quality:
  - throughput delta span was `84.11pp`
  - p95 delta span was `2378.94pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - repeated client phase signals stayed kTLS-higher for body/tail timings
  - repeated server-emission and native response-stream signal tables stayed
    empty, while per-repeat focus rows still exposed server-side outliers in
    repeats 02 and 03
- The next bounded H2 client tail-read split is implemented locally:
  - `native/bench/src/bin/http_stream.rs` now records last connection read and
    connection read count for active H2 client read probes
  - body-tail reports now expose tail connection read count, first-to-last read
    span, and last-read-to-body-end timing
  - `native/bench/src/report.rs`, `native/bench/src/artifacts.rs`,
    `tool/ktls_http2_compare.py`, and
    `tool/ktls_http2_compare_repeats.py` carry those fields through summaries,
    markdown diagnostics, and repeat focus/signal tables
- Commit `449887b` (`bench: split h2 tail read timing`) passed the hosted
  GitHub push chain:
  - `CI` `25133186169`
  - `kTLS Validation` `25133186157`
  - `WAMP Profile Benchmarks` `25133186159`
- The deployment-chain audit against `449887b` reported clean latest `CI`
  jobs and a clean hosted `CI` log scan, so the next blocker is hosted
  isolated benchmark evidence with the new tail-read split.
- Manual hosted rerun `25134092006` reran isolated `s1`, `threads=4`, one
  router worker on `449887b` with `repeat_order=alternating`.
- That hosted rerun is decision-quality:
  - throughput delta span was `23.73pp`
  - p95 delta span was `15.47pp`
  - all repeats produced matched rows
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - kTLS throughput remained lower in all repeats at
    `-36.18%..-12.44%`, median `-25.30%`
- The new body-tail split narrows the stable gap:
  - tail read-span was kTLS-higher by `+0.39..+1.70 ms`
  - tail connection read-to-end was kTLS-higher by `+0.38..+1.70 ms`
  - tail connection last-read-to-end stayed flat at about `0.02..0.04 ms`
  - tail connection read count did not explain the result consistently
  - native response-stream signals stayed empty
- That points away from post-final-read H2 body processing and toward
  client-side socket/TLS read scheduling or per-read delivery while consuming
  the H2 body tail.
- The native response-stream tail-send split is implemented locally:
  - `ct_core` records tail chunk channel wait, tail chunk send-call duration,
    and first-to-last chunk send span for HTTP/2 and HTTP/3 streaming native
    responses
  - `ct_ffi` and the Dart router metrics model expose those counters through
    the native metrics snapshot
  - `native/bench` summaries and the kTLS comparison reports render the new
    timing and slow-path buckets in native response-stream focus rows
- This split is intentionally bounded:
  - if the next hosted isolated `s1` rerun shows a stable kTLS-side native
    tail-send delta, the remaining work is on native server streaming
    scheduling before the socket/TLS read path
  - if native tail-send stays flat while client tail reads remain kTLS-higher,
    the next target remains socket/TLS read delivery on the client side
- Commit `fc71d9a` (`bench: split native response tail send timing`) passed
  the hosted GitHub push chain:
  - `CI` `25135516518`
  - `kTLS Validation` `25135516526`
  - `WAMP Profile Benchmarks` `25135516530`
- The deployment-chain audit against `fc71d9a` reported clean latest `CI`
  jobs and a clean hosted `CI` log scan. Manual log scans for the push-chain
  runs only matched benign timeout-reference/configuration text and passing
  test names containing expected words such as `failed` or `timeout`.
- Documentation checkpoint `564de8e`
  (`docs: record native tail send ci`) passed hosted GitHub `CI` run
  `25136141646`, and the branch-head deployment audit/log scan was clean.
- Manual hosted rerun `25136742292` reran isolated `s1`, `threads=4`, one
  router worker on `564de8e` with `repeat_order=alternating`.
- That hosted rerun completed with matched rows in all three repeats, but it
  was not decision-quality:
  - throughput delta span was `33.35pp`
  - p95 delta span was `129.29pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the throughput spread was mixed and the p95 spread was kTLS-side
- The uploaded comparison unexpectedly rendered no native response-stream
  rows, but the raw JSONL snapshots did contain
  `transport.http_response_stream` counters for the same workload.
- Root cause: the summary transformer required a populated
  `metrics_before.transport.http_response_stream` object. On a clean start,
  that object can be absent until the first streaming response increments the
  counters, so valid after-counters were discarded.
- Commit `8ff7b31` (`bench: keep response stream summaries`) now treats
  missing response-stream `before` counters as zero when the matching `after`
  counter exists.
- Rerendering the `25136742292` raw JSONL with that fix keeps the run
  non-decision-quality but makes the native tail-send signal visible:
  - repeated client phase signals remain kTLS-higher across header wait and
    body/tail read phases
  - repeated server-emission signals remain empty
  - native response-stream tail chunk channel wait is kTLS-higher by
    `+0.20..+0.35 ms`, median `+0.32 ms`
  - native response-stream first-to-last chunk send span is kTLS-higher by
    `+0.23..+0.26 ms`, median `+0.25 ms`
- This means the next diagnosis target is native server tail-send scheduling
  under kTLS, not only client-side socket/TLS read delivery.
- Commit `c71ed8c` (`docs: record response stream summary fix`) passed the
  hosted GitHub push chain:
  - `CI` `25137565822`
  - `kTLS Validation` `25137565809`
  - `WAMP Profile Benchmarks` `25137565865`
- Manual hosted rerun `25138038502` reran isolated `s1`, `threads=4`, one
  router worker on `c71ed8c` with `repeat_order=alternating`.
- That run confirmed the hosted artifacts now include native response-stream
  rows without local rerendering, but it was not decision-quality:
  - throughput delta span was `69.12pp`
  - p95 delta span was `1975.62pp`
  - all repeats produced matched rows
  - the instability was kTLS-side
- The repeated native response-stream signal remained small but
  sign-consistent:
  - tail chunk channel wait was kTLS-higher by `+0.26..+0.28 ms`, median
    `+0.27 ms`
  - first-to-last chunk send span was kTLS-higher by `+0.18..+0.20 ms`,
    median `+0.20 ms`
  - repeated server-emission signals stayed empty
- Inspecting the single-stream HTTP/2 response path showed an unconditional
  fairness yield after the first streamed body chunk. That helps multiplexed
  responses only when another response header is pending, but in isolated
  `streams_per_connection = 1` it can delay draining already-queued tail
  chunks without improving fairness.
- Commit `86c914e` (`perf: avoid h2 single-stream body yield`) gates the
  first-body-chunk yield on the same `pending_headers > 1` condition already
  used for the response-header yield:
  - single-stream/uncontended HTTP/2 responses no longer yield after the first
    body chunk
  - multiplexed responses with pending header work still retain the fairness
    yield
- The hosted push chain for `86c914e` is clean:
  - `CI` `25138760298`
  - `kTLS Validation` `25138760315`
  - `WAMP Profile Benchmarks` `25138760280`
  - the branch-head deployment audit and hosted CI log scan are clean
- Documentation checkpoint `d40543a` (`docs: record h2 yield gating evidence`)
  passed hosted GitHub `CI` run `25139453507`, and the branch-head deployment
  audit/log scan remained clean.
- Manual hosted rerun `25139865949` reran isolated `s1`, `threads=4`, one
  router worker on `d40543a` with `repeat_order=alternating`.
- That post-yield-gate run completed with matched rows in all three repeats,
  but it was not decision-quality:
  - throughput delta span narrowed to `24.53pp`
  - p95 delta span remained kTLS-side and far above threshold at `1640.36pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
- Compared with pre-fix run `25138038502`, the native response-stream tail
  signal improved but did not collapse:
  - tail chunk channel wait moved from `+0.26..+0.28 ms` to
    `+0.14..+0.17 ms`
  - first-to-last chunk send span moved from `+0.18..+0.20 ms` to
    `+0.11..+0.16 ms`
- The same post-fix run exposed repeated server-emission signals that were
  absent before the yield-gate change:
  - first body write was kTLS-higher by `+1.96..+4.16 ms`
  - first body write completed was kTLS-higher by `+1.95..+4.14 ms`
- Documentation checkpoint `52e8e2a` (`docs: record h2 post-yield benchmark`)
  passed hosted GitHub `CI` run `25140097069`; `Fast Checks` completed in
  5m40s, `Full Verify` completed in 6m58s, and the branch-head
  deployment-chain audit/log scan remained clean.
- Expanding the repeat server-emission reporter to include already-collected
  request-drain, stream-open, first-chunk-queued, descriptor-open, and handler
  fields changed the diagnosis boundary:
  - first body write and completion are kTLS-higher because stream-open,
    request-body drain, handler elapsed, and first-chunk-queued timing are
    already kTLS-higher before the first direct stream write call
  - first body write call duration itself stays flat
  - on rerendered `25139865949`, request body drain is kTLS-higher by
    `+1.08..+3.37 ms` with median `+2.10 ms`, matching the handler and
    first-chunk-queued median movement
- The current local request-body drain split adds first-chunk wait, tail-read,
  and chunk-count averages for synthetic streamed HTTP responses and renders
  those fields in both primary and repeated kTLS comparison artifacts.
- Current interpretation:
  - the unconditional single-stream first-body yield contributed to native
    tail-send delay
  - it was not the whole regression
  - the next bounded target is hosted evidence from the request-body drain
    split, not another first-body-write scheduling change
- Commit `57c051d` (`bench: split h2 request body drain timing`) passed the
  hosted GitHub push chain:
  - `CI` `25140818328`
  - `kTLS Validation` `25140818325`
  - `WAMP Profile Benchmarks` `25140818382`
  - the branch-head deployment audit and hosted CI log scan are clean
- Manual hosted rerun `25141243287` reran isolated `s1`, `threads=4`, one
  router worker on `57c051d` with `repeat_order=alternating`.
- That run completed with matched rows in all three repeats, but it was not
  decision-quality:
  - throughput delta span was `52.94pp`
  - p95 delta span was `1813.09pp`
  - the instability source was kTLS-side
- The new request-body drain split still resolves the server-side boundary:
  - request-body first-chunk wait stayed effectively flat at `+0.00..+0.01 ms`
  - request-body drain chunk count stayed flat at `4.08`
  - request-body tail drain carried the server-side kTLS delta at
    `+0.01..+3.41 ms`, median `+2.73 ms`
- The remaining server-side delay is therefore in the post-first-chunk
  request-body drain path / H2 request-body stream delivery, not before the
  first request-body chunk reaches Dart.
- The current local request-body inter-chunk split is implemented:
  - `packages/connectanum_bench/lib/src/http_stream_handler.dart` records
    second-chunk wait and remaining-tail-read timing while preserving the
    existing total, first-chunk, tail-read, and chunk-count fields
  - `native/bench` summaries carry the two new server-emission averages
  - `tool/ktls_http2_compare.py` and `tool/ktls_http2_compare_repeats.py`
    render the new fields in primary and repeated server-emission reports
- This split is intentionally bounded:
  - if the next hosted isolated `s1` rerun shows the kTLS delta concentrated
    in second-chunk wait, the remaining issue is early post-first-chunk H2
    request-body delivery
  - if the delta stays in remaining-tail-read, the next target is later
    request-body stream pacing across the remaining chunks
- Commit `f9b3b27` (`bench: split request body tail drain timing`) passed the
  hosted GitHub push chain:
  - `CI` `25141807658`
  - `kTLS Validation` `25141807596`
  - `WAMP Profile Benchmarks` `25141807457`
  - the branch-head deployment audit and hosted CI log scan are clean
- Manual hosted rerun `25142223693` reran isolated `s1`, `threads=4`, one
  router worker on `f9b3b27` with `repeat_order=alternating`.
- That run completed with matched rows in all three repeats, but it was not
  decision-quality:
  - throughput delta span was `35.05pp`
  - p95 delta span was `335.53pp`
  - the instability source was kTLS-side
- The new request-body inter-chunk split still narrows the server-side
  boundary:
  - request-body first-chunk wait stayed flat at about `0.05..0.06 ms`
  - request-body second-chunk wait stayed flat in two repeats and had one
    kTLS-side outlier (`0.02 -> 0.63 ms`)
  - request-body remaining-tail-read carried the larger moving deltas
    (`0.05 -> 2.41 ms` and `0.05 -> 1.13 ms` in the moving repeats)
  - request-body chunk count stayed flat at `4.08`
- The remaining server-side delay is therefore mostly after the second
  request-body chunk in the native HTTP/2 request-body read path or the Dart
  drain path above it.
- The current local native request-body-reader split is implemented:
  - `ct_core` records native HTTP/2 request-body reader totals, `stream.data()`
    wait, first/second chunk wait, remaining tail-read, and chunk count
  - `ct_ffi` and the Dart native/router metrics model expose those counters
    through `transport.http_request_body_stream`
  - `native/bench` summaries and `tool/ktls_http2_compare.py` /
    `tool/ktls_http2_compare_repeats.py` render those fields in primary and
    repeated server-emission reports
- This split is intentionally bounded:
  - if the next hosted isolated `s1` rerun shows the kTLS delta inside native
    request-body reader timing, the next target is HTTP/2 stream pacing before
    Dart receives/drains request chunks
  - if native reader timing stays flat while Dart-side drain remains
    kTLS-higher, the next target is Dart drain scheduling above the native
    request-body reader
- Commit `ffb1376` (`bench: expose native request body reader timing`) passed
  the hosted GitHub push chain:
  - `CI` `25143265285`
  - `kTLS Validation` `25143265320`
  - `WAMP Profile Benchmarks` `25143265476`
  - the branch-head deployment audit and hosted CI log scan are clean
- Manual hosted rerun `25143770043` reran isolated `s1`, `threads=4`, one
  router worker on `ffb1376` with `repeat_order=alternating`.
- That run completed but is not clean decision evidence:
  - throughput delta span was `121.77pp`
  - p95 delta span was `1841.86pp`
  - the hosted log contained `http/2 accept error ... broken pipe` during
    repeat-01 baseline warm-up immediately before the low baseline row
- Manual hosted retry `25143991933` reran the same workload on `ffb1376`.
- That retry is decision-quality:
  - throughput delta span was `23.85pp`
  - p95 delta span was `27.61pp`
  - all repeats produced matched rows
  - the hosted log scan had no connection-noise pattern beyond the expected
    manual artifact-gate skip notices and benign setup/toolchain text
  - kTLS throughput remained lower in all repeats at
    `-39.24%..-15.38%`, median `-36.77%`
  - p95 moved by `+0.08%..+27.69%`
- The native request-body reader split narrows the boundary:
  - repeat-01 had matching server-side Dart drain and native reader tail
    movement (`request body drain +1.06 ms`, native reader total `+1.19 ms`)
  - repeats 02 and 03 kept Dart drain and native reader totals essentially
    flat while client body/tail read remained kTLS-higher
  - the only repeated native request-body reader signal was data-chunk wait in
    two repeats (`+0.01..+0.29 ms`, median `+0.15 ms`)
- That points away from a broad stable server request-body drain explanation.
  The next bounded target is the client-side HTTP/2 body-tail read path:
  split tail connection read span into inter-read gap and read-size/read-count
  distribution before making more server request-body or first-body-write
  scheduling changes.

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
  - hosted GitHub `CI` run `25126070249` completed successfully on `e547232`
- Current partial-repeat reporter verification:
  - `bin/test-fast`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25127431552` failed during
    repeat 01 with a kTLS HTTP/2 body total timeout and partial artifacts
  - `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - rerendered the partial `25127431552` repeat artifact with
    `tool/ktls_http2_compare_repeats.py`; it now reports
    `Decision quality: no` and lists `repeat-01` as incomplete
  - `git diff --check`
  - `bin/verify`
  - hosted GitHub `CI` run `25128558792` completed successfully on `f85c70e`;
    `Fast Checks` completed in 5m32s and `Full Verify` completed in 8m06s
- Current repeat server/native signal verification:
  - hosted GitHub `CI` run `25129245463` completed successfully on `7878467`;
    `Fast Checks` completed in 5m34s and `Full Verify` completed in 8m15s
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25129905513` completed
    successfully on `7878467` and produced complete but non-decision-quality
    repeat evidence
  - `bin/test-fast`
  - `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - rerendered the `25129905513` repeat artifact with
    `tool/ktls_http2_compare_repeats.py`; it now reports six material client
    phase signals and no material repeated server/native stream signals
  - first full local `bin/verify` attempt failed in
    `http3_multiple_connections_handshake` because the test assumed TCP and
    QUIC could share a TCP-selected ephemeral port on macOS
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_multiple_connections_handshake -- --nocapture`
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi`
  - `bin/verify`
- Current H2 tail-read split verification:
  - hosted GitHub `CI` run `25131284776` completed successfully on `1400ce1`;
    `Fast Checks` completed in 5m55s and `Full Verify` completed in 8m07s
  - hosted GitHub `WAMP Profile Benchmarks` run `25131284793` completed
    successfully on `1400ce1`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25132037358` completed
    successfully on `1400ce1` and produced complete but non-decision-quality
    repeat evidence with five material repeated client phase signals and no
    material repeated server/native stream signals
  - `bin/test-fast`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `cargo test --manifest-path native/bench/Cargo.toml h2_last_write_to_first_read_gap_uses_last_write_boundary --bin http_stream -- --nocapture`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `git diff --check`
  - `bin/verify`
  - hosted GitHub `CI` run `25133186169` completed successfully on `449887b`;
    `Fast Checks` completed in 4m47s and `Full Verify` completed in 8m10s
  - hosted GitHub `kTLS Validation` run `25133186157` completed successfully
    on `449887b`
  - hosted GitHub `WAMP Profile Benchmarks` run `25133186159` completed
    successfully on `449887b`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `449887b`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25134092006` completed
    successfully on `449887b` and produced decision-quality isolated
    `s1`, `threads=4` evidence with the new tail-read split
- Current native response-stream tail-send split verification:
  - `bin/test-fast`
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_response_stream_metrics_record_tail_chunks -- --nocapture`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `dart analyze packages/connectanum_router`
  - `git diff --check`
  - `bin/verify`
  - hosted GitHub `CI` run `25135516518` completed successfully on `fc71d9a`;
    `Fast Checks` completed in 5m38s and `Full Verify` completed in 8m00s
  - hosted GitHub `kTLS Validation` run `25135516526` completed successfully
    on `fc71d9a`
  - hosted GitHub `WAMP Profile Benchmarks` run `25135516530` completed
    successfully on `fc71d9a`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `fc71d9a`
- Current native response-stream summary fix verification:
  - hosted GitHub `CI` run `25136141646` completed successfully on `564de8e`;
    `Fast Checks` completed in 5m48s and `Full Verify` completed in 7m51s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `564de8e`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25136742292` completed
    successfully on `564de8e`; the hosted log scan only matched expected
    manual artifact-gate skip notices and the Rust toolchain timeout-reference
    URL
  - `bin/test-fast`
  - `cargo test --manifest-path native/bench/Cargo.toml --lib -- --nocapture`
  - rerendered the `25136742292` raw JSONL with
    `native/bench/target/debug/transform_results`,
    `tool/ktls_http2_compare.py`, and `tool/ktls_http2_compare_repeats.py`
  - `bin/verify`
- Current H2 single-stream response-yield verification:
  - hosted GitHub `CI` run `25137565822` completed successfully on `c71ed8c`;
    `Fast Checks` completed in 4m43s and `Full Verify` completed in 8m19s
  - hosted GitHub `kTLS Validation` run `25137565809` completed successfully
    on `c71ed8c`
  - hosted GitHub `WAMP Profile Benchmarks` run `25137565865` completed
    successfully on `c71ed8c`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25138038502` completed
    successfully on `c71ed8c`; it confirmed hosted native response-stream rows
    are present, but the repeat result was not decision-quality
  - `bin/test-fast`
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http2_response_yield_requires_multiple_pending_headers -- --nocapture`
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_response_stream_metrics_record_tail_chunks -- --nocapture`
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_core -- --nocapture`
  - `git diff --check`
  - `bin/verify`
  - hosted GitHub `CI` run `25138760298` completed successfully on `86c914e`;
    `Fast Checks` completed in 5m20s and `Full Verify` completed in 8m29s
  - hosted GitHub `kTLS Validation` run `25138760315` completed successfully
    on `86c914e`
  - hosted GitHub `WAMP Profile Benchmarks` run `25138760280` completed
    successfully on `86c914e`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `86c914e`
  - hosted GitHub `CI` run `25139453507` completed successfully on `d40543a`;
    `Fast Checks` completed in 5m38s and `Full Verify` completed in 7m12s
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `d40543a`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25139865949` completed
    successfully on `d40543a`; the hosted log scan only matched the expected
    manual artifact-gate skip notices and the Rust toolchain timeout-reference
    URL
- Current request-body drain split verification:
  - hosted GitHub `CI` run `25140097069` completed successfully on `52e8e2a`;
    `Fast Checks` completed in 5m40s and `Full Verify` completed in 6m58s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `52e8e2a`
  - `bin/test-fast`
  - `dart analyze packages/connectanum_bench/lib/src/http_stream_handler.dart packages/connectanum_bench/test/http_stream_handler_test.dart`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - rerendered the `25139865949` repeat artifact with
    `tool/ktls_http2_compare_repeats.py`
  - `git diff --check`
  - `bin/verify`
  - hosted GitHub `CI` run `25140818328` completed successfully on `57c051d`;
    `Fast Checks` completed in 5m28s and `Full Verify` completed in 8m23s
  - hosted GitHub `kTLS Validation` run `25140818325` completed successfully
    on `57c051d`
  - hosted GitHub `WAMP Profile Benchmarks` run `25140818382` completed
    successfully on `57c051d`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `57c051d`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25141243287` completed
    successfully on `57c051d`; it produced complete but non-decision-quality
    repeat evidence and confirmed the server-side request-body delta is in
    tail drain, not first-chunk wait
  - `dart analyze packages/connectanum_bench/lib/src/http_stream_handler.dart packages/connectanum_bench/test/http_stream_handler_test.dart`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `git diff --check`
  - `bin/verify`
- Current native request-body reader split verification:
  - hosted GitHub `CI` run `25141807658` completed successfully on
    `f9b3b27`; `Fast Checks` completed in 5m09s and `Full Verify` completed
    in 8m12s
  - hosted GitHub `kTLS Validation` run `25141807596` completed successfully
    on `f9b3b27`
  - hosted GitHub `WAMP Profile Benchmarks` run `25141807457` completed
    successfully on `f9b3b27`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `f9b3b27`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25142223693` completed
    successfully on `f9b3b27`; it produced complete but non-decision-quality
    repeat evidence and confirmed the server-side request-body delta is mostly
    after second-chunk wait
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `dart analyze packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`
  - `git diff --check`
  - `bin/test-fast`
  - `bin/verify`
  - hosted GitHub `CI` run `25143265285` completed successfully on
    `ffb1376`; `Fast Checks` completed in 5m43s and `Full Verify` completed
    in 8m10s
  - hosted GitHub `kTLS Validation` run `25143265320` completed successfully
    on `ffb1376`
  - hosted GitHub `WAMP Profile Benchmarks` run `25143265476` completed
    successfully on `ffb1376`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `ffb1376`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25143770043` completed
    successfully but was excluded from decision evidence because it was
    non-decision-quality and had a repeat-01 baseline `broken pipe` log line
  - manual hosted `kTLS HTTP/2 Benchmarks` retry `25143991933` completed
    successfully, was decision-quality, and had no connection-noise log
    pattern beyond expected manual artifact-gate skip notices
- Current H2 client tail read-size/gap split verification:
  - latest docs checkpoint `a3eb74a` passed hosted GitHub `CI` run
    `25144304526`; `Fast Checks` completed in 5m35s and `Full Verify`
    completed in 6m47s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `a3eb74a`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - local pre-change `bin/test-fast`
  - `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records --bin http_stream -- --nocapture`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `git diff --check`
  - `bin/verify`
  - hosted GitHub `CI` run `25145156786` completed successfully on
    `fb1f949`; `Fast Checks` completed in 5m35s and `Full Verify` completed
    in 7m58s
  - hosted GitHub `kTLS Validation` run `25145156820` completed successfully
    on `fb1f949`
  - hosted GitHub `WAMP Profile Benchmarks` run `25145156826` completed
    successfully on `fb1f949`
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `fb1f949`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - documentation checkpoint `6c8bd57`
    (`docs: record h2 tail read size ci`) passed hosted GitHub `CI` run
    `25145654807`; `Fast Checks` completed in 5m32s and `Full Verify`
    completed in 8m31s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `6c8bd57`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25146117904` completed on
    `6c8bd57` but is excluded from decision evidence because it was not
    decision-quality and the hosted log had two
    `http/2 accept error ... broken pipe` lines
  - manual hosted retry `25146345720` completed successfully on `6c8bd57` and
    produced decision-quality isolated `s1`, `threads=4`, one-router-worker
    alternating evidence: throughput delta span was `2.05pp`, p95 delta span
    was `10.26pp`, all repeats produced matched rows, and the hosted log scan
    had no connection-noise pattern beyond expected manual artifact-gate skip
    notices and benign setup/toolchain text
  - the retry kept kTLS throughput lower in all repeats at
    `-37.67%..-35.62%` and p95 higher at `+13.25%..+23.51%`
  - the new read-size/gap fields narrow the body-tail diagnosis: tail
    last-read-to-end stayed flat, average/max read size stayed flat/slightly
    lower on kTLS, tail read-count was only modestly higher, and max
    inter-read gap was kTLS-higher by `+0.25..+1.41 ms` with median
    `+1.35 ms`
  - the hosted artifact exposed a repeat-report readability bug where byte and
    count signal rows rendered with the default `ms` suffix despite the metric
    specs carrying `B` or empty units
  - the current local reporter fix preserves each repeat signal unit through
    rendering; focused verification passed with `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, `git diff --check`, and
    rerendering hosted run `25146345720`; full local `bin/verify` also
    passed on 2026-04-30, including Chrome/Dart2Wasm browser coverage
  - commit `b898053` (`bench: keep repeat signal units`) passed hosted
    GitHub `CI` run `25146937008`; `Fast Checks` completed in 5m56s and
    `Full Verify` completed in 8m24s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `b898053`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - documentation checkpoint `4752778`
    (`docs: record repeat signal unit ci`) passed hosted GitHub `CI` run
    `25147380520`; `Fast Checks` completed in 5m24s and `Full Verify`
    completed in 8m10s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `4752778`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - pre-change `bin/test-fast` passed locally on 2026-04-30 before adding the
    max tail inter-read gap position diagnostic
  - current local diagnostic change records the maximum H2 tail inter-read gap
    position at sample, summary, comparison, and repeat-report levels: read
    index after the gap, bytes before the gap, bytes after the gap, and
    byte-position ratio
  - focused local checks passed for that diagnostic:
    `cargo fmt --manifest-path native/bench/Cargo.toml -- --check`,
    `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records_read_sizes_and_gaps --bin http_stream -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `git diff --check`
  - full local `bin/verify` passed after the max-gap position diagnostic on
    2026-04-30, including Chrome/Dart2Wasm browser coverage
  - commit `b572b31` (`bench: locate h2 tail max gap`) passed hosted GitHub
    `CI` run `25148383883`; `Fast Checks` completed in 5m24s and
    `Full Verify` completed in 7m54s
  - hosted `kTLS Validation` run `25148383878` and hosted
    `WAMP Profile Benchmarks` run `25148383890` completed successfully on
    `b572b31`
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `b572b31`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns beyond benign tool/test text
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25148797004` completed
    successfully on `b572b31` with isolated `s1`, `threads=4`, one router
    worker, alternating repeats, and matched rows in all repeats
  - `25148797004` was complete but not decision-quality:
    throughput delta span was `57.19pp`, p95 delta span was `1736.62pp`, and
    the instability source was kTLS-side
  - the max-gap position diagnostic still narrows the tail-read boundary:
    max inter-read gap stayed kTLS-higher in all repeats by `+0.33..+1.32 ms`
    (median `+0.88 ms`), max-gap read index stayed around `24..25`, and the
    response-level position sat around `0.40..0.43` of the `1 MiB` response
    instead of at final-read completion
  - the current local response chunk-boundary reporting slice is implemented:
    workload request/response chunk sizes now flow into reports, and the max
    tail inter-read gap is summarized as response bytes-before,
    response-position ratio, response chunk offset, and response
    chunk-boundary distance in primary and repeat kTLS artifacts
  - focused local checks for that reporting slice passed:
    `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records_read_sizes_and_gaps --bin http_stream -- --nocapture`,
    `cargo fmt --manifest-path native/bench/Cargo.toml -- --check`, and
    `git diff --check`
  - full local `bin/verify` passed after the response chunk-boundary reporting
    slice on 2026-04-30, including Chrome/Dart2Wasm browser coverage
  - commit `41f9cb6` (`bench: classify h2 max gap chunk position`) passed
    hosted GitHub `CI` run `25149820481`; `Fast Checks` completed in 5m40s
    and `Full Verify` completed in 8m04s
  - hosted `kTLS Validation` run `25149820488` and hosted
    `WAMP Profile Benchmarks` run `25149820479` completed successfully on
    `41f9cb6`
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `41f9cb6`; companion
    kTLS/WAMP log scans only matched benign setup/config text, not Rust
    warnings, skipped tests, panics, resets, broken pipes, or connection-noise
    patterns
  - documentation checkpoint `b75dcca` (`docs: record chunk position ci`)
    passed hosted GitHub `CI` run `25150349893`; `Fast Checks` completed in
    5m44s, `Full Verify` completed in 7m58s, and the branch-head
    deployment-chain audit/log scan remained clean
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25150816510` completed on
    `b75dcca` but is excluded from clean decision evidence because the hosted
    log contained `http/2 accept error ... broken pipe` and an H2 broken-pipe
    connection error around the later repeats
  - manual hosted retry `25151080248` completed successfully on `b75dcca`
    with clean diagnostic logs apart from benign setup text and the expected
    manual artifact-gate skip notices
  - `25151080248` was complete and useful for diagnosis but still not
    release-decision-quality: throughput delta span was within threshold at
    `22.90pp`, p95 delta span was kTLS-side at `1271.34pp`, all repeats
    produced matched rows, and the worst throughput/p95 row stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the clean retry keeps the kTLS throughput loss stable at
    `-82.00%..-59.09%` (median `-69.02%`) and shows p95 at
    `+262.40%..+1533.73%`
  - the chunk-position fields resolve the immediate question: the max tail
    inter-read gap sits mid-response (`0.45..0.50` response-position ratio),
    not at final-read completion, and the chunk-offset/boundary-distance
    movement does not make app response chunk boundaries the sole explanation
  - repeated clean-run signals now point to H2 request-body/response-tail
    scheduling under kTLS: native request-body reader total and remaining
    tail-read, Dart request-body tail drain, native response tail chunk
    channel wait, native response first-to-last chunk send, and client body
    tail read all move kTLS-higher in repeated focus rows
  - documentation checkpoint `aab4c31`
    (`docs: record h2 chunk position benchmark`) passed hosted GitHub `CI`
    run `25151359137`; `Fast Checks` completed in 5m44s, `Full Verify`
    completed in 8m16s, and the branch-head deployment-chain audit/log scan
    remained clean
  - local pre-change `bin/test-fast` passed on 2026-04-30 before adding the
    request-body tail data-wait split
  - the current local native request-body tail data-wait split is
    implemented:
    native HTTP/2 request-body reader telemetry now separates remaining-tail
    wall time from remaining-tail `stream.data()` waits, records the
    per-request max wait, includes the final EOF wait after the second chunk,
    and carries both averages through FFI, Dart router metrics, bench
    summaries, and primary/repeat kTLS comparison reports
  - focused local checks for that diagnostic passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test router_metrics_snapshot_aggregates_reason_totals_and_listener_breakdowns -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `dart analyze packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`,
    and `git diff --check`
  - first full local `bin/verify` attempt exposed an FFI listen-flow race:
    `wait_connection_message_times_out_without_payload` dropped the raw socket
    client before polling the accepted connection, so the runtime could remove
    the connection and make `ct_connection_protocol` return
    `ERR_CONNECTION_NOT_FOUND`
  - that CI-clean blocker is fixed by keeping the TCP stream alive while the
    test polls the connection and waits for the expected no-message timeout;
    focused repro
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test wait_connection_message_times_out_without_payload -- --nocapture`
    passed locally
  - full local `bin/verify` passed on 2026-04-30 after the request-body tail
    data-wait diagnostic and FFI listen-flow race fix, including Rust, Dart
    package, bench, router, and Chrome/Dart2Wasm browser coverage
  - commit `6885def` (`bench: split h2 request tail data wait`) passed the
    hosted GitHub push chain:
    - `CI` `25153069857` with `Fast Checks` in 5m45s and `Full Verify` in
      8m12s
    - `kTLS Validation` `25153069860` in 2m44s
    - `WAMP Profile Benchmarks` `25153069894` in 7m53s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `6885def`; companion
    kTLS/WAMP log scans only matched benign setup/configuration text such as
    git default-branch hints, Rust toolchain timeout-reference comments,
    dependency names, workload timeout settings, and upload
    `if-no-files-found: error` configuration
  - documentation checkpoint `724077b`
    (`docs: record request tail data wait ci`) passed hosted GitHub `CI` run
    `25153709708`; `Fast Checks` completed in 5m39s and `Full Verify`
    completed in 7m53s
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25155199202` completed
    successfully on `724077b` with isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one router worker,
    `repeat_count=3`, `repeat_order=alternating`, `cooldown_seconds=15`,
    and `skip_artifact_gate=true`
  - `25155199202` was complete and log-clean apart from benign setup/toolchain
    text and expected manual artifact-gate skip notices, but it was not
    release-decision-quality: throughput delta span was `58.05pp`, p95 delta
    span was `1283.94pp`, and repeat 03 had a kTLS-side p95/header-wait
    outlier
  - the run still resolves the immediate diagnostic boundary: in the repeats
    where the native request-body tail delay appeared, remaining-tail wall
    time and remaining-tail `stream.data()` wait moved together
    (`0.06 -> 1.17 ms` in repeat 01 and `1.14 -> 3.51 ms` in repeat 03),
    while repeat 02 stayed flat/slightly lower; the remaining gap is therefore
    in H2 body data/EOF availability to `stream.data()`, not post-read
    enqueue/FFI/Dart drain
  - local pre-change `bin/test-fast` passed on 2026-04-30 before adding the
    request-body tail max data-wait position diagnostic
  - the current local diagnostic slice records the position of each request's
    maximum native HTTP/2 request-body remaining-tail `stream.data()` wait:
    returned event index, bytes before the wait, bytes after the wait, and
    whether the max wait was the terminal EOF event; those counters now flow
    through FFI, Dart router metrics, bench summaries, and primary/repeat
    kTLS comparison reports
  - focused local checks for that diagnostic passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test router_metrics_snapshot_aggregates_reason_totals_and_listener_breakdowns -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    rerendering hosted run `25155199202` with
    `tool/ktls_http2_compare_repeats.py`,
    `dart analyze packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`,
    and `git diff --check`
  - full local `bin/verify` passed after the request-body tail max data-wait
    position diagnostic on 2026-04-30, including Rust, FFI, Dart package,
    bench, router, and Chrome/Dart2Wasm browser coverage
  - commit `234e88d` (`bench: locate h2 request data wait`) passed the
    hosted GitHub push chain:
    - `CI` `25156460466` with `Fast Checks` in 5m43s and `Full Verify` in
      8m21s
    - `kTLS Validation` `25156460504` in 3m01s
    - `WAMP Profile Benchmarks` `25156460459` in 7m41s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `234e88d`; companion
    kTLS/WAMP log scans only matched benign setup/configuration text and no
    Rust warnings, skipped tests, panics, resets, broken pipes, or actionable
    connection-noise patterns
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25157185705` reran isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one router worker, alternating
    repeats on `234e88d`
  - `25157185705` completed with matched rows in all repeats but is not clean
    release-decision evidence: throughput delta span was `53.80pp`, p95 delta
    span was `212.93pp`, and the hosted log contained one real
    `http/2 accept error ... broken pipe` line during repeat 03
  - the max data-wait position fields still answer the active split: the
    remaining-tail max `stream.data()` wait is centered around event index
    `4`, with bytes-before around `208 KiB..226 KiB`, bytes-after around
    `244 KiB..250 KiB`, and a mixed EOF ratio around `0.46..0.64`; the gap is
    therefore more consistent with waiting for a late DATA frame than with a
    pure terminal EOF wait
  - the current local clean-chain fix classifies HTTP/2 accept-loop I/O
    shutdowns (`BrokenPipe`, `ConnectionReset`, `ConnectionAborted`,
    `UnexpectedEof`) as graceful peer shutdowns, keeps GOAWAY recorded as
    GOAWAY, and keeps true protocol errors logged
  - focused repro
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http2_accept_broken_pipe_is_classified_as_graceful_shutdown -- --nocapture`
    passed locally, `bin/test-fast` passed after the fix, and full local
    `bin/verify` passed on 2026-04-30 including Chrome/Dart2Wasm browser
    coverage

## Next Step

Commit and push the HTTP/2 accept-loop shutdown classification fix, then watch
the GitHub push chain and log scans. After the branch is hosted-clean again,
rerun the same isolated `s1`, `threads=4`, one-router-worker alternating
kTLS/H2 benchmark to confirm the diagnostic artifact stays free of broken-pipe
connection noise. If the rerun stays clean and repeats the mixed EOF-ratio
shape, the next diagnosis slice should instrument request DATA-frame
availability/window scheduling around the late `stream.data()` wait instead of
post-read enqueue, FFI, Dart drain, or terminal EOF handling.
