# Project State

Last updated: 2026-11-20.
Current milestone: repair WAMP and mutation diagnostics without relaxing gates.
Active plan: [WAMP and mutation diagnostic repair](exec-plans/2026-11-19-wamp-mutation-diagnostics.md).
Completed plan: [Dart 3.14 upgrade](exec-plans/2026-11-17-dart-3.14-upgrade.md).

An external Codecov patch check exposes a remaining SDK-boundary test gap:
748/963 changed executable lines (77.6739%) are covered against the unchanged
94.20% target. Of 215 misses, 188 belong to the HTTP/Socket forwarding adapter.
Seven new contract tests exercise real HTTP verb/URI/body round trips and SDK
configuration, authentication/proxy/TLS callbacks, request completion/errors,
response metadata/redirects/compression and socket options/encoding/lifecycle.
All 61 WebSocket cases pass, with 225/225 adapter lines hit. The union of this
actual measurement and the original CI LCOV estimates 936/963 (97.1963%);
fresh hosted validation is still required. No production source, threshold,
ignore rule, mutation scope or coverage denominator changes. Local model review
is blocked by an active native-mutation resource lease; direct source review and
executable contract tests provide the current evidence.

An additional MessagePack audit exposes one invalid functional-equivalence
claim: a public `Iterable.toList` override can observe `growable` and change
nested wire values while preserving its returned elements and order. The exact
counterexample and a failing public regression reproduce this. Non-List inputs
now use a private iterator snapshot, preserving one traversal and List-input
liveness. The invalid growability waiver is removed. The complete current AST
inventory has 204 candidates and four remaining source-bound equivalences;
no source/operator/test filter or numeric gate changes. All 191 VM, 191 real
Chrome/Dart2Wasm and 206 Chrome/Dart2JS codec cases pass. Fresh complete
qualification is required; the obsolete `9a304a08` CI/mutation campaigns and
the earlier campaign's queued audits are cancelled with evidence retained.

