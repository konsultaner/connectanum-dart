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

CI repair takes priority before the next factory/transport/composition stage.
The verified router/native stage is committed/pushed as ab7f6718. On preceding
6727a18c, CI run 37162280263 has two completed failing jobs:

- Full Verify (111322014870): all three native retries time out at the actual
  slow local write-abandonment boundary in the transaction/fan-out fixture.
  Downloaded log: /tmp/connectanum-flatbuffers-profile-hosted-full-verify.log.
  Reproduce Linux socket behavior with the same producer lease and boundary;
  establish graceful-close versus reset/cancellation semantics rather than
  weakening the timeout or retry policy.
- Client message-binding mutation gate (111318008280): all 522 mutants finish,
  adjusted assertion score 93.794749% versus 95%, 18 survivors. Downloaded log:
  /tmp/connectanum-flatbuffers-profile-hosted-client-binding.log. Focused replay
  must identify missing FlatBuffers metadata/transparent-payload assertions;
  run the full unchanged target after strengthening meaningful contracts.

Run 37165046606 for ab7f6718 is in progress at this checkpoint; its package
publish dry-run passes. Superseded CI runs 37159768909 and 37162280263 are
cancelled after retaining the completed failures above. Local frozen-source
bin/verify remains valid local evidence, not proof of hosted success. All ten
milestone issues and their complete acceptance scope remain open.

CI-contract repair candidate:

- Before adding tests, the 42-candidate survivor replay reproduces all 18
  survivors (53.658536% adjusted assertion score). Add 26 real binding contracts
  for metadata resend/fallback/absence, HEARTBEAT wrapper handling, opaque span
  identity including empty buffers, and invalid flags/types/codes. The 1,839
  binding tests pass. The same focused replay now has nine additional assertion
  kills (75.609756%); this subset is diagnostic, not the full release gate.
  Full unchanged target: /tmp/connectanum-flatbuffers-binding-full-ci-repair.log,
  report directory /tmp/connectanum-flatbuffers-binding-full-ci-repair.
- Original lifetime fixture passes isolated Linux ARM64/AMD64, all 223 Linux
  ARM64 native cases and 20 repeated emulated AMD64 runs. The exact hosted
  failure has not been reproduced locally. Inspecting Linux TCP semantics shows
  shutdown sends FIN and retains the descriptor, whereas zero-linger close
  invokes reset. Make the intended interrupted-write fixture explicitly reset
  the peer; preserve actual producer memory, pending ownership, Abandoned=2,
  exactly-once owner-affine release and the original 5-second boundary. Improved
  failure context includes WebSocket/runtime-shutdown variant and terminal state.
  macOS/ARM64/AMD64 focused checks pass. References:
  https://man7.org/linux/man-pages/man2/shutdown.2.html and
  https://github.com/torvalds/linux/blob/master/net/ipv4/tcp.c (tcp_shutdown,
  __tcp_close and tcp_disconnect, inspected 2026-10-04).
- The emulated AMD64 full native run also reproduces two existing HTTP/3 fixture
  failures. Both client scopes drop before live native queries; a separately
  repeated nine-case HTTP/3 run returns ERR_NOT_FOUND at those queries. Retain
  endpoint/connection/request owners until the assertions and server shutdown.
  All 10 macOS and nine emulated AMD64 cases pass after that change, with existing
  sleeps and deadlines unchanged. Preserve initial full/isolated failure logs:
  /tmp/connectanum-flatbuffers-linux-amd64-full-native.log and
  /tmp/connectanum-flatbuffers-linux-amd64-http3-isolated.log.

Qwen's reset/outcome and round-trip concerns require source checking: the native
receipt has only Pending=0, Written=1 and Abandoned=2, and a WriteGuard drops to
Abandoned for errors/cancellation rather than requiring FIN or timeout. The new
metadata test reads a newly decoded object after serialization. The first GLM
request reaches its token limit; a narrowed review completes but incorrectly
describes receipt 1 as transient and runtime shutdown as merely FIN. Check the
actual guard/runtime ownership rather than adopting those claims. Keep hosted
confirmation outstanding. A fresh complete verification must freeze all product
source after the final candidate edits.

The latest pre-repair ab7f6718 Full Verify job 111329125365 subsequently fails
the same lifetime boundary on all three native attempts, with 222 other tests
passing each time. Save /tmp/connectanum-flatbuffers-router-head-hosted-full-verify.log.
The repair candidate passes all 235 emulated Linux AMD64 ffi-test native cases.
Canonical bin/verify30914 is running with 1,419 frozen product files, unchanged
through the latest hash check. Qwen's separate HTTP/3 review claims a named
underscore-prefixed local drops its returned tuple at block_on return; source and
the successful /tmp/connectanum-rust-retained-binding-probe.rs compiler probe
contradict that claim. The named local retains the actual endpoint/connection/
request owners until enclosing scope exit. Keep this distinction from the `_`
discard pattern explicit; no product change is required for that review claim.

Final CI-contract repair verification:

- Supporting bin/test-fast65769 exits0 but overlaps edits; it is not final
  current-source proof.
- Fresh bin/verify30914 exits0 at
  /tmp/connectanum-flatbuffers-ci-repair-verify.log. All 1,419 product file hashes
  and inventory match the frozen snapshot at completion. Native/default224 and
  ffi-test236, tooling, VM, router/consumer and Chrome JS/WASM checks pass;
  verification ends with 2,699 client WASM cases.
- Full unchanged client-message-binding-vm campaign46647 exits0. All 522
  candidates complete: 103 compile errors, 292 assertion-only kills, 110 mixed
  assertion/test-error kills, eight test-error-only kills and nine survivors.
  Adjusted assertion score 95.9427207637%, conventional
  97.8520286396%, unchanged threshold95%. Initial/restored baselines pass,
  kill-evidence completeness is true, and source/test/support hashes match this
  candidate. Report: /tmp/connectanum-flatbuffers-binding-full-ci-repair/mutation-report.json.
- Independent Linux emulated AMD64 ffi-test suite passes all 235 cases; focused
  native reset/lifetime and retained-client HTTP/3 regressions pass on macOS
  and Linux. These remain local evidence; confirm the repaired pushed head in
  hosted CI before resuming feature implementation.

