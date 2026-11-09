# Project State

Last updated: 2026-11-06.
Current milestone: coordinated `3.0.0-beta.9` publication completed on 2026-11-06.
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
