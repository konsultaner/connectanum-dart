# Project State

Last updated: 2026-11-18.
Current milestone: final-head CI qualification of the managed-input QoS/gateway repair.
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
use the existing bounded fragment path. Native MQTT input uses the Core
decoder’s owned managed bytes; heap snapshots have their independent native
owner, independent of runtime shutdown.

All 41 fanout cases pass unchanged identity/content/count assertions. New tests
cover source mutation, two isolate hops, public mutable recipients, optional old
native libraries, native/SDK failure cleanup and actual GC. All 93 native
ownership cases pass GuardMalloc. The corrected heap variant completes full
`bin/verify`, including real Chrome/Dart2Wasm, with all 19 source/test/tool files
unchanged. The App-Lab process race has a deterministic failing regression;
rechecking child liveness after failed `ps` fixes it, with all 16 App-Lab tests
passing and every deadline preserved.

The singleton repair `669a7bc8` passes all 43 gateway regressions, full local
verification and its cold ARM64 comparison: 40 normal cycles peak at 34.14/63
MiB, p99 1,665–1,738/2,437 us, and six overload cycles peak at 52.56/126 MiB.
Its regular CI then finds a separate standalone MQTT 64-KiB/window-32 blocker:
throughput ratio 0.7416/0.75, CPU ratio 4.095/4, p95 ratio 2.342/2 and p99
2.278/2.25; memory remains below 96 MiB. That head is not accepted. Twenty-nine
checks pass before the obsolete failing workflow is cancelled for requalification.

The standalone broker decodes its packets in Dart, so mapping every large input
body adds work to that path. Restoring SDK-finalized external heap input fixes
CPU/latency but fails the unchanged 96-MiB memory limit in both cold campaigns;
that intermediate candidate is rejected. The current candidate instead uses
the existing Core decoder’s owned managed body, retaining immutable shared
native snapshots and singleton fragments. Its two strict QoS campaigns pass:
throughput ratios 0.9205/0.9629 (minimum 0.75), CPU 2.917/3.182 (maximum 4), p95
1.102/1.019 (maximum 2), p99 1.117/1.050 (maximum 2.25), and peak 54.38/55.68
MiB against 96 MiB. Original mapping fails CPU in both matching campaigns.

The managed input’s complete bytes and view lifetime after runtime disposal
remain covered by actual GC; independent native snapshot ownership still has
its exact release counter. The unchanged ARM64 comparison also passes all 40
normal and six overload candidate cycles: normal peak 31.39/63 MiB, p99 1,429–1,541/2,437 us; overload
75.15/126 MiB. All candidate production source hashes exactly match. Complete local `bin/verify`
passes on all 20 unchanged source/test/tool files, including real Chrome/
Dart2Wasm (4,814 Core and 2,830 client cases; 20 existing native-only browser
skips). Complete final-head CI remains open.

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
| Managed-input repair, [strict standalone QoS](https://github.com/konsultaner/connectanum-dart/actions/runs/44339526524) | Both cold campaigns pass every original CPU/rate/latency/RSS gate; peaks 54.38/55.68 MiB against 96 MiB |
| Managed-input repair, [cold gateway comparison](https://github.com/konsultaner/connectanum-dart/actions/runs/44339531343) | All 40 normal/six overload candidate cycles pass available absolute checks; peaks 31.39/63 MiB and 75.15/126 MiB |
| Managed-input repair, complete local `bin/verify` | Pass, all 20 source/test/tool hashes unchanged; Rust/native/VM/consumers/Chrome/Wasm; final PR CI pending |
| Mapped-input singleton repair, [cold comparison](https://github.com/konsultaner/connectanum-dart/actions/runs/44327753894) | All 40 normal and six overload candidate cycles meet available absolute checks; normal 34.14/63 MiB, p99 1,665–1,738/2,437 us |
| Mapped-input singleton repair, complete local `bin/verify` | Pass, all source hashes unchanged; Rust/native, full VM/consumers and real Chrome/Wasm; full final-head PR CI pending |
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