This candidate is ready for commit/push. No milestone issue is closed, no full
FlatBuffers performance/support claim is added, and no release/version change is
authorized. The next mandatory step is exact-head hosted CI confirmation; keep
factory/WebSocket/mixed-owner composition work behind that CI-first checkpoint.

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
reflects that reviewed scope. Commit ddc2e06b adds native frame
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
the producer capability. Full candidate bin/verify exits 0 (session 6724).

A completed narrowed Qwen review claims unguarded map mutation. Installed
DashMap source contradicts it: RefMut contains RwLockWriteGuard, and get_mut
acquires the write shard. Reserved entries cannot be publicly removed, and the
RAII reservation returns count/entry on failure. No concurrency redesign is
justified by this finding. The earlier output-limited review is incomplete.

Combined real producer lending through delayed/native network writes and fan-out
is covered by the network checkpoint below. Full codecs, negotiation/routing/PPT/E2EE,
hardening, benchmark parity and release evidence remain in the goal. All ten
issues stay open; no milestone completion is claimed.

Full completion-candidate bin/verify exits 0 in session 6724,
/tmp/connectanum-write-completion-verify.log.


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

## Native producer network integration

The independent native producer lends one 8 MiB valid WAMP payload to a fast
peer, a peer with a 4 KiB receive buffer, and an exported view. RawSocket and
WebSocket both run disconnect and runtime-shutdown scenarios. Pointer identity
is checked before sending, the fast peer parses framing independently and checks
the full payload, and the slow receipt remains pending. Dropping the view before
disconnect proves the stalled writer retains the original loan; retaining the
view across runtime shutdown proves shutdown does not invalidate SDK storage.
Only final release returns the quota and calls cleanup on the producer thread.
WebSocket masking is checked against the untouched producer allocation.

All 219 FFI tests pass in /tmp/connectanum-external-network-all-ffi.log.
Fresh full bin/verify exits 0 in /tmp/connectanum-external-network-verify.log
(12506), including Chrome/WASM. The initial broad Qwen review times out. A completed
narrow review claims outcome polling needs an extra socket synchronization step;
the actual helper already waits up to five seconds with a 1 ms poll interval,
and the independent fast reader is joined before runtime or producer cleanup.
Those claims do not justify changing the tested ownership contract.

## Dart validation preparation (#98 / #102)

An isolated scratch validator accepts all 42 pinned compiler fixtures and passes
53 VM tests, including input subranges, malformed roots/vtables/fields/vectors,
required fields, unknown enums, UTF-8, uint64 limits and 2,272 deterministic
truncation/mutation cases. Opaque byte vectors are bounded without scanning their
contents. Table types may share an address, and signed negative vtable offsets
are legal when a reused vtable follows its table. Both are covered explicitly.
This is structural checking, not metadata/argument semantics or a working codec.

Focused Qwen test planning/review completes. Claimed unsafe signed-vtable reads
and scalar-alignment bypasses are refuted by checked u16/scalar reads and explicit
regressions. Browser scratch runs cannot load /tmp tests through the package's
HTTP server; rerun from the package after integrating the validator. No browser
pass is claimed yet. Keep the running network verification snapshot stable
before integrating these new production files.

Network and completion commits are pushed through ff5cc4c7 in draft PR #105.
The structural validator is now integrated with reproducibly generated field
descriptors. All 53 focused tests pass on VM, JavaScript and WASM from the
package root. Analysis is clean, all nine generator tests pass, and exact
regeneration verifies 50 artifacts without changing existing schema/bindings or
fixtures. The scratch browser-loader failures are resolved by that invocation.
No working message codec or metadata/argument semantic validation is claimed.
The first full validator-candidate bin/verify (71236) exits 1 at five complete
serializer-inventory assertions in /tmp/connectanum-flatbuffers-validator-verify.log.
The new test was absent from four support-file inventories and the shared suite.
Those entries are restored without weakening checks or adding exclusions. All
79 tooling tests and all 53 validator cases through the shared wrapper pass.
Qwen debug identifies the same missing-inventory cause, verified against source.
Fresh full verification restarts in
/tmp/connectanum-flatbuffers-validator-verify-retry.log. The validator candidate
was checked by session 67905, which exits 1 at the existing TLS-ticket harness.
The candidate
is uncommitted. Hosted ff5cc4c7 package dry-runs pass (37139143935);
CI 37139143966 remains queued, without a hosted all-green claim.

## Primitive writer and isolated verification

The retry fails after native/client tests at the TLS harness's global runtime
file lock. lsof identifies live PID 85257 in the separate configurable-rights
checkout, listening on localhost:65092. Its library/runtime is unrelated to this
candidate. A task-specific TMPDIR preserves lock coordination within this run;
the entire TLS-ticket case then passes in
/tmp/connectanum-flatbuffers-isolated-tls-probe.log. No other process is stopped
and no production lock semantics, timeouts or gates are changed.

The new pinned-schema writer builds each of the 42 fixture field trees directly
into a supplied fb.Builder. It preserves same-builder byte vectors by end-relative
offset, including growth, and rejects cross-builder references. References are
trusted generated offsets valid only within one build, before reset. It does not
adopt external pointers. All 46 writer tests pass on VM/JS/WASM, focused analysis
is clean and all 79 complete-inventory tooling checks pass. The JS oversized-ID
test uses 2^53+2, because 2^53+1 cannot be represented as a JS source literal;
the structural verifier separately tests its exact wire bits. Qwen's broad
writer review times out without evidence; a completed narrowed reference review
finds no concrete bug, and the pointer-offset tests cover its remaining concerns.

Public message-model projection/decoding, metadata semantics, lazy encoded
payload integration, serializer selection and native network codecs remain
required. This kernel is an intermediate implementation, not a substitute for
the entire ten-issue goal. Full verification of the combined uncommitted
validation/writer candidate is next, with isolated temporary storage.
The combined bin/verify exits 0 in session 46508 in
/tmp/connectanum-flatbuffers-encoding-verify.log, with TMPDIR=/tmp/connectanum-flatbuffers-verify.jr3fJ8.
The completed source snapshot includes both the validator and primitive writer,
all complete-inventory checks and Chrome/WASM suites. Full model projection and
encoding are the next implementation stage; the public serializer stays disabled.

## Direct message-model writer (#98)

