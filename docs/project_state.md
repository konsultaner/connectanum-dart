# Project State

Last updated: 2026-11-18.
Current milestone: qualify the Dart 3.14.0 toolchain on the GitHub CI chain.
Active plan: [Dart 3.14 upgrade](exec-plans/2026-11-17-dart-3.14-upgrade.md).

CI repair resumed on 2026-11-18. The fix transfers large MessagePack worker
frames with `TransferableTypedData` to avoid receiver-side managed byte-array
clones. In an alternating hosted ARM64 comparison, original code fails the
58-MiB drained-RSS limit in two of four cold campaigns; all 20 fixed cycles
pass, with maximum drained RSS 33.96 MiB. Exact-byte, mutation, lazy/PPT and
native enqueue/error regressions pass. Deterministic native lifecycle, file
metrics and worker error tests add 29 hits on previously missed source lines.
All budgets, coverage requirements, workload, warm-up/drain and VM settings are
unchanged. Final local `bin/verify` and PR checks are in progress; see the active
plan for provenance. The earlier macOS capacity failure clears on one targeted
infrastructure retry, with all three ObjectBox platforms passing at `4de24d25`.

Standalone Dart setup, package publishing, diagnostic and ObjectBox jobs now
select 3.14.0, with matching pub-cache keys and `.tool-versions`. Package SDK
lower bounds remain 3.10.0. [PR #138](https://github.com/konsultaner/connectanum-dart/pull/138)
contains the isolated upgrade on current `master`.
The first PR CI run rejected the retention worker's old 3.13.1-only SDK guard.
Its strict guard now selects 3.14.0; six regression tests and real Linux ARM64
AOT/hosted Ubuntu qualification pass with all original GC and memory controls.
At `2d51a258`, hosted `bin/verify`, browser coverage, consumers, mutation gates,
package dry runs and all three ObjectBox platforms pass. All 55 main-CI jobs
pass after one unchanged repeat of gateway shard 1. Its first attempt had a
61.13-MiB cold-cycle drained RSS against a 58-MiB cap; the next four cycles
were 30–32 MiB. Original failure evidence is retained; the successful repeat
does not establish its cause. No budget is relaxed.

The documentation-only head `712e3896` fails gateway shard 1 again on the same
normal-runtime profile: first-cycle drained RSS is 60.78 MiB against the
unchanged 58-MiB cap; the next four cycles are about 30–33 MiB and separate
bounded retention controls pass. Failure/pass/failure establishes a recurring
qualification blocker, with root cause unresolved. No further retry, runtime
workaround or budget reduction is made. The final macOS ObjectBox job could not
acquire a hosted ARM64 runner and was cancelled before execution; Linux and
Windows pass. Source-identical earlier macOS evidence is retained separately.

`codecov/project` also failed at `2d51a258`: 60 of 61 PR checks passed, with
94.12% against the 94.16% base (17 fewer hits over the same 49,969 lines).
Changed-line coverage passes. Lost hits are in unchanged native lifecycle/error
and initial worker metadata paths. At the final checked source head
`712e3896`, hosted `bin/verify`, browser coverage, WampApp and all mutation gates
pass; main CI has 53 successful jobs and two failures (shard 1 plus dependent
Full Verify). Final `codecov/project` also fails at 94.14% versus 94.16%, with
11 fewer hits over the same 49,969 lines; patch coverage passes. The full
rollup is 57 success, three failure and one cancelled check. Exact measurements,
artifact digests and CI links are in the active plan. Acceptance remains
blocked; all coverage and memory requirements are unchanged. The concluding
receipt-only update changes documentation; source qualification is retained at
`712e3896`.

The earlier full local `bin/verify` passed on the mutation-runner branch; that
result does not certify this newer `master` base. This PR carries the SDK
upgrade, its strict test-worker qualification and verification record, with
the focused frame ownership repair described above.

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
| Dart 3.14 source `712e3896`, [CI](https://github.com/konsultaner/connectanum-dart/actions/runs/44103774510) | 53/55 jobs pass; recurrent shard-1 cold RSS failure blocks Full Verify; hosted `bin/verify` passes |
| Dart 3.14 full PR checks at `712e3896` | 57 success, three failure, one cancelled; Codecov project 94.14% vs 94.16%, macOS hosted runner unavailable |
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
