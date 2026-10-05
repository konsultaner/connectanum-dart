# FlatBuffers and zero-copy native buffers

Status: active. Started: 2026-10-03.
Milestone: [GitHub milestone 1](https://github.com/konsultaner/connectanum-dart/milestone/1).
Branch: `codex/flatbuffers-zero-copy` in the managed FlatBuffers worktree.
Baseline: `54eafc5fb675886a04d390f069714c69de2aaac0`;
released master `3bac4cf5` is integrated. Preceding checkpoint: `e6fb28c8`.
Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

Latest accepted/pushed checkpoint: `0cf9e65e`. Its independent negotiated-profile
live peer and GuardMalloc jobs pass; five-platform artifact and package publish
dry-runs pass with publication skipped. All five bundles verify checksums,
manifests and source provenance; platform runtime execution is separate evidence.
The current uncommitted follow-up fixes profile/key-policy callback revalidation
after 72 fail-first assertion failures. Fresh canonical fast/full verification,
whole-package browser coverage and complete VM/Chrome mutation campaigns pass
on the matching 1,458-file candidate snapshot. Audits are recorded in project
state and [research](../research/2026-10-04-e2ee-key-policy-revalidation.md).
Exact-head hosted checks and issue #103's performance comparison remain open.

## Objective and scope

Complete all ten milestone issues. FlatBuffers is a regular serializer beside
JSON, MessagePack and CBOR, with interoperable Dart/Rust codecs, native-owned
construction, generic external-buffer leases, lazy routing, PPT/E2EE and measured
performance at least matching the better binary baseline on declared workloads.
ObjectBox integration itself belongs to a separate adapter package.

The primary checkout is independent and remains untouched. Feature commits,
pushes and draft PR updates are authorized. Release publication, version bumps
and a master merge are not authorized.

## Issue acceptance remains open

- [ ] [#95](https://github.com/konsultaner/connectanum-dart/issues/95): pinned binding, reproducible generation, metadata/schema compatibility.
- [ ] [#96](https://github.com/konsultaner/connectanum-dart/issues/96): native builders, freeze/retain/transfer, native inputs throughout submission.
- [ ] [#97](https://github.com/konsultaner/connectanum-dart/issues/97): generic external leases, producer-thread release, real send completion.
- [ ] [#98](https://github.com/konsultaner/connectanum-dart/issues/98): complete public Dart serializer, factories and verified lazy payload behavior.
- [ ] [#99](https://github.com/konsultaner/connectanum-dart/issues/99): native Rust codec, transport negotiation and supported profile guards.
- [ ] [#100](https://github.com/konsultaner/connectanum-dart/issues/100): homogeneous/mixed routing, delayed/progressive/error flows and lifetime preservation.
- [ ] [#101](https://github.com/konsultaner/connectanum-dart/issues/101): PPT and explicit typed E2EE profile; unchanged CBOR behavior and unsupported file handling.
- [ ] [#102](https://github.com/konsultaner/connectanum-dart/issues/102): external conformance, malformed-input/fuzz, memory/ownership CI.
- [ ] [#103](https://github.com/konsultaner/connectanum-dart/issues/103): representative throughput/latency/memory/copy gates and repeatable hosted evidence.
- [ ] [#104](https://github.com/konsultaner/connectanum-dart/issues/104): platform/consumer readiness and release/adapter documentation.

Implementation exists for many of these paths; unchecked items reflect remaining
acceptance and evidence, not a claim that every feature is unimplemented.

## Current candidate and evidence

The pushed b07d7b26 checkpoint includes explicit local typed E2EE providers, optional
whole-plaintext consuming ABI, retained read-only owners, opt-in deferred runtime
exports, ordinary benchmark factories and the internal RPC serializer-metadata
repair. Existing CBOR APIs/framing remain. Actual ObjectBox bindings stay outside
core. See [current state](../project_state.md) for exact contracts and proof paths.

The verified Session repair preserves negotiated runtime-payload capability
and moves typed key selection after existing preflight through an optional provider
contract. Explicit/policy/negotiated/default precedence, CBOR/custom behavior and
context-free directional defaults are covered by 42 key/capability cases. Focused
checks pass 268 VM client/native, 120 core and 66 JS/WASM cases each (20 native
browser skips per cohort). Initial canonical fast/verify passes and all 1,453
product/native/log/history hashes are audited at snapshot
`84a26cbab9aaa8c02b86ce39b61f57818df2af64c4e25fd7433e968a26ce717e`.
After the coverage repair, the registered Session fixture passes 56 VM cases and
complete client browser coverage passes 2,791 cases plus 20 native skips. Client
96.354% and core 96.160% pass unchanged floors; raw core source/test hashes are
verified before reuse. Final canonical verify passes on 1,453-file snapshot
`c415bf87cca057178fbd8e722182c83ef63200533b758f52d9e632ff2fd8ae36`.
All product/native/log/history hashes pass completed audit under
`session-coverage-repaired-canonical-completed-audit.json`. The registered fixture
passes 56 VM cases; the full client Chrome WASM cohort passes 2,800 cases with 20
native-only skips.
Independent VM/browser campaigns select all 305 mutations, including five new
ones, at unchanged gate/deadlines/equivalents. VM completes 236 kills, ten
survivors and 59 compile errors at 95.93496%, no timeouts; regeneration, all
classifications and input/native/log hashes are independently audited. Chrome JS
also completes all 305 with identical counts/score and no timeouts or new
equivalents; its independent completed audit verifies regeneration,
classifications and all frozen source/test/support/native/log hashes under
`session-preflight-core-e2ee-web-completed-audit.json`.

The preceding 1,450-file candidate passes canonical fast/verify with Chrome WASM
on macOS. Separate focused JS/WASM Session checks pass 44 cases each. Current
production ABI passes 116 VM cases; default feature-tree GuardMalloc passes 57
observed native tests, with five failure-control checks. Those are local evidence,
not hosted/all-platform/performance acceptance.

After the loop-oracle and memory CI additions, fresh canonical fast/verify passes on
1,452-file product snapshot
`edce848870ae28ab3aee2a7e30f144e9b230ab00112c7831085e560187cd40a0`.
Prefix: `/tmp/connectanum-flatbuffers-native-memory-loop-canonical-*`.
Both exit codes and all source/native/log hashes are independently audited.
Native ffi-test artifact9884a143 remains unchanged. The new macOS memory CI job retains reports and failure-control logs,
and Full Verify depends on it. Exact b07d7b26 hosted memory execution passes
57 cases and five failure controls; source, loader/count and log hashes are audited.

Complete VM mutations pass all 300 unchanged-source mutations at 95.9184%:
235 assertion-backed kills, ten survivors and 55 compile errors, no timeouts or
new equivalents. Inputs match the feature tree and are independently audited.
The matching complete Chrome JS campaign passes the same 300-mutation gate and
235/10/55 counts with no timeouts. Its mutation process exits 0 and restored
baseline passes. The outer wrapper exits 1 after an audit helper adds a Python
cache file; independent reconciliation verifies that exact sole added artifact,
all original bytes and all classifications against matching feature inputs.
The original wrapper failure remains preserved, not relabeled as a pass. Earlier
original/logical browser failures remain failed evidence.

## Immediate work

1. Complete fresh canonical fast/verify and the browser/binding mutation gates.
   Canonical snapshot `12c56f17` passes fast/full verification; all 1,454 product
   files and protected native/source/log hashes pass independent completed audit.
   Prefix: `session-deferred-tooling-repaired-canonical-*` under `/tmp`.
   After applying the new binding assertions and ordinary benchmark rows, fresh
   fast/full verification runs under `session-deferred-contracts-canonical-*`
   and full Chrome JS coverage under `session-deferred-browser-coverage-*`.
   The core VM gate
   passes all 356 mutations at 95.35714%: 267 assertion-backed kills, 21 survivors,
   68 compile errors, no timeouts or new exclusions. Regeneration, classifications,
   selected inputs/native/runner/configuration and 358 logs pass independent audit.
   Browser also passes all 356 mutations with the same counts/score; selected
   inputs and every regenerated mutation/classification pass independent audit.
   Binding completes all 603 but fails at 89.43089% assertion coverage: 440
   assertion-backed detections, 16 test-error-only detections, 36 survivors and
   111 compile errors. Preserve that independently audited failure. Isolated
   24-case contract additions pass a 1,880-case baseline/restored control and
   detect 20 of 35 observed survivors with assertions; one further detection is
   test-error-only and 14 survive. Positive metadata/construction assertions
   also have a passing corrected baseline. A fresh complete 603 campaign has completed
   under `/tmp/connectanum-flatbuffers-deferred-binding-contracts-*`; those test
   additions are now applied to the feature tree after the preceding canonical
   verification passed; the applied file matches the isolated campaign's frozen
   test hash. No new exclusions or widened deadlines are used. The sole Python
   expected-inventory test edit is explicitly recorded; preserve any whole-product
   wrapper rejection separately from the selected-input result. Initial fast
   analysis and stale-equivalence failures are
   preserved; repaired runs use the unchanged gates/deadlines and the same eight
   source-verified exclusions. Prefix: `session-deferred-loop-bound-*` under `/tmp`.
   Earlier core-lazy evidence predating this change cannot accept the candidate.
   Focused checks pass 2,227 current-library VM runtime/binding cases,
   371 older-ABI runtime cases, 115 core cases per VM/JS/WASM platform and 228
   production-library Session cases. The preceding repaired fast run fails the
   missing-part support-inventory control, now fixed in both native targets. Its
   lazy campaigns have three VM timeouts and were stopped as incomplete/failed.
   A subsequent exact expected-list assertion is also updated to include the new
   part; both scope controls pass. Six exact assertion-backed VM/JS mutant kills
   and four restored/baseline controls independently audit the bounded test-oracle repair. Production source
   and exclusions are unchanged by that repair. Check current browser coverage
   Fresh browser coverage passes all 4,595 core and 2,820 client cases plus 20
   native-only skips at unchanged floors. Independent audit verifies the frozen
   1,454 product bytes, native/log hashes and all 99 coverage artifacts, and
   regenerates the same summary. Prefix: `session-deferred-browser-coverage-*`.
   The complete binding campaign passes 603 mutations at 96.13821% assertion
   coverage: 477 detections (473 assertion-backed), 111 compile errors and 15
   survivors. Independent audit regenerates all candidates, verifies frozen
   staged inputs and matching selected feature inputs, hashes all 605 logs, and
   verifies both 1,880-case controls with no equivalents or changed deadlines.
   Prefix: `deferred-binding-contracts-client-message-binding-vm-*`.
   Canonical fast passes; full verify fails nine two-second benchmark worker
   readiness checks. The failed execution is independently audited and retained.
   All 36 focused lifecycle cases pass unchanged; exact-setting full benchmark
   reproduction passes all 1,366 cases. The original failure remains preserved
   and its cause is unestablished. No readiness budget or lifecycle implementation is
   changed, and full canonical acceptance remains open.
2. Finish exact e6fb hosted CI acceptance. Five new production bundles already
   pass checksum/manifest/source/workflow attestation checks; exact e6fb Apple
   Silicon sources execute 209 VM native/Session cases and the standalone
   construction consumer. The other four binaries are verified, not executed.
   Oracle absence has actual positive controls; typed consume and inspection are
   present. Publication is skipped. Full CI 37223117459 last had 18 successes and
   21 pending jobs. This evidence does not accept the new Dart candidate.
3. Continue the remaining implementation and issue acceptance below. Keep all ten
   issues open until their criteria have been checked; no performance parity or
   all-platform execution is established.

The Session fixture/registration stage has passed canonical verification, complete
local browser coverage at unchanged floors, and both complete 305-mutation gates.
Its earlier failed coverage wrappers and intermediate gate failures remain retained
in project state and the proof artifacts; they are not relabeled as passes.

## Remaining implementation and acceptance

The candidate now selects typed native decryption before payload exports in
opt-in RawSocket/WebSocket Session receives. Metadata wrappers and a generic
deferred application view preserve lazy values/errors and explicit owned copies.
Default transport forwarding stays eager. Callback mutation, provider/context
replacement, recursive wire loading and classic decoding have fail-first repairs.
The expanded older-ABI matrix also repairs CBOR byte-string shape handling while
rejecting numeric arrays before policy. Fresh local `bin/test-fast` and full
`bin/verify` both pass at exit 0; hosted and acceptance evidence remain pending.
RawSocket AES pointer reuse is observed for the binary serializers;
WebSocket exercised copied fallbacks. Existing malformed-payload and context-free
ordering regressions remain retained evidence.

An initial manual native-owned typed path now connects a frozen FlatBuffers
application payload to `packNativeTypedPayload`, opaque frame composition and
`NativeFrameTransport` submission. Optional ABI v1 borrows the input in Rust and
publishes the cipher's output allocation as a frozen owned buffer. Rust pointer
oracles verify both cipher allocations; Dart tests verify the independent input
owner and composed frame. This avoids payload copies through Dart typed data.
Ordinary Dart-value E2EE retains its existing input/output copies. Full-session
copy counts and controlled performance parity remain unmeasured; account for
crypto, TLS, masking, coalescing, builder growth and transcoding, and apply shared
optimizations to the CBOR/MessagePack baselines too.

Complete external session conformance and malformed-input/fuzz/ownership CI. The
pinned Autobahn object serializer is not a functioning live peer. Existing
independently generated Python read/write fixtures verify codec messages, not full
session conformance. Execute the supported platform/consumer acceptance paths.

Declare controlled workloads, budgets, warmup/repetitions and noise policy before
measuring FlatBuffers versus both CBOR and MessagePack. Cover ordinary values,
native construction and pre-encoded spans separately; both transports, clear/TLS,
Dart/native clients, RPC/pubsub/fan-out/progressive/mixed traffic and relevant
payload sizes. Record correctness, throughput, latency, CPU, memory/GC, wire size,
retained allocations and copied bytes. Missing metrics, failed primary rows or
inconclusive intervals block acceptance. No parity result exists yet.
The proposed [performance contract](../flatbuffers_performance_acceptance.md)
records the comparison groups, primary rows, repetition/noise rules and evidence
requirements before measurement; runner policy and CPU/memory budgets remain open.

The existing ordinary-value 16 KiB serializer diagnostic matrix now contains
FlatBuffers rows for both transports with the same settings as its binary
baselines. A native orchestrator regression proves completeness and serializer
preservation (six-row fail-first, eight-row pass). No performance measurements
are accepted from this change. The current typed-provider prototype remains
incomplete: a typed application schema and worker/iteration validation must
precede typed workloads, especially pub/sub where keyword containers are invalid.

Finish public consumer and adapter-boundary docs, then audit each issue before
closing issues and the milestone. Release publication and merging master remain
outside authorization.

## Pushed checkpoint and research

At d26581c3, hosted PR CI completes successfully with all 40 jobs. Five-platform
Native Artifacts dry-run succeeds with publication skipped. Bundle source/checksum/
provenance verification passes; Apple Silicon executes 34 native checks and a
standalone consumer. Other platform binaries are not executed here. PR #105 now
records these completed results. They do not clear the uncommitted stage.

Reference [binding](../flatbuffers_binding.md), [PPT/E2EE](../e2ee_ppt_research.md),
[ownership](../native_buffer_ownership.md), and [current state](../project_state.md).
The [implementation journal](../history/2026-10-04-flatbuffers-implementation-journal.md)
and [prior state](../history/2026-10-04-project-state-before-flatbuffers-consolidation.md)
remain byte-preserved historical evidence. Retained failed/superseded attempts and
freshly corrected compiler/symbol/platform attribution are recorded in current state.

## Live peer follow-up (isolated candidate)

The independent upstream-only live peer fails at HELLO as expected by the strict
metadata-v1 profile. No public upstream-subset mode exists; do not infer support
from generated upstream readers. A separate generated-schema Python peer checks
explicit CHALLENGE and WELCOME acknowledgements and rejects missing/false offers.
It catches a shared cancellation URI defect and passes both cleartext transports
with the staged correction, including the exact downloaded production library.
Keep the legacy failure-control report and the passing 48-case existing regression
control. The reviewed checker, CI integration and cancellation correction are now applied
after the unchanged-setting full benchmark reproduction passed. Actual feature
production-library peer acceptance independently audits all 1,458 source bytes,
69 regenerated bindings and all protocol/control evidence. Fresh canonical and
browser coverage runs freeze those 1,458 files under `live-peer-*` prefixes;
they must complete before commit/push. No full verify or hosted acceptance is
inferred from the peer proof. Hosted/all-platform evidence and the rest of issue #102 remain open.
See [the research record](../research/2026-10-04-flatbuffers-live-peer-conformance.md).

The first combined-candidate fast run fails two app-lab supervisor deadlines and
never reaches full verify. Its failed 1,458-file snapshot and protected/native/log
hashes independently audit. All 15 focused app-lab tests subsequently pass at the
same deadlines, so preserve both observations without inventing a root cause.
Complete and audit the current fresh browser coverage before scheduling another
full canonical run; avoid simultaneous resource-heavy suites. Do not change
budgets, exclusions or mark either failed canonical run accepted.

Fresh combined-candidate browser coverage passes both complete cohorts and the
independent 1,458-source/99-artifact audit, regenerating the same summary and
preserving unchanged floors. The next complete canonical run is now launched
sequentially under `live-peer-sequential-canonical-*`. No concurrent large suite,
new deadline, exclusion or outcome relabeling is used.
Both canonical phases now pass at exit 0 against the same frozen 1,458-file
inventory. The independent completed audit verifies all product/protected/native/
log hashes and equality with the accepted browser coverage product snapshot:
`/tmp/connectanum-flatbuffers-live-peer-sequential-canonical-completed-audit.json`.
The next crypto boundary is prepared in the
[source-backed research](../research/2026-10-04-native-owned-crypto-boundary.md),
including corrected local test/architecture advice. No new crypto API is applied
during this canonical run. [Benchmark construction preparation](../research/2026-10-04-flatbuffers-benchmark-construction.md)
also records the missing echoed application identity check. Commit/push the
accepted checkpoint and obtain its own hosted evidence before claiming hosted
acceptance; all ten issue criteria remain under audit.