Validation and primitive writing are committed/pushed as 390529e7 after the
combined bin/verify passes. The new uncommitted candidate projects all 25
supported public message models directly into pinned table fields. It does not
encode and decode a complete CBOR/JSON message to get an envelope. Dynamic
args/kwargs and the complete dictionary are independently CBOR-encoded.
Routing IDs and URIs remain distinct from dictionary fields. Unsupported ERROR
request types are rejected, custom authentication names use the negotiated
placeholder fields, and values exceeding upstream scalar width remain in
metadata without truncation. General Details fields and empty authmethods survive
even without typed roles. Incoming dictionary presence and unknown role features
still require a model/codec retention solution before #98/#100 can complete.

The model writer accepts the same guarded native-backed builder and prebuilt
byte-vector references. Retained CBOR args and transparent/packed payloads avoid
calling application decoders. Ordinary values still incur CBOR construction and
vector-write copies. Metadata construction is capped at 1 MiB, container depth
64 and one million input items, with cycle rejection before recursive encoding.
Dynamic construction has a 64 MiB per-value limit; complete frame-size and
encoded-input semantic checks remain work for the actual public codec.

Gemma summarizes the selected dictionary helpers; its claim that dictionary-only
output is inherently lossy is inapplicable to this purpose. Qwen test planning
times out without a complete answer. A completed narrowed scalar/vector
projection review has no concrete findings; unspecified enum names are retained
in metadata intentionally. The code/tests cover remaining nested handling.
The candidate remains an internal encoding stage: public serializer/factories,
strict bounded incoming metadata, agreement and capability negotiation, native
Rust codec, routing, PPT/E2EE and performance gates are still required.

The candidate passes 40 VM/JS/WASM model-writer cases. The CBOR package exposes
the same 2^53 integer as BigInt on VM/WASM and int on JS; the test accepts either
integer type while checking its exact numeric value. The native-backed model
test independently checks the prebuilt vector's physical end-relative offset,
zero growth and exactly the initial vector plus metadata input-copy count. A
derived reader remains valid after disposing the builder. Focused core/client
analysis and all 79 complete-inventory tooling checks pass. Broader Qwen writer
review reaches its token limit without a completed report; no full review claim.
Hosted 390529e7 package dry-runs pass (37142543729), with CI 37142543742 queued.
Fresh full model-writer bin/verify exits 0 in session 5697 at
/tmp/connectanum-flatbuffers-model-writer-verify.log, with
TMPDIR=/tmp/connectanum-flatbuffers-verify.jr3fJ8. The next code stage is bounded
CBOR metadata decoding, wire/metadata agreement, public message reconstruction
and lossless dictionary retention before enabling factory/network selection.

## Bounded frame decoding (#98)

The new CBOR scanner bounds bytes, nesting and item count before materialization,
rejecting truncation, invalid UTF-8, malformed indefinite chunks, duplicate or
non-string metadata keys and trailing values. A schema-driven wire reader keeps
byte vectors as original input spans. Frame checks enforce projected metadata
agreement, reserved zero sessions outside WELCOME, ERROR kinds, CHALLENGE method
consistency, HEARTBEAT presence and disjoint ordinary/transparent payloads.
It validates one complete array/map for ordinary args/kwargs without decoding
their application values. Public models/selection/capability handling remain open.

Two fail-first regressions expose dictionary overwriting independent HELLO realm
and AUTHENTICATE signature and omitted CHALLENGE extra projection. They are fixed;
challenge_scram_ack and welcome_metadata_ack derived fixtures are corrected to
match the existing agreement rules. No original upstream fixture/schema changed.
CBOR DateTime compatibility is retained in metadata and application vectors.
All 133 focused tests pass on VM/JS/WASM, analysis has no issues, nine generator
tests pass and independent upstream/extended Python with Dart/Rust checks pass.
The binding document records reserved-session and extra-map projection policies
and primary WAMP/RFC 8949 sources. The previous full verification predates this
stage; a fresh full run is required before committing it.

A valid 256-alias fixture reproduces repeated string allocation in the reader;
cache decoded strings by their validated wire target. This is allocation
avoidance within the existing limit, not an unbounded-input fix: the validator
already charges repeated string references. The initial full frame-stage run
in /tmp/connectanum-flatbuffers-frame-verify.log is deliberately interrupted for
this follow-up and must not be counted as passing. Fresh full bin/verify
exits 0 in session 70693 at
/tmp/connectanum-flatbuffers-frame-cached-strings-verify.log, with the same isolated
TMPDIR. The expanded 134-test suite passes on VM, JS and WASM; analysis is clean.
Qwen's CBOR-scanner review times out at 90 seconds without a completed report.

The next model-reconstruction/retention candidate is prepared outside the worktree
while preserving this verification snapshot. Its 31 VM checks pass, including
all 25 models, lazy original payload spans, binary/date values, absent/empty
containers and retention of unknown role features and null dictionary values.
Two fail-first cases prove why raw dictionaries need retention. The draft merge
supports explicitly supplied changed paths, but automatic default-value setter
tracking and replaced-object handling are not integrated. No production codec
or lossless mutable-model completion is claimed from that draft.

The full cached-string frame-stage verification completes successfully, including
native, VM, Chrome/WASM, router and consumer checks. The verified internal writer
and frame reader can now be committed/pushed. All ten issue acceptance audits
remain open; the temporary reconstruction/retention files are not part of this
verified candidate.

The writer/frame stage is committed and pushed as 71e57a46 in draft PR #105.
Hosted package dry-run 37146562164 succeeds at that exact commit; CI 37146562161
is queued in the latest snapshot. The PR description is updated around the
verified stage, with public codecs and every whole-issue acceptance still open.

Before the public decoder is enabled, enforce string/unique keys at the kwargs
root while preserving other supported map types in application values. Complete
the ordinary outgoing TransferableTypedData normalization as well. Metadata
already applies string/unique keys to its entire dictionary tree. These are
remaining codec acceptance checks, not advertised public support in this stage.


## Public Dart codec and mutable dictionary retention (#98)

Integrated direct model reconstruction and owner-retaining lazy CBOR vectors.
Guarded setters observe 47 feature booleans and Yield progress only after the
received baseline is captured. A fail-first explicit-false regression reproduced
the previous retained-null loss; all per-feature cases now pass. Tests also cover
replaced features/options, unknown siblings, in-place binary edits, cycles,
aliased TransferableTypedData, unchanged-container identity and root kwargs keys.
Metadata input normalization bounds recursion before snapshots and avoids cloning
unchanged containers. Root kwargs require unique string keys; nested application
maps retain supported non-string keys. Typed model failures become payload-free
FormatExceptions before the decoded model is returned.

