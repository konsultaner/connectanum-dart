# Project State

Last updated: 2026-11-18.
Current milestone: final-head CI qualification of the Dart 3.14 repair.
Active plan: [Dart 3.14 upgrade](exec-plans/2026-11-17-dart-3.14-upgrade.md).

[PR #138](https://github.com/konsultaner/connectanum-dart/pull/138) pins standalone
Dart 3.14.0 across `.tool-versions`, CI/cache keys and all eight publishing jobs.
Package SDK lower bounds remain 3.10.0. Implementation `9dc7b2d4` passed all 61
checks and complete local `bin/verify`, including real Chrome/Dart2Wasm.
Documentation-only head `2bd89a33` then reproduced CBOR peak RSS at 79.28 MiB
against the original 63-MiB cap; acceptance is reopened. Its other 59 checks
pass, including GuardMalloc, all mutation/coverage lanes and three ObjectBox
platforms. Earlier green results do not clear the current head.

Independent Linux OS, VM and allocator observations confirm real resident peaks.
At the 78.76-MiB peak, managed old-heap use is 4.4 MiB while libc retains
32.8 MiB of freed allocations. Mapping only native input, ordinary external
arrays, managed snapshots and managed snapshots plus mapped input all fail
repeated cold comparisons. The last combination peaks at 66.75 MiB against
63 MiB. Functional verification alone does not qualify these candidates.

A minimal Dart 3.14 Linux ARM64 AOT repro distinguishes ordinary readonly views
(which SendPort copies) from VM-created immutable external typed data (which
shares identity across isolate hops). The current candidate snapshots large
internal binary values into independently owned heap storage and publishes
these through `Dart_NewUnmodifiableExternalTypedDataWithFinalizer`. A private
carrier preserves that ownership contract; remote routing retains the immutable
backing, while public callbacks receive mutable owned copies. Older native
libraries/VMs keep the existing transfer fallback. Default eligible CBOR Events
use the existing bounded fragment path. Native MQTT input mappings and heap snapshots
each have one owner, independent of runtime shutdown.

All 41 fanout cases pass unchanged identity/content/count assertions. New tests
cover source mutation, two isolate hops, public mutable recipients, optional old
native libraries, native/SDK failure cleanup and actual GC. All 93 native
ownership cases pass GuardMalloc. The corrected heap variant completes full
`bin/verify`, including real Chrome/Dart2Wasm, with all 19 source/test/tool files
unchanged. The App-Lab process race has a deterministic failing regression;
rechecking child liveness after failed `ps` fixes it, with all 16 App-Lab tests
passing and every deadline preserved.

The current candidate also keeps singleton binary Events on the negotiated
fragment path. Both new singleton regressions and all 41 prior fanout cases
pass on macOS and Linux, including legacy workers. In the unchanged cold
comparison, all 40 candidate normal cycles and six overload cycles meet every
available absolute CPU/rate/latency/process-memory check: normal peak 34.14/63
MiB, p99 campaign medians 1,665–1,738/2,437 us; overload peak 52.56/126 MiB.
All candidate production source hashes exactly match the working tree.
Earlier mapped and heap-only candidates remain rejected; GC traces retain
the evidence behind the missing singleton path. Fresh full `bin/verify` on the
20-file source passes, including Rust/native, VM, consumers and real
Chrome/Dart2Wasm. Complete relative-control, collected-retention
and all-profile acceptance still requires all checks on the final PR head.

All numeric budgets, coverage/mutation thresholds, queues, workloads,
warm-up/drain/stall durations, default VM options and original timeout controls
remain unchanged. No forced production GC or global allocator tuning is added.
The plan retains original failures, rejected candidates and checksum-verified
evidence. No merge or release is performed.

Latest release: coordinated `3.0.0-beta.9` publication completed on 2026-11-06.
All eight Dart packages are public, with matching signed native assets for five
platforms. [Release and evidence](https://github.com/konsultaner/connectanum-dart/releases/tag/v3.0.0-beta.9).
Completed plan: [beta.9 release](exec-plans/2026-11-06-3.0.0-beta.9-release.md).
[PR #137](https://github.com/konsultaner/connectanum-dart/pull/137) retains normal
GitHub review for the version metadata and release record. Publication used the
fully qualified commit `72c078f1`; no branch protection was bypassed.

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
| Current Dart 3.14 repair, [cold comparison](https://github.com/konsultaner/connectanum-dart/actions/runs/44327753894) | All 40 normal and six overload candidate cycles meet available absolute checks; normal 34.14/63 MiB, p99 1,665–1,738/2,437 us |
| Current 20-file repair, complete local `bin/verify` | Pass, all source hashes unchanged; Rust/native, full VM/consumers and real Chrome/Wasm; full final-head PR CI pending |
| Dart 3.14 source `9dc7b2d4`, [CI](https://github.com/konsultaner/connectanum-dart/actions/runs/44268728740) | All 55 main jobs pass, including all 16 memory/performance shards |
| Dart 3.14 full PR checks at `9dc7b2d4` | All 61 checks pass, zero skipped/cancelled; Codecov project 94.20% vs 94.16%, patch 100% |
| Dart 3.14 final-source local `bin/verify` | Pass, Rust/native/Dart/consumers/ObjectBox/Chrome/Wasm; clean worktree at completion |
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
