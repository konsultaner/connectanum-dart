# Project State

Last updated: 2026-10-30.

Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
Branch: `codex/flatbuffers-performance-parity`, [PR #132](https://github.com/konsultaner/connectanum-dart/pull/132).
PR #132 remains draft. Do not merge or claim performance acceptance yet.

## Current work

Current frozen runtime: `40f8cec585939af2f6cf402939f435c689b6c6c4` (pushed).
Renewed CI `41112069093` fails Fast Checks and local full verification exits 1
on the same stale hard-coded mutation-range expectation: config correctly moved
from 1100–1257 to 1108–1265 after the verified eight-line insertion, but its test
still expects the old range. Correct only that test; all 93 contracts pass
(1 declared platform skip), with all 167 proof sites retained. No production,
policy, scenario, instrumentation or measurement change occurs. Renew CI and
local full verification on this tooling-only follow-up. Keep the running
paired diagnostic `41112077193` and copy proof `41112073189` untouched; preserve
all failed and superseded run histories. Full 48-case primary and final-runtime
50-case supplemental remain pending; numerical acceptance is not yet claimed.

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

Paired `41056036677` on runtime `ef61b156fb61572d7f4f0baf109e1393386fc2cd`
completes all 90 rows. Independent reproduction verifies retained source inputs,
production binaries and the exact hosted comparison. Only two RSS gates fail:

- Dart values: median 1.0087769550; 95% CI [0.9965808754, 1.0243417666].
- Native buffer: median 1.0285043000; 95% CI [0.9903861263, 1.0685564016].

All throughput, CPU, p95, p99, allocation, GC and pre-encoded RSS gates pass.
No integrity issue exists; diagnostic campaigns cannot establish primary
acceptance. Full 48-case primary and final-runtime 50-case supplemental remain
pending under the original strict budgets. Earlier supplemental runs have
numerical failures and remain diagnostic history, not acceptance for this source.

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
