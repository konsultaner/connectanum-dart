# Project State

Last updated: 2026-10-31.

Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
Branch: `codex/flatbuffers-performance-parity`, [PR #132](https://github.com/konsultaner/connectanum-dart/pull/132).
PR #132 remains draft. Do not merge or claim performance acceptance yet.

## Current work

## Serial workload candidate and complete campaign checkpoint (2026-10-31)

The independently reproduced 49b831d5 diagnostic has four numerical misses:
Dart-value RSS 1.01967105, native pre-encoded RSS 1.00405113, Dart GC
1.06776769 and Dart p99 confidence (median 0.96862745, upper 1.08339709).
Its full frozen bin/verify passes, and all 32 hosted MQTT comparisons pass on
EPYC 9V74. This does not establish a repair on the earlier 7763 runner.
Owned-copy accounting independently verifies 3,291 source inputs, 120 live and
300 inventory rows, including E2EE/transcoding; all native lifetime controls pass.
Complete primary/supplemental runs 41196965823 / 41196967775 now test that exact
49b831d5 source. Retain them to completion; they cannot validate later edits.

A separate candidate removes completion-race scaffolding from serial workloads.
With one operation in flight, directly await that operation instead of allocating
pending/completion wrappers and Future.any listeners. The existing scheduling
condition, timing validation, full sample history, payload verification, copy
accounting and concurrent path remain. This is an instrumentation allocation
optimization, not demonstrated RSS or full performance acceptance. All
2,873 benchmark VM tests pass, including the live transport matrix, new ordered
serial samples and original-error/session-cleanup checks. Independent GLM review
finds no confirmed correctness defect; its hypothetical side-effect concern does
not apply because the scheduling predicate only reads time and sample bounds.
A local fake-peer component retains all 100,000 operations in each of six
interleaved processes: elapsed median ratio 0.83010658. It establishes no RAM
improvement (RSS median ratio 1.01424635). See the checked-in component
receipt for exact code fingerprints and its limited scope. Baseline49b831d5
bin/test-fast also passes on an unchanged separate worktree. Canonical and hosted
validation remain required on the candidate's own frozen commit. No gates or SDK settings change.

The fd983af8 supplemental predecessor completed: retain all 1,500 raw rows.
Independent recomputation exactly matches its hosted aggregate: 38 eligible
cases, 1,140 rows, 173 numerical misses and four evidence findings; the payload
batch is excluded because the separately pending SDK allocation-precision scope
decision remains unresolved. This is failed historical evidence, not acceptance.
PR132 remains at 40ddcb3f/draft; complete final-source acceptance is still required.


## Native MQTT singleton-prefix coalescing (2026-10-31)

The abb0905b full frozen bin/verify passes, including actual Chrome JS/Wasm,
with log SHA-256 a54ac89771dd954c543e639dc51c67e63a92c1423e2f4a70ed17540ee6495d91.
Its MQTT CI still fails on EPYC 7763: independently reproduce all 32 summaries,
unchanged budgets and library hashes. Candidate/matched WebSocket ratios remain
roughly 0.619-0.670; an absolute TCP3.1.1 profile also misses at 0.72685942. Do
not label literal matching a complete CI repair. Preserve its three MQTT
artifacts before cancelling only the rejected candidate's remaining correctness
CI work to free hosted capacity. All numerical campaign rows remain retained.

A new native-only MQTT candidate extends the existing bounded poll/yield/poll
coalescing turn to a singleton prefix. Previously the first frame flushes before
that turn can collect bytes made ready by the native scheduler. Expand the
existing regression over initial one/two-frame prefixes, every partial next-frame
boundary and3/128/65,536-byte payloads. The corrected before test runs exactly one
case and fails first chunk3bytes versus expected6. The earlier --exact filter
matched zero tests and is preserved as a setup error, not validation.

Both threshold conditions change consistently from two to one. The same pinned
read future survives partial reads, yielding and flushing. A quiet tail flushes
in the existing second Poll::Pending branch before next.await; no timer is added.
The64KiB pending batch bound, independent frame bounds, control/close ordering,
consumer backpressure, wake coalescing and TLS/non-Linux immediate policy remain.
All43 MQTT Rust cases, all454 Rust core cases plus three codec integrations, and
106 Dart MQTT integration cases pass (seven existing skips). The new ffi-test
release library builds successfully. macOS network policy is immediate; the
explicit Rust tests exercise coalescing=true, and hosted Linux must verify it.

Diff-only Qwen review missed the unchanged flush before next.await. GLM with
full context finds no concrete defect conditional on flush semantics. Verify
pending.split().freeze() empties pending and mpsc.send has complete-success or
error semantics; no partial successful flush exists. Existing closed-consumer,
quiet/partial tail and expanded singleton tests cover those paths. No confirmed
finding remains. This is not yet demonstrated hosted throughput or RAM repair.

Run the unchanged full MQTT budgets with a same-runner40ddcb3f native baseline:
the parent89681add native production source is byte-identical to that baseline,
so this tests the actual native coalescing change rather than a different Dart
broker. Retain955e4a91 and89681add canonical/paired/full reports on their own
sources. PR132 stays40ddcb3f/draft until final-source full acceptance. The separate
SDK allocation-precision question remains pending; change no gate without its
answer. Full955e4a91 canonical verification also passes, log SHA-256
202c9d7a7e36b7d0f68c0559e476aa1ed3ba0f17fd0b73932f398e1691ce0e4e;
its bounded-text cache remains excluded from this smaller native candidate.

## Smaller candidate after cache rejection (2026-10-31)

Independently reproduce all 90 abb0905b diagnostic rows, exact source/binaries,
and hosted summary: five numerical misses remain. Dart-values p99 median is
1.00386997 (upper 1.24961832), GC 1.04534898 (upper 1.15608839), RSS 1.01127284.
Native-buffer RSS median 0.99741740 passes its point gate but upper 1.11711471
fails confidence; native pre-encoded RSS median is 1.01047166. All throughput,
CPU, allocation and p95 comparisons pass. Do not call the cache a RAM fix or
causally attribute differences across runners. Both independently controlled
components also retain a CALL decode regression around 2.7%.

Exclude this unaccepted cache from the smaller candidate. Restore the exact
40ddcb3f production CBOR scanner, native client text decoder and its original
binding test file; no accepted root-envelope/scanner optimization is removed.
Retain the generic metadata mutation/Unicode/range/churn checks, the reproduced
lazy-logging fix and literal-MQTT matching. This new runtime differs from the
older accepted baseline by those actual fixes; it is not an unchanged-code
numerical retry. Metadata validation and every payload operation remain intact.
The rejected-cache and 955e4a91 complete campaigns continue to completion with
all raw evidence retained. Only a source that passes the full strict matrix can
be adopted into PR132. The 955e4a91 full/copy/CI run set is 41190894898 /
41190896355 / 41190897817 / 41190899393, with diagnostic 41190893418. No result
from those runs is attributed to this smaller candidate.

A product question now explicitly requests the separate issue103 SDK allocation-
precision scope decision: the existing 1% requirement is distinct from actual
RAM gates and the user's earlier standard-SDK copy scope. Keep that question
pending and do not waive any allocation figure or alter policy without an answer.
The smaller candidate needs its own paired/full canonical and final campaign
verification; PR132 stays at 40ddcb3f and remains draft.


## Latest checkpoint: lazy logging and final acceptance (2026-10-31)

PR132 remains at fully verified 40ddcb3f; final candidates are isolated. Latest
eligible runtime fd983af8 (production-identical to 40ddcb3f) has two RSS misses
in its three-case diagnostic. Its full 48-case primary and 50-case supplemental
campaigns remain running. The latest completed predecessor 35f4b84c full primary
has 93 numerical misses; no diagnostic supersedes the complete matrix.
Current 40ddcb3f CI is red on MQTT WebSocket throughput, with matched master and
candidate failures on EPYC 7763. Do not infer repair from another runner's pass.

Experimental 79c9dced full frozen bin/verify passes, including actual Chrome
JS/Wasm, with log SHA-256
9402d8bb2727768b353db835dcda8efc490514aeae954227c5d9abca2bda1862.
Refined bounded-text and literal-MQTT candidate abb0905b is under canonical,
paired and CI verification. Its owned-copy run 41189753582 passes independent
3,288-input / 120-live / 300-inventory / 32-zero-avoidable audits and the native
positive/negative lifetime controls. E2EE/transcode scope is unchanged; SDK/TLS/
crypto internals remain unmeasured. The separate allocation-precision decision
for two 1 MiB native MessagePack supplemental cases remains pending.

A concrete lazy logging defect is reproduced before changing behavior: the echo
helper interpolates packedPayloadBytes even when FINE is disabled. Both INFO
and FINE tests observe one unwanted source read. Isolated original-source testing
with a real native PPT lease also flips hasExportedByteView to true. Fix presence
logging with non-materializing flags and guard disabled FINE/FINER interpolation
at the seven workload logging sites. Normal fine log records remain; body
creation, verification, E2EE decode, samples, counters and measurement windows
remain unchanged. This is an actual view-export regression, not yet an attributed
cause of the failed RAM gates. A view export is not necessarily a byte copy.

All 115 focused cases pass, including real native leases remaining unexported at
INFO/FINE and existing E2EE/release cases. All 168 live transport scenarios pass,
including both transports, native/Dart clients, transcodes, typed construction,
E2EE and progressive/file workloads. Analysis is clean. Local review's required-
constructor warning refers to unchanged, compiled code; its other hypothetical
provider/cache concerns are not introduced by this patch. No confirmed finding.
The checked-in lazy-logging repro receipt retains exact source and log hashes.
Freeze the new logging candidate and renew full canonical verification, CI,
paired/full primary, supplemental and copy evidence before adoption. Keep every
predecessor campaign and failure; never weaken gates, force acceptance GC or
rerun unchanged numerical code for a favorable outcome. Keep PR132 draft.

## Earlier checkpoints

## Isolated scalar-CBOR scanner component (2026-10-31)

PR runtime remains `35f4b84c`, published tooling head `e02d6c27`. Its clean fixed-
head `bin/verify` passes all Rust/tooling/VM/native/router/consumer and complete
Chrome JS/Wasm core/client suites. Log SHA-256:
4e77ea9ef68f73f5de1cc625615db42e1a0c586a7cf8b842c3f9d42ac98582d5.
Preserve the earlier fresh-worktree formatter failure without resolved lint
packages; bootstrap resolves dependencies and no tracked file was changed.

Paired 41169319403 independently reproduces all 90 rows with source/binaries
verified and no integrity issue. Both native constructions pass all seven gates;
RSS medians are 0.9920871187 / 0.9969105252. Dart-values throughput now passes
(1.0054030768). Remaining Dart misses: RSS median 1.0047214273, GC upper CI
1.1915303221, and p99 upper CI 1.0523479600. Do not weaken any point/CI gate.
Full primary 41169321811 and supplemental 41169323042 remain running on this
runtime, together with predecessor f16ae5 complete campaigns.

Renewed copy 41170259967 passes; independently verify 3,283 source/resolved
inputs, 120 live / 300 inventory / 32 zero-avoidable checks and three six-row/
twelve-observation native positives plus expected zero-row/single-failure
negative. Stable PIDs and clean shutdown agree. Live E2EE/transcode/native-crypto
counts 96/120/48; inventory 96/60/72. External build-directory native binaries
are hosted-guard digest attestations, not retained independent rehashes.
Current standard-SDK VM profile 41170959383 verifies all 3,282 inputs, native
digest, 18 snapshots and exact hosted audit with no findings. Native owners and
sample instances disappear after diagnostic GC; no persistent native leak is
proven, and diagnostic GC is never used for acceptance. After-work snapshots
show differing transient garbage/VM capacity, not exact peak allocation sites.
Mint census is one instance for both codecs, so speculative timestamp boxing
is rejected. Fully represented PPT already bypasses dictionary retention.

An isolated `codex/flatbuffers-cbor-chunk-component` candidate only lifts the
CBOR scanner's nested string-chunk closure into a private method, preserving
all byte/cursor/UTF-8/charging operations and generic behavior. No new parser
fast path or omitted validation. Both private variants pass 265 metadata/frame
cases; the actual candidate passes all 3,546 serializer cases and analysis.
Qwen review completes: Git availability is an existing hosted-checkout
precondition; a pinned full `git show` is independent of index state; private
core/dependency input guards exclude its generic contamination concern. Reuse
the new target path constant in fixture checks. Runtime benefit is unmeasured.
Two local numerical attempts collect no samples after shared resource reservation
rejections; do not bypass them. Extend hosted component isolation to permit only
this single new core file and restore its actual baseline, reject mixed scanner/
validator changes, and include the CBOR validation suite. The fail-first contract
rejects the old tool; all ten final isolation/audit contracts pass. No primary
workload, metric window, payload construction, policy or gate changes occur.

MQTT candidate's 20 absolute gates and 12 matched summaries independently
reproduce exactly with all candidate gates passing against 66b4814d. Same-runner
WS throughput is essentially unchanged (0.9953/1.0048), so do not claim causal
repair of the old CPU-model WS failures from the 32-to-two write component.
CI 41169255165 and latest 41170261916 remain pending. The predecessor encrypted
progressive supplemental in 41159936492 completes all eight cases/240 rows,
exactly reproduced with verified inputs/native binaries and no integrity issue;
its 47 numerical cost diagnostics are retained. Protocol/final aggregate remain.
The separate SDK allocation-precision decision stays pending; PR #132 stays draft.

## Frozen runtime verification and copy-tool port repair (2026-10-31)

Canonical `bin/verify` now exits 0 on clean, fixed `66b4814d`, including all
Rust/tooling/VM/native/router/live/consumer and full Chrome JS/Wasm core/client
checks. Log SHA-256: 550018813bd651ada4e9f872a89f6db93990ac347513c0f3f2b90b6d9f7d632c.
Do not infer strict RAM/throughput acceptance from this correctness result.

MQTT candidate runtime stays frozen at `35f4b84c`. Completed GLM review has no
concrete production regression after checking its advisories: the sole caller
caps batches at 16, 32 descriptors suffice, and the queue byte budget is 8 MiB.
CurrentThread test runtime and the task's lack of suspension after close signal
exclude the proposed test-yield race. A private exact-source follow-up proves
all 16 chunks' byte permits remain held through an asynchronously paused WS
flush and return after completion. Preserve initial blocked companion attempts.
Hosted CI/paired/full primary/full supplemental remain pending on this runtime.

Copy 41169320675 fails before any payload proof: its tooling startup-failure
test obtains the same ephemeral port twice after immediately closing each
reservation. A deterministic released-port-reuse fixture reproduces the exact
ValueError on the old tool. Reserve all listener sockets together with ExitStack,
then close them before launching the child; all 15 probe tests pass, including
real-child cleanup and evidence retention. Preserve the failed workflow's logs/
2,832-byte artifact and fail-first repro. The completed advisory debug proposes
a child/listener leak, but source and reproduction exclude it: failure occurs
before child launch. Final tool review's hypothetical reuse flags do not apply
to default TCP sockets; the release-to-launch external race remains pre-existing.
No workload, metric, native/Dart runtime or acceptance gate changes occur.

Renew copy proof on the tooling-only commit while retaining the numerical
campaigns pinned to identical runtime `35f4b84c`: diagnostic 41169319403,
48-case primary 41169321811 and 50-case supplemental 41169323042. CI is
41169255165 and separate MQTT attribution 41169256479 completes. PR #132 stays
draft; nothing is waived and no PR is merged.

## MQTT gate repair candidate (2026-10-31)

An isolated `codex/flatbuffers-mqtt-egress` worktree branches from 66b4814d,
leaving the main PR source frozen for its canonical verification. Native MQTT
writers currently issue one socket write per already-queued packet/frame.
A fail-first counting writer reproduces 32 writes for 32 packets in both TCP
and WS. A ready-only bounded scatter/gather candidate uses two writes while
preserving every TCP byte and separate WS frame. Reuse batch descriptors and
retain every payload owner / byte permit through IO and WS flush; keep the
original singleton and nonvectored paths. No timer, new packet wait, payload
copy, frame merge, environment policy, workload or acceptance budget changes.

[Counter component](research/2026-10-31-mqtt-ready-egress-component.json)
retains exact counts and input hashes. All 43 MQTT tests pass, including six new
byte/frame/counter/partial-write/nonvectored/control-close/permit-release cases;
full ct_core passes 454 unit and three integration cases. Preserve the private
missing-lock/fixture setup failures and the expected baseline counter failures.
Local companion review and numerical timing are blocked by another workload's
exclusive machine reservation; do not bypass it. Manual source review finds no
concrete ownership/protocol regression. No transport improvement or CI pass is
claimed before hosted measurements. The main 66b4814d bin/verify remains running;
no main-worktree source or HEAD changes occur during it. Full primary and
supplemental f16ae5 runs are retained to completion, not acceptance for this
candidate. PR #132 remains draft and every strict gate stays unchanged.

## Scalar observation storage candidate (2026-10-31)

After frozen `6575b7e9`, share only eight immutable scalar sample context
values in a bounded 64-entry cache. Each observation retains its own iteration,
latency, preparation time and start/end timestamps. Public getters and all 13
named/positional fields are unchanged; there is no payload, builder, owner or
lease in the cache. Apply identically to every serializer. Do not alter work,
windows, copy accounting or acceptance thresholds.

[Complete-record component](research/2026-10-31-flatbuffers-sample-context-component.json)
retains eight fresh balanced ABBA observations. All 33,991 Dart and 32,067
native records preserve complete output hashes. Peak RSS falls about 4–5 MB;
loaded sample memory falls about 12 MB without a measured CPU penalty in this
component. This is not transport/RAM acceptance. Observable eviction, independent
observation values, mutation isolation and null-versus-zero controls pass.
Completed GLM review suggests reset/worker-affinity changes; source inspection
rejects them: the cache is capped at 64, a new tuple becomes the last-entry fast
path immediately, and matches explicitly compares worker along with all seven
other scalars. No mutable data is shared. Preserve linear-scan cost as a risk for
workloads with many distinct tuples; full regression and hosted measurements
remain required.

Frozen `6575b7e9` canonical `bin/verify` exits 0 on a clean, fixed HEAD, including
full Chrome JS/Wasm core/client and Rust/tooling/VM/native/router/live/consumer
checks. Log SHA-256:
0f00180523045487ae379076f369cd8becdbf1ecd9d2e2b577f07f0b9a2df864.
Paired diagnostic 41165318716 completes all 90 rows with exact independent
reproduction and verified retained inputs/binaries. Five numerical misses remain:
Dart-values throughput median 0.9892592301, p99 upper CI 1.4569961489,
GC upper CI 1.0755105768, RSS median 1.0100816168; pre-encoded RSS median
1.0091516331 (upper CI 1.1159422793). Native-buffer passes all seven metrics.
Keep all failed reports; no unchanged numerical retry is used to seek a pass.

Copy renewal 41165320239 passes; independently verify 3,281 source/resolved
inputs and 120 live / 300 inventory / 32 zero-avoidable checks. Live
E2EE/transcode/native-crypto counts remain 96/120/48; inventory 96/60/72.
External native binaries are digest-only hosted-guard attestations in this copy
artifact, not independently rehashed retained files. CI 41159940789 completes
successfully; its MQTT artifacts reproduce exactly. Full primary 41159934237
and supplemental 41159936492 continue on f16ae5e9. The completed supplemental
payload shard reproduces exactly with 30 SDK-allocation precision findings and
13 numerical cost diagnostics; the other shards and final aggregate remain.
PR #132 stays draft; full strict acceptance and the separate SDK precision
scope decision are outstanding.

Named HTTP report streaming candidate (after f16ae5e9): prepare an immutable
sample-list snapshot, validate finite numeric rows and encode all metadata before
sending. Emit every standard JSON row in bounded sample batches through the
existing HTTP stream, yielding so its Dart queue can flush. Samples/metadata and
native/socket queues retain their own storage; do not call this fully bounded
pipeline memory. All fields, observations and metric windows remain unchanged.

[Complete-record component](research/2026-10-31-flatbuffers-streamed-report-component.json)
retains all eight fresh-process ABBA measurements and all 33,991 actual records
plus metadata. Named output hashes/9,173,502 bytes match exactly; peak RSS falls
from about 65.4 MB to 57.2 MB, while isolated encoding/hash time rises about 12%.
Positional output also matches, but peak RSS and encoding time worsen. Reject
positional streaming: the compact worker remains byte-for-byte f16ae5e9. Apply
this candidate only to named HTTP reporting for every serializer.

All 2,866 benchmark tests pass during the experiment; after retaining the existing
compact writer, final 69 boundary tests (including negative finite JSON spellings)
and four live 2,048-sample source responses pass with clean shutdown. Earlier four
live responses and 139 focused cases also pass; targeted analysis is clean.
Qwen's broad review reaches its output cap; bounded GLM judgment completes.
Its negative-latency suggestion would change the existing model contract and is
rejected; negative values must keep standard JSON behavior. Numeric-only model
fields and ASCII keys justify the sample byte bound; existing empty/nullable/
Unicode-metadata controls pass. Canonical verification and hosted diagnostic on
the final frozen candidate remain required. This is not RAM/parity acceptance.

Fresh-process allocator 41162296996 on f16ae5e9 independently verifies all 3,276
tracked source inputs, retained resolved files/production binaries/wrappers,
60 rows, 24 owned role snapshots and exact summary. Preserve the initial private
audit error that omitted report newlines from hashes; corrected byte-preserving
hashes match. FlatBuffers fresh pairs vary substantially (439.7 / 400.0 MB summed
median peaks), with VM capacities and free allocator bins differing. Do not
subtract those bins from RSS or infer an exact workload allocation site.
Native/Dart CPU attribution 41163196895 also completes; its 3,279 inputs, native
digest and 18 snapshots independently match. It is diagnostic, not acceptance.
The primary profile request defaults to 65,536 bytes; the 10-KiB test applies only
to ext_08. Do not add a payload override based on that rejected misreading.

Frozen report-staging runtime: `f16ae5e9f41c5e38495187ca12a536915800531b`.
Canonical `bin/verify` passes on its clean, fixed HEAD, including complete
Chrome JS/Wasm core/client and all Rust/tooling/VM/native/router/live/consumer
checks. Log SHA-256: 1f508f8283abbced3b7c64a9b93d40d75921be5e10839dbf3a68a6a8f641cb3f.

Paired diagnostic 41159942894 completes all 90 rows and independently reproduces
exactly with retained inputs/binaries verified. Three numerical misses remain:
Dart-values RSS median 1.0172681176, Dart-values GC upper CI 1.1289654710
(median 0.9767352224), and native-buffer p99 upper CI 1.0732797140 (median
0.9879740981). Pre-encoded passes all seven metrics, including RSS; native-buffer
RSS also passes. This does not replace primary acceptance. Current Dart-values
VM attribution 41161593502 completes and independently verifies 3,279 inputs,
native digest, all 18 snapshots and exact audit with zero findings. Case ID is
rpc_rawsocket_clear_dart_values. After diagnostic GC the client external count
is 112 bytes in every codec. FlatBuffers live client heap is 27,688,304 bytes,
compared with MessagePack 26,900,112 and CBOR 29,238,224; these after-work/GC
snapshots do not attribute the acceptance RSS peak. Fresh-process read-only
allocator/memory capture 41162296996 and native/Dart CPU attribution 41163196895
are running before choosing another fix. Do not equate profiler report staging
with a proven workload allocation site.

Copy/lifetime renewal 41159938655 passes on f16ae5e9. Independent audit verifies
all 3,280 source/resolved inputs and complete 120 live / 300 inventory / 32
zero-avoidable checks, E2EE/transcode/native-crypto counts, stable PIDs and clean
shutdown. All three native controls reproduce six reports/twelve observations,
with the expected zero-report, single-failure negative. Recorded native binary
invariance is attested by the hosted guard; this copy artifact does not retain
the external build-directory binaries for independent byte rehashing.

Full primary 41159934237, all supplemental shards 41159936492, and full CI
41159940789 are running on f16ae5e9. Predecessor CI 41153485459 completes all 39
jobs successfully; its 20 MQTT gate and 12 matched master/native summaries
independently reproduce exactly with unchanged budgets and consistent hashes.
The later native/Dart companion reviews both finish; source checks reject
speculative cache-key/projection concerns (keys are ints/records, the full
projection delegates to the field helper, and native callbacks return to the
per-field loop). No actionable regression is identified. Preserve the earlier
incomplete review attempts.

A possible fragmented-CALL writer fast-path gap is rejected as the remaining
RAM cause: serializeFragments replaces the parts with its builder-owned vector
reference before invoking the writer, so the actual path already qualifies.
No speculative writer or wake-pacer change is made. A separate vector-observer
closure-removal prototype exists only in /tmp; functional/performance execution
has not started after the shared-machine lease rejects component/test-planning
attempts. Do not ship it without measured benefit and equivalence controls. Do not rerun unchanged
numerical campaigns to seek a lucky pass.

The next RAM candidate removes the full-size UTF-8 join when preparing worker
and HTTP benchmark reports. It retains owned 64 KiB encoder chunks, completes
encoding before publishing, and sends the same complete JSON through existing
stdout/HTTP stream transports. All observations, named/positional fields,
processes and resource windows remain unchanged for every serializer. This is
a report staging optimization, not a claim of bounded report memory or payload
zero-copy. The SDK sink adapter copies its slices according to its ownership
contract; no borrowed encoder buffer is retained.

Byte-equivalence/atomic-error controls and worker lifecycle tests pass (136
cases), as does targeted analysis. Four live large responses preserve all 2,048
samples each across Dart/native worker paths and mixed serializers; four small
responses retain E2EE/transcode accounting and clean process shutdown. The complete
benchmark suite passes all 2,863 cases. The balanced fresh-process ABBA
[report component](research/2026-10-31-flatbuffers-report-staging-component.json)
preserves 32,067 samples and identical output digests in both formats. Named
output remains 12,168,713 bytes; positional output remains 2,837,250 bytes.
Current RSS after encoding is lower; lifetime peak improvements are small or
absent because input-report parsing precedes measurement. This is not acceptance.
The frozen-source canonical and copy renewal now pass as recorded above; strict
primary/supplemental acceptance remains pending. A completed Qwen
review suggests invalid/mixed sample/null casts, but source inspection confirms
the same pre-existing callback and concrete List<WampSample>; null/invalid cases
are covered by exact-byte/error tests. No actual regression is identified.
A bounded GLM judgment also completes with no evidenced correctness/fairness
regression. Its fresh-buffer explanation is not the ownership guarantee: SDK
source confirms the ordinary sink adapter copies addSlice data, as required.

Hosted component 41157110077 on 07807a6e succeeds. Independent audit verifies
3,275 tracked source inputs, retained locks and all 219 private artifacts; all
160 raw rounds reproduce the summary exactly. Median candidate/baseline decode
time is 0.951223 for RESULT and 0.985733 for CALL; measured managed allocation
falls from 3,855.82 to 3,439.31 bytes per RESULT and 6,475.20 to 6,068.32 per CALL.
These are isolated decoder measurements, never transport/RAM acceptance.

Copy/lifetime renewal 41157111216 also succeeds on 07807a6e. Independent audit
verifies all 3,279 source/resolved inputs and complete 120 live / 300 inventory /
32 zero-avoidable checks, including E2EE/transcode/native-crypto. The native view
controls reproduce three six-row positives and the expected single-failure,
zero-row negative with unchanged inputs, stable processes and clean shutdown.

Native pre-encoded profile 41154814129 succeeds on da5398a6: independently verify
all 3,277 input hashes, native binary, 18 snapshots and exact memory audit with
zero findings. FlatBuffers has only 112 external client bytes after workload
and diagnostic GC, so these snapshots do not establish a native storage leak.
The completed public response is 12,168,713 bytes / 32,067 samples, compared with
11,542,082 / 29,993 for MessagePack and 7,354,966 / 19,352 for CBOR. FlatBuffers
router snapshots include 26,632,672 Uint8List bytes and client snapshots include
14,108,064. This motivates reducing temporary report staging; exact attribution
to one allocation site is not claimed. Diagnostic GC is never added to acceptance.

Current candidate removes temporary dictionary projections in native
and Dart FlatBuffers agreement, and keeps the common two-table Dart validator
cache inline without allocating a captured height-update closure. Full schema,
metadata agreement, alias identity and all resource budgets remain enforced.
The pre-change `bin/test-fast` passes. Candidate checks pass 3,545 serializer
cases, the 111-case frame suite including the added extended RESULT regression,
47 native FlatBuffers tests and all 167 mutation equivalence proofs. Analysis
exits 0 with only the three existing core info diagnostics. A fail-first tool
contract now permits exactly this three-file decoder/validator component
combination; all nine isolation/audit tests pass. This changes no parity gate.

[Component evidence](research/2026-10-31-flatbuffers-field-projection-component.json)
retains 24 native paired cases: identical complete frames and verified payload aliases,
one fewer allocator request / 224 fewer requested bytes per typed decode.
A frozen-baseline Dart differential matches 12,258 inputs and 1,512 depth/table
budget combinations exactly. These checks establish neither RSS nor performance
acceptance. Local timing is not executed after resource-lease rejection. Final
GLM review later starts but reaches its 150-second deadline with an incomplete
stream; it is not a successful review. Do not bypass resource ownership.

Canonical `bin/verify` passes with observed exit 0 on frozen, clean `da5398a6`,
including full Chrome JS/Wasm core/client suites. Log SHA-256:
56d1b0e69f72933f21e9acb2855a42d6039da2ea97fb50f7ccab1f389adedd65.
The first run correctly fails one deployment-audit fixture when the commit
changes HEAD mid-check (4dec9dd -> da5398a); preserve that failure. The frozen
rerun and a focused fixed-head audit test pass; no audit rule is changed.

Paired `41153557716` on da5398a6 completes all 90 rows and independently
reproduces exactly with retained inputs/binaries verified. Its only nonnumeric
finding is diagnostic ineligibility, not missing evidence. Six numerical misses
remain: Dart-values speed/p99/GC/RSS, and pre-encoded p99/RSS. Native-buffer passes
all seven metrics. RSS ratios remain 1.0294900042 and 1.0270929504 respectively.
This is not primary acceptance; the full predecessor's 102 failures remain.

Hosted component `41153337377` fails before readiness/measurement: its probe
reads ordinary arguments from an opaque typed payload. Both private functional
suites pass but that fixture had not been exercised. The repaired probe shares
its accessor with pre-measurement tests for both payload forms: opaque vectors
must alias the wire; ordinary materialized bytes must reuse the existing decoded
buffer (the ordinary codec may already copy). Sixteen direct controls and 546
private regressions per frozen baseline/candidate pass, along with all nine
tool contracts. Retain the private initial nullable-ResultDetails compile error
and invalid ordinary-alias test assumptions; neither is a production defect.
No shipped runtime, workload, wire, copy scope or acceptance gate changes in
this probe repair. Its renewed hosted comparison and memory attribution are
completed/audited above. Correctness CI `41153485459` on da5398a6 is still running
with 37 successful jobs and only Dart VM coverage pending. Do not renew unchanged
numerical tests to seek a lucky pass.

Predecessor runtime: `4dec9ddc978b3b6fd47275e67cf46fd40ac46931`.
It fixes public reanchoring releasing the wrong allocation: explicit payload
release now follows the actual retained `storageOwner`. Fail-first native and
ordinary Dart-owned cases pass. It also fixes two encrypted FlatBuffers file
header cases merged from master: validate authenticated decoded CBOR metadata
while retaining ciphertext storage, and keep plain opaque header rejection.
512 lifetime/file and 186 socket/file cases pass, both encrypted live transfers
pass, and canonical external-peer live RPC checks actual backing ownership.
Earlier private probes used a wrong peer/always-native assumption; preserve them
as invalid diagnostics, not production failures or acceptance evidence.

Canonical `bin/verify` completes with observed exit 0 on 4dec9ddc, including
Rust/tooling, all VM/native/router/live transport suites, standalone package
consumers and complete Chrome/WebAssembly core/client suites. Its retained log
SHA-256 is da5c3d46bd2a2d13d54ca8435b7b261aa582087dde029233948349f7487bc66a.
The receipt verifies a clean tree. Qwen review completes; source/test checks
exclude its speculative double-free/race/null-owner claims. Later debug calls
hit their explicit timeout/token bounds; preserve those incomplete attempts.

Final copy/lifetime workflow `41120169745` completes successfully on 4dec9ddc.
Independent audit verifies all 3,277 source inputs, generated lock receipts,
native/input hashes, complete raw counts, PIDs and cleanup: 120 live / 300
inventory / 32 zero-avoidable checks. Live E2EE/transcode/native-crypto counts
are 96/120/48; inventory counts are 96/60/72. Native lifetime controls reproduce
three six-row positives and the expected zero-row/single-failure negative,
with clean exits and no reader errors. SDK/TLS/crypto internals stay explicitly
unmeasured at the user-approved standard SDK boundary.

Full 48-case primary `41120217349` completes all 1,440 rows on this frozen
runtime and fails 102 strict numerical gates: RSS 41, CPU 21, throughput 17,
p99 12, p95 7, GC 3 and allocation 1. Independent reproduction matches the
hosted comparison exactly, verifies retained inputs/native binaries, and
finds zero integrity failures. The earlier two-RAM-failure diagnostic is not
the current acceptance result. Preserve it and every predecessor report.
Full CI `41120166268` completes successfully: all 39 jobs pass. Its 20 MQTT performance profiles all pass and are
independently recomputed exactly from raw rows against unchanged budgets; its
same-runner native-library comparison against master also passes; all 12
comparison summaries reproduce exactly with consistent library hashes, pinned
source refs and unchanged automatic worker sizing. Previous
CI 41113454274 retains four cleartext MQTT failures and cancelled remaining
duplicate jobs. Do not infer a cause or call cancelled history a pass.

Payload-size supplemental shard in 41120221904 completes all 360 rows but fails
strict evidence validation: ext_17 and ext_19 MessagePack (native-buffer 1 MiB
RPC over clear RawSocket / secure WebSocket) cannot meet the allocation
estimator's 1% precision rule. All 14 measured observations independently pass
every preceding invariant: stable PID/observer, endpoint brackets, groups,
complete unique GC events, native counters, heap/reclaimed arithmetic. Only
rounding uncertainty rejects them (6.72–7.06%). Raw reports are unchanged; all
15 numerical diagnostics and 30 integrity findings remain retained. The shard
reproduces exactly, including retained inputs/binaries. Standard SDK 3.13.5
publishes GC heap values in rounded KB; its allocation profile is a live census,
not an exact cumulative allocation counter. No guessed exact values or relaxed
precision are introduced. Ask the user whether these two supplemental
allocation figures may remain explicitly SDK-limited and unmeasured; this is
separate from the earlier accepted copy-accounting scope. All primary gates
remain strict. The completed primary has no allocation-precision rejection.

The encrypted-progressive supplemental shard completes successfully. Independent
reproduction verifies all eight cases / 240 rows, retained inputs/native hashes
and the exact hosted comparison, with zero integrity findings. Its 51 numerical
cost diagnostics remain reported; supplemental reporting is not primary parity.

All three supplemental shards now finish: 50 cases / 1,500 raw rows. Protocol
independently reproduces 30 cases / 900 rows with zero integrity findings and
128 numerical cost diagnostics. All shard input/native hashes and comparisons
verify. The combined failed report and manifest reproduce exactly: 38 validated
cases / 1,140 rows, 179 retained costs and four findings, because strict SDK
precision validation excludes the whole 12-case payload batch. Its other 360
raw rows and fifteen costs remain in that shard. No incomplete aggregate is
claimed complete or primary-eligible. The initial private aggregate audit uses
the wrong CLI subcommand and is retained separately; the corrected merge command
reproduces the hosted failure exactly. Artifact selection verifies all three
source-pinned attempt-1 IDs. The primary campaign independently fails its
numerical gates; resolving supplemental precision alone cannot make it pass.

A private stock-SDK native timeline callback probe does not resolve precision:
it captures natural-GC begin/end events, but its heap-usage equivalence check
fails by up to 1,043,456 bytes. SDK source confirms the C API's new-heap metric
returns capacity, not precise usage. Reject it; no production/acceptance setting
changes or custom SDK build are introduced. Both probes and the failed assertion
are retained; primary optimization and the separate precision decision remain
outstanding.

PR #132 stays draft until full primary acceptance and supplemental reporting
are complete, including the pending SDK precision decision. Preserve every predecessor report and budget.

`07d3227c` fixes a concrete explicit-release gap. A direct FFI weak observer
proved that a 65,536-byte FlatBuffers result remained alive after
`releaseNativeMessagePayload` returned true: the routing handle was released,
but exported native owners waited for GC. Client exports now share an optional
explicit byte lease. Explicit payload release reclaims that lease's owners;
ordinary `NativeIncomingMessage.release()` preserves exported views. Independent
export leases retain their separate lifetimes. Native frame allocations used by
Dart RawSocket receive have the equivalent detachable allocation owner, shared
by bounded aliases. Pointer lookups reject released allocations.

The identical direct repro now observes destruction immediately (1 -> 0),
without GC. All ten native owner cases (including independent exports), 405
focused lifetime/file/E2EE cases, 94 socket cases and 77 transport/frame cases
pass. A live fragmented FlatBuffers result releases without affecting its next
frame. A child GC proof keeps only derived immutable ByteData after both the
incoming wrapper and root facade die, then observes destruction after that last
view is dropped. Fourteen focused boundary cases pass, including empty storage
and foreign/disposed lease rejection. The initial plain-name selector matched
no tests; the corrected regex invocation passes. No wire/data/window/gate or
SDK/allocator tuning changes occur.

The preceding canonical `bin/test-fast` exits 0. Focused analysis is clean;
complete analysis exits 0 with the 31 existing info diagnostics after removing
one new style diagnostic. All 167 mutation equivalence proofs and 15 native
probe contracts pass. Initial local companion calls were blocked by another
project's shared resource lease. Qwen later supplies advisory test cases; unsafe
reads after manual release are rejected. Its review exceeds the output bound;
a completed GLM audit is checked against source and tests. Its three advisory
claims do not identify a defect: each repeated Arc token owns a separate
reference, any surviving old export already pinned the whole StoredMessage,
and released-owner lookup stays false. Retain all failed advisory attempts.

Master integration brings in MQTT merge `ef822e08` before final acceptance.
The pre-merge full verification passes Rust checks and runs tooling tests, then
is intentionally superseded (exit 143), never a full pass. Its log and structured
termination receipt are retained outside the tree. Resolve the merge by keeping
both required CI/mutation lane inventories, both notification cleanup paths,
MQTT dispatch inside the existing guarded router loop, both file-prefix and
receive-release tests, and the existing decoded-CBOR file chunk fix. Renew full
verification, hosted CI, copy proof and numerical campaigns on the merged source.

## Latest numerical and copy evidence

Paired `41112077193` on runtime `40f8cec5` completes all 90 rows.
Independent recomputation matches the hosted comparison exactly, with retained
config/locks/scenario/native binary hashes verified and no integrity issue.
Native-buffer RSS now passes (median 0.9993, CI [0.9858, 1.0240]). Four numerical
failures remain under unchanged budgets:

- Dart-values p99: median 0.9772209567; CI [0.9328537170, 1.1998468606].
- Dart-values GC: median 0.9072043762; CI [0.7838200752, 1.1617671870].
- Dart-values RSS: median 1.0180264809; CI [1.0140671904, 1.0850607930].
- Pre-encoded RSS: median 1.0049883897; CI [1.0022969898, 1.0107649544].

All other throughput, CPU, allocation and latency gates pass. This is diagnostic,
not primary acceptance. Preserve the preceding two-RSS-failure report
`41056036677` and every earlier failure.

Copy `41112073189` passes on 40f8cec5. Independent audit verifies 3,277 source
inputs, retained generated locks, binary digest, raw observations, stable process
identities and cleanup: 120 live / 300 inventory / 32 zero-avoidable checks.
Live E2EE/transcode/native-crypto counts are 96/120/48; inventory counts are
96/60/72. All three native-view positives produce six rows with zero failures;
the negative control produces zero rows and its expected single failure. SDK,
TLS and crypto internals remain labelled unmeasured at the agreed standard-SDK
boundary. The first audit formatter's optional-field KeyError is preserved.

Dart-values VM attribution `41116315782` completes on runtime-identical da46d7f6.
Its 18 snapshots reproduce the hosted memory audit exactly with no findings.
After workload, native wrapper/allocation counts are zero and client external
usage is 160 bytes (112 after diagnostic GC). No retained payload leak is proven
for this case. Full source/binary input auditing remains pending; diagnostic GC
is never used for acceptance or to subtract memory from reported RSS.

`2d0ee379cfe4de890bf3916405d18e192506fd97` repairs only private probe marker
placement; production/native/dependency inputs are byte-identical to ef61b156.
CI `41057774775` passes all 38 jobs. Copy `41057771623` passes; independent audit
verifies 3,225 inputs, 120 live / 300 inventory / 32 zero-avoidable checks,
E2EE/transcode/native-crypto counts, retained hashes, stable PIDs and clean exits.
The deliberately failed copy predecessor, cancelled duplicate correctness CI
and all earlier numerical reports are retained. SDK/TLS/crypto internals remain
explicitly unmeasured under the user's accepted standard-Dart-SDK scope.

VM profile `41106228701` on 2d0ee379 completes. Independent audit verifies all
3,224 inputs, three retained generated input files, native library digest and
all 18 snapshot hashes, and reproduces the hosted memory audit exactly after
normalizing Python tuples through JSON. The first raw object comparison fails
only on that tuple/list representation difference. There are no audit findings;
process identities, clean exits and group cleanup agree. FlatBuffers client
external usage is 34,165,208 bytes after the workload and 112 after its diagnostic
GC request (CBOR 5,902,848 -> 112; MessagePack 112 -> 112). This supports the
export-lifetime investigation; neither these snapshots nor diagnostic GC are
performance acceptance.
The earlier tooling-head local verification's dependency-network exit 124 remains
recorded. A prior ef61 verification log reaches every VM/native/consumer and both
browser successes, but its expired exec handle retains no direct final status.
Do not relabel either history as an observed full verification exit 0.

The implementation, archived checkpoints and evidence details are retained in
[the active execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md)
and [the RAM research record](research/2026-10-28-flatbuffers-runtime-memory.md).

## Other shipped work

[MQTT PR #128](https://github.com/konsultaner/connectanum-dart/pull/128) is merged
as ef822e08. Preserve its native QoS 0 TCP/TLS/WS/WSS implementation and existing
CI performance gates. Remaining MQTT work stays in
[its plan](exec-plans/2026-10-14-mqtt-broker-interoperability.md) and
[milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2).
Current README tables and fixtures remain in-tree; historical MQTT benchmark
runs are preserved in the [verified immutable archive](benchmarks/README.md#archive).

The separate [connectanum_objectbox_adapter 3.0.0-beta.8](https://pub.dev/packages/connectanum_objectbox_adapter/versions/3.0.0-beta.8)
was published via [PR #133](https://github.com/konsultaner/connectanum-dart/pull/133).
Do not expand the separate old-DLL callback compatibility issue #134 here.

The scalar-context candidate's full benchmark suite now passes all 2,867 tests;
focused tests and targeted analysis also pass. Native lifetime renewal on
6575b7e9 independently reproduces three six-row/twelve-observation positives
and the expected zero-row/single-failure negative, with stable PIDs and clean
shutdown. Preserve the private audit's initial exit_code/process_exit field
lookup error; the corrected audit does not change evidence.

Latest CI 41165321973 has an MQTT performance failure. All 32 MQTT summaries
independently reproduce exactly with unchanged budgets and library hashes;
four absolute gate profiles fail (TCP CPU for versions 5/3.1.1 and clear WS
throughput for versions 5/3.1.1), and matched controls retain their failures too.
The candidate native digest is byte-identical to the preceding all-green f16ae5
run; different runner CPU models are recorded, not asserted as the cause.
Investigate before claiming clean CI. Do not retry unchanged numerical jobs
for a favorable runner, weaken gates or mark PR ready.

## 2026-10-31: scanner component verified; event-queue pacing candidate

Hosted scanner component 41172911103 succeeds: independently verify 3,279 source
inputs, four resolved inputs and 219 private artifacts; all 160 rounds and the
summary reproduce exactly. Complete RESULT decode time falls 3.38%, CALL 1.81%;
managed allocations fall about 384/373 bytes per decode. Both private correctness
suites pass. See research/2026-10-31-flatbuffers-cbor-chunk-component.json. This
isolated component is not transport, RAM or primary acceptance.

Latest e02d6c CI still fails MQTT absolute TCP CPU and clear WS throughput gates
on EPYC 7763. All 32 summaries reproduce exactly; native ready-write batching did
not establish repair. Retain its failed job log/artifacts; no lucky runner retry.
The 35f4b8 three-case diagnostic now passes every native metric and Dart-values
throughput, but Dart RSS median 1.0047214, GC upper CI 1.1915303 and p99 upper CI
1.052348 remain failures. No gate is changed.

The new router candidate replaces only per-busy-pass zero-delay SDK timers with
a reusable RawReceivePort event. It preserves idle timers, wake flags, scan order,
full payload work and workload/measurement policies. Pending work keeps its
isolate alive; idle ports do not, and boss-loop finally closes its port. Fail-first
reproduces eight SDK timers before the change, zero after. Ten focused tests pass,
including original-zone continuations, timer/message progress, pending close,
reuse and natural child-isolate exit. Targeted analysis passes. The first broad
router attempt fails because the new worktree lacks its native library; preserve
that setup failure and rerun with the existing source-identical native build.
Local advisory tests/judge are blocked by the shared native-mutation resource
lease; do not bypass it. The native-enabled rerun passes all 636 selected router/MQTT tests (six existing
skips); targeted analysis also passes. Performance and final canonical
verification are still required. No numerical improvement is yet claimed.

Full 48-case primary and 50-case supplemental 35f4b8 campaigns remain running and
must be retained to completion. Older f16 supplemental retains all 1,500 raw rows;
38 validated cases reproduce 176 cost diagnostics, while payload precision leaves
four aggregate findings. Two SDK-limited allocation metrics remain a separate,
unanswered product decision. No acceptance, readiness or milestone closure.

## 2026-10-31 07:07 UTC: final-candidate correctness/copy pass, RAM still fails

Published runtime 4b99d15d5bac88c6fa611bbbdfae5d06f83117e6 combines a83d85 scalar
CBOR scanning with reusable busy-loop event turns. Canonical bin/verify passes
on the clean frozen PR worktree with HEAD unchanged; log SHA256
65d3083ec58df6bba2f4efc3d39ed9d39cecf407987df91d7e64dce4723cb33a.
All Rust/tooling/VM/native/router/consumer/standalone and Chrome JS/Wasm suites
pass. Earlier dependency/setup and incomplete local-review attempts stay retained.

Paired diagnostic 41176299437 independently reproduces all 90 rows/three cases
with inputs/binaries verified. Six numerical findings remain: Dart-values
throughput median .99372646, p99 median 1.06333568 / upper1.11837456, GC median
1.06951168 / upper1.27463089, RSS median1.03226995; native-buffer RSS1.00888312
(upper1.12594078), pre-encoded RSS1.00577164. Native other metrics all pass.
Dart RSS median per-role delta is client +9,179,136B, server +1,073,152B against
the same per-repetition better memory baseline. These peaks do not identify
allocation sites; no claim that RAM is fixed. Full 48/50 campaigns 41176301519 /
41176304174 remain running and must finish. No gate, sample/window, body work,
VM/allocator flag, validation or copy scope is changed. No unchanged lucky rerun.

Copy/lifetime 41176306351 passes: independently check 3,284 source/resolved inputs,
120 live / 300 inventory / 32 zero-avoidable checks. Live E2EE/transcode/native-
crypto 96/120/48; inventory96/60/72. Three native positives each retain six rows /
twelve observations with stable PIDs; negative has zero rows/one expected failure;
clean exits and group cleanup agree. Build-directory native inputs retain hosted
digest invariance attestations, not independent rehashes of missing binaries.
All 20 absolute plus 12 matched MQTT summaries in 41176297129 reproduce exactly
with unchanged budgets; all candidate gates pass, native controls pinned master
ef822e08. CPU9V45 differs from failed7763, so causal older-runner repair is not
claimed. CI has23 successful jobs/no failures at this checkpoint and remains active.

VM profile41177813663 verifies3,283 inputs, retained native digest,18 snapshots,
exact hosted audit and clean cleanup with no findings. Its heavy class census
and diagnostic GC are not acceptance. External usage after diagnostic GC112B;
no persistent native-owner leak is proven. Weak properties52/~1.6KiB and one Mint
cannot explain multi-MiB RSS excess. Targeted standard-SDK/glibc RSS attribution
41178785283 is queued to inspect heap/native process footprints; never subtract
free bins, force acceptance GC or replace allocators. Explicit native-frame release
already detaches its sized native finalizer before malloc.free; SDK internals
remain unmeasured. Request/result owners
already dispose/release in finally; don't repeat these rejected leak hypotheses.

Older full primary41159934237 finishes:48cases/1,440rows,104 numerical misses,
zero integrity findings, exact independent reproduction; full metrics include
34RSS/22CPU/19throughput/13p99/12p95/3GC/1allocation misses. Old f16 supplemental
all1,500 raw rows remain: exact aggregate38validated cases/1,140rows/176costs and
four findings, payload precision exclusion retained. Newer35f4b8 full campaigns
continue to completion. Separate two SDK allocation-precision figures still need
a product scope answer; standard-SDK copy scope does not waive precision.

Completed Qwen review/GLM judge are advisory. Alleged synchronous thread races
are impossible in one Dart isolate; port reuse, pending keep-alive and root-zone
success completion are verified by tests. Suggested idle-close regression already
exists and awaits an actual pending idle wait within one second. Keep existing
wake-check logic unchanged. Qwen test suggestions reopen/busy-close are covered;
other synchronous interleaving claims are rejected. No extra code change follows.
PR132 remains draft; do not merge, retarget, close103 or close the milestone.

## Validated root-envelope record candidate (2026-10-31)

Allocator/RSS diagnostic41178785283 completes all six fresh process cohorts /
60rows and24role snapshots. Independently verify3,280 source inputs, retained
binary/wrapper digests, unchanged policy, every raw row, exact summaries, stable
PIDs and cleanup with no finding. Fresh cohorts show substantial VM page-cache,
main/service-isolate and allocator differences; they do not localize a persistent
owner leak or waive the actual failed RSS gates. No subtraction/custom allocator.
Private loopback probes preserve two successful2MiB native releases and aligned
64KiB Dart-owned whole frames (bodyoffset204mod4=0). An initial64KiB assertion
wrongly required a native allocation despite complete SDK frames; preserve it as
a probe assumption failure, not a product defect. Original test was restored.

A separate candidate removes only the temporary outer root Map during frame
reading. It returns a typed tag/body/metadata record after the same full generic
validator, uses generated root field widths/union references and retains the
existing body table reader. The old Map API is unchanged. No wire, schema,
validation, bytes/cursor, payload/model, native code or policy changes. Shared
body table/string cache identity and mutable byte-view aliasing are preserved.
Six new API/differential cases cover defaults, absent metadata, aliases, shared
physical tables with different schema types and every one-bit root mutation in
the fixture. All3,552 serializer tests and targeted analysis pass. Initial tests
incorrectly required ByteBuffer wrapper identity; corrected direct mutation tests
prove actual shared storage. Both histories remain retained.

Completed Qwen review's enum/union bounds and null-body claims are excluded by
unchanged full validation (enum membership and nonzero/in-range union tags checked
before any read); table() has a nonnullable Map return. Copying metadata would
break the intentionally unchanged borrowed-byte contract. No confirmed finding.
Keep the new API tests in their own file: existing shared component suites can
run unchanged on both source variants, and all six new cases run on the actual
candidate. The existing component isolation already permits precisely frame.dart
plus wire_reader.dart. Measure against4b99d15d before integrating; no transport,
RAM or primary acceptance is yet established for this optimization.


The807ff2f0 root-envelope component41181756276 now passes: independently verify
3,281 source inputs, four resolved inputs,219 private artifacts, exact original
frame/reader files for both variants,160 raw rounds and exact summary. Both shared
correctness suites pass; all six new API tests and all3,552 serializers pass on
the actual candidate. RESULT elapsed ratio .92929817, allocated3,055.64688 to
2,880.72624B/decode; CALL .93981717,5,696.25324 to5,510.9956B/decode. This isolated
complete model decode preserves the10KiB byte-vector contents and is never
transport/RAM/primary acceptance. Adopt the measured implementation, then freeze
and renew canonical verification, CI, paired/full/supplemental and copy evidence.
Earlier4b99d15d full verification/copy proof remain valid predecessor evidence;
its six numerical misses remain failures. No gate or workload changes occur.

## Serializer wrapper registration repair (2026-10-31)

First fd983af8 frozen bin/verify exits1 on five existing inventory assertions:
the new envelope test was absent from four CBOR/MessagePack VM/web support-file
sets and the shared wrapper imports/group. Preserve the clean-head failure
receipt and CI Fast Checks job124482556278 log. Fix by adding the file to all
four inventories and the shared wrapper, without changing any inventory check.
All87 verification-script contracts now pass; the complete VM wrapper runs3,697
cases and Chrome JS wrapper3,702 cases, including all six envelope cases.

The original per-loop exception-capture differential test also fails under the
full browser wrapper. Per-call normalized outcomes retain every one-bit mutant
and compare the exact decoded fields or rejection type without a captured loop
failure variable. All six cases pass on VM/Chrome, the complete Chrome wrapper
passes, and targeted analysis is clean. The hardcoded browser-path attempt and
its missing-executable failure remain retained; use canonical ensure_chrome_env.
Do not claim an SDK or production parser defect from those test/setup failures.

These changes affect only tests, verification inventory and documentation. The
production code, native sources/build, workload/scenario/policy, measurement
windows and serializer wire behavior remain byte-identical to fd983af8. Keep its
running numerical campaigns; do not repeat unchanged measurements for a favorable
result. Renew full canonical verification and CI on this repair, retain runtime
input equality evidence, and renew owned copy/lifetime checking as needed.

## Current acceptance checkpoint and bounded text candidate (2026-10-31)

Full canonical `bin/verify` passed on clean frozen `40ddcb3f`, including the
serializer inventories and actual Chrome JS/Wasm suites. Receipt log SHA-256:
`b2e3621a1b276e4e32325fdb61d25e33d3bf5af539cb7ee5f6153bf108bdf7da`.
Its production inputs are byte-identical to `fd983af8`; retain that revision's
running numerical campaigns rather than rerunning unchanged measurements.

The independently reproduced 90-row diagnostic `41182487687` has exactly two
numerical misses: Dart-values summed sampled peak RSS median 1.0028886482 and
native pre-encoded RSS median 1.0067350799. All other metrics in all three cases
pass. These three cases are diagnostic evidence, not the complete acceptance
matrix. The predecessor `35f4b84c` full campaign `41169321811` finished with all
48 cases / 1,440 rows retained, exact hosted comparison, 93 numerical misses and
zero integrity findings. The final-runtime full 48-case and supplemental
50-case campaigns remain pending; their results must be checked in full.

Current-head owned-copy run `41183917422` independently verifies 3,286 inputs,
120 live rows, 300 inventory rows and 32 zero-avoidable-copy rows, with the native
view controls and cleanup checked separately. E2EE and transcode accounting
remain within the approved Connectanum-owned scope; dependency internals remain
unmeasured. The allocation-precision scope decision is separately unanswered.

Current CI `41183915691` fails its MQTT WebSocket throughput gate on EPYC 7763:
matched master and candidate libraries both fail both WebSocket profiles in both
rounds; the TCP 64 KiB profile passes. Independently reproduce every unchanged
budget and all 32 summary files from their raw rows. The earlier 4b99d15d CI pass
on EPYC 9V45 does not resolve this runner-specific failure. No lucky retry or
weakened budget is authorized.

A separate candidate shares at most 64 immutable ASCII strings of at most 64
characters while decoding metadata and native projected text. It compares every
byte before reuse, keeps strict UTF-8 fallback and retains no input byte view,
payload or external owner. All existing structural and CBOR validation remains.
Collision churn, input mutation, independently mutable decoded maps, logical
readonly byte ranges, empty/long strings, Unicode, BOM and malformed UTF-8 cases
are covered. All 3,554 serializer cases and 155 CBOR cases on VM, Chrome JS and
Chrome Wasm pass. All 2,684 native VM/kernel cases pass with concurrency=1; analysis is clean.
Measure the candidate
against 40ddcb3f before adoption; it is not yet a demonstrated RAM repair.

The first broad native command incorrectly combined native global-runtime tests
in concurrent suites and selected unsupported browser compilation. Retain both
failed setup runs. Use explicit VM/kernel and concurrency=1, as in the canonical
native verification path. Do not report these setup failures as serializer bugs.
Completed local review has no confirmed finding: utf8Range explicitly returns
false for any non-ASCII sequence, and every cache hit compares all bytes. Its
conditional UTF-8 warning and collision warning were checked against source and
VM/browser tests. Keep PR #132 draft; do not merge, retarget, close #103 or close
the milestone before final-runtime strict acceptance is complete.

## Bounded text measurement and validation refinement (2026-10-31)

Isolated candidate 79c9dced component run 41187993679 is independently reproduced:
3,282 source inputs, four resolved inputs, 219 retained private artifacts, exact
variant scanner/reader sources, all 160 raw rounds, tests and cleanup. RESULT
elapsed ratio is 0.98983963 and managed allocation falls from 2,880.7288 to
2,735.17248 bytes/decode. CALL allocation falls from 5,511.0452 to 5,343.0556,
but elapsed ratio 1.02589399 is a regression. Keep that measured result; do not
adopt it as a RAM repair or retry its unchanged code for favorable numbers.
The checked-in short-text component receipt records the mixed result explicitly.

Refine cache lookup to compare every byte against a known ASCII String before
performing a second ASCII scan. A hit itself validates every current input byte;
no validation proof is inherited from a prior buffer or message. Bounds checks,
CBOR item/depth/byte budgets, duplicate-key checks, chunk validation and metadata
semantics remain. A miss uses the existing validator. The native text entrypoint
uses strict UTF-8 decode on a miss; equality of byte count and decoded UTF-16 unit
count proves ASCII before caching (every non-ASCII scalar uses more bytes than
units). BOM handling also reduces that count. The cache still retains only up to
64 immutable Strings of at most 64 characters, with no borrowed owner.

New checks warm the text cache before corrupting UTF-8 or truncating the logical
input; both are rejected. Native text tests compare all UTF-8 code-point width
boundaries, BOM, malformed sequences, arbitrary readonly offsets and collisions
against the standard decoder. All 3,554 serializers, 1,952 native-binding VM
cases and all 155 CBOR cases on actual Chrome JS and Chrome Wasm pass. GLM finds
no concrete defect in the validation equivalence. Its statement about Dart not
stripping BOM is not relied on: the unchanged strict SDK decoder supplies the
actual value and the proof excludes non-ASCII/BOM bytes either way. Review and
independent component measurements are required before adoption.

The predecessor 35f4b84c supplemental run 41169323042 is fully retained and
independently merged exactly: all 1,500 raw rows (1,050 measured), 50 declared
cases. Protocol contributes 127 numerical findings and encrypted/progressive
48; payload sizes have 16 valid numerical findings plus 30 allocation-precision
findings. The exact aggregate excludes that invalid payload shard, retaining
38 validated cases / 1,140 rows, 175 numerical findings and four findings.
This remains failed predecessor evidence, never complete supplemental acceptance.

## Revised text evidence and MQTT literal matching (2026-10-31)

Revised d6d188fa component 41188935493 independently verifies 3,283 inputs,
four resolved inputs, all 219 private artifacts, exact scanner/reader sources,
all 160 raw rounds, unchanged model bytes/aliases, tests and cleanup. RESULT
elapsed ratio improves to 0.94692797; managed allocation falls from 2,880.72368
to 2,735.1776 bytes/decode. CALL allocation falls from 5,511.12464 to 5,343.15096,
but elapsed ratio remains 1.02677092. Record that regression explicitly. The
candidate proceeds to whole-transport measurement for its allocation reduction;
component evidence does not establish RAM repair or overall performance parity.
Completed GLM/Qwen reviews have no confirmed defect after source/test audits.

Investigating the red MQTT gate exposes avoidable per-publication topic lists.
After the unchanged dollar-topic restriction, compare literal filter/topic text
directly; return false for a mismatched filter without wildcards. The existing
wildcard matcher remains. No packet framing, delivery, queue, flushing, wake,
budget or benchmark workload changes occur. All 52 new real-broker behavior
cases pass before the change, covering both versions, literal prefix mismatches,
Unicode normalization differences, ordinary '*', dollar topics, empty/trailing
levels and wildcard edge cases. Afterward all 85 QoS0 integration cases pass
(one optional Paho skip), plus 21 actual native-router MQTT cases (six existing
platform skips). Analysis and diff checks are clean. Local review's reported
findings explicitly re-evaluate themselves as correct unchanged behavior;
no corresponding source defect is present. This is not yet a demonstrated repair
of the hosted EPYC 7763 throughput failure: renew the unchanged full CI budgets.

The clean 40ddcb3f pre-change canonical bin/test-fast completes successfully in
its separate worktree; log SHA-256
b21d5d0759b825e44e773c517581353595871f1dc9f53b85f974260db865a68a.
Keep the experimental candidate isolated from PR132 until its complete strict
transport evidence is assessed. Freeze the combined candidate for canonical
verification and run paired diagnostics and CI; retain every failed predecessor
and every row from the older full primary/supplemental campaigns still running.
No threshold, measurement window, body generation/verification or copy scope is
weakened, and the separate supplemental allocation-precision decision is pending.
