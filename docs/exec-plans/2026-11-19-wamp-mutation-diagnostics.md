# WAMP and Mutation Diagnostic Repair

Status: active.
Started: 2026-11-19.
Base: `0a3d96e663363e8d1830baeb127cf4e33c6bbf41` (`github/master`, merged PR #138).
Branch: `codex/fix-wamp-mutation-diagnostics`.

## Objective and acceptance

Repair the WAMP and mutation diagnostic failures and prove the complete final
workflow inventory green. Preserve all numeric thresholds, 95% assertion gates,
complete mutation inventories/operators, existing tests, workload sizes,
repetitions, deadlines, queue bounds, warm-up/drain intervals and evidence rules.
Do not hide failures by disabling diagnostics, filtering survivors, or adding
unproven equivalence/exclusion entries. Production GC/allocator tuning is outside
this repair. Preserve unrelated work on `codex/mutation-runner-speed`.

- [x] Complete fresh-master `bin/test-fast` baseline.
- [x] Reproduce each failure with a focused regression or minimal matched case.
- [x] Fix native restored-baseline failure and demonstrate complete clean inventories.
- [ ] Fix full MessagePack VM/web and MCP/CLI diagnostic assertion failures.
- [x] Fix WAMP fragmentation/file-transfer throughput against original floors.
- [ ] Run focused validation, local companion review and complete `bin/verify`.
- [ ] Publish a reviewable branch/PR and run all diagnostic and regular workflows.
- [ ] Audit every final workflow/job, with no unresolved failed required work.

## Original evidence

Merge `0a3d96e6` passes all 55 mandatory CI jobs, all sixteen gateway shards,
ObjectBox, package dry runs, kTLS validation and the standard WAMP benchmark.
Its diagnostic workflows remain red:

- WAMP run 44530794223: fragmentation and file-transfer gates each report five
  findings against unchanged 2,000-Mbps floors. Payload-mode throughput also
  crashes at the large CBOR PPT RPC (`NativeByteSnapshot.toCbor`), then times
  out. Both heavy file-transfer and RawSocket gates pass.
  Artifact 14533488631 digest:
  `31f8796d855f6d190cd6eaa62743a8563dd841862de31306e7683e01fb7a02e2`.
- Mutation run 44530794131: four native jobs fail restored-baseline validation;
  MessagePack VM/web scores are 3.1111%/88.4444% against 95%; native MCP CLI
  adjusted score is 68.9773% against 95%. E2EE web is cancelled and the full MCP
  job is still running at initial inspection. No incomplete result is accepted.
- Read-only audit: `/tmp/connectanum-master138-ci-audit-20261119.json`.
  Bounded GLM triage: `/tmp/connectanum-master138-compact-triage-20261119-result.txt`.
  These logs establish failure signatures, not an SDK regression or matched
  performance cause. Ollama's first broad triage timed out; the independent GLM
  triage completes and is checked against raw logs.

## Working record

### Restored MCP smoke requires its service event, not any nonempty batch

Main CI run 44727893379 at `8a9fbc0c` completes all 55 jobs successfully.
Both WAMP workflows, strict kTLS, three-platform ObjectBox and package dry runs
also pass. Complete WAMP diagnostics run 44727980355 passes all eight original
scenarios / 117 workloads on its first attempt. Full MessagePack VM artifact
14625411583 has verified ZIP SHA256
`b31ecf81e2067cc80650fec761ef069f3e2c943270c4e3f1d10cb4e960db7c9a`;
all 204 outcome log hashes and input pins match the independent frozen campaign.
Its 183 assertion-only kills, nine compile errors and four separately proven
functional equivalences produce 95.8115183246% against the unchanged 95% gate.

Complete mutation run 44727972644 exposes one further failure in MCP shard 17,
job 136260932691: the clean baseline passes and all 71 assigned mutants execute,
but the restored baseline fails. Its original artifact 14632161670 has ZIP
SHA256 `96fd9c55baf2d8a3dd1a88c681ed68c1667ba510fd79711b93c5426afa2cf8b3`.
All 122 failure messages derive from one shared public-router smoke reporting
that the Streamable pub/sub batch lacks the expected service event.

The helper returns its first nonempty batch, although the four callers require
a specific service publication after independent MCP and service publishes.
The publisher batch can arrive first. Extracting the unchanged original loop
and injecting those two batches deterministically fails the new regression.
The corrected predicate waits for exactly the task ID already required by each
caller's unchanged postcondition. The original twenty polls, 25-ms delay,
request IDs, SDK deadlines, headers and direct/Streamable routing are preserved.
The overflow caller retains its original nonempty-batch behavior and every
queue/drop/remaining/newest-event assertion. No mutation-runner retry is added.

Four focused tests cover split batches, exhaustion after exactly twenty polls,
success on the twentieth poll and preservation of a transport error. All four
and all 129 real native CLI integration tests pass; focused analysis and diff
checks are clean. The small callback seam belongs to the example executable,
with no package-library API or dependency change. MCP/CLI test/support hashes
change, so a new complete same-commit campaign is required; old shard results
will not be mixed into its aggregate.

Frozen `580a599a` completes `bin/verify` at 13:25:01 UTC after starting at
13:02:09, with all 3,192 source/lock hashes and HEAD unchanged and clean status
before/after, including real Chrome/Dart2Wasm. Its complete `bin/test-fast`
also passes before the repair is transferred from an isolated checkout.
The new smoke repair postdates that frozen proof and requires a fresh one.
Local Qwen debugging/test planning/review resumes once the separate native
campaign releases its resource lease; advisory findings are verified against
complete source and actual test outcomes.

### Codecov patch coverage reproduces an SDK forwarding test gap

All local verification and the five completed current workflow families pass,
but external Codecov check 136284507056 reports 77.67% patch coverage against
the unchanged 94.20% target. This is not a pending partial upload: the workflow
uploads exactly its Dart VM LCOV; browser/application reports are retained as
artifacts. The official Codecov report API and the exact merge-base diff
independently reproduce 748/963 (77.6739356179%). Overall reported coverage is
94.47%; the patch denominator identifies the narrower issue.

Of 215 changed executable-line misses, 188 are in
`byte_frame_http_client_io.dart` (37/225 lines hit). The native receive coalescer
already has 135/135 hits. Original CI artifact 14628007728 has verified ZIP
SHA256 `9be882f2f608bac09c634b8cd21a36e4f0a03aa30b0360960575f1c3a3b5ec78`.

Seven additional contract tests exercise all fourteen real HTTP verb/URI
entry points with headers, cookies and bodies, client timeout/connection
configuration, authentication/proxy/TLS callbacks, actual sink encoding and
error events, request abort/completion, response metadata and redirect wrapping,
compression bypass and detached socket options/endpoints/close lifecycle.
They register through the existing VM WebSocket test entry point, so the
unchanged explicit fast/full/coverage launchers execute them. All 61 combined
WebSocket cases pass and focused analysis reports no issues.

The actual new LCOV hits all 225 adapter lines. Merging measured hits into the
unmodified original CI line inventory adds exactly 188 hits, estimating 936/963
(97.1962616822%), above the unchanged Codecov target. This is an estimate until
the fresh hosted upload; no threshold, ignore rule, production source or
denominator is changed. Existing mutation-selected sources/tests/support and
native source pins remain unchanged by this additional contract coverage.
That coverage-only change preserves the campaign's inputs. The subsequent
smoke correction above changes MCP/CLI support and requires a new full campaign.

Local summarization and GLM test-planning initially refuse inference while
another native mutation campaign holds the resource lease. The lease is
respected; direct source/SDK inspection and executable contracts provide the
initial review, with local companion review resumed after the lease ends. The public SDK `ConnectionTask.fromSocket` is used, preserving its
socket future and cancellation callback without mocking its final type.

### Public iterable counterexample corrects an equivalence proof

The additional audit finds a genuine counterexample to the growability waiver.
`Iterable.toList` is virtual: a valid override records its `growable` argument
and delegates to the standard conversion, preserving elements and order. A
nested readonly Map exposes this public state. Original versus boolean-mutant
encodings differ in actual wire bytes (`mode: false` versus `mode: true`), so
the earlier claim that this list/options were necessarily private is invalid.
The portable public regression fails before repair (byte 194 versus expected
192) and passes after repair. The old MessagePack 95.288% calculation is an
algorithmic result under that rejected proof, not accepted qualification.

Non-List iterables now materialize with a direct collection-for snapshot. It
consumes the iterator once and exposes neither a conversion callback nor an
allocation option to input objects. List inputs retain their existing live
iteration behavior. The unnecessary growability flag and its invalid waiver
are removed together with the virtual conversion. All 204 current generated
candidates remain inventoried; the four remaining functional-equivalence
classes are re-pinned to the current source. No operators, tests or source
locations are filtered, and the 95% gate is unchanged.

All 191 VM, 191 real Chrome/Dart2Wasm and 206 Chrome/Dart2JS codec cases pass,
including the new wire/one-traversal regression. The bounded local semantic
review confirms the callback hole and private fresh-buffer copy proofs. Its
negative-private-offset concern is rejected by actual caller induction: public
decode starts at zero, private next offsets advance through positive headers
and unsigned lengths, and every availability-guard call has positive offset
and nonnegative length. The two existing private-boundary proofs still apply.

Obsolete `9a304a08` CI 44717335301 and mutation 44717614622 are cancelled;
the `52b103c0` campaign's four queued aggregate jobs are also cancelled.
Completed raw evidence is retained. Fresh complete current-source campaigns
and frozen `bin/verify` remain required; no cancelled run is treated as green.

### Complete earlier mutation unions independently audited

All 97 execution jobs at `52b103c0` pass; four final GitHub aggregate jobs
were queued before the later correction superseded the run. A separate checkout independently
regenerates each complete inventory. The unmodified checked-in merger audits
every downloaded original shard, raw outcome log, assertion classification,
baseline/restored-baseline digest and source/test/support/config identity.
Every ZIP digest matches its GitHub artifact metadata. The original same-run
Linux library is only hashed locally; its manifest, full Rust source pins,
build features/defaults and dependency-lock digest are verified. Its unchanged
SHA256 is `bc1c121766d97a2d5e1e068c7446961c6a31e014c6ddd3446f10c9539cefa7fa`.
These portable evidence audits do not rerun Linux native code on macOS or replace
the required current-commit GitHub qualification.

- Native CLI: all 16 shards / 1,162 candidates; 794 assertion-bearing kills,
  327 compile errors, 41 survivors and no equivalences. The 835 viable mutations
  yield 95.0898203593% against the original 95% gate. No kill is a pure test error
  or unknown failure. Audited report SHA256:
  `2c1c49134930778457f19d29f1ded8ca731619b423bd89953bf254301f8ab830`.
- Full MCP: all 32 shards / 2,263 candidates; 1,611 assertion-bearing kills,
  589 compile errors, 63 survivors and no equivalences. The 1,674 viable mutations
  yield 96.2365591398% against 95%, with no pure-error/unknown kills. Report SHA256:
  `04f25fa4e21bd09c330f66fc20a41299c09601c1afdc942f20b32010785f5830`.
- MessagePack browser: all eight shards / 205 candidates; 182 assertion kills,
  nine compile errors and 14 survivors, including five then-configured
  equivalences. The adjusted assertion calculation yields 95.2879581152% against
  95%; one equivalence is later disproved above, invalidating its qualification.
  No error/mixed/unknown kills occur.
- E2EE browser: all eight shards / 313 candidates; 245 assertion-bearing kills,
  59 compile errors, nine survivors and no equivalences. The unchanged metric
  yields 96.4566929134% against 95%, with no pure-error/unknown kills.

All 14 CLI and 49 MCP source/test/support pins match current `9a304a08` bytes.
Its changed native library and full workflow conclusions still require their
actual fresh campaign. No inventory, gate, classifier, equivalence justification
or original evidence is changed by these additional read-only audits.

### Frozen 9a304a08 verification and complete WAMP gates

The actual complete `bin/verify` passes from 10:13:17.762264 to
10:38:14.125746 UTC. All 3,191 input hashes, HEAD and clean status remain
unchanged, including real Chrome/Dart2Wasm. The normal WAMP diagnostic workflow
[44717600688](https://github.com/konsultaner/connectanum-dart/actions/runs/44717600688)
passes all eight original scenarios and 117 workloads on its first attempt.
Artifact 14620707462 has verified ZIP SHA256
`078b608da3a6190ac5edbf8cd25887353ac86f2de8a18d8ba9ff20d013f41d5c`.
Every summary row has workload and gate exit code zero. All 36 checked-in WAMP
scenario and policy files are byte-identical to merge `0a3d96e6`.
Regular WAMP 44717596346, strict kTLS 44717604963, all three ObjectBox platforms
44717609881 and package dry run 44717335495 also pass on the same commit.
Main CI 44717335301 and complete Mutation Diagnostics 44717614622 remain
pending; no incomplete aggregate score is accepted.

The initial paired investigation 44716920600 fails before measurement because
the detached baseline checkout lacks the ignored workspace lock. The corrected
helper copies the exact bootstrapped lock and enforces it for both workers.
Run [44717987869](https://github.com/konsultaner/connectanum-dart/actions/runs/44717987869)
then completes all four alternating baseline/candidate campaigns with frozen
sources, executables, locks, workloads and policies. Mean WebSocket file lifecycle
Mbps improves 2,636.24 to 3,035.94 CBOR (+15.16%), 2,705.07 to 3,028.69 MessagePack
(+11.96%) and 2,222.18 to 2,511.73 JSON (+13.03%). RawSocket controls vary -5.00%,
-8.93% and +0.25%. The six profiles retain every original byte count, iteration,
concurrency and chunk size; no runtime/compiler defaults change.

Its subsequent complete diagnostic run passes seven gates and retains one
native TLS JSON contiguous lifecycle finding, 1,925.994 below the original
2,000-Mbps floor. All eight workload commands complete successfully. Artifact
14620289257 has verified ZIP SHA256
`ceaca5cd4d1d86f4008de4cc1834ca2add868645a45f3e5568a9c0039424377b`.
Both this investigation and the normal passing PR workflow use Xeon 6975P-C-class
hosts. This residual additional measurement remains recorded; the normal run's
first-attempt success is not a claim that every hosted measurement will exceed
the floor. No faster-host retry, changed gate or host selection is used.

### Fresh Linux coverage and bounded SDK receive buffers

All 55 main CI jobs pass at `52b103c0`; its full mutation campaign remains
incomplete with no failed jobs at the latest inspection. Fresh native coverage
run [44705776522](https://github.com/konsultaner/connectanum-dart/actions/runs/44705776522)
passes the original Cargo and all 23 Dart FFI groups against frozen production
sources. Artifact 14615519326 has verified ZIP SHA256
`1e4c9fe984a8f6ce078b1d0b2c191147ab4569217ab5ec6b02dc0e9f2abf73c0`.
Combined actual macOS/Linux counts cover all 979 original MQTT statements.
Changed Rust sources use exclusively fresh counts. Four wholly byte-identical
sources retain their historical measured reports. The original 781 Core-lib
statement keys, original source archive and exact unchanged statement bytes
remain verified, with an independent unchanged-block mapping check.

The complete ReadBuf/alphabet candidate still fails 11 metrics on Xeon 8573C
in run 44706039812. Artifact 14615258699 has verified ZIP SHA256
`61cb4af865cab33a32cbe4aab5b0a90abf58400ace30491f040a03abeae5e33f`.
All eight workload commands complete; five gates pass. Fragmentation, file and
heavy file lifecycle/throughput findings remain actual failures.

The [SDK receive path](https://github.com/dart-lang/sdk/blob/3.14.0/sdk/lib/_http/websocket_impl.dart)
copies multi-part message bytes at FIN. A new synchronous bounded adapter gives
the SDK one privately owned native frame for eligible complete messages. It
retains original headers/payload slices and flushes exact originals for controls,
invalid headers, EOF, errors, oversized inputs and bookkeeping limits. Existing
SDK validation and original JSON provenance remain authoritative. Already
contiguous binary messages bypass the allocation. All 54 focused tests pass,
including real SDK backing-pointer identity, invalid-text close ordering,
fragment/header splits, pause/cancel, compression and subprotocol behavior.

The focused VM coverage report executes all 135 coalescer source lines. Client
analysis exits successfully with its existing 15 informational lints; all 29
package-publishing/proof controls pass. The bounded local review's proposed
stale-header issue is unreachable: every `flushPending` sets permanent
passthrough, so parsing never resumes with that state. Original malformed-header
split and prompt-forwarding tests cover this path. Native finalizer ownership
belongs to the backing buffer, independently of the metadata Expando.

Frozen alternating local comparisons retain the six exact original 64-MiB Dart
file profiles. The final candidate's mean WebSocket lifecycle Mbps increases
4.24% CBOR, 1.63% MessagePack and 1.93% JSON; RawSocket controls vary between
-3.04% and +1.76%. These small local changes are not hosted qualification.
An intermediate synchronous-hashing integration regresses and is removed;
its failed comparison remains available. No hashing dispatch or buffer-retention
change from that experiment is included.

Investigation run [44716920600](https://github.com/konsultaner/connectanum-dart/actions/runs/44716920600)
alternates baseline/candidate on the original six file profiles, then executes
all eight original diagnostic scenarios on the same default hosted runner.
All workloads, gates, timers and production runtime/compiler defaults remain
unchanged. This investigation branch is separate from PR #139; final current-ref
verification and the complete seven-workflow inventory remain required.

### Remaining EPYC findings and measured buffer costs

Frozen `52b103c0` completes `bin/verify` at 08:29:55 UTC with all 3,185
input hashes, HEAD and clean status unchanged. Its regular WAMP, kTLS,
three-platform ObjectBox and package dry runs pass. Complete WAMP diagnostics
44699790883 on EPYC 7763 report 15 findings: twelve fragmentation metrics,
one JSON file lifecycle metric and two 256-MiB RawSocket lifecycle metrics.
Artifact 14612946770 has verified ZIP SHA256
`6d998815262b56e1b1d02ded5b5d166ede3ba39a5b4747966cb963c842a46f53`.
The failed measurements remain distinct from the earlier passing hosts.

Unqualified user-space profiling run 44702026411 uses original workload
parameters, separate plain/sampled runs and frozen bundles/sources. Its
artifact 14613602977 has verified SHA256
`67f4e7d9a20f96033df1fe44db4ee40508439e0016604a89b04e3e5f288ac25a`.
On Intel Xeon 8573C, the fragmentation profile includes 1.56 seconds under
buffer acquisition's initialization; RawSocket payload construction consumes
4.18 seconds inclusive. These are measured costs, not a matched EPYC speedup
or qualification result. GNU gprofng uses clock sampling with hardware events
disabled, following children without compiler or kernel-security changes:
[primary manual](https://www.sourceware.org/binutils/docs/gprofng.html).

WebSocket payload reads now fill an empty pooled Vec through safe public Tokio
`take(len).read_buf` APIs, rather than zeroing the entire destination before
overwriting it. The original frame length, timeout scope, mask/control handling
and retained ownership remain. A regression fails before and passes after;
Pending, exact frame boundaries, masked sizes and partial/stale reads are covered.
All 435 Core tests pass. The alphabet fixture uses native String repetition
with identical bytes, sizes and timing boundaries; all 66 runner tests pass,
as do independent exact 4/64/256-MiB comparisons.

Qwen reviews and GLM judgment are advisory. GLM's oversized-buffer overread
claim is rejected against Tokio 1.54.1's bounded `Take::poll_read` implementation
and fourteen independent oversized-capacity cases retaining the next frame.
Its EOF owner-leak concern is covered by the existing Drop implementation and
the new partial-read recycle test. No unnecessary zeroing is restored.

Fresh complete Cargo and 23-group Dart FFI coverage measurements pass on macOS;
the instrumented library SHA256 is
`65b734f367673bda5c727ed51a4d3a34421763987cfd18d567ad4984de8aa37e`.
Fifteen original Linux-only MQTT statements require a fresh Linux measurement,
currently pending. The proof retains all 979 original statements; original Core
statement locations are checked byte-for-byte against a checksum-pinned archived
source with a monotonic one-to-one map. Changed source files receive only fresh
counts, and historical records apply solely to wholly byte-identical sources.
Do not qualify the new implementation until this proof and all workflows pass.

### Complete local verification and coverage ownership

The quiet frozen `bin/verify` at `840e144c` passes completely from
06:40:45 to 07:05:03 UTC: all 3,185 source/lock hashes, HEAD and clean status
remain unchanged. Real Chrome/Dart2Wasm also passes (Client 2,844 tests and the
20 existing native-only skips). All five additional workflow families on that
same commit pass: both WAMP workflows, kTLS, three-platform ObjectBox and package
dry runs. Main CI and the complete mutation aggregate remain unqualified.

Main CI's VM coverage job 136136750515 fails only component ownership: the
new shared validator is present in both MCP components, while the existing
checker requires exactly one owner. Its required-source entry and every
mutation scope remain. Coverage assigns it solely to the stricter 98% library
component, keeping the CLI entrypoint at its unchanged 93.4% floor. No floor,
required source, operator or test is removed; the exact-one-owner checker is
unchanged. A real-policy regression fails before and passes after the fix.

The checksum-verified CI artifact 14611972292 has ZIP SHA256
`9b99a99fbd3867516ba57130dd37ad5b20247b62e3259b1b3c7b400b32c73176`.
Replaying its identical LCOV bytes with the corrected policy passes all gates:
library 1,692/1,703 = 99.354%; CLI 2,188/2,217 = 98.692%. The production sources
and measured hit counts are unchanged. All 26 coverage-tool, 95 mutation-runner,
87 script-contract and 24 package-boundary tests pass (one existing host skip).
A fresh final CI run is required; the old red job is preserved as evidence.

### Complete component manifests and full WAMP pass

The next frozen verification at `7d918b38` keeps all 3,185 inputs unchanged
and detects a missing component assignment: `mcp-library` intentionally covers
all MCP library sources except the CLI entrypoint, so it must also contain the
new shared validator. The module is added to both its mutation source list and
matching coverage component; existing CLI/full-MCP scopes remain intact.
No source exclusion, floor, operator or test is removed. The inventory guard
also retains the newly added router smoke-evidence test in both full suites.
All 95 mutation-runner tests now pass (one existing host-specific skip), as do
the remaining six tooling suites. Earlier tooling suites passed in the full
run; the current complete frozen verification still remains outstanding.

Complete WAMP diagnostics run 44685867822 at `f25b8de9` passes all eight
original scenarios, including every fragmentation, buffered/heavy file and
large RawSocket floor. It runs on an AMD EPYC 9V45 host, distinct from both the
older EPYC 7763 failure and Intel matched study. Its artifact 14607200587 ZIP
SHA256 is verified as
`3bbae2a3cb05070abbd84e9a77eb57bdb03b30c4da19cafc29134b70c7e43dbe`.
The regular WAMP workflow, kTLS, all three ObjectBox platforms and package dry
runs also pass at that revision. Preserve the older hardware observations;
main CI, complete final mutation scores and final local verification remain
pending. The global component-config hash changes, so final mutation receipts
must be collected again rather than reusing an old aggregate.

### Frozen verification and heterogeneous-runner findings

The quiet frozen `bin/verify` at `f25b8de9` fails in one package-boundary test
with 13 subcase failures. All 3,185 tracked/source/lock hashes and HEAD remain
unchanged; the rejected receipt is
`/tmp/connectanum-diag-frozen-verify-f25b8de9-20261120/receipt.json`.
The static test still searches for validators and messages in their previous
CLI file. It now preserves each original invariant in its actual source file,
asserts the module import, definitions and CLI delegation, and retains public
package-boundary checks for the shared module. All 24 boundary tests pass.
The token-audited production validators and their mutation scope do not change.

Complete WAMP run 44684683569 at `760bcc9a` remains red: ten native TLS
fragmentation findings, WebSocket JSON file lifecycle 1,895.396 Mbps, and native
256-MiB RawSocket JSON/CBOR lifecycle 1,781.405 / 1,706.214 Mbps. Five complete
scenarios pass, including heavy file transfer. Artifact 14606561889 ZIP SHA256
is verified as `c3700f179867dc6095a740804fccaf4e01b91acc1c7bdd4e368ae65f68456378`.

This runner is AMD EPYC 7763 (Azure), whereas the passing matched file study is
Intel Xeon 6975P-C (KVM). The library's production Rust sources match apart from
test-only changes, and both use the original AOT worker. The earlier matched
study therefore establishes an optimization on its host, not universal hosted
qualification. Preserve the AMD failures and investigate their hot paths;
do not select faster runners, relax floors or change the canonical loads.
Final verification and all workflow families remain pending.

### Final receive-order regression

The local architecture audit identifies the abort/Close ordering as worth an
additional SDK comparison. A real raw-server reproduction shows the baseline
SDK sends 1002 for an incomplete malformed text followed by Close, whereas the
candidate sends 1007 early. The adapter now remembers the first UTF-8 validation
failure and raises it only before complete message delivery, at the SDK's
original text-validation boundary. Close, invalid headers and EOF before FIN
retain their own SDK handling; complete invalid text still closes with 1007.
The paired real SDK regression passes, as do all 39 focused WebSocket cases.
This is a Dart-only change: the freshly measured six Rust coverage source pins
and all original MQTT statement identities remain unchanged.

Two additional real transport probes pause before receipt / after the first
message, then close the peer with three large messages pending. Both preserve
all three eager payloads in order. Their source and output are retained under
`/tmp/connectanum-diag-json-byte-paused-close-repro-20261120.*`.

### Complete large-JSON receive path

The actual native WebSocket writer emits two small metadata fragments before
its large argument continuation. Early prototypes missed that path and are
retained as rejected/incomplete measurements. The final candidate stages bounded
metadata, retains the original SDK framing/control/HTTP/compression code, and
uses its byte accumulator only for eligible uncompressed JSON. Standard strict
UTF-8 validation retains SDK close 1007; original wire text/binary provenance,
custom decoder behavior and eager text-payload ownership have regressions.
See [the ownership/design record](../wamp_json_byte_transport.md).

All 37 focused WebSocket cases and 77 codec/ownership cases pass. The new native
borrow API has release-on-success/error tests and public SDK ABI tests. The first
broad client invocation was rejected: native runtime-reset suites require their
existing per-file isolation. The first development `bin/test-fast` also exposes
an App-Lab supervision fixture failure during concurrent builds; no final
verification is claimed from either run. A quiet final `bin/verify` is pending.

Linux investigation run 44682963542 compares three full AOT bundles on one
runner with the same frozen native library and original four 64-MiB file loads.
Baseline/borrowed/full-receive WebSocket JSON lifecycle medians are
1,504.5 / 1,213 / 944.5 ms. All four full-receive samples clear the original
2,000-Mbps floor (2,263--2,368 Mbps); RawSocket JSON, CBOR and MessagePack also
clear it in every sample. This is matched investigative evidence, not the final
complete diagnostic workflow. Artifact 14605223270 has verified ZIP SHA256
`c2356cd0cffdfb2065a8093f8018f4029acba9e5f5fc378f7ae9b4b14eb7276d`.

Fresh current-source Cargo coverage and all 23 separate real Dart FFI
test groups plus the build step complete successfully with frozen inputs. The changed FFI
source's MQTT pin is refreshed from those measurements; all 58 original FFI
statements and all 979 original MQTT statements remain covered. All 89 native
transport/profile cases also pass with their required per-file isolation.
The App-Lab case passes three direct repeats without a deadline change; the
initial failure remains rejected evidence, and no production fix is inferred. Local Qwen/GLM review proposals are checked against actual SDK contracts:
acquire errors do not establish a borrow, release is called exactly once,
encoded lengths use checked arithmetic, and empty complete messages require
their own provenance entry. Unadapted text stays under SDK UTF-8 validation.
The proposed double-callback path is precluded by the fragmented-header guard
and empty payload loop; no unverified finding changes the protocol.
Final frozen verification and all seven workflow families must
still qualify one final source revision.

### Complete-inventory feedback on 2026-11-20

The old `0095bf40` artifacts are downloaded for all 32 MCP and 16 native CLI
shards, with every archive checked against its GitHub digest. MCP records
1,614 kills / 589 compile errors / 102 survivors / three errors; native CLI
records 800 kills / 327 compile errors / 80 survivors. Six CLI kills have only
test-error evidence and earn no assertion credit. The original 95% policy
remains unchanged. Local copies are retained under
`/tmp/connectanum-diag-0095-mcp-all-artifacts-20261120`.

Shared CLI validators now live in `src/cli/router_hosted_client_validation.dart`.
An analyzer-token audit verifies ten moved functions differ only in their
names. Thirteen duplicated state checks call the same invariant, preserving
their original diagnostics. The original production files remain in every
source scope and the new module is added to all affected mutation/coverage
lists. Complete current CLI generation is 1,162, including every operator;
the reduction from 1,207 comes from those repeated checks. Its full aggregate
score is not yet claimed. The new module's complete 73-mutant campaign passes:
50 assertion kills, 23 compile errors, no other outcomes, clean/restored tests.
Evidence: `/tmp/connectanum-diag-cli-validation-module-complete-mutations-20261120`.

The positive option oracle now asserts that argv boundary violations are CLI
failures rather than uncaught RangeErrors. Successful real HTTP exchanges
assert against unexpected MCP protocol/format rejections; transport, process,
native and deadline errors retain their original behavior. Three previously
error-only stateless-factory replays now have strict assertion evidence. The
three argv replays also pass with strict assertion evidence against the full
1,162 inventory. Each uses clean/restored baselines and an unchanged native
library. The earlier missing-value replay is retained as a rejected error-only
result: `completes` propagates its Future error, so the final oracle explicitly
asserts the public argv-boundary contract instead.
The standalone declaration/evidence tests are also added to both complete
MCP/native-CLI inventories. A real compatibility template expansion and an
unconfigured compatibility session add missing public-path coverage. All
1,253 focused MCP/CLI/evidence cases pass after correcting the new template
test to use the public resource-content List shape.

The complete local native WAMP campaign at `5ec2288e` inventories all 350
mutants: 259 assertion kills, 90 compile errors and one unclean result, with
zero survivors/timeouts. Deleting Publish dispatch reaches the two allocation
regressions' generic variant panics. Their exact expected variants now use
assertion oracles, with storage/pointer/allocation assertions retained. The
strict selected replay passes and all 433 Core tests pass. Preserve the red
full receipt at `/tmp/connectanum-diag-cbor-bounded-native-complete-20261120`;
the corrected replay is `/tmp/connectanum-diag-cbor-publish-variant-native-strict-replay-20261120`.
A complete final hosted campaign is still required.

Linux studies use a separate unqualified investigation branch, full executable
bundle fingerprints (including the AOT shared object), unchanged canonical
4x64-MiB workloads and alternating comparisons on one runner. Run 44675290073
confirms the borrowed-encoding/private-envelope path reduces JSON coalescing
from 357,918,020 to 3,908 copied bytes, but gives only about 9% throughput gain.
Run 44675950598 combines that path with private binary coalescing: CBOR/Msgpack
lifecycle medians are 1,060/1,028 ms, compared with 1,181.5/1,122 ms controls;
WebSocket JSON remains 1,441 ms. Run 44676815245 compares both controls with a
public Latin-1 String decoder; its extra WebSocket gain is only about 1%, so
that decoder is not adopted. All original final workloads and budgets remain
unchanged. The remaining JSON receive cost is being investigated in isolation.

`bin/test-fast` completes successfully during this development interval. Its
inputs were not frozen while the CLI changes were being developed, so it is
not the final qualification receipt. The final quiet, frozen `bin/verify` and
all relevant hosted workflows still remain outstanding.

A fresh isolated worktree starts at fetched `github/master`; the user's original
worktree and unrelated mutation-runner history are unchanged. Initial bootstrap
and `bin/test-fast` complete successfully (43 passing suite markers, final
zero-copy worker suite 11/11). Native isolation omitted both schema JSON files
and 42 binary FlatBuffers fixtures; compile-time and runtime fail-first tests
now cover copying and tamper detection. A real lazy echo handler reproduces the
WAMP PPT crash before carrier materialization; all eight new transport/mode/codec
cases pass afterward. The first native campaign is retained as a rejected
missing-binary-fixture run. Full native and MessagePack inventories are running. Qualifying source/test/tool files and original
policies will be fingerprinted for each accepted run; rejected/interrupted
experiments retain their separate evidence.

### First repair evidence

- Native fixture v2 now compiles and restores all 60 WAMP baseline tests. Its
  complete 402-mutant inventory remains red: 207 assertion kills, 117 errors,
  69 compile errors, six survivors and three timeouts. The audit remains strict;
  crashes/timeouts do not earn assertion credit. Raw evidence is retained at
  `/tmp/connectanum-diag-native-wamp-v2-20261119`.
- The six survivors comprise a redundant empty-slice copy guard, eager CBOR
  payload decoding guards, an OR/XOR-equivalent integer assembly loop and two
  unreachable null match arms already precluded by map admission checks.
  Reader timeouts come from corrupt progress/index updates. Standard checked
  slice/byte readers and explicit allocation/progress assertions are next.
- WAMP regression now uses the actual lazy benchmark echo handler. Original
  CBOR PPT fails with `NativeByteSnapshot.toCbor` then RPC timeout. Materializing
  internal carriers before PPT/wire conversion passes eight workload cases and
  four additional byte-exact RPC cases with nested 64-KiB binary values whose
  results remain independent after input mutation and session closure.
- MessagePack has a real stateless portable backend shared with production
  fallback and VM/Chrome tests. A one-shot iterable fails on the original JS
  delegate-then-retry path; selecting portable encoding before consumption fixes
  it. All 202 Chrome cases pass. A BigInt reference checks signed/unsigned word
  pairs around +/-2^53 and representative high/low boundaries on both runtimes.
  Complete VM v4 inventory: 205 selected, 196 viable, 182 assertion kills and
  14 survivors, raw assertion score 92.8571%, still below the unchanged gate.
  Candidate equivalence proofs are reviewed separately; no unproved waiver or
  changed kill classifier is accepted.
- MCP CLI positive tests assert completion. The real-router response proxy now
  exercises wrong status, session-header and body diagnostics; all 404 HTTP and
  option cases plus 118 native-router cases pass. A bounded protocol oracle
  asserts one resource-notification poll and aborts unexpected repeat requests,
  so corrupt filter mutants cannot hide behind a five-second polling timeout.
- Original full MCP job finally completes at 18:55 UTC: 2,308 selected, 1,719
  viable, 1,227 conventional kills, 492 survivors (470 CLI), raw strict score
  70.8551%. Complete artifact 14564173801, SHA256
  `e0dab1634d60f1cfadc8a7838bcf0990cfcfc6618fba281f8ab449e587790957`.
  Its existing test scope omits native CLI integration; add those tests without
  removing any existing source/operator/test or relaxing deadlines.
- File IO profiling alternates both methods over identical 64-MiB inputs, four
  reads each, six measured rounds: readInto median 109,015.5 us versus owned
  read buffers 52,962 us (individual ratios 1.83--2.18). This is exploratory,
  not hosted throughput qualification. The owned-buffer regression fails on
  original code, then all 98 file-transfer cases pass after eliminating the
  extra destination copy. Partial-read assembly, reopens, EOF, cancellation and
  error cleanup preserve the original chunk and backpressure contracts.
- Local GLM review completes. Its proposed negative-boundary correction is
  rejected: -2^53 + low is inside the range for low >= 0, independently proved
  by BigInt tests on VM/JS. Its map-cast warning is precluded by the marker/type
  guard, glob on a missing directory returns an empty iterator, and decode input
  is a buffered Uint8List rather than a consumable stream. Broad local-model
  requests timed out or hit output limits; bounded tests/arithmetic reviews work.

No source is pushed and no final workflow qualification is claimed yet.

### Reviewable checkpoint

The full local MessagePack VM v5 run completes all 205 mutants and passes the
unchanged adjusted 95% gate at 95.2880%, preserving raw score 92.8571%, all 14
observed survivors and five independently checked source-hash-pinned functional
proofs. See [the proof record](../msgpack_mutation_evidence.md). No crash/timeout
classifier, numeric budget, operator scope or source range changes.

The full MCP target retains all existing sources/tests and adds the native CLI
integration it previously omitted. Existing MCP cases retain the five-second
per-test default; the added integration file declares its existing native CLI
20-second timeout. Clean/restored full MCP baselines pass with all 2,308 mutants
still inventoried and the native binary unchanged. CLI-native deadlines stay
20 seconds per test and 45 seconds per complete command sequence.

Slow diagnostics now partition complete inventories: eight web shards each,
sixteen full MCP shards and eight native CLI shards. Original 60/360-minute
job deadlines and 45-minute Rust deadlines remain unchanged. One same-run
ffi-test artifact is checked against source, toolchain, dependency lock and
binary identity in every native shard and its independent aggregate. Tests
reject missing/replaced native artifacts and missing unchanged receipts, along
with existing duplicate/incomplete/tampered inventory/log/source/test cases.

Focused checkpoint checks: 62 native WAMP tests, 99 file-transfer tests, 202
Chrome codec cases, 404 CLI HTTP/options cases, 118 native CLI cases, complete
MCP baselines, native mutation tooling and 114 mutation-runner/CI execution
contracts (one existing host-specific skip). Final full bin/verify and hosted
all-workflow qualification are still outstanding. The first hosted checkpoint
is an explicit draft, not a claim that all diagnostic targets are green.

### Hosted checkpoint findings

Draft PR #139 at `2fe7337a` retains the complete diagnostic scope. MessagePack
VM and all eight browser shards pass. WAMP run 44598752416 completes all eight
scenarios: the PPT crash is gone, but fragmentation (nine findings), buffered
file transfer (four) and heavy RawSocket lifecycle (one) still miss unchanged
2,000-Mbps floors. Artifact 14568525535 SHA256:
`78fd8a8afcda067373345b104bcdd46e6f7d3165973c1b0c4f08c5a2bd75cd88`.

The hosted full MCP baseline exceeds its original 45-second command deadline.
The full native integration is now scheduled first and independent Dart test
file isolates overlap at concurrency two. A local matched complete run is
27.26 seconds serial, 21.86 seconds at concurrency two, and 19.46 seconds with
the native file first. All files, assertions, mutation inventories, five- and
20-second per-test timeouts and the total 45-second deadline remain unchanged.
This timing is exploratory until hosted qualification completes.

Two frozen-input full verification attempts are retained: the first reveals
four missing serializer helper manifests and obsolete exact workflow-upload
counts; the second passes those and detects the test-only allocator module
changing a historically coverage-pinned MQTT source. Move that observer under
WAMP's test module and restore `ct_core/src/lib.rs` byte for byte. The exact
historical coverage-hash assertion remains intact. No final green claim yet.

The CLI-native baseline also times out in the checkpoint: its separate HTTP,
option and native processes consume 11.44, 2.13 and the remaining 31.43 seconds.
Use the existing single Dart test-command mode for this target, with two
independent test-file isolates and native first. Preserve all three files and
20-second per-test / 45-second whole-command limits. The original assertion,
load/error/timeout classification code is untouched; concurrent test-file
reporter evidence uses the same fully completed command classifier as full MCP.

Overlapped clean/restored baselines pass locally for full MCP (2,308 selected)
and CLI-native (1,207 selected), both with unchanged native binary receipts.
The concurrent real-reporter regression confirms assertion/mixed failures,
error-only failures, elapsed test deadlines and abrupt process exit retain their
original strict classifications. The focused local review identifies no verified
correctness defect: every execution/listing path builds the validated command;
config bytes and recorded commands already bind independent shard auditing.

### Native progress, strict batching and JSON input ownership

The complete local RawSocket repair run preserves all source/test/tool inputs
through clean, mutant and restored phases: 92 generated, 87 strict assertion
kills, five compile errors, zero survivors/errors/timeouts. Shared portable
sendfile result/progress handling replaces duplicated host-specific loops;
only the actual syscall signature remains platform-specific. Kernel counts,
EOF, explicit file offsets, interruption and permanent error identities retain
coverage. The existing zero-survivor gate remains per host; no cross-host OR
waiver is introduced.

Complete WAMP v3 records 241 assertion kills, 76 compile errors, 12 errors and
two survivors (331 total). The failures identify unchecked header slicing,
a pointer-derived test offset lacking a preceding ownership assertion and a
custom UNREGISTERED test panic. Safe range access and standard assertion
oracles address those cases; a populated generic payload test checks the last
unexercised helper against independent wire encoders. All 426 native Core tests
pass afterward; complete post-fix mutation evidence is still required.

Three hosted native jobs exceed their original 45-minute deadlines. Complete
inventories are now distributed across four RawSocket/eight WAMP batches per
host with unchanged 30-second mutant/180-second build limits. Every batch
retains clean/restored full test inventories and its complete pinned candidate
inventory. The independent aggregate regenerates that inventory, rejects
missing/duplicate/tampered evidence, reclassifies raw logs and requires zero
survivors with no errors/timeouts. Original whole-component users retain their
95% API; diagnostics explicitly use `--require-all-killed`. One same-run Cargo
lock is shared across batches and their per-host aggregates. Dynamic binary
fixtures are hash-bound alongside the schema/TLS fixtures. Real tiny Rust
fixtures verify both narrow target batches and all original test deadlines.

New E2EE tests preserve preflight-validated plaintext/ciphertext when an
application key policy replaces arguments, and authenticate a typed XSalsa
payload above the legacy wrapper's one-MiB cap. All 169 browser cases pass;
focused, explicitly partial counterexample replay kills three former survivors
with assertion evidence. Full-inventory browser qualification remains required.

Actual JSON file CPU samples identify the String-to-byte conversion. The
native String accelerator fills one native ASCII input allocation and reuses
the existing owned-output decoder; explicit app byte/String decoders and the
generic fallback stay authoritative. All 65 browser JSON / three native
boundary tests pass, including Unicode outside the encoded span, malformed
canonical input, independent mutable results and explicit release. Four
alternating matched canonical local runs improve WebSocket data median
1,068.733 to 980.729 ms and lifecycle 1,146 to 1,071 ms; these are exploratory
Mac observations, not hosted floor qualification. A separate event-loop pacing
candidate is rejected after poorer measurements and is not shipped. Temporary
VM CPU instrumentation and profiling subsets remain outside the branch.

The superseded hosted checkpoint is cancelled after its completed artifacts
are retained, freeing runners for the current source. PR #139 remains draft;
no merge or release is authorized for it. All numeric policy JSON files,
workloads, serializer/security matrices, queue bounds and GC defaults remain
unchanged. Final quiet `bin/verify`, review and complete final-head workflow
qualification remain outstanding.

### Checkpoint f604 hosted results and ordinary MCP success oracles

Checkpoint `f604a27e` publishes the native repair and complete native batching.
Its WAMP run 44615131514 still fails fragmentation, buffered file transfer and
heavy RawSocket lifecycle floors. Artifact 14574519151 SHA256:
`2ca9dedffe4cf7a761289396e94ee2104389dd7ff2d3f1e20a6e245692852190`.
All eight workloads execute; the same 2,000-Mbps floors are retained. The native
String adapter alone does not qualify the affected paths. Final optimization
and hosted proof remain outstanding; no successful WAMP claim is made.

Core browser coverage at `a4d6dd92` reports 177/182 MessagePack codec lines,
97.253%, below its unchanged 97.29% floor. Pairing each legal width and exact
byte-data reader removes the unreachable invalid-width branch. A real Chrome
probe now covers 178/182 (97.8022%). A complete 205-candidate VM mutation run
passes again at 95.288%, including clean/restored baselines and the same five
revalidated hash-bound functional equivalences. Final hosted coverage is pending.

MCP partial results reveal a test-oracle gap: the standard `completes` matcher
forwards deliberate CLI `StateError` validation rejections as test errors. The
success helper now explicitly asserts that a valid exchange is not rejected by
that product validator. Other exception classes and deadlines retain their
original classification. A completed child exit 255 is treated as a public smoke
rejection only with explicit unhandled MCP/example-smoke stack evidence; compiler
exits, signals, missing assets, unclassified failures and any nested timeout still
fail setup. All 20 classification-boundary tests pass. Focused replay detects the
former WAMP-metadata setup failure with ordinary assertion evidence, while the
strict runner classifier is unchanged. This is a partial counterexample replay,
not full-target qualification.

A SHA256-pinned fixture retains all 208 real public-router HTTP exchanges and
exact CLI output. Fast protocol regressions check every baseline request/output,
single-response faults, exact rejection diagnostics and cleanup-only behavior.
The native integration cases remain intact; every target executing the new CLI
suite explicitly snapshots/hashes the compressed fixture. The full current CLI
inventory is being replayed independently to identify remaining negative cases.
Complete final-head MCP/native/browser campaigns and quiet bin/verify remain
required; PR #139 stays draft.

The hosted RawSocket batches expose colored compiler diagnostics rather than a
new native survivor: three actual `error[E0277]` build failures on each host
contain ANSI escapes from GitHub's `CARGO_TERM_COLOR=always`. Every native
campaign and restored command now explicitly requests `CARGO_TERM_COLOR=never`
before capturing raw evidence. The strict classifier, phase/status checks and
zero-survivor policy are unchanged. All 57 native tool tests pass; a current
raw batch under an inherited `always` environment remains to be replayed.

The first complete fast CLI replay is diagnostic only: all 1,207 disjoint
candidates are retained (697 detections, 327 compile failures, 183 survivors).
This configured CLI-only target omits no test from its own inventory but does
not replace the mandatory native/full MCP aggregates. Of the 148 previously
non-assertion/undetected partial native cases, 71 now have fast-test detections.
Further regressions observe actual owned HTTP clients even when idle, retain
original infrastructure exceptions and reap leaks after recording the failure.
They add the existing 1,024-page catalog boundary and procedure-only/topic-only
metadata cases. No source/operator or native suite is removed and no deadline
is extended. Final complete-native/full-MCP scores remain unqualified.

The complete MCP/CLI inventories now use 32/16 disjoint hosted shards rather
than 16/8. This preserves every configured test, source and operator and each
original 60-minute job / 45-second command / five- or 20-second test deadline;
full native sessions are still exercised for every assigned mutant. The same
independent full-inventory aggregates require all shards, reclassify raw logs
and enforce the original 95% threshold. Partitioning reduces total per-job work
instead of extending any execution deadline. No release workflow is dispatched.

Current local controls pass: 451 fast CLI tests, 20 child-smoke classification
boundaries, clean/restored full MCP and native CLI baselines (2,308 / 1,207
inventoried mutants), and 117 mutation-runner/CI contracts (one existing skip).
The RawSocket batch replay under inherited `CARGO_TERM_COLOR=always` now has
20 assertion kills, three compile failures, no errors/timeouts, clean evidence.
The proxy enforces its existing one-poll oracle before forwarding, so an
unexpected empty upstream SSE wait cannot masquerade as mutation evidence.

Native full-frame and deferred JSON binding now use the SDK's fused UTF-8/JSON
decoder, retaining normalization, strict malformed-input handling and ownership.
All 1,895 binding cases pass on VM and real Chrome/Wasm, including BOM/nonzero
offset views, large strings, Unicode/surrogates, binary markers, malformed UTF-8,
trailing data and retained decoded values after input mutation. A matched AOT
microcomparison reduces 16 four-MiB decodes from about 80 to 31 ms; this is not
hosted throughput qualification. Canonical native JSON pub/sub comparisons and
a separate file-write backpressure experiment remain exploratory. The earlier
fused JSON encoder prototype was slower and is not shipped. No temporary CPU
profiling code, pacing timer, allocator setting or GC override is included.


### 20 November: completed-product oracles and measured native candidates

The b6 checkpoint's WAMP diagnostic run 44628365501 completes all eight scenarios;
six pass, including both heavy cases. File-transfer RawSocket JSON lifecycle,
WebSocket CBOR/MessagePack lifecycle and WebSocket JSON data/lifecycle still miss
the unchanged 2,000-Mbps floors. TLS JSON fragmented pub/sub lifecycle and TLS
CBOR contiguous pub/sub data/lifecycle also remain below that floor. Retained
artifact 14581311683 SHA256:
`b2fd5b6a00b845dbb69c714555d49846731ea192dc4884640ef69e885dd9bb0f`.
This is a failed checkpoint, not final qualification.

Hosted MCP shard 26 times out its clean baseline without test failures. Ten
new positive metadata cases repeated complete native CLI sessions. Preserve all
ten names and operation assertions, but lazily capture four completed transcripts
by response shape; each non-wrapped capture rewrites count/list/get together and
asserts all three responses and final session deletion. Sessions remain sequential,
with original test concurrency and deadlines. Clean/restored full-MCP baselines
pass locally with all 2,308 source/operator candidates inventoried. That baseline
predates the final extra declaration/header controls and must be repeated.

Compatibility proxies preserve discovery/nested paths and assert initialization,
negotiated subscription/poll session identity and consumption of a delivered
resource update before forwarding another SSE poll. Completed exit-255 public
smoke errors have narrow product/frame oracles; nested infrastructure exceptions,
signals, compiler failures and ambiguous HTTP 500 responses retain setup-error
classification. An eligible HTTP 500 needs a separate pure, valid catalog/server
construction to fail with ArgumentError/FormatException. No network callback is
invoked or operation retried. The runner's strict classifier is untouched.
All 146 boundary controls pass. Six selected product counterexamples pass
full-native replay with clean/restored controls and unchanged native artifact
receipts: empty event-buffer removal, form elicitation rejection, default/explicit
completion capability validation, generic API pagination and request-state type
validation. All 2,308 candidates are inventoried per replay; these partial
replays do not qualify the complete target score.

Recorded real-protocol tests also preserve existing content when a resource adds
an entry or annotations, reject structurally unchanged rereads and reject invalid
publication topic/acknowledgement/id fields. All 47 recorded protocol cases pass.
Four former CLI survivors (`a3c82f7a61103289efa6`, `c7007c2ac721df42cd3f`,
`ffdfa55db8119f918cb9`, `8315b0addef074d0785e`) now have strict assertion kills
with clean/restored controls, complete 1,207-candidate inventories and one selected
counterexample per replay. These are partial replays, not whole-target scores.

The b6 main CI VM coverage job reports a test casting an already decoded public
PPT Event argument to TransferableTypedData. The regression now inspects owned
binary wire arguments, retains packed-byte equality before and after public
access, and checks both decoded positional/keyword values. The focused case
passes. No production PPT behavior is changed.

`bin/test-fast` completes successfully before the native production change.
A new segmented CBOR allocation regression fails beforehand with a 131,072-byte
scratch allocation. Standard serde borrowing from a complete current segment
removes that allocation; split values retain the standard IO-reader path. Reader
position, bounds, malformed/all-split and pointer/encoding checks remain in scope.
All 429 Core tests then pass. No custom CBOR validator or frame flattening is added.

The FFI's canonical base64 engine uses pinned base64 0.23.1 SIMD with runtime CPU
dispatch and the same padded standard alphabet/strict decoding configuration;
other architectures retain its scalar standard engine. The official
[SIMD engine documentation](https://docs.rs/base64/0.23.1/base64/engine/simd/struct.Simd.html)
was checked. An exact dev-only 0.21.7 reference independently checks every length
through 1,024, large inputs, vector/tail boundaries, invalid bytes in every lane,
padding/discarded bits and independent mutable FFI ownership. All six base64-filtered
FFI tests pass. Earlier four-round canonical local comparisons show RawSocket JSON
file data median 377.344 to 292.8 ms, WebSocket JSON 830.581 to 751.803 ms;
borrowed-only TLS CBOR contiguous pub/sub data 1,376.458 to 858.45 ms. These Mac
observations select candidates; final-source Linux/hosted qualification is pending.
TLS read-ahead, extra drain barriers and other slower prototypes are rejected.

Local advisory review finds no verified production defect after checking its
suggestions against the actual split-value tests, outer progress guard and strict
base64 differential controls. Five of six historically pinned MQTT source files
remain byte-identical; the FFI import changes the sixth. Fresh actual FFI coverage
retains all 979 covered MQTT statements. The first collection is invalidated by
a concurrent MCP test edit and explicitly discarded. A second frozen-input
Dart FFI collection and the complete instrumented Cargo workspace pass, including
all 429 Core / 310 FFI unit cases. The changed FFI file's 58 original statements
are covered exclusively by fresh measurements; source-record extracts for five
byte-identical files retain the historical Linux evidence. The original proof
and archives stay immutable. The new current-source inventory and regression
require exactly the same six files, the exact original statement mapping and
979/979 coverage, verify byte-for-byte extraction and recompute both measurement
channel counts. No historical hashes, statements or thresholds are waived.

Before readiness: complete current-source native/MCP/browser diagnostic campaigns,
run quiet frozen-input `bin/verify`, and
require every workflow family on the final head to pass. PR #139 remains draft;
no merge or release is authorized.

All 67 checked-in budget/scenario files are byte-identical to freshly fetched
`github/master` (`0a3d96e6`), which is contained in this branch. Local current
coverage-receipt validation passes, with all 29 packaging/tooling tests also
passing before the final additional scope/channel assertions. The final focused
receipt audit passes those stricter assertions. Complete hosted qualification
and quiet `bin/verify` are still pending; publishing this checkpoint is not a
readiness or all-green claim.


### Follow-up checkpoint: remaining current-source diagnostics

Checkpoint `e3bbb70a` passes three ObjectBox hosts, publishing dry runs and the
regular WAMP profile workflow. WAMP diagnostics run 44644466139 still fails;
artifact 14588213397 SHA256
`5067160ba2c9b3e14e465db494cd96554a8de0a2f56ad48c4eef153ad6f2db1a`
retains all eight scenarios. RawSocket JSON file lifecycle and native contiguous
CBOR now pass. Remaining file lifecycle rates are WebSocket CBOR 1,986.57 and
MessagePack 1,774.78 Mbps; WebSocket JSON data/lifecycle are 1,468.78/1,216.70.
TLS native JSON contiguous lifecycle is 1,954.92; fragmented JSON data/lifecycle
are 1,610.98/1,475.43 and fragmented CBOR lifecycle is 1,820.67 Mbps. Every floor
remains 2,000 Mbps. This checkpoint is not qualified for readiness.

The local frozen `bin/verify` at e3 is explicitly interrupted after 3m38s when
newly completed b6 artifacts reveal two further product-oracle classes. No file,
head or clean-worktree status changes during that attempt, but termination with
SIGTERM is not a passing verification. The e3 mutation run is cancelled as
superseded; useful completed b6 diagnostics remain available. Repeat complete
verification after the remaining changes are selected.

Completed valid example calls now recognize the specific input-response object
validation and missing generic API-list tool errors, with the same private smoke
frame and nested-infrastructure exclusions. Pure declarations cover both default
and positive limits, auto/explicit capabilities and valid resource templates.
All 166 classification boundary controls pass. Three additional full-MCP selected
replays (2,308 inventoried each) detect input-response validation, missing API-list
tool and positive event-buffer limit rejection; a fourth detects template-registry
rejection. All clean/restored baselines pass and native binary receipts stay
unchanged. These are partial counterexample replays, not complete campaign scores.

Rejected metadata batches now enforce the existing no-following-request assertion
before forwarding another native exchange. Both forwarding modes have mock
upstream coverage; all ten positive metadata cases remain and pass. The original
slow b6 metadata counterexample times out. At e3 it is assertion-killed locally
in 37.776 seconds; early enforcement reduces that to 25.432 with the same full
native CLI test scope, 1,207-candidate inventory, original 45-second command
limit and clean/restored controls. No test case or native exchange before the
injected rejection is removed.

Strict kTLS run 44644478764 fails because the Azure Linux 7.0.0-1020 kernel
advertises `espintcp mptcp` but no `tls` ULP. Artifact 14588500788 SHA256
`058cd76fd88f6978f93c69f8eab1e8bf6699e800d379bed55202997e6cdbe2f6`
confirms both require/enable flags remain 1. The runner now loads the TLS module
when absent and verifies that it is advertised before executing the same strict
HTTP/2 workload. There is no userspace fallback or skipped kTLS qualification.
The [kernel TLS interface](https://docs.kernel.org/networking/tls.html) requires
setting the TLS ULP on an established TCP socket; runner preparation precedes
that unchanged production handoff. Hosted confirmation is still required.

Remaining work is WAMP WebSocket file/TLS-fragmentation throughput, complete
current-source MCP/native/browser campaigns and final quiet `bin/verify`.
All numeric policy, workload, source/operator inventories and original deadlines
remain unchanged. No merge or release is made.


### Further diagnostic evidence (20 November)

Strict kTLS run [44649902504](https://github.com/konsultaner/connectanum-dart/actions/runs/44649902504)
passes at `0095bf40` after loading the runner's TLS kernel module. Both strict
flags, the workload and its gates remain unchanged.

The completed b6 mutation run has 101 jobs: 62 pass and 39 fail. Both native
complete gates pass on Linux/macOS. MCP/native CLI aggregates reject incomplete
or incompatible shard evidence and do not establish a full campaign score.
MessagePack browser aggregation is complete but reports 181 assertion kills,
15 survivors and nine compiler rejections, with the same five historical
functional proofs: adjusted assertion score 94.7644%, below the unchanged 95%.
Artifact 14589479693 SHA256
`19956d39ebafd775c989b9b31ed0b7d6f64b29de4b2319bd14f1ffe2f22b4acb`
is retained locally with its checksum verified.

A new public serialization regression covers a nested iterator updating a later
entry in its enclosing List. The original encoder visits live List entries;
an unnecessary List snapshot loses that update. Independent expected wire bytes,
decoded values and one traversal are asserted. All 204 MessagePack browser tests
pass. Selected browser replay `61e6321a7eaf430d5d53` inventories all 205 original
mutants, assertion-kills this counterexample and passes clean/restored baselines.
This is a selected replay; the full new browser score remains pending. Local
advisory review was checked against the actual assertion/log: its claim that a
snapshot could pass contradicts the observed `updated`/`before` failure.

Additional exploratory performance candidates are rejected: unmasked vectored
continuation writes do not improve JSON file throughput and regress cleartext
fragmented scenarios; copying JSON String input through Utf8Encoder is slower.
A Sonic parser prototype also shows no macro gain and is not shipped. Its
[checked APIs and UTF-8 policy](https://github.com/cloudwego/sonic-rs) and
[borrowing contract](https://docs.rs/sonic-rs/0.5.11/sonic_rs/struct.LazyValue.html)
were inspected; no alternate JSON parser, compiler CPU flag or new dependency
is added to the production change. Original budgets/workloads stay identical.


### Current native and protocol repair checkpoint

The `0095bf40` WAMP mutation batches on both hosts expose the same remaining
non-assertion failure: replacing `Read::read` with `Ok(1)` makes `read_to_end`
report false progress forever. The regression now asserts the zero-length read
contract immediately before the original drain, retaining every earlier assertion
and the original 30-second native deadline. The full 358-candidate inventory is
retained; the selected counterexample is assertion-killed, with clean/restored
baselines and frozen source receipts. Linux artifact 14593751223 has SHA256
`ba080efbca3b7acfc5af8ab916b3cdfa155c8e947ee7318bbbace820c9ed6dc4`;
macOS artifact 14594276511 has SHA256
`f3f4ec742d75db13eb05a7846374866b80ea804e2124800606b10a6ac347740c`.
This is a selected replay, not a full current-source campaign result.

CBOR cross-segment validation now retains one shared suffix allocation, using
standard serde validation and a 64-byte stack preview for short split metadata.
Payload slices reuse that validation storage; the public raw frame retains its
original segments. A fail-first regression observes 131,072 allocated bytes for
a 65,576-byte wire frame before this repair. The corrected path asserts total
allocation at most wire size plus 16 KiB, exact payload bytes and original raw
segment pointers. Existing aligned borrowing/allocation tests remain unchanged.

TLS preserves Ring's exact ordered cipher-suite IDs, key exchange groups,
signature verifier mappings, RNG and key provider, replacing only each available
cipher-suite implementation with AWS-LC for the same suite ID. Rustls explicitly
supports [mixing provider components](https://docs.rs/rustls/0.23.45/rustls/crypto/struct.CryptoProvider.html).
No TLS version or negotiated algorithm is added or reordered. The first explicit
process provider remains authoritative. HTTP/3-only initialization is tested in
a fresh process; every supported TLS 1.3 suite has bidirectional Ring interop,
record-boundary, ALPN, application-data and corrupt-tag rejection coverage.
All 432 Core tests, the new HTTP/3 process regression and three serializer
integration tests pass. The six pinned MQTT production sources remain unchanged.

The native canonical base64 String path uses public synchronous
`Dart_StringToUTF8`/`Dart_IsError` callbacks inside the documented
[Handle FFI scope](https://api.dart.dev/dart-ffi/Handle-class.html).
The scoped copy is consumed before return; decoded bytes have independent native
ownership. Only entirely ASCII strings take this path; Unicode contexts and older
native libraries retain their tested scalar fallback. Actual UTF-8 bounds are
checked before slicing. All ten focused Rust FFI cases pass, including malformed
canonical forms, vector boundaries, ownership after input changes/free, missing
APIs, invalid ranges, empty storage and missing nonempty API storage. Three Dart
native tests pass with both the new and old native libraries. All 65 recorded CLI
protocol controls pass, including empty and null catalogs and missing responses.

Matched exploratory four-round comparisons select the native candidates:
cleartext CBOR 4-KiB fragmentation data median 665 to 594 ms; TLS JSON/CBOR
medians improve about 10--12 percent. With the same new native library on both
sides, the public-API String worker reduces WebSocket JSON file data median
874.35 to 700.34 ms, while RawSocket JSON remains 391 to 392 ms. These are local
candidate comparisons, not hosted floor qualification. CPU profiling is kept
outside the product and qualifying runs. Local advisory reviews find no verified
new correctness defect: pre-existing SNI fallback is outside this change; serde
rejects incomplete values before advancing, offsets remain original absolute
positions, TLS 1.2 is disabled by the unchanged feature set, and the Dart mutation
fixture is always nonempty. No new waiver or relaxed classifier is introduced.

Remaining work: complete current-source hosted mutation campaigns and all WAMP
floors, finish quiet frozen-source `bin/verify`, then audit every workflow/check
on one final commit. PR #139 remains draft; no merge or release is authorized.


### Frozen verification and remaining hosted failures

Commit `892f19cd` completes local `bin/verify` successfully in a quiet run from
02:30:14 to 02:53:18 UTC. All 3,178 tracked/untracked input and lock hashes,
committed head and clean worktree status remain unchanged throughout. Chrome and
Dart2Wasm run successfully. This qualifies that exact checkpoint; subsequent test
and kTLS fixture repairs require another final frozen verification.

At the same checkpoint package dry runs, all three ObjectBox hosts and regular
WAMP profiles pass. WAMP diagnostics run 44661260682 clears all native TLS
fragmentation floors. Artifact 14596735743 has verified SHA256
`68afa476dd598d6284ada71dd2e65fa459c73e74a40dd350ee72cee17fe3482f`.
File lifecycle rates remain RawSocket JSON 1,833.889, WebSocket CBOR 1,771.851
and MessagePack 1,934.670 Mbps; WebSocket JSON data/lifecycle are
1,397.605/1,170.929. Heavy 256-MiB native RawSocket JSON RPC lifecycle is
1,992.100. Every corresponding floor remains 2,000. The new host is an Intel
Xeon 6973P-C; the previous host was AMD EPYC 9V74. Unmatched hosted rates do not
establish a candidate gain. A separate branch captures explicitly unqualified
Linux CPU profiles; it does not alter any qualifying workload or policy.
The uninitialized coalescing prototype gains only about one percent in matched
MessagePack file data timing and is not adopted.

Isolated kTLS run 44661270856 exposes the dual-provider ambiguity in its Linux-only
test fixture before reaching the unchanged strict workload. The server fixture
now explicitly uses the same Ring provider as its existing client, with the same
safe default protocol versions and every original assertion. Production provider
selection and both strict kTLS flags remain unchanged; hosted confirmation is
required. The HTTP/3-first process regression remains separate.

The full `0095bf40` MCP shards expose two residual non-assertion counterexamples:
`isNotification: !hasId` losing its negation, and the default `includePubSubTools`
selection becoming false. Artifacts 14596036000/14596476233 have verified SHA256
`ffb1a895658d0ce526da13b92e3a3b8d0af9820f43bdbf43dbbe5519695b4688` /
`623e474c237a5e10aa7cc6fa9b0d6e1ef1cc19afd8b36df83fc249e8a9ff6c5f`.
Tests now assert response/error/result Map shapes and required collection
cardinality before their existing casts, matches and selections. Completed child
missing-response/missing-declared-tool signatures additionally require an
independent public in-process server initialization and actual tool-catalog
assertion. Only its explicit TestFailure corroborates the product defect;
unknown parsers/tools, other exits, missing corroboration and nested infrastructure
errors remain unclassified setup errors. No runner kill classifier is changed.
All 1,242 MCP, native CLI and evidence controls pass. Both selected full-inventory
replays retain 2,308 candidates, assertion-kill their counterexample, pass
clean/restored baselines and preserve the same native binary. These are selected
replays rather than final campaign scores.

Four canonical-base64 Dart tests pass with both new and old native libraries.
The new direct ABI control actually invokes the optional native String entry
point and public VM callbacks when present, including an embedded NUL context
and Unicode fallback. The official Dart 3.14.0 Linux SDK's JIT/AOT runtimes both
export Dart_StringToUTF8/Dart_IsError; this proves symbol availability, not which
path a particular benchmark worker used. Local reviews are advisory: suggestions
to loosen exact signatures or widen accepted error types are rejected. The
returned Object preserves its runtime type, and existing dedicated schema tests
cover schema behavior beyond this catalog-presence probe.

Current blockers remain final hosted file/heavy floors, complete current-source
mutation scores, hosted kTLS confirmation and final frozen verification after
these further repairs. PR #139 remains draft; no merge or release is made.


### Bounded CBOR preview and strict counterexample evidence

Strict kTLS passes again at `1cc12182` in run
[44665881303](https://github.com/konsultaner/connectanum-dart/actions/runs/44665881303).
The original kernel-module preparation, both strict flags, workload and gates
remain unchanged. A third full-MCP counterexample, `cb5614cb5c1a0e66c710`
(`request.isNotification` becoming true), has the same missing-response failure
as the earlier negation mutant. The existing new guards assertion-kill it in a
selected 2,308-candidate replay, with clean/restored baselines and the same native
binary. Full campaign scores remain pending.

The CBOR cache's manual preview progress introduced an arithmetic mutation
failure: baseline passes, while `filled += count` becoming `-=` panics with
subtraction overflow. A direct isolated regression reproduces that failure before
repair. The preview now writes into a bounded standard Cursor over its 64-byte
stack buffer; prefix subtraction uses checked arithmetic. Partial writes are
intentional when that concrete slice-backed Cursor reaches capacity; write_all
would incorrectly reject a large input segment. No alternate validator is added.

A new public parse regression uses both complete and byte-split metadata prefixes,
an aligned 64-KiB argument block and 4-KiB-fragmented 64-KiB keyword arguments.
It retains exact raw pointers/bytes and requires the aligned argument pointer to
remain borrowed, with total allocation no greater than kwargs wire size plus
16 KiB. Existing allocation/pointer tests remain unchanged. Both changed early
exit conditions fail this regression through assertions, without arithmetic
panics. All 433 Core tests, fresh-process HTTP/3 and three serializer integration
cases pass in the candidate worktree and the main worktree.

The complete current native WAMP inventory contains 350 mutants after replacing
manual operators with standard bounded IO and checked subtraction. All current
operators/source locations remain inventoried; no filter, waiver, timeout or
threshold changes. Three strict selected campaigns (preview break 17/350, prefix
break 182/350 and false progress 1/350) are assertion-killed with clean/restored
baselines, complete raw/filtered inventories and frozen source receipts. They
are partial counterexample proofs, not a complete native score. Local review's
partial-write concern was checked against the concrete bounded Cursor and the
passing split-prefix/pointer regressions; no hypothetical generic writer is used.

The broad Linux profile is explicitly interrupted after collecting its original
source-mode data; artifact 14599495462 has verified SHA256
`117d9ddcfd2e819c2fe4eb1830d5202d2e03dd1fcf5aeba95123ead19668d3f8`.
A subsequent focused, unqualified profile retains four exact canonical Dart
file workloads, with every original byte count, repetition, concurrency and
chunk size unchanged. Both source and AOT profiling complete in run 44667850793;
artifact 14598164101 has SHA256
`950d510cb95c3fbdbed983e9d24395e8df4d32f2d12e2d6e84f1883ebda1fdea`.
These profiles do not qualify throughput gates; investigation and final full
workflow verification remain outstanding.
