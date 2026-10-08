# Project State

Last updated: 2026-10-08.
Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
Issues [#95](https://github.com/konsultaner/connectanum-dart/issues/95), [#96](https://github.com/konsultaner/connectanum-dart/issues/96), [#97](https://github.com/konsultaner/connectanum-dart/issues/97), [#98](https://github.com/konsultaner/connectanum-dart/issues/98) and [#99](https://github.com/konsultaner/connectanum-dart/issues/99) are complete. Issues #100–#104 remain open. Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

Current follow-up (2026-10-08): PR #105 Codecov project regression.
At `7b530d58`, hosted test/mutation, package and native-artifact checks pass;
Codecov project coverage fails at 88.693% against master's 93.896%.
Its report includes two generated WAMP FlatBuffers files already measured
separately by the local coverage checker. Codecov now uses the same exact
exclusions; handwritten runtime/serializer code and thresholds remain unchanged.
The coverage runner also retains eight previously omitted complete suites,
including native owned segments, FlatBuffers frames/profiles, copy metrics and
router forwarding variants. Actual added-suite runs pass and contribute 171
handwritten VM line hits; the merged hosted-report estimate is 93.913%.
Three fail-first regression methods reproduce the omissions and scope mismatch.
Fresh baseline `bin/test-fast` and candidate `bin/verify` pass at exit 0,
including Rust/VM/consumer/router checks and both browser suites (4,751 core,
2,829 client; 20 unchanged native-only skips). All 110 coverage-policy/runner
methods pass. Codecov's public validator accepts the exact generated-file scope.
The functional fix is published as `7bf7dd4f`; current hosted acceptance is
reported by [PR #105 checks](https://github.com/konsultaner/connectanum-dart/pull/105/checks).
Evidence: [coverage scope/proof](research/2026-10-08-codecov-project-coverage.md).

Current follow-up (2026-10-07): coverage runtime ownership isolation.
The normal runner isolates remote-auth integration; the coverage runner omitted
that separation. A focused combined actual run aborts at exit 134 with runtime
already started and a native callback from the wrong isolate. Four MCP and
thirteen remote-auth cases pass when separated. Coverage now retains both full
suites in sequential processes with separate raw reports; formatting continues
to merge the whole raw root. Two fail-first runner methods and failure controls
pass; all 85 script regressions pass. Bounded review identifies no concrete
finding. Candidate canonical fast/full checks pass at exit 0, including both
browser suites with the same 20 native-only skips. Hosted acceptance is pending.
The previous Linux MCP subscription assertion's specific cause remains unknown.
The `df1a9ad5` native run provides verified 34-case reports on all five platforms
(170 total, no skips), including Windows lifecycle and 48-byte ABI guards. Its
package dry run passes. The overall native run fails afterward on macOS Intel
attestation persistence; two rerun requests return HTTP 500. Sampled hosted PR
jobs fail without acquiring a runner (five attempts, no steps). These external
failures remain recorded; gates are not skipped.
Evidence: [coverage scope/proof](research/2026-10-07-coverage-runtime-isolation.md).

Current follow-up (2026-10-07): Windows native runtime admission.
Published `4a7ac185` native run 37622772557 passes four Linux/macOS platforms;
Windows now launches tests and passes the 48-byte ABI guard, then rejects
runtime startup because its platform selector chooses the unsupported stub.
Windows now uses the existing shared supported handle. Other hosts retain
explicit rejection. The packaged verifier exercises actual start, duplicate
start, shutdown and restart before running all 34 profiles. All 20 verifier
methods and local constructor/lifecycle/unsupported controls pass. A fresh
macOS production candidate passes the runtime audit, ABI guard and all 34
public profiles. Bounded review is checked against source; GLM identifies no
definite defect. Candidate canonical fast/full checks pass at exit 0. Hosted
Windows acceptance remains pending. The preceding `4a7ac185` PR VM coverage
job 112825887695 fails one MCP last-owner cleanup assertion (expected empty,
observed `[1]`); source-level cause and repair remain pending and are the next
CI priority. Both remote masters remain at integrated `3bac4cf5`; no new merge
is needed. The five-platform gate and all benchmark budgets are unchanged.
Evidence: [runtime scope and proof](research/2026-10-07-windows-runtime-admission.md).

Current follow-up (2026-10-07): Windows packaged consumer launcher.
Verified source checkpoint `736b6454` contains the Tokio-Rustls observer,
fast ownership-oracle selection fix and packaged 48-byte ABI guard.
Published `2bfff943` native dry run 37614965856 passes four platforms but
Windows hook compilation tries `dart.EXE.exe` before any profile tests.
Two execution regressions fail first. Windows `.EXE`/`.exe` and shell wrappers
now normalize to lowercase `.exe` and require the executable file.
All 17 verifier methods pass; POSIX paths, SDK and profile requirements remain
unchanged. Bounded local review completes without a definite error.
The corrected macOS production consumer passes the 48-byte ABI guard and all
34 public profile cases. Final `bin/test-fast` and `bin/verify` pass at exit 0,
including Rust/VM/public consumers and both browser suites (20 unchanged
native-only skips). Hosted Windows runtime acceptance remains pending. Evidence:
[Windows launcher scope and proof](research/2026-10-07-windows-consumer-launcher.md).

Current follow-up (2026-10-07): first full hosted primary result.
Frozen `a5c6aaf9` completes all 1,440 rows (48 cases, three codecs, three warmup
and seven measured passes); driver exit0 and cleanup, policy/executable hashes
and exact local comparison replay verify. The comparator fails with 2,129
findings, including 276 parity failures: throughput, latency, CPU and allocation
gates each fail in all 48 cases; RSS fails in 36. Missing copy fields, zero GC
baselines and five windows below 10,000ms remain blockers. A forced-GC probe
emits real `GC` category B/E collection spans while the existing collector reports
zero; a positive regression fails. No collector repair is included yet.
Every original supplement, normative copy field and budget remains mandatory.
Evidence: [hosted result and GC repro](research/2026-10-07-hosted-primary-result.md).

Current follow-up (2026-10-07): actual Tokio-Rustls plaintext extraction.
The workspace pins published Tokio-Rustls 0.26.6, both original licenses,
its unchanged published lockfile and four restored upstream test fixtures.
The source hook counts only successful `ReadBuf::put_slice()` bytes;
borrowed views and consumption preserve the storage pointer and count zero.
Two fail-first copy cases and a pending/malformed-input control pass after
instrumentation. Both macOS/Linux pass all 14 enabled and 11 disabled cases;
Linux matches all 3,017 frozen inputs and passes a real TLS connection test.
Both candidate production bundles pass 34 public profile cases and nine exact
license/notice/manifest checks each. The source gate passes all twelve controls.
Initial companion attempts are lease-blocked; later test advice completes.
The first canonical fast check loads the just-packaged production library and
fails three owner-oracle cases because test symbols are intentionally absent.
The fast client suite now explicitly prepares `ffi-test`, matching full
verification. Three execution controls pass on macOS/Linux after reproducing
both production-selection failures; a failed test build stops verification.
A larger review reaches its token limit; a bounded retry completes without an
actionable finding. Its speculative cautions are disproved by initialization,
feature selection and execution tests. Canonical fast verification passes.
Full verification terminates at exit 255 on Dart kernel-copy OS error 28:
the host disk is full. Rebuildable feature-worktree compiler/debug caches are
removed, restoring 21 GiB free while retaining source, release libraries and
proof artifacts. The production-consumer audit also exposes missing coverage
of the new 48-byte Rustls snapshot. It now requires the export and checks its
null status, writes and surrounding guards in a fresh process. All 14 verifier
methods pass, including six new failure controls; the macOS packaged library
passes the ABI guard and all 34 profile cases. A bounded GLM review completes
without a definite error. Docker's API is unresponsive after the disk event;
its original Linux direct-probe session remains live and is not restarted.
Both published cde CI runs are green. Final canonical `bin/test-fast` and
`bin/verify` pass at exit 0 after cache cleanup, including Rust/VM/consumers,
1,642 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with 20 unchanged native-only skips. Published `2bfff943` native dry
run 37614965856 passes all 34 public cases on four Linux/macOS platforms;
Windows fails before testing because hooks launch `dart.EXE.exe`. Two
execution controls reproduce uppercase suffix propagation and omitted
executable validation; a narrow launcher correction is the next CI priority.
This source-only Tokio observation does not extend the Rustls ABI or close
complete-copy/performance criteria. Evidence:
[extraction scope and proof](research/2026-10-07-tokio-rustls-extraction.md).

Current follow-up (2026-10-07): optional Rustls source metrics bridge.
Twelve fail-first cases reproduce omitted partial-counter metadata on both
transports. A separate 48-byte C snapshot exposes all six actual Rustls source
counters; legacy 24-byte and V2 40-byte transport snapshots remain unchanged.
Client/router optional lookup and nullable deltas retain null with old libraries.
Benchmark client/router breakdowns retain the named partial observations while
complete TLS/transport gates remain unchanged. MacOS passes the native layout/
null/tail guard, 56 merge/delta cases and old/new ABI probes. Linux matches all
2,996 final frozen source/lock inputs and passes its native guard, 56 merge/delta
cases and both new/published-old ABI probes. A separate fail-first negative
counter test now preserves unmeasured metadata for invalid values. Completed companion
test advice is checked; final review is blocked by the active native-mutation
resource lease. The candidate fast check exposes a local SDK path in the published artifact
proof. Command paths are now normalized to `dart`, retaining raw report hashes;
the public-reference gate passes. Fresh canonical `bin/test-fast` and full
`bin/verify` pass at exit 0: Rust/VM/consumers, 1,642 benchmark, 4,958 router,
4,751 core browser and 2,829 client browser cases with 20 unchanged native-only
skips. Crate formatting and the final Linux native/new-ABI replay pass with
all 2,996 formatted inputs matched. Narrowed review remains lease-blocked. Both cde
hosted CI runs pass all completed jobs and retain only their MCP mutation jobs;
the frozen full primary remains independent. No complete-copy, parity or
milestone acceptance follows.

Current follow-up (2026-10-07): packaged production runtime consumers.
Source checkpoint `0ce3c364` commits the payload observer after canonical fast
and full verification passed. The new Native Artifacts gate verifies the
archive checksum, detached/embedded source manifest and production ABI/oracle
inventory, then runs all 34 public profile cases in three separate Dart
processes against the extracted library. JSON evidence rejects skips, missing
cases, errors and unfinished starts even with a success summary. Per-platform
proofs and logs upload on failure. Nine failure controls pass on macOS/Linux, and Actionlint passes. The actual
gate passes all 34 cases against each frozen published `cde9fbed` arm64 bundle;
completed companion advice is checked against source and actual timeout
behavior. Canonical candidate `bin/test-fast` and full verification pass at exit 0
together with the metrics bridge. Hosted runtime proof for all five
resulting-source platforms remains pending. No release, whole-copy or
performance acceptance follows.

Current follow-up (2026-10-07): payload copy observations.
Published source `cde9fbed` passes canonical fast/full checks. Push CI fast
checks now pass; remaining resulting-source jobs are live. Native dry run
37588514671 passes all five builds; package dry run 37588518168 passes.
All 15 pinned attestations, 25 exact notices/manifests (including Windows),
30 preview assets and rendered notes verify. Both hosted arm64 production
libraries pass 34 profile cases; other platforms have build/provenance evidence.
The independent full primary 37582544124 remains live on frozen `a5c6aaf9`.
Four new fail-first tests expose omitted 7/8/10/9-byte payload copy observations.
Hooks cover owned clones, borrowed ownership conversion, bounded U8/U16 reads
and content/certificate encodes while preserving borrowed reads and owned
moves. A targeted U24 test confirms inner clone delegation counts once.
All 243/232 macOS and 244/233 Linux enabled/disabled cases pass; both real TLS
checks pass with all 860 frozen Linux inputs matched. The source gate and five
failure controls pass. Initial companion findings are disproved by source and the targeted regression.
The follow-up is initially blocked by the native-mutation resource lease; its
post-verification retry completes and confirms the clone/borrow semantics. Canonical candidate `bin/test-fast` and full `bin/verify` pass at exit 0:
Rust/VM/consumers, 1,616 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with 20 unchanged native-only skips. No whole TLS or
parity acceptance follows; #100–#104 remain open. Evidence:
[scoped payload proof](research/2026-10-07-rustls-payload-copies-proof.json).

Current follow-up (2026-10-07): deframer and record copy observations.
Four new fail-first tests expose omitted deframer appends/moves and record
clones/appends. All 238 enabled and 232 disabled upstream library cases pass;
the source gate and five failure controls pass. Named counters remain partial.
A live receive assertion exposes that buffered Rustls reads directly into
its deframer, bypassing `extend`; accepted input is not counted as an assumed
copy. That invalid new assertion is removed, preserving existing coverage.
The live record-append check passes on macOS and Linux. Linux passes 239 enabled
and 233 disabled cases with all 860 frozen source/lock inputs matched.
Canonical `bin/test-fast` and full `bin/verify` pass at exit 0: Rust/VM/consumers,
1,616 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases,
with 20 unchanged native-only skips.
Growth, remaining record/crypto and Tokio-Rustls/SDK extraction still prevent
whole-copy acceptance. The published `a5c6aaf9` full primary remains live;
native and package dry runs finish successfully. Both resulting-source CI fast
jobs fail a campaign unit fixture's missing generated Cargo lockfile. An
isolated temporary source root reproduces it; explicit synthetic locks and
hash/archive assertions pass all 15 campaign cases without changing policy.
All 15 a5 artifact attestations and 30 preview assets verify. Windows converts
the bundled notice and source manifest to CRLF; their new `-text` attributes
prevent that byte drift; all 843 source/fixture/notice/manifest filter controls
pass. The unchanged release-note renderer reproduces the
preview with the exact workflow reference. All 34 production profile cases
pass against both hosted macOS arm64 and Linux arm64 libraries; other three
platforms have build/provenance evidence. No release or parity claim follows.
#100–#104 remain open.

Current follow-up (2026-10-07): source-observed Rustls copies.
Rustls 0.23.45 is pinned with original licenses and an 841-file digest manifest,
including exact upstream test fixtures. Two fail-first cases expose omitted
actual chunk/queue copies; observations make all 234 library cases
pass. A feature-disabled build and real native TLS outbound observation pass.
The live receive probe exposes a separate Tokio-Rustls copy site; total TLS
coverage remains unknown. The dependency lock changes only Rustls source at the
same version. Five source-integrity failure controls and fresh `bin/test-fast` pass.
All 841 source blobs remain exact with Windows newline conversion enabled.
Native bundle packaging retains Rustls licenses and source digests. Final
`bin/verify` fails the unchanged FastCGI cumulative stdout-limit fixture
with a peer reset; its isolated unchanged repro and five unchanged repeats
pass. Fresh full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,616
benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases,
with 20 unchanged native-only skips. The narrowed GLM judgment completes
with no confirmed native defect. Real macOS arm64 packaging passes: all five
Rustls notice/manifest files match and the library excludes test oracles.
Clean source commit `3b251789` packaging then matches the verified library,
notices and source manifest. All 34 production profile cases pass in separate
processes; an initial combined probe finds an already-started shared runtime.
This scoped macOS check does not provide multi-platform release acceptance. #100–#104 and all gates remain
open. Research: [Rustls copy observer](research/2026-10-07-rustls-copy-observer.md).

Current follow-up (2026-10-07): native prefetched input copies.
Two real TCP-pair regressions expose uncounted staging/replay copies; an
intermediate observation identifies the duplicate unread-buffer copy, now
removed. The old 24-byte snapshot remains unchanged beside a new optional
40-byte ABI. Both Dart runtimes retain null for absent counters. The 30 merge,
39 comparator/campaign and eight live worker cases pass; new test-library and
old production-library snapshot tests pass. Complete transport reports require the new input
counter evidence. Initial fast-check warnings and an omitted direct test
dependency are corrected; Linux locked-snapshot setup was repaired without
relaxing dependency locking. Final Linux arm64 native/FFI, 31 Dart and eight
live worker cases pass with all 18 source/lock hashes matched. Fresh
`bin/test-fast` passes at exit 0, including all 1,616 benchmark cases.
Full verify first exposes a test-only stale-debug library selection; the exact
repro fails before and passes after using the existing canonical test resolver.
Final full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,616 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases, with the same
20 native-only skips. Evidence: `/tmp/connectanum-native-io-copy-verify-final.{log,exit}`.
Companion debug/review/test advice is verified; no accepted source defect remains.
Preceding `0ec8df06` PR run 37565054707 completes all 41 jobs successfully.
Push run 37565051795 also completes all 41 jobs successfully. The four verified
commits through `a5c6aaf9` are now published to both remotes. Resulting-source
CI runs 37582506753 (push) and 37582511052 (PR), full primary campaign
37582544124, native dry run 37582546475 and package dry run 37582549630
are dispatched; acceptance remains pending. Resulting-head
hosted acceptance and performance parity remain pending; no issue closure follows. Research: [prefetched input copies](research/2026-10-07-native-prefetched-input-copies.md).

Current follow-up (2026-10-07): hosted full FlatBuffers campaign.
The registered profile workflow gains an explicit manual primary choice with
all 1,440 rows and unchanged gates. Production release binaries, locks and raw
failure evidence are archived. The 38 campaign/comparator tests and verified
Actionlint pass; four synthetic summary fixtures preserve failure status.
Final companion review is blocked by the active native mutation resource lease.
Baseline `bin/test-fast` and full `bin/verify` pass at exit 0, including
1,609 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with the unchanged 20 native-only skips. Evidence:
`/tmp/connectanum-hosted-primary-verify.{log,exit}`. Hosted execution remains
pending; no performance acceptance follows. Research: [hosted full campaign](research/2026-10-07-hosted-flatbuffers-primary-campaign.md).

Current follow-up (2026-10-07): observed native PPT submission metrics.
Thirty-six fail-first cases expose zero-copy values inferred only from settings
and permissive observation parsing. Each sample now requires its own observed
native frame submission and complete encoded-owner reuse. Missing/fallback/
repeated/mismatched observations remain unmeasured. All 121 focused, 32 native
and 20 live benchmark cases pass on macOS/Linux, with matched Linux inputs.
Tracking is opt-in; no ownership/ABI/fallback or acceptance gate changes.
Baseline fast and full `bin/verify` pass at exit zero, including 1,609 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases with 20 unchanged
native-only skips. Evidence: `/tmp/connectanum-observed-owned-copy-verify.{log,exit}`.
Resulting-head hosted verification remains pending. Final local review is blocked by
the active native mutation resource lease; direct review and focused checks
complete. Research: [observed submissions](research/2026-10-07-observed-native-ppt-copy-boundary.md).

Current follow-up (2026-10-07): measured RawSocket input normalization.
Twenty-seven fail-first assertions reproduce partial-input retries and omitted
header accounting. Full arrays and validated native ranges retain their storage;
other inputs make one measured copy before queueing. All 81 socket/metrics cases
pass on macOS and Linux arm64, and the exact Linux diagnostic CI step passes.
Baseline fast and bounded GLM review pass. First verify fails an unchanged
FastCGI closure fixture; isolated repro and five unchanged repeats pass. Fresh
full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,563 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases, with 20
unchanged native-only skips. No assertions or timeouts changed. Evidence:
`/tmp/connectanum-socket-normalization-final-verify.{log,exit}`. SDK/TLS
and performance acceptance remain open. Research: [input normalization](research/2026-10-07-rawsocket-input-normalization.md).

Current primary campaign (2026-10-07): the unchanged full matrix failed at
124 partial warm-up rows. An overlapping diagnostic Dart job triggered the
existing guard, which stopped the driver process group at 01:25:48 UTC. The
run provides no performance acceptance; all gates and #100–#104 remain open.
Finish builds and tests before starting a new frozen campaign. Research:
[failed primary campaign](research/2026-10-07-primary-flatbuffers-campaign.md).

Current follow-up (2026-10-07): bounded native socket views. Twelve fail-first
transport cases reproduce the SDK partial-view copy. Validated malloc-owned
ranges now retain their original allocation through bounded read-only aliases;
a Dart finalization token retains the source through the backing root. An
interim unread metadata field passed VM tests but failed a compiled lifetime
check; the repair passes all 83 focused tests on macOS and Linux arm64. Four
real 16 MiB backpressure cases pass in both VM and compiled AOT modes, retaining
original write addresses through collection and observing final native release.
The exact CI step and its missing-interposer controls pass. Baseline fast,
focused analysis and bounded review pass. Restarted `bin/verify` passes at exit 0:
Rust/VM/consumers, 1,563 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with the unchanged 20 native-only skips. Evidence:
`/tmp/connectanum-bounded-native-alias-token-verify.{log,exit}`. Resulting-head
hosted acceptance remains pending; no total-copy or parity acceptance follows. Research: [bounded native views](research/2026-10-07-bounded-native-socket-views.md).

Current production checkpoint `8503f31c`: [Native Artifacts 37546766311](https://github.com/konsultaner/connectanum-dart/actions/runs/37546766311)
passes five builds and its signed dry-run preview. All fifteen pinned
attestations, thirty preview assets and rendered notes verify. Fresh source-pinned
Apple Silicon and Linux arm64 production consumers pass eight steps each,
including twenty provenance, ten segment, sixteen owned-PPT and 104 mixed-PPT
cases. Both libraries exclude test oracles; source archive and log hashes match.
The other platforms have build/provenance evidence only. No release or performance
acceptance follows; required current-head CI is live. Research: [production
checkpoint](research/2026-10-07-native-production-checkpoint.md).

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
provenance](research/2026-10-07-native-external-buffer-provenance.md).

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
acceptance follows from this pointer diagnostic. Research: [backpressure](research/2026-10-07-dart-sdk-backpressure.md).

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
[segmented Dart sending](research/2026-10-06-dart-flatbuffers-segmented-send.md).
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
[empty PPT keywords](research/2026-10-06-native-empty-ppt-keywords.md).
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

Independent [SDK copy research](research/2026-10-06-dart-sdk-copy-boundaries.md)
identifies conditional partial-view copies before socket writes and binary
masking/ring-buffer copies. A 15-case ordinary serializer diagnostic shows
all five FlatBuffers frames use partial backing views, unlike the ten
CBOR/MessagePack frames. The checked-in Linux pointer probe now confirms the full/partial-view boundary
through actual libc writes and retries. Internal buffering, TLS and total-copy
volumes remain unmeasured. This is not parity or a complete-copy claim.
Complete hosted acceptance and all unresolved milestone criteria remain pending.

Preceding follow-up: native reuse of opaque PPT bodies between CBOR, MessagePack
and FlatBuffers. Nine new regressions fail before implementation: six mixed
directions report ineligible, and three homogeneous controls lose PPT metadata
on raw echo replies. Empty, binary and 128 KiB bodies exercise five forwarding
kinds, producer lifetime and fan-out. Evidence:
`/tmp/connectanum-native-ppt-routing-before.{log,exit}` (exit 101).
The separate virtual-workspace formatter invocation failed before these tests;
the test file was subsequently formatted directly with rustfmt.
Research: [mixed binary PPT forwarding](research/2026-10-06-native-mixed-ppt-forwarding.md).
All 22 segmented tests now pass, including 405 body/direction/route combinations.
The live native-path assertions reproduce six failures against the preceding
production library. They also expose 28 explicit reserved-`wamp` RPC fallbacks
before the Dart repair. Removing those exclusions yields 109 passing public
PPT/E2EE/mixed-eligibility cases, including ordinary routes, progress, ERROR,
custom details, JSON fallback and legacy-library controls. Current canonical
`bin/test-fast` passes at exit 0, including all 1,563 benchmark cases and live
consumer smokes. GuardMalloc passes all 83 observed ownership cases, including
the 22 segmented-forwarding tests, with confirmed loader interposition. Full
`bin/verify` fails at exit 1 on the worker-session case `dispatches calls across
workers and returns result to caller`, after 4,956 other router cases pass.
The failure is an obsolete reserved-scheme native-exclusion assertion. The
test now runs both paths: unavailable native handle preserves all prior
ciphertext/serialization assertions; a native CBOR handle verifies transfer,
routing IDs and no application decoding. Both cases and all 204 worker/live
cases pass together. The local companion's suggested state-leak explanation
was disproved by the exact taken-handle assertion and source. Its test review
cannot observe a real deserialized native result in the mock boss-port unit
fixture; the existing Rust wire and public live checks supply that evidence.
Fresh root analysis and the corrected full `bin/verify` pass at exit 0, including
Rust, VM, consumer/live checks, 1,563 benchmark, 4,958 router, 4,690 core
Chrome/Dart2Wasm and 2,829 client browser cases (20 declared native-only skips).
Browser verification did not run in the earlier failed attempt. Evidence:
`/tmp/connectanum-native-ppt-routing-worker-and-live.{log,exit}`,
`/tmp/connectanum-native-ppt-routing-verify-fixed.{log,exit}` and the earlier
failed `/tmp/connectanum-native-ppt-routing-verify.{log,exit}`.
The preceding
`7d7fab90` fast/full pass is the baseline. Implementation/test hashes are recorded
and unchanged. Evidence: `/tmp/connectanum-native-ppt-routing-fast.{log,exit}`.
GuardMalloc evidence: `/tmp/connectanum-native-ppt-routing-guardmalloc/report.json`.
Hosted coverage blocker: job `112370303567` on `7d7fab90` is explicitly
cancelled at the 45-minute maximum. Library coverage reports and gates are
written at 17:05:38 UTC; cancellation at 17:15:10 interrupts the separate
packaging formatter. These partial results are not complete hosted acceptance.
Only the aggregate VM coverage budget becomes 90 minutes, allowing both
formatter phases and uploads. Every other workflow byte, collection script and
coverage policy is unchanged. All 80 existing verification-tool checks pass;
hosted completion with the new budget remains pending. Evidence:
`/tmp/connectanum-native-ppt-routing-coverage-budget-proof.json` and
`/tmp/connectanum-native-ppt-routing-workflow-tests-final.{log,exit}`.
Research: [GitHub job timeout behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).
Evidence: `/tmp/connectanum-native-ppt-routing-segmented-complete.{log,exit}` and
`/tmp/connectanum-native-ppt-routing-public-fixed.{log,exit}`. A temporary local
refactor accidentally omitted following FFI functions and failed compilation;
they were restored before the passing runs, with the public ABI inventory
unchanged. The failed compile log is retained separately and is not behavioral
evidence. Local Qwen review/debug completed; source and lifetime tests resolve
its mixed-vector and zero-length owner concerns and its inaccurate suggestion
that the live tests should accept the fallback.

Native Artifacts `37489961393` passes all five builds and its dry-run preview at
`7d7fab90`. All fifteen attestations verify, all thirty preview assets match, and
the notes exactly match the renderer. Resulting-body-bridge artifacts remain
pending; no release is published. Evidence:
`/tmp/connectanum-7d7fab90-platform-provenance.json` and
`/tmp/connectanum-7d7fab90-preview-proof.json`.
Both freshly fetched master refs remain `3bac4cf5`, already ancestors of this
branch; no merge is needed. All unresolved milestone criteria remain open.

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


The preceding follow-up repairs a WampApp privacy-test false positive exposed by
the new CI run on `62f99ebb`. Consumer job `112272706961` passes 409 cases and
fails the contact-vault assertion because randomized Base64 ciphertext happens
to contain `bob`. The recorded JSON contains only public encrypted-envelope
metadata; its decoded ciphertext bytes do not contain the plaintext marker.
The repaired test checks the exact public metadata keys and quoted JSON tokens,
while keeping reopen, wrong-password, tamper and account-binding coverage.
Production vault/crypto code is unchanged. The captured old oracle fails, the
new oracle passes, and injected plaintext contacts still fail. All 22 vault
cases pass. Full `bin/test-wamp-app` passes at exit 0, including VM/JS/Wasm tests,
mutation controls and the web build. Fresh canonical `bin/verify` passes at
exit 0, including Rust, VM, consumers, 1,541 benchmark, 4,935 router, 4,690 core
browser and 2,829 client browser cases (20 declared native-only client skips).
Evidence: `/tmp/connectanum-vault-oracle-verify.{log,exit}`.
Evidence: `/tmp/connectanum-vault-oracle-control-proof.json` and
`/tmp/connectanum-vault-oracle-{baseline,focused}.{log,exit}`. The current hosted
run is not accepted as complete CI, and all remaining milestone issues stay open.
Its Fast Checks job now passes with the corrected aggregate budget; WampApp's
old test failure still prevents that PR run's Full Verify and VM coverage.

The preceding `62f99ebb` artifact checkpoint is complete:
[Native Artifacts 37464710421](https://github.com/konsultaner/connectanum-dart/actions/runs/37464710421)
passes all five builds and the dry-run preview. All fifteen source/branch/workflow
attestations verify, the thirty preview assets match, and the rendered notes
exactly match the current renderer with commit-pinned evidence links. A fresh
source archive's standalone public consumer, ten segment tests and sixteen live
owned-PPT cases pass with the Apple Silicon production artifact. All four public
serializers round-trip; direct scalar input/growth copies are zero and retained
read-only views survive disposal. The production library has no `ct_test_*`
exports, with an eighteen-symbol ffi-test positive control. Other platforms have
build/provenance evidence only. The package publish dry run passes. Three
superseded feature CI runs with cancelled Fast Checks were cancelled; current
head CI runs remain active. No release is published. Evidence:
`/tmp/connectanum-62f99ebb-platform-provenance.json`.

The preceding follow-up repairs the separate Fast Checks aggregate budget and
release-preview evidence links. Exact-head PR run `37457588251` on `5f1afae9`
hits GitHub's 20-minute Fast Checks ceiling; its preceding live consumer smoke
finishes at 20m12.701s, 1.937s before cancellation. Only this job's aggregate
budget becomes 45 minutes. Commands, suites, test deadlines and gates stay
unchanged. All 80 verification-tool checks pass. The release-note regression
first fails both missing-link cases and then passes all three tests; conformance,
benchmark and ownership links use the chosen repository/server and exact commit.
The ownership guide now compares pinned Dart entity reconstruction with a C
producer-thread transaction/lease policy and explicit copy fallback. All eight
workspace manifests remain free of ObjectBox dependencies.
No parity or complete copy-coverage claim is added. Fresh canonical `bin/verify`
passes at exit 0, including Rust, VM, consumers, 1,541 benchmark, 4,935 router,
4,690 core browser and 2,829 client browser cases (20 declared native-only client
skips). Evidence: `/tmp/connectanum-release-readiness-verify.{log,exit}`.
Hosted acceptance and the resulting commit's release preview remain pending.

[Native Artifacts 37457831556](https://github.com/konsultaner/connectanum-dart/actions/runs/37457831556)
passes on `5f1afae9`: all five platform builds and the release-preview job.
All 15 archive/checksum/manifest attestations independently verify against that
exact source, branch and workflow; every checksum and manifest source matches.
The fresh standalone consumer passes ordinary JSON/CBOR/MessagePack/FlatBuffers
round trips. Its native public-API check uses the downloaded Apple Silicon
production library, which also passes ten shared-segment ABI/lifetime cases and
all sixteen owned
CBOR/MessagePack RPC/pub-sub runner cases over RawSocket/WebSocket. Direct scalar
construction reports zero input/growth copies, and retained read-only control
views survive caller/frame disposal. The production library exports no
`ct_test_*` symbols; the ffi-test positive control exports eighteen. The other
four artifacts have provenance/build evidence, not runtime execution evidence.
The preview contains all thirty expected assets but lacks the required evidence
links; the renderer repair above addresses that gap. The tag is preview metadata;
no release is published. Full Verify and VM coverage in the PR run are skipped
after the Fast Checks cancellation; binding, browser coverage, GuardMalloc and
WampApp consumer checks pass. Issues #100–#104 remain open.
Evidence: `/tmp/connectanum-fast-budget-repro.json`,
`/tmp/connectanum-current-platform-provenance.json`,
`/tmp/connectanum-current-production-oracle-proof.json`,
`/tmp/connectanum-current-public-consumer-run.{log,exit}` and
`/tmp/connectanum-current-production-owned-{segments,ppt}.{log,exit}`.

The preceding CI follow-up repairs the aggregate Full Verify job budget. Hosted
run `37437589411` on `c3dbc9cb` reaches core browser tests after 40m51s and
continues passing cases until 0.665s before GitHub's 45-minute cancellation.
The annotation explicitly reports the maximum job execution time. The observed
setup/VM/consumer time plus the existing bounded browser commands needs about
70 minutes. Only this job's aggregate budget becomes 90 minutes; suite selection,
LLVM checks, browser command deadlines, per-test deadlines and gates are unchanged.
All 80 verification-tool regressions pass. Fresh `bin/verify` passes at exit 0,
including Rust, VM, consumers, 1,541 benchmark, 4,935 router, 4,690 core browser
and 2,829 client browser cases (20 declared native-only client skips). The
preceding sequential fast result remains the baseline for unchanged product
inputs. Hosted acceptance remains pending; the current-platform artifact
checkpoint is recorded above.
Evidence: `/tmp/connectanum-full-verify-budget-repro.json` and
`/tmp/connectanum-c3-full-verify-{job,annotations}.json`, plus
`/tmp/connectanum-full-verify-budget-canonical.{log,exit}`.

The preceding follow-up addresses complete native construction of the benchmark
CBOR/MessagePack PPT fixture. Its `native_buffer` group previously held only the
body in native memory and later serialized a Dart map. The constructor now writes
the complete existing PPT shape in native storage, counts the single body input
copy and retains the frozen span through the shared submission path. Two owner
cases first fail and then pass. All 140 reference vectors, 596 focused/aggregate
cases and 46 live matrix cases pass; 93 mutation-runner checks pass with one
declared skip. Frozen views survive caller disposal and rejected Session calls
release their owners. All 1,541 Linux benchmark cases pass without native skips.
Targeted coverage is 2,981/3,033 lines (98.286%), above the unchanged 98% gate;
the codec is 122/122 lines. There are no benchmark findings; the other unmeasured
packages prevent whole-repository coverage acceptance. Existing typed and CBOR
encryption cases also pass; the new constructors use the unencrypted custom
typed scheme. First canonical runs fail a stale exact mutation-input assertion;
the exact source/test/fixture inventory is repaired without relaxing thresholds.
Fresh full `bin/verify` passes at exit 0, including Rust, VM, consumers, 1,541
benchmark, 4,935 router, 4,690 core browser and 2,829 client browser cases
(20 declared native-only client skips). The repaired fast run hits an existing
two-second worker-readiness timeout while fast/full checks overlap. That
unchanged case passes five focused repeats, full verify and a fresh sequential
`bin/test-fast` at exit 0. Failed runs remain failed evidence; no timeout or
cancellation assertion changes. Evidence:
`/tmp/connectanum-native-construction-{verify-final,fast-sequential}.{log,exit}`.
Complete copy instrumentation and parity remain open. This constructor
checkpoint is pushed to both remotes as `8937a5d4` in draft PR #105.

The preceding follow-up adds shared encoded native-segment submission for CBOR
and MessagePack. The optional ABI retains frozen input handles on all outcomes
and keeps empty producers alive through write/flush. Dart has capability probes,
tracked submission, a Finalizable input holder and generic lazy owned PPT.
Eligible CBOR/MessagePack CALL/PUBLISH sends retain exact payload spans, count
small metadata copies and reject forged/replaced owner views. Benchmark
pre-encoded spans now keep that exact owner anchor for all three codecs.
All 18 native ownership/network cases, 10 new Dart transport/API cases and 131
focused benchmark/live cases pass. All 17 combined new API/existing frame
cases also pass on Linux arm64. All 73 GuardMalloc cases pass with 141 matching
native/dependency/schema inputs. The complete 281-case native FFI suite passes.
Eight live native Session cases also pass for CBOR/MessagePack RPC/pub-sub over
both transports on macOS and Linux. Linux benchmark coverage includes all 1,504
prior cases, the eight new Session cases and child-process build probes: it is
2,926/2,978 lines (98.254%), above the unchanged 98% gate with no benchmark
finding. This targeted report does not accept whole-repository coverage.
Mutation inventories include the new part/test/support file and all 92 inventory
checks pass with one declared skip. Fresh canonical `bin/test-fast` and
`bin/verify` pass at exit 0, including Rust, VM, consumers, 1,512 benchmark,
4,935 router, 4,690 core browser and 2,829 client browser cases (20 declared
native-only client skips). Evidence:
`/tmp/connectanum-shared-codec-{fast,verify}-recovered.{log,exit}`.
The first canonical runs exhausted the host filesystem during browser
compilation and benchmark temporary-directory creation. Only this worktree's
disposable Rust incremental caches were cleared (about 6 GiB); the failed runs
are retained and are not accepted as clean verification. An earlier baseline
attempt overlapped implementation and caught a transient switch-type
compilation error; that attempt is not claimed as a clean baseline. At that
checkpoint, dynamic native construction and complete copy/parity evidence were
pending; the constructor is now implemented above. Shared submission is pushed
to both remotes as `425c9e62`; at the last inspection both package-publish
dry-runs pass and its two hosted CI runs are queued.

The preceding follow-up implements the paired serializer campaign executor on top
of pushed runtime repair `87688b8c`. It generates the 48-case primary matrix,
balanced interleaved codec order, three warmup and seven measured passes. One
driver/worker remains alive across all passes; flushed JSONL avoids rebuilding
aggregate history. The executor retains partial/cancelled evidence, checks input
hashes before/after and confirms process-group teardown. The evaluator rejects
diagnostics, incomplete execution and duplicate matrix dimensions. Real reports
now retain the actual WAMP codec/TLS/PPT/construction settings for attribution.
Focused Python, Rust and benchmark-config checks pass. The real Linux diagnostic
completes all 120 reports with stable client/server PIDs and driver exit 0. All
input hashes match and per-pass JSONL exactly reproduces the raw driver stream.
The comparison correctly exits 1 with short/diagnostic and missing-copy findings;
no primary parity evidence is accepted. SDK/TLS/transcode copy
coverage remains open under #103; shared CBOR/MessagePack submission is now
implemented in the follow-up above.
Full `bin/verify` passes at exit 0, including Rust, VM, consumers, all 1,502
macOS benchmark cases, 4,935 router, 4,690 core browser and 2,829 client browser
cases (20 declared native-only skips). The final report-metadata predicate uses
the existing WAMP parser so uppercase aliases also retain configuration; a fresh
complete Rust benchmark suite passes after that small correction. Evidence:
`/tmp/connectanum-flatbuffers-campaign-verify.{log,exit}` and
`/tmp/connectanum-flatbuffers-campaign-rust-final-tests.{log,exit}`.

The complete Linux benchmark suite passes all 1,502 cases with no native skips.
Fresh benchmark library coverage is 2,925/2,979 lines (98.187%), above its
unchanged 98% gate, with no benchmark-specific file/package/component finding.
This targeted report does not accept the full repository's coverage job: other
packages are intentionally unmeasured. Evidence:
`/tmp/connectanum-flatbuffers-campaign-linux-bench-coverage.{log,exit}` and
`/tmp/connectanum-flatbuffers-campaign-linux-bench-coverage/{lcov.info,summary.json}`.

The first Linux diagnostic was interrupted and retained after revealing that the
client helper recycled after every workload: all 31 reports use distinct client
PIDs while the server PID stays constant. Reuse is now explicit for successful
RPC/pub-sub rows; default, cancellation and failed workloads still recycle.
Process identity is checked across all warmup/measured reports. All 48 focused
lifecycle/worker tests, 23 comparator tests and 11 executor tests pass. The
corrected diagnostic covers four codec-paired cases with RawSocket/WebSocket,
Dart/native, clear/TLS and all three construction groups. It completes three
warmup and seven measured passes, 40 reports per codec. Source is explicitly
dirty/diagnostic and windows are below policy; the 370 comparison findings remain
failures. Rust driver/native builds precede execution; no build/test/mutation/model
job overlaps the measured run. Evidence: `/tmp/connectanum-flatbuffers-campaign-diagnostic-02`,
`/tmp/connectanum-flatbuffers-campaign-worker-reuse-tests.{log,exit}` and
`/tmp/connectanum-flatbuffers-campaign-rust-tests.{log,exit}`. The complete default
schedule is prepared in the isolated Linux fixture: 48 cases and 1,440 rows,
without claiming execution of that primary matrix. Companion review's duplicate
RSS-stop concern is disproved by the cached stop future and its identity test;
the GLM judge finds no blocker once stable PID attribution is confirmed.

Both hosted Fast Checks on `87688b8c` pass, confirming the runtime repair. PR
consumer/browser coverage, package publish dry-runs, FlatBuffers binding,
GuardMalloc and several mutation gates also pass. Other required jobs are still
running or queued. Hosted checks for the campaign commit remain pending;
no new milestone issue is closed.

## Shared-runtime test teardown (2026-10-06)

The preceding follow-up fixes the Linux benchmark test runtime leak at `1aafa099`.
Its hosted Fast Checks job failed eight cases after the new native E2EE factory
tests left the process-wide client runtime running. Provider release frees keys
and sessions; it does not shut down that shared runtime. A same-process Linux
reproducer fails six accounting cases. Adding the existing factory-test
`NativeClientRuntime.shutdownShared` teardown makes all 39 factory, accounting,
router-config and remote-auth cases pass, with no native skips. All 1,498 full
Linux benchmark cases now pass, also without native skips. The fresh repository
baseline and full `bin/verify` pass at exit 0. Verification includes Rust, VM,
consumer smokes, 1,498 macOS benchmark, 4,935 router, 4,690 core browser and
2,829 client browser cases (20 declared native-only client skips).
Focused formatting and analysis pass. Companion teardown-order concerns were
checked against the test engine and runtime sources: per-test cleanup finishes
before group cleanup, provider release is synchronous, and construction failures
release partial handles. The repair is pushed to both remotes as `87688b8c`.

Both `1aafa099` hosted browser coverage jobs pass. The downloaded push artifact
is retained at `/tmp/connectanum-flatbuffers-ci-1aafa-browser-artifact`.
Both hosted Fast Checks jobs fail the same eight runtime-lifecycle cases;
their logs are retained separately. Seven strict package publish dry-runs pass
with zero warnings on that head. Required hosted acceptance of the teardown
repair remains pending; no additional milestone issue is closed.
Evidence: `/tmp/connectanum-flatbuffers-campaign-baseline.{log,exit}`,
`/tmp/connectanum-flatbuffers-ci-1aafa-runtime-leak-{repro,fixed}.{log,exit}`,
`/tmp/connectanum-flatbuffers-ci-1aafa-linux-bench-fixed.{log,exit}` and
`/tmp/connectanum-flatbuffers-ci-runtime-teardown-verify.{log,exit}`.

## Metric-validation checkpoint (2026-10-06)

The preceding follow-up repairs benchmark copy-report validation and missing VM
isolate handling on top of pushed checkpoint `dbeda203`. Fresh `bin/test-fast`
passes; all 60 focused cases and six fail-first regressions pass after the repair.
Linux benchmark coverage passes its unchanged 98% target at 98.219%; fresh
browser coverage passes both gates. Fresh full `bin/verify` passes at exit 0,
including Rust, VM, consumers, 1,498 benchmark, 4,935 router, 4,690 core browser
and 2,829 client browser cases (20 declared native-only client skips).
The unchanged native implementation retains the 70-case GuardMalloc evidence
from the ordinary-routing checkpoint below.
Hosted CI at `dbeda203` failed both VM coverage jobs because benchmark coverage
was 97.404% against its unchanged 98% gate. One browser job exceeded its 900-second
command limit; the same-head PR browser job passed all coverage gates. These are
different failures from the preceding-head runner shutdowns. Package publish
dry-runs remain pending. No paired performance campaign or parity result exists.

## Coverage repairs and master synchronization (2026-10-06)

Both remotes resolve current `master` to `3bac4cf5`, already an ancestor of the
working branch. The user-requested merge check reports `Already up to date`.

The [push coverage run](https://github.com/konsultaner/connectanum-dart/actions/runs/37382280300)
and [PR coverage run](https://github.com/konsultaner/connectanum-dart/actions/runs/37382287625)
agree on the benchmark VM coverage shortfall. The PR browser artifact passes
core 96.136% and client 96.430%; the push job continued completing crypto tests
until the whole-suite deadline expired. The core command now has a bounded
1,200-second limit, with a 30-minute job budget for both suites and report upload.
Per-test deadlines, full suite selection and coverage policies are unchanged.

A separate six-case reproducer proves that missing boundary metadata can claim
complete copies, negative/fractional counts can be accepted, NaN/infinity can
crash aggregation, and a system-only VM process can throw on an empty application
isolate list. Reports now require explicit valid boundary metadata and exact,
finite, nonnegative byte counts. Invalid counts stay unmeasured; known router
copies remain a lower bound. Isolate fallback safely returns no application ID.
The reproducer now passes. Sixty focused tests pass, including native/Dart typed
E2EE factory interoperability, direct profile/construction rejection before any
session opens, malformed payload correlation and incomplete/TLS metric reports.
Focused analysis and all 80 verification-script tests pass. Companion review
claims were checked against source: nonempty application fallback is unchanged,
native tests resolve the test-enabled artifact and did not skip, malformed
identity tests explicitly assert false, and missing TLS totals remain unmeasured.
Evidence: `/tmp/connectanum-flatbuffers-db-ci-baseline.{log,exit}`,
`/tmp/connectanum-flatbuffers-metrics-{fail-first,regressions-fixed}.{log,exit}`,
`/tmp/connectanum-flatbuffers-ci-{focused-tests,script-tests}.log`.
Fresh macOS benchmark coverage collects all 1,498 passing cases. Its 97.043%
report leaves Linux process-stat paths unexecuted. Linux arm64 passes all 60
focused cases and 1,496 full-suite cases plus the two router-config cases after
repairing the isolated fixture. The initial fixture contained AppleDouble files
that the Dart test loader tried to decode; removing those generated files repaired
discovery. The full Linux attempt then found the missing `bench_router.json`;
restoring the checked-in config and rerunning those two cases passes. These
fixture failures are preserved separately from implementation evidence.
The combined Linux benchmark report covers 2,923/2,976 lines (98.219%) with no
benchmark-specific policy failure. The unchanged whole-repository policy rejects
missing non-benchmark data in these benchmark-only reports; this is a targeted
benchmark measurement, not acceptance of the full VM coverage job.
Fresh `bin/test-browser-coverage` passes at exit 0: core 96.136% and client 96.430%,
with the full suites, existing thresholds and 20 declared native-only client
skips. Evidence: `/tmp/connectanum-flatbuffers-ci-bench-coverage.log`,
`/tmp/connectanum-flatbuffers-ci-linux-bench-coverage-clean.log`,
`/tmp/connectanum-flatbuffers-ci-linux-bench-fixture-repair.log`,
`/tmp/connectanum-flatbuffers-ci-linux-bench-{lcov.info,summary.json}` and
`/tmp/connectanum-flatbuffers-ci-browser-coverage.{log,exit}`.
Fresh full `bin/verify` also passes at exit 0, including 4,682 core VM, 4,935
router, 1,498 benchmark, 4,690 core Chrome/Dart2Wasm and 2,829 client browser cases
(20 declared native-only client skips).
Evidence: `/tmp/connectanum-flatbuffers-ci-verify.{log,exit}`.
No additional milestone issue is closed; hosted acceptance for this follow-up
remains pending.

## Ordinary CBOR/FlatBuffers routing and JSON input ownership (2026-10-06)

Native envelope replacements for INVOCATION, RESULT, EVENT and ERROR now reuse
ordinary CBOR arguments and keywords in both CBOR/FlatBuffers directions.
Optional ABI v1 queries borrow the source message and check destination codec
eligibility. CBOR-to-FlatBuffers validates the pinned container bounds and shape
without reconstructing application collections. The send rechecks the actual
native connection before enqueueing; incompatible attempts preserve the source
handle and emit no bytes. Cross-worker destinations can now use this path.
PPT/transparent payloads retain their existing behavior. Custom INVOCATION
options still select the existing metadata-preserving envelope path; a reproduced
test failure caught and repaired the overly broad non-progressive fast path.

The live mixed-codec tests exposed JSON's mutation of caller-owned binary List/Map
entries into Base64 strings. Removing that redundant mutation preserves typed
and immutable Uint8List containers and allows later FlatBuffers encoding.
A second fail-first regression found repeated materialization of a transfer
inside shared container aliases. A payload-local identity cache now shares its
encoded value across arguments and keywords. TransferableTypedData remains
one-shot; the cache neither extends its lifetime nor promises subsequent reuse.

macOS passes 87 focused native/routing/PPT cases and 29 JSON ownership regressions.
Native pointer/subrange oracles cover four argument shapes and five replacement
envelopes in both directions. GuardMalloc passes 70 observed cases. Linux arm64
passes all 12 forwarding tests and the real network test's 20 RawSocket and
masked/fragmented WebSocket scenarios. Linux passes all 116 focused Dart cases,
including the older-library fallback without missing-native skips.
The broader Linux runtime attempt was stopped while an unrelated existing slow
external-lease network test was still running; it is incomplete evidence.
The initial local full verification was stopped after finding the transfer-alias
regression. The next run passed VM, native, router and benchmark checks but
failed 14 browser cases because TransferableTypedData is unavailable there.
These alias tests now declare `testOn: 'vm'`, matching the existing serializer
tests; all 15 byte-container regressions pass in Chrome/Dart2Wasm. Fresh full
verification on that test-platform correction passes at exit 0: 4,682 core VM,
4,935 router, 1,456 benchmark, 4,690 core browser and 2,829 client browser cases
(20 native-only client skips). Linux's repeated
root-level parallel invocation also exposed the native runtime's global singleton
test conflict; all 116 cases pass with the router's prescribed concurrency 1.
Evidence: `/tmp/connectanum-flatbuffers-cbor-routing-`
`{dart-live-final,linux-native-focused,linux-dart-platform-serial,verify-platform-final}.log`,
`/tmp/connectanum-flatbuffers-json-{immutability-platform-final,immutability-browser-final,ttd-alias-tests-repro}.log`,
and `/tmp/connectanum-flatbuffers-cbor-routing-guardmalloc/report.json`.
Companion review findings were checked against source and tests: negotiated
connection codecs are immutable, native submission revalidates the destination,
recursive JSON output construction already existed, and transparent wire
encoding is unchanged. No additional issue is closed. #100 still needs complete
copy attribution; SDK, masking, TLS and other codec conversions remain unknown.

## Portable crypto copies and typed XSalsa size repair (2026-10-05)

The portable AES provider writes directly into its final nonce-prefixed output;
the CBOR providers avoid redundant plaintext and outbound ciphertext clones.
Optional isolate-local workload windows record explicit portable-provider copies
separately from native staging and FFI bridges. They include the remaining mutable
XSalsa output wrapper and successful/partial failed ciphertext-list coercion.
Crypto dependency internals, native-provider coercion, other isolates and
serializer/framing copies remain unknown; E2EE totals still fail closed.

An authentic 2 MiB typed XSalsa input exposed pinenacl's implicit 1 MiB receive
wrapper cap, despite the declared 64 MiB profile. The typed provider now uses the
public explicit-length body wrapper and nonce API with the same primitive and
existing profile preflight. Old-limit/next-byte/2 MiB cases, all truncated
nonce/tag lengths, tampering, sliced inputs and native/portable 2 MiB parity pass.
The CBOR receive behavior is preserved. Explicitly identical peer codecs now
report homogeneous routes; genuine CBOR-to-JSON transcodes stay unmeasured.

The fresh baseline `bin/test-fast` passed. macOS focused crypto tests and all 82
native-provider cases pass; Linux arm64 passes 234 focused cases and five live
worker scenarios. A full verification started before finding the size defect was
terminated, with its partial log retained; the final implementation's fresh
`bin/verify` passes at exit 0, including 1,456 benchmark tests, 4,923 router tests
and Chrome/WebAssembly (4,675 core; 2,829 client with 20 native-only skips).
Current-head hosted checks remain queued; the older run ended cancelled.
Evidence: `/tmp/connectanum-flatbuffers-portable-crypto-`
`{focused-final,provider-final,linux-focused-final,linux-live,verify}.log`,
`/tmp/connectanum-flatbuffers-xsalsa-{large-repro,limit-test-repro,limit-final}.log`.
No additional issue is closed and no parity result is accepted yet.

## Native crypto staging and typed benchmark profiles (2026-10-05)

XSalsa now constructs its unchanged nonce/tag/ciphertext wire format with detached
in-place crypto. It avoids the previous payload shift and second output copy;
copied decryption stages only the ciphertext body. An independent optional metrics
ABI v1 records actual native plaintext/ciphertext staging, including authentication
failures. Dart snapshots also count this runtime isolate's explicit crypto FFI
copies. Unknown or older metric ABIs leave native fields unavailable safely.

The benchmark worker and Rust orchestrator accept explicit typed FlatBuffers E2EE
RPC/pub-sub with all three construction modes, select the matching Dart/native
version-2 provider, and retain the existing CBOR default. Typed E2EE file transfer
is rejected. Known staging counts remain a lower bound with explicit process and
isolate scopes; serializer/framing, Dart crypto and other isolate bridges remain
unmeasured. Encrypted rows retain `e2ee_copy_bytes=not_measured`; the declared
comparison policy/evaluator rejects incomplete totals or an encrypted exemption.

Four native crypto compatibility/copy-oracle tests pass on macOS and Linux arm64.
Both platforms pass 82 native-provider tests and the two live 64 KiB encrypted
typed RPC metric cases. Four benchmark metric tests, 65 runner tests and 15
comparison tests pass. Full `bin/verify` also passes, including all 1,452 benchmark
cases. Evidence: `/tmp/connectanum-flatbuffers-crypto-verify.log`,
`/tmp/connectanum-flatbuffers-crypto-guardmalloc-final/report.json`, and
`/tmp/connectanum-flatbuffers-crypto-linux-{native,provider,live}.log`.

Earlier Linux CI at `b5ab660c` failed Full Verify and Dart VM Coverage because
two native benchmark test files ignored the test-enabled artifact under
`target/ffi-test/release` after the runner cleared `CONNECTANUM_NATIVE_LIB`.
A clean Linux arm64 fixture reproduces the same five failures. Commit `ecaa43d4`
resolves the artifact explicitly; all 14 focused cases then pass with no skips.
The earlier Rust churn failure passed on retry. These are local repair results;
hosted acceptance still needs the resulting feature head. Issues #100–#104 remain
open, including SDK/TLS/transcode copy coverage and the missing paired campaign.

## External-loan terminal-path acceptance (2026-10-05)

The native transaction-like producer now proves release exactly once on its
registering thread after a successful write whose receipt observer was disposed,
a real bounded transport queue rejection, missing-destination rejection, and
fan-out interrupted by peer reset, local connection close or runtime shutdown.
RawSocket and WebSocket cases consume and verify a payload prefix before
termination, proving partial progress. No caller-held view masks writer retention
in the successful unobserved-send and queue/cancellation cases. Shutdown keeps an
independent exported view readable until its final release. Existing lease and
ABI tests cover construction-failure rollback, byte/count limits, wrong-thread
operations and safe rejection by older/incomplete libraries.

The ownership documentation distinguishes legacy event-loop `drain()`, FIFO
`drainWrites()`, observer disposal and final producer cleanup. The implementation
is storage-agnostic; ObjectBox integration remains outside core. Local evidence:
`/tmp/connectanum-flatbuffers-97-{fast,verify,native-network,memory-runner}.log`
and `/tmp/connectanum-flatbuffers-97-guardmalloc/report.json`. Issue #97 is
complete; hosted conformance/release acceptance remains under #102/#104, and
unmeasured SDK/TLS/transcode copies plus missing performance evidence keep #103
open.

## WAMP RSS window-boundary correction (2026-10-05)

The benchmark RSS sampler now waits for an in-flight periodic read and takes a
final sample before returning both current and sampled-peak RSS from that same
window boundary. Client and server records use that snapshot before VM profiling
queries can add work outside the measured window. Server diagnostics retain an
end-of-workload `ProcessInfo` value on non-Linux platforms; Linux rows remain
missing when `/proc` cannot supply the boundary sample. A deterministic
delayed-reader test covers the race and idempotent stop. `bin/test-fast` and
full `bin/verify` pass at exit 0 on the RSS race correction. After the
non-Linux diagnostic fallback refinement, the focused metrics suite and
`dart analyze packages/connectanum_bench` also pass. An 8-workload Linux arm64
smoke over RawSocket/WebSocket and JSON/MessagePack/CBOR/FlatBuffers emits numeric
client/server RSS with current RSS no higher than sampled peak. It is a short
wiring smoke (640 samples per workload), not parity evidence. The smoke also
confirms the existing Dart-managed transport-copy `not_measured` blocker; no
benchmark rows are accepted. At that checkpoint all milestone issues were open.
This correction is in pushed checkpoint
`e1ee796a`; exact-head hosted CI evidence remains pending.

## Dart transport-copy attribution follow-up (2026-10-05)

The Dart benchmark worker now records Connectanum-owned RawSocket frame
assembly, small-fragment coalescing, pre-handshake queue, and WebSocket fragment
coalescing copies per workload window. The report identifies uninstrumented SDK
socket writes, WebSocket masking, and TLS copies. `bench_main` merges client and
router deltas and reports numeric `transport_copy_bytes` only when both sides
have complete cleartext coverage. The paired evaluator rejects missing/partial
coverage, unknown boundaries, and not-applicable transport totals. Focused
metric/evaluator tests and `bin/test-fast` pass. Dart SDK write/masking
internals, TLS copies and mixed-serializer transcodes remain unmeasured; no
parity campaign exists, so issue #103 and issues #97, #100–#104 remain open.

## Native transport copy-counter follow-up (2026-10-05)

Commit `f7387de0` adds optional C/Dart FFI snapshots for native transport
copies, counting explicit Dart-to-native send copies, WebSocket mask and
coalescing payload copies, and Rustls plaintext accepted bytes. The Rustls
counter reports accepted input volume, not a measured memory copy. Client and router
benchmark snapshots use before/after deltas and combine their measured native
path traffic. Focused Rust tests, client metric-delta tests and package analysis
pass. A fresh `bin/test-fast` passes, including the release FFI build and live
RawSocket/WebSocket WAMP matrix. Full `bin/verify` also passes, including the
Chrome WebAssembly, WAMP, consumer and smoke checks. A paired campaign
evaluator and machine-readable relative parity policy now have eleven focused
unit tests. A working-tree follow-up adds two-process resource accounting and
matching evaluator tests; it requires client plus benchmark-server evidence and
rejects missing metrics. The evaluator does not execute benchmarks or create a
result.
Dart-managed socket/TLS paths and mixed-serializer transcodes remain
unmeasured, so this is partial attribution only; issue #103 remains open and
no FlatBuffers parity or end-to-end zero-copy claim is accepted.

## WAMP benchmark process-resource attribution follow-up (2026-10-05)

The comparison evaluator previously used only the client worker for CPU,
allocation, GC and peak RSS even though the WAMP server runs in a separate Dart
process. Its resource ratios now require both `client_process_metrics` and
`server_process_metrics`, retaining both blocks and comparing combined CPU,
allocation and GC pause per operation plus summed sampled peak RSS. The server
block describes the process hosting `RouterBinding` and the HTTP benchmark
controller. Each workload gets one throwaway warm-up operation before the server
measurement window so lazy router isolates exist before profiling starts. The
collector profiles every application isolate present when the window begins
and fails closed if that set changes or GC timeline evidence is incomplete.
Process CPU ticks and RSS sampling use Linux `/proc`; missing platform metrics
block the row. Eleven focused evaluator tests pass, as do the Rust orchestrator
test target and Dart isolate-selection tests. A live macOS smoke run emits both
process blocks and allocation/GC metrics, while CPU/RSS remain missing as
expected. The benchmark campaign still has no generated manifest or measured
parity result, and the Dart-managed TLS/socket and mixed-codec copy paths remain
unmeasured.

## Session native-owned typed FlatBuffers PPT path (2026-10-05)

`NativeOwnedBuffer.asFlatBuffersPptPayload()` now lets an application pass an
already encoded typed FlatBuffer to `Session.callLazyPayload` or
`Session.publishLazyPayload`. On an established native FlatBuffers session, an
opaque typed PPT CALL/PUBLISH retains the exact frozen payload owner in a
composed native frame. Profile checks run before the fast path; only the WAMP
control envelope is rebuilt. The normal path remains for transparent WAMP
payloads, other serializers, encrypted PPT and ineligible payloads. This keeps
application payload bytes out of Dart serialization buffers on the eligible
path; later transport framing, masking, TLS or encryption may still copy.

RawSocket and WebSocket integration tests verify nested lazy-owner anchors,
session/profile enforcement and immediate disposal of the caller's buffer after
queueing. The benchmark runner now passes native-buffer and pre-encoded
FlatBuffers payloads through the same owned-view API. A new 12-case live matrix
covers native RawSocket RPC/pub-sub, FlatBuffers WAMP envelopes, all three PPT
serializers and two owned construction modes over two iterations. A runner unit
test checks exact view/owner identity and cleanup after a rejected call. Core
tests verify control-only encoding does not read the lazy payload. Both
`bin/test-fast` and full `bin/verify` pass on the current candidate, including
Chrome WebAssembly, live WAMP integration and consumer smoke checks. These are
correctness and ownership results, not end-to-end throughput evidence; no
FlatBuffers-versus-CBOR/MessagePack parity result is accepted, so issue #103
remains open. At that checkpoint, all ten milestone issues remained open pending
their acceptance evidence.

## Checkout and authorization

The managed worktree uses `codex/flatbuffers-zero-copy`; the native Session
fast-path implementation is committed and pushed as `f569e9b4`, following
`274df37c` and `152898d7`. The benchmark-runner integration is committed and
pushed as `9620cfbe`; `bin/test-fast` and full `bin/verify` pass at that
checkpoint. The external-lease test follow-up is committed and pushed as
`a28e92c4`. Its hosted run exposed the two CI defects described above; local
corrections now pass `bin/test-fast`, full `bin/verify`, and both mutation
inventory validations. These corrections are committed in `f7387de0`; fresh
exact-head hosted checks are running. Earlier exact-head hosted runs reported
Fast Checks failures on `274df37c`. It started at
`54eafc5f` and integrates released master `3bac4cf5`. The primary checkout's
independent work remains untouched.
Feature commits, pushes and draft PR updates are authorized; releases, version
bumps, publication and merging master are not authorized. Actual ObjectBox
integration belongs in a separate adapter. Core provides generic memory
contracts. The earlier coverage/mutation objective is deferred.

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

## Typed benchmark runner groups (2026-10-05)

The current follow-up adds the three typed payload-construction groups to the
Dart WAMP runner and passes `payload_construction` through the Rust TOML
orchestrator. Typed RPC/pub-sub samples now retain payload-preparation time and
native-builder input/growth copy counters. A live correctness matrix passes all
18 combinations of RPC/pub-sub, FlatBuffers/CBOR/MessagePack PPT, and Dart
values/native buffer/pre-encoded span, on RawSocket with a Dart caller and CBOR
WAMP envelope. A separate 12-case integration matrix exercises typed FlatBuffers
PPT across both transports, callers and outer serializers; it does not use the
new runner groups. A focused owner test proves that a native payload remains live
through the RPC result and is disposed during runner cleanup. Rust orchestration/
report tests pass (181 tests); package analysis and `bin/verify` pass at exit 0.
These counters cover payload construction only, not total codec/transport copies.
Paired performance, confidence intervals, CPU/memory evidence and exact-head
hosted acceptance are still pending; do not claim parity or close issue #103.
Eligible native-buffer and pre-encoded FlatBuffers typed-PPT sends now use the
Session-owned-view path; other serializers and ineligible payloads keep their
normal behavior. This closes the #96 implementation boundary. #103 remains
open pending complete copy coverage and the paired parity campaign.

## WAMP process-resource attribution verification (2026-10-05)

The server-process resource attribution follow-up passes `bin/test-fast` and
`bin/verify` at exit 0 on this worktree, including browser/WebAssembly tests,
live WAMP transport matrices and consumer smoke checks. The comparator's eleven
unit tests, Dart VM process/isolate tests and Rust `http_stream` tests pass. A
live macOS one-workload smoke confirms both client/server metric blocks and
server allocation/GC collection; macOS lacks the Linux `/proc` CPU and RSS
evidence required by the parity gate. This is correctness evidence only. There
is no paired FlatBuffers performance campaign, so issue #103 and milestone
acceptance remain open. Exact-head hosted CI is pending the current commit.

## Issue acceptance audit (2026-10-05)

Issues #95–#99 are closed as completed. #95's pinned binding, generation
workflow, metadata/schema policy, negotiation rules, fixture coverage and
WebSocket identifier registry status are recorded in `flatbuffers_binding.md`
and checked by the FlatBuffers Binding workflow. #96's Rust-owned builders,
send/transfer contract, allocation identity, copy counters, error transitions,
ABI fallback, finalizers and explicit disposal are covered by the native buffer
API, ownership guide and tests. #98's Dart serializer and #99's native codec,
transport negotiation, auth, fragmentation and TLS paths passed full local
verification. #97's producer-thread cleanup and asynchronous terminal paths are
verified separately above. Issues #100–#104 remain open; #103 still lacks the paired
parity campaign and copy coverage for SDK masking, TLS and mixed-serializer
conversions.
