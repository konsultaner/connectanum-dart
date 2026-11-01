# connectanum_bench

Connectanum benchmark results for MQTT publish/subscribe and WAMP transports.
The package runs the WAMP and HTTP workloads; the MQTT runner lives under
`packages/connectanum_router/benchmark/`.
Full raw results and checksums are in the [benchmark archive](../../docs/benchmarks/README.md#archive);
the tables below are checked against compact offline regression fixtures.

## MQTT publish and subscribe

This table shows all QoS 0 profiles from the [GitHub Actions run of candidate `b1c611ba`](https://github.com/konsultaner/connectanum-dart/actions/runs/40964731528/job/123766445118)
on Ubuntu 24.04 and AMD EPYC 7763, compared with Mosquitto 2.0.18.
C / M means Connectanum / Mosquitto. Higher delivery rate is better; lower
latency and broker CPU ratios are better. Peak RSS is Connectanum broker memory.
Workload counts are publications per run; fan-out rates count deliveries to all
subscribers. WS means WebSocket and WSS means secure WebSocket. Smoke rows
check delivery only. All 20 profiles pass in this run. Matched comparisons and earlier misses remain below.

| Broker | MQTT / link | Workload | Delivered/s C / M | Rate × | p95 / p99 C/M × | Broker CPU C/M × | Peak RSS | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Dart | 5 / TCP | 128 B, 2k, single smoke | 66,107 / 78,110 | 0.846 | 1.217 / 1.237 | 1.500 | 10.5 MiB | Delivery pass |
| Dart | 5 / TCP | 128 B, 200k, single | 73,695 / 86,418 | 0.853 | 1.702 / 1.771 | 1.409 | 11.2 MiB | Pass |
| Dart | 3.1.1 / TCP | 128 B, 200k, single | 74,133 / 87,578 | 0.846 | 1.734 / 1.753 | 1.429 | 11.0 MiB | Pass |
| Dart | 5 / TCP | 128 B, 200k, batch 512 | 487,892 / 82,527 | 5.912 | 0.200 / 0.172 | 0.088 | 17.1 MiB | Pass |
| Dart | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 691,393 / 96,278 | 7.181 | 0.097 / 0.102 | 0.071 | 10.6 MiB | Pass |
| Native | 5 / TCP | 128 B, 2k, single smoke | 68,875 / 77,595 | 0.888 | 1.230 / 1.241 | 1.667 | 21.1 MiB | Delivery pass |
| Native | 5 / TCP | 128 B, 200k, single | 90,830 / 86,258 | 1.053 | 1.137 / 1.161 | 1.549 | 21.9 MiB | Pass |
| Native | 3.1.1 / TCP | 128 B, 200k, single | 84,296 / 85,991 | 0.980 | 1.181 / 1.068 | 1.661 | 21.7 MiB | Pass |
| Native | 5 / TCP | 1 KiB, 100k, single | 67,990 / 8,536 | 7.965 | 0.091 / 0.105 | 1.426 | 28.9 MiB | Pass |
| Native | 5 / TCP | 64 KiB, 5k, single | 5,122 / 5,664 | 0.904 | 1.166 / 1.064 | 2.952 | 62.1 MiB | Pass |
| Native | 5 / TCP | 128 B, 200k, batch 512 | 465,543 / 84,685 | 5.497 | 0.200 / 0.196 | 0.115 | 27.6 MiB | Pass |
| Native | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 657,622 / 111,148 | 5.917 | 0.123 / 0.115 | 0.106 | 21.3 MiB | Pass |
| Native | 5 / TLS | 128 B, 200k, single | 171,039 / 21,660 | 7.896 | 0.115 / 0.062 | 0.686 | 23.7 MiB | Pass |
| Native | 3.1.1 / TLS | 128 B, 200k, single | 172,933 / 21,486 | 8.049 | 0.113 / 0.062 | 0.693 | 23.6 MiB | Pass |
| Native | 5 / WS | 128 B, 200k, single | 36,730 / 49,419 | 0.743 | 1.598 / 1.634 | 2.209 | 22.0 MiB | Pass |
| Native | 3.1.1 / WS | 128 B, 200k, single | 37,096 / 49,272 | 0.753 | 1.581 / 1.610 | 2.173 | 22.0 MiB | Pass |
| Native | 5 / WSS | 128 B, 2k, single smoke | 68,507 / 18,442 | 3.715 | 0.260 / 0.286 | 0.500 | 23.2 MiB | Delivery pass |
| Native | 5 / WSS | 128 B, 200k, batch 64 | 98,767 / 20,034 | 4.930 | 0.223 / 0.222 | 0.262 | 23.5 MiB | Pass |
| Native | 3.1.1 / WSS | 128 B, 2k, single smoke | 52,786 / 16,623 | 3.176 | 0.353 / 0.414 | 0.500 | 23.0 MiB | Delivery pass |
| Native | 3.1.1 / WSS | 128 B, 200k, single | 110,446 / 20,553 | 5.374 | 0.171 / 0.167 | 0.389 | 23.7 MiB | Pass |

| Check | Result |
| --- | --- |
| Direct MQTT delivery | 29,114,000 expected and received across 192 benchmark samples; zero duplicates |
| Profile results | 20 of 20 passed: 16 performance profiles and 4 delivery-only smoke profiles |
| WebSocket throughput budget | MQTT 5 / 3.1.1 rate ratios 0.743× / 0.753× against a 0.700× floor |
| 64 KiB CPU budget | 2.952× broker CPU ratio against a 4.000× cap on this AMD runner |
| MQTT ↔ WAMP translation | Both directions measured; [throughput, latency, CPU and per-process memory](#mqtt-and-wamp-gateway) |
| Typed FlatBuffers PPT parity | No accepted performance result yet; outer-envelope measurements appear below |

| Hosted run and CPU | WS 5 rate × | WS 3.1.1 rate × | TCP 3.1.1 rate × | 64 KiB CPU × | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Required limit | ≥0.700 | ≥0.700 | ≥0.750 | ≤4.000 | — |
| [Latest `b1c611ba`](https://github.com/konsultaner/connectanum-dart/actions/runs/40964731528/job/123766445118), EPYC 7763 | 0.743 | 0.753 | 0.980 | 2.952 | Pass |
| [Previous `e35635de`](https://github.com/konsultaner/connectanum-dart/actions/runs/40951944369/job/123722435370), EPYC 7763 | 0.711 | 0.776 | 1.099 | 2.762 | Pass |
| [Previous `160fc2c2`](https://github.com/konsultaner/connectanum-dart/actions/runs/40940745734/job/123684752425), EPYC 7763 | 0.744 | 0.678 | 1.012 | 2.652 | **Fail (WS rate)** |
| [Previous `6790909b`](https://github.com/konsultaner/connectanum-dart/actions/runs/40929728718/job/123644737494), EPYC 9V74 | 0.757 | 0.694 | 1.122 | 3.000 | **Fail (WS rate)** |
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

The [latest results](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-b1c611ba.json),
[previous production results](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-e35635de.json),
[previous 7763 miss](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-160fc2c2.json),
[previous 9V74 miss](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-6790909b.json),
[passing EPYC 7763 results](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-ffc417a9.json),
[baseline results](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-9aa6b17d.json),
[Intel results](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-2dea8b8e.json)
and [passing AMD repeat](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-84b22de8.json)
include every sample, workload setting, limit, and runner detail. The
[earlier passing AMD run](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-055e5739.json),
[WSS latency regression](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-780145ec.json)
and an [earlier passing AMD snapshot](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-amd-fccc7566.json)
are available for comparison. These results describe this measured run; QoS 0
does not guarantee delivery in every deployment.

The [earlier Intel Xeon 8370C production-baseline run](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-intel8370c-production-40960196402.json)
uses `e35635de` production code, before the readiness-yield change. Both 64 KiB
CPU checks pass the unchanged 4.000× cap. One WebSocket 3.1.1 pass misses the
0.700× throughput floor, so overall performance acceptance remains open.
All 8,100,000 deliveries across 60 samples are exact.

| Intel pass | Workload | Rate × | p95 / p99 × | Broker CPU × | Peak RSS | Result |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | WS MQTT 5 | 0.761 | 1.477 / 1.642 | 2.270 | 21.9 MiB | Pass |
| 1 | WS MQTT 3.1.1 | 0.744 | 1.498 / 1.545 | 2.286 | 21.9 MiB | Pass |
| 1 | TCP 64 KiB | 0.887 | 1.207 / 1.152 | 3.333 | 54.1 MiB | Pass |
| 2 | WS MQTT 5 | 0.759 | 1.452 / 1.583 | 2.275 | 22.0 MiB | Pass |
| 2 | WS MQTT 3.1.1 | 0.695 | 1.603 / 1.713 | 2.444 | 21.9 MiB | **Fail (WS rate)** |
| 2 | TCP 64 KiB | 0.858 | 1.255 / 1.246 | 3.647 | 57.0 MiB | Pass |

The buffered-frame experiment was reverted because the EPYC 7763 gate remained
red. Its [same-runner comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-native-comparison-1660422d.json)
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
[EPYC 7763](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-1660422d-epyc7763.json) and
[EPYC 9V45](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-hosted-pr128-1660422d-epyc9v45.json).


The direct-body decoder candidate reduces large-payload copying. These local Apple M3 Ultra
medians use five interleaved repetitions with the same client and native library.
The [raw comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-direct-body-local-comparison.json)
contains 6,300,000 exact deliveries. Current affected-CPU results appear above; small local WS changes are inconclusive.

| Workload | Deliveries/run | Delivered/s before → candidate | Broker CPU seconds before → candidate | Sampled RSS MiB before → candidate |
| --- | ---: | ---: | ---: | ---: |
| TCP 64 KiB | 20,000 | 9,538 → 10,133 | 1.13 → 1.03 | 75.3 → 78.5 |
| WS MQTT 5 | 200,000 | 104,466 → 103,271 | 3.78 → 3.86 | 29.8 → 29.7 |
| WS MQTT 3.1.1 | 200,000 | 100,944 → 101,112 | 3.92 → 3.89 | 30.4 → 29.9 |


A separate [runtime sizing comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-runtime-workers-local-comparison.json)
uses the same broker binary on this Mac. These local results cover 6,000,000 exact
deliveries. The Linux comparison below motivated isolating MQTT on its own runtime.

| Workload | Delivered/s automatic → one worker | Broker CPU seconds automatic → one worker | Sampled RSS MiB automatic → one worker |
| --- | ---: | ---: | ---: |
| WS MQTT 5 | 129,101 → 153,519 | 3.06 → 1.94 | 30.1 → 34.4 |
| WS MQTT 3.1.1 | 137,040 → 140,152 | 2.90 → 2.07 | 30.5 → 33.7 |

A [same-library Linux comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-runtime-workers-linux-one.json)
on EPYC 7763 also improves WS throughput with one worker, but the first MQTT 5
leg remains below the 0.700× floor. All 16,200,000 deliveries are exact.
[Two workers](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-runtime-workers-linux-two.json) increased WS CPU on EPYC 9V45 and were rejected.

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

The [exact-topic shortcut comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-exact-topic-local-comparison.json)
uses frozen before/after brokers, one client and one native library on Apple M3 Ultra.
All 6,300,000 deliveries are exact. The changes are small and mixed, so the shortcut is reverted.

| Workload | Delivered/s before → shortcut | Broker CPU seconds before → shortcut | Sampled RSS MiB before → shortcut |
| --- | ---: | ---: | ---: |
| TCP 64 KiB | 10,345 → 10,399 | 1.13 → 1.14 | 89.6 → 79.0 |
| WS MQTT 5 | 105,617 → 103,392 | 3.67 → 3.80 | 30.7 → 29.8 |
| WS MQTT 3.1.1 | 101,571 → 101,284 | 3.93 → 3.92 | 30.4 → 30.0 |

The [MQTT reactor candidate](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-reactor-local-comparison.json)
uses identical frozen broker/client binaries on Apple M3 Ultra, changing only
the native library. All 6,300,000 MQTT deliveries are exact. The separate serial
WAMP guard completes 144 workloads. Current hosted results appear above.

| Workload | Deliveries/run | Delivered/s before → reactor | Broker CPU seconds before → reactor | Sampled RSS MiB before → reactor |
| --- | ---: | ---: | ---: | ---: |
| TCP 64 KiB | 20,000 | 10,451 → 10,536 | 0.95 → 0.83 | 80.8 → 78.3 |
| WS MQTT 5 | 200,000 | 101,315 → 106,810 | 3.85 → 2.62 | 30.3 → 29.8 |
| WS MQTT 3.1.1 | 200,000 | 102,330 → 107,774 | 3.81 → 2.61 | 30.3 → 29.7 |

A [repeated EPYC 7763 comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-reactor-epyc7763-comparison.json)
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

A [reader-readiness trial](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-readiness-local-rejected.json) was reverted: MQTT 5 slowed in both runs and the MQTT 3.1.1 gain did not repeat. These local comparisons use the same broker/client binaries and change only the native library.

| Workload | Run | Delivered/s before → trial | Broker CPU seconds before → trial | Sampled RSS MiB before → trial |
| --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | 1 | 154,754 → 146,351 | 1.93 → 2.00 | 35.3 → 35.7 |
| WS MQTT 3.1.1 | 1 | 149,809 → 157,162 | 1.96 → 1.89 | 35.2 → 35.5 |
| WS MQTT 5 | 2 | 158,968 → 151,792 | 1.87 → 1.95 | 35.9 → 35.5 |
| WS MQTT 3.1.1 | 2 | 158,204 → 150,265 | 1.89 → 1.96 | 36.5 → 35.2 |

A [boundary-only variant](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-readiness-boundary-local-comparison.json) also has mixed local results. Linux results follow; affected-CPU acceptance is still open.

| Workload | Run | Delivered/s before → trial | Broker CPU seconds before → trial | Sampled RSS MiB before → trial |
| --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | 1 | 150,307 → 158,009 | 1.96 → 1.89 | 36.1 → 35.5 |
| WS MQTT 3.1.1 | 1 | 152,612 → 156,711 | 1.94 → 1.90 | 35.8 → 35.8 |
| WS MQTT 5 | 2 | 158,246 → 153,157 | 1.88 → 1.93 | 35.8 → 35.7 |
| WS MQTT 3.1.1 | 2 | 162,653 → 157,854 | 1.84 → 1.87 | 36.6 → 36.2 |

The [Linux comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-readiness-boundary-linux-40936331023.json) passes all 12 profile checks on EPYC 9V45. MQTT 5 improves slightly in both pairs; MQTT 3.1.1 is mixed. Tests on the affected CPUs remain pending.

| Workload | Metric | Reactor 1 | Trial 1 | Reactor 2 | Trial 2 |
| --- | --- | ---: | ---: | ---: | ---: |
| WS MQTT 5 | Deliveries/s | 55,814 | 57,298 | 54,049 | 55,261 |
| WS MQTT 5 | Broker CPU seconds | 5.20 | 5.23 | 5.32 | 5.21 |
| WS MQTT 5 | Peak RSS MiB | 22.2 | 22.2 | 22.0 | 22.2 |
| WS MQTT 3.1.1 | Deliveries/s | 55,281 | 53,692 | 52,342 | 57,536 |
| WS MQTT 3.1.1 | Broker CPU seconds | 5.25 | 5.36 | 5.47 | 5.11 |
| WS MQTT 3.1.1 | Peak RSS MiB | 22.1 | 22.2 | 22.2 | 22.2 |
| TCP 64 KiB | Deliveries/s | 8,074 | 7,956 | 8,399 | 8,369 |
| TCP 64 KiB | Broker CPU seconds | 0.35 | 0.36 | 0.34 | 0.35 |
| TCP 64 KiB | Peak RSS MiB | 63.0 | 66.4 | 66.0 | 65.8 |

The [three-host 9V74 comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-reactor-matched-40942027350.json) passes all 18 production-baseline checks. The reader trial is rejected: its changes are mixed and one MQTT 3.1.1 ratio is 0.693, below 0.700. The latest full 7763 gate above passes; earlier production-baseline misses remain in the history table.

| 9V74 host | Production WS 5 rate ×, runs 1 / 2 | Production WS 3.1.1 rate ×, runs 1 / 2 | Production 64 KiB CPU ×, runs 1 / 2 |
| --- | ---: | ---: | ---: |
| Probe 1 | 0.701 / 0.716 | 0.728 / 0.743 | 2.867 / 3.000 |
| Probe 2 | 0.766 / 0.733 | 0.733 / 0.755 | 2.800 / 3.071 |
| Probe 4 | 0.750 / 0.741 | 0.720 / 0.725 | 2.688 / 2.933 |

The [same-binary tracing comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-tracing-epyc7763-40948629881.json)
on EPYC 7763 passes all 12 gates. These small, mixed differences do not establish
coverage tracing as the cause of the full-run failure above. Coverage stays enabled.

| Harness run | WS 5 rate × | WS 3.1.1 rate × | 64 KiB CPU × | Gate |
| --- | ---: | ---: | ---: | --- |
| bare-1 | 0.748 | 0.791 | 2.857 | Pass |
| traced-1 | 0.733 | 0.767 | 2.773 | Pass |
| bare-2 | 0.766 | 0.737 | 2.810 | Pass |
| traced-2 | 0.747 | 0.739 | 2.773 | Pass |

The [owned-wire forwarding trial](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-wire-view-local-rejected.json)
is rejected: it does not improve WebSocket throughput. These local Apple M3 Ultra
results use identical client/native binaries; the 64 KiB workload has 20k publications.
All 6,300,000 deliveries are exact. Before / trial values are medians, except peak RSS.

| Workload | Delivered/s before / trial | Broker CPU seconds before / trial | Peak RSS MiB before / trial |
| --- | ---: | ---: | ---: |
| WS MQTT 5 | 125,337 / 126,221 | 2.27 / 2.26 | 31.4 / 30.7 |
| WS MQTT 3.1.1 | 127,036 / 126,471 | 2.24 / 2.26 | 31.3 / 31.7 |
| TCP 64 KiB | 11,285 / 11,267 | 0.84 / 0.80 | 87.2 / 80.7 |

The [burst-timer trial](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-burst-macos-rejected.json) reduces
CPU use but slows macOS WebSocket delivery, so it is rejected for macOS. These
local results retain all 6,000,000 exact deliveries; the Linux comparison follows.

| Workload | Delivered/s before / trial | Broker CPU seconds before / trial | Peak RSS MiB before / trial |
| --- | ---: | ---: | ---: |
| WS MQTT 5 | 149,975 / 114,439 | 1.95 / 1.04 | 34.8 / 30.0 |
| WS MQTT 3.1.1 | 154,005 / 113,766 | 1.92 / 1.04 | 35.3 / 30.5 |

The [two-host Linux timer comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-burst-linux-40951811976.json)
passes all 24 numeric checks on EPYC 9V74 and delivers 32,400,000 messages exactly.
Throughput changes are mixed despite lower CPU, so the timer is rejected as the
throughput fix. These are separate paired runs; they do not clear the affected
7763/8370C acceptance requirements.

| Host / workload | Rate × baseline / trial, pair 1 | Rate × baseline / trial, pair 2 | Broker CPU seconds baseline / trial, pair 1 | Broker CPU seconds baseline / trial, pair 2 |
| --- | ---: | ---: | ---: | ---: |
| Ubuntu 24 / WS 5 | 0.729 / 0.719 | 0.794 / 0.738 | 6.80 / 5.54 | 6.41 / 5.37 |
| Ubuntu 24 / WS 3.1.1 | 0.741 / 0.723 | 0.767 / 0.753 | 6.75 / 5.64 | 6.69 / 5.08 |
| Ubuntu 24 / TCP 64 KiB | 0.900 / 0.911 | 0.940 / 0.904 | 0.42 / 0.43 | 0.42 / 0.43 |
| Ubuntu 22 / pinned 24 / WS 5 | 0.774 / 0.741 | 0.731 / 0.770 | 9.66 / 9.24 | 9.92 / 8.66 |
| Ubuntu 22 / pinned 24 / WS 3.1.1 | 0.746 / 0.761 | 0.749 / 0.769 | 9.77 / 8.87 | 9.84 / 8.71 |
| Ubuntu 22 / pinned 24 / TCP 64 KiB | 0.926 / 0.917 | 0.920 / 0.913 | 0.60 / 0.59 | 0.62 / 0.60 |

The [no-timer ready-yield comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-yield-linux-40956744846.json)
passes all 36 checks on three actual EPYC 7763 hosts with 48,600,000 exact deliveries.
Changes are small and mixed across these AMD hosts. The production baseline
passes all 18 checks as well. The Intel comparison below establishes the benefit
on the affected Intel model.

| 7763 host / workload | Rate × baseline / trial, pair 1 | Rate × baseline / trial, pair 2 | Broker CPU seconds baseline / trial, pair 1 | Broker CPU seconds baseline / trial, pair 2 |
| --- | ---: | ---: | ---: | ---: |
| Ubuntu 24 A / WS 5 | 0.721 / 0.738 | 0.773 / 0.744 | 8.39 / 7.84 | 8.08 / 8.00 |
| Ubuntu 24 A / WS 3.1.1 | 0.735 / 0.747 | 0.726 / 0.759 | 8.23 / 8.03 | 8.28 / 7.87 |
| Ubuntu 24 A / TCP 64 KiB | 0.904 / 0.933 | 0.909 / 0.891 | 0.59 / 0.59 | 0.59 / 0.59 |
| Ubuntu 24 B / WS 5 | 0.722 / 0.744 | 0.741 / 0.723 | 8.36 / 8.02 | 8.24 / 8.08 |
| Ubuntu 24 B / WS 3.1.1 | 0.790 / 0.775 | 0.725 / 0.729 | 7.80 / 7.78 | 8.18 / 8.16 |
| Ubuntu 24 B / TCP 64 KiB | 0.921 / 0.889 | 0.929 / 0.919 | 0.57 / 0.60 | 0.56 / 0.56 |
| Ubuntu 22 / pinned 24 / WS 5 | 0.775 / 0.772 | 0.820 / 0.783 | 9.10 / 9.19 | 9.10 / 9.20 |
| Ubuntu 22 / pinned 24 / WS 3.1.1 | 0.753 / 0.767 | 0.829 / 0.777 | 9.52 / 9.29 | 8.91 / 9.15 |
| Ubuntu 22 / pinned 24 / TCP 64 KiB | 0.915 / 0.963 | 0.919 / 0.920 | 0.63 / 0.65 | 0.62 / 0.63 |

The [matched Intel Xeon 8370C comparison](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/mqtt-yield-intel8370c-40961646882.json)
changes only the native library, using the same readiness-yield library as
`b1c611ba`. This candidate improves
both WebSocket versions in both pairs, while reducing broker CPU. All six
candidate checks pass; the baseline fails all four WebSocket checks. The 64 KiB
checks pass for both libraries. All 16,200,000 deliveries are exact. The full hosted MQTT matrix
above also passes with this candidate on EPYC 7763.
Current scoped coverage is [882/882 native added lines](../../docs/benchmarks/README.md#coverage),
651/651 MQTT Dart lines and 268/268 benchmark-gate Python lines.

| 8370C workload | Rate × baseline / candidate, pair 1 | Rate × baseline / candidate, pair 2 | Broker CPU seconds baseline / candidate, pair 1 | Broker CPU seconds baseline / candidate, pair 2 | Peak RSS MiB baseline / candidate, maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| WS MQTT 5 | 0.648 / 0.763 | 0.658 / 0.772 | 6.04 / 5.18 | 6.04 / 5.05 | 22.0 / 22.4 |
| WS MQTT 3.1.1 | 0.654 / 0.753 | 0.659 / 0.817 | 6.01 / 5.21 | 5.98 / 4.91 | 22.0 / 22.2 |
| TCP 64 KiB | 0.902 / 0.890 | 0.876 / 0.878 | 0.61 / 0.56 | 0.60 / 0.60 | 57.0 / 59.7 |

## MQTT and WAMP gateway

Measured on GitHub Actions Ubuntu 24.04, Dart 3.13.1, Paho 2.1.0 and Mosquitto 2.0.18. [Measured source `63a897a5`](https://github.com/konsultaner/connectanum-dart/commit/63a897a5cd57405a029c38a5f35821d2d6a591cc) · [CI samples](https://github.com/konsultaner/connectanum-dart/actions/runs/41327609801) · [Raw archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-2026-11-01).
Each profile uses 5 runs of 5,000 publications and fresh clients per cycle. Warm-up sends at least 200 messages and lasts at least 1 second.
Profiles list link, MQTT version, WAMP codec, payload, subscribers/in-flight messages and MQTT client. SDK means Connectanum.
3,850,000 exact translation deliveries; 11,550,000 deliveries including controls; zero duplicates.

Throughput and latency use run medians; CPU uses total load CPU divided by message count.
Rate × compares against the slower matched direct MQTT and WAMP path. WAMP → MQTT uses acknowledged WAMP publications as its control.

Hosts: A: AMD EPYC 9V74 80-Core Processor; B: AMD EPYC 9V74 80-Core Processor; C: Intel(R) Xeon(R) 6973P-C; D: AMD EPYC 7763 64-Core Processor.

| Profile | Direction | Delivered/s | MiB/s | p50 / p95 / p99 (µs) | CPU s/M B / P / S | Rate × |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| TCP 5 · JSON · 128 B · 1/1 · SDK [A] | MQTT → WAMP | 2,500 | 0.31 | 295 / 366 / 439 | 268.0 / 64.0 / 140.4 | 5.000 |
| TCP 5 · JSON · 128 B · 1/1 · SDK [A] | WAMP → MQTT | 500 | 0.06 | 1,851 / 1,894 / 2,041 | 633.2 / 219.2 / 76.4 | 1.000 |
| TCP 5 · MessagePack · 1 KiB · 4/16 · SDK [B] | MQTT → WAMP | 17,399 | 16.99 | 2,005 / 3,414 / 3,806 | 82.1 / 18.4 / 95.6 | 0.880 |
| TCP 5 · MessagePack · 1 KiB · 4/16 · SDK [B] | WAMP → MQTT | 11,651 | 11.38 | 3,447 / 5,257 / 5,688 | 125.8 / 124.8 / 45.2 | 0.717 |
| TCP 5 · CBOR · 64 KiB · 1/1 · SDK [C] | MQTT → WAMP | 859 | 53.68 | 923 / 1,211 / 1,353 | 448.4 / 163.6 / 596.8 | 1.718 |
| TCP 5 · CBOR · 64 KiB · 1/1 · SDK [C] | WAMP → MQTT | 308 | 19.25 | 2,836 / 3,989 / 4,262 | 2924.8 / 673.2 / 189.2 | 0.616 |
| TCP 3.1.1 · MessagePack · 128 B · 4/1 · SDK [D] | MQTT → WAMP | 5,141 | 0.63 | 489 / 625 / 786 | 151.6 / 86.4 / 196.4 | 2.570 |
| TCP 3.1.1 · MessagePack · 128 B · 4/1 · SDK [D] | WAMP → MQTT | 1,999 | 0.24 | 1,712 / 1,866 / 1,965 | 238.4 / 315.6 / 101.2 | 1.000 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · SDK [A] | MQTT → WAMP | 7,290 | 7.12 | 1,234 / 1,927 / 2,085 | 221.6 / 18.0 / 130.4 | 1.367 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · SDK [A] | WAMP → MQTT | 3,184 | 3.11 | 3,138 / 4,611 / 4,915 | 473.2 / 150.8 / 45.6 | 0.708 |
| TCP 3.1.1 · FlatBuffers · 64 KiB · 4/1 · SDK [B] | MQTT → WAMP | 573 | 35.84 | 4,896 / 7,054 / 7,377 | 1701.0 / 189.2 / 879.6 | 0.476 |
| TCP 3.1.1 · FlatBuffers · 64 KiB · 4/1 · SDK [B] | WAMP → MQTT | 1,057 | 66.09 | 3,447 / 4,370 / 4,690 | 804.7 / 777.6 / 222.0 | 0.932 |
| TLS 5 · MessagePack · 128 B · 1/16 · SDK [C] | MQTT → WAMP | 8,193 | 1.00 | 1,104 / 1,801 / 2,004 | 171.2 / 13.6 / 88.0 | 1.529 |
| TLS 5 · MessagePack · 128 B · 1/16 · SDK [C] | WAMP → MQTT | 3,360 | 0.41 | 3,207 / 4,728 / 5,160 | 395.6 / 106.0 / 120.4 | 0.641 |
| TLS 5 · CBOR · 1 KiB · 4/1 · SDK [D] | MQTT → WAMP | 4,042 | 3.95 | 674 / 891 / 1,031 | 202.5 / 196.4 / 263.6 | 2.021 |
| TLS 5 · CBOR · 1 KiB · 4/1 · SDK [D] | WAMP → MQTT | 1,995 | 1.95 | 1,657 / 1,874 / 2,046 | 276.7 / 353.6 / 322.8 | 0.998 |
| TLS 5 · FlatBuffers · 64 KiB · 1/16 · SDK [A] | MQTT → WAMP | 565 | 35.34 | 16,677 / 26,658 / 28,791 | 2375.2 / 639.2 / 896.0 | 0.624 |
| TLS 5 · FlatBuffers · 64 KiB · 1/16 · SDK [A] | WAMP → MQTT | 390 | 24.35 | 21,872 / 32,484 / 34,463 | 3566.8 / 876.8 / 968.0 | 0.430 |
| TLS 3.1.1 · CBOR · 128 B · 4/16 · SDK [B] | MQTT → WAMP | 14,822 | 1.81 | 2,489 / 4,223 / 4,665 | 93.9 / 13.6 / 117.2 | 0.788 |
| TLS 3.1.1 · CBOR · 128 B · 4/16 · SDK [B] | WAMP → MQTT | 9,675 | 1.18 | 4,126 / 6,485 / 7,052 | 131.8 / 118.8 / 140.8 | 0.630 |
| TLS 3.1.1 · FlatBuffers · 1 KiB · 1/1 · SDK [C] | MQTT → WAMP | 1,491 | 1.46 | 507 / 697 / 821 | 357.2 / 140.8 / 204.0 | 2.982 |
| TLS 3.1.1 · FlatBuffers · 1 KiB · 1/1 · SDK [C] | WAMP → MQTT | 500 | 0.49 | 1,845 / 1,945 / 2,149 | 747.6 / 294.8 / 215.6 | 1.000 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · SDK [D] | MQTT → WAMP | 631 | 39.42 | 55,569 / 96,167 / 101,299 | 2505.2 / 1009.6 / 983.2 | 0.427 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · SDK [D] | WAMP → MQTT | 1,162 | 72.61 | 15,390 / 25,551 / 29,597 | 609.4 / 2668.8 / 1600.8 | 0.786 |
| WS 5 · CBOR · 128 B · 1/1 · SDK [A] | MQTT → WAMP | 2,296 | 0.28 | 324 / 447 / 517 | 283.6 / 77.6 / 154.0 | 4.591 |
| WS 5 · CBOR · 128 B · 1/1 · SDK [A] | WAMP → MQTT | 500 | 0.06 | 1,847 / 1,894 / 2,032 | 638.0 / 214.8 / 78.8 | 1.000 |
| WS 5 · FlatBuffers · 1 KiB · 4/16 · SDK [B] | MQTT → WAMP | 10,217 | 9.98 | 3,449 / 5,676 / 6,205 | 143.1 / 32.0 / 160.0 | 0.680 |
| WS 5 · FlatBuffers · 1 KiB · 4/16 · SDK [B] | WAMP → MQTT | 10,426 | 10.18 | 3,567 / 5,478 / 5,858 | 148.0 / 184.4 / 47.2 | 0.840 |
| WS 5 · JSON · 64 KiB · 1/1 · SDK [C] | MQTT → WAMP | 487 | 30.42 | 1,772 / 2,339 / 2,595 | 1751.6 / 201.2 / 562.0 | 0.973 |
| WS 5 · JSON · 64 KiB · 1/1 · SDK [C] | WAMP → MQTT | 300 | 18.77 | 3,670 / 3,974 / 4,313 | 1249.6 / 1601.6 / 192.8 | 0.601 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · SDK [D] | MQTT → WAMP | 3,748 | 0.46 | 753 / 990 / 1,132 | 247.3 / 106.4 / 288.4 | 1.874 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · SDK [D] | WAMP → MQTT | 1,997 | 0.24 | 1,691 / 1,870 / 2,003 | 264.9 / 377.6 / 111.2 | 0.998 |
| WS 3.1.1 · JSON · 1 KiB · 1/16 · SDK [A] | MQTT → WAMP | 7,254 | 7.08 | 1,109 / 1,756 / 1,906 | 235.2 / 30.8 / 109.6 | 1.358 |
| WS 3.1.1 · JSON · 1 KiB · 1/16 · SDK [A] | WAMP → MQTT | 3,211 | 3.14 | 3,143 / 4,453 / 4,727 | 442.4 / 156.8 / 46.4 | 0.657 |
| WS 3.1.1 · MessagePack · 64 KiB · 4/1 · SDK [B] | MQTT → WAMP | 4,215 | 263.44 | 582 / 870 / 1,043 | 195.4 / 188.0 / 256.0 | 2.108 |
| WS 3.1.1 · MessagePack · 64 KiB · 4/1 · SDK [B] | WAMP → MQTT | 1,987 | 124.16 | 1,662 / 1,982 / 2,258 | 220.3 / 329.6 / 210.4 | 0.994 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · SDK [C] | MQTT → WAMP | 7,147 | 0.87 | 1,345 / 2,084 / 2,286 | 196.4 / 14.8 / 121.6 | 1.357 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · SDK [C] | WAMP → MQTT | 3,206 | 0.39 | 3,244 / 4,723 / 5,113 | 428.0 / 143.6 / 117.6 | 0.779 |
| WSS 5 · JSON · 1 KiB · 4/1 · SDK [D] | MQTT → WAMP | 3,839 | 3.75 | 741 / 931 / 1,061 | 231.1 / 266.4 / 220.4 | 1.919 |
| WSS 5 · JSON · 1 KiB · 4/1 · SDK [D] | WAMP → MQTT | 1,996 | 1.95 | 1,659 / 1,869 / 2,029 | 268.6 / 332.4 / 326.0 | 0.998 |
| WSS 5 · MessagePack · 64 KiB · 1/16 · SDK [A] | MQTT → WAMP | 1,436 | 89.75 | 5,957 / 9,691 / 10,064 | 611.2 / 627.2 / 256.4 | 1.508 |
| WSS 5 · MessagePack · 64 KiB · 1/16 · SDK [A] | WAMP → MQTT | 1,044 | 65.24 | 9,185 / 13,390 / 14,284 | 603.2 / 284.4 / 828.4 | 1.097 |
| WSS 3.1.1 · JSON · 128 B · 4/16 · SDK [B] | MQTT → WAMP | 16,028 | 1.96 | 2,248 / 3,797 / 4,150 | 83.7 / 16.4 / 104.8 | 0.842 |
| WSS 3.1.1 · JSON · 128 B · 4/16 · SDK [B] | WAMP → MQTT | 9,947 | 1.21 | 4,057 / 6,333 / 6,899 | 125.1 / 104.0 / 136.8 | 0.632 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · SDK [C] | MQTT → WAMP | 1,661 | 1.62 | 453 / 577 / 683 | 302.4 / 177.6 / 132.8 | 3.322 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · SDK [C] | WAMP → MQTT | 500 | 0.49 | 1,845 / 1,953 / 2,119 | 667.6 / 232.8 / 215.2 | 1.000 |
| WSS 3.1.1 · CBOR · 64 KiB · 4/16 · SDK [D] | MQTT → WAMP | 1,813 | 113.29 | 20,336 / 33,313 / 36,704 | 339.5 / 922.4 / 1220.0 | 1.199 |
| WSS 3.1.1 · CBOR · 64 KiB · 4/16 · SDK [D] | WAMP → MQTT | 911 | 56.93 | 38,355 / 58,825 / 62,005 | 1348.1 / 1044.4 / 1708.4 | 0.602 |
| TCP 5 · JSON · 128 B · 1/1 · Paho [A] | MQTT → WAMP | 2,269 | 0.28 | 352 / 446 / 494 | 282.4 / 127.6 / 141.6 | 4.537 |
| TCP 5 · JSON · 128 B · 1/1 · Paho [A] | WAMP → MQTT | 500 | 0.06 | 1,875 / 1,923 / 2,041 | 610.4 / 223.6 / 134.0 | 1.001 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · Paho [B] | MQTT → WAMP | 5,737 | 5.60 | 684 / 1,129 / 1,329 | 251.6 / 114.4 / 132.8 | 1.075 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · Paho [B] | WAMP → MQTT | 3,166 | 3.09 | 3,128 / 4,643 / 4,964 | 476.0 / 150.8 / 66.0 | 0.703 |
| TLS 5 · CBOR · 1 KiB · 4/1 · Paho [C] | MQTT → WAMP | 4,934 | 4.82 | 565 / 730 / 861 | 139.4 / 182.0 / 186.0 | 2.467 |
| TLS 5 · CBOR · 1 KiB · 4/1 · Paho [C] | WAMP → MQTT | 1,999 | 1.95 | 1,725 / 1,897 / 2,032 | 199.8 / 278.0 / 147.2 | 1.000 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · Paho [D] | MQTT → WAMP | 670 | 41.87 | 47,079 / 85,023 / 90,339 | 2244.8 / 400.0 / 957.6 | 0.253 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · Paho [D] | WAMP → MQTT | 2,008 | 125.52 | 5,748 / 8,459 / 9,756 | 546.1 / 2335.6 / 250.0 | 0.773 |
| WS 5 · JSON · 64 KiB · 1/1 · Paho [A] | MQTT → WAMP | 151 | 9.43 | 6,378 / 6,849 / 7,734 | 1992.4 / 5086.4 / 615.2 | 0.763 |
| WS 5 · JSON · 64 KiB · 1/1 · Paho [A] | WAMP → MQTT | 382 | 23.86 | 1,899 / 3,904 / 4,098 | 1154.8 / 1567.6 / 212.4 | 1.931 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · Paho [B] | MQTT → WAMP | 4,841 | 0.59 | 609 / 803 / 898 | 163.9 / 164.0 / 221.6 | 2.420 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · Paho [B] | WAMP → MQTT | 1,999 | 0.24 | 1,772 / 1,901 / 2,010 | 180.1 / 270.8 / 122.4 | 1.000 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · Paho [C] | MQTT → WAMP | 5,430 | 0.66 | 637 / 1,054 / 1,307 | 242.0 / 117.6 / 134.4 | 1.020 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · Paho [C] | WAMP → MQTT | 3,227 | 0.39 | 3,148 / 4,642 / 5,019 | 420.0 / 142.0 / 102.8 | 0.787 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · Paho [D] | MQTT → WAMP | 1,390 | 1.36 | 596 / 735 / 820 | 414.4 / 309.6 / 186.4 | 2.781 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · Paho [D] | WAMP → MQTT | 500 | 0.49 | 1,824 / 1,918 / 2,051 | 892.0 / 286.0 / 189.2 | 1.000 |

CPU is seconds per million broker deliveries (B), publisher messages (P), and received messages for the highest individual subscriber (S).
Memory shows median warm / highest peak / highest drained RSS in MiB. Peaks use the OS process high-water mark; subscriber columns show the highest individual reading. All subscribers are checked by the gate.
Allocation counters are unavailable in these release runtimes.

| Profile | Direction | Broker MiB | Publisher MiB | Subscriber MiB | Broker growth MiB / MiB per cycle |
| --- | --- | ---: | ---: | ---: | ---: |
| TCP 5 · JSON · 128 B · 1/1 · SDK [A] | MQTT → WAMP | 22.8 / 34.3 / 22.8 | 15.9 / 34.3 / 16.5 | 21.7 / 34.3 / 23.7 | 0.3 / 0.1 |
| TCP 5 · JSON · 128 B · 1/1 · SDK [A] | WAMP → MQTT | 29.5 / 34.3 / 30.6 | 21.3 / 34.3 / 21.6 | 15.0 / 34.3 / 16.6 | 2.2 / 0.5 |
| TCP 5 · MessagePack · 1 KiB · 4/16 · SDK [B] | MQTT → WAMP | 31.8 / 34.3 / 32.3 | 15.8 / 34.3 / 15.9 | 22.0 / 34.3 / 22.4 | 1.3 / 0.3 |
| TCP 5 · MessagePack · 1 KiB · 4/16 · SDK [B] | WAMP → MQTT | 31.4 / 34.5 / 34.5 | 21.3 / 34.3 / 22.6 | 16.6 / 34.3 / 17.4 | 4.8 / 1.2 |
| TCP 5 · CBOR · 64 KiB · 1/1 · SDK [C] | MQTT → WAMP | 37.3 / 56.7 / 55.2 | 15.7 / 34.3 / 15.8 | 21.6 / 34.3 / 23.0 | 23.6 / 5.6 |
| TCP 5 · CBOR · 64 KiB · 1/1 · SDK [C] | WAMP → MQTT | 31.8 / 63.6 / 33.2 | 21.1 / 34.3 / 22.0 | 17.1 / 34.3 / 17.4 | 0.5 / 0.1 |
| TCP 3.1.1 · MessagePack · 128 B · 4/1 · SDK [D] | MQTT → WAMP | 28.9 / 34.4 / 29.2 | 15.8 / 34.4 / 16.5 | 21.6 / 34.4 / 22.6 | 0.7 / 0.2 |
| TCP 3.1.1 · MessagePack · 128 B · 4/1 · SDK [D] | WAMP → MQTT | 29.2 / 34.4 / 30.8 | 21.0 / 34.4 / 21.4 | 15.2 / 34.4 / 16.6 | 1.8 / 0.5 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · SDK [A] | MQTT → WAMP | 30.6 / 34.3 / 30.7 | 15.9 / 34.3 / 16.0 | 22.0 / 34.3 / 22.7 | 0.8 / 0.2 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · SDK [A] | WAMP → MQTT | 30.8 / 34.4 / 34.4 | 21.3 / 34.3 / 22.7 | 16.6 / 34.3 / 17.3 | 4.9 / 1.3 |
| TCP 3.1.1 · FlatBuffers · 64 KiB · 4/1 · SDK [B] | MQTT → WAMP | 35.4 / 65.2 / 37.3 | 15.8 / 34.3 / 15.9 | 21.5 / 34.3 / 31.2 | 2.1 / 0.4 |
| TCP 3.1.1 · FlatBuffers · 64 KiB · 4/1 · SDK [B] | WAMP → MQTT | 31.4 / 62.1 / 32.1 | 21.2 / 34.3 / 22.9 | 17.3 / 34.3 / 17.7 | 1.0 / 0.2 |
| TLS 5 · MessagePack · 128 B · 1/16 · SDK [C] | MQTT → WAMP | 31.3 / 34.3 / 31.6 | 17.1 / 34.3 / 17.2 | 22.8 / 34.3 / 23.2 | 1.7 / 0.4 |
| TLS 5 · MessagePack · 128 B · 1/16 · SDK [C] | WAMP → MQTT | 31.3 / 34.3 / 31.9 | 22.6 / 34.3 / 23.3 | 21.5 / 34.3 / 22.6 | 1.1 / 0.3 |
| TLS 5 · CBOR · 1 KiB · 4/1 · SDK [D] | MQTT → WAMP | 32.5 / 34.4 / 32.7 | 17.1 / 34.4 / 17.2 | 22.5 / 34.4 / 24.7 | 0.4 / 0.1 |
| TLS 5 · CBOR · 1 KiB · 4/1 · SDK [D] | WAMP → MQTT | 31.3 / 34.4 / 31.5 | 22.4 / 34.4 / 23.2 | 18.7 / 34.4 / 21.5 | 0.5 / 0.1 |
| TLS 5 · FlatBuffers · 64 KiB · 1/16 · SDK [A] | MQTT → WAMP | 75.4 / 105.9 / 100.8 | 47.7 / 48.6 / 48.2 | 22.9 / 34.3 / 32.5 | 15.2 / 0.0 |
| TLS 5 · FlatBuffers · 64 KiB · 1/16 · SDK [A] | WAMP → MQTT | 58.8 / 65.0 / 60.5 | 53.6 / 55.4 / 55.4 | 18.9 / 34.3 / 29.2 | 24.7 / 4.6 |
| TLS 3.1.1 · CBOR · 128 B · 4/16 · SDK [B] | MQTT → WAMP | 31.8 / 34.3 / 32.3 | 17.0 / 34.3 / 17.2 | 23.5 / 34.3 / 25.4 | 1.1 / 0.3 |
| TLS 3.1.1 · CBOR · 128 B · 4/16 · SDK [B] | WAMP → MQTT | 33.5 / 36.3 / 36.2 | 22.6 / 34.3 / 22.9 | 21.4 / 34.3 / 22.6 | 4.4 / 1.1 |
| TLS 3.1.1 · FlatBuffers · 1 KiB · 1/1 · SDK [C] | MQTT → WAMP | 24.7 / 34.3 / 24.9 | 17.0 / 34.3 / 17.6 | 22.5 / 34.3 / 23.8 | 0.5 / 0.1 |
| TLS 3.1.1 · FlatBuffers · 1 KiB · 1/1 · SDK [C] | WAMP → MQTT | 31.1 / 34.3 / 32.3 | 22.5 / 34.3 / 23.8 | 19.4 / 34.3 / 21.6 | 1.4 / 0.4 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · SDK [D] | MQTT → WAMP | 41.2 / 96.1 / 43.8 | 23.4 / 48.6 / 48.6 | 30.3 / 34.4 / 32.3 | 1.1 / 0.0 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · SDK [D] | WAMP → MQTT | 37.7 / 42.6 / 40.8 | 52.5 / 63.8 / 54.8 | 19.0 / 34.4 / 29.8 | 5.5 / 1.4 |
| WS 5 · CBOR · 128 B · 1/1 · SDK [A] | MQTT → WAMP | 23.1 / 34.3 / 23.2 | 16.5 / 34.3 / 16.6 | 21.7 / 34.3 / 22.4 | 0.5 / 0.1 |
| WS 5 · CBOR · 128 B · 1/1 · SDK [A] | WAMP → MQTT | 30.2 / 34.3 / 32.9 | 21.5 / 34.3 / 22.2 | 15.3 / 34.3 / 16.8 | 3.8 / 0.9 |
| WS 5 · FlatBuffers · 1 KiB · 4/16 · SDK [B] | MQTT → WAMP | 31.2 / 34.3 / 32.8 | 16.4 / 34.3 / 16.5 | 22.2 / 34.3 / 24.3 | 2.2 / 0.5 |
| WS 5 · FlatBuffers · 1 KiB · 4/16 · SDK [B] | WAMP → MQTT | 32.7 / 38.1 / 38.1 | 21.6 / 34.3 / 23.1 | 17.0 / 34.3 / 17.4 | 7.3 / 1.8 |
| WS 5 · JSON · 64 KiB · 1/1 · SDK [C] | MQTT → WAMP | 30.9 / 34.3 / 31.3 | 16.2 / 34.3 / 16.4 | 21.8 / 34.3 / 30.2 | 0.7 / 0.1 |
| WS 5 · JSON · 64 KiB · 1/1 · SDK [C] | WAMP → MQTT | 34.1 / 36.9 / 36.3 | 22.7 / 34.3 / 24.1 | 17.2 / 34.3 / 17.7 | 5.2 / 1.4 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · SDK [D] | MQTT → WAMP | 29.7 / 34.4 / 30.0 | 16.0 / 34.4 / 16.5 | 21.4 / 34.4 / 23.6 | 1.0 / 0.2 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · SDK [D] | WAMP → MQTT | 30.8 / 34.4 / 33.6 | 21.3 / 34.4 / 22.5 | 15.3 / 34.4 / 16.7 | 3.6 / 0.9 |
| WS 3.1.1 · JSON · 1 KiB · 1/16 · SDK [A] | MQTT → WAMP | 29.7 / 34.3 / 30.0 | 16.4 / 34.3 / 16.6 | 22.2 / 34.3 / 23.3 | 0.6 / 0.1 |
| WS 3.1.1 · JSON · 1 KiB · 1/16 · SDK [A] | WAMP → MQTT | 30.2 / 34.3 / 31.3 | 21.6 / 34.3 / 23.4 | 17.0 / 34.3 / 17.4 | 1.6 / 0.4 |
| WS 3.1.1 · MessagePack · 64 KiB · 4/1 · SDK [B] | MQTT → WAMP | 40.2 / 69.7 / 42.1 | 16.2 / 34.3 / 16.3 | 29.9 / 34.3 / 33.2 | 3.1 / 0.8 |
| WS 3.1.1 · MessagePack · 64 KiB · 4/1 · SDK [B] | WAMP → MQTT | 35.0 / 38.2 / 35.1 | 21.8 / 34.3 / 22.4 | 17.3 / 34.3 / 17.5 | 4.4 / 0.4 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · SDK [C] | MQTT → WAMP | 31.8 / 34.3 / 31.9 | 17.6 / 34.3 / 17.7 | 24.7 / 34.3 / 26.9 | 1.0 / 0.2 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · SDK [C] | WAMP → MQTT | 33.7 / 37.9 / 37.9 | 22.9 / 34.3 / 24.3 | 21.7 / 34.3 / 24.7 | 7.0 / 1.7 |
| WSS 5 · JSON · 1 KiB · 4/1 · SDK [D] | MQTT → WAMP | 31.8 / 34.4 / 32.0 | 17.5 / 34.4 / 17.6 | 22.8 / 34.4 / 23.1 | 0.5 / 0.1 |
| WSS 5 · JSON · 1 KiB · 4/1 · SDK [D] | WAMP → MQTT | 31.4 / 34.4 / 31.8 | 22.5 / 34.4 / 23.2 | 19.3 / 34.4 / 21.6 | 1.2 / 0.3 |
| WSS 5 · MessagePack · 64 KiB · 1/16 · SDK [A] | MQTT → WAMP | 57.1 / 72.1 / 68.3 | 49.2 / 49.8 / 49.8 | 31.1 / 34.3 / 33.0 | 22.7 / 0.2 |
| WSS 5 · MessagePack · 64 KiB · 1/16 · SDK [A] | WAMP → MQTT | 41.6 / 50.0 / 46.0 | 54.6 / 54.9 / 54.3 | 19.0 / 34.3 / 19.5 | 12.1 / 2.8 |
| WSS 3.1.1 · JSON · 128 B · 4/16 · SDK [B] | MQTT → WAMP | 31.5 / 34.3 / 32.1 | 17.6 / 34.3 / 17.6 | 23.2 / 34.3 / 25.1 | 1.2 / 0.3 |
| WSS 3.1.1 · JSON · 128 B · 4/16 · SDK [B] | WAMP → MQTT | 32.2 / 35.0 / 35.0 | 22.9 / 34.3 / 24.3 | 21.6 / 34.3 / 22.6 | 3.3 / 0.9 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · SDK [C] | MQTT → WAMP | 24.6 / 34.3 / 24.7 | 17.6 / 34.3 / 17.8 | 23.3 / 34.3 / 24.7 | 0.2 / 0.1 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · SDK [C] | WAMP → MQTT | 31.3 / 34.3 / 33.6 | 22.6 / 34.3 / 23.3 | 19.4 / 34.3 / 21.5 | 2.5 / 0.6 |
| WSS 3.1.1 · CBOR · 64 KiB · 4/16 · SDK [D] | MQTT → WAMP | 119.6 / 146.3 / 133.9 | 49.2 / 49.8 / 49.7 | 23.7 / 34.4 / 34.2 | 12.1 / 0.0 |
| WSS 3.1.1 · CBOR · 64 KiB · 4/16 · SDK [D] | WAMP → MQTT | 62.5 / 68.3 / 63.4 | 53.2 / 54.7 / 54.3 | 19.0 / 34.4 / 29.2 | 3.4 / 0.0 |
| TCP 5 · JSON · 128 B · 1/1 · Paho [A] | MQTT → WAMP | 22.8 / 34.3 / 22.9 | 25.5 / 34.3 / 25.6 | 21.6 / 34.3 / 23.4 | 0.2 / 0.0 |
| TCP 5 · JSON · 128 B · 1/1 · Paho [A] | WAMP → MQTT | 30.0 / 34.3 / 32.1 | 21.2 / 34.3 / 21.5 | 25.7 / 34.3 / 25.8 | 2.7 / 0.7 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · Paho [B] | MQTT → WAMP | 30.0 / 34.3 / 30.3 | 25.6 / 34.3 / 25.7 | 21.5 / 34.3 / 22.5 | 0.7 / 0.2 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · Paho [B] | WAMP → MQTT | 31.6 / 35.4 / 35.4 | 21.3 / 34.3 / 22.6 | 25.9 / 34.3 / 26.3 | 5.7 / 1.4 |
| TLS 5 · CBOR · 1 KiB · 4/1 · Paho [C] | MQTT → WAMP | 31.9 / 34.3 / 32.8 | 26.9 / 34.3 / 27.0 | 22.7 / 34.3 / 23.1 | 8.0 / 1.7 |
| TLS 5 · CBOR · 1 KiB · 4/1 · Paho [C] | WAMP → MQTT | 31.4 / 34.3 / 33.5 | 22.4 / 34.3 / 23.2 | 27.1 / 34.3 / 27.3 | 2.4 / 0.6 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · Paho [D] | MQTT → WAMP | 64.7 / 134.6 / 85.5 | 26.7 / 34.4 / 26.9 | 30.2 / 34.4 / 32.6 | 37.2 / 3.4 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · Paho [D] | WAMP → MQTT | 38.1 / 42.9 / 41.2 | 53.2 / 63.9 / 54.9 | 27.1 / 34.4 / 27.7 | 6.0 / 1.5 |
| WS 5 · JSON · 64 KiB · 1/1 · Paho [A] | MQTT → WAMP | 31.6 / 41.8 / 31.7 | 25.9 / 34.3 / 26.1 | 21.6 / 34.3 / 32.3 | 0.7 / 0.1 |
| WS 5 · JSON · 64 KiB · 1/1 · Paho [A] | WAMP → MQTT | 35.0 / 38.1 / 37.5 | 23.0 / 34.3 / 24.2 | 26.2 / 34.3 / 26.5 | 4.2 / 1.1 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · Paho [B] | MQTT → WAMP | 23.6 / 34.3 / 30.8 | 25.7 / 34.3 / 25.7 | 21.5 / 34.3 / 23.4 | 7.8 / 1.7 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · Paho [B] | WAMP → MQTT | 31.5 / 34.4 / 34.4 | 21.4 / 34.3 / 22.8 | 25.8 / 34.3 / 26.0 | 4.2 / 1.0 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · Paho [C] | MQTT → WAMP | 31.8 / 34.3 / 32.1 | 27.0 / 34.3 / 27.1 | 24.5 / 34.3 / 26.3 | 0.5 / 0.1 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · Paho [C] | WAMP → MQTT | 34.0 / 38.2 / 38.2 | 22.9 / 34.3 / 24.2 | 27.2 / 34.3 / 27.6 | 6.7 / 1.7 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · Paho [D] | MQTT → WAMP | 24.7 / 34.4 / 24.8 | 26.7 / 34.4 / 26.8 | 23.1 / 34.4 / 24.6 | 0.3 / 0.1 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · Paho [D] | WAMP → MQTT | 31.8 / 34.4 / 33.5 | 22.5 / 34.4 / 23.2 | 26.7 / 34.4 / 26.9 | 2.3 / 0.6 |

Matched direct controls, delivered messages/s. Mosquitto measures the MQTT leg.

| Profile | Direct MQTT/s | Direct WAMP/s | Ack WAMP/s | Mosquitto/s |
| --- | ---: | ---: | ---: | ---: |
| TCP 5 · JSON · 128 B · 1/1 · SDK [A] | 4,928 | 500 | 500 | 6,589 |
| TCP 5 · MessagePack · 1 KiB · 4/16 · SDK [B] | 106,162 | 19,766 | 16,259 | 1,556 |
| TCP 5 · CBOR · 64 KiB · 1/1 · SDK [C] | 2,086 | 500 | 500 | 2,829 |
| TCP 3.1.1 · MessagePack · 128 B · 4/1 · SDK [D] | 8,476 | 2,000 | 2,000 | 9,683 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · SDK [A] | 39,534 | 5,334 | 4,497 | 391 |
| TCP 3.1.1 · FlatBuffers · 64 KiB · 4/1 · SDK [B] | 6,191 | 1,205 | 1,135 | 6,641 |
| TLS 5 · MessagePack · 128 B · 1/16 · SDK [C] | 28,950 | 5,360 | 5,239 | 4,713 |
| TLS 5 · CBOR · 1 KiB · 4/1 · SDK [D] | 5,132 | 2,000 | 2,000 | 5,357 |
| TLS 5 · FlatBuffers · 64 KiB · 1/16 · SDK [A] | 906 | 1,195 | 1,164 | 993 |
| TLS 3.1.1 · CBOR · 128 B · 4/16 · SDK [B] | 92,154 | 18,800 | 15,353 | 32,149 |
| TLS 3.1.1 · FlatBuffers · 1 KiB · 1/1 · SDK [C] | 2,339 | 500 | 500 | 3,109 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · SDK [D] | 1,479 | 2,642 | 2,591 | 1,461 |
| WS 5 · CBOR · 128 B · 1/1 · SDK [A] | 4,669 | 500 | 500 | 5,970 |
| WS 5 · FlatBuffers · 1 KiB · 4/16 · SDK [B] | 77,415 | 15,015 | 12,414 | 66,790 |
| WS 5 · JSON · 64 KiB · 1/1 · SDK [C] | 2,015 | 500 | 500 | 2,114 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · SDK [D] | 8,201 | 2,000 | 2,000 | 9,233 |
| WS 3.1.1 · JSON · 1 KiB · 1/16 · SDK [A] | 25,856 | 5,343 | 4,889 | 31,233 |
| WS 3.1.1 · MessagePack · 64 KiB · 4/1 · SDK [B] | 5,943 | 2,000 | 1,999 | 2,736 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · SDK [C] | 30,314 | 5,265 | 4,117 | 16,335 |
| WSS 5 · JSON · 1 KiB · 4/1 · SDK [D] | 4,635 | 2,000 | 2,000 | 4,871 |
| WSS 5 · MessagePack · 64 KiB · 1/16 · SDK [A] | 952 | 4,094 | 3,749 | 943 |
| WSS 3.1.1 · JSON · 128 B · 4/16 · SDK [B] | 92,482 | 19,037 | 15,729 | 34,486 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · SDK [C] | 2,031 | 500 | 500 | 2,605 |
| WSS 3.1.1 · CBOR · 64 KiB · 4/16 · SDK [D] | 1,512 | 2,570 | 2,509 | 1,175 |
| TCP 5 · JSON · 128 B · 1/1 · Paho [A] | 4,003 | 500 | 500 | 5,156 |
| TCP 3.1.1 · CBOR · 1 KiB · 1/16 · Paho [B] | 10,169 | 5,339 | 4,506 | 389 |
| TLS 5 · CBOR · 1 KiB · 4/1 · Paho [C] | 8,473 | 2,000 | 2,000 | 10,961 |
| TLS 3.1.1 · JSON · 64 KiB · 4/16 · Paho [D] | 7,505 | 2,647 | 2,600 | 3,137 |
| WS 5 · JSON · 64 KiB · 1/1 · Paho [A] | 198 | 500 | 500 | 195 |
| WS 3.1.1 · FlatBuffers · 128 B · 4/1 · Paho [B] | 10,007 | 2,000 | 2,000 | 11,575 |
| WSS 5 · FlatBuffers · 128 B · 1/16 · Paho [C] | 8,190 | 5,323 | 4,100 | 10,690 |
| WSS 3.1.1 · MessagePack · 1 KiB · 1/1 · Paho [D] | 1,966 | 500 | 500 | 2,275 |

The slow-consumer check stalls one subscriber for 20 seconds during 2,048 × 64 KiB publications, 3 times per case.
Healthy subscribers receive every message; the stalled connection closes at its queue limit. Fresh clients then receive all 64 recovery messages on the same router, with queues and client state empty after disconnect.

| Link / codec | Direction | Healthy delivered/s | Slow received, max | Peak MiB B / P / healthy / slow | Drained MiB B / P / healthy / slow | Recovery/cycle |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| TCP 5 · CBOR · 64 KiB · 2/16 · SDK [A] | MQTT → WAMP | 1,437 | 161 | 94.4 / 44.8 / 34.3 / 100.6 | 92.5 / 44.8 / 26.3 / 100.6 | 64/64 |
| TCP 5 · CBOR · 64 KiB · 2/16 · SDK [A] | WAMP → MQTT | 472 | 285 | 65.6 / 52.8 / 36.4 / 58.9 | 56.7 / 52.7 / 36.4 / 40.5 | 64/64 |
| WSS 3.1.1 · FlatBuffers · 64 KiB · 2/16 · SDK [B] | MQTT → WAMP | 404 | 97 | 72.7 / 49.8 / 34.3 / 92.5 | 50.1 / 49.8 / 24.0 / 91.6 | 64/64 |
| WSS 3.1.1 · FlatBuffers · 64 KiB · 2/16 · SDK [B] | WAMP → MQTT | 405 | 69 | 68.1 / 55.3 / 34.3 / 34.3 | 58.9 / 54.6 / 19.1 / 19.0 | 64/64 |

## WAMP throughput

Each cell shows **sustained / full-lifecycle throughput** in Gbit/s; higher is better.
The values are medians of three matched local runs on an Apple M3 Ultra.
FlatBuffers means a FlatBuffers WAMP envelope with CBOR application fragments.
The [file measurements](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/wamp-flatbuffers-file-segments-2026-10-20/README.md)
and [other WAMP measurements](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/wamp-four-serializer-2026-10-20/README.md)
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
The [hosted Linux FlatBuffers file table](https://github.com/konsultaner/connectanum-dart/blob/benchmark-history-pr128-2026-10-30/docs/benchmarks/wamp-flatbuffers-hosted-linux-1c53c153-2026-10-20/README.md)
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
[CI workflow](../../.github/workflows/dart.yml) show the MQTT run setup. The
[gateway runner](../../tool/run_mqtt_gateway_benchmark.py) and
[Linux gateway workflow](../../.github/workflows/mqtt-gateway-benchmarks.yml)
reproduce the translation and memory measurements with pinned independent
clients. For
typed payload setup and test coverage, see the
[FlatBuffers acceptance contract](../../docs/flatbuffers_performance_acceptance.md).
