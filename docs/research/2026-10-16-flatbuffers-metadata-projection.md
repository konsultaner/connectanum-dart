# FlatBuffers metadata projection and prepared native frames

Issue: [#103](https://github.com/konsultaner/connectanum-dart/issues/103).
Acceptance budgets and the primary/supplemental inventories are unchanged.

## Measured reason for the change

The last accepted diagnostic evidence remains the failing 90-row run on
`8be8d5c0`: CPU ratios 1.05537 / 1.08584 / 1.07985 and native-buffer allocation
1.05014. All allocation and sampling boundaries in that run validate.

The Linux CPU diagnostic on `0b9ebbc9` now [completes successfully](https://github.com/konsultaner/connectanum-dart/actions/runs/38885670705).
All three serializers have actual operation windows containing the entire native
sampling interval. Source/library hashes remain unchanged; both PIDs and process
group teardown are recorded. Raw Dart profiles, native perf data and native leaf
and inclusive reports are retained. Frame pointers/debug info perturb execution;
this is attribution evidence, not a parity campaign. Inclusive native FlatBuffers
parse occupies approximately 0.98% of combined captured samples; overlapping
inclusive entries must not be added.

A separate standard-SDK allocation trace warms both serializers before tracing
exactly 100 native-buffer RawSocket cleartext RPC operations per serializer.
Source `0b9ebbc9` and all source inputs remain unchanged. It records 31,588 traced
client allocations for MessagePack and 50,583 for FlatBuffers. The active router
worker records 37,987 / 59,052 respectively. These are selected object allocation
traces, not allocation byte totals or performance measurements. Other router
isolates are retained separately and must not be mistaken for that worker.

FlatBuffers client stacks include 1,400 allocations under projection while
re-reading the just-built control frame for an outgoing profile check, another
1,400 under the original write projection, and 2,200 under call-option dictionary
construction. Router stacks independently identify the same projection/dictionary
families. This motivates removing repeated work while retaining all validation
and mutation semantics.

Local evidence is retained under `out/flatbuffers-milestone-finish/`:
`allocation-owned-0b9-v2-source-audit.json`, its summary, original per-isolate
traces and `linux-cpu-0b9ebbc9/`. CPU/allocation instrumentation is never submitted
as macro performance acceptance.

## Implementation boundary

Ordinary native typed CALL/PUBLISH sends already check the session phase, project
and validate their supplied model through the common writer, freeze the control
buffer and validate composition with the retained payload owner. They can submit
that internally constructed frame without decoding a second model from it.
Immediately before native submission they recheck the live connection and current
session phase, because lazy metadata loaders may execute application code.
Session state commits only after native submission succeeds. Frame/control
cleanup and payload ownership remain unchanged.

Caller-supplied `sendNativeFrame`, tracked frames and pre-encoded buffers retain
their complete reader/profile validation. Encryption is ineligible for this typed
cleartext helper and keeps its existing path. No arbitrary pointer is adopted.
No payload buffer or metadata validation is skipped at a public input boundary.

CALL/PUBLISH/YIELD dictionary construction uses one fresh typed map instead of
short temporary lists, MapEntry objects and an additional projection copy.
Insertion order, explicit false/zero values, existing explicit null YIELD progress
and custom-field override precedence are preserved. Schema lookup tables are
built once from the pinned generated schema instead of scanned with per-call
predicates. Retained dictionaries and model mutation reconciliation are unchanged.

## Verification and remaining acceptance

All 3,386 serializer VM cases pass. The native profile suite passes the initial
optimization. Additional rejection tests cover malformed declared fields,
`forward_for`, unsupported values, owner reuse after rejection and a connection
closed from a lazy metadata loader. The last case first fails with native error
-10, then the connection check restores StateError before submission.

An initial fast attempt overlapped source edits and child compilation and is not
accepted as a frozen baseline. An ownership test attempt incorrectly selected the
production library for three test-only symbol probes; the corrected ffi-test
library rerun passes. Failed logs remain retained. Fresh resulting-source full
verification, focused allocation attribution and Linux macro comparison remain
required. No issue or milestone acceptance checkbox is changed by these tests.

The local review's three suggested regressions were checked against source:
explicit null YIELD progress and custom override precedence both predate this
patch; null-coalescing throw does not allocate on a successful lookup, and schema
tables are generated constants. The suggested synchronous reentrancy risk is
addressed with the live-connection/phase checks and regression test.
