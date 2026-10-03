# FlatBuffers and zero-copy native buffers

Status: active
Started: 2026-10-03
Baseline: `54eafc5fb675886a04d390f069714c69de2aaac0`
Branch: `codex/flatbuffers-zero-copy`
Milestone: https://github.com/konsultaner/connectanum-dart/milestone/1

## Objective and scope

Complete all ten milestone issues. FlatBuffers must be a regular WAMP serializer
beside JSON, MessagePack and CBOR, with Dart/Rust interoperability, native-owned
construction, borrowed-buffer leases, lazy routing, PPT/E2EE support and measured
performance at least matching the better CBOR/MessagePack baseline on declared
representative workloads. Generic native adapter readiness is in scope; actual
ObjectBox integration belongs to a separate connectanum_objectbox_adapter package.

The primary checkout has uncommitted router embedding/shutdown work. This managed
worktree starts from committed HEAD and must not alter or claim those changes.
The previous coverage plan is deferred in this worktree by the explicit new goal;
its unfinished coverage/mutation targets remain open.

## Work order and completion evidence

- [ ] #95: pinned interoperable binding, schema generation, message/metadata map,
  independent fixtures, compatibility and negotiation rules.
- [ ] #96: native-owned buffer/model builders, freeze/transfer/retain semantics,
  allocator/base/capacity/subrange identity and copy counters.
- [ ] #97: external owner leases, owner-affine release, bounded retention and
  observable local send completion across success/error/shutdown/fan-out.
- [ ] #98: complete Dart serializer/factories/exports and verified lazy payload
  handling across VM, browser JavaScript and WASM.
- [ ] #99: native Rust codec, RawSocket ID 5 and WebSocket negotiation, metadata
  FFI integration, authenticated live RPC/pub-sub and old-ABI rejection.
- [ ] #100: homogeneous and mixed-serializer routing, delayed/progressive/error
  paths and fan-out ownership without unnecessary payload materialization.
- [ ] #101: PPT and explicit E2EE profile compatibility, unchanged CBOR profile,
  typed payload negotiation and separately accounted transformation copies.
- [ ] #102: external conformance, malformed-input/fuzz and ownership-lifetime CI.
- [ ] #103: representative throughput/latency/memory/copy budgets, repeated
  controlled runs against CBOR and MessagePack and hosted benchmark evidence.
- [ ] #104: release/consumer documentation and artifact support, generic adapter
  examples, ownership matrix and ObjectBox C boundary without adapter code.

An issue closes only after every acceptance criterion in its authoritative GitHub
body is proven. Whole milestone completion additionally requires bin/verify,
hosted CI/artifact checks and recorded performance gates. Partial fixtures or
successful round trips do not establish complete codec/runtime support.

## Current checkpoint

The worktree and branch are created. Hosted baseline CI 37062527790 and package
dry-run 37062527796 pass at the exact baseline. Pre-change bin/test-fast exits 0 in
/tmp/connectanum-flatbuffers-baseline-fast.log.

Upstream schemas and serializer source at ca1e60c7f7dd78dc2df98a3b7bdc274ae197ae9c
are inspected. Important gaps: the union ordinal is distinct from the WAMP
message ID, arbitrary options/details have no representation, Map is one string
pair, required WELCOME fields exceed the basic WAMP requirements, and schema
revisions have changed union ordering. Preserve pinned fields/tags, append an
optional metadata root field, negotiate extended semantics and reject unsupported
downgrades explicitly. Verify this extension with unmodified upstream readers.

Gemma summary completed. GLM architecture review cannot connect to its independent
local server (connection refused); focused Qwen planning is available. The first
Qwen request reached its output token limit and will be narrowed before relying
on its advice. No milestone issue is complete yet.


## Foundation implementation checkpoint

Pinned seven unchanged upstream schemas and license, checksum-verified compiler
fetching, deterministic combined schema and Dart/Rust bindings. Append-only
metadata and HEARTBEAT extensions pass flatc conformance. The checked-in binding
document maps every discriminator/dictionary, defines capability/downgrade rules
and records upstream gaps. The pinned Autobahn high-level serializer is not a
working peer; independent generated Python readers are used explicitly.

