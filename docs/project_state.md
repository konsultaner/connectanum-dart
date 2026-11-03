# Project State

Last updated: 2026-11-02.
Current priority: [MQTT milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), explicitly prioritized by the user.
Active plan: [MQTT interoperability](exec-plans/2026-10-14-mqtt-broker-interoperability.md).
Branch: `codex/mqtt-wamp-gateway`, based on `ef822e08`.
Current PR: [#135](https://github.com/konsultaner/connectanum-dart/pull/135), open and not draft.

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
| Publication CI follow-up | First run passes all sixteen numeric shards and secure smoke; fixture/runner fixes pass locally and await the next exact-head run |

Publication CI `e1bae7ad` delivered all four test payloads but observed two workers
where its fixture assumed one. The fixture now waits for the configured minimum
pool to register before connecting clients and asserts its actual topology;
all 55 gateway integration cases pass under VM coverage. `bin/test-fast` and the
complete follow-up `bin/verify` pass. Runtime code and numeric
budgets are unchanged. The ownership job executed no steps because GitHub could
not acquire an ARM64 macOS runner. It now uses the supported `macos-15-intel`
label; gateway benchmark runners remain ARM64. The cancelled assignment and
failed test log are retained with the publication CI evidence.
All sixteen first-publication numeric shards pass, and all 264 secure samples
were independently audited. Its 53 artifacts were captured and their immutable
GitHub digests verified. The complete first run remains recorded as failed;
the next exact-head checks and downloaded CI supplement provide final acceptance.

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

PR #135 requires code-owner review. Its merge needs new user authorization;
the earlier admin merge applied to PR #128. The broader milestone remains open
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
