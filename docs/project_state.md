# Project State

Last updated: 2026-10-31.

Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
Branch: `codex/flatbuffers-performance-parity`, [PR #132](https://github.com/konsultaner/connectanum-dart/pull/132).
PR #132 remains draft. Do not merge or claim performance acceptance yet.

## Current work

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
Source freeze, canonical verification and strict hosted renewal remain pending. A completed Qwen
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