Initial generated Rust compilation fails because its Result table shadows
core::result::Result; deterministic return-type qualification fixes it. Initial
Dart2Js fixtures fail because ByteData Uint64 accessors are unsupported. Portable
two-word uint64 reads/writes preserve actual integer bits and eight-byte alignment;
unsafe values and out-of-slice access are rejected. VM and both browser compilers
pass all 32 focused tests after fixing the browser-specific bounds-error matcher.
Python/Dart/Rust bidirectional CALL and large-ID/vector checks pass; unmodified
upstream readers consume all 25 upstream union alternatives and the metadata CALL.
Native tests prove encoded payload ranges point into the input buffer.

Schema checksum/version unit tests, regeneration checks and focused analysis pass.
The complete serializer mutation wrapper/support inventories include the new
binding tests; all 79 verification-tool regressions pass. The CI workflow has a
new mandatory binding generation/independent-interop job. The pre-change
bin/test-fast completes successfully. Full bin/verify is running in session
51940 with log /tmp/connectanum-flatbuffers-foundation-verify.log. No issue is
closed, no hosted new-head evidence exists and no transport support is advertised.

Gemma summary and Qwen focused planning/review ran. Review concerns about an
append-only root field are contradicted by flatc conformance and independent
readers; the script fails explicitly if pinned schema text/hashes change. Runtime
review attempts reached the local model's output limit; GLM remains independently
unreachable. Foreign-reader and VM/JS/WASM tests remain the authoritative checks.

## Next owned-buffer stage (#96)

Current legacy native allocation is uninitialized and its adoption reconstructs a
Vec using pointer/length as both initialized length and capacity. Keep that ABI
for existing copying callers. New builder APIs need explicit allocation base,
capacity, initialized range, used offset/length and safe owned handles. Allocate
zeroed builder storage: the upstream Dart builder relies on zero padding.

A native allocator can back the internal WampFlatBufferBuilder directly. Its
public wrapper must guard every mutation after freeze/transfer and expose no raw
writable aliases. Read-only exported views require an independent retained
native owner so explicit wrapper disposal does not invalidate a surviving view.
Use handle-backed validation instead of adopting foreign or interior pointers.
Reserve capacity and account separately for downward-growth copies. Existing
Dart sends and segment sends still copy; integrate new ownership submission
without removing the ordinary Dart-value path or older-ABI explicit rejection.

Investigate fb.Builder's complete mutation surface and native-owner finalization
before exposing the callback/model API. External borrowed leases, owner-thread
release and genuine drain/completion semantics remain #97, not implicit guarantees
of an owned allocation. Do not change sources during the current verification
without recording and rerunning the checks affected by the change.

## Foundation final validation

Fresh full bin/verify exits 0 in
/tmp/connectanum-flatbuffers-foundation-verify-final.log. All 34 focused tests
pass on VM, JavaScript and WASM. Independent upstream Python readers accept
27 fixtures (all 25 union alternatives plus metadata and typed-payload CALLs);
Rust verifies the heartbeat extension too. Foreign scalar/vector reads prove
inclusive 2^53 support and correct empty-vector alignment. The earlier narrower
ID limit is reproduced fail-first and corrected. Use an underscore-prefixed
metadata capability to follow WAMP implementation-specific key conventions.
Regeneration --check and git diff --check pass. No working transport codec,
performance parity, new hosted result or whole milestone completion is claimed.

Native buffer drafts are staged outside the worktree while validating this
foundation. Rust registry design moves initialized native Vec allocations into
Bytes::from_owner, preserving original base/capacity and explicit used range;
retained/empty slices and exported finalizer tokens retain the allocation. The
Dart builder uses guarded composition, including writeListOfStructs callbacks,
so no mutable builder/allocator alias escapes. Public scalar writes block
freeze/disposal during reentrant model/list callbacks. GLM architecture requests
time out; a narrowed Qwen slice/take review completes with no arithmetic or
atomic-removal finding. Broader review attempts remain incomplete.

Coverage preflight: the two generated Dart files contribute 3,425 executable
lines, of which the binding fixtures hit 573. The coverage collector classifies
these exact compiler-provenance paths separately, preserving raw per-file and
raw overall totals; it does not lower thresholds or apply VM ignore comments to
browser data. Fail-first classification/provenance tests and all 105 selected
coverage/generation/verification-tool regressions pass. All core VM tests pass
with coverage: handwritten 6,815/7,295 (93.420%), raw including generated
7,388/10,720 (68.918%). Every existing core VM policy check passes. This new
collector-only change follows the completed full library verification and is
validated by its focused tool tests. Full browser coverage runs in session 9175,
log /tmp/connectanum-flatbuffers-foundation-browser-coverage.log; no result yet.