Added the public stateless Serializer and core/client/facade exports, including
portable/native-builder construction helpers. Typed FlatBuffers PPT dispatch
passes through one application Uint8List and explicitly rejects dynamic values
and CBOR argument fragments; the application owns schema validation. No new
cryptographic profile is implied. Native/browser transport factories, strict
capability/session negotiation and native Rust codec remain pending.

All 228 focused VM tests and core/client/facade analysis pass. The complete
serializer mutation wrapper and all four inventories include the new test.
All 89 mutation-tooling tests pass, with one existing skip. The earlier fast run
94627 exits 0, but later stages overlapped these edits; it is not an untouched
baseline proof. Exact pre-change verification remains 70693 at commit 71e57a46.
Fresh browser/canonical candidate verification is required before commit/push.

Local Qwen retention review reaches its output limit and is incomplete. A narrowed
GLM review completes, but its suggestions contradict the explicit replacement
policy, scalar setter source and normalization guard. The replacement/47-setter
regressions confirm those boundaries. Expando state cannot vanish while the
message strongly retains the observed objects. No suggested change is applied
without a reproducer. A separate codec/normalization GLM review reaches its output limit without a
completed report; no full companion review of this candidate is claimed.
Source inspection and executable regressions remain the evidence. The focused
227-case suites pass on both Chrome JS and WASM (the transferred-data case is
VM-only). An independent transparent-payload probe confirms original-storage
aliasing, direct PPT view identity and byte-preserving re-encoding. Automatic
transparent-payload delivery through session PPT APIs remains #101.
All ten whole-issue acceptance audits remain open.


Fresh public-codec candidate bin/verify exits 0 in session 62824 at
/tmp/connectanum-flatbuffers-public-codec-verify.log, using the same isolated
TMPDIR. This includes native core/FFI, VM, Chrome/WASM, router, benchmark-path
regressions and external consumer checks. Source remained unchanged throughout
this run; only progress documentation was updated afterward. All 228 focused VM
and 227 JS/WASM cases pass; the earlier narrow tooling command's import-path
failure is repaired with unittest discovery and all 89 tests pass (one skip).
The current candidate can now be committed/pushed without claiming completion
of #98 or any other whole milestone issue.

## Native Rust codec (#99 / #102)

The public Dart stage is committed/pushed as 652ab865. The previous continuation
audited the existing issue set without changing implementation. Resume the
existing native candidate rather than restarting it. Its fast-check handle 94766
and focused parser handle 49729 are confirmed terminal with exit 0; later edits
overlapped the fast run, so it is not an untouched baseline claim.

The RawSocket ID-5/parser mismatch has a real failing reproduction. Add shared
generated field descriptors, a checked wire reader, bounded CBOR scanning before
metadata allocation, direct reconstruction of 25 native messages, and transparent
payload storage distinct from CBOR args/kwargs. Byte vectors retain Bytes slices
from the input allocation. Segmented input coalesces once and retains that owner.
Do not advertise new transport capability until native FFI/session paths work.

A second fail-first regression proves contradictory typed timeout/metadata was
accepted. Metadata projection/agreement now rejects it and validates pinned
known fields/defaults. The direct encoder constructs schema tables/vectors with
the pinned runtime and moves its finished allocation into Bytes without a final
copy. Embedded byte vectors are copied during construction; no end-to-end
zero-copy claim is made for this contiguous encoder. Unsupported ABORT/GOODBYE
payload fields return an error instead of being silently discarded.

All 17 focused tests pass, covering all 25 models, nullable HEARTBEAT masks,
opaque payloads, metadata/CBOR corruption, portable integer boundaries, payload
allocation identity after owner release, every segmentation split, and truncation/
byte mutations of all 42 pinned fixtures without a panic. Independent Python
readers verify generated output; actual Rust -> public Dart -> Rust checks pass
for all 25 messages with custom metadata and CBOR argument spans. The existing
mandatory interop CI command now includes those public-codec checks. Ten generator
tests and exact regeneration of 51 artifacts pass. Logs:
/tmp/connectanum-flatbuffers-native-codec-focused.log,
/tmp/connectanum-flatbuffers-native-codec-interop.log,
/tmp/connectanum-flatbuffers-native-generator-test.log and
/tmp/connectanum-flatbuffers-native-generator-check.log.

Local test planning completes. The broad Qwen review reaches its 120-second
deadline without a completed report; the independent GLM reader review also
stops responding at its 90-second deadline. Neither completes, and no full
companion review is claimed. Initial bin/verify 90258 finds a test that assumes FlatBuffers is
unsupported. Retain its malformed-input coverage and assert Deserialize for
FlatBuffers while keeping UBJSON's UnsupportedSerializer assertion. Fresh
bin/verify is running in session 3387 at
/tmp/connectanum-flatbuffers-native-codec-verify-final.log with its own TMPDIR.
Hosted 652ab865 CI 37149216957 remains in progress. All ten issues remain open.
Next: FFI metadata/payload support, RawSocket/WebSocket factories and explicit
metadata profile negotiation, followed by authenticated RPC/pub-sub and routing.

A third fail-first test proves UNREGISTERED metadata was lost when parsed native
models were re-encoded. Retain its dictionary in the native variant, preserve
optional dictionaries in JSON/MessagePack/CBOR, and keep nonempty metadata
available to existing FFI exports. The C ABI layout is unchanged. The all-25
interop corpus now includes revocation/custom UNREGISTERED details; native model
re-encoding and actual public-Dart/Rust interop pass. An ordinary/segmented codec
regression checks every split and malformed optional dictionaries. Logs:
/tmp/connectanum-flatbuffers-unregistered-fail-first.log and
/tmp/connectanum-unregistered-codecs.log. Verification 3387 overlaps this later
fix and cannot establish complete current-candidate verification; a fresh final
run is required after it finishes. The focused current FFI regression run 52037
exits 0, with 229 passing tests at
/tmp/connectanum-flatbuffers-native-ffi-regression.log. The overlapped full run
3387 exits 0. A fresh final bin/verify is now active in session 92983 at
/tmp/connectanum-flatbuffers-native-codec-verified.log. No source changes follow
its launch; only progress documents are updated. Commit/push and draft PR body
publication remain pending this final run. Prepared PR body:
/tmp/connectanum-flatbuffers-pr-native-codec-body.md.

