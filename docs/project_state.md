# Project State

Last updated: 2026-11-03.
Current priority: [MQTT milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), explicitly prioritized by the user.
Active plan: [MQTT interoperability](exec-plans/2026-10-14-mqtt-broker-interoperability.md).
Branch: `codex/mqtt-ci-skipped-checks`, based on merged `ef1479d6`.
[PR #135](https://github.com/konsultaner/connectanum-dart/pull/135) merged on 2026-11-03.
Current work: keep optional manual diagnostics out of automatic PR check runs.

The opt-in QoS 0 gateway implements #116/#117: realm authorization, trusted WAMP
caller identity, binary publications, bounded queues, cancellation and teardown.
Direct MQTT 5/3.1.1 TCP/TLS/WS/WSS merged in PR #128. Ordinary MQTT PPT remains
opaque. The [contract](mqtt.md) includes configuration and client examples.

## Current qualification

Runtime source `839bbf6e` releases sent CALL payloads while replies remain pending,
shares binary publications and FlatBuffers frame bodies across recipient workers,
and returns unused native allocator pages after peer disconnects. Frames enter
native-owned storage through the existing ABI. Control/profile acceptance,
per-peer backpressure, custom-worker fallback and payload ownership are covered
by regression tests.

| Check | Verified result |
| --- | --- |
| Frozen-source `bin/verify`, Rust, Dart, consumers, Chrome and Wasm | Passed at 14:40 UTC; clean source, no runtime drift |
| Gateway/shared Dart coverage | 1,016 / 1,016 executable lines |
| Gateway tooling, zero exclusions | 1,084 / 1,084 statements |
| Added native production lines, matching source hashes | 979 / 979 |
| Broad router/MQTT/Paho/native / final worker-live / recipient-error checks | 1,039 / 171 / 6 cases passed |
| Same-host ABBA, 64 KiB FlatBuffers fan-out | All twenty samples audited; 400,000 exact deliveries; zero duplicates |
| Paired broker drained RSS, baseline → candidate | 56–62 MiB → 34–40 MiB; unchanged 54 MiB cap |
| Paired broker CPU seconds per million deliveries | 249.7–251.7 → 214.4–220.1 |
| Strict pilot | All eighty samples pass; 1.6 million exact deliveries; zero duplicates |
| WSS slow-peer recovery audit | 8,192 exact deliveries plus 256 recovery; zero duplicates |
| Complete sixteen-shard qualification | All 1,304 samples pass; 64 translation and 4 overload results; zero duplicates |
| Independent secure smoke | All 264 samples verified, both clients, four transports/codecs, fault and retention controls |
| Follow-up working-branch `bin/verify` and table checks | Passed at 17:37 UTC, including Chrome/Wasm; all 29 table/fixture checks pass; no source drift during verification |
| Final gateway publication CI | All 59 checks pass, with two optional manual diagnostic jobs skipped; all 1,304 benchmark and 264 secure samples independently verified |

[Final publication CI](https://github.com/konsultaner/connectanum-dart/actions/runs/41493246321)
qualifies `0a74ca76`, now merged as `ef1479d6`. Its 55 artifacts and the first
publication's 53 artifacts are retained in a downloaded, fully verified CI
supplement. The history archive verifies all 57,941 files; its CI supplement
verifies all 25,937 files. Gateway, native and tooling coverage remain 100%.

The two skipped checks came from manual-only gateway and Intel diagnostic modes
in the PR profiling workflow. The current follow-up separates those entry points.
Main CI's required gateway smoke, all sixteen numeric shards, coverage and strict
Full Verify dependencies remain unchanged. Normal PR CPU profiling continues to
execute a real diagnostic; manual-only jobs will not register as skipped checks.

[Complete source qualification](https://github.com/konsultaner/connectanum-dart/actions/runs/41464161501)
measures both translation directions, direct MQTT/WAMP controls, CPU, latency,
per-process peak/drained RSS and separate retained-memory growth. Default-runtime
performance and absolute RSS retain every original numeric budget. Stress-only
collection uses a bounded nursery and independently validated managed/native
negative controls; its timings are excluded from performance claims.

Current figures live in the [package README tables](../packages/connectanum_bench/README.md#mqtt-and-wamp-gateway).
Compact offline fixtures verify every displayed cell. Full raw captures, source
snapshots, coverage reports, paired comparisons and rejected experiments live in
the [checksum-verified benchmark archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-retention-2026-11-02).
The source-hash proof binds unchanged native coverage to its actual GNU reports;
a shallow-history proof-assembly failure was recovered from those exact reports,
with all 93 collection inputs independently verified. No measurements were rerun
or discarded during recovery.

## Remaining readiness work

The gateway is merged. The CI routing follow-up requires local verification
and its own PR checks. The broader milestone remains open
for QoS 1/2, retained messages/wills, persistence, credential authentication,
complete MQTT properties and release conformance.

#131's controlled-hardware release sign-off remains open: the last runner audit
found no registered GitHub self-hosted runner or confirmed exclusive GitLab Linux
reservation. Hosted ARM64 regression gates remain on GitHub Actions.

Pre-existing auxiliary blockers remain: strict kTLS lacks Linux TLS ULP support;
WAMP diagnostics miss their existing buffered file/heavy RawSocket floors.
Native TCP_NODELAY passes all twelve sustained comparisons in
[41322497967](https://github.com/konsultaner/connectanum-dart/actions/runs/41322497967).
[ObjectBox PR #133](https://github.com/konsultaner/connectanum-dart/pull/133)
published 3.0.0-beta.8. The [FlatBuffers plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md)
remains deferred/reference work during the MQTT priority.
