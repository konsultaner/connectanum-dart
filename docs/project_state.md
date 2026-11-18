# Project State

Last updated: 2026-11-18.
Current milestone: qualify the Dart 3.14.0 toolchain on the GitHub CI chain.
Active plan: [Dart 3.14 upgrade](exec-plans/2026-11-17-dart-3.14-upgrade.md).

[PR #138](https://github.com/konsultaner/connectanum-dart/pull/138) pins standalone
Dart to 3.14.0 in `.tool-versions`, GitHub setup/cache keys and all eight package
publishing jobs. Package SDK lower bounds stay at 3.10.0. The strict retention
worker SDK guard is qualified for exactly 3.14.0, retaining its existing VM,
witness and collection controls.

The CI repair transfers large serialized worker frames rather than cloning
them into the receiver's managed heap. Exact bytes, mutation, lazy/PPT,
ordering, scratch bounds and native enqueue/error regressions pass. Regular
MessagePack and CBOR shards now pass. Deterministic native lifecycle, file
metrics and worker error tests cover 29 previously missed lines; both Codecov
checks pass at `f3798ef4` (project 94.20% versus base 94.16%). Its complete
rollup is 58 success / 3 failure: the native GuardMalloc fixture, overload
shard 0 and dependent Full Verify remain red.

The native fixture follow-up establishes slow backpressure before arming the
fast reader and releases unsubmitted slices on unwind. All payloads, six
variants, instrumentation, five-second I/O/receipt bounds and 120-second group
bound remain. Local GuardMalloc and five hosted Intel inventories pass
(440 cases); production Rust is unchanged. Complete local `bin/verify` passes
on this native follow-up plus the all-codec frame repair.

For overload peak RSS (141.38 MiB versus the unchanged 126-MiB cap), the native
MQTT decoder now copies into independently owned external storage for large
bodies, with native-free lifetime and SDK external-size accounting. The paired
hosted experiment passes all 12 fixed cycles, maximum 91.09 MiB; the original
fails all 12. Framing and native GC-lifetime regressions pass. The separate
input-event transfer candidate failed 11/12 cycles and was discarded.
A subsequent control-test startup race is reproduced with delayed Python
startup: timeout/kill tests now establish their real fixture readiness before
the unchanged 0.2/0.3-second wait. The SIGKILL negative control still catches an
escaping descendant. Final-source `bin/verify` and the complete PR checks are
still required before acceptance. Workload, queues, warm-up/drain, VM settings, coverage/mutation
requirements, numeric budgets, production verification drivers and CI workflows are
unchanged by these repairs. See the [active plan](exec-plans/2026-11-17-dart-3.14-upgrade.md) for
failure history, rejected candidates and exact qualification receipts.

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
| Dart 3.14 source `f3798ef4`, [CI](https://github.com/konsultaner/connectanum-dart/actions/runs/44252531253) | 52/55 jobs pass; GuardMalloc fixture, overload shard 0 and dependent Full Verify fail; all normal gateway profiles pass |
| Dart 3.14 full PR checks at `f3798ef4` | 58 success / 3 failure; both Codecov checks green (project 94.20% vs 94.16%); package dry run and all ObjectBox platforms pass |
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
