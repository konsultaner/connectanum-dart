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
both warmup); actual sampled RSS remains available. Failed and
unavailable observations remain retained; no gate or inventory is relaxed.

Full frozen `bin/verify` on `87b89830` subsequently passes with all 3,113 inputs
unchanged. The first production-native profile passes its 12 real cases on all
five platforms but an outdated declaration still requires 10. Updating that
exact declaration to 12 and showing expected/observed counts preserves strict
rejection of omitted, skipped or unfinished cases. All recorded profiles and
focused verifier guards pass; complete replacement consumers remain required.

## Reuse validated fields in native composition

The fresh Linux profile on `7452ab61` succeeds with source/library unchanged,
confirmed operation windows and complete process teardown. Inclusive native
composition accounts for 1.54% of sampled combined CPU; its parse child accounts
for 0.80%. These overlapping samples are not added or treated as macro costs.
Source inspection shows composition parsing a complete control frame and then
reprojecting its metadata dictionary and CBOR-encoding it before writing the frame.

The parser now has a private tuple-returning helper retaining its validated wire
fields; the ordinary parser returns the same ParsedMessage as before. Composition
retains every original control and metadata byte, changes only application slots,
and explicitly validates supplied containers. The inner Arc is borrowed in place
to avoid an unnecessary clone. No incoming validation, frozen-owner check,
producer identity check, public API or schema changes. The supplied-payload match
remains limited to the same nine payload-bearing message variants.

A new regression first fails because metadata keys are re-ordered during
composition. It now verifies exact metadata bytes, independent generated-reader
acceptance, unchanged controls, correct decoded values and original application
allocation identity. The all-25-message fixture test additionally rejects wrong
container roots, excessive nesting, mixed ordinary/opaque payloads and payloads
on unsupported message types. All 384 core and 295 FFI library tests pass, as do
71 Dart native/frame/network cases and the independent 33 upstream / 42 extended
fixture, bidirectional, all-model and live RawSocket/WebSocket checks. Bindings
remain unchanged. Initial interop invocations used the system Python/missing
flatc; the existing pinned virtual environment and compiler reruns pass. Failed
logs remain retained.

The stock-SDK macOS component measurement uses balanced old/new/new/old process
order, five warmed repetitions per process and 20,000 compositions per repetition.
Median component time is 4.49725 / 3.772925 us (ratio 0.83894). The original and
candidate production-library hashes are retained. This only verifies a local
component gain; it cannot establish Linux end-to-end CPU, latency or RSS parity.
Fresh complete verification and campaign evidence remain required.

The local judge's ownership concern is addressed by borrowing the inner Arc in
place; the raw frame owns Bytes, not the parsed field tree. Both local reviews'
validation concerns were independently checked against the full parser, unchanged
message-type match, payload validator, schema writer and adversarial fixtures.
Dispositions are retained in `retained-wire-compose-review-dispositions.json`.

RSS classification correction: the diagnostic has 27 warmup rows, not nine.
Missing lifetime readings at rows 3 and 13 are both warmup. All measured lifetime
and sampled readings are present; the original failing numeric gates are unchanged.


## Bound small leading RawSocket fragments

A local stock-SDK Dart-values profile on `8b92306c` passes source, library and
operation-window audits. FlatBuffers client attribution includes 66/1,708 samples
in `_send0`, compared with 35/1,652 MessagePack samples. These are CPU samples,
not call counts or comparable per-operation costs; macOS native sampling and
interference detection remain unmeasured. A separate fail-first controlled-socket
regression demonstrates three CBOR/MessagePack submissions and four FlatBuffers
submissions for a large opaque body, instead of a prefix plus body.

The candidate batches only a leading run of fragments up to 1,024 bytes each,
with a total prefix cap of 4,096 bytes including the actual negotiated four- or
five-byte RawSocket header. It never splits a fragment at the cap. The independent
prefix adds small, explicitly measured header/coalescing copies; every remaining
fragment keeps the existing `_send0` ownership anchor and bounded native-view
behavior. Large payload buffers remain borrowed. The optimization applies to all
fragment-capable serializers and changes no benchmark validation or gate.

