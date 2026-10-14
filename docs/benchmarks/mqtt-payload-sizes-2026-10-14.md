# MQTT payload-size performance checkpoint

Date: 2026-10-14. Source: `e7591c86` on an Apple M3 Ultra. The source tree was clean for every run. This local comparison is not a cross-machine release claim.

The native MQTT QoS 0 benchmark now varies payload size and checks 128 B, 1 KiB and 64 KiB publications against Mosquitto 2.1.2. Each profile uses the same AOT Connectanum client for both brokers, five order-balanced pairs, one subscriber and a bounded publish window. Every one of the 30 raw rows has exact payload bytes, ordered delivery, the expected message count and zero duplicates. The summaries retain the source, native-library and AOT binary hashes.

The first 64 KiB calibration disconnected a subscriber: coalesced publications exceeded the native FFI writer's 1 MiB chunk limit. A fail-first broker test reproduced that error. The broker now splits a coalesced burst into chunks at or below 1 MiB, flushes those chunks in order after publication routing and counts preflush chunks together with the retry queue against the 4 MiB peer budget. Regression tests cover the FFI limit, terminal writer failure, a burst exceeding the bound, a full queue followed by a control reply and ordering across transient queue saturation.

| Native MQTT 5 TCP profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Peak Connectanum RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128 B, 200,000 messages, window 512 | 393,629 | 416,589 | 0.945 | 1.079 | 1.115 | 2.071 | 41.1 MiB |
| 1 KiB, 100,000 messages, window 256 | 244,326 | 270,477 | 0.903 | 1.235 | 1.226 | 1.926 | 52.3 MiB |
| 64 KiB, 5,000 messages, window 32 | 9,695 | 10,703 | 0.906 | 1.183 | 1.198 | 3.125 | 72.4 MiB |

The new 1 KiB and 64 KiB profiles each require at least 0.75 of Mosquitto's delivered throughput, at most 2.0/2.25 times its p95/p99 latency, and bounded broker CPU and RSS. The 1 KiB CPU/RSS limits are 3.0 times Mosquitto and 64 MiB; the 64 KiB limits are 4.0 times Mosquitto and 96 MiB. All three profiles pass their checked-in budgets locally. The 64 KiB broker CPU ratio remains a performance target for later tuning. Controlled release measurements are still required; TLS, WebSocket, fan-out and higher QoS payload-size profiles remain open.

Hosted Linux at `aa00139e` completes all 14 profiles with exact delivery, but the 64 KiB native profile misses its CPU gate: 0.73 versus 0.13 broker CPU seconds, ratio 5.615 against a 4.0 cap. Its throughput ratio 0.858, p95 1.458, p99 1.214 and peak RSS 90.1 MiB all pass. The remaining 13 profiles pass. This is a release blocker; the local table above does not supersede the hosted result. A direct PUBLISH encoder candidate reduces the dirty-tree local 64 KiB broker CPU from 0.50 to 0.42 seconds; its hosted run follows below.

Hosted `47aed4d2` reaches 598/598 MQTT Dart and 226/226 Python benchmark lines with exact delivery in all 140 matched rows, but three budgets miss: Dart-only MQTT 5/3.1.1 sustained throughput ratios 0.716/0.746 against 0.75, and native 64 KiB broker CPU 1.26/0.16 seconds (ratio 7.875) against 4.0. The optimized encoder also accelerates the common AOT benchmark client, so the small-payload Mosquitto baseline changes; a controlled same-source rerun remains necessary. A local follow-up keeps packets at or above 64 KiB out of the broker's coalescing copy while retaining its 4 MiB pending-byte limit and queue retry. The five-pair native 64 KiB median is 0.37 broker CPU seconds versus roughly 0.43 before that change; a one-pair 50,000-publication stress run delivers exactly with no disconnect. This improvement is provisional until hosted proof passes the unchanged limits.

Hosted [`b653424f`](https://github.com/konsultaner/connectanum-dart/actions/runs/38641132486/job/116117380485) delivers all 140 matched rows exactly and reaches 607/607 scoped MQTT Dart lines. Thirteen of fourteen unchanged budgets pass. Native 64 KiB improves to 0.69 versus 0.16 broker CPU seconds, ratio 4.3125 against the 4.0 cap; throughput 0.944 and p95/p99 1.147/1.125 pass. The earlier Dart-only MQTT 5/3.1.1 throughput misses recover to 0.772/0.821. This remains a red hosted gate. A dirty-tree native-read experiment raises TCP read and Dart poll buffers from 16 to 64 KiB with residual slicing for legacy 16 KiB callers; five local 64 KiB and 1 KiB pairs pass exact delivery and unchanged budgets. Hosted proof is required before adoption.

The initial payload-size checkpoint had exact 583/583 focused MQTT VM lines; the latest hosted source reaches 607/607 across the same five required production files. The 36 Python gate regressions and full `bin/verify` pass at exit 0. The new CI run must establish hosted benchmark and exact Python gate coverage on the new source.

| Profile | Summary | Raw matched rows |
| --- | --- | --- |
| 128 B native TCP | [summary](mqtt-payload-e7591c86-128-summary.json) | [raw](mqtt-payload-e7591c86-128-raw.jsonl) |
| 1 KiB native TCP | [summary](mqtt-payload-e7591c86-1k-summary.json) | [raw](mqtt-payload-e7591c86-1k-raw.jsonl) |
| 64 KiB native TCP | [summary](mqtt-payload-e7591c86-64k-summary.json) | [raw](mqtt-payload-e7591c86-64k-raw.jsonl) |
