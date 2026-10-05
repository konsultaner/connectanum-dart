# Project State

Last updated: 2026-10-05.
Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
All ten issues (#95–#104) remain open. Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

## Checkout and authorization

The managed worktree uses `codex/flatbuffers-zero-copy`; its latest pushed checkpoint is
`dc33fcc6ce216469c8818b919ce003543ea74091`, following `3b5927f1`. Exact-head
hosted checks for this checkpoint are pending. It started at `54eafc5f` and
integrates released master `3bac4cf5`. The primary checkout's independent work
remains untouched. Feature commits, pushes and draft PR updates are authorized;
releases, version bumps, publication and merging master are not authorized.
Actual ObjectBox integration belongs in a separate adapter. Core provides generic
memory contracts. The earlier coverage/mutation objective is deferred.

## Accepted deferred Session checkpoint (0cf9e65e)

The pushed checkpoint connects opt-in native consuming typed E2EE to actual
Session receives. Both native transports expose `consumeTypedE2eePayloads`,
disabled by default and locked once opening starts. Eligible RESULT/EVENT/
INVOCATION metadata can be read before payload exports; application loading
selects native decrypt first. Generic `LazyMessagePayload.deferred` shares values
or terminal error/stack across related views. Ordinary transport behavior stays
eager. Original unexported ciphertext becomes unavailable after consumption.
Wire export forces a safe copied fallback; wire mutation clears its native anchor.
The following detailed records describe successive historical validation attempts;
the current uncommitted follow-up is the key-policy repair below. The final
sequential canonical/browser audits accept this checkpoint, while its earlier
failed attempts remain failed evidence.

Fail-first regressions caught 24 key-policy mutation failures, two stale
provider/context views, recursive wire loading and explicit classic decoding;
the fixes have passing controls. Expanding real older-ABI coverage caught 28 CBOR
RESULT/EVENT failures: CBOR byte strings become `Uint8Buffer`, rather than
`Uint8List`. The fallback now validates `CborBytes` directly; four extra cases
reject numeric arrays, short byte strings and non-binary values before policy.

Focused verification passes 2,227 current-library VM runtime/binding cases,
371 older-library runtime cases and 115 core lazy cases on each of VM, Chrome JS
and Chrome WASM. The production Apple Silicon library passes the 228-case new
Session matrix. Actual pointer checks prove contiguous RawSocket AES reuse for
all three binary serializers; WebSocket exercised copied fallbacks. Initial
fixture-only JSON/read-only expectation failures remain preserved. These are
correctness/ownership checks, not benchmark parity acceptance.

The first canonical fast run failed workspace analysis on eight fixture API/
import errors; targeted analysis had missed the part-file context. The fixture
now reuses the existing JSON codec and default shared native runtime. Workspace
analysis exits 0. Both initial mutation runs failed closed on eight stale
equivalence records. All eight operators/contexts and paired-field invariants
were rechecked, with no new exclusions or gate/deadline change:
`/tmp/connectanum-flatbuffers-session-deferred-equivalence-rebase.json`.
The repaired fast run then caught the new part missing from two native mutation
targets' support inventories. Its failing tooling test is preserved; adding the
part to both inventories passes that exact control. The initial repaired lazy
campaigns observed three actual VM timeouts: two deleted recursion guards and
deleted graph-copy memoization. Bounded loader assertions and the existing
traversal-budget graph turn all three into completed assertion failures on VM
and Chrome JS at the unchanged deadlines. All six exact mutant kills, four
197-case baseline/restored controls and staged/source/log hashes pass audit:
`/tmp/connectanum-flatbuffers-session-deferred-loop-bound-completed-audit.json`.
The known-failed campaigns were stopped before applying these test-only repairs;
both interrupted reports remain incomplete/failed, and their owned children are
confirmed gone. No production source or equivalence changed in that repair.

The complete VM campaign now passes all 356 mutations: 267 assertion-backed
kills (176 assertion-only, 91 mixed), 21 survivors and 68 compile errors at
95.35714%, with no timeouts, unknown/testError-only kills or new exclusions.
Both baseline/restored controls complete all 197 cases. Every mutation is
regenerated and its applied-source hash/classification, all selected input,
runner/configuration/native hashes and 358 mutation/control log hashes verify:
`/tmp/connectanum-flatbuffers-session-deferred-loop-bound-core-lazy-vm-completed-audit.json`
and `*-independent-log-hashes.json`. The first audit used the wrong restored-log
suffix; the corrected audit reads the actual restored-baseline log. The run is
unchanged. The complete browser campaign also passes all 356 mutations with
identical counts, score and assertion evidence. Independent regeneration and
selected-input audit passes; its whole-product wrapper failure remains recorded
because of the sole tooling-test edit described below. The complete 603-mutation
binding campaign fails at 89.43089%: 456 detections (440 assertion-backed),
36 survivors and 111 compile errors. Both 1,856-case controls pass. Its regenerated
inventory, classifications and selected-input hashes are independently audited;
the failed result remains evidence rather than acceptance.

An isolated 24-case binding contract fixture covers all eligible incoming codes,
both ciphers, runtime versus wire loading, memoization, metadata rejection and
wire replacement/anchor invalidation. Its 1,880-case baseline and restored
controls pass. Of 35 observed survivors, 20 become assertion-backed kills,
one becomes a test-error-only detection and 14 remain; all staged input and
individual log hashes pass a targeted audit. This is not a complete gate result.
Explicit positive metadata and successful-construction assertions strengthen
that fixture; its corrected 1,880-case baseline passes. An initial fixture-only
compile failure from using getter values as constant switch patterns is retained.
Fresh complete binding verification has completed in
`/tmp/connectanum-flatbuffers-deferred-binding-test-stage`, with prefix
`/tmp/connectanum-flatbuffers-deferred-binding-contracts-*`. After canonical
verification completed, these test additions were applied to the feature tree;
the completed campaign's test hash exactly matches the applied file. Its isolated
inputs remain frozen.

The next fast run failed an exact expected-support-list assertion that still
listed only the old parts. Its literal inventory is now updated, and both exact
scope controls pass. This sole Python tooling-test change is outside every
selected mutation runtime/test/support input; its before/after hashes and reason
are recorded in `session-deferred-tooling-expected-list-change.json` under `/tmp`.
Keep any whole-product wrapper rejection of that edit separate from the actual
mutation process result and selected-input audit. Canonical fast/verify passes
on the 1,454-file snapshot
`12c56f179b45a0b84446bfa489784e2420d9b537a1afd08cf8af46add59e458a`.
Prefix: `/tmp/connectanum-flatbuffers-session-deferred-tooling-repaired-canonical-*`.
Both terminal exits, all product/protected source and native/log hashes pass
independent completed audit. This accepts the Session candidate before the new
binding assertions and benchmark diagnostic rows. Fresh fast/full verification
now runs under `/tmp/connectanum-flatbuffers-session-deferred-contracts-canonical-*`;
fresh complete Chrome JS coverage runs under
`/tmp/connectanum-flatbuffers-session-deferred-browser-coverage-*`. Both freeze
the updated 1,454-file product inventory. Fresh Chrome JS coverage completes
4,595 core cases and 2,820 client cases plus 20 native-only skips. Client
96.42969% and core 96.18337% pass unchanged floors. All 1,454 product bytes,
the native library, log and 99 raw/LCOV/summary artifacts pass independent audit;
a freshly regenerated coverage summary also agrees. Proof:
`/tmp/connectanum-flatbuffers-session-deferred-browser-coverage-completed-audit.json`.
The complete fresh binding campaign now passes all 603 mutations at 96.13821%:
477 detections (473 assertion-backed and four test-error-only), 111 compile
errors and 15 survivors. No equivalents or deadline/gate changes. All regenerated
mutations, frozen staged inputs and matching selected feature inputs, native hashes,
605 individual logs and both 1,880-case controls pass independent audit:
`/tmp/connectanum-flatbuffers-deferred-binding-contracts-client-message-binding-vm-completed-audit.json`.

Fresh canonical fast passes, but full verify fails nine two-second readiness
checks in `native_wamp_worker_lifecycle_test.dart` during the benchmark suite.
The complete failed run's 1,454 source bytes, native/protected inputs and logs
pass independent audit under `session-deferred-contracts-canonical-completed-failed-audit.json`.
An initial auditor incorrectly counted repeated error phrases instead of failed
test entries; corrected counting confirms nine failures without changing execution.
All 36 focused lifecycle cases pass at unchanged deadlines. The complete benchmark
reproduction passes all 1,366 cases under `/tmp/connectanum-flatbuffers-canonical-bench-full-repro.log`
with the exact original environment and test settings; its completed proof is
`/tmp/connectanum-flatbuffers-canonical-bench-full-repro-proof.json`. The preceding
readiness failure is not reproduced, but its cause is not established. No readiness deadline or
lifecycle code has been changed. Full verification remains unaccepted. The preceding
`session-deferred-repaired-*` runs are failed evidence, not gate acceptance.
Core focused checks still pass 115 cases per VM/JS/WASM compiler after the repair.
Companion advice/dispositions are recorded in
`/tmp/connectanum-flatbuffers-session-deferred-companion-dispositions.json`.

The ordinary 16 KiB serializer diagnostic matrix now adds FlatBuffers RPC rows
for both RawSocket and WebSocket, alongside all existing JSON/MessagePack/CBOR
rows. A fail-first native orchestrator regression fails on six versus eight rows,
then passes with identical operation/payload/concurrency settings and preserved
serializer names. The initial zero-test selector and formatting correction are
retained in `/tmp/connectanum-flatbuffers-serializer-matrix-focused-proof.json`.
This matrix uses CBOR fragments inside FlatBuffers envelopes. No throughput,
latency, typed-payload, native-construction or parity result is established.

The pushed e6fb checkpoint's five production bundles pass manifest/checksum and
exact source/workflow attestation verification. Its Apple Silicon bundle passes
209 VM native/Session cases and the standalone 108-byte/three-segment construction
consumer against all 1,453 exact e6fb product bytes. Oracle exports are actually
absent with positive controls; typed consume and inspection exports are present.
Proofs: `/tmp/connectanum-flatbuffers-e6fb-platform-artifact-proof.json` and
`/tmp/connectanum-flatbuffers-e6fb-artifact-consumer-completed-audit.json`.
Four other binaries are verified but not executed. Publication is skipped.
Exact-head CI 37223117459 last showed 18 successes and 21 queued/running jobs;
full hosted acceptance remains pending. This artifact proof accepts e6fb sources,
not the new Dart candidate.

## Independent live peer candidate

An upstream-only Python peer reproduces strict-profile rejection at HELLO because
it has no metadata vector. Source inspection confirms this is the current default
contract, not proof of a broken upstream-subset implementation: no public subset
mode is exposed. An independent peer generated from the derived pinned schema
explicitly offers and checks metadata-v1; this is not an Autobahn session peer.

The live peer catches a genuine shared cancellation URI defect. The router returns
`wamp.error.invocation_canceled` for killnowait, whereas WAMP specifies
`wamp.error.canceled`. An isolated exact-source candidate changes the shared
constant and preserves legacy incoming error classification in the benchmark
helper. Both cleartext RawSocket and WebSocket pass independent authentication,
large fragmented RPC, wide IDs, binary/UTF-8/kwargs, progressive results, callee
errors, cancellation/interrupt, acknowledged pub/sub and cleanup against the
pushed e6fb production Apple Silicon library. Missing/false offers abort before
credentials. Restoring the legacy URI makes the independent checker fail; the
failed report stays failed. All 48 focused benchmark/router cancellation tests
pass. Candidate code and reproducible CI tooling have now been applied to the feature
tree after the original-setting complete benchmark reproduction passed. The
feature's actual 1,458 product files, all 69 independently regenerated Python
binding files, native/report/log hashes and legacy failure control pass audit:
`/tmp/connectanum-flatbuffers-live-peer-feature-completed-audit.json`.
Its production Apple Silicon peer passes all 11 checks on both cleartext transports.
Python optimized mode is explicitly rejected; targeted analysis and CI YAML parsing
pass. The Dart router helper lives inside its owning router package; an initial
root-tool placement produced dependency lint diagnostics and was corrected.
An unrelated formatter-only typedef change was reverted using the pinned 3.10
formatter. Fresh canonical fast/full verification now runs under
`/tmp/connectanum-flatbuffers-live-peer-canonical-*`; fresh complete browser
coverage runs under `/tmp/connectanum-flatbuffers-live-peer-browser-coverage-*`.
Both freeze all 1,458 product files. The new canonical fast run fails two
unchanged app-lab supervisor fixtures at their 20-second deadline; full verify
is not reached. Its full source/protected/native/log audit preserves that failure:
`/tmp/connectanum-flatbuffers-live-peer-canonical-completed-failed-audit.json`.
All 15 app-lab tests then pass unchanged in focused reproduction, including both
failures; their cause remains unestablished. No deadline is changed. Fresh browser
coverage now completes 4,595 core and 2,820 client cases plus 20 native-only skips.
The complete 1,458-file source/native/log/99-artifact audit passes and regenerates
an identical coverage summary at unchanged floors:
`/tmp/connectanum-flatbuffers-live-peer-browser-coverage-completed-audit.json`.
A fresh complete canonical fast/verify run now proceeds sequentially under
`/tmp/connectanum-flatbuffers-live-peer-sequential-canonical-*`, freezing those
same 1,458 files with no other large validation suite running. Both `bin/test-fast`
and `bin/verify` now pass at exit 0, including the unchanged app-lab/readiness
deadlines. All product/protected/native/log hashes independently audit, and the
browser coverage snapshot matches every product byte:
`/tmp/connectanum-flatbuffers-live-peer-sequential-canonical-completed-audit.json`.
Snapshot: `76eb0b32841425d9cca365fd68742d29570d09fa049156b3eddabc4e1f274d50`.
Both preceding failed canonical runs remain failed evidence. Feature checkpoint
commit/push follows this completed local acceptance; new exact-head hosted
acceptance remains pending.
Chrome WASM completes 4,585 core and 2,829 client cases with 20 native-only skips;
VM native suites run without unavailable-library skips. The standard ffi-test
library remains at SHA256 `334d3449af8b18723b1f83c09bff080e4256b6c2c05b076a0afc23df9d8dfccf`.
Research and evidence boundaries: [live peer findings](research/2026-10-04-flatbuffers-live-peer-conformance.md).

## Current key-policy candidate

The deferred/live-peer checkpoint is now pushed as `0cf9e65e`. Its complete local
canonical/source audit passes. [Exact-head CI](https://github.com/konsultaner/connectanum-dart/actions/runs/37235293321)
remains pending; its independently audited negotiated-profile peer and GuardMalloc
jobs pass. The [five-platform artifact dry-run](https://github.com/konsultaner/connectanum-dart/actions/runs/37235321617)
and package publish dry-run pass, with publication skipped. All five downloaded
bundles verify checksum, manifest and exact-source provenance; platform execution
is separate evidence. Proofs: `/tmp/connectanum-flatbuffers-0cf-platform-artifact-proof.json`
and `/tmp/connectanum-flatbuffers-0cf-hosted-live-peer-completed-audit.json`.
The live-peer audit independently regenerates all 69 Python bindings and verifies
11 checks on each cleartext transport. An initial local auditor omitted generator
flags; its helper failure is preserved separately from the passing hosted report.
No TLS/upstream Autobahn, all-platform runtime, copy-count or performance acceptance
is inferred. Draft PR #105 is updated.

A new issue #101 follow-up has 72 fail-first assertion failures across portable
and native profile/key-policy callbacks. The uncommitted repair revalidates the
fixed profile and provider state after callbacks and keeps the effective key
aligned with metadata. All 88 contracts pass; eight extra controls preserve
existing reused-options key pinning. Complete focused checks pass 174 core cases
on VM, Chrome JS and Chrome WASM, plus 2,468 serial client/native cases on each
current and older library. A parallel native
test invocation's single unavailable-keyring-handle error is preserved separately.
Core E2EE inventory regeneration succeeds with 308 selected candidates, without
new equivalents, exclusions, deadlines or gates. The original canonical runner
passed `bin/test-fast` but lost its recorded processes while `bin/verify` was in
progress; its frozen verification record remains nonterminal and its log has no
terminal summary. Preserve that attempt as incomplete. The already-passing fast
phase and exact 1,458-file snapshot are independently checked before resuming
`bin/verify` under `/tmp/connectanum-flatbuffers-policy-revalidation-canonical-resumed-verify-*`.
The resumed `bin/verify` completes at exit 0; an independent audit reconciles it
with the prior `bin/test-fast` pass on the same frozen 1,458-file snapshot:
`/tmp/connectanum-flatbuffers-policy-revalidation-canonical-resumed-completed-audit.json`.
Fresh browser coverage then passes and verifies all 99 artifacts. Handwritten
Dart Chrome line coverage is 96.2473% overall (core 96.1862%, client 96.4297%);
164 library source files are outside this measurement and two generated
FlatBuffers artifacts are reported separately:
`/tmp/connectanum-flatbuffers-policy-revalidation-browser-coverage-completed-audit.json`.
The complete 308-mutant core E2EE VM and Chrome campaigns both pass at
95.9839% adjusted assertion score against the unchanged 95% gate. Each has 239
kills, 10 survivors, 59 compile errors, zero equivalents and matching 167-test
baseline/restored-baseline runs. Independent audits regenerate the inventory
and verify all input/log hashes:
`/tmp/connectanum-flatbuffers-policy-revalidation-core-e2ee-vm-completed-audit.json`
and `/tmp/connectanum-flatbuffers-policy-revalidation-core-e2ee-web-completed-audit.json`.
These accept this local key-policy candidate only. Exact-head hosted CI and the
separate throughput/latency/copy-count acceptance in issue #103 remain pending.
See [key-policy research](research/2026-10-04-e2ee-key-policy-revalidation.md).

## Earlier checkpoints

Commit b07d7b26 contains the typed E2EE, deferred exports, benchmark/RPC repairs
and memory CI tooling below. The verified Session repair preserves runtime
payload capability through negotiated Session wrapping. Typed providers opt into
key selection after their existing preflight: explicit key, configured policy,
negotiated directional key, then provider default. CBOR/custom behavior stays;
context-free wrapper calls retain their existing directional defaults. Actual
fail-first regressions cover early policy invocation and the initial candidate's
context-free default-key regression. No duplicate byte conversion is introduced.
Focused checks pass 268 client/native VM cases, 120 core VM cases and 66 cases in
each Chrome JS/WASM cohort; each browser cohort explicitly skips 20 native cases.
The initial 42 key-selection/capability cases cover portable/native ciphers and
CBOR, with source/log hashes audited under `session-preflight-final-focused`.
The registered fixture now has 56 VM cases including constructor, file-wrapper,
metadata-WELCOME and packed-application behavior; all pass. The change
does not yet make ordinary Session receive buffers unique or defer their exports.

Portable/native sibling providers implement a Connectanum-local version-2
`wamp` / `flatbuffers` E2EE profile for XSalsa20-Poly1305 and AES-256-GCM. They
preserve one raw application span, reject keyword containers and share machinery
with unchanged version-1 CBOR providers. Session selects exact profile/provider
compatibility. This is not a standardized WAMP E2EE version; application schemas
and all outer metadata are not validated or authenticated by this profile.

An optional native consume-format-wide API returns complete typed plaintext.
Format 0 preserves legacy CBOR unwrapping; missing typed exports use generic raw
decryption. Read-only outputs retain their owner through backing/derived views.
Explicit root release invalidates those views. Opt-in
`materialize(..., deferPayloadExports: true)` postpones all exports until the first
getter. Consume/release before export invalidates unexported getters; already
exported ciphertext remains valid and forces the safe copied fallback. Ordinary
transports/Session remain eager. Actual VM-service GC and 42 ownership matrix
cases are included in the 135-case runtime cohort.

Ordinary benchmark factories now support FlatBuffers, whose WAMP envelope uses
FlatBuffers and dynamic argument fragments use CBOR. Internal RPC transfer now
records the actual native serializer separately from fragment encoding. The
repaired peer speaks FlatBuffers, uses RawSocket ID 5 and acknowledges the profile.
Focused checks pass 78 factory and 16 live transport/RPC/pubsub cases. Typed
benchmark workloads remain a separate unfinished prototype.

The new macOS Native Ownership GuardMalloc CI job verifies failure controls and
uploads logs, exact source/executable hashes and dependency lock. Full Verify
depends on it. Both canonical scripts include its five tooling controls. A missing
Cargo lock is resolved before freezing the native inventory; compilation then
uses `--locked`. Timeout/interruption logs and owned-process cleanup failures are
retained and fail closed. Actual feature-tree execution passes 57 instrumented
cases, with loader/count/log evidence independently recomputed:
`/tmp/connectanum-flatbuffers-native-memory-feature-default-repo-completed-audit.json`.
The exact-head hosted job now also passes and its uploaded 57-case loader/count,
five failure-control, source and dependency/log hashes are independently verified:
`/tmp/connectanum-flatbuffers-b07-hosted-guardmalloc-completed-audit.json`.
This is macOS execution, not all-platform, ASan/Miri or performance acceptance.

## Earlier verification checkpoints

The preceding 1,450-file candidate passes both canonical fast/verify on snapshot
`b77da9a480509729d469e9d7ca91cf3bda5b5fc96132ff2030e4ded92afed1ea`.
All product/native/log hashes are audited:
`/tmp/connectanum-flatbuffers-deferred-factory-repaired-canonical-completed-audit.json`.
Local canonical scripts select Chrome WASM on macOS; hosted Linux selects JS.
Separate focused Session checks pass 44 cases each in Chrome JS and WASM.
The earlier description of both compilers as local canonical execution is corrected.

After applying the test-only loop oracle and memory CI tooling, fresh combined
fast/verify passes on unchanged 1,452-file snapshot
`edce848870ae28ab3aee2a7e30f144e9b230ab00112c7831085e560187cd40a0`.
Prefix: `/tmp/connectanum-flatbuffers-native-memory-loop-canonical-*`.
Both process exit codes, all product/native/log hashes and preserved history
bytes are independently audited in `*-completed-audit.json`. Canonical browser
execution is Chrome WASM on this host.
The native ffi-test library remains SHA256
`9884a14303c9036eec642cd55470f105dbfb898e62b3e4cb9ee28ffc179a2a78`.

The initial Session candidate passes combined fast/verify on 1,453 files,
snapshot `84a26cbab9aaa8c02b86ce39b61f57818df2af64c4e25fd7433e968a26ce717e`.
Prefix: `/tmp/connectanum-flatbuffers-session-preflight-canonical-*`; all source,
native/log and preserved-history hashes pass independent completed audit. That
pre-registration run does not itself execute the new fixture. After applying the
audited script/56-case fixture repair, final `bin/verify` passes on snapshot
`c415bf87cca057178fbd8e722182c83ef63200533b758f52d9e632ff2fd8ae36`
under `/tmp/connectanum-flatbuffers-session-coverage-repaired-canonical-*`.
All 1,453 source/native/log/history hashes pass independent completed audit:
`/tmp/connectanum-flatbuffers-session-coverage-repaired-canonical-completed-audit.json`.
The registered fixture passes all 56 VM cases with the native runtime available;
the full client Chrome WASM cohort passes 2,800 cases with 20 native-only skips.
Its core source adds five mutations: both fresh campaigns select all 305 at the
unchanged 95% gate/deadlines, with no equivalent additions. Independent committed
VM/browser checkouts use scratch snapshot `464ec8f9`. VM completes all 305: 236
assertion-backed kills, ten survivors and 59 compile errors at 95.93496%, with no
timeouts or new equivalents. Independent regeneration/classification and all
source/test/support/native/log hashes pass audit:
`/tmp/connectanum-flatbuffers-session-preflight-core-e2ee-vm-completed-audit.json`.
The Chrome JS campaign also completes all 305 with the same 236/10/59 counts,
95.93496% assertion score and no timeouts or new equivalents. Independent
regeneration, classifications, mutant hashes and source/test/support/native/log
hashes pass audit:
`/tmp/connectanum-flatbuffers-session-preflight-core-e2ee-web-completed-audit.json`.
Generated Python/Dart caches are explicitly excluded from wrapper source inventory;
every tracked product and test/support input still participates in source checks.

Current production native library SHA256
`01c90d8dbc169e49874e7755f06086e2f57c20fbc56f479961cb68fe678aef9c`
builds without ffi-test and passes 116 explicit VM provider/runtime cases.
The typed-format export exists; four actual owner-oracle exports are absent, with
positive controls against ffi-test. Audit:
`/tmp/connectanum-flatbuffers-typed-production-vm-completed-audit.json`.
The initial command completed VM cases but failed by attempting FFI WASM loading;
its failed report remains retained. Its misspelled symbol-absence check is discarded.
Older d265 production ABI fallback checks also remain valid independent evidence.

## Mutation acceptance

Unchanged production source has 300 core E2EE mutations. The repaired loop oracle
uses a distinct throwing policy sentinel so skipped byte conversion cannot proceed
to expensive 64 MiB decryption. Four observed timeout mutants are assertion-killed
at unchanged deadlines, with restored baseline passing. The full VM campaign
passes 235 kills, ten survivors and 55 compile errors at 95.9184%; no timeouts,
unknown/testError-only kills or new equivalents. All classifications and mutation
hashes are audited; source/test/support and target inputs match the feature tree:
`/tmp/connectanum-flatbuffers-typed-e2ee-loop-bound-committed-snapshot-core-e2ee-vm-feature-input-completed-audit.json`.
The matching Chrome JS campaign also completes all 300 mutations with the same
235/10/55 counts and 95.9184% assertion score, no timeouts or new equivalents,
and restored baseline exit 0. Its wrapper exits 1 because the separate audit
helper generated one `tool/__pycache__/run_dart_mutations.cpython-314.pyc` during
execution. The original failed wrapper report is preserved. An independent audit
verifies that exact sole added artifact, every frozen source/test/support byte,
all 300 classifications and mutant hashes, unchanged gate/deadlines, and feature
input equivalence:
`/tmp/connectanum-flatbuffers-typed-e2ee-loop-bound-committed-snapshot-core-e2ee-web-feature-input-cache-reconciled-completed-audit.json`.
The mutation process exits 0; the wrapper is not relabeled as passing.

Earlier failed campaigns remain failed: original VM 90.9465%; expanded VM with
one timeout; original browser with three timeouts at 94.6939%; logical-fixture
browser with one timeout at 95.5102%. The complete logical browser failure is
independently audited:
`/tmp/connectanum-flatbuffers-typed-e2ee-logical-bound-committed-snapshot-core-e2ee-web-completed-audit.json`.
Canonical fixture-registration, fake-peer, support-list and analyzer failures,
partial interruptions and scratch startup/mode/lock failures remain retained.
They are repaired or superseded evidence, not passes. See the history archives.

## Last pushed hosted evidence

[PR CI run 37196989435](https://github.com/konsultaner/connectanum-dart/actions/runs/37196989435)
passes all 40 jobs at d26581c3. Local canonical, complete lazy VM/web and binding
mutation gates pass; browser client coverage is 96.5283% above 96.29%.
[Native Artifacts run 37197154855](https://github.com/konsultaner/connectanum-dart/actions/runs/37197154855)
passes five platform builds with publication skipped. Downloaded source manifests,
checksums and provenance verify. Apple Silicon executes 34 native cases and a
standalone consumer; other platform binaries are not executed on this host.
PR #105 now records these completed hosted results. They do not clear the newer
candidate.

At b07d7b26, [PR CI 37213443908](https://github.com/konsultaner/connectanum-dart/actions/runs/37213443908)
is still running and has a Core Browser Coverage failure. All 2,755 browser
cases pass, but client coverage is 2,857/2,970 (96.195%) against the unchanged
96.29% gate. Preserve the failed log/report and reproduce the missing coverage
before accepting a repair. The isolated repair registers the Session suite in
fast/full verification and VM/browser coverage, with omission controls passing
among 80 tooling tests. Its first run passes 4,568 core and 2,777 client JS cases
(20 native skips), then fails reporting because `/tmp` and `/private/tmp` produce
relative LCOV paths outside scope. The failed wrapper is preserved. Reformatting
the same raw data under the physical path fixes source attribution but still
fails the unchanged client gate at 2,874/3,002 (95.736%). Eleven additional
constructor/native-file delegation cases pass alongside the existing cases
(53 VM total), but the complete refreshed client gate still fails at 96.086%.
Three additional metadata-WELCOME/packed-application cases then pass (56 VM
total). Final complete client coverage passes 2,791 JS cases with 20 native skips,
reusing only unchanged-source 4,568-case core data whose raw hashes are verified.
Independent DA counts and every source/raw/report/log hash are audited:
`/tmp/connectanum-flatbuffers-browser-coverage-final-completed-audit.json`.
Client is 2,907/3,017 (96.354%); core is 9,089/9,452 (96.160%), at unchanged
floors and scope. Original failed wrapper and both intermediate gate failures
remain failed. File probes and metadata peer verify Dart wrapper behavior, not
native file/network execution. The audited test and five tooling-file repairs
are now applied; final canonical verify and its completed audit pass. The memory job is accepted
separately above.
[Native Artifacts 37213468173](https://github.com/konsultaner/connectanum-dart/actions/runs/37213468173)
passes five builds with publication skipped. All manifests, checksums and exact
source/workflow provenance verify. Its Apple Silicon production library (SHA256
`b346c52ffd1d965f2a951d01935d08f6429044e953bffb363db1d47e4e889324`)
executes 145 VM native transport/provider/runtime cases plus the standalone
108-byte/three-segment consumer with direct input/growth copied bytes both zero.
Actual oracle symbols are absent with ffi-test positive controls, and the typed
consume-format export exists. Other four binaries are verified but not executed.
Proofs: `/tmp/connectanum-flatbuffers-b07-platform-artifact-proof.json` and
`/tmp/connectanum-flatbuffers-b07-artifact-consumer-completed-audit.json`.

## Earlier checkpoint follow-up and evidence

Final coverage-repaired canonical verification, the complete local browser
coverage audit and both 305-mutation VM/browser audits pass. The Session stage is
pushed as c37c04ee. [Its CI](https://github.com/konsultaner/connectanum-dart/actions/runs/37218464793)
is queued/running with no observed failures so far; its [artifact dry-run](https://github.com/konsultaner/connectanum-dart/actions/runs/37218557969)
passes five builds with publication skipped. All five downloaded bundles pass
checksum/manifest and exact source/workflow provenance verification under
`/tmp/connectanum-flatbuffers-c37-platform-artifact-proof.json`. Its Apple Silicon
production library passes 201 VM native/Session cases and the standalone
108-byte/three-segment construction consumer using an exact c37 source snapshot:
`/tmp/connectanum-flatbuffers-c37-artifact-consumer-completed-audit.json`.
The four test-oracle exports are absent with actual ffi-test positive controls;
typed consume is present and the new inspection export is absent, as expected for
c37. Other four binaries are verified but not executed. Hosted browser coverage
passes 4,568 core and 2,791 client cases (20 native skips), with uploaded LCOV
independently recomputed at 96.160%/96.354% under unchanged floors:
`/tmp/connectanum-flatbuffers-c37-hosted-browser-coverage-completed-audit.json`.
Hosted GuardMalloc passes 57 cases and five failure controls. The PR merge
checkout has c37 as its parent; all 138 native/schema inputs match c37, and the
generated lock plus loader/count/log hashes pass audit:
`/tmp/connectanum-flatbuffers-c37-hosted-guardmalloc-completed-audit.json`.
Its recorded executable hash cannot be independently rehashed because the
executable is not uploaded. Remaining CI jobs are pending; these results do not
accept the new inspection repair.

Before deferred Session receive integration, a real eight-case regression proves
that typed native decryption with null Dart arguments invokes a key policy before
rejecting empty ciphertext on all four serializers and both ciphers. Report:
`/tmp/connectanum-flatbuffers-native-anchor-preflight-repro.json`. The first test
attempt had an invalid exception type; that compilation failure is not the repro.
The verified repair adds optional non-consuming native single-binary
length inspection, validating canonical JSON base64 without decoding and using
the existing borrowed binary readers. Typed provider preflight checks native
shape/minimum/64 MiB limit before policy. Older ABI safely materializes instead.
Focused native/fallback cases cover malformed shapes, keyword containers, length
boundaries and released/cached owners; updated native inspection tests pass.
An initial test assumed the existing FlatBuffers fixture was segmented; the
fixture is contiguous. That failed assertion remains failed evidence, and a
separate actual segmented-frame case verifies inspection does not flatten it.
Focused new-library checks pass 224 VM cases (143 runtime, 25 providers and 56
Session). The older ABI independently passes the same 143 runtime cases, with
the capability probe observing inspection absent and typed consume present.
All 1,453 product bytes, both library hashes and every log/count pass audit:
`/tmp/connectanum-flatbuffers-native-inspection-focused-completed-audit.json`.
A separate eight-case fail-first regression caught skipped length checks on the
candidate's authenticated cache; reconstructed ciphertext lengths now preserve
both bounds without exporting wire bytes. GuardMalloc passes 58 cases, with all
139 source hashes, executable, loader/count/log and cleanup evidence audited:
`/tmp/connectanum-flatbuffers-native-inspection-guardmalloc-completed-audit.json`.
Fresh canonical `bin/test-fast` and `bin/verify` both pass on 1,453-file snapshot
`508a2c0cbe7142250df7df1100e5b3fe0d63f04ffaf0bfea7c98ba566177694c`.
All product/native/log/history hashes, all 139 GuardMalloc native/dependency
inputs and the independently built memory executable still match:
`/tmp/connectanum-flatbuffers-native-inspection-canonical-completed-audit.json`.
Native VM cases run without unavailable-library skips. Chrome WASM passes 4,558
core and 2,800 client cases, with 20 explicitly verified native-only client skips.
The initial audit mistakenly rejected those browser skips; its corrected scope
checks VM availability and every browser skip separately. The verification runs
themselves passed. Canonical scripts rebuild the standard ffi-test library to
SHA256 `334d3449af8b18723b1f83c09bff080e4256b6c2c05b076a0afc23df9d8dfccf`;
the prior 9884a143 library remains preserved independently for compatibility checks.
Companion advice and verified dispositions are recorded under
`/tmp/connectanum-flatbuffers-native-inspection-companion-dispositions.json`.
Exact-head hosted checks and new production artifacts remain pending. Existing
core mutation evidence applies to unchanged core source; this repair changes
native IO only.
The pushed checkpoint's earlier 300-mutation browser wrapper cache discrepancy
remains explicitly retained. Choose runtime decryption before opaque exports.
Merely setting deferred mode in
the transport would still export through its `incoming.message` getter. Routing
metadata details already use a temporary export/copy with synchronous owner free;
they do not themselves leave a shared bulk payload owner alive. Source audit:
`/tmp/connectanum-flatbuffers-session-routing-metadata-owner-audit.json`. Existing
immutable ciphertext and forwarding semantics must stay valid. Session defaulting
previously invoked a key policy before underlying typed preflight; c37c04ee
reproduces and fixes that wrapper ordering. Initial source audit:
`/tmp/connectanum-flatbuffers-session-native-crypto-capability-audit.json`.

The current worktree adds optional owned-buffer E2EE ABI v1 and the public native
typed `packNativeTypedPayload` path. It borrows frozen native plaintext in Rust,
returns independent native-owned ciphertext, and composes it as an opaque
FlatBuffers frame. Rust pointer oracles and Dart ownership/decryption tests cover
both ciphers; the ordinary Dart-value E2EE path still copies across FFI. This
advances issues #96 and #101 but does not complete their broader acceptance.
Fresh `bin/test-fast` and `bin/verify` both pass at exit 0 on this worktree on
2026-10-05. This is local verification; exact-head hosted checks remain pending.
Complete external session conformance, malformed-input/fuzz and ownership CI,
supported-platform consumers and adapter/release docs.
The source-backed [native-owned crypto preparation](research/2026-10-04-native-owned-crypto-boundary.md)
records verified API boundaries and corrected local test/architecture advice;
it introduces no new crypto API. [Benchmark preparation](research/2026-10-04-flatbuffers-benchmark-construction.md)
records the current Dart fragment factory and missing echoed RPC identity check.
Declare representative performance/copy budgets before controlled measurement.
No throughput parity is established. The pinned Autobahn object serializer is not
a functioning live peer; independent generated Python codec fixtures do not prove
full session conformance. Audit every issue before closing this milestone.

## Research and preserved history

[Binding](flatbuffers_binding.md), [PPT/E2EE](e2ee_ppt_research.md) and
[ownership](native_buffer_ownership.md) record the contracts.
[Prior state](history/2026-10-04-project-state-before-flatbuffers-consolidation.md)
and [implementation journal](history/2026-10-04-flatbuffers-implementation-journal.md)
preserve earlier notes byte-for-byte. Their older entries are historical checkpoints.
