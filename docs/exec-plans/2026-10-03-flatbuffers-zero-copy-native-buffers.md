# FlatBuffers and zero-copy native buffers

Status: active. Started: 2026-10-03.
Milestone: [GitHub milestone 1](https://github.com/konsultaner/connectanum-dart/milestone/1).
Branch: `codex/flatbuffers-zero-copy` in the managed FlatBuffers worktree.
Baseline: `54eafc5fb675886a04d390f069714c69de2aaac0`;
released master `3bac4cf5` is integrated. Preceding checkpoint: `e6fb28c8`.
Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

Latest pushed checkpoint: `e1ee796a` on PR #105, following the native transport
counter/evaluator checkpoint `f7387de0` and fixes for the exact-head CI failures
exposed by `a28e92c4`. The `e1ee796a` RSS window correction passed local
`bin/test-fast` and `bin/verify`; exact-head hosted checks were queued. The
working-tree Dart transport-copy follow-up passes `bin/test-fast` and full
`bin/verify`; exact-head hosted checks remain pending. It adds partial Dart-path
attribution and closes the evaluator's coverage gate, but does not provide a
measured performance result. Issues #95 and #96 are now complete and closed. Earlier
independent negotiated-profile, GuardMalloc, five-platform artifact and package
publish dry-runs remain separate evidence.

## Objective and scope

Complete all ten milestone issues. FlatBuffers is a regular serializer beside
JSON, MessagePack and CBOR, with interoperable Dart/Rust codecs, native-owned
construction, generic external-buffer leases, lazy routing, PPT/E2EE and measured
performance at least matching the better binary baseline on declared workloads.
ObjectBox integration itself belongs to a separate adapter package.

The primary checkout is independent and remains untouched. Feature commits,
pushes and draft PR updates are authorized. Release publication, version bumps
and a master merge are not authorized.

## Issue acceptance status

- [x] [#95](https://github.com/konsultaner/connectanum-dart/issues/95): pinned binding, reproducible generation, metadata/schema compatibility.
- [x] [#96](https://github.com/konsultaner/connectanum-dart/issues/96): native builders, freeze/retain/transfer, native inputs throughout submission.
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

## Typed benchmark fixture checkpoint (2026-10-05)

The benchmark package now has a deterministic workload schema with worker and
iteration identity, equivalent Dart/native FlatBuffers builders, and live echo
coverage for twelve RawSocket/WebSocket, Dart/native-caller, and outer-serializer
combinations. Native WebSocket callers use a spawned isolate because a native
handshake in the same isolate as its Dart callee can fail with native I/O error
`-7`. The generator uses the compiler version already pinned in the WAMP
manifest, and CI checks that generated Dart stays current. The fixture avoids an
extra expected-body allocation during verification. These are correctness and
generation checks only. `WampWorkloadRunner` does not yet expose the three
construction groups, and no paired throughput/latency/memory campaign or parity
result exists. Issue #103 remains open.

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
3. Continue the remaining implementation and issue acceptance below. Keep each
   issue open until its criteria have been checked; #95 and #96 are now closed.
   No performance parity or all-platform execution is established.

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
Ordinary Dart-value E2EE retains its existing input/output copies. Native-path
transport copy counters now expose explicit Dart-to-native copies and WebSocket
mask/coalesce copies across client and router snapshots. A separate Rustls
counter reports accepted plaintext bytes, not memory copies. Dart-managed
socket/TLS copy paths, mixed-serializer transcodes and other
end-to-end copy sources remain unmeasured. Controlled performance parity is
still unmeasured; account for crypto, builder growth and remaining copy paths,
and apply shared optimizations to the CBOR/MessagePack baselines too.

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
acceptance. At that checkpoint all ten issue criteria remained under audit.

The initial manual native-owned FlatBuffers E2EE path is committed as `dc33fcc6`
and pushed to PR #105. Fresh `bin/test-fast` and `bin/verify` pass at exit 0 on
the code checkpoint; its exact-head hosted checks are pending. The path is
generic Connectanum ownership infrastructure that a future C-backed ObjectBox
adapter can consume under an explicit producer lifetime. Issues #96 and #101
advance but remain open at that checkpoint; all ten milestone issues were under
audit.

## Typed benchmark runner construction groups (2026-10-05)

The typed fixture now drives unique, per-iteration benchmark payloads for RPC and
pub/sub. TOML `payload_construction` is passed through the Rust orchestrator to
the Dart runner. `values`, `native_buffer`, and `pre_encoded_span` work with
FlatBuffers, CBOR and MessagePack PPT under the typed benchmark schema; invalid
scheme/mode/serializer combinations fail validation. The runner validates every
RPC result and each pub/sub delivery, retains owners until cleanup and reports
payload preparation plus native-builder input/growth counters. Eighteen live
RawSocket cases with the Dart caller and CBOR WAMP envelope pass, and a focused
RPC test confirms owner disposal follows result consumption. A separate twelve
case matrix exercises typed FlatBuffers PPT across both transports and caller
implementations, but not the new runner groups. Rust tests pass 181/181; focused
Dart tests, package analysis and formatting pass.

Instrumentation is deliberately attributed narrowly: end-to-end `latency_ms`
includes preparation and response validation, but `payload_preparation_us` for
dynamic CBOR/MessagePack groups excludes later PPT serialization. Builder copy
counters exclude codec and transport copies, including TLS, WebSocket and E2EE.
See [the updated acceptance contract](../flatbuffers_performance_acceptance.md)
and [bench usage](../../packages/connectanum_bench/README.md). `bin/verify`
passes at exit 0 on 2026-10-05. No paired campaign, memory/CPU gate or performance
parity result exists. The runner stage does not accept issue #103 or the milestone.

## Session native-owned typed FlatBuffers PPT path (2026-10-05)

`NativeOwnedBuffer.asFlatBuffersPptPayload()` can be passed to
`Session.callLazyPayload` or `Session.publishLazyPayload` with matching opaque
FlatBuffers PPT options. Once a native FlatBuffers session is established, the
CALL/PUBLISH fast path accepts only a nonempty non-`wamp` PPT scheme, the
`flatbuffers` application serializer, and no PPT cipher or key ID. It confirms
that the exact packed byte view still belongs to a frozen `NativeOwnedBuffer`,
then emits a control-only FlatBuffers envelope and composes the encoded
application bytes as a retained opaque frame span. `FlatBuffersSessionProfile`
preflight still runs before fast-path selection; `sendNativeFrame` validates and
commits the profile through the envelope. Other message shapes use normal
serialization.

Cycle-safe traversal follows nested `LazyMessagePayload` storage owners and
anchors. Queueing retains the native allocation through asynchronous native
frame submission, so tests dispose the caller's owner as soon as Session send
returns and still receive the correct response. RawSocket and WebSocket session
integration, a deep nested-anchor case, transparent CBOR fallback, and
control-only writer behavior pass. Ordinary Dart-backed payloads retain their
copying serializer path. This avoids passing the application bytes through a
Dart serialization buffer for eligible messages, but does not claim that later
WebSocket masking, TLS, encryption or platform output stages avoid copies. No
benchmark parity is inferred. `bin/test-fast` and `bin/verify` pass at exit 0
on functional checkpoint `f569e9b4`; the benchmark-runner follow-up passes
`bin/test-fast` and awaits full verification and fresh exact-head hosted CI.

## Native typed benchmark runner integration (2026-10-05)

For typed FlatBuffers PPT with `native_buffer` or `pre_encoded_span` construction,
the runner now uses `NativeOwnedBuffer.asFlatBuffersPptPayload()`. When the
caller is the native implementation and the WAMP envelope serializer is
FlatBuffers, eligible PPT calls use a control-only envelope and retained
application span. `dartValues`, Dart transports, other outer serializers,
transparent payloads, other PPT serializers and encrypted PPT keep the existing
serialization paths.

A live 12-case matrix covers native RawSocket RPC/pub-sub with FlatBuffers WAMP
envelopes, FlatBuffers/CBOR/MessagePack PPT and both owned construction groups;
each case runs two validated iterations. Runner tests verify that packed bytes
and the storage-owner record are the same view, ownership is live during a call,
and a rejected call still disposes the owner. Focused runner analysis, scenario
tests and the live matrix pass. Both `bin/test-fast` and `bin/verify` pass on the
current candidate, including Chrome WebAssembly and hosted consumer smoke tests.
Fresh exact-head hosted CI remains pending. This is correctness evidence only:
no timed comparisons or complete copy, CPU, memory or parity results exist, so
issue #103 stays open.

## External producer lease through a delayed native send (2026-10-05)

The external C producer fixture now emits a deterministic 15 MiB byte pattern
from its owner thread. A test peer runs in a separate Dart isolate because the
native RawSocket connect/handshake call blocks the caller isolate. It completes
the handshake, pauses reads until the native write receipt is observed pending,
then resumes and validates the complete RawSocket frame byte-for-byte. The test
asserts that the producer lease remains live during backpressure and is released
exactly once on its owner thread after write completion. The focused test passes;
`bin/test-fast` and full `bin/verify` also pass. Fresh hosted evidence for this
follow-up is pending. This supplies a real-send lifetime oracle for #97 without
closing that issue's remaining acceptance criteria.

## Native transport copy-counter follow-up (2026-10-05)

Optional C/Dart FFI snapshots count explicit Dart-to-native send copies and
WebSocket mask/coalescing payload copies. A separate Rustls counter reports
accepted plaintext input volume, not memory copies. The
benchmark aggregates active client and router process deltas; missing active
path counters fail closed. Dart-managed socket/TLS paths and mixed-serializer
transcodes remain unmeasured. Focused tests, `bin/test-fast` and full
`bin/verify` pass at exit 0, including Chrome WebAssembly, live WAMP integration
and consumer smoke checks. This is correctness evidence and partial native-path
attribution only; it establishes neither complete copy coverage nor FlatBuffers
performance parity, and issue #103 remains open.

## Dart transport-copy attribution follow-up (2026-10-05)

The Dart benchmark worker records synchronous Connectanum-owned RawSocket
framing, small-fragment coalescing, pre-handshake queue copies, and WebSocket
fragment coalescing around each workload. Those counters deliberately exclude
copies inside `dart:io`, SDK WebSocket masking, and TLS. The final report nests
client/router copy breakdowns, adds router deltas to the known-own lower bound,
and emits numeric `transport_copy_bytes` only for a complete measured cleartext
path. The paired evaluator requires the corresponding complete coverage marker
and an empty unknown-boundary list; it also rejects not-applicable transport
totals. Focused counter, aggregation, and 13 evaluator tests pass, and
`bin/test-fast` passes on this working tree. Full `bin/verify` and exact-head
hosted checks remain pending. This instrumentation does not measure Dart SDK
writes/masking, TLS or mixed-serializer transcodes and does not establish
FlatBuffers parity. Issue #103 remains open.

## Paired comparison evaluator and hosted CI correction (2026-10-05)

`tool/wamp_serializer_compare.py` now validates campaign metadata, non-overlap,
workload identity/order, complete sample/resource/copy evidence and the declared
paired metric gates. The machine-readable policy covers throughput, p95/p99
latency, CPU, allocation, GC pause, peak RSS and zero avoidable payload copies
at named optimized boundaries. Seven evaluator unit tests pass. It is an
analysis/gate tool only: it does not execute or schedule benchmarks, and there
is no campaign manifest or measured result. Unmeasured Dart-managed socket/TLS
and mixed-codec transcode paths remain blockers for the required rows.

The exact-head run for `a28e92c4` exposed two reproducible CI defects. Five
bench tests tried to load `libct_ffi.so` because the CI fast script did not pass
its just-built FFI test artifact into the package process. The two core-lazy
jobs stopped before mutation execution because source edits changed the AST
mutation identifiers while their justifications still named the old IDs. The
The fixes are committed and pushed as `f7387de0`. `bin/test-fast`, full
`bin/verify`, and source/ID inventory checks for both VM and browser targets
pass locally. Exact-head hosted CI for `f7387de0` is running; its complete
mutation campaigns remain acceptance evidence for this correction.

## WAMP process-resource attribution follow-up (2026-10-05)

The comparator previously evaluated CPU, allocations, GC pause and peak RSS
from the client worker only. A new working-tree change requires both client and
server process metric blocks, preserves them separately in JSONL and transformed
artifacts, and calculates resource ratios from the sum per operation. The
`server_process_metrics` block explicitly describes the Dart process hosting
RouterBinding and the HTTP benchmark controller, not an isolated router. Each
workload gets one throwaway warm-up operation before its server measurement
window so lazy router isolates exist before profiling starts. The collector
profiles all application isolates present when the window begins and rejects
isolate-set changes. Linux `/proc` provides process CPU ticks and 50 ms RSS
samples; those fields remain missing on other platforms, as do GC values when
the timeline fails to settle. The Rust orchestrator starts VM-service profiling
on that process when `--collect-wamp-vm-metrics` is requested. Eleven Python
evaluator tests, the Dart isolate-set tests, the Rust `http_stream` tests and a
live macOS one-workload smoke pass. The smoke confirms both process blocks and
server allocation/GC data; macOS lacks the Linux CPU/RSS fields required for
acceptance. The comparator names its RSS total `summed_sampled_peak_rss_bytes`
because client and server peaks can occur at different times. No campaign is
scheduled by the evaluator, and no FlatBuffers parity result exists. The exact
head after these working-tree changes still needs full local verification and
hosted CI.

`bin/test-fast` and full `bin/verify` now both exit 0 on 2026-10-05. Full
verification includes Chrome/WebAssembly serializer and client suites, live
FlatBuffers WAMP transport workloads, Rust benchmark tests, consumer-package
smokes and router integration suites. The paired-comparison evaluator has
eleven passing tests; the Dart VM process/isolate and Rust `http_stream` tests
also pass. The macOS workload smoke verifies collection wiring only because
Linux `/proc` CPU/RSS evidence is unavailable there. No paired measurements
have run, so issue #103 remains open and milestone parity acceptance is not met.
Exact-head CI and package publish dry-run workflows are queued for pushed
commit `f47438d4`.

## RSS sample-window race correction (2026-10-05)

The sampler previously dropped its final `/proc/<pid>/status` read when a 50 ms
timer read was still in flight. Server current RSS was also read after VM
profiling RPCs, outside the measured interval. `DartVmMetricsRssSampler.stop`
now waits for an active read, performs one final read, and returns current and
peak RSS together; repeated stops share the same result. Both client and server
process records use this snapshot before VM profiling finishes. A delayed-reader
test verifies ordering, end-boundary current RSS, maximum peak RSS and idempotent
stop. The server retains an end-of-workload `ProcessInfo` current-RSS value for
non-Linux diagnostics, while Linux rows remain missing if `/proc` cannot supply
the sampled boundary. `bin/test-fast` and `bin/verify` pass with exit 0 on the
RSS race correction; the final non-Linux diagnostic fallback also passes the
focused metrics suite and benchmark-package analysis. An 8-workload Linux arm64
serializer-matrix smoke emits numeric current/peak RSS
for both processes and all rows satisfy current <= sampled peak. It is a
640-sample wiring smoke, below the 1,000-sample acceptance floor. The same smoke retains
`transport_copy_bytes: not_measured` for Dart-managed callers; copy attribution,
the full campaign, hosted exact-head CI and every issue acceptance remain open.