## Pushed foundation and CI repair

Foundation commit 3ff76b9b1390f8f98f7d463511dcd23b4f70c2dd is pushed in draft
PR #105. Full browser coverage exits 0: core 7,487/7,748 (96.631%), client
2,777/2,859 (97.132%), preserving all floors and VM-ignore handling. Hosted
package dry-runs 37118172292 and 37118238076 fail on pub's single-version
flat_buffers dependency warning. Move the exact 25.9.23 conformance pin to the
unpublished workspace dev dependency and allow >=25.9.23 <25.10.0 in published
libraries; pin compiler, Rust and Python versions unchanged. Verify a clean
commit snapshot through the strict package dry-run before claiming repair.
The main CI runs remain queued; there is no hosted binding pass yet.

## Native-owned buffer partial implementation (#96)

Uncommitted Rust owned-buffer ABI v1 and VM-only public native_buffers.dart now
implement initialized handle-owned allocation, freeze/subranges, retain/slice,
independent exported owners and consume-on-submission sending. Rust preserves
base/capacity using Bytes::from_owner; no foreign or interior Vec adoption.
All six Rust ownership tests and ten Dart guard/model/export tests pass, and
focused Dart analysis passes. The fake old-library test must use a separate
system-library handle: DynamicLibrary.process() sees ct_ffi already loaded by
build hooks. Ordinary client sends remain available.

The Dart FlatBuffers facade implements the complete pinned Builder interface.
writeListOfStructs passes the facade into model callbacks; all writes block after
freeze or disposal and callbacks cannot freeze/dispose during an in-progress
write. Read-only list/ByteBuffer/ByteData/subviews survive wrapper disposal.
Constructor/finalizer setup failures release owned handles. Native builders
account for growth and raw byte-vector input copies separately from newly
encoded scalar/string writes. Public runtime allocation is lazy and optional;
older libraries reject the whole ownership capability explicitly.

