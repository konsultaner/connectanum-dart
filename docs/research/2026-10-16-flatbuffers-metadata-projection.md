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

## Candidate attribution and verification follow-up

On `f2b577ff`, the exact same warmed 100-operation trace exits 0 with HEAD and all
3,113 source inputs unchanged. Selected FlatBuffers client allocations fall from
50,583 to 38,665 (23.6%); the active router worker falls from 59,052 to 57,538
(2.6%). MessagePack client counts are 31,588 / 31,370 and router-worker counts
37,987 / 37,987. Small incidental setup differences are retained. This is selected
object attribution, not allocated-byte volume, CPU, or macro acceptance.

The frozen full verification on `f2b577ff` fails one WebSocket test after its
actual native submission/retained-byte assertions pass: a second test-only public
wrapper spy still expects interception of the removed internal round trip.
Source and all 3,113 inputs remain unchanged. The fixture now relies on its
existing native submission observer and independent peer result/codes; all 22
WebSocket network cases pass. Public caller-supplied frame tests remain intact.
The failed full run is not accepted; resulting-source full verification is needed.

The focused GLM advice was also checked against source. Its claimed send-before-
profile order is reversed: `prepareOutgoing` runs before `nativeBuffers.sendFrame`,
and `_commitSend` only assigns state afterward. On the actual native path, close
clears the connection ID synchronously and `_finishOpen` awaits
`openNativeConnection` before assigning another ID; a synchronous model accessor
cannot complete close/reopen inside that send stack. The explicit close-loader
regression covers the real reentrancy path. Advisory output and source dispositions
are retained; no unsupported finding is presented as a verified defect.

## Packed reply reproduction and repair

The subsequent uninstrumented Linux diagnostic on `f2b577ff` still fails CPU
parity for values, native-buffer and preencoded construction (1.08631, 1.07976,
1.07664), and native-buffer allocation (1.03508). All 180 allocation observations
validate. One warmup lifetime RSS endpoint is unavailable; measured endpoints are
valid. Attribution profiles and selected allocation objects are not parity.

An isolated observational typed native-buffer RPC probe finds the internal echo
handler returning one packed 65,576-byte binary argument. `_sendInternalInvocationResult`
constructs PPT details but omits those details when restoring its transferred
lazy payload. The existing restoration helper therefore cannot recognize the
binary wrapper as a packed PPT payload. The resulting model has materialized
arguments and enters general CBOR staging. Passing the four existing PPT fields
to restoration preserves the exact packed bytes; an after-fix two-operation probe
records `packed=65576`, `args=null`, `kwargs=null` and `pptDecoded=false` for both
results, with source and native library unchanged during observation. These logs
are correctness evidence, not timing measurements.

New tests fail before the correction for FlatBuffers, CBOR, MessagePack and
encrypted PPT replies, while ordinary binary arguments remain ordinary arguments.
Each resulting PPT reply survives all three outer serializers without decoding.
A progressive-response test also reproduces the existing `replyPort.first`
behavior discarding the terminal reply after the first progress reply. The router
now reads replies until completion, and checks authoritative invocation lifetime
for progressive calls so cancellation/disconnection retires the port and releases
its retained native loan exactly once. Progress never transfers that native loan;
the terminal native-forward branch explicitly requires `!progress`.

All 114 router worker/profile/native regressions, focused analysis and all 154
mutation proofs pass. The retained-loan test verifies that the first progress
reply keeps the handler pending and the loan alive, and caller removal retires
both with exactly one release. Advisory local reviews were checked against source;
rejected assumptions and the supporting invariants are retained in
`packed-reply-review-dispositions.json`. No new SDK, native ABI or payload schema
is introduced. Fresh full verification and timed Linux comparison remain required.

The current supplemental `progressive` cases exercise progressive CALL input,
not progressive RESULT streams. Result-stream performance/copy coverage must be
added explicitly before claiming the original issue's progressive-result scope.
Primary inventories and strict performance budgets remain unchanged.

## Packed-reply numeric follow-up

The 90-row Linux run on `01300605` completes all duration/sample floors and 180
independently recomputed allocation observations. Allocation gates now pass for
all three construction modes: 0.84549 / 0.89153 / 0.81924. CPU still fails at
1.03383 / 1.03914 / 1.03297. Several throughput, latency, GC and sampled RSS
point gates also fail. Two lifetime RSS values are unavailable (rows 3 and 13,
one warmup and one measured); actual sampled RSS remains available. Failed and
unavailable observations remain retained; no gate or inventory is relaxed.

Full frozen `bin/verify` on `87b89830` subsequently passes with all 3,113 inputs
unchanged. The first production-native profile passes its 12 real cases on all
five platforms but an outdated declaration still requires 10. Updating that
exact declaration to 12 and showing expected/observed counts preserves strict
rejection of omitted, skipped or unfinished cases. All recorded profiles and
focused verifier guards pass; complete replacement consumers remain required.
