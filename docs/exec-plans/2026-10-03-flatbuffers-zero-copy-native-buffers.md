# FlatBuffers and zero-copy native buffers

Status: active. Started: 2026-10-03.
Milestone: [GitHub milestone 1](https://github.com/konsultaner/connectanum-dart/milestone/1).
Branch: `codex/flatbuffers-zero-copy` in the managed FlatBuffers worktree.
Baseline: `54eafc5fb675886a04d390f069714c69de2aaac0`;
released master `3bac4cf5` is integrated. Session checkpoint: `c37c04ee`.
Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

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

1. Verify the new native-anchor preflight checkpoint's hosted CI and production
   artifacts. Canonical fast/full checks and completed source/native/log audit
   pass on the unchanged 1,453-file snapshot `508a2c0c`. Chrome WASM passes 4,558
   core and 2,800 client cases (20 explicit native-only skips); VM native suites
   have no unavailable-library skips. The eight-case fail-first regression proves
   policy invocation before empty-ciphertext rejection. Optional non-consuming
   shape/length inspection repairs it; canonical JSON is checked without decoding,
   binary readers borrow storage, and older ABI materializes safely. Focused
   verification passes 224 new-library VM cases and 143 older-ABI runtime cases.
   GuardMalloc passes 58 cases with audited source/executable/loader/count/log and
   cleanup evidence. A separate eight-case cached-boundary regression is repaired.
   Preserve the wrong-exception compilation failure and the mistaken segmented
   fixture assertion separately from successful evidence. Core source is unchanged;
   its complete mutation evidence does not need rerunning for this IO repair.
2. Verify exact pushed-head CI, including hosted browser coverage and memory
   tooling. c37c04ee contains the Session/coverage repair and is queued/running
   without observed failures. Hosted browser coverage and 57-case/five-control
   GuardMalloc pass, with uploaded source/LCOV/loader/count/log evidence audited.
   Other CI jobs remain pending. All five c37 dry-run bundles pass checksum/manifest
   and source/workflow provenance verification. Its Apple Silicon production
   library passes 201 VM native/Session cases and the standalone construction
   consumer with exact c37 sources; four other binaries are verified but not
   executed. Publication is skipped. These results do not accept the new repair.
3. Continue the remaining implementation and issue acceptance below. Keep all ten
   issues open until their criteria have been checked; no performance parity or
   all-platform execution is established.

The Session fixture/registration stage has passed canonical verification, complete
local browser coverage at unchanged floors, and both complete 305-mutation gates.
Its earlier failed coverage wrappers and intermediate gate failures remain retained
in project state and the proof artifacts; they are not relabeled as passes.

## Remaining implementation and acceptance

Accept the candidate's runtime-payload capability and key-ordering fix, then select
native decryption before opaque payload exports. Eager exports keep native references
and force the safe copied AES fallback. Opt-in deferred materialization alone is
insufficient for transport integration: reading `incoming.message` exports all
parts. Preserve already exported immutable data and forwarding semantics. Existing
malformed-payload and context-free ordering regressions remain retained evidence.

Connect native-owned payload construction through encryption and submission.
Generic crypto still copies input into native storage and output back to Dart.
Measure avoidable copies separately from crypto, TLS, masking, coalescing, builder
growth and transcoding, and make shared optimizations available to binary baselines.

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
