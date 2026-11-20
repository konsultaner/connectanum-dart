# Project State

Last updated: 2026-11-20.
Current milestone: repair WAMP and mutation diagnostics without relaxing gates.
Active plan: [WAMP and mutation diagnostic repair](exec-plans/2026-11-19-wamp-mutation-diagnostics.md).
Completed plan: [Dart 3.14 upgrade](exec-plans/2026-11-17-dart-3.14-upgrade.md).

PR #138 is merged into `master` at `0a3d96e6`. Its mandatory main CI passes all
55 jobs and all sixteen performance/memory shards. Additional WAMP diagnostics
fail fragmentation/file-transfer throughput floors; full mutation diagnostics
show native restored-baseline errors and MessagePack/MCP CLI assertion scores
below the original 95% gates. The new active plan records the exact failures;
the broader diagnostic chain is not qualified. No threshold or inventory is
relaxed. The previous Dart upgrade qualification below remains historical
source evidence rather than a claim that these additional workflows pass.

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
