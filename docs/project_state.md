# Project State

Last updated: 2026-11-18.
Current milestone: Dart 3.14.0 CI qualification complete; PR #138 awaits review/merge.
Active plan: none. Completed plan: [Dart 3.14 upgrade](exec-plans/2026-11-17-dart-3.14-upgrade.md).

[PR #138](https://github.com/konsultaner/connectanum-dart/pull/138) qualifies
standalone Dart 3.14.0 across `.tool-versions`, CI setup/cache keys and all
eight package publishing jobs. Package SDK lower bounds stay at 3.10.0; the
retention worker strictly accepts the qualified 3.14.0 stable SDK with its
original VM/witness/collection controls.

Final implementation `9dc7b2d4` passes **all 61 PR checks**, including every
one of the 55 main jobs, all 16 gateway performance/memory shards, all mutation
and coverage lanes, package dry run and ObjectBox on three operating systems.
No checks are skipped or cancelled. Codecov project passes at 94.20% versus
base 94.16%; patch coverage is 100%. Complete local `bin/verify` also passes
on this exact source, including Rust/native FFI, VM suites, consumers, ObjectBox
and real Chrome/Dart2Wasm (4,814 core / 2,830 client, with 20 existing native-only
browser test skips).

The repairs transfer large serialized worker frames and give large native
MQTT input bodies independently owned external storage with native-free
lifetime and SDK external-size accounting. GuardMalloc fixtures establish
actual backpressure/readiness before their measured fast-write or cleanup
boundaries and release unsubmitted slices on unwind. Deterministic failure,
ownership and metadata tests replace previously missing coverage. Production
Rust, all numeric budgets, coverage/mutation requirements, queues, workload,
warm-up/drain, normal VM settings, production timeout drivers and CI workflows
remain unchanged by these repairs. No forced production collection is added.

Regular final-source measurements put MessagePack drained RSS at 27.00 MiB
versus 58 MiB, CBOR peak at 40.82 MiB versus 63 MiB, and overload peak at
78.21 MiB versus 126 MiB. Native GuardMalloc and all original controls pass;
additional hosted Intel qualification covers five full native inventories
(440 cases) and five captured control inventories (25 cases), with exact
source hashes. Earlier failures, rejected candidates and checksum-verified
receipts remain in the completed plan. This receipt follow-up changes only
documentation; implementation qualification is retained at `9dc7b2d4`.

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
