# Project State

Last updated: 2026-10-31.

Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
Branch: `codex/flatbuffers-performance-parity`, [PR #132](https://github.com/konsultaner/connectanum-dart/pull/132).
PR #132 remains draft. Do not merge or claim performance acceptance yet.

## Current work

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