Final native codec verification 92983 exits 0 at
/tmp/connectanum-flatbuffers-native-codec-verified.log; source stayed frozen
during the run. Commit/push of this verified stage is now ready. Hosted base
652ab865 has confirmed Core Browser Coverage and Full Verify failures in run
37149216957. Inspect those logs before continuing FFI feature work. The milestone
and all ten issues remain open.

Verified native codec stage is committed/pushed as 07a81127; draft PR #105
now describes both public codecs and their remaining integration boundaries.
Hosted base CI failures are browser coverage (94.627% versus 96%) and the
external-buffer fan-out terminal wait. Add 24 independent JSON-reference metadata
round trips, including boolean values, principal lists and empty role capabilities.
VM, Chrome JS and WASM pass. Merge actual new Chrome coverage with the unchanged
hosted report: 96.096% (8960/9324); this is not a new complete hosted run. Include
the tests in all four serializer mutation inventories. Retain the fast peer
until its local write receipt and name every terminal wait; do not relax assertions
or timeouts. Original fixture passes 30 local Linux repetitions, so exact hosted
failure remains unconfirmed. Candidate macOS fixture passes; Linux follow-up and
fresh complete verification are pending. Qwen narrow test review hits its token
limit and provides no complete report. FFI metadata tests are prepared separately
at /tmp/connectanum-flatbuffers-ffi-metadata-tests.rs, not yet applied.

Fresh CI-repair bin/verify is active in session 71043 at
/tmp/connectanum-flatbuffers-ci-verify.log, with source frozen after launch.
The bin/test-fast run 70684 remains active; four mutation-tool regressions pass.
Candidate changes remain uncommitted pending final verification. Linux candidate
run 60251 is compiling with persistent toolchain/cache at
/tmp/connectanum-flatbuffers-linux-peer-lifetime.log. Do not claim the hosted
timeout resolved until the named-boundary candidate has hosted evidence.

CI-repair verification 71043 exits 1: the new metadata test is missing from the
serializer mutation wrapper. Add its import/group and verify the inventory guard.
Supporting test-fast 70684 exits 0 but overlaps later native metadata edits.
The repaired fan-out fixture passes on macOS and Linux ARM64.

A real C-ABI probe reproduces FlatBuffers dictionary loss: CALL parses but
details_len is zero. Retain the validated CBOR metadata Bytes span in
ParsedMessage and prefer it during FFI storage; both enqueue APIs share the
storage helper. HEARTBEAT constructs its existing small metadata/control wrapper.
No C structure layout changes. The probe now exports metadata from inside the
frame allocation. Four tests cover owner retention after message drop, pointer
identity, absent dictionaries, narrow/wide APIs and all eight HEARTBEAT masks.
233 FFI tests and 17 native codec tests pass, as does the 24-case mutation wrapper.
Focused Qwen review of the metadata path completes with no findings.

Fresh combined bin/verify 37274 is active at
/tmp/connectanum-flatbuffers-delivery-verify.log. Complete browser coverage 42492
is active at /tmp/connectanum-flatbuffers-delivery-browser.log, and Linux ARM64
FFI verification 68102 at /tmp/connectanum-flatbuffers-linux-delivery.log. Source
is frozen after launch. Commit/push and PR body update wait for final checks.
Next implementation remains Dart native/router fragment binding, opaque payload
delivery, version/capability guards and authenticated FlatBuffers sessions.

Verification 37274 exits 101: parse_message is inherited from a feature-gated
FFI import, so the new test module does not compile without ffi-test. Import
ct_core::parse_message explicitly and run default-feature FFI tests before retry.
Linux ARM64 ffi-test verification 68102 exits 0 with 232 tests; the native test
import fix does not affect browser Dart sources. Complete browser coverage 42492
continues unchanged.

Default-feature FFI verification now passes 222 tests. Fresh final bin/verify
5336 is active at /tmp/connectanum-flatbuffers-delivery-final.log. Only progress
documents change after its launch. Capture actual C ABI message-info records
for all 25 native codec cases and execute both current Dart binders against the
public FlatBuffers codec reference: 42/50 paths fail. Probe artifacts remain in
/tmp/connectanum-flatbuffers-native-bindings-corpus/message_info.json,
/tmp/connectanum-flatbuffers-capture-message-info.py and
/tmp/connectanum-flatbuffers-native-binding-probe.dart; failure log is
/tmp/connectanum-flatbuffers-native-binding-fail-first.log. Convert this corpus
into reproducible binding coverage during the next integration stage.

Complete browser coverage 42492 exits 0: core 96.096% (8960/9324), client
97.132% (2777/2859). Existing gates are unchanged. The fresh final verification
5336 has passed both default (222 tests) and ffi-test (233 tests) native FFI
checks and continues. Candidate commit/push remains pending its terminal result.

Strengthen the temporary native-binding oracle with re-encoded FlatBuffers
dictionary equality as well as JSON-model equality. It exposes GOODBYE dictionary
loss on both binders and UNREGISTERED dictionary loss on the client, bringing
the existing failures to 45/50. Preserve unknown metadata during the upcoming
binding implementation; JSON-only comparison cannot prove that requirement.

Fresh delivery verification 5336 exits 0 at
/tmp/connectanum-flatbuffers-delivery-final.log, with product source unchanged
throughout. The verified native metadata/CI stage is ready for commit/push.
A temporary three-package overlay passes all 50 actual native-info binding paths
after using bounded metadata decoding to preserve the portable 2^53 principal ID.
The overlay is preparatory evidence only; persistent integration tests and the
actual worktree change remain next. All ten issues remain open.

## Dart native binding stage

Delivery/CI repair is committed/pushed as dff1fba0 and draft PR #105 updated.
Apply core bounded metadata/application helpers and reuse them in both native
binders. Full-frame fallback uses the public codec. Metadata-only paths retain
unknown dictionaries on the final materialized model and keep encoded payload
spans unchanged. Preserve HEARTBEAT's existing control wrapper.

