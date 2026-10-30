# Project State

Last updated: 2026-10-30.

Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
Branch: `codex/flatbuffers-performance-parity`, [PR #132](https://github.com/konsultaner/connectanum-dart/pull/132).
PR #132 remains draft. Do not merge or claim performance acceptance yet.

## Current work

Current pushed tooling head: `da46d7f6`, runtime-identical to `40f8cec5`.
Its full local verification exits 1 on two newly merged encrypted FlatBuffers
file-transfer tests. Both now pass after validating authenticated decoded header
metadata while retaining the ciphertext view; plain opaque headers still fail.
An additional fail-first ownership regression proves that public reanchoring
can release another allocation instead of the retained storage. Explicit release
now follows `storageOwner`; both native and ordinary Dart-owned cases pass.
The live RPC regression uses the canonical external FlatBuffers peer and checks
actual backing ownership (a complete SDK Dart frame correctly needs no native
release). Earlier private probes with a wrong peer/ownership assumption are
retained and are not production failures or acceptance evidence.
Focused client lifetime/file suites pass 512 cases; socket/file contracts pass
186 cases and both encrypted live transfers pass. Renewed full `bin/verify` is
running on these changes. Qwen review completes: its double-free/race claims
are excluded by existing idempotent release guards and immutable payload owner
fields; its test null-owner concern is excluded by constructor initialization.
Its metadata cleanup concern does not establish a newly retained owner.

CI `41113454274` has a failed MQTT performance job (four cleartext TCP/WS
profiles); master CI `41105562746` passes that job. The budgets and MQTT source
are unchanged. Inspect retained raw profiles before attributing the regression;
no gate relaxation or selective acceptance is allowed. Other jobs are pending.
Full 48-case primary and final-runtime 50-case supplemental remain pending.

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
