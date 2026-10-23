# Project State

Last updated: 2026-10-23.

Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).

Current performance and copy-accounting follow-up is in the working tree on
`codex/flatbuffers-performance-parity`. It makes control-message fragment
preflight cheaper, reduces FlatBuffers writer/envelope allocations, accelerates
ASCII-heavy CBOR UTF-8 validation while retaining bytewise validation for
multibyte sequences, and adds native-owned E2EE plaintext/ciphertext accounting
for typed FlatBuffers as well as CBOR. The profiler worker now runs through its
package executable, so VM profiles can resolve package imports; exact
`ext_07_small_control` and `ext_22_progressive` profiles completed. Component
UTF-8 timings improved on ASCII and sparse-Unicode input, but they are not
end-to-end parity evidence.

Fresh `bin/test-fast` and full `bin/verify` passed on source `7621f701`, including
the full native, 2,009-case WAMP, Chrome/Dart2Wasm and consumer smoke suites.
The current worktree adds a CBOR transparent-binary parser compatibility repair;
its focused Rust tests and `bin/test-fast` pass, including all 2,009 live WAMP
integration cases. Current-tree full `bin/verify` remains pending.
The unchanged strict run on the previous source
[`39953423478`](https://github.com/konsultaner/connectanum-dart/actions/runs/39953423478)
completed all 1,440 rows and failed 139 numerical performance gates, with no
integrity findings. Supplemental run
[`39953434939`](https://github.com/konsultaner/connectanum-dart/actions/runs/39953434939)
completed all 50 cases/1,500 rows in diagnostic mode with 234 numerical
findings; it does not establish primary acceptance. The successful CI
[`39953531177`](https://github.com/konsultaner/connectanum-dart/actions/runs/39953531177)
is also for the previous source and does not accept this working tree. The
previous-source production copy proof
[`39953447152`](https://github.com/konsultaner/connectanum-dart/actions/runs/39953447152)
passed 120 owned E2EE/transcode/native-crypto rows under
`connectanum_buffer_boundaries_v1`; SDK/TLS/crypto dependency internals remain
explicitly unmeasured. Commit `7621f701` is now pushed to PR #132. Its exact-
source CI [`39992992607`](https://github.com/konsultaner/connectanum-dart/actions/runs/39992992607),
production E2EE/transcode copy proof
[`39993003404`](https://github.com/konsultaner/connectanum-dart/actions/runs/39993003404),
strict primary [`39992996231`](https://github.com/konsultaner/connectanum-dart/actions/runs/39992996231),
and full supplemental campaigns
[`39992999450`](https://github.com/konsultaner/connectanum-dart/actions/runs/39992999450)
are queued or running. No performance gate is waived and milestone acceptance
is not complete.

The `7621f701` production copy run failed when a live FlatBuffers client sent an
opaque E2EE payload through a CBOR WAMP peer: the Rust CBOR parser expected an
arguments list and rejected the direct binary payload, causing the native
worker to close the request. One supplemental encrypted-progressive shard hit
the same parser error. These observations are retained against that exact
source; its strict primary and other supplemental shards are still running,
and its CI remains queued. The worktree now accepts that transparent binary
representation in contiguous and segmented CBOR parsing, keeps definite
contiguous payloads borrowed, and accounts for unavoidable segmented decode
copies. No performance or current-source copy acceptance follows yet.

The exact `844a7913` baseline E2EE/progressive-results shard completed with 44
numerical performance findings across eight cases and no integrity findings;
the original strict gates remain unchanged. Its diagnostic CPU profile is
source/input clean and shows Dart byte-copy work in the inner CBOR/E2EE path;
that profile is diagnostic only. Exact-head primary and protocol campaigns
for `844a7913` are still running and do not include the new working-tree change.

Current performance follow-up: the native reader now omits absent optional
reference entries and reserves scalar/present-field storage for larger tables.
All structural validation, scalar defaults, CBOR Map-null agreement, required
metadata and known authentication methods remain preserved. Separate private
baseline/candidate builds each pass 399 unit/three integration cases; incomplete
Map-null and metadata controls fail the intended semantic tests. Independently
audited 76 allocator inputs/836 cold and repeated observations retain 56 exact
wires with no request increase. Common 1-KiB reads save 224–616 requested bytes.

The selected short-table variant has 160 balanced component observations across
ten inputs. Nine paired CPU medians improve; challenge retains a 0.04% cost.
These are component measurements, not parity acceptance. A further early-skip
variant is excluded with all its observations retained. Actual-source native
format/tests and 34 allocator/wire comparisons pass with 3,205 source/four
resolved hashes fixed. Final full verification, CI, copy/lifetime proof and the
unchanged complete performance campaigns are pending for this runtime.
See [native sparse-reader evidence](research/2026-10-23-flatbuffers-native-sparse-reader.md).

The preceding runtime `629001a6` passes all 38 CI jobs but retains seven strict90
numerical failures. Completed old primary `984288cb` is independently audited:
1,440 rows, zero integrity findings and 143 numerical costs. Its supplemental
protocol/encrypted shards have 900/240 valid rows and 151/46 numerical costs;
its payload shard retains the original TLS failure. No cross-run totals grant
current-runtime acceptance and no started observation has been canceled.

Complete read-only kernel replay 39903748528 retains 90 valid workload rows and
44,784 paired prune events without truncation or loss. Every event is labelled
unowned because that successful run produced no stall-triggered FD witness.
It establishes no kernel cause or transport fix. Separate two-second Linux smoke
39910831712 now independently matches the connect hook to the actual unprivileged
FD inode/PID/tuple/network namespace and verifies graceful cleanup. Applying that
ownership witness to the original workload remains pending; no socket-buffer,
SDK, sysctl, allocator-policy or acceptance-budget change is justified.

Current follow-up packs common validator `(offset, schema)` memo keys into exact
integers, with original-record fallback outside the packed domain. Validation,
wire/ABI and owners are unchanged. Private baseline/candidate each pass 501
functional checks and 63 JS/63 Wasm checks; an unsafe offset-only control fails
three cases including real table-budget undercount. Audited 160 rows/32 fresh
workers/128 allocation windows save about 63–65 managed bytes per decode, with
RESULT/CALL time ratios 0.98961/0.99163. These are component results. Actual-source
analysis, all 3,457 serializer cases and eight isolation contracts pass; runtime
bytes equal the audited candidate. Hosted CI and unchanged complete
acceptance remain pending. See [validator-key evidence](research/2026-10-23-flatbuffers-validator-keys.md).

Runtime `629001a6` now passes frozen `bin/verify` in 22m43s, including Chrome/Wasm,
with all 3,204 source/four resolved hashes fixed and a clean tree. Its Linux
decoder component passes independent source/content/window audit: 492 tests per
variant, 160 rows/32 workers/128 allocation windows and 204 private hashes.
Managed savings persist at about 65/63 bytes per RESULT/CALL decode. Linux timing
ratios are 1.00671/0.96892; RESULT's 0.67% cost stays visible. Current production
copy/lifetime proof also passes all audits: 120 owned/300 short cases/all 32
no-copy observations, 36 groups/108 post-GC, public owners zero before forced GC.
Strict90 has 90 valid rows/zero integrity findings but seven numerical costs:
all CPU/allocation pass; RSS, Dart-value GC confidence/throughput and pre-encoded
p95/p99 remain blockers. Current CI 39893888135 passes all 38 jobs.
The previous diagnostic CI is superseded; no started benchmark is canceled.

Verified runtime `984288cb` removes absent optional reference entries
from internal Dart wire tables and bounds native agreement's temporary field
reservation. Public CBOR metadata, scalar defaults, wire/ABI and payload owners
are preserved. Private Dart baseline/candidate each pass 491 checks, and an
incomplete negative control fails 52 CBOR cases. Native variants use separate
builds and actual-core markers; 39 existing cases plus marker checks pass, all
76 allocator inputs retain every cold/repeated observation without request
increases, and all 56 emitted wires match. Common native reads request 672–1,176
fewer bytes/up to one fewer allocation. The empty-capacity prototype's 56-byte
Abort regression is fixed by schema capping; the unproven shared-target comparison
is excluded. These are components, not Linux RSS/timing acceptance.

Baseline bin/test-fast passes on docs head `2646ee69` with all 3,201 sources/four
resolved inputs unchanged. The current follow-up passes seven component-isolation contracts, 20 CI execution
contracts and 154 mutation proofs. Resulting-source analysis exits 0, all 3,456
serializer cases and 39 native conformance cases pass; actual-source reader/
encoder requests match the audited private candidate exactly. All 3,202 source
and four resolved hashes stay fixed. Qwen questions are resolved by source and
negative controls; GLM has no confirmed correctness finding. The unchanged
complete timing gates remain required.
See [temporary table research](research/2026-10-23-flatbuffers-temporary-tables.md).

Frozen full `bin/verify` on `984288cb` passes in 23m08s, including Chrome/Wasm,
with 3,202 sources/four resolved inputs unchanged and a clean tree. A fresh
`bin/test-fast` also passes with identical source/resolution. Both Linux components
pass independent audits. Dart baseline/candidate each pass 491 cases; 160 raw
rows/32 fresh workers/128 allocation windows preserve wires and aliases.
RESULT/CALL decode ratios are 0.93782/0.91738, about 456/812 fewer managed bytes.
Native readers retain every cold/repeated count without request increases;
24 reader/ten encoder rows have 34 identical wires. These are component results.

Renewed production proof 39882163712 passes all source/content/lifetime audits:
120 owned cases, 300 short rows/all 32 no-copy observations, 36 groups/108 post-GC.
All public leases have zero owners before forced GC. Current strict 39882166630
has 90 valid rows/zero integrity findings but eight numerical costs. Allocation
and CPU pass all three cases; Dart-value GC, latency/RSS and remaining RSS/p99
gates fail. Full primary 39882169066 and supplemental 39882172130 continue.
Its payload shard fails after 20 valid rows at the original ext18 FlatBuffers TLS
300000-ms deadline. The earlier runtime55 payload shard fails after 139 rows at
the same case/deadline; all completed rows and failures remain retained.

Profile 39884174360 passes source/window/native-clock/18-snapshot audit. An
ordinary-no-PPT fragmentation proposal is excluded before observation because
the failing primary values already use typed PPT. A generated getter annotation
experiment passes 76 cases per variant and 160 component rows but has mixed
timing/essentially unchanged allocation; it is also excluded. No production
follow-up is adopted from either experiment.

Current work targets the recurring TLS receive-window failure. Traced original
replay 39883379996 and untraced focused 39885378060 preserve all original limits.
Upstream kernel code supplies a clamp lead, not a proven Ubuntu Azure cause.
The diagnostic now adds bounded, allowlisted namespace TCP prune/collapse
counters with explicit failures. All five new groups fail before repair; 86
focused ownership/capture/smoke/CI contracts pass afterward. Advisory review has
no confirmed defect. Frozen full `bin/verify` on diagnostic head `f2dbdfa4` passes
in 22m36s, including Chrome/Wasm, with 3,203 sources/four resolved inputs fixed
and a clean tree. Its CI 39888953092 is superseded by current-runtime CI; preceding runtime55 CI
39874541986 passes all 38 jobs.

Both untraced focused replays reproduce the original ext18 deadline. Run
39885378060 has 72 valid rows/three qualified owned socket pairs, client buffer
1,138 bytes, peer window 2,048 and about 9.85 KB/s continuing transfer. The
counter-enabled run 39886982363 has four valid rows/three qualified pairs,
client buffer 30,603, peer window 30,720 and 99.9–100% sender window limitation.
Its namespace totals retain seven prune calls/four receive prunes/24 collapses
and zero TCP memory-pressure events; these totals are not per-socket attribution.
Matching-version Ubuntu Azure source confirms the queued-memory clamp assignment
and uses incoming `skb->len` in ingestion checks, differing from upstream's
`truesize` check. Source does not prove the executed kernel path.

Private bounded, borrowed batches for large unmasked WebSocket writes pass all
14 focused checks versus ten passes/four intended baseline failures. Full native
conformance passes 402 unit/three integration tests. All 6,408 private inputs,
actual-core markers and separate executable hashes are independently verified.
The unchanged 90-row Linux focused replay 39892063835 on separate experiment
commit `2be50a0b` fails after three valid rows at ext18 CBOR's original TLS deadline.
Its 3,203 sources/four resolved inputs, original limits/binaries and cleanup are
audited. Three qualified captures retain six owned socket records: worker buffer
35,812 bytes/peer window 35,840. The scheduling candidate is excluded and never
adopted; the failure now also reproduces on CBOR. Runtime `984288cb` full CI
39882176722 passes all 38 jobs; diagnostic CI 39888953092 is still running without
known failures. Keep the TLS blocker and all completed observations visible.
No SDK, sysctl, allocator, socket-buffer or acceptance-policy change is justified.
See [TLS follow-up](research/2026-10-23-tls-receive-buffer-follow-up.md).

The private kernel observer now passes independently audited Linux lifecycle,
BTF-render, explicit monotonic clock, original UID/environment/argv and STOP/EOF
proofs. Thirty-four private contracts pass; deliberate observer failure does not
cancel the two-second sibling dummy. No real workload/prune path is proved yet.
The current-runtime focused replay 39901646493 is building separately, preserving
all original 90 rows/floors/deadlines. Current CI 39893888135 passes all 38 jobs.
The older runtime55 primary is now fully audited: 1,440 rows/zero integrity findings,
207 numerical costs, exact recomputation. It grants no current acceptance. See the
[Linux observer evidence](research/2026-10-23-tls-receive-buffer-follow-up.md#live-btf-and-independent-observer-lifecycle).

## Earlier checkpoints (historical)

The preceding runtime candidate `55ae6f4d` derives immutable dictionary-field plans once
from the pinned schema and shares them between projection and frame agreement.
It removes repeated full-schema scans/filtering in two Dart modules without
changing value/default/type checks, wire schema, native ABI or byte ownership.
Hosted component run 39872554911 passes analysis and 434 existing functional
cases on each private baseline/candidate. Independent audit verifies all 3,201
sources/four resolved contents, selected package variants, identical wires and
payload aliases, 160 raw rows/32 fresh workers/128 measured windows and managed
allocation proofs. RESULT/CALL median decode ratios are 0.82056/0.83085, with
about 80 fewer managed bytes per decode. This is component evidence only;
frozen resulting-source `bin/verify` on docs-only successor `02840d2d` passes
in 22m54s, including Chrome/Wasm, with 3,201 sources/four resolved inputs fixed
and a clean tree. Qwen review finds no demonstrated defect; const schema and
absence of public exports are verified directly. Hosted Fast Checks, binding,
GuardMalloc and shared FFI build pass; the complete CI matrix remains pending.
The renewed production copy/lifetime proof 39874511303 passes independent audit:
3,201 sources/four retained hash-identical resolved contents, 36 groups/108 post-GC
observations, 120 owned cases/300 short rows and all 32 no-copy observations,
including E2EE/native crypto/transcodes. Native binaries match the preceding proof.

Strict candidate run 39874514230 has 90 independently validated rows and no
integrity findings. Throughput, p95/p99, CPU and allocation pass in all three
cases. Two gates remain: Dart-value GC confidence upper bound 1.13284 (median
0.91619), and pre-encoded RSS median 1.01949. Native-buffer passes every metric.
These runner-specific changes do not establish a causal RSS fix. Candidate full
primary 39874517410 and supplemental 39874520570 remain observing. No acceptance
budget, case, floor or observation is waived.

The preceding-runtime supplemental 39852994229 is now independently audited in
full: 50 distinct cases/1,500 rows, all original floors, input/native hashes,
raw/per-pass equality and exact comparison recomputation, zero integrity findings
and 244 reported numerical costs. These diagnostic costs remain visible and
cannot substitute for primary acceptance. Absolute cross-shard costs are not pooled.

The preceding fully verified runtime `c0aef5fa` removes an extra copy of the fresh validated metadata
map and uses the checked-in generated enum switch in Dart decoding. It retains
the adopted two-table/one-string inline reader cache. Private baseline and
candidate suites each pass 434 cases, including mutable ERROR metadata, independent
messages, lazy payload access and re-encoding. Forty initial and 160 subsequent
balanced component windows preserve wires/storage aliases. Eight worker processes
per variant/shape measure about 382/392 fewer managed bytes and roughly 7% lower
warm RESULT/CALL decode time. These are component results, never hosted parity.
Resulting-source formatting, focused analysis and all 3,399 serializer cases
pass with 3,193 source/resolved hashes fixed. Frozen `bin/verify` on runtime `c0aef5fa` passes in 23m22s, including
Chrome/Wasm, with all 3,189 sources/four resolved inputs fixed and a clean tree.
Its renewed copy proof 39840616517 also passes independent source/contents/
lifetime audits.
The current follow-up changes diagnostic capture/control tooling and its tests;
the native library remains unchanged; the dictionary-field candidate above
adds the first Dart runtime follow-up to verified `c0aef5fa`.

Frozen full `bin/verify` on corrected diagnostic head `76c4282c` passes in
22m59s, including Chrome/Wasm, with all 3,193 sources/four resolved inputs fixed
and a clean tree. Runtime CI 39840612253 passes all 38 jobs. The superseded
ordinary CI on pre-correction `fe9f9b6d` is confirmed canceled; all started
benchmark observations remain preserved.

Both corrected fresh-process RSS controls pass independent audits: 60 rows each,
exact inputs/scenarios, stable per-pair processes, production binaries and cleanup.
FlatBuffers remains higher than CBOR in both fresh pairs for each case. The
excess is mostly client RSS and larger than reported live-heap differences;
no causal runtime fix is established. A default-off passive memory observer now
reads standard VM buckets and owned process maps, with complete-report hashes,
identity checks and retained failures. Both hosted Linux attribution controls now pass independent audits (120 rows,
48 owned role observations). Most of the native-case client RSS gap is in unnamed
anonymous mappings. The FFI library resident size is identical across codecs.
No cause or runtime fix is inferred from mapping names/alignment. No acceptance
policy changes.

A diagnostic-only allocator follow-up adds owned, bounded standard external-memory
usage and glibc all-arena counters through temporary benchmark wrappers. Existing
instrumented profile snapshots have 112 bytes of external usage after workloads
for every codec; that does not establish unprofiled liveness or RSS acceptance.
The new default-off mode must pass a known native allocation/free self-test and
real Linux service/ownership smoke before observing workloads. It changes no
production package, SDK, allocator policy, GC or acceptance limit. Focused Python
contracts pass; local Dart analysis/full verification and companion review are
currently blocked by another task's machine resource lease. They are not claimed
as passed. Pinned hosted validation is the next check. The canonical tooling gate now includes the
owned-discovery, smoke, RSS-control and memory-observer regressions; a new gate
contract fails for all four omissions before repair and passes afterward. The
owned local verification resource wait is stopped before verification begins
to make this test-chain repair; no benchmark observation is canceled.

The first allocator control 39865339251 passes pinned Dart analysis, the
controlled allocation/free check and the owned Linux extension smoke. It then
fails one CBOR worker observation after two complete ten-row driver segments.
Independent audit verifies all 3,196 sources/four retained contents, exact raw
reports, stable PIDs, unchanged production binaries and cleanup. Its old error
records only ValueError, so that failing condition is still unknown. Additionally,
the wrappers retain a 260+ MiB kernel-service heap, unlike canonical cached JIT
executables. All partial comparisons are excluded. Temporary wrappers now compile
to JIT kernels before launch, with checked kernel magic and an explicit compiler-
heap exclusion. Errors retain safe phase/source locations and only our literal
validation messages. Ninety-nine focused contracts and workflow parsing pass;
real Linux validation is still required. No started benchmark is canceled.

The JIT-kernel retry 39867099125 passes analysis, controlled allocation/free and
real compiled-kernel smoke. Retained complete snapshots have no compiler heap and
return to roughly 200–235 MiB RSS. It again finishes two ten-row driver segments,
then fails CBOR worker getMemoryUsage type validation before report ten finishes.
Sources are unchanged and both drivers/cleanup succeed. This identifies the
failing operation, not the unexpected response type or its cause. A bounded
protocol-type/kind/request-isolate record now preserves only known safe enums;
Sentinel/error results remain failures, never zero or automatic retries. Seventeen
memory contracts pass. The failed artifact remains excluded from comparisons.

Classification run 39868319957 confirms Collected Sentinel from the isolate-
scoped getMemoryUsage request, this time on the first FlatBuffers pair. Failed
captures remain failures, with no zero substitution or retry. The probe now uses
the standard getIsolateGroupMemoryUsage API once per distinct group, matching
shared-heap semantics and avoiding duplicate per-isolate requests. Group IDs and
isolate references are retained; Expired group sentinels still fail the capture.
Eighteen memory contracts and 101 combined focused contracts pass before the
final URL assertion, which also passes. Real Linux group capture passes in run 39869871111/artifact 12466123130:
60 complete rows, six fresh pairs, 12 snapshots/24 owned role observations,
controlled allocation/free and compiled-kernel ownership smoke. Independent
source/content/binary/report/PID/cleanup audits pass. No compiler heap remains;
worker external usage is 112 bytes for every codec at the final boundary.
All-arena free retention accounts for most arena-system bytes, while FlatBuffers
RSS lies within the CBOR range on this diagnostic runner. These counters do not
reconcile resident bytes exactly or establish a runtime fix; strict RSS gates
remain unchanged.

Current-runtime supplemental payload batch 39852994229/artifact 12463981138
passes independent input/binary/raw/comparison audits: 360 rows/12 cases, zero
integrity findings, 28 numerical costs. Ten-KiB Dart values have about 2–3% CPU
costs. Profile 39868579299 passes independent 3,196-source/three-resolved-content,
18-snapshot, clock/window, native sampling and cleanup audits. Filtered stacks
identify repeated dictionary projection and agreement checks, motivating the
measured dictionary-field candidate above. Superseded ordinary CI32 is confirmed canceled with five
successful jobs retained, including Fast Checks and FlatBuffers Binding. Every
started benchmark is preserved, and final-head CI is still required.

Older primary run 39792311393 completes all 1,440 rows/48 cases with zero integrity
findings but 144 numerical costs; independent input/binary/raw verification and
comparison recomputation agree exactly. This is older runtime `2de4ec32`, never
current acceptance. The preceding-runtime full campaigns remain observing; the new Dart candidate
requires fresh campaigns.

Current strict run 39840621032 completes 90 valid rows with zero integrity
findings. Throughput, p95/p99, CPU, managed allocation and GC pass in every
case. Two RSS costs remain: Dart values (ratio 1.0082) and native buffer
(1.0188); pre-encoded spans pass all metrics. This three-case diagnostic cannot
accept primary parity, and runner-to-runner count changes are not causal proof.
The native-buffer profile 39841411082 also passes source, clock/window,
18-snapshot and cleanup audits. Its profiling flags exclude timing acceptance;
no new isolated codec hotspot is established from it.

The corrected real Linux smoke passes in run 39845190356. Its faithful replay
then fails at 47/360 rows, preserving three positive owned TCP_INFO captures.
Independent audit verifies all 3,190 sources/four retained resolved contents,
original order/floors, production binaries and recorded cleanup/invariance flags.
The client receive buffer remains 2,072 bytes, server advertised send window
3,072 bytes, and transfer continues at about 14.8 KB/s while receive-window limited.
This establishes flow limitation, not its cause. The next opt-in diagnostic
records owned descendants' socket-option calls and fixed TCP policy/pressure
state. It preserves the original driver/scenarios/deadlines and cannot accept parity.
The traced replay 39852837408 now completes all 360 rows. Independent audit
verifies sources/contents/binaries/original schedule/cleanup and the full trace:
13,107 setsockopt calls, zero SO_RCVBUF or TCP_WINDOW_CLAMP mentions. Of 55 owned
snapshots, 54 have stable progress through capture; one changed during capture
and is excluded from interval interpretation. Tracing is intrusive and cannot
accept parity or prove the earlier intermittent failure fixed.
A separate fresh-process RSS control distinguishes codec/process history without
changing the strict RSS gate. The first hosted RSS controls fail validation after one ten-row segment each.
Their retained reports expose incorrect sample timestamp assumptions and missing
worker-reuse environment. Both have failing regressions before correction; all
60 archived strict rows pass the repaired report validator, and 18 focused
contracts pass. The renewed complete controls pass as recorded above. Runtime CI 39840612253 passes all 38 jobs. Latest full
`bin/verify` on `76c4282c` passes as recorded above; the new optional attribution
follow-up still requires resulting-source verification.

Before this follow-up, `dd6e674a` passes the resulting-source serializer directory
(3,398 cases), focused analysis and full `bin/verify`, including Chrome/Wasm.
The combined focused/analysis/full pipeline takes 23m30s, with all 3,186 sources
and four resolved inputs unchanged and a clean tree. Advisory Qwen review finds
no concrete reader/cache/map defect; reader lifetime is synchronous and local,
and the checked-in generated `fromValue` factory is verified directly.

Its renewed production copy/lifetime run 39835442712 passes independent audit:
four lifetime phases, 36 snapshot groups/108 post-GC observations, 120 owned-path
cases and 300 short rows, including E2EE/native crypto/transcode and all 32
no-copy observations. Public leases export no byte view and leave zero native
owners before GC. Production exports contain no test oracles. All four recorded
resolved hashes match independently retained contents; native/driver binaries
match the preceding production proof.

The `dd6e674a` strict diagnostic 39835447509 completes 90 valid rows with zero
integrity findings and twelve numerical costs. Allocation and throughput pass
in all three cases; CPU/latency/GC/RSS still have failures. Do not infer a causal
change from the earlier runner's six-cost result. Its full primary campaign
39835451321 and all three supplemental shards 39835455283 are observing.
Only superseded run 39824883272 is canceled: a fresh snapshot verifies an
unstarted pending job with no runner steps. Every started campaign is preserved.
No budget, case, floor, repetition, baseline or deadline is waived.

Native `08efcd5b` passes frozen local verification and all 39 conformance tests.
Independent allocator audits verify matching compiler/lock/probes and 34
identical wires: decoding requests 552–1,368 fewer bytes/1–3 fewer allocations,
and encoding requests 720 fewer bytes in all ten fixtures. The completed older
`36a6df24` primary campaign has 1,440 rows, zero integrity gaps and 187 costs,
retained separately.

The faithful 1-MiB TLS timeout remains unresolved. The next diagnostic adds
bounded `ss` TCP_INFO/socket-memory snapshots for verified owned IPv4 loopback
application sockets, with numeric tuple/inode checks and process identity checks.
Its isolated 46-test staging suite and 49 original production capture
contracts/14 CI contracts pass; the five added smoke-fix cases also pass.
All 54 combined resulting-source capture/smoke contracts and 14 CI contracts
pass. The real Linux smoke now passes; the unchanged replay failure and next
discrimination are recorded above. This changes observations, never the workload
or performance acceptance. See the TCP diagnostic research note.

Native source review finds no demonstrated defect. Qwen's hypothetical sorting/
sharing concerns are checked against private storage, binary-position insertion,
mutable-value-only access and bounded (at most 21-field) schema tables. GLM also
finds neither claim demonstrated; schema-wide BTreeMap comparison and Arc/Bytes
alias regressions pass. Application dictionaries retain their original maps.

A retention regression finds that artifact uploads omit the copied
.dart_tool/package_config.json because its path contains a hidden directory.
Visible retained names now preserve every resolved input; the new assertion
fails before the repair and all 21 capture tests pass afterward. Both older
replays' recorded package hash exactly matches independently retained e1ab797a
profile content, permitting content verification with explicit recovery provenance.

The original-process replay on 17f27d25 fails at 257/360 rows on the same one-MiB
Dart/TLS/FlatBuffers case. Three captures show server send queues of about
497/954/364 KiB, no client kernel receive backlog and unchanged native runtime
CPU ticks. This identifies backpressure but does not establish its cause.
The reduced 90-row diagnostic passes; it cannot accept the full schedule.
The complete 36a6df24 protocol shard has 900 valid rows and 153 retained costs.

The repaired operation-window profile on e1ab797a captures a valid MessagePack
interval and native reports, then fails starting the FlatBuffers perf recorder
(exit 255). It has no FlatBuffers comparison. Retry 39822284373 is running.

The repaired E2EE profile retry `39822284373` on `e1ab797a` succeeds for all
three codecs. Independent audit verifies 3,183 source/three resolved hashes,
18 snapshots, independent post-hoc VM/native clock ranges and every sampled VM
timestamp, positive filtered native reports and cleanup. Its largest exclusive
Dart function is in a common CBOR PPT copy path. No additional FlatBuffers cause
is established. Before/after class allocation deltas are not inferred because
workload observers reset accumulators. Profile HTTP reports lack the driver's
pipeline-applicability fields; observed component sums/active crypto are checked,
while full copy acceptance comes from the separate production proof. The earlier
same-head recorder startup failure remains retained rather than relabelled.

The CPU profiler explicitly pins/records one native runtime thread, matching
acceptance. Hosted fail-first `5b9f63c7` reproduces nine inherited parent threads
in all 32 selection/mode combinations. Repair `80b16f4b` passes all 13 tests and
the real 10-KiB profile; independent audit verifies 3,181 tracked sources/three
resolved inputs, the pin, 18 snapshots and cleanup. The profile does not isolate
the primary regression. Earlier actual thread counts remain unrecorded.
Production Dart/Rust remains unchanged. All 38 runtime CI jobs on `2de4ec32` pass.
The original Linux thread/TCP replay continues. A separate 90-row reduced
diagnostic targets the three declared case transitions preceding the captured
stall; its preparation, smoke and result remain pending. Full campaigns continue.

The working tree now adds a first-owner slot with lazy identity-map overflow to
the native Dart FlatBuffers allocator, after frozen `bin/test-fast` passes in
15m20s with 3,172 source inputs/four resolved inputs unchanged. Private actual-model
components retain 20 native lifecycle checks, 24 allocation windows and 56
balanced timing observations under fixed root/private/library inputs. For the one-KiB fixture, managed
allocation pressure falls about 209 bytes per construction (6.8%); one-KiB
construction time improves about 7.2%. Growth/one-MiB timing intervals overlap
parity. The primary workload uses 64 KiB; these component percentages are not
primary gains or whole-workload acceptance. The adopted
methods match the tested candidate; declaration grouping/comments preserve field
order. See [allocator research](research/2026-10-22-native-flatbuffers-inline-owner.md).

The adopted source passes 50 focused ownership/frame/segment cases, independent
wire and isolated native-counter regressions, clean analysis, all 154 existing
static mutation proofs and regenerated target inventory. The first Python tooling
invocation uses the wrong module path and executes no actual tests; direct-entry
reruns pass 13 proof tests and 93 runner tests (one pre-existing skip). New helper
style notices are fixed; its isolated cleanup probe, added parent error-path
coverage case and final 50-case rerun pass with clean analysis. Source review
confirms no demonstrated ownership defect; withdrawn/inapplicable companion
findings are recorded with source/test dispositions. Frozen full `bin/verify` on committed `2de4ec32` then passes in 23m58s, with
all 3,174 source inputs/four resolved inputs unchanged and a clean tree, including
Chrome/Dart2Wasm. Its exact-head hosted lifetime/copy renewal also passes;
full CI and performance campaigns remain pending. No ABI/schema,
write guard, byte-view export rule, lease or copy policy changes. Last fully
verified checkpoint `36a6df24` remains separate from this working-tree follow-up.

Frozen full `bin/verify` passes in
27m22s, including VM/live/consumer and Chrome/Dart2Wasm verification. All 3,172
source inputs and four resolved inputs remain unchanged; the tree is clean
through verification. [Exact-head CI](https://github.com/konsultaner/connectanum-dart/actions/runs/39780933118)
on checkpoint `36a6df24` now passes all jobs.

The native reader now caches its first four string offsets inline, initialized
lazily, with randomized HashMap overflow and the original validation/visit
budgets. All 37 native FlatBuffers tests pass. Independent audits of Linux
[baseline](https://github.com/konsultaner/connectanum-dart/actions/runs/39779792736)
and [candidate](https://github.com/konsultaner/connectanum-dart/actions/runs/39780950258)
verify 3,172 tracked inputs, the resolved lock, same compiler/probe, executable
hashes and all 24 identical reader wires. CALL/ERROR/PUBLISH each save one
allocation and 116 requested bytes on Linux (108 bytes locally). Normal-allocator
local component timings improve CALL/PUBLISH without claiming whole-workload
parity. See [string-cache research](research/2026-10-22-flatbuffers-inline-string-cache.md).

[Current lifetime/copy proofs](https://github.com/konsultaner/connectanum-dart/actions/runs/39780939085)
pass independent audit of four phases, 120 owned cases and 300 short inventory
rows, including E2EE, native crypto, transcode and all 32 no-copy observations.
Public leased workloads prohibit byte-view export and leave zero tracked owners
before GC. These short observations establish copy correctness only.

The [current strict 90-row diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/39780945063)
completes with zero integrity gaps and three numerical failures. All three
throughput, p95/p99, CPU and allocation comparisons pass. Dart-value GC confidence
bounds and Dart-value/native-pre-encoded RSS comparisons fail. Its production
binaries exactly match the copy proof. Final [48-case/1,440-row primary](https://github.com/konsultaner/connectanum-dart/actions/runs/39784808712)
and [50-case/1,500-row supplemental](https://github.com/konsultaner/connectanum-dart/actions/runs/39784813538)
campaigns are running. No floor, case, budget, deadline or better-codec baseline
is weakened; absolute cross-runner costs are not pooled.

The checkpoint `36a6df24` payload-size shard also fails, at 85/360 rows after
its two completed passes, on the same one-MiB TLS WebSocket Dart-value FlatBuffers
deadline. All retained rows meet sample/duration floors, match the original order
and verify 14 no-copy observations; available locks/policy/scenario/binary hashes
and cleanup pass audit. Its final source-invariance flag is absent/unconfirmed.
The native library/driver match the checkpoint's copy and strict timing binaries.

On `2de4ec32`, the [renewed copy proof](https://github.com/konsultaner/connectanum-dart/actions/runs/39792299754)
passes independent audit against all 3,174 committed source hashes: four lifetime
phases, 120 owned cases, 300 short inventory rows and all 32 no-copy observations.
The production library/driver hashes match `36a6df24`; the Dart allocator differs.
The [renewed strict diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/39792305245)
completes 90 rows with zero integrity gaps and eight numerical failures. Dart
values fail CPU, throughput, p95, p99, GC and RSS; native-buffer and pre-encoded
paths each fail RSS. All allocation comparisons pass. These are separate runner
observations, not causal before/after estimates or primary acceptance. The
resulting-source [primary](https://github.com/konsultaner/connectanum-dart/actions/runs/39792311393)
and [supplemental](https://github.com/konsultaner/connectanum-dart/actions/runs/39792316277)
campaigns remain queued/running behind retained observations.

The resulting-source payload-size shard completes all 360 rows with zero
integrity findings, all 60 no-copy observations, stable client/router processes
and identical independently recomputed comparisons. Its production binaries
match the copy proof; all original floors/repetitions remain. It retains 36
performance costs, including about 19% lower throughput in the 10-KiB Dart-value
RawSocket case. Profiling now accepts that exact canonical case; its new
contracts/profile are pending validation. A passing full shard does not explain
or waive the separately reproduced intermittent one-MiB stall.

The passing historical replay is not a causal control: it uses URI entrypoint
wrappers, ephemeral ports and disabled unused HTTP/3, and its resolved Cargo
graphs differ (including Tokio 1.54.0 to 1.54.1). Both runs use JIT; AOT is not a
difference. An original-process diagnostic is now implemented, with validation
pending: existing owned
external metrics observers already carry authenticated VM endpoints in their
startup arguments, so stacks can be captured without changing application
entrypoints or listener configuration. Scope discovery to the diagnostic driver's
own descendants, verify PID identity, restrict endpoints to loopback and redact
authentication URLs. Debug RPC can perturb scheduling and never accepts timing.
The focused original-process contracts and real authenticated VM smoke pass on
`f0875fef`. Its replay reproduces the same stall after 47/360 rows, with all
3,178 tracked hashes, three lock contents, retained order/floors, native binaries,
original configuration, recorded invariance flags and cleanup independently
verified. Three router/client captures succeed, but all nine isolates return
empty execution/async-continuation stacks. Deprecated `Stack.messages` cannot
show queue state. Added bounded owned Linux thread/TCP observations and retention
of the fourth resolved input (package configuration) are pending validation.
Local tests, full verification and companion review remain blocked by another
job's preserved resource lease; all local waits expire without execution. The
initial fail-before attempt expired without executing; a reconstructed old-source
regression check remains unexecuted and must not be described as a chronological
fail-first pass. No causal runtime fix is claimed.

The [Dart-value CPU/heap profile](https://github.com/konsultaner/connectanum-dart/actions/runs/39803478045)
passes independent audit: 3,178 tracked sources/three resolved inputs unchanged,
18 snapshots, actual 64-KiB requests, sampling inside workload windows and clean
shutdown. Profiling native build flags differ from acceptance. Socket/async
frames dominate the VM inventory; snapshots do not establish a retained-buffer
leak or identify reader maps/builder guards as the next bottleneck. No collection,
allocator trimming or speculative runtime change is adopted. See
[profile research](research/2026-10-22-dart-value-profile.md).

The previous source `f316941a` retains its complete primary campaign with zero
integrity gaps and 151 numerical failures, completed protocol/encrypted shards
with 900/240 rows and 152/42 costs, and an incomplete 139/360-row payload shard.
The latter reaches the original one-MiB TLS WebSocket Dart-value deadline and
lacks final source-invariance confirmation. The [unchanged full payload replay](https://github.com/konsultaner/connectanum-dart/actions/runs/39773158466)
on historical `3c954a92` completes all 360 rows, preserving 3,170 tracked source
hashes, locks, binaries, workload order, cleanup and all 60 no-copy observations.
It captures no stall or VM stack; the previous timeout is not reproduced and
no causal production fix is established. Diagnostic wrappers cannot accept
performance. All failed and incomplete observations remain retained.

An isolated native-builder guard experiment is rejected: `vm:prefer-inline`
on both guards gives no measurable managed-allocation reduction. Its initial
in-process profile is inconclusive because profile response decoding allocates
in the workload isolate. An external controller then uses the production heap/GC
volume collector for 18 windows of 100,000 operations and six empty controls,
with matching wire/copy controls and unchanged source/library inputs. No pragma
is adopted. The allocator owner-map follow-up is now adopted as described above; resulting-source
acceptance remains pending. Evidence is under `out/flatbuffers-resume-20261022/`.

Performance acceptance remains open in #103 and draft PR #132. Ready PR #130
implements #100/#101 and still requires an independent approving review under
master protection. The ObjectBox adapter remains published as `3.0.0-beta.8`.
Standard SDK/TLS/crypto internals remain explicitly unmeasured under the approved
scope. No release or milestone completion is claimed.

## Earlier checkpoints

Resume after PR #133 (2026-10-20): the user merges the ObjectBox adapter at
master `78f2b32b`; all hosted master checks pass. Fresh `bin/test-fast` passes
on performance source `830c34cd` before integration. Copy-accounting PR #130
has all 41 checks passing on parent `63a802f7`; integration `1f46c70b` resolves
its state-document conflict with master. The performance branch now carries
that integration, preserving the published-adapter and copy-accounting records.
Analysis passes (30 existing informational lints), the rebuilt native library
passes all 32 adapter tests, and CI execution/coverage-policy/package-inventory
checks pass. Full canonical `bin/verify` passes on combined source `9e964951`,
with all 3,153 source inputs and resolved locks unchanged. An earlier lifecycle
timeout is retained as failed; three isolated reruns and a quiet full rerun pass
without changing deadlines. A paired Linux RSS follow-up reproduces three lost
HWM observations, then passes 36 collector and 46 comparator tests while
preserving the sampled peak and every parity budget. See the
[RSS research](research/2026-10-20-linux-paired-rss-endpoint.md). Full `bin/verify`
and fresh `bin/test-fast` then pass on RSS source `8104d339`, with all 3,154 inputs
and resolved locks unchanged. Exact-head PR #130 CI passes all 38 jobs; its body
records that evidence and it is ready for the required independent review. Evidence
is under `out/flatbuffers-resume-20261020/`. PR #130 implements #100/#101 and still
requires independent approval. Performance PR #132 remains draft: the prior
complete primary campaign fails 176 gates, and fresh measurements are required.
All sample floors, copy scope, workloads and parity budgets remain unchanged.

Earlier hosted blocker: the integrated 90-row Linux diagnostic completes with
all three allocation comparisons passing, but fails eleven numerical gates.
The renewed payload-size batch stops after twenty warmup rows at the one-MiB
TLS WebSocket FlatBuffers workload. A local replay completes all 36 original
warmup rows, without reproducing the Linux timeout. Four server allocation
windows retain uncertainty above the unchanged one-percent limit. The opt-in
hosted stack-capture diagnostic passes 58 focused checks, syntax validation and
a real three-codec one-MiB VM-stack smoke test; hosted capture is pending before
application changes;
see [payload-timeout research](research/2026-10-20-hosted-payload-timeout-diagnostics.md).
Complete parity and supplemental acceptance remain unproven.

Copy-gate checkpoint `f88a8f3d`: all 120 renewed production cases pass (96 E2EE,
48 native-crypto, 120 transcode/encoded-volume reconciliations). The complete
50-case short correctness inventory passes all 300 rows, including 32 declared
zero-avoidable-copy observations. All 3,157 inputs remain unchanged; native/Dart
production sources match the verified `8104d339` build. These short runs are
rejected by the unchanged timing policy. Criterion two in #103 is checked;
the other five remain open. Exact-head hosted CI for `8104d339` now passes too.
The first opt-in Linux replay completes 36 rows without a timeout or allocation
gap, on a newer runner image and Rust 1.99.1. The repository's `stable` selection
overrides the action's apparent 1.99.0 pin. Effective job-level selection and
version checks now correct that; a fail-first regression covers both jobs.
The diagnostic is extended to all 360 original rows in one process context.
Sixteen focused checks pass; complete hosted evidence and final resulting-source
canonical verification remain required before handoff. Historical failures are
not waived by the passing one-pass replay.

Canonical verification on `53c19b72` fails six existing Rust HTTP CLI lifecycle
cases at their unchanged two-second startup limit, with local models idle.
An isolated unchanged-source rerun passes. The test fixture now compiles its
identical worker once per test process and installs private executable copies;
runtime directories, sockets, environment and cleanup remain isolated. The
initial ten tests and three additional ten-test processes pass; a compiler shim
confirms one compilation per process. Full frozen `bin/verify` passes on
`c43f4e62`, with all 3,157 inputs and resolved locks unchanged. Its Rust CLI target
fails twice before the existing retry passes; those failures remain in the log.
The cache reduces setup but has not resolved the intermittent startup flake.
Companion review was blocked by another campaign's preserved resource lease;
that resource subsequently becomes available after canonical verification.

The effective-pin diagnostic on `53c19b72` completes ninety rows with stable
client/server processes, complete cleanup and an independently identical report.
All three allocation comparisons pass, while thirteen numerical gates fail on
the newer Linux runner. The full 360-row timeout replay is running separately.
Neither run changes the original acceptance policy.

The next native writer change removes temporary per-table slot/borrowed-owner
vectors. Bounded stack storage is derived from the pinned schema. Controlled
source restoration confirms segmented envelope allocations fall from fifteen
to twelve and requested bytes from 3,360 to 2,520, with original application
pointers retained. All 31 isolated FlatBuffers tests pass; 56 independently
encoded streams remain byte-identical across 25 public models and three opaque
body sizes. See [staging research](research/2026-10-20-native-flatbuffers-staging.md).
Frozen `bin/verify` passes on `40927925`, with all 3,158 source inputs and
resolved locks unchanged and no Rust CLI retry. Renewed production proofs pass
all 120 copy cases and all 300 short supplemental rows, including 32 zero-
avoidable-copy observations; source and binary hashes remain unchanged.
The complete 1,440-row hosted primary campaign is running. Full parity remains
unproven. All 38 hosted CI jobs also pass on preceding tooling source `53c19b72`.

A second reader change keeps the first four table-cache entries inline and
preserves randomized HashMap overflow, cached heights and all existing bounds.
Independent generated frames pass on the original and proposed reader at the
10,000-table limit, reject the next distinct table, and preserve shared-table
references. All 32 FlatBuffers tests pass; 56 wire streams remain identical.
Controlled restoration confirms one fewer decode allocation (seven to six)
and 140 fewer requested bytes per frame. Local parsing improves 5.2%; this is
component evidence. A slower compact-field alternative is discarded. See
[table-cache research](research/2026-10-20-native-flatbuffers-table-cache.md).
Paired diagnostics and full stack replays use separate hosted concurrency
groups. Frozen full `bin/verify` passes on `28fa8011` in 23m41s, with all
3,159 inputs and resolved locks unchanged and no Rust CLI retry. Renewed
production proofs pass all 120 copy cases and 300 short supplemental rows,
including 32 zero-avoidable-copy observations; production binary hashes match.
The current strict ninety-row diagnostic completes with stable processes and
an independently identical report: zero integrity gaps, eleven numerical gates
failing. Both optimized native construction paths pass throughput, CPU and
allocation comparisons; retained memory fails in all three cases. This is not
parity. All 38 hosted CI checks pass on both writer source `40927925` and current
reader-cache source `28fa8011` (run `39466446961`).

The complete effective-pin payload replay finishes all 360 original rows without
a stall. All 720 allocation windows independently satisfy the existing 1%
precision limit; sources, binaries, locks, inventory and cleanup are verified.
It remains a replay diagnostic; the historic timeout and four precision gaps
are not retroactively accepted. The current full supplemental campaign runs at
[39467640642](https://github.com/konsultaner/connectanum-dart/actions/runs/39467640642),
and the current full primary campaign queues at
[39468662119](https://github.com/konsultaner/connectanum-dart/actions/runs/39468662119).
The preceding writer primary campaign remains separate and retained. The current
payload-size supplemental shard completes all 360 rows with stable processes,
zero integrity findings and 32 performance-cost findings. Its report recomputes
identically; it remains diagnostic evidence rather than parity acceptance.

A private ffi-test lifetime diagnostic completes eighteen workloads across all
three codecs and construction groups. Every native allocation, handle,
external-buffer-owner and receipt counter returns to zero after each requested
collection. FlatBuffers producer allocations wait longer for GC in this probe;
there is no reproduced native-owner leak. See
[lifetime research](research/2026-10-20-native-opaque-payload-lifetimes.md).
Investigate avoiding unnecessary producer Dart-view exports while preserving the
existing reusable-payload and exported-view lifetime contracts. No new lease API
or performance acceptance is delivered by this diagnostic.

A separate manual Linux lifetime probe now stages a private source archive and
uses a compile-time source marker plus a throwing-loader negative control. Its
six positive cases cover both native construction modes at zero, 64-KiB and
one-MiB bodies; full byte validation and native-owner cleanup remain required.
Ten focused tool tests, sixteen capture tests, fourteen CI execution tests
and 87 verification-script tests pass. The first hosted probe validates its
negative control but reproduces earlier session-layer materialization in the
positive variant (`39481115738`). The extended
private session/transport variant then passes all six Linux cases with twelve
snapshots and every native counter zero before forced GC (`39481566412`).
Independent evidence also confirms source/library invariance and cleanup. A
matched unchanged-API baseline then passes in the same Linux job
(`39482582437`): its six workloads retain 410/268/1 and 290/125/1 producer
allocations before collection; the prototype retains zero in every case. Both
phases return all counters to zero after collection.
This is controlled lifetime evidence, not an RSS or performance acceptance.
Another active job holds the shared local resource lease, preventing local native verification and companion
review of this tooling; the holder and lock are preserved. Last complete
canonical verification remains the passing, frozen `28fa8011` production source.

Completed delivery (2026-10-19): the separate
[`connectanum_objectbox_adapter` 3.0.0-beta.8](https://pub.dev/packages/connectanum_objectbox_adapter/versions/3.0.0-beta.8)
is published to pub.dev. The live version API confirms publication at
13:19:06 UTC. Source is in [PR #133](https://github.com/konsultaner/connectanum-dart/pull/133),
branch `codex/objectbox-c-adapter`, based on released master `73d840c9`.
The unrelated performance worktrees and primary mutation-runner checkout are
preserved. No client/core version or native ABI changes are required.

Fresh pristine-master `bin/test-fast` passes. Full canonical `bin/verify` passes
at exit 0 on implementation head `ce1d40b5`, including Rust, Dart VM/native,
isolated consumers and Chrome/Dart2Wasm (20 existing native-only browser skips).
Analysis and all 32 adapter tests pass against actual ObjectBox 5.3.2 and the
published Connectanum beta.8 native runtime, independently with hosted Dart
dependencies and on hosted Linux/macOS/Windows. FlatBuffers/CBOR/MessagePack
receive writes use zero additional adapter body copies. Modified bytes and
expired routing handles safely fall back to counted copies. C roundtrips cover
all eight physical pointer offsets and Dart-builder four-byte wide-vector
layouts. Reads return owned snapshots; no transaction-borrowed DB view escapes.
Adapter coverage is 354/368 lines (96.196%), gated at 96.19%; old floors are
unchanged. Local native-lifetime/bounds review claims are checked against source.

The strict archive dry run has zero warnings and excludes engine binaries.
After publication, an isolated consumer with a fresh pub cache resolves the
hosted package, passes analysis and a real C write/read smoke test with zero
additional native-input adapter copies. All six downloaded library files match
the published source, and the archive digest matches pub.dev metadata. Snapshots
survive Store closure and `await`. Public evidence is in the checked ObjectBox
adapter research; detailed logs remain under `out/objectbox-adapter-evidence/`.
Two fail-first tooling fixtures (seven-package release order and missing mocked
adapter command) are fixed; their 23 and 14 tests pass. Hosted Fast Checks,
three-platform adapter tests and publish dry run pass on `ce1d40b5`; broader CI
is still running without a known failure at this checkpoint. Protected-master
review/merge remains separate from the explicitly authorized first publication.
No FlatBuffers performance gate or unfinished milestone issue is waived.

Issues [#95](https://github.com/konsultaner/connectanum-dart/issues/95), [#96](https://github.com/konsultaner/connectanum-dart/issues/96), [#97](https://github.com/konsultaner/connectanum-dart/issues/97), [#98](https://github.com/konsultaner/connectanum-dart/issues/98) and [#99](https://github.com/konsultaner/connectanum-dart/issues/99) are complete. Issues #102 and #104 are also closed; #100, #101 and #103 remain open. PR [#105](https://github.com/konsultaner/connectanum-dart/pull/105) is merged at `0e585405`.

Issues [#95](https://github.com/konsultaner/connectanum-dart/issues/95), [#96](https://github.com/konsultaner/connectanum-dart/issues/96), [#97](https://github.com/konsultaner/connectanum-dart/issues/97), [#98](https://github.com/konsultaner/connectanum-dart/issues/98) and [#99](https://github.com/konsultaner/connectanum-dart/issues/99) are complete. Issue [#104](https://github.com/konsultaner/connectanum-dart/issues/104) is complete. Issue [#102](https://github.com/konsultaner/connectanum-dart/issues/102) is complete. Issues #100, #101 and #103 remain open. PR [#105](https://github.com/konsultaner/connectanum-dart/pull/105) is merged at `0e585405`.


Current verification follow-up (2026-10-19): `5600f1f7` passes every hosted CI
job and the full local fast suite. The complete 816-mutation router gate passes
95.2087% without exclusions. `1a20561d` repairs standard-SDK GC ring loss: the
renewed 30-row 1 MiB TLS WebSocket run completes with all 60 client/server
allocation windows measured and no timeout. Its CI stops at one unformatted test
line before coverage tests. `8f6e753a` corrects it; all 736 files pass formatting.
The first full `540ab37f` verification reproduces a synthetic VM fixture missing
`clearVMTimeline`; that superseded run is failed, not a pass. The fixture now
handles the RPC, and a new regression proves clear failure aborts measurement.
All 221 collector/worker lifecycle tests pass, with causal source restoration.
Fresh full verification and production proofs remain required. The prior 85
focused Dart cases, analysis and 139 driver tests pass. See high-GC research.

The complete b8 primary campaign finishes all 1,440 rows across 48 cases with
complete allocation observations. Independent archive/source/binary/policy/
config/lock/scenario and raw/split hashes match, and the unchanged evaluator
reproduces its report exactly. It fails 176 performance gates. Supplemental
protocol completes 900 rows with 152 performance findings; encrypted progressive
completes 240 rows with 44 performance findings and three missing measured RSS
endpoints. Payload sizes stops at 192/360 rows on the recorded 1 MiB timeout.
No complete supplemental acceptance or parity is claimed. No budget, sample
floor, workload, owned-copy requirement or dependency scope is waived. The b8
frozen full verify, 300 short rows, 120 accounting cases, 36 progressive
combinations and 190 five-platform consumers remain valid for that source.
PR #132 remains draft for unmet parity; #130 still needs independent review.

Current native envelope candidate (2026-10-17): source `b2fb8b63` passes
frozen full `bin/verify`, 300 short supplemental rows, 120 accounting cases and
36 progressive combinations with all 3,124 inputs unchanged. Its strict Linux
90-row diagnostic still fails parity (CPU 1.0099 / 1.0057 / 1.0038), with all
allocation comparisons passing and additional throughput/latency/GC/RSS failures.
A fail-first regression now motivates keeping a single borrowed application's
vector header in the native envelope, removing its separate header allocation.
All 386 core, 26 segmented-forwarding FFI and 26 FlatBuffers FFI tests pass,
including generated verification, original owners and multi-vector fallback.
Fresh production copy/volume and performance evidence is pending; no acceptance
budget, workload, measurement floor or dependency scope changes. See the checked
terminal-vector research. PR #132 remains draft for unmet parity; #130 still
requires independent review.

Current fully represented CALL candidate: a fresh audited Linux profile on
`65833214` still captures 24 inclusive native-metadata retention ticks (diagnostic
only). A limited complete-grammar match now avoids the custom loader and retained
history for two PPT strings exactly represented by fresh CALL options, with all
other fields null. Unknown/null/default/tagged/Unicode or other control shapes
keep their prior path. All 3,971 binding/metadata cases, both production consumers,
nonminimal decoder comparisons and source-restored fail-first checks pass;
analysis is clean. See the checked fully represented CALL research. Fresh
performance measurements and final full verification are pending.

The preceding `65833214` whole `bin/test-tooling` and hosted Fast Checks pass
with all 3,123 inputs unchanged. Its nonfinal remaining CI jobs were cancelled
to free the profiler runner; no full CI pass is claimed for it. The earlier
`7388e666` hosted CI now passes every job, alongside its frozen full local verify
and five-platform consumers. The `b4e2b4ea` strict 90-row diagnostic has complete
allocation/RSS observations but fails CPU ratios 1.0122 / 1.0024 / 1.0045 and
other gates. All three allocation comparisons pass. No budget is changed and no
primary/supplemental performance acceptance or milestone closure is claimed.

The complete local tooling run on `10d21c49` also reproduces a stale exact
router-test-list assertion in the mutation-runner tests. Its expected list now
includes the new router regression, while the client list remains exact. All
93 runner checks (one existing skip) and the remaining five tooling scripts pass.
The full tooling prefix had passed before that assertion. Fresh whole-tooling
and hosted checks are required on the repaired fixture; no gate is loosened.

Serializer mutation inventory repair: the hosted `b4e2b4ea` Fast Checks failure
reproduces five omissions of the new core metadata test. All four CBOR/MessagePack
VM/browser support inventories and the shared suite now include it; the router
binding target also runs its new native regression file. All 87 tooling checks
and all eight new cases through both VM and JavaScript wrappers pass. No test
exclusion, inventory equality or mutation threshold is relaxed. The preceding
source completes 300 short rows, 120 accounting cases and 36 progressive cases
with all 3,123 inputs unchanged. Its redundant full verification is intentionally
stopped for the known tooling failure; it is not a pass. Application code is
unchanged by this inventory repair. Run resulting-source tooling/CI first, use
the strict Linux diagnostic to choose the next performance step, and complete
fresh full verification before handoff/acceptance.

Deferred validation repair: a bounded 10,240-value tag diagnostic finds two
well-formed date-tag values rejected by the materializer. A fail-first native
retention test confirms rejection moved to resend. Tagged dictionaries now
retain eager semantic decoding; tag-free dictionaries keep deferred snapshots.
Tags nested in metadata are detected, while byte-string contents stay opaque.
All 312 focused VM and 160 Chrome/WASM cases pass; focused analysis is clean.
The superseded `a353ce56` proof/diagnostic attempts are stopped and preserved;
no resulting-source full verification or parity is claimed for them.

Current deferred-metadata candidate (2026-10-16): the hosted Linux profile
passes source/PID/window/report/map audits, with 46 inclusive Dart retention
ticks (not a CPU-cost or parity result). Native perf Dart addresses remain
unresolved. Three fail-first cases reproduce 16 KiB of eager metadata clones
for a 4 KiB binary extension. Native CALL/PUBLISH/YIELD now validate immediately
and defer original decode/projection/snapshots, retaining immutable native bytes
and payload-free original control fields. All 129 focused
metadata cases, five Chrome/WASM cases and 3,877 binding/fragment regressions
pass, including all 32 native flag combinations. Original eager
semantics, unknown/default/null fields, edits before resend and application
laziness are covered. Fresh full/hosted/accounting/performance proof is pending.

Eligibility source `7388e666` now passes frozen full `bin/verify` with all 3,119
inputs unchanged, all 190 production consumers on five platforms, 300 short
supplemental rows, 120 accounting cases and 36 progressive combinations. The
preceding `4738c452` hosted CI is fully green. Resulting-head hosted CI remains
in progress without a known failure. No parity or milestone closure is claimed.

CPU diagnosis follow-up: Linux native profiles now request standard Dart router
JIT maps, retain PID/hash attribution and separate router/client perf reports.
Nine tool tests cover startup/probe configuration and missing/corrupt/foreign
maps; generated Dart analysis has no errors. Profiles remain diagnostic and
cannot waive canonical parity. Hosted validation is pending. Eager native
FlatBuffers dictionary retention (decode/project/snapshot) is a concrete next
cost to profile before changing metadata semantics.

Current native eligibility repair (2026-10-16): marker-only PPT borrowing can
lose the scheme when raw null PPT fields become indistinguishable from absence
in typed Dart options. Rust and real anonymous/ticket CBOR wire reproducers fail
before the repair. Capability version 2 now requires a positive per-message
native query on the held alias at lending and forwarding; ambiguous metadata
uses the existing copying path. Older marker-only bindings reject version 2 as
well. All 69 lifetime tests (eight new native binding cases), 110 worker tests,
22 native predicate combinations plus invalid/non-CALL/released aliases and the
two production consumers pass. Five native-library variants and older Dart
bindings have live compatibility coverage. See the checked native eligibility
research. Final resulting-source full/hosted verification is still required.

The preceding `4738c452` source passes frozen full `bin/verify` with all 3,118
inputs unchanged, all 190 production consumers across five platforms, 300 short
supplemental rows, 120 accounting cases and 36 progressive combinations. The
copy-boundary comparison across nine payload-size cases removes the three large
router copies for all binary codecs; it does not establish speed improvement.
The strict Linux diagnostic validates 90 rows, 180 allocation observations and
all RSS endpoints, but fails parity: CPU ratios 1.0290 / 1.0086 / 0.9974, with
additional latency/allocation/GC/RSS failures. All gates remain unchanged. Its
hosted CI is still completing without a known failure. No milestone closure or
performance acceptance is claimed for that preceding, marker-only source.

Current internal PPT candidate (2026-10-16): a fail-first regression observes
an argument-byte array crossing the internal CALL handoff for unchanged plaintext
PPT. The candidate allows retained native handoff for exact original body identity
and immutable original PPT headers, with a cached optional native version marker.
Missing/unknown markers, changed/removed input or reply headers, replacements,
custom details, active progress, encryption and reserved `wamp` payloads fall back.
Both removed-header guards have independent fail-first/restoration proofs. All
110 worker tests, 18 new-library live cases, 18 old-library fallback cases and the
two production consumers (empty/3/65,536-byte opaque internal bodies, anonymous
and ticket) pass. Final unchanged replies after progress may reuse their loan.
Copied-but-equal reply bytes also fall back. The local companion review found
and prompted the stripped-input-header guard; a final bounded GLM judgment finds
no guard blocker. Baseline `bin/test-fast` passes. Live accounting and timing for
this candidate are still pending.

Baseline verification correction: hosted `895ff3d9` CI is now fully green, as are
its five native artifact platforms. Local `ce897f98` full verification hit native
receive-worker exits while a separate `bin/test-fast` overlapped the full suite.
That failed attempt is retained with all 3,118 inputs unchanged; no cause or pass
is claimed before a serial rerun. The three profiler-path assertions are fixed.
The `4b840309` strict Linux diagnostic completes 90 rows/180 valid allocation
observations but fails CPU parity at 1.0250 / 1.0131 / 1.0129 plus other gates.
Three lifetime-RSS observations (one warmup, two measured) remain unavailable;
reading final fields together does not remove that historical-peak contradiction.
All unavailable evidence still blocks acceptance. No gate or budget is changed.

Verified prefix checkpoint (2026-10-16): source `792cd99d` passes full frozen
`bin/verify` with all 3,115 inputs unchanged, all 38 hosted CI jobs and 180 audited
production consumers across five platforms, with zero skips and independently
matched archive/library/manifest/log hashes. Renewed 300 short supplemental rows,
120 accounting cases and 36 progressive codec combinations reconcile every owned
copy and encoded-volume component. All 36 Linux RawSocket pointer probes pass.
The strict Linux diagnostic validates all 90 rows / 180 allocation observations
and every RSS endpoint, but still fails parity: CPU ratios 1.0057 / 1.0185 /
1.0229, with additional throughput/latency/GC/RSS failures. No budget is waived.
CPU profiling succeeds on a second unchanged-source attempt; the first attempt's
CBOR `perf record` failure and partial data remain retained explicitly.

Current cancellation repair (2026-10-16): pre-change `bin/test-fast` passes on
`c15f2185`; the corrected native mutation inventory passes all 93 tool tests and
hosted Fast Checks. A real workload-sequence probe also reproduces the rejected
router send with CBOR. A temporary, restored diagnostic captures the rejected
FlatBuffers frame: `ERROR(INVOCATION, 52, {}, wamp.error.no_such_invocation)` after
callee close. WAMP requires late non-waiting cancellation responses to be ignored.
The repair discards removed-invocation responses and cancellation races during
completion/progressive update, without retaining cancelled-call state. Nine
fail-first assertions now pass, alongside two existing store-error controls;
all 109 session tests pass with default and enabled native forwarding. Analysis
passes with the same 30 existing infos. The rejected-volume gate is unchanged.
See [the checked research](research/2026-10-16-wamp-late-cancellation-responses.md).
Renewed 300 short supplemental rows, 120 independent accounting cases and
36 progressive combinations pass on `895ff3d9`. Its full frozen `bin/verify`
passes with all 3,116 inputs unchanged. All 190 production consumers across
five platforms pass with zero skips and independently matched library/archive/
manifest/log hashes. macOS Intel first failed SDK download DNS resolution;
its unchanged-source retry passes, with the original failure retained. Hosted
CI passes all 38 jobs. The strict `c15f2185` Linux diagnostic completes all 90 rows and
validates 180 allocation observations, but CPU ratios 1.0867 / 1.0254 / 1.0216
and other throughput/latency/GC/RSS gates fail. One lifetime-RSS observation is
explicitly unavailable. No performance acceptance or milestone closure is claimed.

CPU profiling now selects each of the three canonical diagnostic construction
paths explicitly; the default remains native/native-buffer. Five mocked
orchestration tests check startup/probe/audit attribution, unsupported selections
and independent targets. The actual Dart SDK verifies the six probe argument
positions; generated-probe analysis has no errors and workflow actionlint passes.
Per-request JSON and selected-case provenance are retained. The `8cb54d20`
Linux Dart-values profile succeeds: all 3,117 source hashes, the native binary,
13 actual request files, process IDs and three real sampling windows are
independently checked. These profiles never supply primary acceptance.

Full verification of `4b840309` reproduced three profiler-test failures on
macOS: the production launcher resolves output paths but the mocked assertion
expected an unresolved `/var` path. The assertion now checks the same canonical
path; all five profiler tests pass. Full verification is being rerun.

The RSS endpoint repair reads final VmRSS and the first VmHWM from one procfs
snapshot. All 32 metrics tests, including existing strict negative controls,
pass and changed-file analysis is clean. Missing/contradictory values still
block acceptance; fresh Linux observation is pending. See the paired Linux RSS
research document. Router internal PPT handoff remains the next performance
investigation: the existing Dart guards reject PPT even though the native
result-from-call encoder can preserve opaque PPT headers and body slices.
Measured router copies are about 128 KiB in Dart plus 64 KiB at native submission
per 64 KiB RPC; no-copy forwarding requires careful ownership/metadata guards.

Active native candidate (2026-10-16): a fail-first typed-send regression observes
172 native control-string copy bytes. The private canonical Call/Publish path now
builds an aligned native prefix with the vector length at its tail and submits it
with the existing frozen payload through the existing owned-segment ABI. It avoids
native reparse/composition and extra frame wrappers. Public supplied-frame checks,
64 MiB full-frame limits, profile/connection guards and the old-ABI frame fallback
remain. No native ABI, schema, payload copy, benchmark inventory or budget changes.

All 76 focused native/ownership/transport cases pass in canonical separate
processes, plus 36 complete-wire shape cases and 14 missing-optional-ABI fixture
cases. The counter test uses an isolated child VM because native counters are
process-wide. Parallel native-file runs reproduce shared-runtime teardown
interference; their failures are retained, not used as accepted verification.
The capability fixture changes only an optional dynamic export in a test copy,
not a historical binary or production artifact. A balanced local preparation-only
probe measures 8.24 to 4.18 us; it excludes send/network/session work and is not
macro parity. Resulting-source full verification, renewed live accounting, hosted
CI and strict timing remain required. Production consumers now require 14 first
profile cases: all 190 pass on `4dab389f` across the five packaged platforms,
with zero skips and independently matched log/archive/manifest/library hashes.
Resulting-cancellation-source evidence remains pending.

RawSocket prefix candidate (2026-10-16): frozen `bin/test-fast` passes on
`2524d89b` with all 3,115 inputs unchanged. A focused fail-first regression proves
large FlatBuffers/CBOR/MessagePack frames submit their small fragments separately.
The candidate copies a bounded leading prefix (at most 4 KiB including the actual
four/five-byte header), records every performed header/coalescing copy and retains
all remaining fragments with their owner anchors. All 93 socket tests pass,
including exact wire bytes, full and bounded native bodies, cap boundaries,
independent prefix storage and failed-submission accounting. Review claims were
checked against source and these regressions. No benchmark verification, policy
or native transport changes. Resulting-source full verification, Linux pointer
probes, renewed live accounting and strict parity remain required.

Current verification (2026-10-16): source `edf3feda` passes frozen full
`bin/verify` with all 3,113 inputs unchanged, renewed 120-case accounting and
36 progressive codec combinations with independent copy/volume recomputation,
and 180 audited five-platform production consumers with zero skips. Hosted CI
passes all 38 jobs on that source. Its strict
90-row Linux diagnostic validates all 180 allocation observations and every RSS
endpoint. Allocation and GC gates pass for all three construction modes. CPU
still fails at 1.03886 / 1.03192 / 1.02334; several latency/RSS/throughput gates
also fail. Actual parity and full campaigns remain blockers; no budget is waived.

The active CI change keeps all 50 supplemental cases / 1,500 rows but distributes
complete cases over three controlled Linux jobs (30 protocol, 12 size, 8 encrypted
progressive cases). Recorded two-minute workloads make the six-hour hosted job
limit a real scheduling risk. Every case retains all codecs, three warmups,
seven measurements and existing floors/guards. A strict raw-evidence merger
requires all batches and records per-batch hardware/PIDs/attempts without pooling
absolute costs. Primary acceptance remains separate. All 78 focused cases, the complete
`bin/test-tooling` chain and actionlint workflow checks pass. Resulting-source
full verification, live batch proof and hosted publication remain pending.

Live batching proof on `8b92306c` completes all 50 cases / 300 short rows,
with stable processes in each batch and all 3,115 inputs unchanged. Independent
checks reconcile 96 E2EE, 60 active transcode, 72 native-crypto and 300 encoded
WAMP-volume observations; all 32 eligible rows retain zero avoidable payload
copies. The strict policy rejects these short runs as required. A local Dart-values
CPU profile passes source/library/window audits; native CPU and interference
observation remain unmeasured on macOS. Neither result establishes parity.

Hosted Fast Checks on `8b92306c` reproduces a synthetic merger fixture depending
on an ignored Cargo lockfile. A clean-archive regression confirms the failure;
synthetic fixture locks now replace local files, and all ten merger tests pass
in a clean archive with no generated locks. Production hash verification is
unchanged. Resulting-source CI and full local verification remain required.

Native composition candidate (2026-10-16): frozen `bin/test-fast` passes on
`7452ab61` with all 3,113 inputs unchanged. That checkpoint also passes renewed
120-case copy accounting, 36 progressive codec combinations and 180 independently
audited production consumers across five platforms, with zero skips. Its Linux
CPU diagnostic passes source/library/window audits; attribution shows native
composition rebuilding already validated metadata.

The candidate retains the full existing parser, reuses its validated field tree,
changes only application slots and validates every supplied container. Original
encoded metadata survives byte-for-byte. The regression fails first on reordered
metadata keys. All 384 core / 295 FFI library cases, 71 Dart native/frame/network
cases, 33/42 independent fixtures, all 25 public message models, generated bindings
and independent live RawSocket/WebSocket peers pass. Every public model also
rejects malformed/mixed/deep supplied containers and unsupported payload slots.
A balanced local component probe improves composition from 4.50 to 3.77 us;
this is not macro parity. Resulting-source full verification, renewed copy totals,
Linux timing and fresh native consumers remain required. No public ABI, schema,
primary inventory or performance budget changes.

Verified checkpoint (2026-10-16): full frozen `bin/verify` passes on
`87b89830` with HEAD and all 3,113 inputs unchanged, including 4,984 core and
2,865 client Wasm cases (20 existing native-only skips). Hosted CI on `84fe0f29`
passes all 38 jobs. Current hosted CI remains pending.

The production native dry run on `87b89830` builds all five artifacts and passes
all 12 first-profile consumer cases on every platform, but its verifier still
expects 10. All five actual logs reproduce the count rejection and validate with
12; the declaration now requires 12, retaining every omitted/skipped/unfinished
failure guard and reporting expected/observed counts. Focused verifier checks
pass. Replacement five-platform dry-run evidence remains required.

The packed-reply Linux diagnostic on `01300605` completes 90 rows / 180 valid
allocation observations. Allocation ratios now pass: 0.84549 / 0.89153 / 0.81924.
CPU still fails: 1.03383 / 1.03914 / 1.03297; some throughput, latency, GC and
sampled RSS gates also fail. Two lifetime RSS observations are unavailable,
both in warmup; they remain explicit. Sampled RSS gates use actual
available readings and fail. No numeric gate is waived. Fresh CPU attribution,
actual parity and full campaign acceptance remain required.

Progressive-result coverage (2026-10-16): the supplemental inventory is now
version `flatbuffers_extensions_v2`, with 50 cases (1,500 full campaign rows).
The four progressive RPC cases retain three CALL chunks and now validate two
progressive RESULTs plus a terminal result. Eight added encrypted cases exercise
both ciphers, Dart/native clients and mixed CBOR peers. A frozen-input short live
proof passes all 36 codec combinations; independent arithmetic reconciles 24 E2EE,
16 active transcode, 12 native-crypto paths and every encoded WAMP-volume total.
All 92 focused Dart and 65 comparison/campaign cases pass; analysis is clean.
The preceding packed-reply commit `01300605` separately passes all 120 renewed
copy cases with 3,113 unchanged inputs. New-source full verification, hosted CI,
full campaigns and actual primary parity remain required. No budget changes.

Current packed-reply correction (2026-10-16): full frozen `bin/verify` on
`84fe0f29` passes with all 3,113 inputs unchanged; its renewed 120 live accounting
cases independently reconcile Connectanum E2EE, transcode and encoded WAMP volume
components. Hosted CI currently has 36 passing jobs and VM coverage still running.
The `f2b577ff` 90-row Linux diagnostic still fails parity: CPU ratios
1.08631 / 1.07976 / 1.07664 and native-buffer allocation 1.03508. Every allocation
observation validates; one warmup lifetime RSS endpoint is unavailable. Measured
endpoints remain valid. No gate is relaxed.

An actual typed RPC probe finds internal replies losing their packed-payload
classification because PPT metadata was omitted from payload restoration. The
candidate passes the existing four metadata fields to that restoration helper;
a fresh probe preserves the exact 65,576-byte packed payload without materialized
arguments. Progressive internal replies now consume their reply stream through
the terminal result, retaining native loans until completion or cancellation.
All 114 focused router regressions, analysis and 154 mutation proofs pass. Local
companion suggestions were checked against source and resource-lifetime tests.
Resulting-source full verification, renewed accounting and Linux parity remain
required. Existing progressive benchmark cases measure CALL input chunks; explicit
progressive-result cost coverage remains required before supplemental acceptance.
No issue, milestone or release is closed.

Encoded-volume CI repair (2026-10-16): source `1b751b72` passes all 120
live copy/encoded-volume cases, with 3,108 unchanged inputs and independent
component recomputation. Its full local verification and hosted Fast Checks
reproduce 16 synthetic fixture failures: the older fixture producer emitted
unmeasured encoded-volume observations. The producer now supplies explicit
synthetic disjoint boundary observations through the real delta/merge code, and
an independent Python test checks and corrupts every resulting combination.
Current-source verification is pending; all performance budgets remain unchanged.
The preceding `f2dc00f0` CI run passes every hosted job.

Encoded-volume follow-up (2026-10-16): the `f2dc00f0` checkpoint passes frozen
full `bin/verify`, with HEAD and all 3,105 inputs unchanged, all 120 audited live
copy cases and 170 five-platform native consumers. Its 90-row Linux diagnostic
still fails CPU (1.094–1.118) and native-buffer allocation (1.05324), among other
gates. All 180 allocation observations validate; two warmup lifetime RSS
endpoints remain unavailable and are retained explicitly. Measured endpoints
are valid. The quiet CPU profile also retains all 3,105 inputs unchanged.

The active change repairs `wire_bytes`, which actually contained application
bytes, and adds separate actual serialized WAMP message-volume accounting at
Dart/native send acceptance. No volume counter enters a copy total; optional
native symbols preserve the existing 48-byte ABI. All budgets and inventories
stay unchanged. Focused checks pass: 825 ownership/volume cases, 37 comparison
cases, 85 VM transport cases, 122 native ABI/provider/runtime cases, both browser
compilers and the older-native-library fallback. All 154 mutation proofs validate.
Resulting-source full verification and live encoded-volume proof remain pending.
Extension diagnostics and credible primary parity remain required; no issue,
milestone or release is closed.
See [encoded-volume evidence](research/2026-10-16-encoded-wamp-volume.md).

Current candidate (2026-10-16): a pinned, licensed SDK-derived VM builder
bulk-copies typed byte vectors through the standard Builder API. Web retains the
SDK backend after a read-only alias regression. Bool staging is eliminated and
owned UTF-8 staging is observed as framing copies. All outgoing checks remain.
Checks pass: 3,386 serializer VM / 3,391 JS / 3,381 Wasm, 30 native-owner cases,
analysis, all 154 mutation proofs, generated bindings, and independent 33/42
fixture plus 25-message interoperability. Component bulk-writer time is about
1% of the SDK byte loop; no macro parity is claimed. Final full verification,
renewed live accounting, hosted consumers and the Linux comparison are pending.
Actual encoded-size measurement and extension diagnostics remain blockers.
See [bulk writer evidence](research/2026-10-16-flatbuffers-bulk-byte-writer.md).

Current checkpoint (2026-10-16): `5dda2ecd` passes `bin/test-fast`, focused
VM/JS/Wasm ownership checks, all 120 renewed copy cases with 3,099 unchanged
inputs, and 170 audited five-platform production consumers with zero skips.
Its 90-row Linux diagnostic improves CPU to 1.1590 / 1.1782 / 1.1633, but
native-buffer allocation is still 1.0634 and other numerical gates fail. One
baseline lifetime RSS endpoint is unavailable. Bounded rereads now retain every
actual observation; all 30 focused Dart and 32 Rust library / 139 driver tests
pass. Persistent or missing endpoints remain unavailable; no budget is changed.

Performance and reporting remain blockers: investigate repeated metadata string
allocations, measure actual encoded WAMP volume separately from logical
application bytes, and complete the declared extension diagnostics. The 48-case
primary campaign must wait for credible diagnostic parity. Full resulting-source
verification remains required; no issue or milestone is closed and no release
is made.

Concrete typed-word candidate (2026-10-16): the preceding source `25862a53`
passes frozen full `bin/verify` with all 3,098 inputs and HEAD unchanged. Its
90-row Linux diagnostic has no RSS/duration measurement failures but still
fails CPU (1.32–1.39) and native-buffer allocation (1.0838), among other gates.
A concrete `Uint32List.view` writer matches the SDK wire/allocation layout in
38,400 prototype cases and reduces 64 KiB component writer time to 0.307–0.317
of the SDK path. Integrated VM serializer (3,378) and native ownership (30)
cases pass; browser, final-source verification and end-to-end measurements are
pending. This differs from the rejected generic word adapter. Native source188
artifact retry now passes all five platforms, with 170 independently audited
consumer cases and zero skips. No parity or release is claimed.
See [concrete writer evidence](research/2026-10-16-flatbuffers-concrete-word-writer.md).

RSS/duration repair ready (2026-10-16): fresh Linux lifetime RSS is now read
after the final sampled live boundary; missing or contradictory endpoints stay
null through Dart/Rust reports while other resource observations are retained.
The scheduler now performs real operations until actual sample coverage reaches
the unchanged minimum; the fail-first logging-delay case reproduces 2.578 ms
versus a required 30 ms. All 139 Rust driver, 31 library/artifact, 93 focused
Dart, 35 comparator and 87 inventory-script checks pass; analysis and all 154
mutation proofs pass. Resulting-source full verification is pending.

The `188d33cd` Linux diagnostic completes but still fails CPU (1.24–1.34)
and native-buffer allocation (1.0637), among other gates. A quiet CPU profile
without allocation tracing identifies SDK byte-vector writing as a major cost.
All 3,097 tracked/intended inputs stay unchanged during profiling. The next
optimization targets that measured bottleneck; no parity is claimed. Native
artifact source188 fails only Linux x64 manifest attestation due to a Sigstore
network timeout; its failed job is retried. PR #130 source63 remains fully green.
See [boundary repair evidence](research/2026-10-16-linux-rss-duration-boundaries.md).

Verification/measurement repair (2026-10-16): `188d33cd` passes all
120 renewed HTTP copy cases with all 3,097 inputs unchanged. Its local diagnostic
still fails: throughput 0.9827 / 1.0156 / 0.9838; allocation
0.9758 / 1.0884 / 0.9853. Every observation remains retained. Frozen full
verification fails five inventory assertions because the new metadata encoding
test was absent from four serializer mutation support lists and their shared
wrapper. The test is now added everywhere, preserving every prior source/test
and floor; all 87 verification-script checks and 154 mutation proofs pass.
Resulting-source full verification remains required.

The preceding `249e0c8a` Linux 90-row/10-second diagnostic completes with full
resource observations but fails all CPU gates (1.30–1.41), several resource and
latency gates, stale child max-RSS versus later live-RSS checks, and one sample
window just below 10 seconds. No gate is loosened. Current-head Linux diagnostic
is running. Obsolete full campaigns are cancelled with artifacts retained;
a fresh primary must follow measurement repairs and credible diagnostic parity.
The next work repairs RSS/time boundary capture, then profiles actual CPU cost.

Latest performance candidate (2026-10-16): source `249e0c8a` passes the
renewed 120-case copy matrix with 3,097 inputs unchanged. The short diagnostic
improves native-buffer throughput to 1.0170 and p95/p99 to 0.9625 / 0.9927,
but allocation still fails at 1.1503; managed/pre-encoded throughput is below
parity. Component probes show native construction is already cheaper than
MessagePack. Sharing immutable membership sets in metadata projection reduces
profile allocation from about 22,000 to 8,600 bytes while retaining every check.
All 3,375 serializer VM tests, analysis and unchanged mutation preflight pass.
Browser, whole-source and end-to-end verification are pending for that candidate.

Current checkpoint (2026-10-16): `d12196ce` passes renewed 120-case owned
E2EE/transcode proof with 3,096 inputs unchanged and all 170 audited five-platform
production consumer checks. Its 90-row diagnostic still fails (throughput
0.9518 / 0.9887 / 0.9740; allocation 1.0384 / 1.1694 / 1.0535), with every raw
allocation observation valid. Full verification finds one existing FastCGI
stdout-limit fixture race; a narrow test-only reset allowance fixes all 29
focused cases while preserving HTTP status/reason/event/closure assertions.
The next candidate removes CBOR wrapper/hash/UTF-8 staging for small ASCII
scalar metadata while preserving exact wire bytes and all fallback/budget rules.
A component probe drops allocation from about 8,900 to 650 bytes per dictionary.
Whole-source verification and end-to-end performance remain pending. A separate
hosted 90-row Linux diagnostic retains the primary durations/samples/repetitions;
it never establishes primary acceptance. #103 remains open; no release is made.

Current performance work (2026-10-16): all hosted CI checks pass at
`63a802f7`, including the complete VM coverage policy with no findings and
benchmark coverage 98.74% (3,846/3,895). Frozen local `bin/verify`, package
publishing dry run and five-platform production consumers (170 cases, zero
skips, independently audited hashes) also pass. PR #130 contains this reviewed
accounting/coverage checkpoint.

Experimental `1785387e` passes `bin/test-fast`, 120 HTTP copy checks with all
3,096 inputs unchanged, and 170 audited production consumer cases. Its 90-row
diagnostic fails the unchanged budgets: throughput 0.9347 / 0.9875 / 0.9478 and
allocation 1.1348 / 1.1691 / 1.0589. All 180 allocation reports validate. Large
read-only word writes regress, so the selected candidate restores the standard
SDK byte writer while retaining the strict single-pass scalar metadata parser.

The selected candidate avoids retained Call/Publish dictionary snapshots only
in transient native outgoing profile checks, after the same wire/model/projection
validation. Public deserialization and negotiation metadata remain unchanged.
Fragmented typed FlatBuffers PPT arguments retain a canonical CBOR prefix and
the original byte body, preserving the existing args wire representation and
kwargs/crypto/metadata-authority rules. Explicit contiguous access accounts for
its coalescing copy. Regression checks pass: 3,370 VM serializer tests, 3,376
JavaScript tests, 3,366 Wasm tests and 54 serial native profile/network tests.
Independent upstream/extended readers accept 33/42 fixtures, bidirectional
Python/Dart/Rust Call conformance passes, and contiguous/segmented output for all
25 public messages agrees. The bounded local judge finds no confirmed defect;
all requested prefix boundaries are covered against an independent CBOR encoder.
Mutation preflight and analysis pass. Current-source full verification, renewed
120-case copy proof and paired timing remain pending; no parity acceptance or
release is claimed. See [vector/metadata research](research/2026-10-16-flatbuffers-vector-metadata-allocation.md).

## Earlier checkpoints

Coverage repair in progress (2026-10-16): the first full benchmark VM run
passes all 2,657 tests but measures 93.81%, below the unchanged 98% gate.
The new external metrics observer runs outside the instrumented test process.
Direct real-VM collector tests and deterministic observer-protocol/process-failure
tests pass all 72 focused checks; the fresh full benchmark suite passes all
2,692 tests. Fresh coverage calculation and hosted CI remain pending; earlier full verification is historical evidence for `24f4276b`.
The latest scalar-metadata diagnostic still fails parity: throughput ratios are
0.9602 / 0.9973 / 0.9679 and allocation ratios 1.1364 / 1.1777 / 1.0556 for
managed values / native buffers / pre-encoded spans. No acceptance gate is waived.

Browser CI repair (2026-10-16): hosted `24f4276b` passes 4,852 browser
cases and fails two new reference-builder tests. Raw SDK builders call uint64
accessors unsupported by dart2js; production uses the portable WAMP builder.
Both failures reproduce locally. The byte-vector spy now supplies only relevant
fields and the wire comparison uses the portable builder. All 155 focused JS
cases pass without skips or threshold changes. Resulting-head CI is pending.

Verified allocation checkpoint (2026-10-16): full frozen `bin/verify` passes at
`24f4276b` with HEAD and all 3,092 tracked/intended-new inputs unchanged. This
includes Rust, VM/live, packaging, core Chrome/Wasm and 2,865 client browser cases
with twenty declared native-only skips. Prior copy-accounting source `bb549a4c`
also passes every hosted CI check and all five production consumer platforms
(170 cases, zero skips, audited hashes). New-head CI/native dry run is running.

The next measured bottleneck is repeated FlatBuffers metadata normalization.
A validated scalar-map shortcut preserves fallback semantics for complex values;
all 3,358 serializer cases pass. Fifty-five differential/reference vectors and
all truncation prefixes pass on VM and Chrome/Wasm. Two independently checked
metadata-allocation probe pairs drop from about 13,900 to 3,000 managed bytes per
decode; this is allocation-only diagnostic evidence, not primary acceptance.
A fail-first managed-fixture case also exposes an unobserved byte-vector build;
the benchmark now uses the public observed builder. All 31 fixture cases preserve
wire bytes/capacity and pass. New end-to-end timing and final verification remain
pending, and #103 stays open with unchanged budgets.

Allocation/performance follow-up (2026-10-16): stock-SDK heap/GC volume now
retains raw proof and runs its observers outside both measured PIDs. Independent
Python recomputation rejects the legacy live-heap census and forged totals;
35 comparison cases and the live 24-row/48-process allocation matrix pass.
The Rust driver now preserves the raw metadata (fail-first round-trip regression,
17 driver cases pass). GC crossing one measured snapshot is reproduced; bounded
three-attempt boundary retries retain the entire original workload and collection
window. All 100 focused allocation/GC/wire/process cases pass.

Typed input, completed CBOR encoder/decoder buffers and PPT singleton binary
views avoid extra copies. Metadata-only native PPT views now respect dictionary
authority; all 1,916 binding cases pass. All 3,270 serializer/owned-copy cases
pass before the small-frame reservation threshold refinement. Large-frame
reservation reproduces oversized backing allocation and matches standard wire
bytes. The next short diagnostic reaches 1.003 native-buffer throughput, but allocation
ratios remain 1.10–1.23 and latency still fails. All 180 allocation observations
validate after the boundary repair. The earlier diagnostic has one
allocation report correctly remains unmeasured at the ambiguous GC boundary.
No budget or inventory is relaxed. Current-source full verification, new paired
timing and hosted acceptance remain pending. See
[allocation method](research/2026-10-15-dart-allocation-volume-research.md).

Owned pipeline accounting follow-up (2026-10-15): E2EE totals now combine eight
independently observed owned components; mixed transcode totals expose actual
router serializer/dispatch buffers separately from transport. Strict producer and
Python validation reject stale native coverage, rewound counters and forged
subtotals. The unchanged 48-byte codec layout has a separate optional coverage
scalar; the prior production library safely yields unavailable coverage. Focused
717 benchmark, 86 client and 35 router cases pass. All 120 full HTTP cases
pass copy validation. Frozen full verification passes with all 3,082 inputs and
HEAD unchanged. An extra native typed pub/sub check finds a benchmark verifier
reading the wire payload; its one-accessor correction and eight fail-first
regressions pass afterward. Final combined/hosted verification remains pending.
Missing resource values now display unmeasured/fail rather than false 1.0 parity.
No issue is closed and all performance budgets remain unchanged. See
[accounting contract](research/2026-10-15-owned-pipeline-copy-accounting.md).


Lazy mutation startup repair (2026-10-15): hosted `b43a0a56` rejects stale
source-bound equivalence records before running `core-lazy-vm` and web. All eight
previous predicates map uniquely to unchanged text in the full current
356-mutant inventory. Their reasons and count are revalidated; only IDs and
source hashes change. Both full 356-mutant targets pass at 95.7142857143%,
with zero errors/timeouts and all 246 relevant inputs plus HEAD unchanged.
Independent benchmark/reporting changes are explicitly excluded from that
scoped proof. A preflight catches sixteen additional older stale records; their
unchanged predicates are revalidated without changing reasons, counts, ranges
or floors. All 154 proof records validate and thirteen preflight tests pass.
Canonical scripts now reject stale metadata early. Replacement hosted CI is
pending. Production dry run 38798749509 passes all five platforms and 170
consumer cases with zero skips and audited log hashes. The two paired 90-row
reply diagnostics complete cleanly but still show roughly 0.84 throughput
ratios; no parity is established. Dirty aggregate/native copy follow-up remains
unverified as a whole. See [proof refresh](research/2026-10-15-lazy-mutation-proof-refresh.md).

Allocation measurement audit (2026-10-15): pinned Dart 3.13.1 source and a
forced-GC repro show `accumulatedSize` is live heap inventory, not allocation
volume. Prior allocation ratios cannot establish that resource gate. A standard
SDK native heap-callback prototype preserves 128 MiB of allocation history after
GC, but small-allocation weighting and observer isolation still need validation.
No numeric budget changes. See [allocation research](research/2026-10-15-dart-allocation-volume-research.md).

Owned-copy CI checkpoint (2026-10-15): all 633 client binding mutants
complete with zero errors/timeouts, clean/restored baselines and a 95.9302325581%
assertion score against the unchanged 95% floor. Pinned client/core inputs stay
unchanged; the independent inventory guard and unrelated router correction are
recorded separately. The first full verification fails because the new serializer
test was missing from its independent inventory expectation. The second frozen
run reaches three JSON mixed-PPT failures, exposing an opaque-body conversion
gap. A router-only view wraps the same bytes in one Arguments item, retaining the
original message/owner. All fourteen fail-first control/body cases and all 107
public mixed PPT/E2EE cases now pass. The legacy JSON codec stays unchanged.
Frozen full `bin/verify` passes at `03524853` with HEAD and all 3,070
tracked/intended-new input hashes unchanged. This includes Rust, VM/live and
packaging smoke tests, core Chrome/Dart2Wasm and 2,859 client browser cases
with twenty declared native-only skips. Replacement hosted CI and production
consumers are pending; complete owned copy totals and parity stay open.

Hosted CI repair in progress (2026-10-15): `fc1881d3` finishes with 39
successful checks and one root failure: client message-binding mutation score
94.3359375% versus the unchanged 95% floor; Full Verify correctly fails as its
aggregate. A 24-case storage matrix adds event/result/invocation/error, PPT/plain
and three binary encodings. It reproduces a native ERROR metadata bug: human
message text was mistaken for a PPT scheme. The repaired predicate reads ERROR's
actual metadata. All 1,910 binding cases pass and four exact hosted survivors
are killed by assertions with source restoration checked. Complete resulting
inventory, frozen full verification and replacement hosted CI remain pending.

Owned copy foundation and reply retention (2026-10-15): cumulative Dart
observations now cover explicit clones, coalescing, byte-vector writes, allocator
moves, isolate transfers, framing, keys, PPT and portable crypto. Router worker
snapshots fence asynchronous work and reject missing/replaced workers; workload
quiescence returns an explicit success flag. The separate optional native codec
ABI observes vector/string/growth/parser/framing/key bytes without extending any
published layout. Full totals remain uncertified while the source inventory and
aggregation are completed. The new reply regression removes two full model
copies per RPC by retaining matching packed lazy payloads; other codecs retain
byte-identical wrapper output. All twelve reply cases, 371 Rust core and 294 FFI
cases, 3,383 shared serializer cases, and thirteen live copy/encryption/file cases
pass. Production verification, new timing and complete accounting remain pending.
No remaining issue is closed. See [source and limits](research/2026-10-15-owned-copy-foundation.md).

Nonce-freshness CI repair (2026-10-15): four repeated-plaintext/key checks cover
both ciphers and both plaintext profiles. The exact skipped-initialization CI
mutant fails first; all 168 focused E2EE cases and sixteen Chrome/Dart2Wasm
cases pass. The unchanged complete 315-mutant target passes at 95.3125% with
zero errors/timeouts and the original 95% floor. An initial test-setup attempt
constructs providers during discovery and produces loader errors; its failed
run is retained. The final tests construct providers inside their test cases.
Bounded Qwen review completes without a confirmed issue. All other preceding
head hosted jobs pass; resulting-head CI and fresh full verification are pending.
No performance or complete copy-acceptance claim is added.

Raw-frame verification and exact-capacity diagnostic (2026-10-15): full
`bin/verify` passes at `fc1881d3` with all 3,057 tracked inputs and HEAD unchanged.
Both 90-row paired runs complete using the same production library. Throughput
ratios remain around 0.80 of the better binary baseline; exact fixture capacity
does not establish a useful speed improvement. Allocation and latency still
regress. Required Linux CPU/RSS evidence remains unavailable; diagnostic ratio
placeholders are not measurements. A five-platform production dry run targets
`fc1881d3` (run 38773856451). The next controlled change reserves 256 bytes for
native controls and caches immutable Dart schema field-name sets. All 366 Rust
core cases, 514 Dart FlatBuffers cases, pinned Python/Dart/Rust interop and
separate client/router counter suites (83/34) pass. Local review finds no confirmed
issue. New-source timing and final full verification remain pending. See
[control construction and evidence](research/2026-10-15-flatbuffers-control-construction.md).

Raw-frame follow-up (2026-10-15): single-span native frames now retain their
owner instead of copying, and reversed ranges return unavailable instead of
panicking. Fail-first regressions, all 366 Rust core tests, the additive 32-byte
ABI guard, 46 fixture/report cases, 117 public router/native PPT cases and three
live codec observations pass. Those unfragmented live rows report zero raw-frame
copies; no macro performance improvement is claimed. Exact pinned benchmark
buffer sizing preserves wire bytes and avoids a partial Dart backing view.
Fresh full verification, production artifacts, complete E2EE/transcode owned
totals and parity remain pending. See [source and limits](research/2026-10-15-raw-frame-copy-observations.md).

Verification checkpoint (2026-10-15): `CARGO_INCREMENTAL=0 bin/verify`
passes at `7976a464` with Git HEAD and all 3,052 tracked input hashes unchanged.
The resulting complete 315-mutant E2EE target also passes at 95.3125%, retaining
its 95% floor and zero errors/timeouts. All 131 randomized VM/native cases,
30 randomized Chrome/Dart2Wasm cases and nine live RPC/file cases pass. Hosted
acceptance and complete outer/transcode totals remain pending. A source audit
also identifies unconditional singleton raw-frame coalescing in the native
FlatBuffers receive path; its owner/pointer regression is prepared but no
optimization or performance improvement is claimed yet.

PPT/framing observation follow-up (2026-10-15): fresh pre-change
`bin/test-fast` passes on unchanged combined head `8f1fbfb9`. Actual CBOR PPT
wrapping, binary cloning, coalescing and cold metadata setup now have separate
scoped counters for native and portable providers. An optional native plaintext
framing scalar observes file wrappers and canonical headers while preserving
the sixteen-byte v1 ABI. Fail-first observations reproduce the undercounts;
nine Rust and 131 randomized focused VM/native cases pass. Fresh-process probes verify the
new scalar and the preceding production library's null fallback. All 30 randomized
Chrome/Dart2Wasm cases and nine live RPC/file cases pass. Full frozen
`bin/verify` passes at `7976a464`. See
[PPT/framing source and limits](research/2026-10-15-ppt-serializer-copy-observations.md).
Outer WAMP serialization, transcode totals and all performance acceptance stay
open. No milestone issue is closed by these partial observations.

Current follow-up (2026-10-15): finish remaining FlatBuffers issues.
Both unprofiled 90-row router-view diagnostics complete. Dart-value FlatBuffers
throughput improves 23.2% (best-binary ratio 0.6546 to 0.8040); native construction
and pre-encoded cases show no useful gain. All remain failed acceptance evidence.
The next native receive regression reproduces another opaque-body clone. Shared
core byte views now serve only the built-in native PPT decoder, preserving ordinary
copy semantics, custom decoders and FlatBuffers' 64 MiB encoded limit. All 1,906
focused client/core cases and twenty Chrome/Dart2Wasm cases pass. Full-source
verification and new-source measurements remain pending. PR #130's hosted
core-E2EE mutation failure at 94.921875% is repaired in `ef1fc548` without
changing its 95% floor; replacement hosted CI is pending.

Performance follow-up now uses `codex/flatbuffers-lazy-ppt-views` based on
`25e0d41f`; PR #130 retains the E2EE/counter and verified-shard review. A server
CPU diagnostic identifies eager CBOR decoding just to unwrap an opaque PPT body.
The public native test reproduces a body clone for FlatBuffers/CBOR. Bounded
singleton byte views repair that boundary without parsing the application model.
Twenty unit cases, 107 public PPT cases and nine internal regressions pass;
analysis is clean. Paired unprofiled diagnostics and complete frozen verification
remain pending; the earlier profiled attempts are failed diagnostics, not parity.
See [implementation and evidence](research/2026-10-15-internal-ppt-byte-views.md).

The frozen full run preserves all 20 input hashes and reaches the benchmark
suite, where a stale live assertion expects zero AES assembly bytes rather than
48. The repaired test checks both RPC legs: four portable/native and cipher
combinations now pass, including exact 48-byte portable AES and 160-byte native
nonce/tag totals for two RPCs. This first full run exits 1 and is retained; a
fresh full rerun is still required. New-source production artifacts pass all five
platforms: downloaded logs verify 170 visible cases, zero skips, 22 file hashes,
ABI guards and lifecycle. The downloaded production library passes the actual
crypto copy probe. No E2EE/transcode total or parity acceptance is added.

E2EE follow-up reproduces and repairs unobserved portable AES nonce assembly,
partial failed native legacy CBOR coercion, and Rust nonce/tag framing copies.
An additive optional scalar preserves the 16-byte v1 ABI; eight Rust crypto
cases pass. The final sequential provider/report retry passes 117 cases against the rebuilt
new-scalar library; older production lookup safely returns unavailable. Frozen
full verification remains pending. The CI audit
now also requires both router shard jobs, and all 28 audit cases pass on a stable
head. The earlier 129-case run's four failures come from moving HEAD during its
fake-head assertions; its stable audit retry passes. The current fast run sees a
transient Dart ffi qualification error during edits and is not accepted; analysis
passes after qualification. See [copy boundaries](research/2026-10-15-e2ee-copy-boundaries.md).

PR #129 now passes every hosted job and both Codecov gates. PR #130 passes
both coverage gates, but its router message-binding mutation job reaches its
90-minute deadline after 622 of 699 mutants, cancelling Full Verify. A rerun
is dispatched. The follow-up partitions the unchanged full inventory into two
shards and requires independently regenerated union scoring plus successful
shard jobs in Full Verify, using the existing MCP mechanism. No timeout,
mutation inventory or score threshold is relaxed. Focused CI checks are running;
complete new-head verification is pending. E2EE/transcode owned-boundary totals
and all performance parity budgets remain open. The shared local native resource
lease temporarily blocks timed diagnostics; no other campaign is interrupted.

Current follow-up (2026-10-14): validate FlatBuffers byte-vector views.
Branch `codex/flatbuffers-byte-vector-views` starts at scope checkpoint `fc808e92`;
[PR #129](https://github.com/konsultaner/connectanum-dart/pull/129) retains the
separate measurement/scope review. Fresh pre-change `bin/test-fast` passes.
Immutable byte views retain exact input ranges and storage, with explicit native
lifetime requirements. Both pinned generators select the same reader. Shared
payload generation fills its byte buffer directly; FlatBuffers builders reserve
the known model size. Focused VM and Chrome/Dart2Wasm binding/view cases pass.
The initial root-level browser invocation fails its hybrid loader paths; the
package-root retry passes 79 cases. A live diagnostic first rejects an outdated
driver without executing rows; the driver is being rebuilt. No parity is claimed.
Fresh pinned interop passes 33 upstream/42 extended fixtures and all 25
public message types. Both 90-row before/after diagnostics complete; native
FlatBuffers throughput improves roughly 5–6%, while the Dart-value case does
not improve usefully and allocation/GC ratios still regress. Both diagnostics
fail acceptance; Linux CPU/RSS and full duration/matrix evidence remain absent.
The first full verify rejects the new test missing from serializer mutation
inventories; all four target support lists and the shared suite now include it.
Replacement full `bin/verify` passes at exit 0 with all 12 frozen
code/test/config inputs unchanged; no mutation target or budget is reduced.
The measurement branch's child ABI probe now contributes real coverage, and
preceding head `e55d36cf` passes all main CI jobs. The subsequent borrowed-FFI
observation/router-owned-send fix is merged here from `ef9f605c`; that head passes
all five production platforms (170 cases, zero skips), audited source/log/ABI/
lifecycle evidence, a production-library ABI probe, WAMP profiles and package
dry run. Its main CI/Codecov checks remain pending. The combined branch initially
fails deployment-audit tests because the local disk is full, not because scripts
changed. Clearing only this worktree's rebuildable caches restores all 28 tests.
Fresh combined `bin/verify` passes at exit 0 with all 38 frozen code/test/config
inputs unchanged; source, native executables and prior evidence stay preserved.
Hosted byte-view acceptance remains pending. See [source and measured limits](research/2026-10-14-flatbuffers-byte-vector-views.md).
The primary mutation checkout stays untouched.

Current follow-up (2026-10-14): complete the GitHub FlatBuffers milestone.
Branch `codex/finish-flatbuffers-milestone` reuses the managed worktree; the
primary mutation-runner checkout stays untouched. The released master remains
`73d840c9`. Its main CI now passes all 36 jobs, and all five production native
consumers pass 170 cases with zero skips. Issue #104 is closed after auditing
its public examples, generic external-owner contract, ObjectBox boundary,
seven hosted packages and linked release evidence. Issue #102 also closes on
released-source CI: the downloaded GuardMalloc report verifies 87 cases and
263 committed inputs, plus its separately recorded generated lock. The milestone description
now reflects merged and published work.

Fresh `bin/test-fast` initially fails on two absolute local paths in the
unpublished beta.8 documentation checkpoint. Normalizing those references
reproduces and repairs the policy failure; the replacement fast run passes.
The independent peer moves to cbor2 5.9.0, the first patched release for
GHSA-3c37-wwvx-h642. Fresh interop passes 33 upstream and 42 extended fixtures,
both encoding directions and all 25 public message types; the negotiated
RawSocket/WebSocket live peer also passes.

A live extraction-counter test then reproduces an existing observation gap:
Tokio-Rustls's public client/server reads bypass the instrumented internal
`Stream::poll_read`. Four source hooks now observe both public initial and
batched copies. Exact tests fail first at zero instead of three bytes and
pass after the repair, including borrowed-pointer preservation and EOF.
An additive optional scalar C API exposes this partial counter to both Dart
runtimes and client/router benchmark breakdowns. The old 48-byte Rustls ABI
is unchanged; the published beta.8 library correctly returns null for the
new optional metric. Complete dependency TLS/SDK/crypto totals remain unknown. On 2026-10-14
the user explicitly selects the standard Dart SDK scope: prove Connectanum
buffer boundaries and label unmeasured dependency internals. The follow-up
uses a new versioned scope marker, validates owned totals against their
client/router breakdowns, and permits only active, precisely labelled TLS/SDK
masking exclusions. Missing owned counters, E2EE/transcode gaps and all numeric
performance/resource budgets remain blockers. See [approved contract](research/2026-10-14-standard-sdk-copy-scope.md).
Resulting-source `bin/verify` passes at exit 0; all six scope code/test/policy
inputs match their frozen hashes. The 32 comparison and 66 owned-counter cases
pass, including forged totals and malformed evidence. Bounded Qwen test planning
and review complete; the heavyweight GLM judge times out, so the contract is
also checked manually against the actual transport/source boundaries. PR #129
contains the measurement repairs and this approved scope update. At preceding
head `7965857f`, all five production platforms pass 170 cases with zero skips;
downloaded profile logs, ABI/lifecycle guards and source hashes are audited.
WAMP profile gates, binding, GuardMalloc, fast checks and package dry run pass.
New-head hosted acceptance remains pending; no parity is established.
The first full run reproduces the strengthened GC probe failure: actual
collections produce paired category-GC collection scopes, but the old parser
reports zero. Actual VM evidence also reproduces duplicated notifications and heap
statistics for isolates sharing one group. The final collector reads native
cumulative collection/time counters and profiles allocation once per shared
heap, while retaining every isolate for lifecycle validation. Missing, malformed
or rewound counters remain unavailable. All 35 focused forced-GC, heap/delta and
live-worker cases pass. The first timeline-reconciliation experiment fails its
stronger stream check and is retained as diagnostic evidence.
See [GC source and scope](research/2026-10-14-dart-gc-metrics.md).
Final canonical `bin/verify` passes at exit 0, including Rust, VM/native,
consumers and Chrome/Dart2Wasm (4,751 core, 2,829 client; 20 declared native-only
skips). All 22 recorded changed code/test inputs still match their frozen hashes.
The completed local review identifies a missing-profiling-metadata fallback;
it now leaves allocation/GC unavailable, and a real VM probe verifies that
behavior. Other speculative review findings are checked against the actual SDK
snapshot and stable-isolate tests. Hosted new-source acceptance is pending.
A byte-vector construction prototype is prepared but its timed run is blocked
by an active native-mutation resource lease; that lease and primary work stay
untouched.
See [scope and evidence](research/2026-10-14-tokio-rustls-public-copy-metrics.md).

PR #129 coverage follow-up: the `fc808e92` VM coverage job passes, but
Codecov patch coverage is 92.70% against 93.91%, with ten changed lines missed.
The existing isolated transport ABI probe now exports real client/router hits
through the canonical child-coverage directory. Its scalar/legacy ABI checks
stay isolated from shared counters; collection does not pause the current
isolate, and exclusive report creation prevents overwriting evidence. The
coverage-enabled probe passes and records seven previously missed router
lines. The normal probe plus collector regression suite passes 42 cases, and
analysis is clean. Qwen review reports no confirmed issue; its speculative
partial-write concern is covered by the existing exclusive writer tests. Full
resulting-source verification prints successful summaries for every suite,
including Chrome/Dart2Wasm. Its zsh wrapper then fails when assigning the
read-only `status` variable, so no clean canonical exit is recorded. The next
run uses a dedicated exit-code variable and an explicit Bash wrapper. Coverage
floors and milestone criteria remain unchanged; hosted acceptance is pending.
A subsequent source audit identifies another actual owned copy: the router's
borrowed send copies into Dart's native staging allocation, then
`ct_send_message` copies that input again in Rust. The existing total covers
only the first copy. Add direct Rust observation and conservative optional-ABI
fallback, then use the established owned-send API to avoid that second copy
when supported. Fresh pre-change `bin/test-fast` passes at exit 0. The Rust
regression fails first in both actual borrowed-send and file-wrapper cases,
then all five cases pass after eight source hooks. Both Dart runtimes expose
the additive nullable scalar. Missing observation prevents complete native
client/router coverage; staging and Rust bytes are retained separately. The
real ABI/ownership probe and scoped merger pass 69 cases, including three
borrowed bytes versus zero Rust copies on owned router rejection. All 32
comparison tests pass. Resulting-source `bin/verify` now passes with a clean
exit 0, including Rust, VM/native, consumers and Chrome/Dart2Wasm (4,751 core,
2,829 client; 20 declared native-only skips). All 13 changed code/test hashes
match their frozen inputs. The older production library passes the ABI probe,
leaving the absent scalar and its deltas null. GuardMalloc passes all 87 cases;
all 266 source/lock hashes, group logs and the executable are independently
verified. Bounded GLM review completes without a confirmed finding; the broader
Qwen review times out. The measurement PR remains ready for review with new-head
hosted acceptance pending. E2EE/transcode pipeline gaps, parity and milestone
closure remain open. See the FFI research note for source boundaries and the
verified disposition of the local ownership advice.

Current follow-up (2026-10-10): synchronized beta.8 publication is complete.
The user merges PR #107 through protected master at `73d840c9`; its tree exactly
matches tested release head `b382b21c`. All eight release/package tags point to
that merge. [Native release v3.0.0-beta.8](https://github.com/konsultaner/connectanum-dart/releases/tag/v3.0.0-beta.8)
is published as a prerelease with 30 assets across five platforms.
[Native workflow 38033155639](https://github.com/konsultaner/connectanum-dart/actions/runs/38033155639)
passes all five builds, production consumers, signing and publication. Downloaded
reports independently verify 170 profile cases with zero skips, exact source,
log hashes, lifecycle and 48-byte ABI guards. All five published manifests match
`73d840c9`; fresh client/router installation passes and both binary hashes match
the production proof. Intel macOS initially queues, then passes on a runner.
All seven `3.0.0-beta.8` packages are confirmed through the public pub.dev API:
[core](https://pub.dev/packages/connectanum_core/versions/3.0.0-beta.8),
[client](https://pub.dev/packages/connectanum_client/versions/3.0.0-beta.8),
[MCP](https://pub.dev/packages/connectanum_mcp/versions/3.0.0-beta.8),
[router](https://pub.dev/packages/connectanum_router/versions/3.0.0-beta.8),
[facade](https://pub.dev/packages/connectanum/versions/3.0.0-beta.8),
[auth server](https://pub.dev/packages/connectanum_auth_server/versions/3.0.0-beta.8)
and [bench](https://pub.dev/packages/connectanum_bench/versions/3.0.0-beta.8).
All seven tag-triggered publication workflows pass in dependency order; hosted
constraints remain synchronized. An isolated consumer outside the repository
uses a fresh public cache, all seven exact hosted versions and matching archive
hashes. Its default hooks download the verified production library. Dart macOS
bundling changes the install name/ad hoc signature, while all 14 code/data
sections remain identical. The public native FlatBuffers example passes with
116 frame bytes, three segments, zero application-input copies and zero
control-growth copies. The initial benchmark index is stale; refreshing after
public-index propagation resolves the clean install without changing versions.
Evidence is retained under `out/beta8-publish-evidence/`; the standalone
consumer uses an isolated scratch directory outside the repository.
Local full `bin/verify` passes on identical tree `b382b21c`; all 36 main jobs,
seven strict archives and WampApp artifacts also pass there. Post-merge
[CI 38032968401](https://github.com/konsultaner/connectanum-dart/actions/runs/38032968401)
passes all 36 jobs, including VM coverage and both mutation gates. WAMP profile gates and kTLS validation pass on `73d840c9`.
The closed release PR's separate Codecov comparison loses three hits in
unchanged router WebSocket polling and MCP timer-identity branches (patch 100%;
project 93.90% versus 93.91%). Actual LCOV differences are retained; no coverage
floor is relaxed. Local companion triage is blocked by an active native mutation
resource lease. The primary checkout and earlier local evidence stay preserved.
This documentation checkpoint remains local on `codex/publish-3.0.0-beta.8`;
published source/tags stay at `73d840c9`, avoiding another unchanged CI run.
Issues #100–#104 and performance/copy acceptance remain open; no ObjectBox
adapter or stable-release claim is included in this beta checkpoint.

Current follow-up (2026-10-09): integrate merged CI into the beta.8 release.
The user merges PR #108 at master `759d3d4c`. Release PR #107 then has one
execution-plan documentation conflict. Fresh pre-merge `bin/test-fast` passes
at exit 0 on `85b92916`; baseline evidence is retained under
`out/ci-release-resync-evidence/`. The merge preserves both the release checklist
and completed CI acceptance evidence. Package/runtime/crate changes remain the
approved beta.8 graph; no package is published yet. Canonical `bin/verify`,
strict package archives and replacement hosted acceptance are pending.
Required review and protected-master promotion remain mandatory before native
assets and dependency-ordered pub.dev tags are published. Companion summary
was initially resource-lease blocked; review then times out on Ollama and cannot
reach GLM. Manual version/tag review passes; the primary checkout is preserved.

Current follow-up (2026-10-08): coordinated `3.0.0-beta.8` publication.
The user authorizes another synchronized version bump and pub.dev deployment.
All seven beta.7 packages are confirmed through the live pub.dev API; beta.8
is not yet published. The release branch starts from merged master `0e585405`
and synchronizes seven Dart manifests, their hosted constraints, three Rust
crate versions, MCP runtime identities, hook fixtures and changelogs.
Fresh baseline `bin/test-fast` passes at exit 0 before the version edits.
All 37 release planner/tag/note/intent tests and all seven exact publish-tag
checks pass. After committing the candidate, all seven strict archive dry runs
report zero warnings. Full `bin/verify` passes at exit 0 on pushed `7ca882c6`,
including Rust, VM, native, consumers, router and Chrome/Dart2Wasm (4,751 core,
2,829 client; the same 20 native-only skips). Companion review is blocked by the
active native mutation resource lease; manual diff review is complete.
Ready-for-review [release PR #107](https://github.com/konsultaner/connectanum-dart/pull/107)
requires one approving review and passing hosted Fast Checks/Full Verify.
[Native dry run 37799443111](https://github.com/konsultaner/connectanum-dart/actions/runs/37799443111)
passes all five platforms and the release preview, with publication skipped.
Downloaded reports independently confirm commit `7ca882c6`, 170 passing public
profile cases, zero skips, matching log hashes, lifecycle and 48-byte ABI guards.
Hosted checks pass on original head `7ca882c6`. Its production-profile proof
remains tied to that head; new integration verification is recorded above.
Publish matching `v3.0.0-beta.8` native assets first, validate installation, then
publish core, client, MCP, router, facade, auth server and benchmark package tags
in dependency order and confirm every hosted version. Existing external-app
pins remain unchanged until the new graph is published. Issues #100–#104 and
performance/copy acceptance remain open; this is a beta release checkpoint.

Current follow-up (2026-10-09): CI repair for [PR #108](https://github.com/konsultaner/connectanum-dart/pull/108).
Branch `codex/ci-execution-sharing` starts from merged master `0e585405`;
the beta.8 release branch/head remains preserved separately. The first run at
`163699a0` fails before tests because setup-dart registers its matcher from the
parent composite path. The explicit matcher opt-out at `15bbac7f` fixes shared
setup; hosted Fast Checks, package dry runs, browser coverage, shared native
build and completed mutation gates pass. Fresh local `bin/test-fast` and
canonical `bin/verify` also pass (Rust, VM, consumers, Chrome/Dart2Wasm; 4,751
core, 2,829 client, 20 unchanged native-only skips).

The replacement [run 37850365570](https://github.com/konsultaner/connectanum-dart/actions/runs/37850365570)
then exposes missing native benchmark coverage: its process intentionally
clears `CONNECTANUM_NATIVE_LIB`, while the shared library only exists under
`out/ci-native`. One ABI test fails and 230 native cases skip. Prepare now
installs and verifies the same artifact at the conventional ffi-test location,
using atomic replacement; dependency, source, toolchain, profile and digest
checks remain enforced. The real Dart discovery regression fails before the
fix and passes after it. All 14 CI execution contracts pass; the actual native
copy ABI case passes with the override unset and no skips. Local CI coverage
executes all 1,642 benchmark cases with zero skips. Its macOS benchmark gate
measures 97.203% against the 98% Linux CI floor: the exact 35-line difference
from the passing Linux report is confined to Linux-only CPU/RSS metrics.
No floor or platform guard is changed. Canonical `bin/verify` with shared
artifact reuse passes at exit 0 (Rust, VM, consumers, Chrome/Dart2Wasm;
4,751 core, 2,829 client, 20 unchanged native-only browser skips).
Replacement hosted Linux acceptance passes on source head `3efbba99`:
all 1,642 benchmark cases pass, benchmark coverage is 98.329%, handwritten
VM coverage is 93.916%, and library/packaging policies report no findings.

At source head `3efbba99`, all six hosted MCP shards and independently
regenerated aggregation complete all 1,101 mutants; the uploaded outcomes
exactly match the fresh inventory, both baselines pass, and the assertion score
is 97.37783075089392%, above the original 95% gate. The latest
[main run 37855378339](https://github.com/konsultaner/connectanum-dart/actions/runs/37855378339)
passes all 36 jobs, including Linux coverage and required Full Verify. All 47
PR checks pass on source head `3efbba99`. The user merges PR #108 into master
at `759d3d4c` on 2026-10-09. Package dry runs and every WampApp platform artifact pass on
the same source head. The separate macOS
artifact job initially cannot acquire a runner; its targeted retry passes on
unchanged artifact head `163699a0` (run 37810537255, attempt 2). Inventories,
coverage scopes/floors and deadlines stay unchanged. Local companion attempts
remain blocked by the active native mutation resource lease. Scope and proof:
[CI plan](research/2026-10-08-ci-execution-sharing.md).

CI acceptance evidence was retained locally while PR #108 was under review;
it is now recorded here after that PR is merged. The tested source head stays
at `3efbba99`. The beta.8 release follows through PR #107.

Current follow-up (2026-10-08): PR #105 Codecov project regression.
At `7b530d58`, hosted test/mutation, package and native-artifact checks pass;
Codecov project coverage fails at 88.693% against master's 93.896%.
Its report includes two generated WAMP FlatBuffers files already measured
separately by the local coverage checker. Codecov now uses the same exact
exclusions; handwritten runtime/serializer code and thresholds remain unchanged.
The coverage runner also retains eight previously omitted complete suites,
including native owned segments, FlatBuffers frames/profiles, copy metrics and
router forwarding variants. Actual added-suite runs pass and contribute 171
handwritten VM line hits; the merged hosted-report estimate is 93.913%.
Three fail-first regression methods reproduce the omissions and scope mismatch.
Fresh baseline `bin/test-fast` and candidate `bin/verify` pass at exit 0,
including Rust/VM/consumer/router checks and both browser suites (4,751 core,
2,829 client; 20 unchanged native-only skips). All 110 coverage-policy/runner
methods pass. Codecov's public validator accepts the exact generated-file scope.
The functional fix is published as `7bf7dd4f`, followed by `ec675d59`.
All 85 PR checks pass: Codecov project is 93.90% (+0.01 percentage points
versus master), and Codecov patch, Full Verify and mutation checks pass.
The verified PR is marked ready and merged at `0e585405`.
Hosted acceptance: [PR #105 checks](https://github.com/konsultaner/connectanum-dart/pull/105/checks).
Evidence: [coverage scope/proof](research/2026-10-08-codecov-project-coverage.md).

Current follow-up (2026-10-07): coverage runtime ownership isolation.
The normal runner isolates remote-auth integration; the coverage runner omitted
that separation. A focused combined actual run aborts at exit 134 with runtime
already started and a native callback from the wrong isolate. Four MCP and
thirteen remote-auth cases pass when separated. Coverage now retains both full
suites in sequential processes with separate raw reports; formatting continues
to merge the whole raw root. Two fail-first runner methods and failure controls
pass; all 85 script regressions pass. Bounded review identifies no concrete
finding. Candidate canonical fast/full checks pass at exit 0, including both
browser suites with the same 20 native-only skips. Hosted acceptance is pending.
The previous Linux MCP subscription assertion's specific cause remains unknown.
The `df1a9ad5` native run provides verified 34-case reports on all five platforms
(170 total, no skips), including Windows lifecycle and 48-byte ABI guards. Its
package dry run passes. The overall native run fails afterward on macOS Intel
attestation persistence; two rerun requests return HTTP 500. Sampled hosted PR
jobs fail without acquiring a runner (five attempts, no steps). These external
failures remain recorded; gates are not skipped.
Evidence: [coverage scope/proof](research/2026-10-07-coverage-runtime-isolation.md).

Current follow-up (2026-10-07): Windows native runtime admission.
Published `4a7ac185` native run 37622772557 passes four Linux/macOS platforms;
Windows now launches tests and passes the 48-byte ABI guard, then rejects
runtime startup because its platform selector chooses the unsupported stub.
Windows now uses the existing shared supported handle. Other hosts retain
explicit rejection. The packaged verifier exercises actual start, duplicate
start, shutdown and restart before running all 34 profiles. All 20 verifier
methods and local constructor/lifecycle/unsupported controls pass. A fresh
macOS production candidate passes the runtime audit, ABI guard and all 34
public profiles. Bounded review is checked against source; GLM identifies no
definite defect. Candidate canonical fast/full checks pass at exit 0. Hosted
Windows acceptance remains pending. The preceding `4a7ac185` PR VM coverage
job 112825887695 fails one MCP last-owner cleanup assertion (expected empty,
observed `[1]`); source-level cause and repair remain pending and are the next
CI priority. Both remote masters remain at integrated `3bac4cf5`; no new merge
is needed. The five-platform gate and all benchmark budgets are unchanged.
Evidence: [runtime scope and proof](research/2026-10-07-windows-runtime-admission.md).

Current follow-up (2026-10-07): Windows packaged consumer launcher.
Verified source checkpoint `736b6454` contains the Tokio-Rustls observer,
fast ownership-oracle selection fix and packaged 48-byte ABI guard.
Published `2bfff943` native dry run 37614965856 passes four platforms but
Windows hook compilation tries `dart.EXE.exe` before any profile tests.
Two execution regressions fail first. Windows `.EXE`/`.exe` and shell wrappers
now normalize to lowercase `.exe` and require the executable file.
All 17 verifier methods pass; POSIX paths, SDK and profile requirements remain
unchanged. Bounded local review completes without a definite error.
The corrected macOS production consumer passes the 48-byte ABI guard and all
34 public profile cases. Final `bin/test-fast` and `bin/verify` pass at exit 0,
including Rust/VM/public consumers and both browser suites (20 unchanged
native-only skips). Hosted Windows runtime acceptance remains pending. Evidence:
[Windows launcher scope and proof](research/2026-10-07-windows-consumer-launcher.md).

Current follow-up (2026-10-07): first full hosted primary result.
Frozen `a5c6aaf9` completes all 1,440 rows (48 cases, three codecs, three warmup
and seven measured passes); driver exit0 and cleanup, policy/executable hashes
and exact local comparison replay verify. The comparator fails with 2,129
findings, including 276 parity failures: throughput, latency, CPU and allocation
gates each fail in all 48 cases; RSS fails in 36. Missing copy fields, zero GC
baselines and five windows below 10,000ms remain blockers. A forced-GC probe
emits real `GC` category B/E collection spans while the existing collector reports
zero; a positive regression fails. No collector repair is included yet.
Every original supplement, normative copy field and budget remains mandatory.
Evidence: [hosted result and GC repro](research/2026-10-07-hosted-primary-result.md).

Current follow-up (2026-10-07): actual Tokio-Rustls plaintext extraction.
The workspace pins published Tokio-Rustls 0.26.6, both original licenses,
its unchanged published lockfile and four restored upstream test fixtures.
The source hook counts only successful `ReadBuf::put_slice()` bytes;
borrowed views and consumption preserve the storage pointer and count zero.
Two fail-first copy cases and a pending/malformed-input control pass after
instrumentation. Both macOS/Linux pass all 14 enabled and 11 disabled cases;
Linux matches all 3,017 frozen inputs and passes a real TLS connection test.
Both candidate production bundles pass 34 public profile cases and nine exact
license/notice/manifest checks each. The source gate passes all twelve controls.
Initial companion attempts are lease-blocked; later test advice completes.
The first canonical fast check loads the just-packaged production library and
fails three owner-oracle cases because test symbols are intentionally absent.
The fast client suite now explicitly prepares `ffi-test`, matching full
verification. Three execution controls pass on macOS/Linux after reproducing
both production-selection failures; a failed test build stops verification.
A larger review reaches its token limit; a bounded retry completes without an
actionable finding. Its speculative cautions are disproved by initialization,
feature selection and execution tests. Canonical fast verification passes.
Full verification terminates at exit 255 on Dart kernel-copy OS error 28:
the host disk is full. Rebuildable feature-worktree compiler/debug caches are
removed, restoring 21 GiB free while retaining source, release libraries and
proof artifacts. The production-consumer audit also exposes missing coverage
of the new 48-byte Rustls snapshot. It now requires the export and checks its
null status, writes and surrounding guards in a fresh process. All 14 verifier
methods pass, including six new failure controls; the macOS packaged library
passes the ABI guard and all 34 profile cases. A bounded GLM review completes
without a definite error. Docker's API is unresponsive after the disk event;
its original Linux direct-probe session remains live and is not restarted.
Both published cde CI runs are green. Final canonical `bin/test-fast` and
`bin/verify` pass at exit 0 after cache cleanup, including Rust/VM/consumers,
1,642 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with 20 unchanged native-only skips. Published `2bfff943` native dry
run 37614965856 passes all 34 public cases on four Linux/macOS platforms;
Windows fails before testing because hooks launch `dart.EXE.exe`. Two
execution controls reproduce uppercase suffix propagation and omitted
executable validation; a narrow launcher correction is the next CI priority.
This source-only Tokio observation does not extend the Rustls ABI or close
complete-copy/performance criteria. Evidence:
[extraction scope and proof](research/2026-10-07-tokio-rustls-extraction.md).

Current follow-up (2026-10-07): optional Rustls source metrics bridge.
Twelve fail-first cases reproduce omitted partial-counter metadata on both
transports. A separate 48-byte C snapshot exposes all six actual Rustls source
counters; legacy 24-byte and V2 40-byte transport snapshots remain unchanged.
Client/router optional lookup and nullable deltas retain null with old libraries.
Benchmark client/router breakdowns retain the named partial observations while
complete TLS/transport gates remain unchanged. MacOS passes the native layout/
null/tail guard, 56 merge/delta cases and old/new ABI probes. Linux matches all
2,996 final frozen source/lock inputs and passes its native guard, 56 merge/delta
cases and both new/published-old ABI probes. A separate fail-first negative
counter test now preserves unmeasured metadata for invalid values. Completed companion
test advice is checked; final review is blocked by the active native-mutation
resource lease. The candidate fast check exposes a local SDK path in the published artifact
proof. Command paths are now normalized to `dart`, retaining raw report hashes;
the public-reference gate passes. Fresh canonical `bin/test-fast` and full
`bin/verify` pass at exit 0: Rust/VM/consumers, 1,642 benchmark, 4,958 router,
4,751 core browser and 2,829 client browser cases with 20 unchanged native-only
skips. Crate formatting and the final Linux native/new-ABI replay pass with
all 2,996 formatted inputs matched. Narrowed review remains lease-blocked. Both cde
hosted CI runs pass all completed jobs and retain only their MCP mutation jobs;
the frozen full primary remains independent. No complete-copy, parity or
milestone acceptance follows.

Current follow-up (2026-10-07): packaged production runtime consumers.
Source checkpoint `0ce3c364` commits the payload observer after canonical fast
and full verification passed. The new Native Artifacts gate verifies the
archive checksum, detached/embedded source manifest and production ABI/oracle
inventory, then runs all 34 public profile cases in three separate Dart
processes against the extracted library. JSON evidence rejects skips, missing
cases, errors and unfinished starts even with a success summary. Per-platform
proofs and logs upload on failure. Nine failure controls pass on macOS/Linux, and Actionlint passes. The actual
gate passes all 34 cases against each frozen published `cde9fbed` arm64 bundle;
completed companion advice is checked against source and actual timeout
behavior. Canonical candidate `bin/test-fast` and full verification pass at exit 0
together with the metrics bridge. Hosted runtime proof for all five
resulting-source platforms remains pending. No release, whole-copy or
performance acceptance follows.

Current follow-up (2026-10-07): payload copy observations.
Published source `cde9fbed` passes canonical fast/full checks. Push CI fast
checks now pass; remaining resulting-source jobs are live. Native dry run
37588514671 passes all five builds; package dry run 37588518168 passes.
All 15 pinned attestations, 25 exact notices/manifests (including Windows),
30 preview assets and rendered notes verify. Both hosted arm64 production
libraries pass 34 profile cases; other platforms have build/provenance evidence.
The independent full primary 37582544124 remains live on frozen `a5c6aaf9`.
Four new fail-first tests expose omitted 7/8/10/9-byte payload copy observations.
Hooks cover owned clones, borrowed ownership conversion, bounded U8/U16 reads
and content/certificate encodes while preserving borrowed reads and owned
moves. A targeted U24 test confirms inner clone delegation counts once.
All 243/232 macOS and 244/233 Linux enabled/disabled cases pass; both real TLS
checks pass with all 860 frozen Linux inputs matched. The source gate and five
failure controls pass. Initial companion findings are disproved by source and the targeted regression.
The follow-up is initially blocked by the native-mutation resource lease; its
post-verification retry completes and confirms the clone/borrow semantics. Canonical candidate `bin/test-fast` and full `bin/verify` pass at exit 0:
Rust/VM/consumers, 1,616 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with 20 unchanged native-only skips. No whole TLS or
parity acceptance follows; #100–#104 remain open. Evidence:
[scoped payload proof](research/2026-10-07-rustls-payload-copies-proof.json).

Current follow-up (2026-10-07): deframer and record copy observations.
Four new fail-first tests expose omitted deframer appends/moves and record
clones/appends. All 238 enabled and 232 disabled upstream library cases pass;
the source gate and five failure controls pass. Named counters remain partial.
A live receive assertion exposes that buffered Rustls reads directly into
its deframer, bypassing `extend`; accepted input is not counted as an assumed
copy. That invalid new assertion is removed, preserving existing coverage.
The live record-append check passes on macOS and Linux. Linux passes 239 enabled
and 233 disabled cases with all 860 frozen source/lock inputs matched.
Canonical `bin/test-fast` and full `bin/verify` pass at exit 0: Rust/VM/consumers,
1,616 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases,
with 20 unchanged native-only skips.
Growth, remaining record/crypto and Tokio-Rustls/SDK extraction still prevent
whole-copy acceptance. The published `a5c6aaf9` full primary remains live;
native and package dry runs finish successfully. Both resulting-source CI fast
jobs fail a campaign unit fixture's missing generated Cargo lockfile. An
isolated temporary source root reproduces it; explicit synthetic locks and
hash/archive assertions pass all 15 campaign cases without changing policy.
All 15 a5 artifact attestations and 30 preview assets verify. Windows converts
the bundled notice and source manifest to CRLF; their new `-text` attributes
prevent that byte drift; all 843 source/fixture/notice/manifest filter controls
pass. The unchanged release-note renderer reproduces the
preview with the exact workflow reference. All 34 production profile cases
pass against both hosted macOS arm64 and Linux arm64 libraries; other three
platforms have build/provenance evidence. No release or parity claim follows.
#100–#104 remain open.

Current follow-up (2026-10-07): source-observed Rustls copies.
Rustls 0.23.45 is pinned with original licenses and an 841-file digest manifest,
including exact upstream test fixtures. Two fail-first cases expose omitted
actual chunk/queue copies; observations make all 234 library cases
pass. A feature-disabled build and real native TLS outbound observation pass.
The live receive probe exposes a separate Tokio-Rustls copy site; total TLS
coverage remains unknown. The dependency lock changes only Rustls source at the
same version. Five source-integrity failure controls and fresh `bin/test-fast` pass.
All 841 source blobs remain exact with Windows newline conversion enabled.
Native bundle packaging retains Rustls licenses and source digests. Final
`bin/verify` fails the unchanged FastCGI cumulative stdout-limit fixture
with a peer reset; its isolated unchanged repro and five unchanged repeats
pass. Fresh full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,616
benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases,
with 20 unchanged native-only skips. The narrowed GLM judgment completes
with no confirmed native defect. Real macOS arm64 packaging passes: all five
Rustls notice/manifest files match and the library excludes test oracles.
Clean source commit `3b251789` packaging then matches the verified library,
notices and source manifest. All 34 production profile cases pass in separate
processes; an initial combined probe finds an already-started shared runtime.
This scoped macOS check does not provide multi-platform release acceptance. #100–#104 and all gates remain
open. Research: [Rustls copy observer](research/2026-10-07-rustls-copy-observer.md).

Current follow-up (2026-10-07): native prefetched input copies.
Two real TCP-pair regressions expose uncounted staging/replay copies; an
intermediate observation identifies the duplicate unread-buffer copy, now
removed. The old 24-byte snapshot remains unchanged beside a new optional
40-byte ABI. Both Dart runtimes retain null for absent counters. The 30 merge,
39 comparator/campaign and eight live worker cases pass; new test-library and
old production-library snapshot tests pass. Complete transport reports require the new input
counter evidence. Initial fast-check warnings and an omitted direct test
dependency are corrected; Linux locked-snapshot setup was repaired without
relaxing dependency locking. Final Linux arm64 native/FFI, 31 Dart and eight
live worker cases pass with all 18 source/lock hashes matched. Fresh
`bin/test-fast` passes at exit 0, including all 1,616 benchmark cases.
Full verify first exposes a test-only stale-debug library selection; the exact
repro fails before and passes after using the existing canonical test resolver.
Final full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,616 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases, with the same
20 native-only skips. Evidence: `/tmp/connectanum-native-io-copy-verify-final.{log,exit}`.
Companion debug/review/test advice is verified; no accepted source defect remains.
Preceding `0ec8df06` PR run 37565054707 completes all 41 jobs successfully.
Push run 37565051795 also completes all 41 jobs successfully. The four verified
commits through `a5c6aaf9` are now published to both remotes. Resulting-source
CI runs 37582506753 (push) and 37582511052 (PR), full primary campaign
37582544124, native dry run 37582546475 and package dry run 37582549630
are dispatched; acceptance remains pending. Resulting-head
hosted acceptance and performance parity remain pending; no issue closure follows. Research: [prefetched input copies](research/2026-10-07-native-prefetched-input-copies.md).

Current follow-up (2026-10-07): hosted full FlatBuffers campaign.
The registered profile workflow gains an explicit manual primary choice with
all 1,440 rows and unchanged gates. Production release binaries, locks and raw
failure evidence are archived. The 38 campaign/comparator tests and verified
Actionlint pass; four synthetic summary fixtures preserve failure status.
Final companion review is blocked by the active native mutation resource lease.
Baseline `bin/test-fast` and full `bin/verify` pass at exit 0, including
1,609 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with the unchanged 20 native-only skips. Evidence:
`/tmp/connectanum-hosted-primary-verify.{log,exit}`. Hosted execution remains
pending; no performance acceptance follows. Research: [hosted full campaign](research/2026-10-07-hosted-flatbuffers-primary-campaign.md).

Current follow-up (2026-10-07): observed native PPT submission metrics.
Thirty-six fail-first cases expose zero-copy values inferred only from settings
and permissive observation parsing. Each sample now requires its own observed
native frame submission and complete encoded-owner reuse. Missing/fallback/
repeated/mismatched observations remain unmeasured. All 121 focused, 32 native
and 20 live benchmark cases pass on macOS/Linux, with matched Linux inputs.
Tracking is opt-in; no ownership/ABI/fallback or acceptance gate changes.
Baseline fast and full `bin/verify` pass at exit zero, including 1,609 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases with 20 unchanged
native-only skips. Evidence: `/tmp/connectanum-observed-owned-copy-verify.{log,exit}`.
Resulting-head hosted verification remains pending. Final local review is blocked by
the active native mutation resource lease; direct review and focused checks
complete. Research: [observed submissions](research/2026-10-07-observed-native-ppt-copy-boundary.md).

Current follow-up (2026-10-07): measured RawSocket input normalization.
Twenty-seven fail-first assertions reproduce partial-input retries and omitted
header accounting. Full arrays and validated native ranges retain their storage;
other inputs make one measured copy before queueing. All 81 socket/metrics cases
pass on macOS and Linux arm64, and the exact Linux diagnostic CI step passes.
Baseline fast and bounded GLM review pass. First verify fails an unchanged
FastCGI closure fixture; isolated repro and five unchanged repeats pass. Fresh
full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,563 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases, with 20
unchanged native-only skips. No assertions or timeouts changed. Evidence:
`/tmp/connectanum-socket-normalization-final-verify.{log,exit}`. SDK/TLS
and performance acceptance remain open. Research: [input normalization](research/2026-10-07-rawsocket-input-normalization.md).

Current primary campaign (2026-10-07): the unchanged full matrix failed at
124 partial warm-up rows. An overlapping diagnostic Dart job triggered the
existing guard, which stopped the driver process group at 01:25:48 UTC. The
run provides no performance acceptance; all gates and #100–#104 remain open.
Finish builds and tests before starting a new frozen campaign. Research:
[failed primary campaign](research/2026-10-07-primary-flatbuffers-campaign.md).

Current follow-up (2026-10-07): bounded native socket views. Twelve fail-first
transport cases reproduce the SDK partial-view copy. Validated malloc-owned
ranges now retain their original allocation through bounded read-only aliases;
a Dart finalization token retains the source through the backing root. An
interim unread metadata field passed VM tests but failed a compiled lifetime
check; the repair passes all 83 focused tests on macOS and Linux arm64. Four
real 16 MiB backpressure cases pass in both VM and compiled AOT modes, retaining
original write addresses through collection and observing final native release.
The exact CI step and its missing-interposer controls pass. Baseline fast,
focused analysis and bounded review pass. Restarted `bin/verify` passes at exit 0:
Rust/VM/consumers, 1,563 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with the unchanged 20 native-only skips. Evidence:
`/tmp/connectanum-bounded-native-alias-token-verify.{log,exit}`. Resulting-head
hosted acceptance remains pending; no total-copy or parity acceptance follows. Research: [bounded native views](research/2026-10-07-bounded-native-socket-views.md).

Current production checkpoint `8503f31c`: [Native Artifacts 37546766311](https://github.com/konsultaner/connectanum-dart/actions/runs/37546766311)
passes five builds and its signed dry-run preview. All fifteen pinned
attestations, thirty preview assets and rendered notes verify. Fresh source-pinned
Apple Silicon and Linux arm64 production consumers pass eight steps each,
including twenty provenance, ten segment, sixteen owned-PPT and 104 mixed-PPT
cases. Both libraries exclude test oracles; source archive and log hashes match.
The other platforms have build/provenance evidence only. No release or performance
acceptance follows; required current-head CI is live. Research: [production
checkpoint](research/2026-10-07-native-production-checkpoint.md).

Current follow-up (2026-10-07): native external-buffer allocation provenance.
Six fail-first regressions show that matching bounds allowed a foreign anchor
to redirect a native read, including an incorrect SHA-256 digest. The resolver
now verifies backing-buffer equality and retains that buffer with its anchor.
The final 20-case suite passes without skips on macOS and Linux arm64, including
equal-content foreign-allocation controls and actual GC retention/collection.
The malloc finalizer and existing copying fallback are unchanged. Fresh quiet
`bin/verify` passes at exit 0, including Rust/VM/consumers, 1,563 benchmark,
4,958 router, 4,751 browser core and 2,829 browser client tests with the unchanged
20 native-only skips. Evidence: `/tmp/connectanum-external-provenance-verify.{log,exit}`.
No total-copy or performance acceptance follows. Both preceding `a9907161`
hosted CI runs now pass all 41 jobs: [push](https://github.com/konsultaner/connectanum-dart/actions/runs/37523093121)
and [PR](https://github.com/konsultaner/connectanum-dart/actions/runs/37523101879).
The publication hold is released; resulting-head hosted checks remain pending.
Master `3bac4cf5` was fetched from both remotes and is already integrated;
`git merge github/master` reports Already up to date. Research: [allocation
provenance](research/2026-10-07-native-external-buffer-provenance.md).

Current diagnostic follow-up (2026-10-07): real Dart SDK backpressure.
The four 16 MiB full/read-only/partial/read-only-partial cases require genuine
EAGAIN, pending flush, positive writes after receiver resumption and exact
received/accepted bytes. Full views retain allocation identity; partial views
use SDK copies. The exact updated Linux CI step passes all three probes and its
absence control; source hashes match. Root analysis and the new tool's explicit
missing-interposer rejection pass. Fresh quiet `bin/verify` passes at exit 0,
including all 1,563 benchmark, 4,958 router, 4,751 core Chrome/Dart2Wasm and
2,829 client browser cases with 20 declared native-only skips. Evidence:
`/tmp/connectanum-sdk-backpressure-verify.{log,exit}`. Final sequential
`bin/test-fast` also passes at exit 0, including all 1,563 benchmark cases and
the unchanged readiness regression. Evidence:
`/tmp/connectanum-sdk-backpressure-final-fast.{log,exit}`. The preceding local
commit `d4d91317` passed both canonical commands and independent interop. Its push is held while preceding
`a9907161` CI's MCP mutation gates remain active. No total-copy, TLS or parity
acceptance follows from this pointer diagnostic. Research: [backpressure](research/2026-10-07-dart-sdk-backpressure.md).

Current follow-up: Dart FlatBuffers fragments and one-copy small RawSocket frames.
The ordinary fragment API preserves encoded CBOR args/kwargs and opaque body
views through valid forward-offset vector layout. Normal serialization and the
wire schema are unchanged. Two public regressions fail before the writer; all
61 focused core cases pass across seven payload-bearing message families.
Three small-frame copy regressions fail before the shared transport repair;
all 43 RawSocket tests then pass, including six codec/size copy/identity cases.
The Linux developer probe now exercises real negotiated RawSocket PPT traffic,
and CI uploads it beside the SDK boundary probe. The source audit corrects the
forced short-write/EINTR boundary to the native SocketBase::Write loop; it does
not establish Dart-level EAGAIN resumption. Partial SDK views, total SDK/TLS/
crypto copies and the full strict parity campaign remain unfinished. Research:
[segmented Dart sending](research/2026-10-06-dart-flatbuffers-segmented-send.md).
The final 36-case real Linux PPT pointer probe passes with exact source hashes;
Rust/Python readers accept contiguous and segmented output for all 25 messages.
The first canonical fast attempt failed the new-test inventory. All four
VM/browser inventories and their shared suite now include that test; all 80
workflow regressions pass with unchanged thresholds. The next fast attempt
failed the existing HELLO/GOODBYE rejection tests because controls used the
fragment writer. Controls and absent-vector messages now return null to retain
the normal serialize path. All 22 unchanged negotiation/rejection tests and
61 core fragment cases pass. The exact Linux CI step also passes both probes
and its missing-interposer control with final source hashes. A fresh canonical
fast run passes the changed paths and then hits the unchanged two-second
worker exit-before-READY deadline in the 1,563-case benchmark suite. Five
isolated repeats pass without code/deadline changes. The failed full fast log
is retained; timing sensitivity is not accepted as proof of a clean suite.
Fresh quiet `bin/verify` now passes at exit 0, including Rust, VM,
consumer/live checks, all 1,563 benchmark and 4,958 router cases, 4,751 core
Chrome/Dart2Wasm cases and 2,829 client browser cases (20 declared native-only
skips). The unchanged worker-readiness case passes in the complete benchmark
suite without deadline or assertion changes. The final independent interop run
also passes after the control fallback repair: 33 upstream fixtures, 42 extended
fixtures and all 25 public messages in contiguous and segmented Dart output.
Fresh sequential final `bin/test-fast` also passes at exit 0, including all
1,563 benchmark cases and the unchanged readiness regression. Evidence:
`/tmp/connectanum-flatbuffers-fragments-verify.{log,exit}`,
`/tmp/connectanum-flatbuffers-fragments-final-interop.{log,exit}` and
`/tmp/connectanum-flatbuffers-fragments-final-fast.{log,exit}`. Earlier failed
logs remain failed evidence. The focused local GLM selector review completed without a concrete
defect; two Qwen attempts reached output limits and are not review evidence.
At preceding published checkpoint `a9907161`, hosted push Full Verify and VM
Coverage pass; PR Full Verify also completes with no observed failure. Both
current CI runs remain live for the MCP mutation gate. Do not push another
checkpoint while those checks are still running. Preceding `b8096fd6` CI runs
were cancelled by that newer push, so their successful individual jobs do not
constitute complete hosted acceptance. This follow-up is committed locally as
`d4d91317`; publication awaits the existing hosted mutation run. Full performance
and remaining milestone acceptance stay open.

Preceding follow-up: native PPT body reuse with empty outer CBOR/MessagePack
keyword maps. The preceding implementation rejected these valid WAMP maps.
Fresh baseline fast checks pass; four new mixed-direction regressions fail
before the repair. All 26 segmented tests now pass, including 810 additional
body/header/direction/route combinations and native input parsing of every
tested header form. They verify body identity, empty-body producer lifetime,
metadata and final fan-out release. Malformed/nonempty maps and invalid
FlatBuffers mixed vectors retain fallback. Research:
[empty PPT keywords](research/2026-10-06-native-empty-ppt-keywords.md).
GuardMalloc passes 87 observed ownership cases with all 141 native/schema
inputs unchanged. Final `bin/test-fast` passes. Fresh `bin/verify` passes at exit 0, including Rust, VM, consumer/live
checks, 1,563 benchmark, 4,958 router, 4,690 core Chrome/Dart2Wasm and 2,829
client browser cases (20 declared native-only skips). Final native input hashes
are unchanged. Evidence: `/tmp/connectanum-empty-ppt-kwargs-verify.{log,exit}`.
Local Qwen review completed; source and regression evidence disprove its
logic-inversion, indefinite-map and wrong-kind hypotheses.

Production checkpoint `b8096fd6` [Native Artifacts 37515940631](https://github.com/konsultaner/connectanum-dart/actions/runs/37515940631)
passes all five builds and its preview. Fifteen attestations, thirty assets,
archive/library checksums and exact rendered notes verify. Fresh commit-pinned
Apple Silicon and Linux arm64 production consumers each pass all four serializers,
native construction, ten segment cases, sixteen live owned-PPT cases and 104
public mixed-PPT cases. Their source archives match. Both production libraries
exclude test oracles, with an eighteen-symbol ffi-test positive control on macOS.
The other three platforms have build/provenance evidence only. This is runtime
correctness, not performance acceptance. Evidence:
`/tmp/connectanum-b8096fd6-platform-provenance.json`,
`/tmp/connectanum-b8096fd6-preview-proof.json`,
`/tmp/connectanum-b8096fd6-production-consumers-proof.json` and
`/tmp/connectanum-b8096fd6-linux-production-consumers-proof.json`.
Hosted FlatBuffers Binding and GuardMalloc pass in PR run 37515806715. The
RawSocket/WebSocket independent-peer inputs match `b8096fd6`; the memory report
passes 87 cases/eight groups, with all 140 tracked sources matching and the
generated lock hash verified. Its synthetic PR merge has `b8096fd6` as a parent.
Uploaded group-log hashes match. Hosted PR Fast Checks also passes. Remaining
required hosted CI is still running without an observed failure. Evidence:
`/tmp/connectanum-b8096fd6-hosted-conformance-proof.json`.

Independent [SDK copy research](research/2026-10-06-dart-sdk-copy-boundaries.md)
identifies conditional partial-view copies before socket writes and binary
masking/ring-buffer copies. A 15-case ordinary serializer diagnostic shows
all five FlatBuffers frames use partial backing views, unlike the ten
CBOR/MessagePack frames. The checked-in Linux pointer probe now confirms the full/partial-view boundary
through actual libc writes and retries. Internal buffering, TLS and total-copy
volumes remain unmeasured. This is not parity or a complete-copy claim.
Complete hosted acceptance and all unresolved milestone criteria remain pending.

Preceding follow-up: native reuse of opaque PPT bodies between CBOR, MessagePack
and FlatBuffers. Nine new regressions fail before implementation: six mixed
directions report ineligible, and three homogeneous controls lose PPT metadata
on raw echo replies. Empty, binary and 128 KiB bodies exercise five forwarding
kinds, producer lifetime and fan-out. Evidence:
`/tmp/connectanum-native-ppt-routing-before.{log,exit}` (exit 101).
The separate virtual-workspace formatter invocation failed before these tests;
the test file was subsequently formatted directly with rustfmt.
Research: [mixed binary PPT forwarding](research/2026-10-06-native-mixed-ppt-forwarding.md).
All 22 segmented tests now pass, including 405 body/direction/route combinations.
The live native-path assertions reproduce six failures against the preceding
production library. They also expose 28 explicit reserved-`wamp` RPC fallbacks
before the Dart repair. Removing those exclusions yields 109 passing public
PPT/E2EE/mixed-eligibility cases, including ordinary routes, progress, ERROR,
custom details, JSON fallback and legacy-library controls. Current canonical
`bin/test-fast` passes at exit 0, including all 1,563 benchmark cases and live
consumer smokes. GuardMalloc passes all 83 observed ownership cases, including
the 22 segmented-forwarding tests, with confirmed loader interposition. Full
`bin/verify` fails at exit 1 on the worker-session case `dispatches calls across
workers and returns result to caller`, after 4,956 other router cases pass.
The failure is an obsolete reserved-scheme native-exclusion assertion. The
test now runs both paths: unavailable native handle preserves all prior
ciphertext/serialization assertions; a native CBOR handle verifies transfer,
routing IDs and no application decoding. Both cases and all 204 worker/live
cases pass together. The local companion's suggested state-leak explanation
was disproved by the exact taken-handle assertion and source. Its test review
cannot observe a real deserialized native result in the mock boss-port unit
fixture; the existing Rust wire and public live checks supply that evidence.
Fresh root analysis and the corrected full `bin/verify` pass at exit 0, including
Rust, VM, consumer/live checks, 1,563 benchmark, 4,958 router, 4,690 core
Chrome/Dart2Wasm and 2,829 client browser cases (20 declared native-only skips).
Browser verification did not run in the earlier failed attempt. Evidence:
`/tmp/connectanum-native-ppt-routing-worker-and-live.{log,exit}`,
`/tmp/connectanum-native-ppt-routing-verify-fixed.{log,exit}` and the earlier
failed `/tmp/connectanum-native-ppt-routing-verify.{log,exit}`.
The preceding
`7d7fab90` fast/full pass is the baseline. Implementation/test hashes are recorded
and unchanged. Evidence: `/tmp/connectanum-native-ppt-routing-fast.{log,exit}`.
GuardMalloc evidence: `/tmp/connectanum-native-ppt-routing-guardmalloc/report.json`.
Hosted coverage blocker: job `112370303567` on `7d7fab90` is explicitly
cancelled at the 45-minute maximum. Library coverage reports and gates are
written at 17:05:38 UTC; cancellation at 17:15:10 interrupts the separate
packaging formatter. These partial results are not complete hosted acceptance.
Only the aggregate VM coverage budget becomes 90 minutes, allowing both
formatter phases and uploads. Every other workflow byte, collection script and
coverage policy is unchanged. All 80 existing verification-tool checks pass;
hosted completion with the new budget remains pending. Evidence:
`/tmp/connectanum-native-ppt-routing-coverage-budget-proof.json` and
`/tmp/connectanum-native-ppt-routing-workflow-tests-final.{log,exit}`.
Research: [GitHub job timeout behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).
Evidence: `/tmp/connectanum-native-ppt-routing-segmented-complete.{log,exit}` and
`/tmp/connectanum-native-ppt-routing-public-fixed.{log,exit}`. A temporary local
refactor accidentally omitted following FFI functions and failed compilation;
they were restored before the passing runs, with the public ABI inventory
unchanged. The failed compile log is retained separately and is not behavioral
evidence. Local Qwen review/debug completed; source and lifetime tests resolve
its mixed-vector and zero-length owner concerns and its inaccurate suggestion
that the live tests should accept the fallback.

Native Artifacts `37489961393` passes all five builds and its dry-run preview at
`7d7fab90`. All fifteen attestations verify, all thirty preview assets match, and
the notes exactly match the renderer. Resulting-body-bridge artifacts remain
pending; no release is published. Evidence:
`/tmp/connectanum-7d7fab90-platform-provenance.json` and
`/tmp/connectanum-7d7fab90-preview-proof.json`.
Both freshly fetched master refs remain `3bac4cf5`, already ancestors of this
branch; no merge is needed. All unresolved milestone criteria remain open.

The preceding follow-up repairs a root-analyzer regression at `8df5c9b3`.
Fresh `bin/test-fast` fails at exit 3 on four `undefined_named_parameter`
errors: the new benchmark test helper passes VM-only `runtime:` parameters
through the public conditional-export API. The helper now uses the public
`libraryPath:` parameter; its prior singleton initialization keeps the metrics
collector and provider on the same native runtime. Production code is unchanged.
Root `dart analyze` and all 28 focused counter cases pass at exit 0. The corrected
`bin/test-fast` and fresh `bin/verify` pass at exit 0, including Rust, VM,
consumer/live WAMP and browser suites (20 declared native-only client skips).
Final Dart/YAML input hashes are unchanged. Hosted acceptance remains pending.
The earlier full `bin/verify` pass did not include root analysis and therefore
did not detect this regression. Evidence:
`/tmp/connectanum-e2ee-pipeline-baseline-fast.{log,exit}` and
`/tmp/connectanum-e2ee-public-helper-{analyze,focused,fast,verify}.{log,exit}`.

The CI workflow now groups automated `codex/` branch runs by workflow, event and
ref, cancelling superseded runs within each group. Master, tags, manual dispatch
and other branches use unique run IDs, avoiding cancellation of pending runs as
well as active runs. Push and PR groups remain separate. Thirteen event/ref
boundary scenarios plus workflow separation pass with the official
`@actions/expressions` evaluator 0.3.61; all 80 verification-tool cases pass.
Every existing job body is byte-identical, including commands, gates and deadlines.
The ownership guide replaces its stale fixed case count and temporary report path
with the reproducible runner command and per-run source/count evidence.
Research: [GitHub concurrency semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)
and [official expression evaluator](https://github.com/actions/languageservices/tree/main/expressions).
Hosted cancellation behavior remains unverified. Local GLM judgment and Qwen
review completed; the evaluator/source checks resolve their inaccurate PR-ref
details. Initial bounded companion requests exhausted output limits and are not
completed reviews. Evidence: `/tmp/connectanum-ci-concurrency-evaluation.json`,
`/tmp/connectanum-ci-concurrency-job-proof.json` and
`/tmp/connectanum-ci-concurrency-tool-tests.log`.

[Native Artifacts 37480119838](https://github.com/konsultaner/connectanum-dart/actions/runs/37480119838)
passes all five builds and its dry-run preview at `8df5c9b3`. All fifteen
source/branch/workflow attestations verify; thirty preview assets match and the
notes exactly match the renderer. A fresh pinned-source standalone consumer
passes all four serializers and the public native API with the Apple Silicon
production library; ten shared-segment and sixteen live owned-PPT cases also
pass. Direct scalar input/growth copies are zero and independently owned
read-only views survive disposal. Production exports contain no `ct_test_*`
oracles; the ffi-test positive control contains eighteen. Other platforms have
build/provenance evidence only. No release is published. Evidence: `/tmp/connectanum-8df5c9b3-platform-provenance.json` and
`/tmp/connectanum-8df5c9b3-preview-proof.json` and
`/tmp/connectanum-8df5c9b3-production-consumers-proof.json`.

The preceding follow-up measures native-provider ciphertext byte-list coercion.
The fail-first matrix passes four Uint8List decrypt cases and fails all eight
ordinary-list cases because their conversions are omitted from the lower bound.
The runtime now counts that isolate-local boundary separately from FFI and native
staging, without changing the native ABI or wire representation. All 28 focused
cases pass, including both ciphers/profiles, immutable bounded subviews, exact
prefix counts on typed rejection, absent staging ABI and counter reset/deltas.
Failed legacy CBOR coercion remains explicitly excluded. The total E2EE pipeline
stays `not_measured`; no parity or complete-copy claim is added.
Baseline `bin/test-fast` passes at exit 0 before this change. All 178 native and
Session provider/profile/key-selection cases pass with the explicit ffi-test
library. Fresh canonical `bin/verify` passes at exit 0, including Rust, VM,
consumers, 1,563 benchmark, 4,935 router, 4,690 core browser and 2,829 client
browser cases (20 declared native-only client skips). The final Dart source/test
hashes are unchanged. Evidence: `/tmp/connectanum-e2ee-wrapper-verify.{log,exit}`.
Earlier focused evidence:
`/tmp/connectanum-e2ee-wrapper-{baseline-fast,regression-before-valid,focused}.{log,exit}`.
The initial regression command used a wrong package-relative path and is not the
fail-first evidence. An initial provider command also named a nonexistent test
and selected a library without the required owned-crypto/staging ABI; its failed
result is retained; the corrected run passes with the explicit ffi-test library.
Evidence: `/tmp/connectanum-e2ee-wrapper-providers-corrected.{log,exit}`.
Hosted push CI `37473576179` on `8feb80c1` now passes WampApp Consumer and
Fast Checks. Complete hosted acceptance remains pending. The superseded PR run
`37464701287`, which failed the old privacy oracle and skipped Full Verify, was
cancelled; its successful older push run and both new-head runs were preserved.


The preceding follow-up repairs a WampApp privacy-test false positive exposed by
the new CI run on `62f99ebb`. Consumer job `112272706961` passes 409 cases and
fails the contact-vault assertion because randomized Base64 ciphertext happens
to contain `bob`. The recorded JSON contains only public encrypted-envelope
metadata; its decoded ciphertext bytes do not contain the plaintext marker.
The repaired test checks the exact public metadata keys and quoted JSON tokens,
while keeping reopen, wrong-password, tamper and account-binding coverage.
Production vault/crypto code is unchanged. The captured old oracle fails, the
new oracle passes, and injected plaintext contacts still fail. All 22 vault
cases pass. Full `bin/test-wamp-app` passes at exit 0, including VM/JS/Wasm tests,
mutation controls and the web build. Fresh canonical `bin/verify` passes at
exit 0, including Rust, VM, consumers, 1,541 benchmark, 4,935 router, 4,690 core
browser and 2,829 client browser cases (20 declared native-only client skips).
Evidence: `/tmp/connectanum-vault-oracle-verify.{log,exit}`.
Evidence: `/tmp/connectanum-vault-oracle-control-proof.json` and
`/tmp/connectanum-vault-oracle-{baseline,focused}.{log,exit}`. The current hosted
run is not accepted as complete CI, and all remaining milestone issues stay open.
Its Fast Checks job now passes with the corrected aggregate budget; WampApp's
old test failure still prevents that PR run's Full Verify and VM coverage.

The preceding `62f99ebb` artifact checkpoint is complete:
[Native Artifacts 37464710421](https://github.com/konsultaner/connectanum-dart/actions/runs/37464710421)
passes all five builds and the dry-run preview. All fifteen source/branch/workflow
attestations verify, the thirty preview assets match, and the rendered notes
exactly match the current renderer with commit-pinned evidence links. A fresh
source archive's standalone public consumer, ten segment tests and sixteen live
owned-PPT cases pass with the Apple Silicon production artifact. All four public
serializers round-trip; direct scalar input/growth copies are zero and retained
read-only views survive disposal. The production library has no `ct_test_*`
exports, with an eighteen-symbol ffi-test positive control. Other platforms have
build/provenance evidence only. The package publish dry run passes. Three
superseded feature CI runs with cancelled Fast Checks were cancelled; current
head CI runs remain active. No release is published. Evidence:
`/tmp/connectanum-62f99ebb-platform-provenance.json`.

The preceding follow-up repairs the separate Fast Checks aggregate budget and
release-preview evidence links. Exact-head PR run `37457588251` on `5f1afae9`
hits GitHub's 20-minute Fast Checks ceiling; its preceding live consumer smoke
finishes at 20m12.701s, 1.937s before cancellation. Only this job's aggregate
budget becomes 45 minutes. Commands, suites, test deadlines and gates stay
unchanged. All 80 verification-tool checks pass. The release-note regression
first fails both missing-link cases and then passes all three tests; conformance,
benchmark and ownership links use the chosen repository/server and exact commit.
The ownership guide now compares pinned Dart entity reconstruction with a C
producer-thread transaction/lease policy and explicit copy fallback. All eight
workspace manifests remain free of ObjectBox dependencies.
No parity or complete copy-coverage claim is added. Fresh canonical `bin/verify`
passes at exit 0, including Rust, VM, consumers, 1,541 benchmark, 4,935 router,
4,690 core browser and 2,829 client browser cases (20 declared native-only client
skips). Evidence: `/tmp/connectanum-release-readiness-verify.{log,exit}`.
Hosted acceptance and the resulting commit's release preview remain pending.

[Native Artifacts 37457831556](https://github.com/konsultaner/connectanum-dart/actions/runs/37457831556)
passes on `5f1afae9`: all five platform builds and the release-preview job.
All 15 archive/checksum/manifest attestations independently verify against that
exact source, branch and workflow; every checksum and manifest source matches.
The fresh standalone consumer passes ordinary JSON/CBOR/MessagePack/FlatBuffers
round trips. Its native public-API check uses the downloaded Apple Silicon
production library, which also passes ten shared-segment ABI/lifetime cases and
all sixteen owned
CBOR/MessagePack RPC/pub-sub runner cases over RawSocket/WebSocket. Direct scalar
construction reports zero input/growth copies, and retained read-only control
views survive caller/frame disposal. The production library exports no
`ct_test_*` symbols; the ffi-test positive control exports eighteen. The other
four artifacts have provenance/build evidence, not runtime execution evidence.
The preview contains all thirty expected assets but lacks the required evidence
links; the renderer repair above addresses that gap. The tag is preview metadata;
no release is published. Full Verify and VM coverage in the PR run are skipped
after the Fast Checks cancellation; binding, browser coverage, GuardMalloc and
WampApp consumer checks pass. Issues #100–#104 remain open.
Evidence: `/tmp/connectanum-fast-budget-repro.json`,
`/tmp/connectanum-current-platform-provenance.json`,
`/tmp/connectanum-current-production-oracle-proof.json`,
`/tmp/connectanum-current-public-consumer-run.{log,exit}` and
`/tmp/connectanum-current-production-owned-{segments,ppt}.{log,exit}`.

The preceding CI follow-up repairs the aggregate Full Verify job budget. Hosted
run `37437589411` on `c3dbc9cb` reaches core browser tests after 40m51s and
continues passing cases until 0.665s before GitHub's 45-minute cancellation.
The annotation explicitly reports the maximum job execution time. The observed
setup/VM/consumer time plus the existing bounded browser commands needs about
70 minutes. Only this job's aggregate budget becomes 90 minutes; suite selection,
LLVM checks, browser command deadlines, per-test deadlines and gates are unchanged.
All 80 verification-tool regressions pass. Fresh `bin/verify` passes at exit 0,
including Rust, VM, consumers, 1,541 benchmark, 4,935 router, 4,690 core browser
and 2,829 client browser cases (20 declared native-only client skips). The
preceding sequential fast result remains the baseline for unchanged product
inputs. Hosted acceptance remains pending; the current-platform artifact
checkpoint is recorded above.
Evidence: `/tmp/connectanum-full-verify-budget-repro.json` and
`/tmp/connectanum-c3-full-verify-{job,annotations}.json`, plus
`/tmp/connectanum-full-verify-budget-canonical.{log,exit}`.

The preceding follow-up addresses complete native construction of the benchmark
CBOR/MessagePack PPT fixture. Its `native_buffer` group previously held only the
body in native memory and later serialized a Dart map. The constructor now writes
the complete existing PPT shape in native storage, counts the single body input
copy and retains the frozen span through the shared submission path. Two owner
cases first fail and then pass. All 140 reference vectors, 596 focused/aggregate
cases and 46 live matrix cases pass; 93 mutation-runner checks pass with one
declared skip. Frozen views survive caller disposal and rejected Session calls
release their owners. All 1,541 Linux benchmark cases pass without native skips.
Targeted coverage is 2,981/3,033 lines (98.286%), above the unchanged 98% gate;
the codec is 122/122 lines. There are no benchmark findings; the other unmeasured
packages prevent whole-repository coverage acceptance. Existing typed and CBOR
encryption cases also pass; the new constructors use the unencrypted custom
typed scheme. First canonical runs fail a stale exact mutation-input assertion;
the exact source/test/fixture inventory is repaired without relaxing thresholds.
Fresh full `bin/verify` passes at exit 0, including Rust, VM, consumers, 1,541
benchmark, 4,935 router, 4,690 core browser and 2,829 client browser cases
(20 declared native-only client skips). The repaired fast run hits an existing
two-second worker-readiness timeout while fast/full checks overlap. That
unchanged case passes five focused repeats, full verify and a fresh sequential
`bin/test-fast` at exit 0. Failed runs remain failed evidence; no timeout or
cancellation assertion changes. Evidence:
`/tmp/connectanum-native-construction-{verify-final,fast-sequential}.{log,exit}`.
Complete copy instrumentation and parity remain open. This constructor
checkpoint is pushed to both remotes as `8937a5d4` in draft PR #105.

The preceding follow-up adds shared encoded native-segment submission for CBOR
and MessagePack. The optional ABI retains frozen input handles on all outcomes
and keeps empty producers alive through write/flush. Dart has capability probes,
tracked submission, a Finalizable input holder and generic lazy owned PPT.
Eligible CBOR/MessagePack CALL/PUBLISH sends retain exact payload spans, count
small metadata copies and reject forged/replaced owner views. Benchmark
pre-encoded spans now keep that exact owner anchor for all three codecs.
All 18 native ownership/network cases, 10 new Dart transport/API cases and 131
focused benchmark/live cases pass. All 17 combined new API/existing frame
cases also pass on Linux arm64. All 73 GuardMalloc cases pass with 141 matching
native/dependency/schema inputs. The complete 281-case native FFI suite passes.
Eight live native Session cases also pass for CBOR/MessagePack RPC/pub-sub over
both transports on macOS and Linux. Linux benchmark coverage includes all 1,504
prior cases, the eight new Session cases and child-process build probes: it is
2,926/2,978 lines (98.254%), above the unchanged 98% gate with no benchmark
finding. This targeted report does not accept whole-repository coverage.
Mutation inventories include the new part/test/support file and all 92 inventory
checks pass with one declared skip. Fresh canonical `bin/test-fast` and
`bin/verify` pass at exit 0, including Rust, VM, consumers, 1,512 benchmark,
4,935 router, 4,690 core browser and 2,829 client browser cases (20 declared
native-only client skips). Evidence:
`/tmp/connectanum-shared-codec-{fast,verify}-recovered.{log,exit}`.
The first canonical runs exhausted the host filesystem during browser
compilation and benchmark temporary-directory creation. Only this worktree's
disposable Rust incremental caches were cleared (about 6 GiB); the failed runs
are retained and are not accepted as clean verification. An earlier baseline
attempt overlapped implementation and caught a transient switch-type
compilation error; that attempt is not claimed as a clean baseline. At that
checkpoint, dynamic native construction and complete copy/parity evidence were
pending; the constructor is now implemented above. Shared submission is pushed
to both remotes as `425c9e62`; at the last inspection both package-publish
dry-runs pass and its two hosted CI runs are queued.

The preceding follow-up implements the paired serializer campaign executor on top
of pushed runtime repair `87688b8c`. It generates the 48-case primary matrix,
balanced interleaved codec order, three warmup and seven measured passes. One
driver/worker remains alive across all passes; flushed JSONL avoids rebuilding
aggregate history. The executor retains partial/cancelled evidence, checks input
hashes before/after and confirms process-group teardown. The evaluator rejects
diagnostics, incomplete execution and duplicate matrix dimensions. Real reports
now retain the actual WAMP codec/TLS/PPT/construction settings for attribution.
Focused Python, Rust and benchmark-config checks pass. The real Linux diagnostic
completes all 120 reports with stable client/server PIDs and driver exit 0. All
input hashes match and per-pass JSONL exactly reproduces the raw driver stream.
The comparison correctly exits 1 with short/diagnostic and missing-copy findings;
no primary parity evidence is accepted. SDK/TLS/transcode copy
coverage remains open under #103; shared CBOR/MessagePack submission is now
implemented in the follow-up above.
Full `bin/verify` passes at exit 0, including Rust, VM, consumers, all 1,502
macOS benchmark cases, 4,935 router, 4,690 core browser and 2,829 client browser
cases (20 declared native-only skips). The final report-metadata predicate uses
the existing WAMP parser so uppercase aliases also retain configuration; a fresh
complete Rust benchmark suite passes after that small correction. Evidence:
`/tmp/connectanum-flatbuffers-campaign-verify.{log,exit}` and
`/tmp/connectanum-flatbuffers-campaign-rust-final-tests.{log,exit}`.

The complete Linux benchmark suite passes all 1,502 cases with no native skips.
Fresh benchmark library coverage is 2,925/2,979 lines (98.187%), above its
unchanged 98% gate, with no benchmark-specific file/package/component finding.
This targeted report does not accept the full repository's coverage job: other
packages are intentionally unmeasured. Evidence:
`/tmp/connectanum-flatbuffers-campaign-linux-bench-coverage.{log,exit}` and
`/tmp/connectanum-flatbuffers-campaign-linux-bench-coverage/{lcov.info,summary.json}`.

The first Linux diagnostic was interrupted and retained after revealing that the
client helper recycled after every workload: all 31 reports use distinct client
PIDs while the server PID stays constant. Reuse is now explicit for successful
RPC/pub-sub rows; default, cancellation and failed workloads still recycle.
Process identity is checked across all warmup/measured reports. All 48 focused
lifecycle/worker tests, 23 comparator tests and 11 executor tests pass. The
corrected diagnostic covers four codec-paired cases with RawSocket/WebSocket,
Dart/native, clear/TLS and all three construction groups. It completes three
warmup and seven measured passes, 40 reports per codec. Source is explicitly
dirty/diagnostic and windows are below policy; the 370 comparison findings remain
failures. Rust driver/native builds precede execution; no build/test/mutation/model
job overlaps the measured run. Evidence: `/tmp/connectanum-flatbuffers-campaign-diagnostic-02`,
`/tmp/connectanum-flatbuffers-campaign-worker-reuse-tests.{log,exit}` and
`/tmp/connectanum-flatbuffers-campaign-rust-tests.{log,exit}`. The complete default
schedule is prepared in the isolated Linux fixture: 48 cases and 1,440 rows,
without claiming execution of that primary matrix. Companion review's duplicate
RSS-stop concern is disproved by the cached stop future and its identity test;
the GLM judge finds no blocker once stable PID attribution is confirmed.

Both hosted Fast Checks on `87688b8c` pass, confirming the runtime repair. PR
consumer/browser coverage, package publish dry-runs, FlatBuffers binding,
GuardMalloc and several mutation gates also pass. Other required jobs are still
running or queued. Hosted checks for the campaign commit remain pending;
no new milestone issue is closed.

## Shared-runtime test teardown (2026-10-06)

The preceding follow-up fixes the Linux benchmark test runtime leak at `1aafa099`.
Its hosted Fast Checks job failed eight cases after the new native E2EE factory
tests left the process-wide client runtime running. Provider release frees keys
and sessions; it does not shut down that shared runtime. A same-process Linux
reproducer fails six accounting cases. Adding the existing factory-test
`NativeClientRuntime.shutdownShared` teardown makes all 39 factory, accounting,
router-config and remote-auth cases pass, with no native skips. All 1,498 full
Linux benchmark cases now pass, also without native skips. The fresh repository
baseline and full `bin/verify` pass at exit 0. Verification includes Rust, VM,
consumer smokes, 1,498 macOS benchmark, 4,935 router, 4,690 core browser and
2,829 client browser cases (20 declared native-only client skips).
Focused formatting and analysis pass. Companion teardown-order concerns were
checked against the test engine and runtime sources: per-test cleanup finishes
before group cleanup, provider release is synchronous, and construction failures
release partial handles. The repair is pushed to both remotes as `87688b8c`.

Both `1aafa099` hosted browser coverage jobs pass. The downloaded push artifact
is retained at `/tmp/connectanum-flatbuffers-ci-1aafa-browser-artifact`.
Both hosted Fast Checks jobs fail the same eight runtime-lifecycle cases;
their logs are retained separately. Seven strict package publish dry-runs pass
with zero warnings on that head. Required hosted acceptance of the teardown
repair remains pending; no additional milestone issue is closed.
Evidence: `/tmp/connectanum-flatbuffers-campaign-baseline.{log,exit}`,
`/tmp/connectanum-flatbuffers-ci-1aafa-runtime-leak-{repro,fixed}.{log,exit}`,
`/tmp/connectanum-flatbuffers-ci-1aafa-linux-bench-fixed.{log,exit}` and
`/tmp/connectanum-flatbuffers-ci-runtime-teardown-verify.{log,exit}`.

## Metric-validation checkpoint (2026-10-06)

The preceding follow-up repairs benchmark copy-report validation and missing VM
isolate handling on top of pushed checkpoint `dbeda203`. Fresh `bin/test-fast`
passes; all 60 focused cases and six fail-first regressions pass after the repair.
Linux benchmark coverage passes its unchanged 98% target at 98.219%; fresh
browser coverage passes both gates. Fresh full `bin/verify` passes at exit 0,
including Rust, VM, consumers, 1,498 benchmark, 4,935 router, 4,690 core browser
and 2,829 client browser cases (20 declared native-only client skips).
The unchanged native implementation retains the 70-case GuardMalloc evidence
from the ordinary-routing checkpoint below.
Hosted CI at `dbeda203` failed both VM coverage jobs because benchmark coverage
was 97.404% against its unchanged 98% gate. One browser job exceeded its 900-second
command limit; the same-head PR browser job passed all coverage gates. These are
different failures from the preceding-head runner shutdowns. Package publish
dry-runs remain pending. No paired performance campaign or parity result exists.

## Coverage repairs and master synchronization (2026-10-06)

Both remotes resolve current `master` to `3bac4cf5`, already an ancestor of the
working branch. The user-requested merge check reports `Already up to date`.

The [push coverage run](https://github.com/konsultaner/connectanum-dart/actions/runs/37382280300)
and [PR coverage run](https://github.com/konsultaner/connectanum-dart/actions/runs/37382287625)
agree on the benchmark VM coverage shortfall. The PR browser artifact passes
core 96.136% and client 96.430%; the push job continued completing crypto tests
until the whole-suite deadline expired. The core command now has a bounded
1,200-second limit, with a 30-minute job budget for both suites and report upload.
Per-test deadlines, full suite selection and coverage policies are unchanged.

A separate six-case reproducer proves that missing boundary metadata can claim
complete copies, negative/fractional counts can be accepted, NaN/infinity can
crash aggregation, and a system-only VM process can throw on an empty application
isolate list. Reports now require explicit valid boundary metadata and exact,
finite, nonnegative byte counts. Invalid counts stay unmeasured; known router
copies remain a lower bound. Isolate fallback safely returns no application ID.
The reproducer now passes. Sixty focused tests pass, including native/Dart typed
E2EE factory interoperability, direct profile/construction rejection before any
session opens, malformed payload correlation and incomplete/TLS metric reports.
Focused analysis and all 80 verification-script tests pass. Companion review
claims were checked against source: nonempty application fallback is unchanged,
native tests resolve the test-enabled artifact and did not skip, malformed
identity tests explicitly assert false, and missing TLS totals remain unmeasured.
Evidence: `/tmp/connectanum-flatbuffers-db-ci-baseline.{log,exit}`,
`/tmp/connectanum-flatbuffers-metrics-{fail-first,regressions-fixed}.{log,exit}`,
`/tmp/connectanum-flatbuffers-ci-{focused-tests,script-tests}.log`.
Fresh macOS benchmark coverage collects all 1,498 passing cases. Its 97.043%
report leaves Linux process-stat paths unexecuted. Linux arm64 passes all 60
focused cases and 1,496 full-suite cases plus the two router-config cases after
repairing the isolated fixture. The initial fixture contained AppleDouble files
that the Dart test loader tried to decode; removing those generated files repaired
discovery. The full Linux attempt then found the missing `bench_router.json`;
restoring the checked-in config and rerunning those two cases passes. These
fixture failures are preserved separately from implementation evidence.
The combined Linux benchmark report covers 2,923/2,976 lines (98.219%) with no
benchmark-specific policy failure. The unchanged whole-repository policy rejects
missing non-benchmark data in these benchmark-only reports; this is a targeted
benchmark measurement, not acceptance of the full VM coverage job.
Fresh `bin/test-browser-coverage` passes at exit 0: core 96.136% and client 96.430%,
with the full suites, existing thresholds and 20 declared native-only client
skips. Evidence: `/tmp/connectanum-flatbuffers-ci-bench-coverage.log`,
`/tmp/connectanum-flatbuffers-ci-linux-bench-coverage-clean.log`,
`/tmp/connectanum-flatbuffers-ci-linux-bench-fixture-repair.log`,
`/tmp/connectanum-flatbuffers-ci-linux-bench-{lcov.info,summary.json}` and
`/tmp/connectanum-flatbuffers-ci-browser-coverage.{log,exit}`.
Fresh full `bin/verify` also passes at exit 0, including 4,682 core VM, 4,935
router, 1,498 benchmark, 4,690 core Chrome/Dart2Wasm and 2,829 client browser cases
(20 declared native-only client skips).
Evidence: `/tmp/connectanum-flatbuffers-ci-verify.{log,exit}`.
No additional milestone issue is closed; hosted acceptance for this follow-up
remains pending.

## Ordinary CBOR/FlatBuffers routing and JSON input ownership (2026-10-06)

Native envelope replacements for INVOCATION, RESULT, EVENT and ERROR now reuse
ordinary CBOR arguments and keywords in both CBOR/FlatBuffers directions.
Optional ABI v1 queries borrow the source message and check destination codec
eligibility. CBOR-to-FlatBuffers validates the pinned container bounds and shape
without reconstructing application collections. The send rechecks the actual
native connection before enqueueing; incompatible attempts preserve the source
handle and emit no bytes. Cross-worker destinations can now use this path.
PPT/transparent payloads retain their existing behavior. Custom INVOCATION
options still select the existing metadata-preserving envelope path; a reproduced
test failure caught and repaired the overly broad non-progressive fast path.

The live mixed-codec tests exposed JSON's mutation of caller-owned binary List/Map
entries into Base64 strings. Removing that redundant mutation preserves typed
and immutable Uint8List containers and allows later FlatBuffers encoding.
A second fail-first regression found repeated materialization of a transfer
inside shared container aliases. A payload-local identity cache now shares its
encoded value across arguments and keywords. TransferableTypedData remains
one-shot; the cache neither extends its lifetime nor promises subsequent reuse.

macOS passes 87 focused native/routing/PPT cases and 29 JSON ownership regressions.
Native pointer/subrange oracles cover four argument shapes and five replacement
envelopes in both directions. GuardMalloc passes 70 observed cases. Linux arm64
passes all 12 forwarding tests and the real network test's 20 RawSocket and
masked/fragmented WebSocket scenarios. Linux passes all 116 focused Dart cases,
including the older-library fallback without missing-native skips.
The broader Linux runtime attempt was stopped while an unrelated existing slow
external-lease network test was still running; it is incomplete evidence.
The initial local full verification was stopped after finding the transfer-alias
regression. The next run passed VM, native, router and benchmark checks but
failed 14 browser cases because TransferableTypedData is unavailable there.
These alias tests now declare `testOn: 'vm'`, matching the existing serializer
tests; all 15 byte-container regressions pass in Chrome/Dart2Wasm. Fresh full
verification on that test-platform correction passes at exit 0: 4,682 core VM,
4,935 router, 1,456 benchmark, 4,690 core browser and 2,829 client browser cases
(20 native-only client skips). Linux's repeated
root-level parallel invocation also exposed the native runtime's global singleton
test conflict; all 116 cases pass with the router's prescribed concurrency 1.
Evidence: `/tmp/connectanum-flatbuffers-cbor-routing-`
`{dart-live-final,linux-native-focused,linux-dart-platform-serial,verify-platform-final}.log`,
`/tmp/connectanum-flatbuffers-json-{immutability-platform-final,immutability-browser-final,ttd-alias-tests-repro}.log`,
and `/tmp/connectanum-flatbuffers-cbor-routing-guardmalloc/report.json`.
Companion review findings were checked against source and tests: negotiated
connection codecs are immutable, native submission revalidates the destination,
recursive JSON output construction already existed, and transparent wire
encoding is unchanged. No additional issue is closed. #100 still needs complete
copy attribution; SDK, masking, TLS and other codec conversions remain unknown.

## Portable crypto copies and typed XSalsa size repair (2026-10-05)

The portable AES provider writes directly into its final nonce-prefixed output;
the CBOR providers avoid redundant plaintext and outbound ciphertext clones.
Optional isolate-local workload windows record explicit portable-provider copies
separately from native staging and FFI bridges. They include the remaining mutable
XSalsa output wrapper and successful/partial failed ciphertext-list coercion.
Crypto dependency internals, native-provider coercion, other isolates and
serializer/framing copies remain unknown; E2EE totals still fail closed.

An authentic 2 MiB typed XSalsa input exposed pinenacl's implicit 1 MiB receive
wrapper cap, despite the declared 64 MiB profile. The typed provider now uses the
public explicit-length body wrapper and nonce API with the same primitive and
existing profile preflight. Old-limit/next-byte/2 MiB cases, all truncated
nonce/tag lengths, tampering, sliced inputs and native/portable 2 MiB parity pass.
The CBOR receive behavior is preserved. Explicitly identical peer codecs now
report homogeneous routes; genuine CBOR-to-JSON transcodes stay unmeasured.

The fresh baseline `bin/test-fast` passed. macOS focused crypto tests and all 82
native-provider cases pass; Linux arm64 passes 234 focused cases and five live
worker scenarios. A full verification started before finding the size defect was
terminated, with its partial log retained; the final implementation's fresh
`bin/verify` passes at exit 0, including 1,456 benchmark tests, 4,923 router tests
and Chrome/WebAssembly (4,675 core; 2,829 client with 20 native-only skips).
Current-head hosted checks remain queued; the older run ended cancelled.
Evidence: `/tmp/connectanum-flatbuffers-portable-crypto-`
`{focused-final,provider-final,linux-focused-final,linux-live,verify}.log`,
`/tmp/connectanum-flatbuffers-xsalsa-{large-repro,limit-test-repro,limit-final}.log`.
No additional issue is closed and no parity result is accepted yet.

## Native crypto staging and typed benchmark profiles (2026-10-05)

XSalsa now constructs its unchanged nonce/tag/ciphertext wire format with detached
in-place crypto. It avoids the previous payload shift and second output copy;
copied decryption stages only the ciphertext body. An independent optional metrics
ABI v1 records actual native plaintext/ciphertext staging, including authentication
failures. Dart snapshots also count this runtime isolate's explicit crypto FFI
copies. Unknown or older metric ABIs leave native fields unavailable safely.

The benchmark worker and Rust orchestrator accept explicit typed FlatBuffers E2EE
RPC/pub-sub with all three construction modes, select the matching Dart/native
version-2 provider, and retain the existing CBOR default. Typed E2EE file transfer
is rejected. Known staging counts remain a lower bound with explicit process and
isolate scopes; serializer/framing, Dart crypto and other isolate bridges remain
unmeasured. Encrypted rows retain `e2ee_copy_bytes=not_measured`; the declared
comparison policy/evaluator rejects incomplete totals or an encrypted exemption.

Four native crypto compatibility/copy-oracle tests pass on macOS and Linux arm64.
Both platforms pass 82 native-provider tests and the two live 64 KiB encrypted
typed RPC metric cases. Four benchmark metric tests, 65 runner tests and 15
comparison tests pass. Full `bin/verify` also passes, including all 1,452 benchmark
cases. Evidence: `/tmp/connectanum-flatbuffers-crypto-verify.log`,
`/tmp/connectanum-flatbuffers-crypto-guardmalloc-final/report.json`, and
`/tmp/connectanum-flatbuffers-crypto-linux-{native,provider,live}.log`.

Earlier Linux CI at `b5ab660c` failed Full Verify and Dart VM Coverage because
two native benchmark test files ignored the test-enabled artifact under
`target/ffi-test/release` after the runner cleared `CONNECTANUM_NATIVE_LIB`.
A clean Linux arm64 fixture reproduces the same five failures. Commit `ecaa43d4`
resolves the artifact explicitly; all 14 focused cases then pass with no skips.
The earlier Rust churn failure passed on retry. These are local repair results;
hosted acceptance still needs the resulting feature head. Issues #100–#104 remain
open, including SDK/TLS/transcode copy coverage and the missing paired campaign.

## External-loan terminal-path acceptance (2026-10-05)

The native transaction-like producer now proves release exactly once on its
registering thread after a successful write whose receipt observer was disposed,
a real bounded transport queue rejection, missing-destination rejection, and
fan-out interrupted by peer reset, local connection close or runtime shutdown.
RawSocket and WebSocket cases consume and verify a payload prefix before
termination, proving partial progress. No caller-held view masks writer retention
in the successful unobserved-send and queue/cancellation cases. Shutdown keeps an
independent exported view readable until its final release. Existing lease and
ABI tests cover construction-failure rollback, byte/count limits, wrong-thread
operations and safe rejection by older/incomplete libraries.

The ownership documentation distinguishes legacy event-loop `drain()`, FIFO
`drainWrites()`, observer disposal and final producer cleanup. The implementation
is storage-agnostic; ObjectBox integration remains outside core. Local evidence:
`/tmp/connectanum-flatbuffers-97-{fast,verify,native-network,memory-runner}.log`
and `/tmp/connectanum-flatbuffers-97-guardmalloc/report.json`. Issue #97 is
complete; hosted conformance/release acceptance remains under #102/#104, and
unmeasured SDK/TLS/transcode copies plus missing performance evidence keep #103
open.

## WAMP RSS window-boundary correction (2026-10-05)

The benchmark RSS sampler now waits for an in-flight periodic read and takes a
final sample before returning both current and sampled-peak RSS from that same
window boundary. Client and server records use that snapshot before VM profiling
queries can add work outside the measured window. Server diagnostics retain an
end-of-workload `ProcessInfo` value on non-Linux platforms; Linux rows remain
missing when `/proc` cannot supply the boundary sample. A deterministic
delayed-reader test covers the race and idempotent stop. `bin/test-fast` and
full `bin/verify` pass at exit 0 on the RSS race correction. After the
non-Linux diagnostic fallback refinement, the focused metrics suite and
`dart analyze packages/connectanum_bench` also pass. An 8-workload Linux arm64
smoke over RawSocket/WebSocket and JSON/MessagePack/CBOR/FlatBuffers emits numeric
client/server RSS with current RSS no higher than sampled peak. It is a short
wiring smoke (640 samples per workload), not parity evidence. The smoke also
confirms the existing Dart-managed transport-copy `not_measured` blocker; no
benchmark rows are accepted. At that checkpoint all milestone issues were open.
This correction is in pushed checkpoint
`e1ee796a`; exact-head hosted CI evidence remains pending.

## Dart transport-copy attribution follow-up (2026-10-05)

The Dart benchmark worker now records Connectanum-owned RawSocket frame
assembly, small-fragment coalescing, pre-handshake queue, and WebSocket fragment
coalescing copies per workload window. The report identifies uninstrumented SDK
socket writes, WebSocket masking, and TLS copies. `bench_main` merges client and
router deltas and reports numeric `transport_copy_bytes` only when both sides
have complete cleartext coverage. The paired evaluator rejects missing/partial
coverage, unknown boundaries, and not-applicable transport totals. Focused
metric/evaluator tests and `bin/test-fast` pass. Dart SDK write/masking
internals, TLS copies and mixed-serializer transcodes remain unmeasured; no
parity campaign exists, so issue #103 and issues #97, #100–#104 remain open.

## Native transport copy-counter follow-up (2026-10-05)

Commit `f7387de0` adds optional C/Dart FFI snapshots for native transport
copies, counting explicit Dart-to-native send copies, WebSocket mask and
coalescing payload copies, and Rustls plaintext accepted bytes. The Rustls
counter reports accepted input volume, not a measured memory copy. Client and router
benchmark snapshots use before/after deltas and combine their measured native
path traffic. Focused Rust tests, client metric-delta tests and package analysis
pass. A fresh `bin/test-fast` passes, including the release FFI build and live
RawSocket/WebSocket WAMP matrix. Full `bin/verify` also passes, including the
Chrome WebAssembly, WAMP, consumer and smoke checks. A paired campaign
evaluator and machine-readable relative parity policy now have eleven focused
unit tests. A working-tree follow-up adds two-process resource accounting and
matching evaluator tests; it requires client plus benchmark-server evidence and
rejects missing metrics. The evaluator does not execute benchmarks or create a
result.
Dart-managed socket/TLS paths and mixed-serializer transcodes remain
unmeasured, so this is partial attribution only; issue #103 remains open and
no FlatBuffers parity or end-to-end zero-copy claim is accepted.

## WAMP benchmark process-resource attribution follow-up (2026-10-05)

The comparison evaluator previously used only the client worker for CPU,
allocation, GC and peak RSS even though the WAMP server runs in a separate Dart
process. Its resource ratios now require both `client_process_metrics` and
`server_process_metrics`, retaining both blocks and comparing combined CPU,
allocation and GC pause per operation plus summed sampled peak RSS. The server
block describes the process hosting `RouterBinding` and the HTTP benchmark
controller. Each workload gets one throwaway warm-up operation before the server
measurement window so lazy router isolates exist before profiling starts. The
collector profiles every application isolate present when the window begins
and fails closed if that set changes or GC timeline evidence is incomplete.
Process CPU ticks and RSS sampling use Linux `/proc`; missing platform metrics
block the row. Eleven focused evaluator tests pass, as do the Rust orchestrator
test target and Dart isolate-selection tests. A live macOS smoke run emits both
process blocks and allocation/GC metrics, while CPU/RSS remain missing as
expected. The benchmark campaign still has no generated manifest or measured
parity result, and the Dart-managed TLS/socket and mixed-codec copy paths remain
unmeasured.

## Session native-owned typed FlatBuffers PPT path (2026-10-05)

`NativeOwnedBuffer.asFlatBuffersPptPayload()` now lets an application pass an
already encoded typed FlatBuffer to `Session.callLazyPayload` or
`Session.publishLazyPayload`. On an established native FlatBuffers session, an
opaque typed PPT CALL/PUBLISH retains the exact frozen payload owner in a
composed native frame. Profile checks run before the fast path; only the WAMP
control envelope is rebuilt. The normal path remains for transparent WAMP
payloads, other serializers, encrypted PPT and ineligible payloads. This keeps
application payload bytes out of Dart serialization buffers on the eligible
path; later transport framing, masking, TLS or encryption may still copy.

RawSocket and WebSocket integration tests verify nested lazy-owner anchors,
session/profile enforcement and immediate disposal of the caller's buffer after
queueing. The benchmark runner now passes native-buffer and pre-encoded
FlatBuffers payloads through the same owned-view API. A new 12-case live matrix
covers native RawSocket RPC/pub-sub, FlatBuffers WAMP envelopes, all three PPT
serializers and two owned construction modes over two iterations. A runner unit
test checks exact view/owner identity and cleanup after a rejected call. Core
tests verify control-only encoding does not read the lazy payload. Both
`bin/test-fast` and full `bin/verify` pass on the current candidate, including
Chrome WebAssembly, live WAMP integration and consumer smoke checks. These are
correctness and ownership results, not end-to-end throughput evidence; no
FlatBuffers-versus-CBOR/MessagePack parity result is accepted, so issue #103
remains open. At that checkpoint, all ten milestone issues remained open pending
their acceptance evidence.

## Checkout and authorization

The managed worktree uses `codex/flatbuffers-zero-copy`; the native Session
fast-path implementation is committed and pushed as `f569e9b4`, following
`274df37c` and `152898d7`. The benchmark-runner integration is committed and
pushed as `9620cfbe`; `bin/test-fast` and full `bin/verify` pass at that
checkpoint. The external-lease test follow-up is committed and pushed as
`a28e92c4`. Its hosted run exposed the two CI defects described above; local
corrections now pass `bin/test-fast`, full `bin/verify`, and both mutation
inventory validations. These corrections are committed in `f7387de0`; fresh
exact-head hosted checks are running. Earlier exact-head hosted runs reported
Fast Checks failures on `274df37c`. It started at
`54eafc5f` and integrates released master `3bac4cf5`. The primary checkout's
independent work remains untouched.
Feature commits, pushes and draft PR updates are authorized; releases, version
bumps, publication and merging master are not authorized. Actual ObjectBox
integration belongs in a separate adapter. Core provides generic memory
contracts. The earlier coverage/mutation objective is deferred.

## Accepted deferred Session checkpoint (0cf9e65e)

The pushed checkpoint connects opt-in native consuming typed E2EE to actual
Session receives. Both native transports expose `consumeTypedE2eePayloads`,
disabled by default and locked once opening starts. Eligible RESULT/EVENT/
INVOCATION metadata can be read before payload exports; application loading
selects native decrypt first. Generic `LazyMessagePayload.deferred` shares values
or terminal error/stack across related views. Ordinary transport behavior stays
eager. Original unexported ciphertext becomes unavailable after consumption.
Wire export forces a safe copied fallback; wire mutation clears its native anchor.
The following detailed records describe successive historical validation attempts;
the current uncommitted follow-up is the key-policy repair below. The final
sequential canonical/browser audits accept this checkpoint, while its earlier
failed attempts remain failed evidence.

Fail-first regressions caught 24 key-policy mutation failures, two stale
provider/context views, recursive wire loading and explicit classic decoding;
the fixes have passing controls. Expanding real older-ABI coverage caught 28 CBOR
RESULT/EVENT failures: CBOR byte strings become `Uint8Buffer`, rather than
`Uint8List`. The fallback now validates `CborBytes` directly; four extra cases
reject numeric arrays, short byte strings and non-binary values before policy.

Focused verification passes 2,227 current-library VM runtime/binding cases,
371 older-library runtime cases and 115 core lazy cases on each of VM, Chrome JS
and Chrome WASM. The production Apple Silicon library passes the 228-case new
Session matrix. Actual pointer checks prove contiguous RawSocket AES reuse for
all three binary serializers; WebSocket exercised copied fallbacks. Initial
fixture-only JSON/read-only expectation failures remain preserved. These are
correctness/ownership checks, not benchmark parity acceptance.

The first canonical fast run failed workspace analysis on eight fixture API/
import errors; targeted analysis had missed the part-file context. The fixture
now reuses the existing JSON codec and default shared native runtime. Workspace
analysis exits 0. Both initial mutation runs failed closed on eight stale
equivalence records. All eight operators/contexts and paired-field invariants
were rechecked, with no new exclusions or gate/deadline change:
`/tmp/connectanum-flatbuffers-session-deferred-equivalence-rebase.json`.
The repaired fast run then caught the new part missing from two native mutation
targets' support inventories. Its failing tooling test is preserved; adding the
part to both inventories passes that exact control. The initial repaired lazy
campaigns observed three actual VM timeouts: two deleted recursion guards and
deleted graph-copy memoization. Bounded loader assertions and the existing
traversal-budget graph turn all three into completed assertion failures on VM
and Chrome JS at the unchanged deadlines. All six exact mutant kills, four
197-case baseline/restored controls and staged/source/log hashes pass audit:
`/tmp/connectanum-flatbuffers-session-deferred-loop-bound-completed-audit.json`.
The known-failed campaigns were stopped before applying these test-only repairs;
both interrupted reports remain incomplete/failed, and their owned children are
confirmed gone. No production source or equivalence changed in that repair.

The complete VM campaign now passes all 356 mutations: 267 assertion-backed
kills (176 assertion-only, 91 mixed), 21 survivors and 68 compile errors at
95.35714%, with no timeouts, unknown/testError-only kills or new exclusions.
Both baseline/restored controls complete all 197 cases. Every mutation is
regenerated and its applied-source hash/classification, all selected input,
runner/configuration/native hashes and 358 mutation/control log hashes verify:
`/tmp/connectanum-flatbuffers-session-deferred-loop-bound-core-lazy-vm-completed-audit.json`
and `*-independent-log-hashes.json`. The first audit used the wrong restored-log
suffix; the corrected audit reads the actual restored-baseline log. The run is
unchanged. The complete browser campaign also passes all 356 mutations with
identical counts, score and assertion evidence. Independent regeneration and
selected-input audit passes; its whole-product wrapper failure remains recorded
because of the sole tooling-test edit described below. The complete 603-mutation
binding campaign fails at 89.43089%: 456 detections (440 assertion-backed),
36 survivors and 111 compile errors. Both 1,856-case controls pass. Its regenerated
inventory, classifications and selected-input hashes are independently audited;
the failed result remains evidence rather than acceptance.

An isolated 24-case binding contract fixture covers all eligible incoming codes,
both ciphers, runtime versus wire loading, memoization, metadata rejection and
wire replacement/anchor invalidation. Its 1,880-case baseline and restored
controls pass. Of 35 observed survivors, 20 become assertion-backed kills,
one becomes a test-error-only detection and 14 remain; all staged input and
individual log hashes pass a targeted audit. This is not a complete gate result.
Explicit positive metadata and successful-construction assertions strengthen
that fixture; its corrected 1,880-case baseline passes. An initial fixture-only
compile failure from using getter values as constant switch patterns is retained.
Fresh complete binding verification has completed in
`/tmp/connectanum-flatbuffers-deferred-binding-test-stage`, with prefix
`/tmp/connectanum-flatbuffers-deferred-binding-contracts-*`. After canonical
verification completed, these test additions were applied to the feature tree;
the completed campaign's test hash exactly matches the applied file. Its isolated
inputs remain frozen.

The next fast run failed an exact expected-support-list assertion that still
listed only the old parts. Its literal inventory is now updated, and both exact
scope controls pass. This sole Python tooling-test change is outside every
selected mutation runtime/test/support input; its before/after hashes and reason
are recorded in `session-deferred-tooling-expected-list-change.json` under `/tmp`.
Keep any whole-product wrapper rejection of that edit separate from the actual
mutation process result and selected-input audit. Canonical fast/verify passes
on the 1,454-file snapshot
`12c56f179b45a0b84446bfa489784e2420d9b537a1afd08cf8af46add59e458a`.
Prefix: `/tmp/connectanum-flatbuffers-session-deferred-tooling-repaired-canonical-*`.
Both terminal exits, all product/protected source and native/log hashes pass
independent completed audit. This accepts the Session candidate before the new
binding assertions and benchmark diagnostic rows. Fresh fast/full verification
now runs under `/tmp/connectanum-flatbuffers-session-deferred-contracts-canonical-*`;
fresh complete Chrome JS coverage runs under
`/tmp/connectanum-flatbuffers-session-deferred-browser-coverage-*`. Both freeze
the updated 1,454-file product inventory. Fresh Chrome JS coverage completes
4,595 core cases and 2,820 client cases plus 20 native-only skips. Client
96.42969% and core 96.18337% pass unchanged floors. All 1,454 product bytes,
the native library, log and 99 raw/LCOV/summary artifacts pass independent audit;
a freshly regenerated coverage summary also agrees. Proof:
`/tmp/connectanum-flatbuffers-session-deferred-browser-coverage-completed-audit.json`.
The complete fresh binding campaign now passes all 603 mutations at 96.13821%:
477 detections (473 assertion-backed and four test-error-only), 111 compile
errors and 15 survivors. No equivalents or deadline/gate changes. All regenerated
mutations, frozen staged inputs and matching selected feature inputs, native hashes,
605 individual logs and both 1,880-case controls pass independent audit:
`/tmp/connectanum-flatbuffers-deferred-binding-contracts-client-message-binding-vm-completed-audit.json`.

Fresh canonical fast passes, but full verify fails nine two-second readiness
checks in `native_wamp_worker_lifecycle_test.dart` during the benchmark suite.
The complete failed run's 1,454 source bytes, native/protected inputs and logs
pass independent audit under `session-deferred-contracts-canonical-completed-failed-audit.json`.
An initial auditor incorrectly counted repeated error phrases instead of failed
test entries; corrected counting confirms nine failures without changing execution.
All 36 focused lifecycle cases pass at unchanged deadlines. The complete benchmark
reproduction passes all 1,366 cases under `/tmp/connectanum-flatbuffers-canonical-bench-full-repro.log`
with the exact original environment and test settings; its completed proof is
`/tmp/connectanum-flatbuffers-canonical-bench-full-repro-proof.json`. The preceding
readiness failure is not reproduced, but its cause is not established. No readiness deadline or
lifecycle code has been changed. Full verification remains unaccepted. The preceding
`session-deferred-repaired-*` runs are failed evidence, not gate acceptance.
Core focused checks still pass 115 cases per VM/JS/WASM compiler after the repair.
Companion advice/dispositions are recorded in
`/tmp/connectanum-flatbuffers-session-deferred-companion-dispositions.json`.

The ordinary 16 KiB serializer diagnostic matrix now adds FlatBuffers RPC rows
for both RawSocket and WebSocket, alongside all existing JSON/MessagePack/CBOR
rows. A fail-first native orchestrator regression fails on six versus eight rows,
then passes with identical operation/payload/concurrency settings and preserved
serializer names. The initial zero-test selector and formatting correction are
retained in `/tmp/connectanum-flatbuffers-serializer-matrix-focused-proof.json`.
This matrix uses CBOR fragments inside FlatBuffers envelopes. No throughput,
latency, typed-payload, native-construction or parity result is established.

The pushed e6fb checkpoint's five production bundles pass manifest/checksum and
exact source/workflow attestation verification. Its Apple Silicon bundle passes
209 VM native/Session cases and the standalone 108-byte/three-segment construction
consumer against all 1,453 exact e6fb product bytes. Oracle exports are actually
absent with positive controls; typed consume and inspection exports are present.
Proofs: `/tmp/connectanum-flatbuffers-e6fb-platform-artifact-proof.json` and
`/tmp/connectanum-flatbuffers-e6fb-artifact-consumer-completed-audit.json`.
Four other binaries are verified but not executed. Publication is skipped.
Exact-head CI 37223117459 last showed 18 successes and 21 queued/running jobs;
full hosted acceptance remains pending. This artifact proof accepts e6fb sources,
not the new Dart candidate.

## Independent live peer candidate

An upstream-only Python peer reproduces strict-profile rejection at HELLO because
it has no metadata vector. Source inspection confirms this is the current default
contract, not proof of a broken upstream-subset implementation: no public subset
mode is exposed. An independent peer generated from the derived pinned schema
explicitly offers and checks metadata-v1; this is not an Autobahn session peer.

The live peer catches a genuine shared cancellation URI defect. The router returns
`wamp.error.invocation_canceled` for killnowait, whereas WAMP specifies
`wamp.error.canceled`. An isolated exact-source candidate changes the shared
constant and preserves legacy incoming error classification in the benchmark
helper. Both cleartext RawSocket and WebSocket pass independent authentication,
large fragmented RPC, wide IDs, binary/UTF-8/kwargs, progressive results, callee
errors, cancellation/interrupt, acknowledged pub/sub and cleanup against the
pushed e6fb production Apple Silicon library. Missing/false offers abort before
credentials. Restoring the legacy URI makes the independent checker fail; the
failed report stays failed. All 48 focused benchmark/router cancellation tests
pass. Candidate code and reproducible CI tooling have now been applied to the feature
tree after the original-setting complete benchmark reproduction passed. The
feature's actual 1,458 product files, all 69 independently regenerated Python
binding files, native/report/log hashes and legacy failure control pass audit:
`/tmp/connectanum-flatbuffers-live-peer-feature-completed-audit.json`.
Its production Apple Silicon peer passes all 11 checks on both cleartext transports.
Python optimized mode is explicitly rejected; targeted analysis and CI YAML parsing
pass. The Dart router helper lives inside its owning router package; an initial
root-tool placement produced dependency lint diagnostics and was corrected.
An unrelated formatter-only typedef change was reverted using the pinned 3.10
formatter. Fresh canonical fast/full verification now runs under
`/tmp/connectanum-flatbuffers-live-peer-canonical-*`; fresh complete browser
coverage runs under `/tmp/connectanum-flatbuffers-live-peer-browser-coverage-*`.
Both freeze all 1,458 product files. The new canonical fast run fails two
unchanged app-lab supervisor fixtures at their 20-second deadline; full verify
is not reached. Its full source/protected/native/log audit preserves that failure:
`/tmp/connectanum-flatbuffers-live-peer-canonical-completed-failed-audit.json`.
All 15 app-lab tests then pass unchanged in focused reproduction, including both
failures; their cause remains unestablished. No deadline is changed. Fresh browser
coverage now completes 4,595 core and 2,820 client cases plus 20 native-only skips.
The complete 1,458-file source/native/log/99-artifact audit passes and regenerates
an identical coverage summary at unchanged floors:
`/tmp/connectanum-flatbuffers-live-peer-browser-coverage-completed-audit.json`.
A fresh complete canonical fast/verify run now proceeds sequentially under
`/tmp/connectanum-flatbuffers-live-peer-sequential-canonical-*`, freezing those
same 1,458 files with no other large validation suite running. Both `bin/test-fast`
and `bin/verify` now pass at exit 0, including the unchanged app-lab/readiness
deadlines. All product/protected/native/log hashes independently audit, and the
browser coverage snapshot matches every product byte:
`/tmp/connectanum-flatbuffers-live-peer-sequential-canonical-completed-audit.json`.
Snapshot: `76eb0b32841425d9cca365fd68742d29570d09fa049156b3eddabc4e1f274d50`.
Both preceding failed canonical runs remain failed evidence. Feature checkpoint
commit/push follows this completed local acceptance; new exact-head hosted
acceptance remains pending.
Chrome WASM completes 4,585 core and 2,829 client cases with 20 native-only skips;
VM native suites run without unavailable-library skips. The standard ffi-test
library remains at SHA256 `334d3449af8b18723b1f83c09bff080e4256b6c2c05b076a0afc23df9d8dfccf`.
Research and evidence boundaries: [live peer findings](research/2026-10-04-flatbuffers-live-peer-conformance.md).

## Current key-policy candidate

The deferred/live-peer checkpoint is now pushed as `0cf9e65e`. Its complete local
canonical/source audit passes. [Exact-head CI](https://github.com/konsultaner/connectanum-dart/actions/runs/37235293321)
remains pending; its independently audited negotiated-profile peer and GuardMalloc
jobs pass. The [five-platform artifact dry-run](https://github.com/konsultaner/connectanum-dart/actions/runs/37235321617)
and package publish dry-run pass, with publication skipped. All five downloaded
bundles verify checksum, manifest and exact-source provenance; platform execution
is separate evidence. Proofs: `/tmp/connectanum-flatbuffers-0cf-platform-artifact-proof.json`
and `/tmp/connectanum-flatbuffers-0cf-hosted-live-peer-completed-audit.json`.
The live-peer audit independently regenerates all 69 Python bindings and verifies
11 checks on each cleartext transport. An initial local auditor omitted generator
flags; its helper failure is preserved separately from the passing hosted report.
No TLS/upstream Autobahn, all-platform runtime, copy-count or performance acceptance
is inferred. Draft PR #105 is updated.

A new issue #101 follow-up has 72 fail-first assertion failures across portable
and native profile/key-policy callbacks. The uncommitted repair revalidates the
fixed profile and provider state after callbacks and keeps the effective key
aligned with metadata. All 88 contracts pass; eight extra controls preserve
existing reused-options key pinning. Complete focused checks pass 174 core cases
on VM, Chrome JS and Chrome WASM, plus 2,468 serial client/native cases on each
current and older library. A parallel native
test invocation's single unavailable-keyring-handle error is preserved separately.
Core E2EE inventory regeneration succeeds with 308 selected candidates, without
new equivalents, exclusions, deadlines or gates. The original canonical runner
passed `bin/test-fast` but lost its recorded processes while `bin/verify` was in
progress; its frozen verification record remains nonterminal and its log has no
terminal summary. Preserve that attempt as incomplete. The already-passing fast
phase and exact 1,458-file snapshot are independently checked before resuming
`bin/verify` under `/tmp/connectanum-flatbuffers-policy-revalidation-canonical-resumed-verify-*`.
The resumed `bin/verify` completes at exit 0; an independent audit reconciles it
with the prior `bin/test-fast` pass on the same frozen 1,458-file snapshot:
`/tmp/connectanum-flatbuffers-policy-revalidation-canonical-resumed-completed-audit.json`.
Fresh browser coverage then passes and verifies all 99 artifacts. Handwritten
Dart Chrome line coverage is 96.2473% overall (core 96.1862%, client 96.4297%);
164 library source files are outside this measurement and two generated
FlatBuffers artifacts are reported separately:
`/tmp/connectanum-flatbuffers-policy-revalidation-browser-coverage-completed-audit.json`.
The complete 308-mutant core E2EE VM and Chrome campaigns both pass at
95.9839% adjusted assertion score against the unchanged 95% gate. Each has 239
kills, 10 survivors, 59 compile errors, zero equivalents and matching 167-test
baseline/restored-baseline runs. Independent audits regenerate the inventory
and verify all input/log hashes:
`/tmp/connectanum-flatbuffers-policy-revalidation-core-e2ee-vm-completed-audit.json`
and `/tmp/connectanum-flatbuffers-policy-revalidation-core-e2ee-web-completed-audit.json`.
These accept this local key-policy candidate only. Exact-head hosted CI and the
separate throughput/latency/copy-count acceptance in issue #103 remain pending.
See [key-policy research](research/2026-10-04-e2ee-key-policy-revalidation.md).

## Earlier checkpoints

Commit b07d7b26 contains the typed E2EE, deferred exports, benchmark/RPC repairs
and memory CI tooling below. The verified Session repair preserves runtime
payload capability through negotiated Session wrapping. Typed providers opt into
key selection after their existing preflight: explicit key, configured policy,
negotiated directional key, then provider default. CBOR/custom behavior stays;
context-free wrapper calls retain their existing directional defaults. Actual
fail-first regressions cover early policy invocation and the initial candidate's
context-free default-key regression. No duplicate byte conversion is introduced.
Focused checks pass 268 client/native VM cases, 120 core VM cases and 66 cases in
each Chrome JS/WASM cohort; each browser cohort explicitly skips 20 native cases.
The initial 42 key-selection/capability cases cover portable/native ciphers and
CBOR, with source/log hashes audited under `session-preflight-final-focused`.
The registered fixture now has 56 VM cases including constructor, file-wrapper,
metadata-WELCOME and packed-application behavior; all pass. The change
does not yet make ordinary Session receive buffers unique or defer their exports.

Portable/native sibling providers implement a Connectanum-local version-2
`wamp` / `flatbuffers` E2EE profile for XSalsa20-Poly1305 and AES-256-GCM. They
preserve one raw application span, reject keyword containers and share machinery
with unchanged version-1 CBOR providers. Session selects exact profile/provider
compatibility. This is not a standardized WAMP E2EE version; application schemas
and all outer metadata are not validated or authenticated by this profile.

An optional native consume-format-wide API returns complete typed plaintext.
Format 0 preserves legacy CBOR unwrapping; missing typed exports use generic raw
decryption. Read-only outputs retain their owner through backing/derived views.
Explicit root release invalidates those views. Opt-in
`materialize(..., deferPayloadExports: true)` postpones all exports until the first
getter. Consume/release before export invalidates unexported getters; already
exported ciphertext remains valid and forces the safe copied fallback. Ordinary
transports/Session remain eager. Actual VM-service GC and 42 ownership matrix
cases are included in the 135-case runtime cohort.

Ordinary benchmark factories now support FlatBuffers, whose WAMP envelope uses
FlatBuffers and dynamic argument fragments use CBOR. Internal RPC transfer now
records the actual native serializer separately from fragment encoding. The
repaired peer speaks FlatBuffers, uses RawSocket ID 5 and acknowledges the profile.
Focused checks pass 78 factory and 16 live transport/RPC/pubsub cases. Typed
benchmark workloads remain a separate unfinished prototype.

The new macOS Native Ownership GuardMalloc CI job verifies failure controls and
uploads logs, exact source/executable hashes and dependency lock. Full Verify
depends on it. Both canonical scripts include its five tooling controls. A missing
Cargo lock is resolved before freezing the native inventory; compilation then
uses `--locked`. Timeout/interruption logs and owned-process cleanup failures are
retained and fail closed. Actual feature-tree execution passes 57 instrumented
cases, with loader/count/log evidence independently recomputed:
`/tmp/connectanum-flatbuffers-native-memory-feature-default-repo-completed-audit.json`.
The exact-head hosted job now also passes and its uploaded 57-case loader/count,
five failure-control, source and dependency/log hashes are independently verified:
`/tmp/connectanum-flatbuffers-b07-hosted-guardmalloc-completed-audit.json`.
This is macOS execution, not all-platform, ASan/Miri or performance acceptance.

## Earlier verification checkpoints

The preceding 1,450-file candidate passes both canonical fast/verify on snapshot
`b77da9a480509729d469e9d7ca91cf3bda5b5fc96132ff2030e4ded92afed1ea`.
All product/native/log hashes are audited:
`/tmp/connectanum-flatbuffers-deferred-factory-repaired-canonical-completed-audit.json`.
Local canonical scripts select Chrome WASM on macOS; hosted Linux selects JS.
Separate focused Session checks pass 44 cases each in Chrome JS and WASM.
The earlier description of both compilers as local canonical execution is corrected.

After applying the test-only loop oracle and memory CI tooling, fresh combined
fast/verify passes on unchanged 1,452-file snapshot
`edce848870ae28ab3aee2a7e30f144e9b230ab00112c7831085e560187cd40a0`.
Prefix: `/tmp/connectanum-flatbuffers-native-memory-loop-canonical-*`.
Both process exit codes, all product/native/log hashes and preserved history
bytes are independently audited in `*-completed-audit.json`. Canonical browser
execution is Chrome WASM on this host.
The native ffi-test library remains SHA256
`9884a14303c9036eec642cd55470f105dbfb898e62b3e4cb9ee28ffc179a2a78`.

The initial Session candidate passes combined fast/verify on 1,453 files,
snapshot `84a26cbab9aaa8c02b86ce39b61f57818df2af64c4e25fd7433e968a26ce717e`.
Prefix: `/tmp/connectanum-flatbuffers-session-preflight-canonical-*`; all source,
native/log and preserved-history hashes pass independent completed audit. That
pre-registration run does not itself execute the new fixture. After applying the
audited script/56-case fixture repair, final `bin/verify` passes on snapshot
`c415bf87cca057178fbd8e722182c83ef63200533b758f52d9e632ff2fd8ae36`
under `/tmp/connectanum-flatbuffers-session-coverage-repaired-canonical-*`.
All 1,453 source/native/log/history hashes pass independent completed audit:
`/tmp/connectanum-flatbuffers-session-coverage-repaired-canonical-completed-audit.json`.
The registered fixture passes all 56 VM cases with the native runtime available;
the full client Chrome WASM cohort passes 2,800 cases with 20 native-only skips.
Its core source adds five mutations: both fresh campaigns select all 305 at the
unchanged 95% gate/deadlines, with no equivalent additions. Independent committed
VM/browser checkouts use scratch snapshot `464ec8f9`. VM completes all 305: 236
assertion-backed kills, ten survivors and 59 compile errors at 95.93496%, with no
timeouts or new equivalents. Independent regeneration/classification and all
source/test/support/native/log hashes pass audit:
`/tmp/connectanum-flatbuffers-session-preflight-core-e2ee-vm-completed-audit.json`.
The Chrome JS campaign also completes all 305 with the same 236/10/59 counts,
95.93496% assertion score and no timeouts or new equivalents. Independent
regeneration, classifications, mutant hashes and source/test/support/native/log
hashes pass audit:
`/tmp/connectanum-flatbuffers-session-preflight-core-e2ee-web-completed-audit.json`.
Generated Python/Dart caches are explicitly excluded from wrapper source inventory;
every tracked product and test/support input still participates in source checks.

Current production native library SHA256
`01c90d8dbc169e49874e7755f06086e2f57c20fbc56f479961cb68fe678aef9c`
builds without ffi-test and passes 116 explicit VM provider/runtime cases.
The typed-format export exists; four actual owner-oracle exports are absent, with
positive controls against ffi-test. Audit:
`/tmp/connectanum-flatbuffers-typed-production-vm-completed-audit.json`.
The initial command completed VM cases but failed by attempting FFI WASM loading;
its failed report remains retained. Its misspelled symbol-absence check is discarded.
Older d265 production ABI fallback checks also remain valid independent evidence.

## Mutation acceptance

Unchanged production source has 300 core E2EE mutations. The repaired loop oracle
uses a distinct throwing policy sentinel so skipped byte conversion cannot proceed
to expensive 64 MiB decryption. Four observed timeout mutants are assertion-killed
at unchanged deadlines, with restored baseline passing. The full VM campaign
passes 235 kills, ten survivors and 55 compile errors at 95.9184%; no timeouts,
unknown/testError-only kills or new equivalents. All classifications and mutation
hashes are audited; source/test/support and target inputs match the feature tree:
`/tmp/connectanum-flatbuffers-typed-e2ee-loop-bound-committed-snapshot-core-e2ee-vm-feature-input-completed-audit.json`.
The matching Chrome JS campaign also completes all 300 mutations with the same
235/10/55 counts and 95.9184% assertion score, no timeouts or new equivalents,
and restored baseline exit 0. Its wrapper exits 1 because the separate audit
helper generated one `tool/__pycache__/run_dart_mutations.cpython-314.pyc` during
execution. The original failed wrapper report is preserved. An independent audit
verifies that exact sole added artifact, every frozen source/test/support byte,
all 300 classifications and mutant hashes, unchanged gate/deadlines, and feature
input equivalence:
`/tmp/connectanum-flatbuffers-typed-e2ee-loop-bound-committed-snapshot-core-e2ee-web-feature-input-cache-reconciled-completed-audit.json`.
The mutation process exits 0; the wrapper is not relabeled as passing.

Earlier failed campaigns remain failed: original VM 90.9465%; expanded VM with
one timeout; original browser with three timeouts at 94.6939%; logical-fixture
browser with one timeout at 95.5102%. The complete logical browser failure is
independently audited:
`/tmp/connectanum-flatbuffers-typed-e2ee-logical-bound-committed-snapshot-core-e2ee-web-completed-audit.json`.
Canonical fixture-registration, fake-peer, support-list and analyzer failures,
partial interruptions and scratch startup/mode/lock failures remain retained.
They are repaired or superseded evidence, not passes. See the history archives.

## Last pushed hosted evidence

[PR CI run 37196989435](https://github.com/konsultaner/connectanum-dart/actions/runs/37196989435)
passes all 40 jobs at d26581c3. Local canonical, complete lazy VM/web and binding
mutation gates pass; browser client coverage is 96.5283% above 96.29%.
[Native Artifacts run 37197154855](https://github.com/konsultaner/connectanum-dart/actions/runs/37197154855)
passes five platform builds with publication skipped. Downloaded source manifests,
checksums and provenance verify. Apple Silicon executes 34 native cases and a
standalone consumer; other platform binaries are not executed on this host.
PR #105 now records these completed hosted results. They do not clear the newer
candidate.

At b07d7b26, [PR CI 37213443908](https://github.com/konsultaner/connectanum-dart/actions/runs/37213443908)
is still running and has a Core Browser Coverage failure. All 2,755 browser
cases pass, but client coverage is 2,857/2,970 (96.195%) against the unchanged
96.29% gate. Preserve the failed log/report and reproduce the missing coverage
before accepting a repair. The isolated repair registers the Session suite in
fast/full verification and VM/browser coverage, with omission controls passing
among 80 tooling tests. Its first run passes 4,568 core and 2,777 client JS cases
(20 native skips), then fails reporting because `/tmp` and `/private/tmp` produce
relative LCOV paths outside scope. The failed wrapper is preserved. Reformatting
the same raw data under the physical path fixes source attribution but still
fails the unchanged client gate at 2,874/3,002 (95.736%). Eleven additional
constructor/native-file delegation cases pass alongside the existing cases
(53 VM total), but the complete refreshed client gate still fails at 96.086%.
Three additional metadata-WELCOME/packed-application cases then pass (56 VM
total). Final complete client coverage passes 2,791 JS cases with 20 native skips,
reusing only unchanged-source 4,568-case core data whose raw hashes are verified.
Independent DA counts and every source/raw/report/log hash are audited:
`/tmp/connectanum-flatbuffers-browser-coverage-final-completed-audit.json`.
Client is 2,907/3,017 (96.354%); core is 9,089/9,452 (96.160%), at unchanged
floors and scope. Original failed wrapper and both intermediate gate failures
remain failed. File probes and metadata peer verify Dart wrapper behavior, not
native file/network execution. The audited test and five tooling-file repairs
are now applied; final canonical verify and its completed audit pass. The memory job is accepted
separately above.
[Native Artifacts 37213468173](https://github.com/konsultaner/connectanum-dart/actions/runs/37213468173)
passes five builds with publication skipped. All manifests, checksums and exact
source/workflow provenance verify. Its Apple Silicon production library (SHA256
`b346c52ffd1d965f2a951d01935d08f6429044e953bffb363db1d47e4e889324`)
executes 145 VM native transport/provider/runtime cases plus the standalone
108-byte/three-segment consumer with direct input/growth copied bytes both zero.
Actual oracle symbols are absent with ffi-test positive controls, and the typed
consume-format export exists. Other four binaries are verified but not executed.
Proofs: `/tmp/connectanum-flatbuffers-b07-platform-artifact-proof.json` and
`/tmp/connectanum-flatbuffers-b07-artifact-consumer-completed-audit.json`.

## Earlier checkpoint follow-up and evidence

Final coverage-repaired canonical verification, the complete local browser
coverage audit and both 305-mutation VM/browser audits pass. The Session stage is
pushed as c37c04ee. [Its CI](https://github.com/konsultaner/connectanum-dart/actions/runs/37218464793)
is queued/running with no observed failures so far; its [artifact dry-run](https://github.com/konsultaner/connectanum-dart/actions/runs/37218557969)
passes five builds with publication skipped. All five downloaded bundles pass
checksum/manifest and exact source/workflow provenance verification under
`/tmp/connectanum-flatbuffers-c37-platform-artifact-proof.json`. Its Apple Silicon
production library passes 201 VM native/Session cases and the standalone
108-byte/three-segment construction consumer using an exact c37 source snapshot:
`/tmp/connectanum-flatbuffers-c37-artifact-consumer-completed-audit.json`.
The four test-oracle exports are absent with actual ffi-test positive controls;
typed consume is present and the new inspection export is absent, as expected for
c37. Other four binaries are verified but not executed. Hosted browser coverage
passes 4,568 core and 2,791 client cases (20 native skips), with uploaded LCOV
independently recomputed at 96.160%/96.354% under unchanged floors:
`/tmp/connectanum-flatbuffers-c37-hosted-browser-coverage-completed-audit.json`.
Hosted GuardMalloc passes 57 cases and five failure controls. The PR merge
checkout has c37 as its parent; all 138 native/schema inputs match c37, and the
generated lock plus loader/count/log hashes pass audit:
`/tmp/connectanum-flatbuffers-c37-hosted-guardmalloc-completed-audit.json`.
Its recorded executable hash cannot be independently rehashed because the
executable is not uploaded. Remaining CI jobs are pending; these results do not
accept the new inspection repair.

Before deferred Session receive integration, a real eight-case regression proves
that typed native decryption with null Dart arguments invokes a key policy before
rejecting empty ciphertext on all four serializers and both ciphers. Report:
`/tmp/connectanum-flatbuffers-native-anchor-preflight-repro.json`. The first test
attempt had an invalid exception type; that compilation failure is not the repro.
The verified repair adds optional non-consuming native single-binary
length inspection, validating canonical JSON base64 without decoding and using
the existing borrowed binary readers. Typed provider preflight checks native
shape/minimum/64 MiB limit before policy. Older ABI safely materializes instead.
Focused native/fallback cases cover malformed shapes, keyword containers, length
boundaries and released/cached owners; updated native inspection tests pass.
An initial test assumed the existing FlatBuffers fixture was segmented; the
fixture is contiguous. That failed assertion remains failed evidence, and a
separate actual segmented-frame case verifies inspection does not flatten it.
Focused new-library checks pass 224 VM cases (143 runtime, 25 providers and 56
Session). The older ABI independently passes the same 143 runtime cases, with
the capability probe observing inspection absent and typed consume present.
All 1,453 product bytes, both library hashes and every log/count pass audit:
`/tmp/connectanum-flatbuffers-native-inspection-focused-completed-audit.json`.
A separate eight-case fail-first regression caught skipped length checks on the
candidate's authenticated cache; reconstructed ciphertext lengths now preserve
both bounds without exporting wire bytes. GuardMalloc passes 58 cases, with all
139 source hashes, executable, loader/count/log and cleanup evidence audited:
`/tmp/connectanum-flatbuffers-native-inspection-guardmalloc-completed-audit.json`.
Fresh canonical `bin/test-fast` and `bin/verify` both pass on 1,453-file snapshot
`508a2c0cbe7142250df7df1100e5b3fe0d63f04ffaf0bfea7c98ba566177694c`.
All product/native/log/history hashes, all 139 GuardMalloc native/dependency
inputs and the independently built memory executable still match:
`/tmp/connectanum-flatbuffers-native-inspection-canonical-completed-audit.json`.
Native VM cases run without unavailable-library skips. Chrome WASM passes 4,558
core and 2,800 client cases, with 20 explicitly verified native-only client skips.
The initial audit mistakenly rejected those browser skips; its corrected scope
checks VM availability and every browser skip separately. The verification runs
themselves passed. Canonical scripts rebuild the standard ffi-test library to
SHA256 `334d3449af8b18723b1f83c09bff080e4256b6c2c05b076a0afc23df9d8dfccf`;
the prior 9884a143 library remains preserved independently for compatibility checks.
Companion advice and verified dispositions are recorded under
`/tmp/connectanum-flatbuffers-native-inspection-companion-dispositions.json`.
Exact-head hosted checks and new production artifacts remain pending. Existing
core mutation evidence applies to unchanged core source; this repair changes
native IO only.
The pushed checkpoint's earlier 300-mutation browser wrapper cache discrepancy
remains explicitly retained. Choose runtime decryption before opaque exports.
Merely setting deferred mode in
the transport would still export through its `incoming.message` getter. Routing
metadata details already use a temporary export/copy with synchronous owner free;
they do not themselves leave a shared bulk payload owner alive. Source audit:
`/tmp/connectanum-flatbuffers-session-routing-metadata-owner-audit.json`. Existing
immutable ciphertext and forwarding semantics must stay valid. Session defaulting
previously invoked a key policy before underlying typed preflight; c37c04ee
reproduces and fixes that wrapper ordering. Initial source audit:
`/tmp/connectanum-flatbuffers-session-native-crypto-capability-audit.json`.

The current worktree adds optional owned-buffer E2EE ABI v1 and the public native
typed `packNativeTypedPayload` path. It borrows frozen native plaintext in Rust,
returns independent native-owned ciphertext, and composes it as an opaque
FlatBuffers frame. Rust pointer oracles and Dart ownership/decryption tests cover
both ciphers; the ordinary Dart-value E2EE path still copies across FFI. This
advances issues #96 and #101 but does not complete their broader acceptance.
Fresh `bin/test-fast` and `bin/verify` both pass at exit 0 on this worktree on
2026-10-05. This is local verification; exact-head hosted checks remain pending.
Complete external session conformance, malformed-input/fuzz and ownership CI,
supported-platform consumers and adapter/release docs.
The source-backed [native-owned crypto preparation](research/2026-10-04-native-owned-crypto-boundary.md)
records verified API boundaries and corrected local test/architecture advice;
it introduces no new crypto API. [Benchmark preparation](research/2026-10-04-flatbuffers-benchmark-construction.md)
records the current Dart fragment factory and missing echoed RPC identity check.
Declare representative performance/copy budgets before controlled measurement.
No throughput parity is established. The pinned Autobahn object serializer is not
a functioning live peer; independent generated Python codec fixtures do not prove
full session conformance. Audit every issue before closing this milestone.

## Research and preserved history

[Binding](flatbuffers_binding.md), [PPT/E2EE](e2ee_ppt_research.md) and
[ownership](native_buffer_ownership.md) record the contracts.
[Prior state](history/2026-10-04-project-state-before-flatbuffers-consolidation.md)
and [implementation journal](history/2026-10-04-flatbuffers-implementation-journal.md)
preserve earlier notes byte-for-byte. Their older entries are historical checkpoints.

## Typed benchmark runner groups (2026-10-05)

The current follow-up adds the three typed payload-construction groups to the
Dart WAMP runner and passes `payload_construction` through the Rust TOML
orchestrator. Typed RPC/pub-sub samples now retain payload-preparation time and
native-builder input/growth copy counters. A live correctness matrix passes all
18 combinations of RPC/pub-sub, FlatBuffers/CBOR/MessagePack PPT, and Dart
values/native buffer/pre-encoded span, on RawSocket with a Dart caller and CBOR
WAMP envelope. A separate 12-case integration matrix exercises typed FlatBuffers
PPT across both transports, callers and outer serializers; it does not use the
new runner groups. A focused owner test proves that a native payload remains live
through the RPC result and is disposed during runner cleanup. Rust orchestration/
report tests pass (181 tests); package analysis and `bin/verify` pass at exit 0.
These counters cover payload construction only, not total codec/transport copies.
Paired performance, confidence intervals, CPU/memory evidence and exact-head
hosted acceptance are still pending; do not claim parity or close issue #103.
Eligible native-buffer and pre-encoded FlatBuffers typed-PPT sends now use the
Session-owned-view path; other serializers and ineligible payloads keep their
normal behavior. This closes the #96 implementation boundary. #103 remains
open pending complete copy coverage and the paired parity campaign.

## WAMP process-resource attribution verification (2026-10-05)

The server-process resource attribution follow-up passes `bin/test-fast` and
`bin/verify` at exit 0 on this worktree, including browser/WebAssembly tests,
live WAMP transport matrices and consumer smoke checks. The comparator's eleven
unit tests, Dart VM process/isolate tests and Rust `http_stream` tests pass. A
live macOS one-workload smoke confirms both client/server metric blocks and
server allocation/GC collection; macOS lacks the Linux `/proc` CPU and RSS
evidence required by the parity gate. This is correctness evidence only. There
is no paired FlatBuffers performance campaign, so issue #103 and milestone
acceptance remain open. Exact-head hosted CI is pending the current commit.

## Issue acceptance audit (2026-10-05)

Issues #95–#99 are closed as completed. #95's pinned binding, generation
workflow, metadata/schema policy, negotiation rules, fixture coverage and
WebSocket identifier registry status are recorded in `flatbuffers_binding.md`
and checked by the FlatBuffers Binding workflow. #96's Rust-owned builders,
send/transfer contract, allocation identity, copy counters, error transitions,
ABI fallback, finalizers and explicit disposal are covered by the native buffer
API, ownership guide and tests. #98's Dart serializer and #99's native codec,
transport negotiation, auth, fragmentation and TLS paths passed full local
verification. #97's producer-thread cleanup and asynchronous terminal paths are
verified separately above. Issues #100–#104 remain open; #103 still lacks the paired
parity campaign and copy coverage for SDK masking, TLS and mixed-serializer
conversions.

Native encoder component calibration (2026-10-21): baseline `e73a5eb0`
(`39517222518`) passes all focused contracts, four lifetime phases and 34 native
FlatBuffers tests, then stops on non-identical allocation observations. The
control and empty opaque cases retain ten stable observations (11/2,328 and
12/2,520 allocator calls/requested bytes respectively). The first nonempty
Vec-backed `bytes` 1.12.1 clone promotes its ownership through `shallow_clone_vec`
and a `Shared` allocation; the earlier local probe cloned before counting. The
new example records the genuine first-call cost separately and retains ten
subsequent observations without relaxing their stability check. First and steady
wire output must match, and all borrowed pointer identities are checked. Print
observations before a stability assertion so failures preserve their data.
The failed artifact and logs are retained; its new 120/300 copy renewal never
started. Production writer code remains unchanged. A focused manual encoder
campaign avoids rebuilding Dart/native transport proofs during component
calibration. It retains compiler, resolved lock, all source hashes, executable
and wires; it never grants performance or copy acceptance.
