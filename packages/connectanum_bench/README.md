# connectanum_bench

Connectanum benchmark results for MQTT publish/subscribe and WAMP transports.
The package runs the WAMP and HTTP workloads; the MQTT runner lives under
`packages/connectanum_router/benchmark/`.

## MQTT publish and subscribe

This table shows all QoS 0 profiles from the [GitHub Actions run of head `8f65e2ae`](https://github.com/konsultaner/connectanum-dart/actions/runs/40697536943/job/122849485870)
on Ubuntu 24.04 and AMD EPYC 7763, compared with Mosquitto 2.0.18.
C / M means Connectanum / Mosquitto. Higher delivery rate is better; lower
latency and broker CPU ratios are better. Peak RSS is Connectanum broker memory.
Workload counts are publications per run; fan-out rates count deliveries to all
subscribers. WS means WebSocket and WSS means secure WebSocket. Smoke rows
check delivery only. The two failed rows missed their throughput floor.

| Broker | MQTT / link | Workload | Delivered/s C / M | Rate × | p95 / p99 C/M × | Broker CPU C/M × | Peak RSS | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Dart | 5 / TCP | 128 B, 2k, single smoke | 63,426 / 69,652 | 0.911 | 1.261 / 1.253 | 1.000 | 9.9 MiB | Delivery pass |
| Dart | 5 / TCP | 128 B, 200k, single | 79,329 / 81,156 | 0.977 | 1.497 / 1.515 | 1.339 | 11.1 MiB | Pass |
| Dart | 3.1.1 / TCP | 128 B, 200k, single | 84,853 / 78,666 | 1.079 | 1.438 / 1.513 | 1.190 | 10.9 MiB | Pass |
| Dart | 5 / TCP | 128 B, 200k, batch 512 | 495,135 / 69,336 | 7.141 | 0.132 / 0.129 | 0.075 | 17.8 MiB | Pass |
| Dart | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 693,929 / 97,086 | 7.148 | 0.100 / 0.105 | 0.072 | 10.2 MiB | Pass |
| Native | 5 / TCP | 128 B, 2k, single smoke | 83,167 / 80,733 | 1.030 | 1.173 / 1.211 | 1.333 | 21.9 MiB | Delivery pass |
| Native | 5 / TCP | 128 B, 200k, single | 73,611 / 81,517 | 0.903 | 1.360 / 1.269 | 1.894 | 34.9 MiB | Pass |
| Native | 3.1.1 / TCP | 128 B, 200k, single | 74,505 / 76,987 | 0.968 | 1.242 / 1.312 | 1.806 | 34.6 MiB | Pass |
| Native | 5 / TCP | 1 KiB, 100k, single | 59,218 / 8,047 | 7.359 | 0.098 / 0.116 | 1.627 | 45.1 MiB | Pass |
| Native | 5 / TCP | 64 KiB, 5k, single | 4,346 / 4,893 | 0.888 | 1.198 / 1.112 | 3.682 | 55.9 MiB | Pass |
| Native | 5 / TCP | 128 B, 200k, batch 512 | 457,439 / 77,418 | 5.909 | 0.171 / 0.151 | 0.115 | 27.9 MiB | Pass |
| Native | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 652,756 / 89,043 | 7.331 | 0.115 / 0.114 | 0.099 | 21.9 MiB | Pass |
| Native | 5 / TLS | 128 B, 200k, single | 162,319 / 17,346 | 9.358 | 0.093 / 0.065 | 0.632 | 24.2 MiB | Pass |
| Native | 3.1.1 / TLS | 128 B, 200k, single | 163,346 / 17,312 | 9.436 | 0.091 / 0.061 | 0.616 | 24.8 MiB | Pass |
| Native | 5 / WS | 128 B, 200k, single | 33,189 / 48,598 | 0.683 | 1.501 / 1.578 | 2.441 | 22.4 MiB | **Fail** |
| Native | 3.1.1 / WS | 128 B, 200k, single | 33,483 / 48,475 | 0.691 | 1.488 / 1.546 | 2.369 | 22.3 MiB | **Fail** |
| Native | 5 / WSS | 128 B, 2k, single smoke | 64,086 / 15,262 | 4.199 | 0.219 / 0.250 | 0.500 | 23.1 MiB | Delivery pass |
| Native | 5 / WSS | 128 B, 200k, batch 64 | 84,070 / 16,092 | 5.224 | 0.214 / 0.210 | 0.301 | 23.2 MiB | Pass |
| Native | 3.1.1 / WSS | 128 B, 2k, single smoke | 48,272 / 13,609 | 3.547 | 0.301 / 0.357 | 0.400 | 22.9 MiB | Delivery pass |
| Native | 3.1.1 / WSS | 128 B, 200k, single | 106,458 / 16,803 | 6.336 | 0.138 / 0.132 | 0.424 | 23.8 MiB | Pass |

| Check | Result |
| --- | --- |
| Direct MQTT delivery | 29,114,000 expected and received across 192 benchmark samples; zero duplicates |
| Profile results | 18 of 20 passed: 14 of 16 performance profiles and all 4 delivery-only smoke profiles |
| 64 KiB CPU budget | 3.682× broker CPU ratio against a 4.0× cap on this AMD runner |
| MQTT ↔ WAMP translation | No benchmark yet; the live gateway is pending |
| Typed FlatBuffers PPT parity | No accepted performance result yet; outer-envelope measurements appear below |

| Hosted run and CPU | WS 5 rate × | WS 3.1.1 rate × | TCP 3.1.1 rate × | 64 KiB CPU × | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Required limit | ≥0.700 | ≥0.700 | ≥0.750 | ≤4.000 | — |
| [Measured `8f65e2ae`](https://github.com/konsultaner/connectanum-dart/actions/runs/40697536943/job/122849485870), EPYC 7763 | 0.683 | 0.691 | 0.968 | 3.682 | Fail |
| [Prior `38910e96`](https://github.com/konsultaner/connectanum-dart/actions/runs/40690921222/job/122825185662), EPYC 7763 | 0.687 | 0.682 | 0.914 | 3.905 | Fail |
| [Prior retry](https://github.com/konsultaner/connectanum-dart/actions/runs/39788086482/job/122798346858), EPYC 7763 | 0.657 | 0.647 | 0.718 | 3.952 | Fail |
| [First exact-head run](https://github.com/konsultaner/connectanum-dart/actions/runs/39788086482/job/119859421236), EPYC 7763 | 0.656 | 0.653 | 0.830 | 3.696 | Fail |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39778169837/job/119822330473), EPYC 9V45 | 0.822 | 0.813 | 0.994 | 3.455 | Pass |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39411135727), Intel Xeon 6973P-C | — | — | — | 5.000 | Fail |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967), Intel Xeon 8573C | — | — | — | 4.294 | Fail |

The [raw results](../../docs/benchmarks/mqtt-hosted-pr128-8f65e2ae.json)
include every sample, workload setting, limit, and runner detail. An
[earlier passing AMD snapshot](../../docs/benchmarks/mqtt-hosted-amd-fccc7566.json)
is available for comparison. These results describe this measured run; QoS 0
does not guarantee delivery in every deployment.

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