Frozen `9a304a08` passes the complete local `bin/verify` from 10:13:17 to
10:38:14 UTC, including real Chrome/Dart2Wasm. All 3,191 source/lock hashes
and HEAD remain unchanged, with a clean worktree before and after the run.
Both WAMP workflows, strict kTLS, ObjectBox on all three platforms and package
dry runs pass on this commit. The complete WAMP diagnostic run
[44717600688](https://github.com/konsultaner/connectanum-dart/actions/runs/44717600688)
passes all eight scenarios and 117 workloads. All 36 WAMP scenario and policy
files remain byte-identical to the PR #138 merge. These are historical results
before the additional iterable repair; PR #139 stays draft pending fresh runs.

All 97 execution jobs from `52b103c0` pass. Independent local audits of the
complete original shard artifacts pass the unchanged 95% assertion gates:
CLI 95.0898% (1,162 candidates, 16 shards), MCP 96.2366% (2,263 candidates,
32 shards), and E2EE browser 96.4567% (313 candidates, eight shards). Each
independently regenerates the full inventory and checks raw-log hashes,
classifications, baseline/restore evidence and provenance. The earlier
MessagePack 95.2880% calculation includes the subsequently rejected virtual
conversion equivalence and is not accepted as qualification. Current source
and native-binary campaigns remain required.

The frozen paired Linux comparison confirms WebSocket file lifecycle gains of
15.16% CBOR, 11.96% MessagePack and 13.03% JSON. Its subsequent complete diagnostic
run retains one native TLS JSON lifecycle near-miss at 1,925.994 versus the
original 2,000-Mbps floor; seven gates pass. Both runs use Xeon 6975P-C-class
hosts. This failed additional measurement is preserved separately from the
successful normal PR workflow's first attempt. No universal host-performance
claim or gate/runtime-default change is made.

Frozen `52b103c0` passes the complete local `bin/verify` from 08:05:25 to
08:29:55 UTC, including real Chrome/Dart2Wasm; all 3,185 input hashes, HEAD
and clean status remain unchanged. Regular WAMP, kTLS, three-platform ObjectBox
and package dry runs pass; all 55 main CI jobs pass. Full mutation aggregates
remain pending, with no failed jobs at the latest inspection.
Complete WAMP diagnostics on EPYC 7763 still report 15 findings in three
scenarios. Those failures are preserved, not replaced by the faster-host runs.

User-space profiles identify WebSocket buffer initialization and large synthetic
payload construction costs. Bounded safe Tokio `read_buf` now avoids pre-zeroing
payloads, with exact next-frame, masking, Pending and truncated-read regressions;
all 435 Core tests pass. The byte-identical alphabet generator passes all 66
workload-runner tests and independent 4/64/256-MiB identity checks. Fresh native
Cargo and all 23 Dart FFI coverage groups pass on macOS and Linux. Fresh counts
cover all 979 original MQTT statements, including the 15 Linux-only statements.
The proof retains the complete original scope and independently verifies each
original statement's unchanged source mapping.

The ReadBuf/alphabet candidate's complete diagnostics still fail 11 metrics on
Xeon 8573C (run 44706039812); that failed evidence is preserved. A bounded Dart
WebSocket receive adapter now avoids the SDK's final managed-array copy, with
54 focused tests passing. A frozen alternating macOS comparison shows small
WebSocket gains; a synchronous-hashing experiment regresses and is rejected.
Matched Linux measurements and all eight original scenarios are running in
investigation run 44716920600. This candidate is not yet qualified. No floor,
workload parameter, timer boundary, allocator/GC/compiler default or inventory
is relaxed.

PR #138 is merged into `master` at `0a3d96e6`. Its mandatory main CI passes all
55 jobs and all sixteen performance/memory shards. Additional WAMP diagnostics
fail fragmentation/file-transfer throughput floors; full mutation diagnostics
show native restored-baseline errors and MessagePack/MCP CLI assertion scores
below the original 95% gates. The new active plan records the exact failures;
the broader diagnostic chain is not qualified. No threshold or inventory is
relaxed. The previous Dart upgrade qualification below remains historical
source evidence rather than a claim that these additional workflows pass.

Frozen `840e144c` local `bin/verify` passes completely with all 3,185 input
hashes, HEAD and clean status unchanged, including real Chrome/Dart2Wasm.
Both complete WAMP workflows, kTLS, ObjectBox on all three platforms and package
dry runs pass on that same commit. Main CI exposes one coverage-ownership
error: the shared validator belongs to two components. It is now assigned only
to the stricter 98% library component, retaining all required sources and
mutation scopes and the original CLI floor. Replaying the unchanged CI LCOV
passes every gate (library 99.354%, CLI 98.692%); a new actual-policy regression
protects unique ownership. Fresh main CI/full-mutation qualification is pending.

Complete WAMP diagnostics at `f25b8de9` pass all eight original scenarios on
AMD EPYC 9V45, with unchanged floors. Regular WAMP, kTLS, all three ObjectBox
platforms and package dry runs also pass. Frozen `7d918b38` verification exposes
one remaining component assignment: the shared validator must also belong to
`mcp-library`. Both mutation and coverage scopes now include it; all 95
mutation-runner tests and the remaining tooling suites pass. Main CI, full
final mutation aggregates and a fresh frozen `bin/verify` are still pending.

Latest frozen verification at `f25b8de9` fails only stale static CLI source
checks after validator extraction; all 3,185 input hashes remain unchanged.
The checks now follow the actual module and assert its public import/delegation;
all 24 package-boundary tests pass. Complete WAMP diagnostics on an AMD EPYC
7763 host still miss native TLS, large native RawSocket and one JSON file floor.
The earlier matched passing study ran on Intel Xeon 6975P-C. Those are separate
host measurements; the diagnostic chain remains unqualified and its floors,
runner labels, workloads and deadlines remain unchanged.

The complete fragmented JSON receive candidate now clears all four original
Linux file-transfer workload floors in a matched investigation. WebSocket JSON
lifecycle improves from 1,504.5 to 944.5 ms; each measured sample exceeds the
unchanged 2,000-Mbps floor. All 39 focused WebSocket tests pass, including strict
UTF-8, controls, original binary provenance, custom decoders and text ownership.
Fresh native coverage and quiet final verification are in progress; the final
complete workflow inventory is still unqualified. Design and evidence:
[large JSON transport](wamp_json_byte_transport.md).

Current local repair evidence: all 1,253 MCP/CLI/evidence tests pass. Ten CLI
validators move without changing their production tokens; thirteen repeated
session checks use the same tested invariants and retain their diagnostics.
The internal module remains in all original CLI mutation and coverage scopes.
Its complete 73-mutant run records 50 assertion kills and 23 compile errors,
with clean and restored baselines. The full CLI inventory is now 1,162 after
deduplicating those checks; no source, operator, test or threshold is excluded.
The full MCP/CLI aggregate scores still require fresh hosted qualification.

The complete 350-mutant native WAMP run has zero survivors/timeouts but one
non-assertion result: deleting Publish dispatch reaches generic panics in two
allocation regressions. Those tests now assert the actual message variant;
the strict selected replay and all 433 Core tests pass. The complete final
native campaign and all final workflows remain pending.

Matched Linux file studies qualify private coalescing as a useful production
candidate: CBOR/MessagePack lifecycle medians clear the original 2,000-Mbps
floors. Borrowed JSON encoding also removes the measured full-frame coalesce
copy, but WebSocket JSON still misses its floor. A public Latin-1 String API
variant gives only about 1% further WebSocket improvement and is not adopted.
These studies remain separate from the unmodified final diagnostic workloads.

[PR #138](https://github.com/konsultaner/connectanum-dart/pull/138) pins standalone
Dart 3.14.0 across `.tool-versions`, CI/cache keys and all eight publishing jobs.
Package SDK lower bounds remain 3.10.0.

The repair keeps MQTT input in the Core decoder's owned managed body. Large
internal binary values use privately owned, VM-immutable native snapshots across
isolate hops; public callbacks receive mutable owned copies. The existing
negotiated, bounded fragment/batch path also handles singleton gateway recipients.
Older native libraries and custom workers retain their capability fallback.
The App-Lab child-exit race has a deterministic regression. Lifecycle, copy/GC
ownership, file-counter and worker-error paths have regression coverage.
Six added normal/lazy RPC cases at 16,383/16,384/65,537 bytes cover the native
snapshot public-copy path, nested keywords and independent mutable results.
Removing that copy fails the regression; original tests stay unchanged.

Implementation `8a70e37c` passes **all 61 PR checks**, without skipped or
cancelled checks: all 55 [main CI jobs](https://github.com/konsultaner/connectanum-dart/actions/runs/44356684316), all sixteen gateway
performance/memory shards, exact gateway coverage, all mutation gates and both
Codecov contexts, three ObjectBox platforms and package dry runs. GuardMalloc
observes and passes 93 native ownership cases. All 20 standalone MQTT QoS
profiles pass. Critical 64-KiB/window-32 result: peak 61.65/96 MiB, CPU ratio
2.467/4, p95 1.116/2, p99 1.096/2.25 and throughput 0.9467/0.75.

Complete current-source local `bin/verify` passes with both the committed head
and all 21 frozen implementation/test/tool hashes unchanged throughout,
including real Chrome/Dart2Wasm (4,814 Core and 2,830 client cases; 20 existing
native-only browser skips). Qualifying cold comparisons match production
Dart/native source hashes and clear both strict standalone QoS and all 40
normal/six overload gateway cycles. Full PR CI independently qualifies the
complete profile/retention/control matrix.

All 19 benchmark-budget JSON files match `master`; measured critical QoS
budgets equal checked-in values. Numeric memory/performance, coverage and
mutation limits, workloads, queue bounds, warm-up/drain/stall durations,
default VM settings and timeout controls remain unchanged. No forced production
GC or global allocator tuning is added. The completed plan preserves original
failures, rejected candidates and checksum-verified evidence. No merge or release
is made.

Latest release: coordinated `3.0.0-beta.9` publication completed on 2026-11-06.
All eight Dart packages are public, with matching signed native assets for five
platforms. [Release and evidence](https://github.com/konsultaner/connectanum-dart/releases/tag/v3.0.0-beta.9).
Completed plan: [beta.9 release](exec-plans/2026-11-06-3.0.0-beta.9-release.md).
[PR #137](https://github.com/konsultaner/connectanum-dart/pull/137) retains normal
GitHub review for the version metadata and release record. Publication used the
fully qualified commit `72c078f1`; no branch protection was bypassed.

Diagnostic repair is published as draft [PR #139](https://github.com/konsultaner/connectanum-dart/pull/139).
Checkpoint `2fe7337a` passes MessagePack VM and all eight MessagePack browser
shards, package publishing dry runs and five of eight WAMP scenarios. WAMP
fragmentation, buffered file transfers and one heavy RawSocket lifecycle floor
remain red. Hosted full MCP baselines exceed the unchanged 45-second command
deadline; independent test-file isolates are now overlapped, with the native
integration scheduled first. Local matched full-suite times are 27.26 seconds
serial versus 19.46 seconds overlapped, with complete test inventory and all
original timeouts intact. This is exploratory timing, not hosted qualification.
Full MCP and CLI-native clean/restored baselines pass locally with all
2,308 / 1,207 mutants inventoried and unchanged native binary receipts.

Frozen-input `bin/verify` exposed four missing serializer helper manifests,
obsolete workflow-upload counts and a historical MQTT coverage source-hash
mismatch caused by a test-only allocator module declaration. The manifests and
exact upload checks are repaired; the allocator now lives under WAMP's test
module, restoring the MQTT source byte for byte. Complete final `bin/verify`
and all hosted workflow gates remain outstanding.

Current repair evidence: all 426 native Core tests pass. A complete frozen-input
RawSocket campaign inventories all 92 current mutants and records 87 assertion
kills / five compile errors, zero survivors/errors/timeouts. WAMP v3 completes
331 candidates but remains unqualified (12 non-assertion failures and two
survivors); checked range access, stronger pointer/variant assertions and a
populated generic-payload regression address the observed cases. The next full
campaign and hosted proof remain pending.

The diagnostic workflow partitions complete native inventories into four
RawSocket/eight WAMP batches per host, preserving each original 45-minute job
and 30-second native test deadline. An independent per-host aggregate regenerates
the complete inventory, reaudits every raw log and requires zero survivors plus
clean evidence. All batches share one same-run Cargo dependency lock. Browser
E2EE regressions detect three formerly surviving mutants; all 169 browser E2EE
cases pass. The direct native JSON String decoder preserves explicit app decoder
choices and owned mutable output; 65 browser JSON and three native boundary
cases pass. Its local matched WebSocket file gain is about eight percent and is
not hosted throughput qualification. No numeric policy, source/operator scope,
workload or queue limit is relaxed. Final quiet `bin/verify` and all seven
hosted workflow families remain required before PR #139 is ready.

Latest local progress (20 November): `bin/test-fast` passes before the native
candidate change; afterward all 429 Core and six canonical-base64 FFI cases pass.
Segmented CBOR borrows complete encoded values using standard serde, and the
canonical FFI base64 engine uses runtime SIMD with strict 0.21.7 differential
controls. Local timing selects these candidates; hosted throughput remains
unqualified. The b6 WAMP checkpoint passes six of eight scenarios, with the
remaining file/fragmentation floors unchanged. MCP completed-product smoke oracles
and four shared metadata-shape captures preserve the full test/candidate inventory
and deadlines; 146 boundary and 47 recorded-protocol cases pass. Four formerly
surviving CLI counterexamples are assertion-killed, but complete current-source
campaigns are still required. A stale PPT test now checks wire bytes and public
decoded content correctly. The fresh native coverage
receipt preserves all six source pins and all original 979/979 MQTT statements;
quiet final `bin/verify` and all seven final-head workflow families remain
outstanding. See the active plan for
discarded coverage evidence and exact partial-replay limits. PR #139 remains draft.

Current checkpoint `e3bbb70a` passes package dry runs, three ObjectBox hosts and
regular WAMP profiles. WAMP diagnostics still miss WebSocket file and native TLS
fragmentation floors; the active plan records exact measured rates and verified
artifacts. kTLS requires explicit runner module preparation while retaining both
strict flags and the original workload. New MCP controls total 166 cases; selected
native replays detect the additional declaration/protocol failures. The local
frozen e3 `bin/verify` is deliberately interrupted after new diagnostic evidence
arrives and is not a pass. Complete final-source verification remains required;
PR #139 stays draft.

Strict kTLS now passes at `0095bf40` with the original flags/workload. The full
b6 native mutation gates pass on both hosts; MCP aggregate evidence remains
unqualified. A missing live-List traversal regression is repaired and all 204
MessagePack browser tests pass, with its formerly surviving counterexample
assertion-killed. The complete new campaign score, remaining WAMP floors and
quiet final `bin/verify` are still pending; PR #139 remains draft.

Latest native/protocol checkpoint: all 432 Core tests, fresh-process HTTP/3
initialization, three serializer integrations, ten focused canonical-base64 FFI
cases and 65 recorded CLI protocol controls pass. The WAMP false-progress mutant
is assertion-killed in a selected full-inventory replay. CBOR validation reuses
one suffix allocation; TLS retains the exact Ring policy with accelerated record
implementations; the optional public Dart UTF-8 API path preserves Unicode and
old-library fallbacks. Local matched timing selects these candidates but does
not qualify hosted floors. Complete final mutation scores, all WAMP scenarios
and quiet frozen-source `bin/verify` remain pending. PR #139 remains draft.

Quiet frozen `bin/verify` passes at `892f19cd`, including Chrome/Dart2Wasm,
with all 3,178 inputs, head and clean worktree unchanged. That checkpoint also
passes package dry runs, three ObjectBox hosts, regular WAMP profiles and native
TLS fragmentation floors. File/heavy diagnostic floors remain red on the new
Intel runner. An isolated Linux kTLS fixture needs explicit provider selection;
the fix retains the existing Ring client/server algorithms and strict workload.
Two remaining full-MCP non-assertion counterexamples are assertion-killed in
selected 2,308-inventory replays after explicit response/catalog guards; all
1,242 focused MCP/native/evidence controls and four new/old-library base64 cases
pass. Full campaign scores and hosted floor qualification remain pending. The
additional repairs require another final frozen `bin/verify`; PR #139 stays draft.

Strict kTLS passes at `1cc12182`. A third missing-response MCP counterexample is
assertion-killed in a selected full-inventory replay. The CBOR preview now uses
bounded standard Cursor IO after reproducing an arithmetic mutation panic;
a new split-metadata/aligned-argument/fragmented-kwargs regression preserves
borrowing and allocation limits. All 433 Core tests plus integrations pass;
three strict selected native replays retain the complete 350-mutant inventory
and clean/restored baselines. Complete campaign scores, remaining file/heavy
floors and final-source frozen verification are still pending. The completed
focused Linux source/AOT profiles are investigative evidence, not gate passes.

## Release scope

All eight Dart packages and three Rust crates are synchronized at beta.9.
All five native production builds and the router image publication pass. Both
native installers download the published bundle successfully. Seven package tags
publish through existing GitHub OIDC; ObjectBox retains its individual ownership
and uses the existing authenticated Dart CLI. See [publishing](dart_package_publishing.md).

The release includes MQTT 5/3.1.1 QoS 0 over TCP/TLS/WS/WSS and an opt-in,
realm-authorized MQTT ↔ WAMP gateway. Binary payloads, trusted caller identity,
bounded queues, cancellation, teardown and bounded asynchronous client receive
batches have live/regression coverage. Ordinary MQTT PPT remains opaque.
See the [MQTT contract](mqtt.md) and completed
[gateway plan](exec-plans/2026-10-14-mqtt-broker-interoperability.md).

## Last-known verification

| Source/check | Verified result |
| --- | --- |
| Managed-input/RPC repair `8a70e37c`, [main CI](https://github.com/konsultaner/connectanum-dart/actions/runs/44356684316) | All 55 jobs pass on attempt 1, including all sixteen performance/memory shards and exact coverage/mutation gates |
| Managed-input/RPC repair `8a70e37c`, complete PR rollup | All 61 checks pass, zero skipped/cancelled checks; both Codecov contexts, three ObjectBox platforms and package dry runs pass |
| Managed-input/RPC repair `8a70e37c`, committed-head `bin/verify` | Pass, head and all 21 source/test/tool hashes unchanged; Rust/native/VM/consumers/real Chrome/Wasm |
| Managed-input repair, [strict standalone QoS](https://github.com/konsultaner/connectanum-dart/actions/runs/44339526524) | Both cold campaigns pass every original CPU/rate/latency/RSS gate; peaks 54.38/55.68 MiB against 96 MiB |
| Managed-input repair, [cold gateway comparison](https://github.com/konsultaner/connectanum-dart/actions/runs/44339531343) | All 40 normal/six overload candidate cycles pass available absolute checks; peaks 31.39/63 MiB and 75.15/126 MiB |
| Managed-input repair, complete local `bin/verify` | Pass, all 20 source/test/tool hashes unchanged; Rust/native/VM/consumers/Chrome/Wasm; complete source-head CI passes at `8a70e37c` |
| Mapped-input singleton repair, [cold comparison](https://github.com/konsultaner/connectanum-dart/actions/runs/44327753894) | All 40 normal and six overload candidate cycles meet available absolute checks; normal 34.14/63 MiB, p99 1,665–1,738/2,437 us |
| Mapped-input singleton repair, complete local `bin/verify` | Pass, all source hashes unchanged; Rust/native, full VM/consumers and real Chrome/Wasm; historical mapped-input source, superseded by the complete managed-input/RPC qualification |
| Dart 3.14 source `9dc7b2d4`, [CI](https://github.com/konsultaner/connectanum-dart/actions/runs/44268728740) | All 55 main jobs pass, including all 16 memory/performance shards |
| Dart 3.14 full PR checks at `9dc7b2d4` | All 61 checks pass, zero skipped/cancelled; Codecov project 94.20% vs 94.16%, patch 100% |
| Earlier Dart 3.14 source `9dc7b2d4`, local `bin/verify` | Pass, Rust/native/Dart/consumers/ObjectBox/Chrome/Wasm; clean worktree at completion |
| Released source `72c078f1`, [CI](https://github.com/konsultaner/connectanum-dart/actions/runs/42228480314) | All 61 PR checks pass, zero skipped checks; all sixteen performance/memory shards pass |
| Published native builds / production profiles | Five platforms pass, 170 cases, zero skips |
| Fresh hosted-only beta.9 consumer | All eight exact versions; MQTT 5/3.1.1 and both gateway directions pass; zero duplicates |
| Published archive/source audit | Eight archive digests and 315 code/hooks/README/changelog/license files match |
| Merged MQTT source `47e06946`, [main CI](https://github.com/konsultaner/connectanum-dart/actions/runs/42204368959) | All 55 jobs pass |
| PR #136 source `e109df94`, [CI](https://github.com/konsultaner/connectanum-dart/actions/runs/41668179162) | All 59 checks pass, zero skipped jobs |
| PR #136 clean-source `bin/verify` | Pass, Rust/Dart/consumers/Chrome/Wasm; all 3,147 tracked files unchanged |
| Complete MQTT client/gateway hosted coverage | 828/828 executable lines, including client 160/160 |
| Gateway tooling, zero exclusions | 1,084/1,084 statements |
| Added native production lines | 979/979, source-hash proof retained |
| MQTT/Paho integration | 150 cases pass, no skips; ten receive regressions, six fail on original client |
| Sixteen gateway performance/memory shards | All pass; 1,304 samples, 64 translation/four overload results |
| Independent secure smoke | All 264 samples pass |
| Exact default-runtime translation deliveries | 3,850,000; zero duplicates/errors |
| Beta.9 stalled MQTT subscriber peak RSS | 35.6 MiB against unchanged 50 MiB cap |
| Release baseline `47e06946`, local `bin/test-fast` | Pass; all tracked source hashes unchanged |

Beta.9 qualification and publication receipts are retained in the completed
release plan and GitHub release. A clean-source beta.9 `bin/verify` passes with
all 3,148 tracked files unchanged; the final runner-label change is independently
verified by Actionlint and all three ObjectBox platforms. All numeric budgets,
default runtime settings and coverage requirements remain intact. Friendly
benchmark tables remain in the [benchmark package README](../packages/connectanum_bench/README.md#mqtt-and-wamp-gateway),
with complete history in the
[checksum-verified archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-retention-2026-11-02).

## Remaining readiness work

The broader MQTT milestone remains open for QoS 1/2, retained messages/wills,
persistence, credential authentication, full properties and release conformance.
#131 controlled-hardware sign-off remains open: no confirmed exclusive Linux
reservation was available; hosted ARM64 regression gates remain on GitHub Actions.
This beta does not claim final MQTT conformance or controlled-hardware sign-off.

Pre-existing auxiliary blockers remain: strict kTLS lacks Linux TLS ULP support;
WAMP diagnostics miss their existing buffered file/heavy RawSocket floors.
FlatBuffers parity, the broader security audit and regression/mutation target
remain prerequisites for final `3.0.0`. No release gate is relaxed for beta.9.

Checkpoint `f604a27e` WAMP diagnostics still fail three scenario families; all
existing 2,000-Mbps floors remain. Core MessagePack browser coverage is repaired
locally to 178/182 lines (97.802% > 97.29%), with its complete 205-mutant VM gate
passing again at 95.288% and only the same five revalidated functional proofs.
MCP success oracles now assert deliberate product validator/smoke rejections as
ordinary behavior failures; 20 boundary controls keep compiler, signal, asset,
unknown and timeout failures in their original infrastructure classes. A complete
208-exchange real-router fixture adds fast adversarial protocol checks without
removing native cases. Complete current CLI replay, performance repair, quiet
bin/verify and final-head hosted qualification are still pending.
The hosted RawSocket compiler-diagnostic errors are reproduced as ANSI-decorated
Rust E0277 failures. Native campaigns/restorations now request undecorated raw
logs before capture; all 57 native tool tests pass and the strict classifier is
unchanged. The full fast CLI replay retains all 1,207 candidates but still has
183 survivors; it does not substitute for the mandatory native aggregate.
Owned HTTP-client lifecycle, the existing 1,024-page boundary, one-sided WAMP
metadata and resource-notification oracles are being strengthened before the
next full hosted run.
The current local diagnostic controls pass 451 fast CLI cases, 20 smoke-boundary
cases, both clean/restored MCP/native CLI baselines, 117 runner/CI contracts
(one existing skip) and the formerly red RawSocket batch with three correctly
classified compiler failures. Complete inventories now use 32/16 MCP/CLI shards
with all original per-job/per-command deadlines intact. Native JSON binding uses
the standard fused UTF-8/JSON decoder; all 1,895 binding cases pass on VM and
Chrome/Wasm, including malformed-input and owned-value controls. The microbench
shows lower decode cost but hosted WAMP budgets remain unqualified. PR #139
remains draft pending full final-head workflows and quiet bin/verify.