The real C ABI corpus covers 25 kinds through both consumers, metadata-only
binding, repeated retention and later model edits. The additional 2^53/nested/
binary application case first fails all three paths with incompatible BigInt
values; sharing the core application decoder repairs it. All 84 corpus cases
and all 3,810 focused tests pass. The 28 public metadata/application checks pass
on VM, Chrome JS and WASM. Analysis and diff checks pass.

Qwen's bounded review completes, but both findings are contradicted by inspected
source: deserialize returns null only for null input, and both binders retain
metadata. Intentional bounded ownership is not established as a leak. GLM's
prior preparatory identity/double-retention suggestions are covered by real
materialization, repeat-retention and mutation tests; a referenced message cannot
be collected. No unsupported claim is accepted from either advisory.

Fresh full verification 52267 is active at
/tmp/connectanum-flatbuffers-binding-verify.log. Product source stays frozen;
only progress documentation changes afterward. Supporting fast37810 overlaps
binding edits and remains supporting evidence. Opaque delivery, profile/version
guards, factories, live flows, performance and release/consumer work remain.

Supporting fast37810 exits 0 but overlaps the binding stage; final proof remains
verification52267. The pinned typed CALL fixture has a 136-byte reference opaque
vector. The current C
ABI exports neither encoded args nor binary info for it and rejects the proposed
opaque selector 5 with -4. Probe logs: /tmp/connectanum-flatbuffers-opaque-fail-first.log
and /tmp/connectanum-flatbuffers-opaque-reference.txt. No product source changes
follow the binding verification launch. Add explicit opaque presence/span ownership
next; an opaque application buffer cannot be treated as CBOR arguments.

An independent real C-ABI-info -> current router binder probe confirms the
functional opaque loss: expected transparent vector length 136, actual null.
Log: /tmp/connectanum-flatbuffers-opaque-binding-fail-first.log.
Prepared next-stage Rust source and focused ownership tests remain outside the
worktree in /tmp/connectanum-flatbuffers-opaque-stage (not applied or compiled).
They add an explicit presence flag, byte selector 5 and an additive native binding
version, retaining the original allocation through exported-view owners. Wire
negotiation remains independently required. Apply only after the frozen binding
verification has a terminal result; then extend both Dart runtime/binding paths,
older-library guards and real opaque delivery/lifetime coverage.

2026-10-04: Fresh binding verification52267 exits 0, with product source
unchanged throughout the run. The binding stage is ready for commit/push.
The independent opaque Rust overlay compiles and passes two focused tests:
all seven payload-bearing kinds preserve empty/nonempty presence and the
original allocation; narrow/wide exported owners survive message-handle release.
The first overlay build lacks public benchmark TLS fixtures; copying those
fixtures into the correctly laid-out temporary overlay repairs its build without
changing the worktree. Prototype log: /tmp/connectanum-flatbuffers-opaque-native-overlay.log.
Its library build is active in session64702 at
/tmp/connectanum-flatbuffers-opaque-overlay-library.log. Actual opaque source,
Dart runtime integration and full verification remain next. All ten issues stay open.

The verified binding stage is committed/pushed as ce6f55ec; draft PR #105 now
reports its final validation and remaining scope. Native opaque overlay library
build64702 exits 0; its real C-ABI probe exports all 136 bytes under selector5,
matching message info and the public codec reference. Apply the tested native
opaque candidate and two tests to the worktree after starting fast25100.
Focused native run66535 is at /tmp/connectanum-flatbuffers-opaque-native-focused.log.
The candidate remains uncommitted. Next: NativeMessageBytePart selector, explicit
presence delivery, safe exported payload views in both materializers, final-model
retention, older-library/version guards, empty-vector/absence and lifetime tests.
Do not call selector4 for an opaque vector or advertise factories before profile
negotiation is complete. No complete verification of this new candidate is claimed.

## Opaque native/Dart receive integration

Both runtimes now export selector5 under presence bit8, retain the vector on the
final payload model and skip selector4 for opaque INVOCATION data. The payload-only
CALL reader also owns its opaque vector. No app schema registry or ObjectBox
runtime dependency is introduced. Missing/unknown binding versions and version1
without native byte ownership reject before reading even an empty vector.

The payload-only regression first fails on the absent API, then passes for
absent/empty/nonempty vectors. A separate fail-first C fixture demonstrates that
version1 without byte ownership was incorrectly accepted; the complete guard
repairs it. Another fail-first test writes through an exposed native view;
read-only views now block writes through list, ByteBuffer and subview aliases.
All 61 lifecycle tests pass after that change. Two Rust tests cover all seven
payload-bearing kinds and narrow/wide exports, including the existing no-owner
empty-span ABI. Earlier 3,848 binding regressions pass before final immutability.
Logs: opaque-call-reader-fail-first, opaque-version-fail-first,
opaque-mutable-view-fail-first, opaque-bindings-regression,
opaque-immutable-lifetime and opaque-native-final under /tmp/connectanum-flatbuffers-.

Supporting fast25100 is terminal1, with worker stdout EOF before READY (not an
observed cancel failure); source overlapped edits. Its cause remains unproven.
The isolated worker case and all 56 full transport integration tests pass in new
processes. Do not replace this with a clean-fast claim or alter deadlines. Fresh
bin/verify must run with source frozen and a unique temporary directory.

GLM's ownership audit completes: original Arc ownership and empty exports are
sound. Document selector4 versus flagged selector5 explicitly; default flags and
existing flag preservation are confirmed. Qwen's final bounded review completes
but its proposed bit8 check in the library capability probe is rejected: presence
belongs to the per-message metadata checks, while ownership is validated by the
exported owner. Its broad earlier review times out without a completed report.
The test advisory's proposal to read after freeing a view owner is rejected;
weak witnesses check lifetime before any escaped byte is dereferenced instead.
All ten issues remain open. Session negotiation/factories, routing, live flows,
PPT/E2EE, full CI/memory/performance gates and release consumers remain required.

Fresh verification2971 is live at /tmp/connectanum-flatbuffers-opaque-verify.log,
with a unique TMPDIR and product source frozen. Its Rust HTTP CLI startup test
misses the 2-second READY deadline on attempt1 and passes the unchanged built-in
retry. Preserve the attempt and do not invent a clean-first-attempt result.
A preparatory client-profile state machine and rejection checks pass outside the
worktree in /tmp/connectanum-flatbuffers-profile-stage. It is not shipped/session
proof. Integration points are native transport receive before controller delivery,
outgoing validation with state committed only after queue acceptance, and router
HELLO/CHALLENGE/WELCOME in router_worker_handshake.dart. Core retained-dictionary
projection is needed to inspect and decorate unknown role feature keys without
losing metadata or reading app payloads. Implement and test the actual paths only
after verification2971 becomes terminal and the opaque stage is committed.