All 93 socket cases pass, including 14 prefix boundary/error cases. They verify
wire equality, exact copy counts, retained body/subview pointers, original buffer
contents, prefix independence after source mutation, whole-fragment cap handling,
empty fragments, both header formats and copy totals after forced socket failure.
The Linux libc-pointer probe retains body-pointer, backpressure and EINTR checks;
its expected counters now reflect performed prefix/header copies rather than the
previous separate metadata input copy. Hosted execution remains required. A first
extra error-fixture compile attempt used a name inherited by Socket; renaming the
fixture field resolves it. Local review claims of cap overflow and missed copies
on socket failure are contradicted by the guarded increment and copy-before-send
ordering, with explicit passing regressions. Macro parity remains unestablished.


## Reuse native spans for canonical typed sends

The fully verified `792cd99d` checkpoint passes all 38 hosted jobs and all 180
five-platform consumers, plus renewed 300-row/120-case/36-combination accounting.
Its strict 90-row Linux comparison still fails. CPU ratios are 1.0057, 1.0185 and
1.0229 for values/native-buffer/pre-encoded; other gates also fail. All allocation
and RSS observations validate. A complete CPU profile passes on unchanged-source
attempt two; attempt one's failed CBOR perf recording remains explicit. Profiles
are attribution only, never performance acceptance.

Native send previously built a validated model into a native SDK control buffer,
parsed/composed that buffer in Rust, registered a temporary frame, queried its
metadata and transferred it. A real fail-first submission window observes 172
native control-string copy bytes, excluding the later incoming reply. The private
canonical Call/Publish path can use the already shipped segment ABI instead.

The SDK writes backwards. Writing the payload length first leaves that uint32 at
the end of the eventual prefix; `FlatBufferByteVectorReference` links its existing
builder offset without reading or copying the application allocation. An unused
float64 written next establishes eight-byte minimum alignment before the trailing
length word. The complete prefix plus body is an ordinary contiguous wire frame;
the private prefix alone is intentionally incomplete and never goes through the
public caller-supplied frame API. The prefix remains at most the 64 MiB frame
limit minus the payload; oversized cases retain the old rejection path.

Existing `ct_owned_buffer_send_segments` synchronously borrows/retains every
frozen allocation before queue submission. Its Frame retains control and
application owners through write/flush. The new path therefore disposes its
caller prefix handle after acceptance while preserving the body handle. Profile
commit and reuse counters occur only after acceptance, following a final
connection check after all model/profile accessors. Public raw-frame validation
and the existing frame-composition fallback remain intact. No new ABI or encoding
is introduced; the same pinned writer and immutable native allocations are used.

All 36 complete-wire shape cases pass for Call/Publish, zero/one/max IDs,
empty/three-byte/64 KiB bodies, initial-capacity growth and eight-byte offsets.
All 76 focused ownership/native/transport cases pass separately, including new
full-frame boundary rejection and zero native control-string copies. The
process-global native copy counter case reexecutes in an isolated child VM and
checks its actual successful completion. Combining unrelated native test files
reproduces global runtime teardown races; the canonical scripts already use
separate processes, and those failed combined runs remain retained.

A test-only copy of the production library hides the optional segment ABI version
export while retaining all other dynamic exports/addresses and machine code.
All 14 profiles pass with an explicit unavailable-capability/legacy-copy assertion.
This proves optional-capability fallback, not historical build compatibility. An
initial nmedit fixture changed symbol-table visibility without hiding the dynamic
export; its capability assertion correctly failed. The corrected fixture and all
hashes remain separate from production and timing artifacts.

A quiet old/new/new/old component probe, 5,000 warmups and 50,000 preparations per
process, measures mean 8.23754 versus 4.17613 us (ratio 0.50696). This experiment
excludes native submission, I/O, profile/session work and allocation acceptance;
it neither establishes macro parity nor predicts a full-workload percentage.
Advisory claims about wire non-contiguity, premature release and connection
checks were verified against actual concatenation, retention code, ordering and
executed tests. Fresh full verification, live accounting, cross-platform consumers
and Linux timing remain required. The first consumer profile now requires 14
cases, raising the five-platform total from 180 to 190 without allowing skips.
