# FlatBuffers supplemental diagnostics

Issue: [#103](https://github.com/konsultaner/connectanum-dart/issues/103).

The primary acceptance inventory remains 48 cases, comparing all three codecs
for 3 warmups and 7 paired repetitions, each at least 10 seconds and 1,000 actual
samples. All checked-in throughput, latency, CPU, allocation, GC and RSS point
and confidence budgets remain unchanged. Sixteen native buffer/span cases now
explicitly require zero observed optimized payload copies; omitting a declaration
or observing a nonzero count fails the comparison.

## Supplemental inventory

`flatbuffers_extensions_v2` contains 50 cases, each paired across CBOR,
MessagePack and FlatBuffers: 1,500 total rows with the same run minima.

| Group | Cases | Coverage |
|---|---:|---|
| Small control operations | 8 | Publish acknowledgement, subscribe, register and cancellation; RawSocket clear and WebSocket TLS |
| Payload sizes | 12 | 10 KiB, 100 KiB and 1 MiB; Dart/native clients on both representative transports |
| Fan-out | 2 | Eight native subscribers on both representative transports |
| Progressive RPC | 4 | Three CALL chunks and three verified RESULTs; Dart/native clients on both representative transports |
| Mixed codecs | 6 | JSON/MessagePack/CBOR peers on both representative transports |
| Encrypted PPT | 8 | XSalsa20-Poly1305/AES-256-GCM; CBOR/FlatBuffers PPT on both representative transports |
| Fragmented WebSocket | 2 | Native masked 1,024-byte fragments with cleartext/TLS |
| Encrypted progressive results | 8 | Both ciphers and Dart/native clients; three CALL chunks and three RESULTs; CBOR peers on both transports |

Control and progressive rows use the ordinary envelope/CBOR-argument path;
unsupported typed progressive payloads are not substituted or silently omitted.
Encrypted ordinary RPC rows explicitly label the PPT serializer and create an application callee matching the envelope codec. Encrypted progressive rows use a CBOR application peer, exercising both homogeneous and mixed outer serializers. The control echo handler has no encryption provider and is not a valid encrypted application endpoint. Other rows use
the typed benchmark payload with the codec's matching PPT serializer. Human
reports retain these configurations, all per-codec resource/copy observations,
and actual accepted serialized bytes per operation, separately from logical
application bytes and transport framing.

Zero-payload controls report operations per second, not a meaningless ratio of
zero application Mbps. Supplemental numeric costs remain visible per case and
are descriptive diagnostics; they cannot establish primary acceptance. Missing
process, allocation, copy, encoded-volume or configuration evidence still fails.
Only a complete strict inventory with the pinned policy and unchanged inputs can
produce `diagnostic_complete`; it never produces primary `passed` acceptance.
The existing release comparator's primary acceptance behavior remains intact.

## Stable workers and duration support

Both the Dart workload runner and Rust driver previously rejected timed control
and progressive modes. The parent also discarded every successful helper outside
RPC/pub-sub, despite the child runtime already supporting serialized commands.
Five Dart duration cases, five parent PID cases and a Rust configuration case
first fail on these restrictions. The supported mode set now includes progressive
RPC and the four control cycles, using the existing real-operation scheduler.
Regressions require actual sample-window duration, contiguous operation identities
and empty registrations/subscriptions after cleanup.

Worker reuse remains opt-in. Failures always discard and reap the generation;
unsupported modes and default callers retain recycling. Both RPC and cancellation
failure recovery are covered. A preceding direct real-worker probe executes 370
mixed commands on one PID and exits normally; this is correctness evidence,
not benchmark timing or sufficient proof of the resulting parent path.

The new workflow mode `flatbuffers_extensions` runs the full declared inventory
on Linux and retains the complete inputs, source/artifact hashes, raw reports,
comparison JSON and Markdown. Its minimums do not change the primary policy.
Current-source live short proof, full verification and hosted results are pending.
The latest verified primary diagnostic still fails CPU and native-buffer
allocation parity; #103 and the milestone remain open.

The first short driver run stops after 18 rows on an encrypted RPC fixture
without that application callee. An isolated native MessagePack/WebSocket/TLS
AES-GCM + FlatBuffers PPT reproducer returns HTTP 500 with the control echo and
HTTP 200 with six verified samples after selecting the matching application
callee. The generated TOML regression fails first on the missing peer and now
requires it. This corrects the diagnostic setup; it is not a product crypto fix.
The failed run retains all 3,111 inputs unchanged and is not acceptance evidence.

## Renewed live correctness proof

After correcting the encrypted callee setup, the real Rust driver completes all
252 rows (one short warmup and one short measured pass) with one client PID and
one server PID. All 3,111 inputs and HEAD remain unchanged. Independent checking
verifies every declared configuration, at least four samples and 50 ms of actual
samples, all 252 encoded-volume sums, 48 encrypted/native-crypto pipelines,
28 active mixed transcodes and 32 zero-copy assertions. Homogeneous rows retain
explicit not-applicable transcode observations. The strict comparator rejects
these deliberately short settings. This is not performance acceptance.

## CPU profiling for the remaining regression

`tool/profile_wamp_serializers.py` samples the three codecs on warmed native
RawSocket cleartext 64 KiB buffer-construction RPC. It retains full HTTP reports,
Dart CPU sample tables, source and native-library hashes, process identities and
teardown evidence. Sampling must fit inside the actual observed operation sample
window. It shares the campaign host lease, detects Linux build/test/mutation
interference and rejects changed source or native libraries. Missing Linux
interference detection or native perf on other hosts is explicitly labelled.

The manual `flatbuffers_profile` workflow adds Linux perf captures and native
frame pointers/debug information. It retains the raw perf data and inclusive/leaf
reports beside the Dart sample tables. Such instrumentation alters execution;
these are hotspot diagnostics and never primary parity evidence. Native perf can
leave Dart JIT addresses unresolved, so Dart CPU samples remain separate.
The local three-codec smoke passes with distinct PIDs, unchanged inputs and full
process-group cleanup; native perf is explicitly unmeasured there. Linux capture
and the complete resulting-source verification remain pending.

The profiling invocation follows the Linux [perf record manual](https://man7.org/linux/man-pages/man1/perf-record.1.html)
for PID selection, software CPU-clock events and DWARF call chains. The workflow
installs Ubuntu's `linux-tools-generic` package and selects its actual executable,
avoiding a wrapper tied to the hosted kernel version. No SDK fork is required.

Focused checks pass: 139 Rust driver cases, 117 Dart workload/lifecycle cases,
43 comparator cases, 22 campaign/profiler-guard cases and eight synthetic
copy-evidence cases. Static analysis has only the existing informational lints;
all 154 equivalent-mutation proofs validate. The final local profiler smoke
checks that all three sampling intervals fit entirely inside real operation
windows, native/source hashes remain unchanged, and the process group stops.

## Resulting-source verification and Linux capture setup

Source `8f6f86f5` passes frozen full `bin/verify`, including JavaScript and
WebAssembly, with all 3,112 inputs unchanged. The only later application-test
change gives the preparation unit an explicit synthetic metadata root and three
lockfiles; it no longer depends on an ignored local native/bench/Cargo.lock.
All 22 campaign/profiler-guard cases and the corrected hosted Fast Checks pass.

Linux setup uses Python executable discovery because the hosted runner does not
have ripgrep. Perf files are returned to the runner's ownership before upload;
the first successful capture's upload failed because root-created files were
unreadable by the artifact action. The renewed upload retains all failed evidence.

The next capture correctly fails its sampling-window guard: collection ends
0.7507 seconds after the 15-second observed MessagePack operation window. Source,
library and process-group checks pass, with no interfering jobs. The diagnostic
operation window is now 30 seconds, retaining the same actual-window check and
five-second perf capture. This changes no primary or supplemental acceptance
minimum, repetition or numerical budget. A fresh Linux capture is required.

## Progressive result-stream coverage (inventory v2)

The original four progressive rows only sent three CALL chunks and consumed a
single result. Inventory v2 keeps that input coverage and now requires two
progressive results followed by one terminal result. Every result must contain
exactly the echoed payload and the expected progress flag, with no unexpected
keywords. Latency ends after the terminal reply; sample response volume includes
all three payloads. The comparison independently rejects sample request/response
volumes that omit any of the three chunks or results. Version v1 reports cannot
substitute for this inventory. No primary case or numeric budget changes.

Eight additional cases combine result streams with both supported ciphers,
Dart/native clients, representative transports and a CBOR application peer. The
current 36-codec-combination live correctness proof completes with 72 measured
operations: 24 encrypted paths, 16 active mixed transcodes and 12 native-crypto
paths. Independent summation reconciles all disjoint copy components and accepted
WAMP-volume totals. All source inputs remain unchanged during the proof; the
candidate is explicitly recorded as dirty, not misidentified as committed HEAD.
These short observations establish correctness only. Full source-frozen
verification and the complete Linux supplemental campaign remain required.

The new three-result regression fails on the preceding implementation. All 92
focused Dart cases and 65 campaign/comparison cases pass after the change;
analysis reports no issues. Additional rejection tests cover missing/extra
results, incorrect progress flags, corrupted payloads and unexpected keywords.

## Hosted case batches and complete-report validation

[GitHub documents a six-hour limit for hosted jobs](https://docs.github.com/en/actions/reference/limits)
(checked 2026-10-16). The superseded single-job run completes 137 unique first-pass
rows before cancellation, recording 2,117 seconds of actual sample windows.
Dart AES-GCM progressive cases require 118–123 seconds for 1,000 samples; the
largest payload case requires 62 seconds. Those observed costs put the full
1,500-row inventory at risk of the existing 19,800-second campaign deadline.
The incomplete run is retained as runtime evidence only: its execution remains
unfinished and its post-cancellation input proof is unavailable.

The workflow therefore partitions cases into three fixed semantic batches,
without changing inventory v2 or its operations:

| Batch | Cases | Full rows |
|---|---:|---:|
| Protocol, control, fan-out, mixed codecs and ordinary encrypted PPT | 30 | 900 |
| Payload sizes | 12 | 360 |
| Encrypted progressive results | 8 | 240 |

Every case keeps all three codecs, three warmups and seven paired measurements
on one controlled Linux runner. Every workload still requires at least ten
seconds and 1,000 actual samples. Each batch retains the existing stable client
and server PIDs, teardown, no-overlap, input, configuration, allocation, copy and
encoded-volume guards. The primary 48-case campaign and every numeric budget
remain unchanged. Case membership follows canonical identities and group
semantics, not list positions. The unsharded full CLI remains supported.

`--extension-shard` requires supplemental diagnostic mode and rejects individual
case selection. A valid batch produces `diagnostic_shard_complete`, never full
`diagnostic_complete` or primary acceptance. Removing its scope marker makes the
partial inventory fail the original full-inventory check. Primary campaigns
reject supplemental scope markers.

`tool/merge_wamp_extension_campaigns.py` re-evaluates each batch's original raw
reports with the unchanged checked-in policy. It verifies retained policy,
router configuration, every lockfile, driver/native binary and scenario hashes;
all batches must share the full source revision, input identity and toolchains.
It also compares the stored comparison to raw recomputation, checks exact
original-driver/per-pass equality and counts every case/codec/pass. Missing,
duplicate, cancelled, incomplete or corrupted evidence cannot complete the
inventory. CI matrix success is independently required even if all raw reports
happen to be available.

Results remain per case. Each batch's CPU model, platform, PIDs, artifact name,
workflow attempt and raw hashes are retained. Absolute costs across different
runners are explicitly `not_comparable`; no cross-case numeric pooling is done.
Canonical reordering preserves the original per-case observations and ratios.
The aggregate can produce full `diagnostic_complete` only for the exhaustive
inventory, and always retains `primary_acceptance_eligible: false`.

Retries select the newest whole artifact for each named batch within the same
workflow run. A previously completed atomic batch may be reused when another
batch is retried. Individual samples from different attempts are never spliced;
a newer expired or incomplete artifact cannot fall back to an older success.
All original artifacts remain retained. Explicit attempts and artifact names in
the aggregate make that provenance visible.

Focused tests use a deliberately small synthetic declaration but the real
1,000-sample floors, unchanged policy, raw evaluator, hashes and aggregation
checks. Separate tests require the exact real 50-case / 1,500-row partition.
Fault injections cover missing/duplicate batches, source/scope changes, input and
binary corruption, low samples, PID changes, unknown copy boundaries, forged
conclusions, mismatched driver rows and compensating codec omissions/duplicates.
These fixtures are never performance evidence. Real complete hosted batches
remain required after a credible primary candidate is established.