Verification2971 exits 0 with product source unchanged throughout. Native Rust
(default and ffi-test), VM, external package consumers, router/native forwarding
and Chrome/WASM suites pass, including all 4,460 core and 2,673 client browser
checks. Retain the HTTP CLI first-attempt startup failure and canonical retry.
The opaque stage is ready for commit/push. Factories and profile guards remain
next; the independent prototype is preparatory only and all ten issues stay open.

Opaque receive integration is committed/pushed as 896fd29a; draft PR105 has its
final scope and evidence. Native default/ffi-test totals are 223/235. Exact-head
CI runs37159768909 and37159768913 are queued; no new hosted pass is claimed.
Product source and the recorded verification agree. Leave this bookkeeping
uncommitted until the next implementation stage. Next: fresh test-fast, shared
metadata projection/profile gates, native version checks before connect, and
normal RawSocket/WebSocket factory selection with real authentication tests.

## Shared session profile and native client enforcement

2026-10-04: Prior turn verifies all ten issues and adds explicit WAMP custom-binding
and ObjectBox C/Dart clarifications to #95/#97; the full milestone remains active.
Test-fast32338 exits0 but overlaps subsequent source edits. The new bounded
metadata accessor preserves retained unknown role keys, detaches nested maps and
binary data, and does not access application vectors. Its absent API fails first;
all three new metadata tests pass after implementation.

Add a shared immutable client/router profile with explicit HELLO advertisement,
CHALLENGE acknowledgement before credentials, fresh WELCOME acknowledgement,
repeated acknowledged authentication rounds, bootstrap ABORT and terminal
GOODBYE handling. Integrate native client ingress before controller delivery and
both ordinary and pre-encoded owned/leased send paths. Commit outgoing state only
after enqueue acceptance. Require the complete native binding capability before
both RawSocket/WebSocket native connect calls. A version0 local artifact fails
before connecting; rebuilding current source with ffi-test passes.

With the rebuilt library and the previous transport source, a real RawSocket
peer reproduces unacknowledged CHALLENGE delivery and a resulting WELCOME. Restore
the candidate source after that baseline probe; five live cases then pass,
including ordinary anonymous RPC and tracked/untracked native-owned transfers.
Rejection leaves pre-encoded buffers unconsumed. Both current and buffered receive
batches have explicit handle cleanup. All 74 existing native transport/owned-buffer
regressions and 3,240 serializer-wrapper cases pass before final constructor
consistency coverage. Register the new tests in canonical native scripts and the
serializer wrapper. Expanded profile tests pass; final six-case native run,
browser coverage and unchanged-source bin/verify remain required.

Qwen/GLM reviews complete. Reject their proposed removal of anonymous WELCOME and
repeated challenge rounds: these are intentional and tested. Profile immutability
does not forbid decorating bootstrap models. Non-null codec input cannot return
null; decoded retained feature dictionaries are lossless and explicitly tested.
A rejected receive frame closes the connection and drains its handles, so there
is no subsequent ABORT transition to grant on that connection. No valid new
finding is established by those advisories. Keep all ten issues open; next work
is router handshake enforcement and normal factories, then live routing/PPT,
memory/conformance/CI and performance/release gates.

The final six native cases and focused analysis pass. First full verify32863
exits1 with product source unchanged; native/default/ffi-test and benchmark Rust
suites pass, then the complete serializer mutation inventory guard reports the
two new files absent from all four VM/web CBOR/MessagePack support lists. Add the
files to those manifests without changing the guard; the isolated inventory
regression passes. Preserve /tmp/connectanum-flatbuffers-profile-verify.log.
Browser coverage78292 remains live, with Dart product libraries/tests unchanged.
Freeze the corrected complete source for fresh canonical verification.

Browser coverage78292 exits0: core96.085% (9032/9400), client96.877%
(2792/2882), with unchanged gates and 2,673 client browser cases. The Dart
libraries/tests remain unchanged throughout that run; only the mutation support
manifest is repaired after first verification fails. Fresh verify44100 is live
at /tmp/connectanum-flatbuffers-profile-verify-final.log with product source
frozen and verified unchanged against
/tmp/connectanum-flatbuffers-profile-frozen-source-final.json. Do not edit
product source, commit or claim its full verification until that handle reaches
a terminal result. All ten issues and the full milestone remain open.


2026-10-04: Final profile verification44100 exits0. Its complete product source
matches all 1,415 frozen-file hashes at completion; no source edits occurred
throughout verification. Canonical native/default/ffi-test, VM, router/consumer
and Chrome JS/WASM checks pass, ending with 2,673 client WASM cases. Browser
coverage remains core96.085% and client96.877% with the existing gates. The prior
mutation-inventory failure remains recorded; its support-manifest correction is
included in the final verified candidate. Commit/push the profile stage next.

While source was frozen, prepare router profile enforcement in the temporary
package overlay recorded at /tmp/connectanum-flatbuffers-router-profile-stage-path.txt.
Six initial handshake/queue-acceptance scenarios pass, including delayed WELCOME
acceptance for anonymous and authenticated sessions. Extend all ten ordinary
session send call sites with connection context and test failed CHALLENGE/WELCOME
cleanup. This is preparatory overlay evidence, not shipped/live-router proof.
No ordinary factory, routing, PPT/E2EE, performance or release completion is claimed.
All ten issues and the full milestone remain open.


## Router enforcement and segmented native forwarding

2026-10-04: Commit/push the verified client profile stage as 6727a18c. The
subsequent planning turn verifies the existing milestone but makes no
implementation progress; resume against the actual dirty worktree. Integrate the
profile into all actual router handshake and session paths. Native enqueue ACKs
are produced by the real boss on success and both supported rejection classes.
Three real-boss receipt tests pass. A disconnect while WELCOME is queued initially
reopens a ghost session; compare the original profile and phase before committing
the transition. A rejected GOODBYE initially leaves an open session; close it in
finally and make draining continue cleanup after an enqueue error. All 142 router
profile/auth/session tests pass; pending-auth onAbort is exactly once.