Not complete: real accepted/queue-full transport sends, forced-GC derived-view
finalization, native allocation counters/performance proof, public transport
integration, shared router API, old-native-runtime fixture and canonical
coverage/mutation test inventories, broad/full verification and hosted evidence.
External owner leases/completion (#97) are still absent. Do not close #96 or
claim actual FlatBuffers transport support from these ownership tests.

## Native owned-buffer validation checkpoint

The complete owned ABI v1, public VM buffer/FlatBuffers facade and native
transport capability now have seven Rust and 18 Dart focused passing tests.
A standalone VM-service probe proves wrapper collection, derived ByteData
retention and actual allocation destruction after its final view disappears.
Independent C fixtures prove complete-symbol version rejection and distinct
library identity rejection before transfer. Live JSON RawSocket/WebSocket peers
receive both retained and transferred native frames. Controlled submission tests
prove the exact backward-subrange pointer and release on queue-full rejection.
The full verification of the earlier partial native candidate exits 0. The
expanded run first catches a newly added mutation-job audit inventory mismatch;
the proposed gate is deferred while its coverage remains inadequate, preserving
the existing hosted gates. A fresh full candidate verification runs in session
80399, log /tmp/connectanum-owned-buffers-verify-repaired.log.

A complete 99-mutant ownership diagnostic finishes with clean/restored baselines
and unchanged native artifact, but fails its 95% assertion gate: 69.697%
detection, 44.444% assertion lower bound. This is evidence for the earlier
13-test candidate, not the expanded 18-test suite. Missing default-range,
finish/reset/reentrancy and ABI-version/library-identity regressions are added.
The diagnostic remains registered; no score waiver or hosted green claim is made.
Expanded lifetime/fuzz/mutation hardening remains #102.

The package constraint repair passes all seven clean-snapshot strict dry-runs;
hosted package run 37119001156 and the binding job in CI 37119001152 pass.
Its Fast Checks also pass; Full Verify and remaining matrix jobs are pending.
The binding contract now requires positive pinned-layout acknowledgement by
default; an explicitly trusted upstream-subset peer must name the pinned schema
revision because old union ordinals can parse as layout-compatible wrong types.
The portable uint64 timeout bound is recorded separately from WAMP ID semantics.

GLM and Qwen now complete narrow requests. Their claims that SDK view tokens die
with wrapper collection and that repeated monotonic-handle release double-frees
are contradicted by the forced-GC/Rust tests and the handle-store contract.
The actual exported-token failure path is tightened: once asTypedList succeeds,
SDK backing storage remains the sole releaser even if the read-only facade
allocation fails. See docs/native_owned_buffers.md for the ownership matrix,
copy accounting and SDK sources. No performance-parity claim is made.

## Native physical-alignment regression

Source inspection identifies a real native-consumer defect missed by relative
Dart reads: flat_buffers aligns fields relative to the allocation end. A
1023-byte native capacity leaves a uint64-containing root at address modulo 8
of 7. A new test-only native observation reproduces the failure before changing
the allocator (/tmp/connectanum-owned-alignment-repro.log). Round every native
FlatBuffers allocation/growth capacity to eight bytes, preserving downward copy
ranges and accounting; generic byte builders retain arbitrary byte ranges.
The expanded focused 19-test candidate is running in
/tmp/connectanum-owned-buffers-alignment-fixed.log. Current full verification
session 80399 started before this alignment change; rerun affected suites and
fresh full verification before committing the final owned-buffer increment.

External-lease design judgment completed. Owner-affine release queues must offer
native waiting/wakeup and documented pumping rather than requiring an owner to
block on peer delivery. Retained limits remain charged until actual native
producer-thread release; queue starvation causes bounded rejection, not unsafe
release or unbounded storage. Buffer-release and local-write completion remain
separate observable states. Implementation of #97 is still pending.

The repaired full run 80399 exits 0. The physical-alignment fix then passes all
19 focused ownership tests and focused analysis. Final full verification is
running in session 82853, /tmp/connectanum-owned-buffers-aligned-verify.log;
its owned-buffer suite has passed all 19 tests. The external lease/write-completion
contract is captured as planned work in docs/native_external_leases_design.md.
No external capability is advertised. Qwen's claim that downward resize copies
new capacity instead of back+front is contradicted by the pinned allocator's
_copyDownward implementation; the existing copied-byte counter remains exact.

## Ephemeral allocator finalizer regression

Full aligned-candidate bin/verify 82853 exits 0. SDK NativeFinalizer documentation
requires the finalizer itself to remain reachable. Strengthen the GC child to
use ephemeral allocators and prove their collection too. It fails first with two
native allocations/handles remaining (/tmp/connectanum-owned-ephemeral-allocator-repro.log).
Retain one native handle finalizer per loaded library identity for process
lifetime; its monotonic stale-handle release remains harmless. All 19 tests and
focused analysis now pass, including allocator collection and derived-view
release. Final full verification runs in /tmp/connectanum-owned-buffers-finalizer-verify.log.
This supersedes the earlier aligned verification for final handoff. A broader
GLM registry judgment times out at 60 seconds; narrow completed judgments and
source/forced-GC evidence remain the authority. No issue closure yet.

## Remaining binding audit before closing #95

Focused source audit of current Heartbeat and session.fbs finds two additional
non-dictionary gaps: Heartbeat.ping/incoming/outgoing are nullable in the shipped
Dart/Rust models but the extension currently uses ordinary default-zero scalars;
Challenge.method is an AuthMethod enum while existing WAMP authentication accepts
custom method strings. Root metadata preserves only the existing dictionary
position, so it cannot fix these control-field gaps implicitly.

Before enabling the codec or closing #95, append a Heartbeat presence mask
(default all three present for existing fixture interpretation) and an optional
Challenge.method_name string. Preserve every upstream field/union tag and verify
flatc conformance plus absent/explicit-zero/custom-method cross-language fixtures.
Audit ERROR.request_type for HEARTBEAT ID 7 against the upstream MessageType enum.
Existing generic invalid request types need an explicit supported-code policy.

Authentication also precedes WELCOME. Negotiation rules must permit a router
that received the client's metadata feature in HELLO to acknowledge it in
CHALLENGE.extra before extended challenge/authenticate data is used. Anonymous
sessions acknowledge in WELCOME. Ordinary RPC/pub-sub still requires affirmative
binding identity. Bootstrap ABORT needs an explicit terminal/error policy rather
than blindly treating every pre-WELCOME extension as forbidden. These are design
requirements, not implemented codec/session behavior. Keep #95 open until the
wire contract and fixtures resolve them; #96 implementation can be committed
independently while its issue closure waits for its declared dependency.

Final native-owned candidate bin/verify 88323 exits 0, log
/tmp/connectanum-owned-buffers-finalizer-verify.log. All 19 ownership tests,
Rust suites, native integration, browser JS/WASM and SCRAM worker checks pass.
Only constructor/library-lifetime documentation changes after this run starts;
no functional code changes. SDK DynamicLibrary.close can unload callback code,
so the custom constructor explicitly borrows a library kept loaded for process
lifetime; managed runtime allocators are preferred. Hosted foundation Full Verify
and Core Browser Coverage also pass in 37119001152; remaining mutation jobs run.
Final narrow Qwen/GLM attempts hit output/deadline limits; prior completed narrow
reviews, source checks and fail-first alignment/ephemeral-GC regressions remain
recorded. Commit this verified owned-buffer increment, keeping all issues open
until the binding gaps and remaining milestone acceptance criteria are resolved.

## Binding control-presence and authentication follow-up

The preceding goal turn made verified progress: commit 6637e741 adds native-owned
builders and submission, passes full verification and all seven strict package
dry-runs, and is pushed to draft PR #105. Current-head package, binding, fast,
consumer and browser checks pass; Full Verify and mutation jobs are running.

Two fail-first generation-contract regressions reproduce missing nullable
HEARTBEAT controls and custom CHALLENGE control strings. Append presence:ubyte=7
after the three heartbeat scalars, and method_name:string after Challenge.extra.
The original seven upstream files and original heartbeat.bin remain unchanged;
flatc conformance passes. Nine heartbeat fixtures cover the original plus all
eight absent/explicit-zero masks; authentication/bootstrap fixtures raise the
total to 42. Fifty Dart tests pass on VM, Chrome JS and WASM, focused analysis
and exact regeneration pass. Independent unmodified Python reads 33 compatible
fixtures; derived readers check all 42 and Dart/Rust emitted extensions. Rust
also reads the Dart extensions. These are binding tests, not session-validation
or authenticated network-codec claims.

ERROR retains the upstream enum: its seven supported request codes exclude
HEARTBEAT, which has no correlated request ID. The checked-in contract records
the WAMP source and rejection policy. CHALLENGE may acknowledge the offered
metadata/binding feature before AUTHENTICATE; WELCOME still establishes the
session and requires the applicable role acknowledgement. Bounded terminal
bootstrap ABORT metadata grants no capability. Reserved heartbeat bits,
absent-bit/nonzero scalar contradictions and method-name/enum mismatches must
be rejected by the future codec.

Gemma summary and narrow Qwen planning/review complete. Qwen's union-ID examples
and sys.modules mutation warning are contradicted by the pinned tag map and
list(sys.modules) snapshot. Upstream input hashes make its speculative formatting
drift inapplicable. GLM initially refuses connections; its stopped service is
restarted and loading before the bounded contract judgment is retried. Fresh
full verification is required before committing this follow-up or closing #95.

SCRAM fixture parameters are typed explicitly (integer iterations and base64
salt), with a focused decoded-metadata assertion. Final focused count is 51 on
VM/JS/WASM; independent 42-fixture interop and regeneration still pass. Baseline
bin/test-fast exits 0 in /tmp/connectanum-flatbuffers-binding-audit-fast.log.
Fresh full bin/verify runs in /tmp/connectanum-flatbuffers-controls-verify.log.
The restarted GLM reaches healthy state; the first 55-second contract judgment
times out during reasoning, and a smaller bounded prompt is tried next. No
completed judgment is inferred from either reachability or a partial stream.

The smaller GLM contract judgment completes at 70 seconds. Its only suggested
clarification is explicit rejection of missing/false WELCOME acknowledgement
after a CHALLENGE acknowledgement; this follows the existing policy and is now
stated directly. Full verification is live in exec session 71200; poll that
handle rather than restarting the run. No functional change follows its start.
The planned #97 design additionally records pre-reserved frozen handles and
release-queue capacity, quota held through callback return, recursive-dispatch
rejection, and adapter-specific transaction resource limits. No lease API exists
yet and those requirements have no implementation evidence.


## Producer lease and token adoption checkpoint

Binding follow-up full bin/verify (session 71200) exits 0. Hosted Full Verify
passes at pushed 6637e741; remaining mutations still need their final status.
All issues remain open; no network codec or completed milestone is claimed.

Uncommitted producer ABI v1 registers foreign immutable spans via
Bytes::from_owner, with frozen handle reservation before resource consumption.
The bounded registry retains owners independently of transport shutdown;
last-reference drops enqueue native cleanup and notify the producer. Only the
registration OS thread can admit, wait, dispatch, close or destroy. Full-span
byte/count quota includes queued/in-flight cleanup. Reserved buffer handles
are invisible and roll back on failure. All 216 ct_ffi tests pass, including 15
lease/FFI and nine owned-buffer tests, in
/tmp/connectanum-external-lease-all-ffi-tests.log.

Dart adoption checks the complete optional producer symbol group, version,
store cookie and immutable handle, then consumes the native token exactly once.
The independent C pthread producer plus forced-GC Dart child passes: a derived
read-only ByteData retains the transaction after facade disposal/collection,
then cleanup occurs once on the original native owner thread. Additional old
ABI, wrong version, null/mutable/stale token checks pass. All 21 focused Dart
ownership tests and focused analysis pass.
Current focused test log: /tmp/connectanum-external-adoption-tests.log.

Qwen and GLM external-lease review/test-planning attempts time out at 90 seconds
without findings. The smaller GLM ownership judgment also times out after 60 seconds without
output; no completed review is claimed. This is a local companion limitation, not a task blocker.
Next: fresh candidate verification, then actual write completion and FIFO
writer drain, separate from lease-resource release and peer acknowledgements.

Fresh full producer/adoption bin/verify is running in session 64643,
/tmp/connectanum-external-adoption-verify.log. The binding follow-up is committed
as 722175ca; producer-lease/adoption changes remain uncommitted.


Producer/adoption full bin/verify (session 64643) exits 0 in
/tmp/connectanum-external-adoption-verify.log, including Chrome/WASM. Focused
analysis has no issues and all 21 Dart ownership tests pass. The new C fixture
builds with -Wall -Wextra -Werror. Producer changes are ready to commit; every
milestone issue remains open because acceptance audits and actual write
completion/fan-out integration remain pending. Temporary completion prototypes
are prepared outside the worktree and have not affected this verified snapshot.


## Native write completion candidate

Producer stage a93de717 and binding 722175ca are pushed; draft PR #105 now
reflects that reviewed scope. Current uncommitted candidate adds native frame
completion guards and a FIFO flush barrier to both writers, plus a bounded
six-symbol receipt ABI and public Dart tracked sends/drainWrites. Legacy drain
continues yielding an event-loop turn. Six native writer tests distinguish
partial writes, delayed flushes, queued/active cancellation, deferred failure,
slow fan-out and cancelled preparation workers retaining storage. All 338 core
and 218 FFI tests pass in /tmp/connectanum-write-completion-native-all.log.
All 23 Dart ownership tests pass in
/tmp/connectanum-write-completion-dart-tests.log; focused analysis has no issues.
The receipt GC child observes actual registry capacity returned after observer
collection while the already submitted frame reaches the peer. Complete,
missing-symbol and wrong-version receipt groups are checked independently of
the producer capability. Full candidate bin/verify is next.

A completed narrowed Qwen review claims unguarded map mutation. Installed
DashMap source contradicts it: RefMut contains RwLockWriteGuard, and get_mut
acquires the write shard. Reserved entries cannot be publicly removed, and the
RAII reservation returns count/entry on failure. No concurrency redesign is
justified by this finding. The earlier output-limited review is incomplete.

Combined real producer lending through delayed/native network writes and fan-out
still needs proof before closing #97. Full codecs, negotiation/routing/PPT/E2EE,
hardening, benchmark parity and release evidence remain in the goal. All ten
issues stay open; no milestone completion is claimed.

Full completion-candidate bin/verify is running in session 6724,
/tmp/connectanum-write-completion-verify.log. Do not start a duplicate verification
run while this session is active.


Write-completion full bin/verify (session 6724) exits 0, including Chrome/WASM,
in /tmp/connectanum-write-completion-verify.log. Prior turn is progress: committed
and pushed native producer leases, implemented actual writer guards/barriers and
Dart receipts, and completed full local verification. Next is combined lending
through native network fan-out and all remaining milestone work.

Focused Qwen network-test planning completes. Its suggestion that producer-wait
timeout abandons a write is incorrect: wait only reports cleanup readiness or a
timeout. Likewise quota cannot return while an exported owner remains alive.
The real test uses socket disconnect/runtime shutdown for abandonment and keeps
producer cleanup as a separate final-reference boundary.
