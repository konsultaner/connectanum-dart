# connectanum_bench

Connectanum benchmark results for MQTT publish/subscribe and WAMP transports.
The package runs the WAMP and HTTP workloads; the MQTT runner lives under
`packages/connectanum_router/benchmark/`.

## MQTT publish and subscribe

This table shows all QoS 0 profiles from the [GitHub Actions run of candidate `6790909b`](https://github.com/konsultaner/connectanum-dart/actions/runs/40929728718/job/123644737494)
on Ubuntu 24.04 and AMD EPYC 9V74, compared with Mosquitto 2.0.18.
C / M means Connectanum / Mosquitto. Higher delivery rate is better; lower
latency and broker CPU ratios are better. Peak RSS is Connectanum broker memory.
Workload counts are publications per run; fan-out rates count deliveries to all
subscribers. WS means WebSocket and WSS means secure WebSocket. Smoke rows
check delivery only. 19 of 20 profiles pass. WebSocket MQTT 3.1.1 misses its throughput floor. Passing EPYC 7763 results appear below; Intel CPU acceptance remains open.

| Broker | MQTT / link | Workload | Delivered/s C / M | Rate × | p95 / p99 C/M × | Broker CPU C/M × | Peak RSS | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Dart | 5 / TCP | 128 B, 2k, single smoke | 72,770 / 88,842 | 0.819 | 1.740 / 1.738 | 1.500 | 10.5 MiB | Delivery pass |
| Dart | 5 / TCP | 128 B, 200k, single | 109,628 / 93,148 | 1.177 | 1.207 / 1.318 | 0.981 | 11.2 MiB | Pass |
| Dart | 3.1.1 / TCP | 128 B, 200k, single | 113,387 / 97,961 | 1.157 | 1.109 / 1.283 | 0.985 | 11.1 MiB | Pass |
| Dart | 5 / TCP | 128 B, 200k, batch 512 | 660,921 / 92,732 | 7.127 | 0.161 / 0.151 | 0.069 | 17.5 MiB | Pass |
| Dart | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 926,316 / 102,434 | 9.043 | 0.093 / 0.115 | 0.054 | 10.7 MiB | Pass |
| Native | 5 / TCP | 128 B, 2k, single smoke | 86,923 / 90,855 | 0.957 | 1.394 / 1.406 | 2.000 | 21.2 MiB | Delivery pass |
| Native | 5 / TCP | 128 B, 200k, single | 110,765 / 95,444 | 1.161 | 1.114 / 1.088 | 1.330 | 21.9 MiB | Pass |
| Native | 3.1.1 / TCP | 128 B, 200k, single | 107,923 / 96,204 | 1.122 | 1.052 / 1.020 | 1.409 | 22.0 MiB | Pass |
| Native | 5 / TCP | 1 KiB, 100k, single | 81,022 / 6,605 | 12.267 | 0.070 / 0.079 | 1.206 | 31.0 MiB | Pass |
| Native | 5 / TCP | 64 KiB, 5k, single | 6,145 / 6,888 | 0.892 | 1.148 / 1.098 | 3.000 | 58.1 MiB | Pass |
| Native | 5 / TCP | 128 B, 200k, batch 512 | 644,935 / 95,606 | 6.746 | 0.156 / 0.175 | 0.080 | 27.8 MiB | Pass |
| Native | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 880,220 / 106,931 | 8.232 | 0.113 / 0.123 | 0.067 | 21.5 MiB | Pass |
| Native | 5 / TLS | 128 B, 200k, single | 253,958 / 32,435 | 7.830 | 0.124 / 0.123 | 0.476 | 23.7 MiB | Pass |
| Native | 3.1.1 / TLS | 128 B, 200k, single | 249,822 / 32,185 | 7.762 | 0.124 / 0.123 | 0.493 | 23.9 MiB | Pass |
| Native | 5 / WS | 128 B, 200k, single | 42,104 / 55,621 | 0.757 | 1.372 / 1.426 | 2.063 | 22.0 MiB | Pass |
| Native | 3.1.1 / WS | 128 B, 200k, single | 39,073 / 56,299 | 0.694 | 1.510 / 1.582 | 2.221 | 22.1 MiB | **Fail** |
| Native | 5 / WSS | 128 B, 2k, single smoke | 86,188 / 25,167 | 3.425 | 0.292 / 0.401 | 0.667 | 23.7 MiB | Delivery pass |
| Native | 5 / WSS | 128 B, 200k, batch 64 | 136,787 / 28,169 | 4.856 | 0.238 / 0.241 | 0.273 | 23.9 MiB | Pass |
| Native | 3.1.1 / WSS | 128 B, 2k, single smoke | 68,932 / 23,433 | 2.942 | 0.391 / 0.530 | 0.667 | 23.5 MiB | Delivery pass |
| Native | 3.1.1 / WSS | 128 B, 200k, single | 138,707 / 29,319 | 4.731 | 0.204 / 0.204 | 0.393 | 24.4 MiB | Pass |

| Check | Result |
| --- | --- |
| Direct MQTT delivery | 29,114,000 expected and received across 192 benchmark samples; zero duplicates |
| Profile results | 19 of 20 passed: 15 performance profiles and 4 delivery-only smoke profiles |
| WebSocket throughput budget | MQTT 5 / 3.1.1 rate ratios 0.757× / **0.694×** against a 0.700× floor |
| 64 KiB CPU budget | 3.000× broker CPU ratio against a 4.000× cap on this AMD runner |
| MQTT ↔ WAMP translation | No benchmark yet; the live gateway is pending |
| Typed FlatBuffers PPT parity | No accepted performance result yet; outer-envelope measurements appear below |

| Hosted run and CPU | WS 5 rate × | WS 3.1.1 rate × | TCP 3.1.1 rate × | 64 KiB CPU × | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Required limit | ≥0.700 | ≥0.700 | ≥0.750 | ≤4.000 | — |
| [Latest `6790909b`](https://github.com/konsultaner/connectanum-dart/actions/runs/40929728718/job/123644737494), EPYC 9V74 | 0.757 | 0.694 | 1.122 | 3.000 | **Fail (WS rate)** |
| [Previous `ffc417a9`](https://github.com/konsultaner/connectanum-dart/actions/runs/40924130512/job/123625425453), EPYC 7763 | 0.778 | 0.807 | 1.125 | 2.708 | Pass |
| [Previous `7e1b8727`](https://github.com/konsultaner/connectanum-dart/actions/runs/40914337468/job/123591372808), EPYC 9V74 | 0.756 | 0.760 | 1.051 | 3.133 | Pass |
| [Previous `e7e9585d`](https://github.com/konsultaner/connectanum-dart/actions/runs/40900606891/job/123542245755), EPYC 7763 | 0.672 | 0.668 | 0.840 | 2.952 | Fail (WS rate) |
| [Reverted experiment `1660422d`](https://github.com/konsultaner/connectanum-dart/actions/runs/40873085554/job/123444869138), EPYC 7763 | 0.645 | 0.649 | 0.831 | 3.727 | Fail (WS rate) |
| [Same experiment](https://github.com/konsultaner/connectanum-dart/actions/runs/40873092619/job/123444901951), EPYC 9V45 | 0.824 | 0.814 | 1.025 | 3.417 | Pass |
| [Baseline `9aa6b17d`](https://github.com/konsultaner/connectanum-dart/actions/runs/40738597149/job/122994405521), EPYC 7763 | 0.647 | 0.646 | 0.827 | 3.727 | Fail (WS rate) |
| [Same-code repeat `84b22de8`](https://github.com/konsultaner/connectanum-dart/actions/runs/40728294139/job/122957384343), EPYC 9V74 | 0.760 | 0.760 | 1.045 | 3.375 | Pass |
| [Measured `2dea8b8e`](https://github.com/konsultaner/connectanum-dart/actions/runs/40723591569/job/122941052743), Xeon 8370C | 0.861 | 0.874 | 0.871 | 4.200 | Fail (64 KiB CPU) |
| [Prior `055e5739`](https://github.com/konsultaner/connectanum-dart/actions/runs/40720148060/job/122929058502), EPYC 9V74 | 0.751 | 0.748 | 0.974 | 3.190 | Pass |
| [Prior `780145ec`](https://github.com/konsultaner/connectanum-dart/actions/runs/40712686931/job/122903873214), EPYC 9V45 | 0.845 | 0.839 | 1.032 | 3.333 | Fail (WSS p99) |
| [Prior `8f65e2ae`](https://github.com/konsultaner/connectanum-dart/actions/runs/40697536943/job/122849485870), EPYC 7763 | 0.683 | 0.691 | 0.968 | 3.682 | Fail |
| [Prior `38910e96`](https://github.com/konsultaner/connectanum-dart/actions/runs/40690921222/job/122825185662), EPYC 7763 | 0.687 | 0.682 | 0.914 | 3.905 | Fail |
| [Prior retry](https://github.com/konsultaner/connectanum-dart/actions/runs/39788086482/job/122798346858), EPYC 7763 | 0.657 | 0.647 | 0.718 | 3.952 | Fail |
| [First exact-head run](https://github.com/konsultaner/connectanum-dart/actions/runs/39788086482/job/119859421236), EPYC 7763 | 0.656 | 0.653 | 0.830 | 3.696 | Fail |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39778169837/job/119822330473), EPYC 9V45 | 0.822 | 0.813 | 0.994 | 3.455 | Pass |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39411135727), Intel Xeon 6973P-C | — | — | — | 5.000 | Fail |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967), Intel Xeon 8573C | — | — | — | 4.294 | Fail |

The [latest results](../../docs/benchmarks/mqtt-hosted-pr128-6790909b.json),
[passing EPYC 7763 results](../../docs/benchmarks/mqtt-hosted-pr128-ffc417a9.json),
[baseline results](../../docs/benchmarks/mqtt-hosted-pr128-9aa6b17d.json),
[Intel results](../../docs/benchmarks/mqtt-hosted-pr128-2dea8b8e.json)
and [passing AMD repeat](../../docs/benchmarks/mqtt-hosted-pr128-84b22de8.json)
include every sample, workload setting, limit, and runner detail. The
[earlier passing AMD run](../../docs/benchmarks/mqtt-hosted-pr128-055e5739.json),
[WSS latency regression](../../docs/benchmarks/mqtt-hosted-pr128-780145ec.json)
and an [earlier passing AMD snapshot](../../docs/benchmarks/mqtt-hosted-amd-fccc7566.json)
are available for comparison. These results describe this measured run; QoS 0
does not guarantee delivery in every deployment.

The buffered-frame experiment was reverted because the EPYC 7763 gate remained
red. Its [same-runner comparison](../../docs/benchmarks/mqtt-native-comparison-1660422d.json)
shows small, mixed changes on EPYC 9V45. Higher delivery rate and lower CPU time are better.

| Workload | Metric | Baseline 1 | Candidate 1 | Baseline 2 | Candidate 2 |
| --- | --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | Deliveries/s | 57,364 | 57,607 | 55,134 | 55,776 |
| WS MQTT 5 | Broker CPU seconds | 4.26 | 4.13 | 4.45 | 4.35 |
| WS MQTT 3.1.1 | Deliveries/s | 55,125 | 55,941 | 56,039 | 55,471 |
| WS MQTT 3.1.1 | Broker CPU seconds | 4.24 | 4.13 | 4.34 | 4.38 |
| TCP 64 KiB | Deliveries/s | 7,083 | 7,044 | 7,012 | 7,045 |
| TCP 64 KiB | Broker CPU seconds | 0.41 | 0.40 | 0.39 | 0.41 |

Complete experimental matrices are available for
[EPYC 7763](../../docs/benchmarks/mqtt-hosted-pr128-1660422d-epyc7763.json) and
[EPYC 9V45](../../docs/benchmarks/mqtt-hosted-pr128-1660422d-epyc9v45.json).


The direct-body decoder candidate reduces large-payload copying. These local Apple M3 Ultra
medians use five interleaved repetitions with the same client and native library.
The [raw comparison](../../docs/benchmarks/mqtt-direct-body-local-comparison.json)
contains 6,300,000 exact deliveries. Hosted CPU-class acceptance is pending; small WS changes are inconclusive.

| Workload | Deliveries/run | Delivered/s before → candidate | Broker CPU seconds before → candidate | Sampled RSS MiB before → candidate |
| --- | ---: | ---: | ---: | ---: |
| TCP 64 KiB | 20,000 | 9,538 → 10,133 | 1.13 → 1.03 | 75.3 → 78.5 |
| WS MQTT 5 | 200,000 | 104,466 → 103,271 | 3.78 → 3.86 | 29.8 → 29.7 |
| WS MQTT 3.1.1 | 200,000 | 100,944 → 101,112 | 3.92 → 3.89 | 30.4 → 29.9 |


A separate [runtime sizing comparison](../../docs/benchmarks/mqtt-runtime-workers-local-comparison.json)
uses the same broker binary on this Mac. These local results cover 6,000,000 exact
deliveries. The Linux comparison below shows the candidate still needs more margin.

| Workload | Delivered/s automatic → one worker | Broker CPU seconds automatic → one worker | Sampled RSS MiB automatic → one worker |
| --- | ---: | ---: | ---: |
| WS MQTT 5 | 129,101 → 153,519 | 3.06 → 1.94 | 30.1 → 34.4 |
| WS MQTT 3.1.1 | 137,040 → 140,152 | 2.90 → 2.07 | 30.5 → 33.7 |

A [same-library Linux comparison](../../docs/benchmarks/mqtt-runtime-workers-linux-one.json)
on EPYC 7763 also improves WS throughput with one worker, but the first MQTT 5
leg remains below the 0.700× floor. All 16,200,000 deliveries are exact.
[Two workers](../../docs/benchmarks/mqtt-runtime-workers-linux-two.json) increased WS CPU on EPYC 9V45 and were rejected.

| Workload | Metric | Automatic 1 | One worker 1 | Automatic 2 | One worker 2 |
| --- | --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | Rate × | 0.648 | 0.691 | 0.647 | 0.713 |
| WS MQTT 5 | Broker CPU seconds | 9.29 | 8.90 | 9.23 | 8.52 |
| WS MQTT 5 | Peak RSS MiB | 22.5 | 21.9 | 22.7 | 22.0 |
| WS MQTT 3.1.1 | Rate × | 0.652 | 0.736 | 0.640 | 0.746 |
| WS MQTT 3.1.1 | Broker CPU seconds | 9.19 | 8.45 | 9.24 | 8.45 |
| WS MQTT 3.1.1 | Peak RSS MiB | 22.6 | 21.8 | 22.7 | 22.0 |
| TCP 64 KiB | Rate × | 0.925 | 0.890 | 0.899 | 0.889 |
| TCP 64 KiB | Broker CPU seconds | 0.66 | 0.61 | 0.66 | 0.62 |
| TCP 64 KiB | Peak RSS MiB | 60.1 | 59.6 | 60.6 | 61.3 |

The [exact-topic shortcut comparison](../../docs/benchmarks/mqtt-exact-topic-local-comparison.json)
uses frozen before/after brokers, one client and one native library on Apple M3 Ultra.
All 6,300,000 deliveries are exact. The changes are small and mixed, so the shortcut is reverted.

| Workload | Delivered/s before → shortcut | Broker CPU seconds before → shortcut | Sampled RSS MiB before → shortcut |
| --- | ---: | ---: | ---: |
| TCP 64 KiB | 10,345 → 10,399 | 1.13 → 1.14 | 89.6 → 79.0 |
| WS MQTT 5 | 105,617 → 103,392 | 3.67 → 3.80 | 30.7 → 29.8 |
| WS MQTT 3.1.1 | 101,571 → 101,284 | 3.93 → 3.92 | 30.4 → 30.0 |

The [MQTT reactor candidate](../../docs/benchmarks/mqtt-reactor-local-comparison.json)
uses identical frozen broker/client binaries on Apple M3 Ultra, changing only
the native library. All 6,300,000 MQTT deliveries are exact. The separate serial
WAMP guard completes 144 workloads. Hosted acceptance is pending.

| Workload | Deliveries/run | Delivered/s before → reactor | Broker CPU seconds before → reactor | Sampled RSS MiB before → reactor |
| --- | ---: | ---: | ---: | ---: |
| TCP 64 KiB | 20,000 | 10,451 → 10,536 | 0.95 → 0.83 | 80.8 → 78.3 |
| WS MQTT 5 | 200,000 | 101,315 → 106,810 | 3.85 → 2.62 | 30.3 → 29.8 |
| WS MQTT 3.1.1 | 200,000 | 102,330 → 107,774 | 3.81 → 2.61 | 30.3 → 29.7 |

A [repeated EPYC 7763 comparison](../../docs/benchmarks/mqtt-reactor-epyc7763-comparison.json)
passes all 12 profile legs with 16,200,000 exact deliveries. Default MQTT I/O
uses its own worker; the explicit one-worker option shares the primary pool.
The throughput floors remain 0.700× for WS and 0.750× for TCP, with a 4.000× large-payload CPU cap.

| Workload | Metric | New default 1 | Shared worker 1 | New default 2 | Shared worker 2 |
| --- | --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | Rate × | 0.731 | 0.717 | 0.766 | 0.703 |
| WS MQTT 5 | Broker CPU C/M × | 2.291 | 2.317 | 2.204 | 2.354 |
| WS MQTT 5 | Peak RSS MiB | 21.9 | 21.9 | 22.0 | 21.9 |
| WS MQTT 3.1.1 | Rate × | 0.766 | 0.782 | 0.745 | 0.751 |
| WS MQTT 3.1.1 | Broker CPU C/M × | 2.213 | 2.175 | 2.257 | 2.237 |
| WS MQTT 3.1.1 | Peak RSS MiB | 22.1 | 21.8 | 21.9 | 21.8 |
| TCP 64 KiB | Rate × | 0.911 | 0.882 | 0.911 | 0.909 |
| TCP 64 KiB | Broker CPU C/M × | 2.773 | 3.211 | 2.696 | 2.810 |
| TCP 64 KiB | Peak RSS MiB | 57.3 | 57.6 | 59.3 | 61.0 |

A [reader-readiness trial](../../docs/benchmarks/mqtt-readiness-local-rejected.json) was reverted: MQTT 5 slowed in both runs and the MQTT 3.1.1 gain did not repeat. These local comparisons use the same broker/client binaries and change only the native library.

| Workload | Run | Delivered/s before → trial | Broker CPU seconds before → trial | Sampled RSS MiB before → trial |
| --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | 1 | 154,754 → 146,351 | 1.93 → 2.00 | 35.3 → 35.7 |
| WS MQTT 3.1.1 | 1 | 149,809 → 157,162 | 1.96 → 1.89 | 35.2 → 35.5 |
| WS MQTT 5 | 2 | 158,968 → 151,792 | 1.87 → 1.95 | 35.9 → 35.5 |
| WS MQTT 3.1.1 | 2 | 158,204 → 150,265 | 1.89 → 1.96 | 36.5 → 35.2 |

A [boundary-only variant](../../docs/benchmarks/mqtt-readiness-boundary-local-comparison.json) also has mixed local results; Linux evaluation is pending. It is not an accepted improvement.

| Workload | Run | Delivered/s before → trial | Broker CPU seconds before → trial | Sampled RSS MiB before → trial |
| --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | 1 | 150,307 → 158,009 | 1.96 → 1.89 | 36.1 → 35.5 |
| WS MQTT 3.1.1 | 1 | 152,612 → 156,711 | 1.94 → 1.90 | 35.8 → 35.8 |
| WS MQTT 5 | 2 | 158,246 → 153,157 | 1.88 → 1.93 | 35.8 → 35.7 |
| WS MQTT 3.1.1 | 2 | 162,653 → 157,854 | 1.84 → 1.87 | 36.6 → 36.2 |

## WAMP throughput

Each cell shows **sustained / full-lifecycle throughput** in Gbit/s; higher is better.
The values are medians of three matched local runs on an Apple M3 Ultra.
FlatBuffers means a FlatBuffers WAMP envelope with CBOR application fragments.
The [file measurements](../../docs/benchmarks/wamp-flatbuffers-file-segments-2026-10-20/README.md)
and [other WAMP measurements](../../docs/benchmarks/wamp-four-serializer-2026-10-20/README.md)
include the raw results and run settings.

### 64 MiB file transfer

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) | FlatBuffers (Gbit/s) |
| --- | ---: | ---: | ---: | ---: |
| Native RawSocket | 9.662 / 9.246 | 14.974 / 13.990 | 15.656 / 13.990 | 22.378 / 18.674 |
| Dart RawSocket, buffered | 5.067 / 4.550 | 9.771 / 7.983 | 10.783 / 8.730 | 1.038 / 1.013 |
| Native RawSocket TLS | 6.315 / 6.114 | 11.657 / 10.943 | 11.378 / 10.724 | 11.669 / 10.915 |
| Native WebSocket | 9.319 / 8.865 | 15.665 / 14.222 | 13.456 / 12.540 | 22.156 / 19.523 |
| Dart WebSocket, buffered | 2.273 / 2.158 | 8.925 / 7.431 | 8.881 / 7.405 | 1.004 / 0.980 |
| Native WebSocket TLS | 6.041 / 5.832 | 11.323 / 10.605 | 8.355 / 7.983 | 11.269 / 10.514 |
| Native RawSocket + E2EE | 8.329 / 7.998 | 20.739 / 18.838 | 20.780 / 18.838 | 20.888 / 18.838 |
| Native RawSocket TLS + E2EE | 6.824 / 6.597 | 11.873 / 11.214 | 11.534 / 10.887 | 11.641 / 10.929 |
| Native WebSocket + E2EE | 8.180 / 7.802 | 19.767 / 17.638 | 14.884 / 13.635 | 19.182 / 17.214 |
| Native WebSocket TLS + E2EE | 6.612 / 6.354 | 10.673 / 10.012 | 9.158 / 8.633 | 10.562 / 9.873 |

Files use 4 MiB chunks. Native FlatBuffers file rows use file-backed
segments; Dart buffered rows use the Dart file path.
The [hosted Linux FlatBuffers file table](../../docs/benchmarks/wamp-flatbuffers-hosted-linux-1c53c153-2026-10-20/README.md)
shows the eight native paths and the GitHub Actions gate result.

### Large RPC frames

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) | FlatBuffers (Gbit/s) |
| --- | ---: | ---: | ---: | ---: |
| Native RawSocket | 12.967 / 4.822 | 18.830 / 6.204 | 17.977 / 4.581 | 7.148 / 3.303 |
| Native WebSocket | 7.599 / 6.537 | 10.901 / 9.061 | 7.166 / 6.032 | 5.452 / 4.777 |
| Native RawSocket TLS | 9.453 / 4.212 | 11.678 / 5.142 | 10.946 / 3.971 | 6.075 / 3.064 |
| Native WebSocket TLS | 6.145 / 5.409 | 8.617 / 7.392 | 5.544 / 4.831 | 4.854 / 4.312 |
| Dart RawSocket | 2.475 / 1.863 | 18.835 / 6.243 | 16.972 / 4.623 | 4.550 / 2.640 |
| Dart WebSocket | 2.601 / 2.467 | 8.725 / 7.457 | 8.326 / 6.883 | 3.701 / 3.393 |
| Dart RawSocket TLS reference[^dart-tls] | 0.785 / 0.711 | 1.073 / 0.958 | 1.064 / 0.912 | 0.914 / 0.798 |
| Dart WebSocket TLS reference[^dart-tls] | 0.800 / 0.786 | 0.995 / 0.977 | 0.996 / 0.971 | 0.885 / 0.865 |

RawSocket frames are 60 MiB; WebSocket frames are 8 MiB.

### WebSocket fragmentation and Pub/Sub

| Transport and workload | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) | FlatBuffers (Gbit/s) |
| --- | ---: | ---: | ---: | ---: |
| WebSocket RPC, contiguous | 18.303 / 14.175 | 26.062 / 18.513 | 12.534 / 10.058 | 11.149 / 8.967 |
| WebSocket RPC, 4 KiB fragments | 8.537 / 7.562 | 9.429 / 8.340 | 8.369 / 7.317 | 9.363 / 7.983 |
| WebSocket Pub/Sub, contiguous | 7.374 / 6.498 | 12.342 / 10.035 | 4.651 / 4.190 | 8.165 / 6.785 |
| WebSocket Pub/Sub, 4 KiB fragments | 6.408 / 5.666 | 7.281 / 6.430 | 4.709 / 4.269 | 6.911 / 5.990 |
| WebSocket TLS RPC, contiguous | 10.302 / 8.819 | 12.377 / 10.476 | 8.583 / 7.418 | 11.086 / 9.177 |
| WebSocket TLS RPC, 4 KiB fragments | 8.860 / 7.725 | 9.388 / 8.244 | 7.980 / 6.950 | 9.621 / 8.134 |
| WebSocket TLS Pub/Sub, contiguous | 4.250 / 3.905 | 5.197 / 4.674 | 2.945 / 2.727 | 4.526 / 4.083 |
| WebSocket TLS Pub/Sub, 4 KiB fragments | 4.147 / 3.804 | 5.096 / 4.658 | 3.149 / 2.914 | 5.313 / 4.735 |

Fragmented rows use 4 MiB payloads split into 4 KiB frames with four messages
in flight. These local results are diagnostic; the [WAMP benchmark contract](../../docs/wamp_profile_benchmarks.md) identifies release gates.

[^dart-tls]: Dart TLS rows are reference measurements; native TLS is the production secure path.

## Run and reproduce

The package exposes the benchmark service:

```bash
dart run connectanum_bench:bench_router_service
```

The [native orchestrator](https://github.com/konsultaner/connectanum-dart/tree/master/native/bench)
and its scenarios run complete WAMP campaigns. The
[MQTT gate script](../../tool/run_mqtt_benchmark_gate.py) and
[CI workflow](../../.github/workflows/dart.yml) show the MQTT run setup. For
typed payload setup and test coverage, see the
[FlatBuffers acceptance contract](../../docs/flatbuffers_performance_acceptance.md).