The real RawSocket router test reaches registration, then reproduces unsupported
FlatBuffers CALL-to-INVOCATION forwarding. Add a schema-compatible segmented core
writer plus native EVENT, INVOCATION, YIELD-derived RESULT, CALL-derived RESULT and
ERROR paths. A contiguous implementation fails three allocation-identity oracles;
record /tmp/connectanum-flatbuffers-native-segments-fail-first-final.log. The
forwarding matrix fails five FlatBuffers cases before implementation; record
/tmp/connectanum-flatbuffers-forwarding-fail-first-final.log. The segmented writer
retains original Bytes vectors and patches only owned envelope offsets, with
bounded append headers/padding and presence-preserving empty vectors. All 21
focused core tests pass, including every public model under the generated verifier
and segmented splits. All nine ffi-test forwarding tests pass, including invalid
PPT metadata, progress/disclosure combinations, opaque allocation identity and
exactly-once producer release. The first opaque producer test incorrectly mixes
ordinary/opaque vectors; its final version proves rejection cleanup for mixed
frames and delayed release for valid opaque frames.

The rebuilt ffi-test native artifact passes both anonymous and ticket router
sessions with 128 KiB ordinary and opaque RPC/pubsub, progressive results, callee
ERROR and GOODBYE. Run with CONNECTANUM_FORWARD_NATIVE_PUBLISH=1 to cover native
EVENT forwarding; include this explicitly in test-fast/test-all. Focused analysis
has only the existing runtime-test informational lint. Qwen review's metadata and
Vec-clone concerns are rejected against authorized inputs and the Bytes-only
payload type. The first GLM writer review times out; narrowed offset/vtable review
completes without a concrete defect. Independently verify its imprecise alignment
comment against modulo arithmetic and generated verifier tests. Supporting fast
64699 overlaps product changes. Do not commit/push or claim final candidate
verification until a fresh source-frozen bin/verify completes. All ten milestone
issues remain open; full factories/WebSocket/mixed routing/E2EE/performance/release
acceptance remains required.

Source-frozen router candidate: /tmp/connectanum-flatbuffers-router-forward-frozen-source.json
contains 1,419 product-file hashes. Supporting fast64699 exits0, but it overlaps
edits and cannot replace fresh verification. Canonical verify50035 is live at
/tmp/connectanum-flatbuffers-router-forward-verify.log. Do not change product
source until it is terminal. Tooling script checks separately pass all 79 cases.

While frozen, an external wire-peer test at
/tmp/connectanum-flatbuffers-websocket-probe/websocket_probe_test.dart passes both
anonymous/ticket scenarios over real WebSocket against the current router. It
covers the same ordinary/opaque/progressive/error/pubsub behavior. This is actual
current-router evidence, but the probe is outside canonical CI and must be added
with the next transport stage. The server already selects wamp.2.flatbuffers;
native client websocket_subprotocol() still rejects that serializer. The native
Dart WebSocket helper omits FlatBuffers, all named factories omit it, ordinary
RawSocket/WebSocket constructors reject it, and browser/native stubs need the same
public API. Native RawSocket's generic serializer mapping already accepts ID5.

A scratch client package at the path recorded in
/tmp/connectanum-flatbuffers-factories-stage-path.txt demonstrates the missing
withFlatBuffersSerializer APIs, then passes construction for both native classes
using the current pinned core profile and explicit library. The initial package
runner fetched registry dependencies in that scratch directory, which lack this
codec; preserve that failure and use probe_package_config.json bound to the actual
worktree packages for the valid fail-first/pass. These factories remain outside
product source and do not prove a native WebSocket connection. Apply/review only
after current verification finishes.

Next transport changes: add ordinary codec selection and native WebSocket mapping
plus a Rust subprotocol regression, preserving the existing codec capability gate.
Apply immutable client profile checks to pure RawSocket and VM/browser WebSocket
send/receive, reset on open, and commit outgoing state only after local acceptance.
For RawSocket pre-handshake buffering, local queue acceptance is the boundary;
FlatBuffers uses one complete frame. Check before authentication delivery and
close rejected ingress through existing error handling. Browser Blob conversion
must not let an old receive stream mutate a reopened connection's profile; capture
connection identity/generation around asynchronous decoding. Keep unsupported
native/browser stubs API-compatible. Native WebSocket file-segment serializer
mapping currently defaults unknown protocols to JSON; explicitly resolve FlatBuffers
and its supported/rejected file-segment behavior before advertising that feature.
These are next-step requirements, not completion evidence or waived milestone scope.

Adapter-readiness audit while source is frozen: NativeBufferTransport currently
submits one complete NativeOwnedBuffer frame. NativeTransportRuntime.trySendMessageSegments
still allocates/copies every Uint8List slice, and ct_send_message_segments_owned
adopts only registered Rust Vec allocations. The new core segmented encoder
retains borrowed application Bytes, but there is no corresponding public mixed
owned/leased segment assembly/submission contract for an external producer whose
buffer is only the application payload. A separately linked adapter cannot assume
its own ct_core runtime singleton is the ct_ffi runtime instance. Keep #96/#97/#100
open: add a generic native/FFI assembly and submission path that builds the selected
WAMP envelope around native-owned or externally leased application vectors,
retains all owners, preserves empty/presence and offset/alignment rules, and reports
queue acceptance versus write/release completion. Test identity, rejection,
fan-out and exactly-once owner-affine cleanup with a fake producer before claiming
connectanum_objectbox_adapter readiness. Do not transfer foreign pointers through
the Vec adoption API or treat the existing complete-frame lease tests as proof of
this missing composition boundary. Actual ObjectBox integration remains outside
core; the generic composition API is required by the original no-copy scope.


Canonical verify50035 exits0 at
/tmp/connectanum-flatbuffers-router-forward-verify.log. At completion all 1,419
product-file hashes and the complete file inventory match the frozen snapshot;
there were no product edits during verification. Native/default/ffi-test, tooling,
VM, router/consumer and Chrome JS/WASM pass, ending with 2,673 client WASM cases.
The router VM suite includes 4,805 cases plus separate remote-auth/native EVENT
runs. This router/profile/segmented forwarding stage is ready for commit/push.
Keep all ten issues open; carry the external WebSocket/factory probes and generic
mixed-owner composition gap into subsequent transport/ownership stages.
