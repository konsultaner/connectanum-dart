# FlatBuffers and zero-copy native buffers

Status: active. Started: 2026-10-03.
Milestone: [GitHub milestone 1](https://github.com/konsultaner/connectanum-dart/milestone/1).
Branch: `codex/flatbuffers-zero-copy` in the managed FlatBuffers worktree.
Baseline: `54eafc5fb675886a04d390f069714c69de2aaac0`;
released master `3bac4cf5` is integrated. Preceding checkpoint: `9b28c61c`.
Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

Current follow-up (2026-10-07): native external-buffer allocation provenance.
Six fail-first regressions show that matching bounds allowed a foreign anchor
to redirect a native read, including an incorrect SHA-256 digest. The resolver
now verifies backing-buffer equality and retains that buffer with its anchor.
The final 20-case suite passes without skips on macOS and Linux arm64, including
equal-content foreign-allocation controls and actual GC retention/collection.
The malloc finalizer and existing copying fallback are unchanged. Fresh quiet
`bin/verify` passes at exit 0, including Rust/VM/consumers, 1,563 benchmark,
4,958 router, 4,751 browser core and 2,829 browser client tests with the unchanged
20 native-only skips. Evidence: `/tmp/connectanum-external-provenance-verify.{log,exit}`.
No total-copy or performance acceptance follows. Both preceding `a9907161`
hosted CI runs now pass all 41 jobs: [push](https://github.com/konsultaner/connectanum-dart/actions/runs/37523093121)
and [PR](https://github.com/konsultaner/connectanum-dart/actions/runs/37523101879).
The publication hold is released; resulting-head hosted checks remain pending.
Master `3bac4cf5` was fetched from both remotes and is already integrated;
`git merge github/master` reports Already up to date. Research: [allocation
provenance](../research/2026-10-07-native-external-buffer-provenance.md).

Current diagnostic follow-up (2026-10-07): real Dart SDK backpressure.
The four 16 MiB full/read-only/partial/read-only-partial cases require genuine
EAGAIN, pending flush, positive writes after receiver resumption and exact
received/accepted bytes. Full views retain allocation identity; partial views
use SDK copies. The exact updated Linux CI step passes all three probes and its
absence control; source hashes match. Root analysis and the new tool's explicit
missing-interposer rejection pass. Fresh quiet `bin/verify` passes at exit 0,
including all 1,563 benchmark, 4,958 router, 4,751 core Chrome/Dart2Wasm and
2,829 client browser cases with 20 declared native-only skips. Evidence:
`/tmp/connectanum-sdk-backpressure-verify.{log,exit}`. Final sequential
`bin/test-fast` also passes at exit 0, including all 1,563 benchmark cases and
the unchanged readiness regression. Evidence:
`/tmp/connectanum-sdk-backpressure-final-fast.{log,exit}`. The preceding local
commit `d4d91317` passed both canonical commands and independent interop. Its push is held while preceding
`a9907161` CI's MCP mutation gates remain active. No total-copy, TLS or parity
acceptance follows from this pointer diagnostic. Research: [backpressure](../research/2026-10-07-dart-sdk-backpressure.md).

Current follow-up: Dart FlatBuffers fragments and one-copy small RawSocket frames.
The ordinary fragment API preserves encoded CBOR args/kwargs and opaque body
views through valid forward-offset vector layout. Normal serialization and the
wire schema are unchanged. Two public regressions fail before the writer; all
61 focused core cases pass across seven payload-bearing message families.
Three small-frame copy regressions fail before the shared transport repair;
all 43 RawSocket tests then pass, including six codec/size copy/identity cases.
The Linux developer probe now exercises real negotiated RawSocket PPT traffic,
and CI uploads it beside the SDK boundary probe. The source audit corrects the
forced short-write/EINTR boundary to the native SocketBase::Write loop; it does
not establish Dart-level EAGAIN resumption. Partial SDK views, total SDK/TLS/
crypto copies and the full strict parity campaign remain unfinished. Research:
[segmented Dart sending](../research/2026-10-06-dart-flatbuffers-segmented-send.md).
The final 36-case real Linux PPT pointer probe passes with exact source hashes;
Rust/Python readers accept contiguous and segmented output for all 25 messages.
The first canonical fast attempt failed the new-test inventory. All four
VM/browser inventories and their shared suite now include that test; all 80
workflow regressions pass with unchanged thresholds. The next fast attempt
failed the existing HELLO/GOODBYE rejection tests because controls used the
fragment writer. Controls and absent-vector messages now return null to retain
the normal serialize path. All 22 unchanged negotiation/rejection tests and
61 core fragment cases pass. The exact Linux CI step also passes both probes
and its missing-interposer control with final source hashes. A fresh canonical
fast run passes the changed paths and then hits the unchanged two-second
worker exit-before-READY deadline in the 1,563-case benchmark suite. Five
isolated repeats pass without code/deadline changes. The failed full fast log
is retained; timing sensitivity is not accepted as proof of a clean suite.
Fresh quiet `bin/verify` now passes at exit 0, including Rust, VM,
consumer/live checks, all 1,563 benchmark and 4,958 router cases, 4,751 core
Chrome/Dart2Wasm cases and 2,829 client browser cases (20 declared native-only
skips). The unchanged worker-readiness case passes in the complete benchmark
suite without deadline or assertion changes. The final independent interop run
also passes after the control fallback repair: 33 upstream fixtures, 42 extended
fixtures and all 25 public messages in contiguous and segmented Dart output.
Fresh sequential final `bin/test-fast` also passes at exit 0, including all
1,563 benchmark cases and the unchanged readiness regression. Evidence:
`/tmp/connectanum-flatbuffers-fragments-verify.{log,exit}`,
`/tmp/connectanum-flatbuffers-fragments-final-interop.{log,exit}` and
`/tmp/connectanum-flatbuffers-fragments-final-fast.{log,exit}`. Earlier failed
logs remain failed evidence. The focused local GLM selector review completed without a concrete
defect; two Qwen attempts reached output limits and are not review evidence.
At preceding published checkpoint `a9907161`, hosted push Full Verify and VM
Coverage pass; PR Full Verify also completes with no observed failure. Both
current CI runs remain live for the MCP mutation gate. Do not push another
checkpoint while those checks are still running. Preceding `b8096fd6` CI runs
were cancelled by that newer push, so their successful individual jobs do not
constitute complete hosted acceptance. This follow-up is committed locally as
`d4d91317`; publication awaits the existing hosted mutation run. Full performance
and remaining milestone acceptance stay open.

Preceding follow-up: native PPT body reuse with empty outer CBOR/MessagePack
keyword maps. The preceding implementation rejected these valid WAMP maps.
Fresh baseline fast checks pass; four new mixed-direction regressions fail
before the repair. All 26 segmented tests now pass, including 810 additional
body/header/direction/route combinations and native input parsing of every
tested header form. They verify body identity, empty-body producer lifetime,
metadata and final fan-out release. Malformed/nonempty maps and invalid
FlatBuffers mixed vectors retain fallback. Research:
[empty PPT keywords](../research/2026-10-06-native-empty-ppt-keywords.md).
GuardMalloc passes 87 observed ownership cases with all 141 native/schema
inputs unchanged. Final `bin/test-fast` passes. Fresh `bin/verify` passes at exit 0, including Rust, VM, consumer/live
checks, 1,563 benchmark, 4,958 router, 4,690 core Chrome/Dart2Wasm and 2,829
client browser cases (20 declared native-only skips). Final native input hashes
are unchanged. Evidence: `/tmp/connectanum-empty-ppt-kwargs-verify.{log,exit}`.
Local Qwen review completed; source and regression evidence disprove its
logic-inversion, indefinite-map and wrong-kind hypotheses.

Production checkpoint `b8096fd6` [Native Artifacts 37515940631](https://github.com/konsultaner/connectanum-dart/actions/runs/37515940631)
passes all five builds and its preview. Fifteen attestations, thirty assets,
archive/library checksums and exact rendered notes verify. Fresh commit-pinned
Apple Silicon and Linux arm64 production consumers each pass all four serializers,
native construction, ten segment cases, sixteen live owned-PPT cases and 104
public mixed-PPT cases. Their source archives match. Both production libraries
exclude test oracles, with an eighteen-symbol ffi-test positive control on macOS.
The other three platforms have build/provenance evidence only. This is runtime
correctness, not performance acceptance. Evidence:
`/tmp/connectanum-b8096fd6-platform-provenance.json`,
`/tmp/connectanum-b8096fd6-preview-proof.json`,
`/tmp/connectanum-b8096fd6-production-consumers-proof.json` and
`/tmp/connectanum-b8096fd6-linux-production-consumers-proof.json`.
Hosted FlatBuffers Binding and GuardMalloc pass in PR run 37515806715. The
RawSocket/WebSocket independent-peer inputs match `b8096fd6`; the memory report
passes 87 cases/eight groups, with all 140 tracked sources matching and the
generated lock hash verified. Its synthetic PR merge has `b8096fd6` as a parent.
Uploaded group-log hashes match. Hosted PR Fast Checks also passes. Remaining
required hosted CI is still running without an observed failure. Evidence:
`/tmp/connectanum-b8096fd6-hosted-conformance-proof.json`.

Independent [SDK copy research](../research/2026-10-06-dart-sdk-copy-boundaries.md)
identifies conditional partial-view copies before socket writes and binary
masking/ring-buffer copies. A 15-case ordinary serializer diagnostic shows
all five FlatBuffers frames use partial backing views, unlike the ten
CBOR/MessagePack frames. The checked-in Linux pointer probe now confirms the full/partial-view boundary
through actual libc writes and retries. Internal buffering, TLS and total-copy
volumes remain unmeasured. This is not parity or a complete-copy claim.
Complete hosted acceptance and all unresolved milestone criteria remain pending.

Preceding follow-up: native opaque-PPT body reuse between the three binary codecs.
The nine fail-first regressions report six mixed eligibility failures and three
homogeneous echo metadata failures, exit 101. The passing `7d7fab90` canonical
checks are the baseline. Producer lifetime, empty bodies, routing metadata and
fallback rejection must be verified before publishing this change; whole-path
copy accounting and benchmark parity remain unresolved. All 22 Rust segmented
cases and 109 public live/eligibility cases now pass. The latter exposed and
reproduced 28 explicit `wamp`-scheme RPC fallbacks before removing those Dart
exclusions; custom-detail and other existing routing guards remain intact.
The predecessor's five-platform dry run, fifteen attestations and thirty preview
assets verify at `7d7fab90`; the body bridge's resulting-head artifacts and
hosted acceptance remain pending. Current `bin/test-fast` passes at
exit 0; GuardMalloc observes and passes 83 ownership cases, including all 22
segmented-forwarding tests. Final implementation/test hashes are unchanged.
The first full verification fails on an old worker-session assertion excluding
encrypted native forwarding. The repaired test preserves all ciphertext checks
in a fallback control and adds a native transfer/no-decoding control. Both and
all 204 worker/live cases pass. No product code changed for this test repair.
Fresh root analysis and corrected full `bin/verify` pass at exit 0, including
Rust, VM, consumer/live checks, 1,563 benchmark, 4,958 router, 4,690 core
Chrome/Dart2Wasm and 2,829 client browser cases (20 declared native-only skips).
Evidence: `/tmp/connectanum-native-ppt-routing-verify-fixed.{log,exit}`.
The fast run precedes the test-only worker repair; full verification covers it.
All six recorded final verification inputs and 141 GuardMalloc native/schema
inputs remain unchanged.
Hosted VM coverage on `7d7fab90` passes its library gates, then hits the explicit
45-minute job maximum during packaging formatting. Only this aggregate budget
becomes 90 minutes. All other workflow bytes, collection scripts and coverage
policy are unchanged; all 80 existing verification-tool checks pass. Hosted
completion remains pending. Evidence:
`/tmp/connectanum-native-ppt-routing-coverage-budget-proof.json`.
Research: [GitHub job timeout behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).
Evidence:
`/tmp/connectanum-native-ppt-routing-before.{log,exit}`. Freshly fetched master
remains `3bac4cf5`, already integrated; no merge is needed.

The preceding follow-up repairs a root-analyzer regression at `8df5c9b3`.
Fresh `bin/test-fast` fails at exit 3 on four `undefined_named_parameter`
errors: the new benchmark test helper passes VM-only `runtime:` parameters
through the public conditional-export API. The helper now uses the public
`libraryPath:` parameter; its prior singleton initialization keeps the metrics
collector and provider on the same native runtime. Production code is unchanged.
Root `dart analyze` and all 28 focused counter cases pass at exit 0. The corrected
`bin/test-fast` and fresh `bin/verify` pass at exit 0, including Rust, VM,
consumer/live WAMP and browser suites (20 declared native-only client skips).
Final Dart/YAML input hashes are unchanged. Hosted acceptance remains pending.
The earlier full `bin/verify` pass did not include root analysis and therefore
did not detect this regression. Evidence:
`/tmp/connectanum-e2ee-pipeline-baseline-fast.{log,exit}` and
`/tmp/connectanum-e2ee-public-helper-{analyze,focused,fast,verify}.{log,exit}`.

The CI workflow now groups automated `codex/` branch runs by workflow, event and
ref, cancelling superseded runs within each group. Master, tags, manual dispatch
and other branches use unique run IDs, avoiding cancellation of pending runs as
well as active runs. Push and PR groups remain separate. Thirteen event/ref
boundary scenarios plus workflow separation pass with the official
`@actions/expressions` evaluator 0.3.61; all 80 verification-tool cases pass.
Every existing job body is byte-identical, including commands, gates and deadlines.
The ownership guide replaces its stale fixed case count and temporary report path
with the reproducible runner command and per-run source/count evidence.
Research: [GitHub concurrency semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)
and [official expression evaluator](https://github.com/actions/languageservices/tree/main/expressions).
Hosted cancellation behavior remains unverified. Local GLM judgment and Qwen
review completed; the evaluator/source checks resolve their inaccurate PR-ref
details. Initial bounded companion requests exhausted output limits and are not
completed reviews. Evidence: `/tmp/connectanum-ci-concurrency-evaluation.json`,
`/tmp/connectanum-ci-concurrency-job-proof.json` and
`/tmp/connectanum-ci-concurrency-tool-tests.log`.

[Native Artifacts 37480119838](https://github.com/konsultaner/connectanum-dart/actions/runs/37480119838)
passes all five builds and its dry-run preview at `8df5c9b3`. All fifteen
source/branch/workflow attestations verify; thirty preview assets match and the
notes exactly match the renderer. A fresh pinned-source standalone consumer
passes all four serializers and the public native API with the Apple Silicon
production library; ten shared-segment and sixteen live owned-PPT cases also
pass. Direct scalar input/growth copies are zero and independently owned
read-only views survive disposal. Production exports contain no `ct_test_*`
oracles; the ffi-test positive control contains eighteen. Other platforms have
build/provenance evidence only. No release is published. Evidence: `/tmp/connectanum-8df5c9b3-platform-provenance.json` and
`/tmp/connectanum-8df5c9b3-preview-proof.json` and
`/tmp/connectanum-8df5c9b3-production-consumers-proof.json`.

The preceding follow-up measures native-provider ciphertext byte-list coercion.
The fail-first matrix passes four Uint8List decrypt cases and fails all eight
ordinary-list cases because their conversions are omitted from the lower bound.
The runtime now counts that isolate-local boundary separately from FFI and native
staging, without changing the native ABI or wire representation. All 28 focused
cases pass, including both ciphers/profiles, immutable bounded subviews, exact
prefix counts on typed rejection, absent staging ABI and counter reset/deltas.
Failed legacy CBOR coercion remains explicitly excluded. The total E2EE pipeline
stays `not_measured`; no parity or complete-copy claim is added.
Baseline `bin/test-fast` passes at exit 0 before this change. All 178 native and
Session provider/profile/key-selection cases pass with the explicit ffi-test
library. Fresh canonical `bin/verify` passes at exit 0, including Rust, VM,
consumers, 1,563 benchmark, 4,935 router, 4,690 core browser and 2,829 client
browser cases (20 declared native-only client skips). The final Dart source/test
hashes are unchanged. Evidence: `/tmp/connectanum-e2ee-wrapper-verify.{log,exit}`.
Earlier focused evidence:
`/tmp/connectanum-e2ee-wrapper-{baseline-fast,regression-before-valid,focused}.{log,exit}`.
The initial regression command used a wrong package-relative path and is not the
fail-first evidence. An initial provider command also named a nonexistent test
and selected a library without the required owned-crypto/staging ABI; its failed
result is retained; the corrected run passes with the explicit ffi-test library.
Evidence: `/tmp/connectanum-e2ee-wrapper-providers-corrected.{log,exit}`.
Hosted push CI `37473576179` on `8feb80c1` now passes WampApp Consumer and
Fast Checks. Complete hosted acceptance remains pending. The superseded PR run
`37464701287`, which failed the old privacy oracle and skipped Full Verify, was
cancelled; its successful older push run and both new-head runs were preserved.


The preceding follow-up repairs WampApp's encrypted-vault privacy-test oracle.
Hosted Consumer job `112272706961` on `62f99ebb` passes 409 cases and fails one
because randomized Base64 ciphertext contains `bob`. The captured envelope has
only public metadata; the bare-string predicate is not a plaintext-leak oracle.
The test now allows only the exact public vault/backup metadata fields and checks
quoted JSON tokens. Production crypto is unchanged. The captured old oracle
fails, the repaired oracle passes, injected plaintext contacts fail, and all 22
vault cases pass. Full `bin/test-wamp-app` passes at exit 0, including VM/JS/Wasm
tests, mutation controls and the web build. Fresh canonical `bin/verify` passes
at exit 0, including Rust, VM, consumers, 1,541 benchmark, 4,935 router, 4,690 core
browser and 2,829 client browser cases (20 declared native-only client skips).
Evidence: `/tmp/connectanum-vault-oracle-verify.{log,exit}`. Current hosted CI
remains unaccepted; original issue criteria stay intact.
The repaired Fast Checks budget is confirmed by its passing hosted job; the
old WampApp privacy assertion still blocks that PR run's downstream checks.

Native Artifacts `37464710421` passes at exact `62f99ebb`, including all five
platform builds and the release preview. All fifteen attestations independently
verify; all thirty assets match and the notes exactly match the repaired renderer.
Its fresh standalone consumer, ten segment cases and sixteen live owned-PPT
cases pass with the production Apple Silicon library. No release is published;
other platforms have build/provenance evidence only. Package dry run passes.
Three superseded CI runs with cancelled Fast Checks were cancelled to free
runners; both resulting-head CI runs remain active. Evidence:
`/tmp/connectanum-62f99ebb-platform-provenance.json` and
`/tmp/connectanum-vault-oracle-control-proof.json`.

The preceding follow-up repairs the separate Fast Checks aggregate job budget
and missing release-preview evidence links. On `5f1afae9`, hosted Fast Checks
passes a live consumer smoke at 20m12.701s and is cancelled 1.937s later at
GitHub's explicit 20-minute ceiling. The aggregate budget becomes 45 minutes;
all commands, test deadlines and gates stay unchanged. All eighty verification
tool checks pass. Two release-note link regressions first fail, then all three
renderer tests pass with commit-pinned repository/server-correct conformance,
benchmark and ownership links. The ownership guide explicitly compares pinned
Dart entity reconstruction with the C producer-thread transaction/lease policy
and measured copy fallback; no ObjectBox dependency is added.
Parity and complete copy coverage stay unaccepted.
Fresh canonical `bin/verify` passes at exit 0, including Rust, VM, consumers,
1,541 benchmark, 4,935 router, 4,690 core browser and 2,829 client browser cases
(20 declared native-only client skips). Evidence:
`/tmp/connectanum-release-readiness-verify.{log,exit}`. Hosted acceptance and the
resulting head's release preview remain pending.

Native Artifacts run `37457831556` passes all five builds and the dry-run release
preview at exact source `5f1afae9`. All fifteen archive/checksum/manifest
attestations independently verify against that source/branch/workflow; checksums
and manifest source fields match. The Apple Silicon production artifact passes
a standalone public consumer, ten shared-segment cases and sixteen live owned
CBOR/MessagePack runner cases. The consumer also round-trips ordinary values
through all four public serializers. Its direct scalar payload has zero input/growth
copies and its derived read-only control view retains independent ownership.
Production exports contain no `ct_test_*` oracle; the ffi-test positive control
contains eighteen. Other platforms have build/provenance evidence only. The
preview has thirty expected assets but lacks conformance/benchmark evidence
links, motivating the renderer repair. No release is published. Fast Checks
cancellation skips Full Verify and VM coverage; binding, browser coverage,
GuardMalloc and WampApp consumers pass. Original acceptance remains open.

The preceding follow-up repairs the hosted Full Verify aggregate job budget.
Its preceding `c3dbc9cb` run reaches browser tests after 40m51s and hits GitHub's
45-minute ceiling while cases still pass. The aggregate budget becomes 90 minutes
to contain the observed preceding work and the existing bounded browser commands.
The annotation/timestamp reproducer, all 80 verification-tool checks and fresh
canonical verification pass. No command deadline or gate changes.

The preceding follow-up implements complete native construction of the benchmark
CBOR/MessagePack PPT fixture on top of pushed `425c9e62`. The baseline suites
finish before production edits; its recording wrapper fails afterward. The
`native_buffer` group previously held only a native body and subsequently
serialized a Dart map. The constructor now writes the same complete PPT bytes
directly in native storage and retains that span. Focused/live tests and all
1,541 Linux benchmark cases pass; fresh full canonical verify and sequential
fast checks both exit 0. Linux
benchmark coverage is 2,981/3,033 lines (98.286%), above the unchanged 98% gate,
and the codec is 122/122 lines. Other packages are unmeasured in this targeted
report; whole-repository coverage is not accepted by it.
The regular serializers are the byte-for-byte reference, including integer and
binary-length boundaries. The single body input copy stays counted, just as in
the FlatBuffers native fixture. No original copy/parity gate is relaxed.

The preceding follow-up adds shared encoded native submission for CBOR and
MessagePack on top of pushed campaign checkpoint `c3dbc9cb`. Frozen buffers stay
owned through queued write/flush; generic lazy owned PPT preserves the exact
allocation and counts small metadata copies. API/version/identity guards retain
compatibility and the FlatBuffers session profile. Native, Dart, live Session,
Linux coverage and GuardMalloc checks pass. Fresh canonical fast/full
verification passes after clearing disposable caches following host filesystem
exhaustion; no failed run is accepted as clean.
Dynamic CBOR/MessagePack native construction, complete copy metrics and primary
parity remain open. The preceding executor's 120-row diagnostic is correctness
evidence, not primary performance acceptance.

The preceding follow-up fixes the benchmark test runtime leak at pushed `1aafa099`.
Hosted Fast Checks failed eight cases after native E2EE factory tests left the
process-wide client runtime running. The Linux reproducer fails six accounting
cases; the factory-test runtime teardown repairs all 39 related cases with no
native skips. All 1,498 full Linux benchmark cases now pass with no native skips.
The fresh repository baseline and full `bin/verify` pass at exit 0, including
Rust, VM, consumers, 1,498 benchmark, 4,935 router, 4,690 core browser and 2,829
client browser cases (20 declared native-only client skips).
The repair is pushed to both remotes as `87688b8c`; exact-head hosted CI remains
in progress. Both package publish dry-runs, binding and GuardMalloc checks pass.

The preceding follow-up builds on pushed `dbeda203` with benchmark metric
validation, VM isolate fallback and coverage repairs. Fresh baseline verification
and 60 focused tests pass on macOS and Linux arm64. Linux benchmark coverage is
98.219% against its unchanged 98% target; full browser coverage passes both gates.
Fresh full `bin/verify` passes at exit 0, including 1,498 benchmark, 4,935 router,
4,690 core browser and 2,829 client browser cases (20 declared native-only client
skips). The unchanged native implementation retains the ordinary-routing
GuardMalloc evidence: 70 cases and all 141 native/dependency inputs matching.
Issues #95–#99 are complete. Hosted VM coverage at `dbeda203` failed at 97.404%
against the unchanged 98% benchmark gate; one browser job timed out while the
same-head PR browser job passed. Required hosted acceptance and publish dry-runs
remain pending. Copy counters and the evaluator provide partial attribution and
fail-closed gates; no paired performance campaign or parity result exists.

## Objective and scope

Complete all ten milestone issues. FlatBuffers is a regular serializer beside
JSON, MessagePack and CBOR, with interoperable Dart/Rust codecs, native-owned
construction, generic external-buffer leases, lazy routing, PPT/E2EE and measured
performance at least matching the better binary baseline on declared workloads.
ObjectBox integration itself belongs to a separate adapter package.

The primary checkout is independent and remains untouched. Feature commits,
pushes and draft PR updates are authorized. The user requested merging current
master into this working branch on 2026-10-06; both remotes are already integrated.
Release publication, version bumps and merging the feature into master remain
outside the authorized scope.

## Issue acceptance status

- [x] [#95](https://github.com/konsultaner/connectanum-dart/issues/95): pinned binding, reproducible generation, metadata/schema compatibility.
- [x] [#96](https://github.com/konsultaner/connectanum-dart/issues/96): native builders, freeze/retain/transfer, native inputs throughout submission.
- [x] [#97](https://github.com/konsultaner/connectanum-dart/issues/97): generic external leases, producer-thread release, real send completion.
- [x] [#98](https://github.com/konsultaner/connectanum-dart/issues/98): complete public Dart serializer, factories and verified lazy payload behavior.
- [x] [#99](https://github.com/konsultaner/connectanum-dart/issues/99): native Rust codec, transport negotiation and supported profile guards.
- [ ] [#100](https://github.com/konsultaner/connectanum-dart/issues/100): homogeneous/mixed routing, delayed/progressive/error flows and lifetime preservation.
- [ ] [#101](https://github.com/konsultaner/connectanum-dart/issues/101): PPT and explicit typed E2EE profile; unchanged CBOR behavior and unsupported file handling.
- [ ] [#102](https://github.com/konsultaner/connectanum-dart/issues/102): external conformance, malformed-input/fuzz, memory/ownership CI.
- [ ] [#103](https://github.com/konsultaner/connectanum-dart/issues/103): representative throughput/latency/memory/copy gates and repeatable hosted evidence.
- [ ] [#104](https://github.com/konsultaner/connectanum-dart/issues/104): platform/consumer readiness and release/adapter documentation.

Implementation exists for many of these paths; unchecked items reflect remaining
acceptance and evidence, not a claim that every feature is unimplemented.

## Next work

Mixed binary PPT body reuse and empty outer-map support are implemented and
pass local canonical verification at `b8096fd6`. Its signed artifact dry run and
production consumers now pass. A developer-only socket pointer probe independently
confirms the pinned SDK boundary and retries; fresh fast/full verification passes.
Required hosted CI and complete copy instrumentation remain the next blockers.
Preserve every original milestone criterion.

1. Inspect required hosted CI for the resulting feature commit; fix any failure
   before continuing feature or benchmark work.
2. Complete #100/#101 acceptance, including crypto/serializer/transcode copies
   beyond the measured native staging sites and routing/PPT/E2EE lifetime evidence.
3. Complete #102/#104 hosted conformance, memory, artifact-consumer and release
   dry-run evidence without treating earlier commits as current-head acceptance.
4. Finish #103 measurement coverage, the paired campaign runner and all declared
   performance rows. SDK/TLS/transcode copy gaps and absent campaign results
   remain blockers; do not weaken the parity or copy gates.

## Hosted Full Verify aggregate budget (2026-10-06)

- [x] Inspect job `112200071473` in run `37437589411`, including annotations and
  the actual completed job log while the enclosing mutation run remains live.
  GitHub reports its 45-minute ceiling; core Dart2Js cases pass until 0.665s
  before cancellation. No stalled test is established by this evidence.
- [x] Calculate the observed pre-browser window (40m51s), preserving the existing
  900-second core and two 420-second client command allowances. The combined
  window is 69.861 minutes, exceeding the previous aggregate budget.
- [x] Change only Full Verify's aggregate job limit to 90 minutes. Retain all
  suites, LLVM verification, command/per-test bounds, thresholds and required jobs.
- [x] Pass all 80 verification-tool regression cases. The local debug companion's
  speculative hang/leak hypotheses are not established: timestamped passing
  cases continue immediately before GitHub's explicit deadline cancellation.
- [x] Finish fresh canonical verification before publishing this repair:
  `bin/verify` exits 0, including Rust, VM, consumers, 1,541 benchmark, 4,935
  router, 4,690 core browser and 2,829 client browser cases (20 declared
  native-only client skips). Product inputs remain unchanged from the preceding
  sequential fast check; only the CI budget and its documentation change.
- [ ] Inspect exact-head hosted verification and signed platform artifacts;
  validate the production consumer and release preview without publishing a release.

Evidence: `/tmp/connectanum-full-verify-budget-repro.json`,
`/tmp/connectanum-c3-full-verify-hosted.log`,
`/tmp/connectanum-c3-full-verify-{job,annotations}.json`,
`/tmp/connectanum-full-verify-budget-tools.{log,exit}` and
`/tmp/connectanum-c3-full-verify-timeout-debug.txt`, plus
`/tmp/connectanum-full-verify-budget-canonical.{log,exit}`.

## Complete native benchmark PPT construction (2026-10-06)

- [x] Finish the fresh baseline without changing production sources. All suite
  cases finish without test failure; the outer exit-recording command then
  fails because `status` is a reserved zsh variable. Do not claim that wrapper
  exited 0 or invent its missing exit file. The preceding pushed checkpoint's
  canonical fast/full results remain valid; final checks use `task_exit`.
- [x] Reproduce missing exact owned PPT spans for CBOR/MessagePack
  `native_buffer` construction with the existing recording Session tests.
- [x] Build complete fixture PPT directly in native storage, preserving the
  regular wire shape, uint32 identities and binary body, with one counted body
  input copy and no grow/concatenate copy.
- [x] Preserve lazy application decoding, exact owner identity and release
  on successful or rejected Session sends.
- [x] Compare byte-for-byte with the regular serializers at all relevant integer
  and binary-length boundaries and validate decoded application identity/body.
- [x] Exercise both owned construction groups over native RawSocket/WebSocket
  RPC/pub-sub, including FlatBuffers envelope/other PPT fallback semantics.
- [x] Confirm existing encryption coverage in the complete benchmark suite:
  Dart/native typed FlatBuffers with both ciphers, native mixed-serializer
  encrypted pub/sub, and native CBOR encrypted file transfer all pass on Linux.
  The new CBOR/MessagePack native constructors use the unencrypted custom typed
  benchmark scheme. Existing encrypted CBOR uses its ordinary value path;
  MessagePack is not an E2EE profile. No new encrypted constructor coverage or
  complete crypto copy attribution is claimed.
- [x] Include the codec/owner tests in the workload mutation inputs and suite.
  All 596 focused/aggregate cases and 46 live matrix cases pass. All 93 runner
  regression cases pass with one declared skip and unchanged thresholds.
  The prototype and actual-diff reviews raise source-disproved concerns:
  frozen builder disposal is a no-op, MessagePack binary headers never have
  width 1, and FlatBuffers payloads select their own decoder before the dynamic
  decoder branch. Fixed internal keys are ASCII and body() returns the validated
  requested length. No concrete companion blocker remains.
  The first canonical runs fail the stale exact mutation-inventory assertion.
  Its source, imported-test and fixture sets now include the constructor and its
  tests; exact equality and all thresholds remain enforced. Fresh canonical
  verify passes after that repair.
  The repaired fast run fails one existing close-after-READY worker case at the
  unchanged two-second readiness timeout while fast/full checks overlap. The
  unchanged case then passes five focused repeats and the full verify run's
  1,541-case benchmark suite. Do not accept the failed fast run as green or
  infer a proven root cause. Fresh sequential `bin/test-fast` now exits 0,
  with the unchanged case and all 1,541 benchmark cases passing.
  Full `bin/verify` exits 0, including Rust, VM, consumers, 1,541 benchmark,
  4,935 router, 4,690 core browser and 2,829 client browser cases (20 declared
  native-only client skips). Evidence:
  `/tmp/connectanum-native-construction-verify-final.{log,exit}`,
  `/tmp/connectanum-native-construction-startup-repeat.{log,exit}` and
  `/tmp/connectanum-native-construction-fast-sequential.{log,exit}`.
- [x] Complete focused review, fresh fast/full verification and unchanged Linux
  benchmark coverage before publishing the next checkpoint.
- [ ] Obtain exact-head hosted acceptance. Complete SDK/TLS/transcode/E2EE copy
  instrumentation, resource budgets and primary parity under the original gates.

The constructor is specific to the existing benchmark application model; it
does not replace the public CBOR/MessagePack serializers. Field names, PPT map
structure and map ordering follow the checked-in serializers. Integer and byte
string headers follow [RFC 8949 section 3](https://www.rfc-editor.org/rfc/rfc8949.html#section-3)
and the [MessagePack specification](https://github.com/msgpack/msgpack/blob/master/spec.md).
Only uint32 identities and the existing 64 MiB fixture body limit are supported.

Evidence: `/tmp/connectanum-native-construction-{owner-repro,owner-fixed,prototype,focused,live,inventory}.{log,exit}`,
`/tmp/connectanum-native-construction-{context,test-ideas-narrow,review}.txt`,
`/tmp/connectanum-native-construction-linux-coverage.{log,exit}`,
`/tmp/connectanum-native-construction-linux-{lcov.info,summary.json}`.
The coverage checker exits 1 for 204 findings in unmeasured other packages and
scopes; there are no benchmark findings. The fixture overlays these Dart/tool
changes on the existing Linux clone and retains the unchanged native binary;
it is explicitly dirty functional evidence, not a clean-head timing campaign.
The Linux daemon was unavailable; starting the existing Docker service/container
restores the retained fixture. Its native frame source matches the host's
unchanged source hash `519a466e30580aab98db61b920d0288d6e82ed6bc85b360768f6c22ef85f899d`.
Eight changed Dart/tool inputs are overlaid; it remains explicitly a dirty
functional/coverage fixture, not controlled timing or clean-head acceptance.

## Shared encoded native submission (2026-10-06)

- [x] Reproduce the missing shared ABI and two missing CBOR/MessagePack exact
  owner anchors before implementing their paths.
- [x] Add optional owned-segment ABI v1, retaining 1–64 frozen handles with no
  input consumption on success/rejection and no payload concatenation/copy.
- [x] Keep every empty producer owner alive through a nonempty segment anchor;
  verify exact allocation pointers and producer-thread final release.
- [x] Add Dart capability probes, tracked/untracked submission and a Finalizable
  input holder; preserve the FlatBuffers session-profile guard.
- [x] Add generic lazy owned PPT and eligible CBOR/MessagePack CALL/PUBLISH
  submission; count only newly serialized metadata copies at this boundary.
- [x] Reject forged/replaced owner views and retain regular serializer semantics.
- [x] Use the owned anchor for CBOR/MessagePack benchmark pre-encoded spans.
- [x] Pass 18 native ownership/network cases, 10 new Dart API/transport cases,
  existing FlatBuffers frame cases and all 131 focused benchmark/live cases.
  All 17 combined new API/existing frame cases also pass on Linux arm64.
- [x] Pass all 73 GuardMalloc ownership cases; 141 native/dependency/schema
  inputs match before/after the instrumented checks.
- [x] Complete a focused companion review. Its Finalizable-registration concern
  is disproved by the SDK marker-interface contract: the local holder keeps the
  entire list/handle graph reachable until synchronous native retention returns.
  Queued writes then own independent Frozen references. GLM judge attempts
  reach their deadlines without a substantive response, so no judge verdict is
  claimed.
- [x] Repair mutation inventories for the new part and test: all 92 runner
  regression cases pass, with their single declared skip and unchanged gates.
- [x] Pass all 281 native FFI cases after the test's runtime-rejection path uses
  the global runtime-test lock; memory instrumentation is refreshed afterward.
- [x] Add/pass eight live native Session RPC/pub-sub cases across CBOR/MessagePack
  and RawSocket/WebSocket on macOS and Linux. Use the existing worker process
  for native WebSocket handshakes so the router's Dart isolate can serve them.
- [x] Pass all 1,504 original-plus-owner-anchor Linux benchmark cases and the
  eight added Session cases, with no native skips. Targeted coverage including
  the existing child-process build probes is 2,926/2,978 lines (98.254%), above
  the unchanged 98% gate with no benchmark-specific finding. The first manual
  collection omitted the existing child-coverage environment variable and was
  rejected at 97.851%; no source fix or relaxed threshold is involved.
- [x] Pass fresh canonical fast/full verification. The first runs fail on host
  filesystem exhaustion, during browser compilation and benchmark temporary
  directory creation. Clear only this worktree's disposable Rust incremental
  caches (about 6 GiB), retaining release libraries, binaries and all evidence;
  rerun both commands successfully. Full verification includes Rust, VM,
  consumers, 1,512 benchmark, 4,935 router, 4,690 core browser and 2,829 client
  browser cases (20 declared native-only skips). Do not accept the failed runs.
- [x] Complete the final source/contract review and prepare the checkpoint for
  publication to both remotes and the existing draft PR.
- [ ] Obtain exact-head hosted acceptance after publishing the checkpoint.
- [ ] Complete dynamic CBOR/MessagePack native construction, full SDK/TLS/
  transcode copy metrics, primary timing and parity under unchanged #103 gates.

Evidence: `/tmp/connectanum-shared-codec-{rust-tests,dart-final-tests,bench-tests,linux-client-tests}.{log,exit}`,
`/tmp/connectanum-shared-codec-guardmalloc-final/report.json` and
`/tmp/connectanum-shared-codec-review-final.txt`,
`/tmp/connectanum-shared-codec-{fast,verify}-recovered.{log,exit}` and
`/tmp/connectanum-shared-codec-linux-bench-{lcov.info,summary.json}`.
The first attempted fresh baseline overlapped implementation and caught a
transient Dart switch-type compilation error introduced in this follow-up. It
was repaired before the focused suites; that attempt is not a passing baseline.
A subsequent check also detected missing mutation-inventory registrations;
those sources/tests/support files are now included and all 92 checks pass.
Fresh `bin/test-fast` and `bin/verify` pass at exit 0. No issue is closed or primary
performance claim accepted.

## Campaign executor (2026-10-06)

- [x] Implement all 48 primary cases and deterministic balanced codec schedules,
  retaining one driver/worker through warmup and measured passes.
- [x] Stream flushed JSONL without rebuilding aggregate report history.
- [x] Preserve partial/cancelled evidence and verify process-group cleanup.
- [x] Reject busy hosts, changed inputs, incomplete execution and diagnostics
  as primary acceptance; keep the checked-in numeric policy unchanged.
- [x] Retain actual WAMP configuration and reject codec/profile misattribution
  and repeated primary matrix dimensions. Fail-first regressions are preserved.
- [x] Run focused Python, Rust and benchmark-router configuration checks.
- [x] Preserve the first interrupted Linux diagnostic: 31 distinct client PIDs
  exposed that helpers recycled after every row. Add explicit successful RPC/
  pub-sub reuse and stable client/server PID checks; preserve default, failed and
  cancellation-workload recycling and test close/recovery lifetimes.
- [x] Exercise real Linux codec/transport/TLS/construction rows and inspect
  actual process metrics, raw reports and teardown.
- [x] Complete three warmup and seven measured passes for four paired cases:
  40 reports per codec, one client PID, one server PID, unchanged inputs,
  exact raw/per-pass JSONL equality and driver exit 0. The short diagnostic
  comparison fails at exit 1 with 370 findings; no primary acceptance is claimed.
- [x] Pass all 1,502 Linux benchmark cases with no native skips. Targeted library
  coverage passes the unchanged 98% gate at 2,925/2,979 lines (98.187%) with no
  benchmark-specific policy finding; the full repository report remains separate.
- [x] Pass full `bin/verify`, including all VM, consumer, benchmark, router and
  browser suites. Fresh Rust benchmark tests cover the final metadata alias fix.
- [x] Review the critical lifecycle/report guards and verify companion concerns
  against the actual sequential driver, input hashes and idempotent sampler.
- [x] Commit and push the campaign follow-up as `c3dbc9cb`; exact-head hosted
  checks remain pending.
- [ ] Complete copy coverage, shared binary-codec ownership paths, hosted
  campaign publication and all primary performance gates for #103.

See [campaign contract](../flatbuffers_performance_acceptance.md) for execution
commands and limitations. A short diagnostic cannot satisfy primary acceptance.

## Shared-runtime test teardown (2026-10-06)

- [x] Inspect the exact-head Fast Checks failure at `1aafa099`: eight benchmark
  cases fail after the new native E2EE provider factory tests.
- [x] Reproduce six accounting failures in one Linux test process with the
  factory file preceding the accounting file. Provider disposal leaves the
  shared native runtime alive, preventing a later router runtime start.
- [x] Add the runtime shutdown teardown already used by the other factory
  regression tests. All 39 related Linux cases pass with no native skips.
- [x] Pass all 1,498 full Linux benchmark cases with no native skips.
- [x] Complete the fresh `bin/test-fast` repository baseline at exit 0.
- [x] Pass fresh full `bin/verify` at exit 0 with Rust, VM, consumer, benchmark,
  router and full browser suites. Focused formatting and analysis also pass.
- [x] Push the repair to both remotes as `87688b8c`.
- [ ] Accept required hosted checks on that exact head.

Evidence: `/tmp/connectanum-flatbuffers-ci-1aafa-fast-job.log`,
`/tmp/connectanum-flatbuffers-ci-1aafa-runtime-leak-{repro,fixed}.{log,exit}`.
Full suite evidence: `/tmp/connectanum-flatbuffers-ci-1aafa-linux-bench-fixed.{log,exit}`,
`/tmp/connectanum-flatbuffers-campaign-baseline.{log,exit}` and
`/tmp/connectanum-flatbuffers-ci-runtime-teardown-verify.{log,exit}`.
The strict seven-package publish dry-run on `1aafa099` reports zero warnings;
this is that checkpoint's package evidence, not acceptance of the pending repair.

## Coverage repairs and master synchronization (2026-10-06)

- [x] Fetch both remotes and confirm `master` at `3bac4cf5` is already integrated;
  the merge command reports `Already up to date`.
- [x] Inspect both hosted coverage artifacts. Both VM jobs fail the benchmark
  98% gate at 97.404%. The same-head PR browser report passes core 96.136% and
  client 96.430%; the push job reaches its whole-suite 900-second deadline while
  still completing tests.
- [x] Complete the fresh `bin/test-fast` baseline at exit 0.
- [x] Reproduce six reporting/isolate defects before changing behavior; all six
  pass after the fixes. Incomplete boundary metadata and invalid byte counts now
  fail closed. System-only VM processes have no application fallback.
- [x] Pass all 60 focused metric, malformed-correlation, direct workload/profile
  validation and native/Dart typed E2EE factory tests with no native skips.
- [x] Pass focused analysis and all 80 verification-script tests. Check companion
  findings against source and test evidence; none establishes a remaining defect.
- [x] Pass all 1,498 macOS benchmark cases under coverage collection. Pass all
  Linux cases across the full suite and the two-case fixture repair; Linux
  benchmark coverage is 98.219% (2,923/2,976 lines) with no benchmark policy
  failures. macOS leaves Linux-only process-stat paths unexecuted at 97.043%.
  Benchmark-only input does not accept the whole-repository VM coverage job.
- [x] Pass fresh `bin/test-browser-coverage` at exit 0: core 96.136%, client
  96.430%, with 20 declared native-only client skips and unchanged thresholds.
- [x] Complete fresh `bin/verify` at exit 0: Rust, VM, consumer smokes, 1,498
  benchmark, 4,935 router, 4,690 core Chrome/Dart2Wasm and 2,829 client browser
  cases (20 declared native-only client skips).
- [ ] Push the resulting checkpoint and accept required hosted checks on it.

The bounded core browser deadline is 1,200 seconds and the whole job has 30
minutes for both suites and artifact upload. Per-test deadlines, suite selection
and coverage thresholds are unchanged. Known copy counts remain lower bounds;
these reporting repairs do not measure the outstanding SDK/TLS/transcode sites.
No additional issue is closed and no performance parity result is accepted.
Evidence is recorded in `docs/project_state.md`.

## Ordinary encoded routing and JSON ownership (2026-10-06)

The optional native forwarding-query ABI v1 checks ordinary CBOR/FlatBuffers
argument reuse without consuming the message. CBOR-to-FlatBuffers validates the
pinned container contract. Native envelope replacement resolves and rechecks the
actual destination, keeps each original payload allocation once, and rejects
incompatible output without sending bytes or consuming the source. Worker
forwarding now uses this eligibility for mixed codecs and cross-worker targets.
PPT/transparent data retains its prior path. A real regression test caught a
missing custom INVOCATION-option guard; both progressive and ordinary forwarding
now preserve custom metadata through the existing envelope-building path.

Mixed-codec tests also exposed JSON's destructive binary-container conversion.
Typed and immutable Uint8List containers now remain unchanged and reusable.
Shared TransferableTypedData aliases initially regressed when the redundant
mutation was removed; 14 fail-first cases reproduce this. One payload-local
identity cache now encodes each transfer once across arguments and keywords,
while retaining one-shot consumption and leaving caller containers unchanged.

macOS passes 87 focused native/routing/PPT tests and all 29 JSON regressions.
GuardMalloc passes 70 observed cases with all 141 native/dependency inputs
matching. Linux arm64 passes 12 forwarding tests plus a real network test with
20 transport/direction/envelope scenarios. All 116 focused Linux Dart cases pass,
including the older-library fallback with no missing-native skips.
An unnecessarily broad Linux runtime attempt was stopped during an unchanged
slow external-lease test; no complete Linux runtime-suite pass is claimed.
The initial full verification was stopped after finding the alias regression;
the next passed VM, native, router and benchmark checks but failed 14 browser
alias tests because TransferableTypedData is unsupported there. The alias cases
now explicitly select the VM, as the existing serializers' transfer tests do;
all 15 Uint8List-container cases pass in Chrome/Dart2Wasm. Fresh full verification
on that platform correction passes at exit 0: 4,682 core VM, 4,935 router, 1,456
benchmark, 4,690 core browser and 2,829 client browser cases (20 native-only client
skips). A repeated root-level parallel Linux
invocation exposed conflicting singleton native runtimes; all 116 cases pass
with the router test configuration's required concurrency 1.
Two hosted mutation jobs at
`d3546c6d` ended on runner shutdown signals, without a completed gate result.
Known copy lower bounds and SDK/TLS/transcode unknowns remain explicit. #100–#104
stay open; routing correctness is not complete copy or performance acceptance.

Completed companion reviews were advisory. Source inspection and tests confirm
that destination codecs are immutable and send-time eligibility is rechecked,
recursive JSON output allocation already existed, and cached immutable strings
are serialized independently at each alias with one shared transfer consumption.
The broad follow-up exceeded the helper's context limit; focused Qwen and GLM
follow-ups timed out. Neither incomplete review is counted as coverage. The
29 regressions and direct source checks substantiate the JSON repair.

## Portable provider copies and XSalsa limit (2026-10-05)

Portable AES now uses PointyCastle's `processBytes`/`doFinal` to write directly
after the nonce in the final buffer, returning only the bytes written. The two
portable CBOR providers avoid redundant plaintext/ciphertext wrapper clones.
Copy counters first reproduced the extra operations; the same tests pass after
removal. Windowed core counters expose the remaining mutable XSalsa output
materialization and ciphertext-list coercion, including a failed operation's
already copied prefix. Benchmark lower bounds retain their native-process and
Dart-isolate scopes, unavailable snapshots and incomplete-pipeline markers.

The pinned pinenacl 0.6.0 source exposed a separate contract defect:
`EncryptedMessage.fromList` caps input at 1 MiB. Authenticated 2 MiB typed XSalsa
decryption failed despite the advertised 64 MiB profile. Typed receive now uses
the public explicit-length `ByteList` body wrapper and nonce API with the same
authentication primitive and existing 64 MiB preflight. The legacy CBOR wrapper
is unchanged. Old-limit/next-byte/2 MiB, truncated nonce/tag, tampering, sliced
input and native/portable 2 MiB tests pass. A live reporting regression also
proved that an explicit identical peer codec was incorrectly called mixed;
matching peers are now homogeneous and a CBOR-to-JSON route stays unmeasured.

The fresh baseline `bin/test-fast` passed. macOS focused tests and all 82
native-provider cases pass. Linux arm64 passes 234 focused cases plus five live
worker scenarios. A fresh full `bin/verify` passes at exit 0, including all 1,456
benchmark and 4,923 router cases and Chrome/WebAssembly (4,675 core; 2,829 client,
20 native-only skips). Current-head hosted checks remain queued; the older run
ended cancelled. The earlier partial local run
was stopped after finding the size defect and retained as
`/tmp/connectanum-flatbuffers-portable-crypto-verify-pre-limit.log`.
Narrow Qwen review claims were checked against the pinned library code and real
tests: output capacity includes the tag; counters are isolate-local; native and
portable sites are disjoint; receive views are read synchronously by pure Dart;
short inputs are wrapped as decryption errors. No added input copy is warranted.
Crypto dependency internals, native-provider coercion, other-isolate wrappers and
serializer/framing, SDK/TLS/transcode measurements remain unfinished. #100–#104
stay open, with no accepted parity campaign or current-head hosted evidence.

## Native crypto staging and Linux CI repair (2026-10-05)

Detached XSalsa preserves the existing nonce/tag/ciphertext bytes while removing
the old payload shift and second output copy. Native ABI v1 metrics count the
actual bulk staging sites separately from transport counters; Dart records the
runtime isolate's crypto FFI copies. Existing AES wire behavior is unchanged,
including its eligible consuming decrypt with no crypto staging copy. The report
names process-wide native and isolate-local bridge scopes explicitly and keeps
total E2EE coverage unmeasured. Optional symbols plus exact ABI version guard
prevent calling an incompatible snapshot layout.

Explicit typed FlatBuffers E2EE now reaches benchmark providers, construction
groups and call/publish options instead of the former CBOR-only rules. Omitted
serializers retain the CBOR profile; typed file transfer is rejected. Live 64 KiB
native RPCs for both ciphers emit staging metrics on macOS and Linux arm64.
Four native oracle/wire/error tests and 82 native-provider cases pass on each
platform. The metric suite (4), runner suite (65) and comparator suite (15) pass.
The comparator/policy requires E2EE evidence and rejects partial totals and false
not-applicable exemptions. These correctness checks do not establish parity.

Linux CI at `b5ab660c` failed five cases across two benchmark test files because
their default library lookup omitted the CI `target/ffi-test/release` artifact.
The Linux arm64 repro fails identically before `ecaa43d4` and passes all 14 focused
cases after it, with no skips. Full local `bin/verify` passes, including 1,452
benchmark cases and Chrome/Wasm. GuardMalloc passes all 66 cases; 141 recorded
native/dependency inputs still match. Logs are
`/tmp/connectanum-flatbuffers-crypto-verify.log`,
`/tmp/connectanum-flatbuffers-crypto-guardmalloc-final/report.json`,
`/tmp/connectanum-flatbuffers-crypto-linux-{native,provider,live}.log` and
`/tmp/connectanum-flatbuffers-bench-native-path-linux-{repro,fixed}.log`.

Narrow Qwen reviews completed; claimed tag-layout, failed-call counting, ABI and
scope issues were checked against the source and direct tests. Tag insertion is
explicit, failed calls count copies already performed, unknown versions never call
the snapshot, and the mixed measurement scopes are labelled as a lower bound.
The GLM advisory request did not finish and is not review acceptance. Remaining
crypto/serializer/transcode and SDK/TLS measurement gaps, hosted CI, consumer
artifacts and the paired performance campaign keep #100–#104 open.

## External-loan terminal-path acceptance (2026-10-05)

Four native network tests now cover eleven RawSocket/WebSocket or rejection
scenarios: unobserved successful writes, actual full-queue rejection, missing
destinations, and fan-out terminated by peer reset, local close or shutdown.
Verified payload prefixes prove partial progress before termination. The sole
writer retains the foreign loan when no caller view/handle remains. A separate
rejected producer releases while the accepted send stays pending; an exported
view remains readable across shutdown. Callback count/thread, byte integrity and
byte/lease quotas are checked. Existing registration and ABI tests cover setup
rollback and safe capability fallback. GuardMalloc requires all four network
tests and passes 62 total observed cases; its runner failure-control tests pass.
Fresh canonical fast/full verification both exit 0. Local logs and the memory
report are recorded in `docs/project_state.md`; hosted acceptance for the new
commit remains pending. This completes #97 without adding database integration
or asserting end-to-end zero-copy/performance parity.

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

## Earlier verification evidence

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

## Earlier verification work and outcomes

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
