# connectanum_bench

Connectanum benchmark results for MQTT publish/subscribe and WAMP transports.
The package runs the WAMP and HTTP workloads; the MQTT runner lives under
`packages/connectanum_router/benchmark/`.

## MQTT publish and subscribe

This table shows all QoS 0 profiles from the [GitHub Actions run of head `38910e96`](https://github.com/konsultaner/connectanum-dart/actions/runs/40690921222/job/122825185662)
on Ubuntu 24.04 and AMD EPYC 7763, compared with Mosquitto 2.0.18.
C / M means Connectanum / Mosquitto. Higher delivery rate is better; lower
latency and broker CPU ratios are better. Peak RSS is Connectanum broker memory.
Workload counts are publications per run; fan-out rates count deliveries to all
subscribers. WS means WebSocket and WSS means secure WebSocket. Smoke rows
check delivery only. The two failed rows missed their throughput floor.

| Broker | MQTT / link | Workload | Delivered/s C / M | Rate × | p95 / p99 C/M × | Broker CPU C/M × | Peak RSS | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Dart | 5 / TCP | 128 B, 2k, single smoke | 73,279 / 66,441 | 1.103 | 1.151 / 1.131 | 1.000 | 10.0 MiB | Delivery pass |
| Dart | 5 / TCP | 128 B, 200k, single | 96,974 / 82,233 | 1.179 | 1.202 / 1.456 | 1.049 | 10.6 MiB | Pass |
| Dart | 3.1.1 / TCP | 128 B, 200k, single | 89,634 / 83,469 | 1.074 | 1.297 / 1.485 | 1.143 | 11.0 MiB | Pass |
| Dart | 5 / TCP | 128 B, 200k, batch 512 | 487,572 / 77,328 | 6.305 | 0.159 / 0.147 | 0.081 | 17.8 MiB | Pass |
| Dart | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 702,716 / 90,389 | 7.774 | 0.095 / 0.102 | 0.066 | 10.6 MiB | Pass |
| Native | 5 / TCP | 128 B, 2k, single smoke | 89,783 / 79,180 | 1.134 | 0.990 / 1.016 | 1.500 | 27.5 MiB | Delivery pass |
| Native | 5 / TCP | 128 B, 200k, single | 75,762 / 81,486 | 0.930 | 1.242 / 1.315 | 1.697 | 28.5 MiB | Pass |
| Native | 3.1.1 / TCP | 128 B, 200k, single | 75,087 / 82,158 | 0.914 | 1.231 / 1.326 | 1.798 | 27.3 MiB | Pass |
| Native | 5 / TCP | 1 KiB, 100k, single | 59,149 / 7,748 | 7.634 | 0.098 / 0.114 | 1.634 | 51.0 MiB | Pass |
| Native | 5 / TCP | 64 KiB, 5k, single | 4,127 / 4,882 | 0.845 | 1.212 / 1.159 | 3.905 | 58.3 MiB | Pass |
| Native | 5 / TCP | 128 B, 200k, batch 512 | 455,624 / 78,484 | 5.805 | 0.201 / 0.159 | 0.115 | 29.0 MiB | Pass |
| Native | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 653,599 / 90,533 | 7.219 | 0.112 / 0.117 | 0.100 | 21.8 MiB | Pass |
| Native | 5 / TLS | 128 B, 200k, single | 165,063 / 17,998 | 9.171 | 0.094 / 0.064 | 0.603 | 23.8 MiB | Pass |
| Native | 3.1.1 / TLS | 128 B, 200k, single | 166,128 / 17,958 | 9.251 | 0.094 / 0.063 | 0.617 | 24.0 MiB | Pass |
| Native | 5 / WS | 128 B, 200k, single | 33,945 / 49,377 | 0.687 | 1.489 / 1.569 | 2.373 | 22.4 MiB | **Fail** |
| Native | 3.1.1 / WS | 128 B, 200k, single | 34,016 / 49,855 | 0.682 | 1.499 / 1.587 | 2.367 | 22.2 MiB | **Fail** |
| Native | 5 / WSS | 128 B, 2k, single smoke | 66,219 / 16,397 | 4.038 | 0.244 / 0.257 | 0.500 | 23.1 MiB | Delivery pass |
| Native | 5 / WSS | 128 B, 200k, batch 64 | 87,078 / 16,733 | 5.204 | 0.211 / 0.209 | 0.297 | 23.2 MiB | Pass |
| Native | 3.1.1 / WSS | 128 B, 2k, single smoke | 49,623 / 15,079 | 3.291 | 0.353 / 0.387 | 0.500 | 22.9 MiB | Delivery pass |
| Native | 3.1.1 / WSS | 128 B, 200k, single | 108,149 / 17,571 | 6.155 | 0.143 / 0.137 | 0.422 | 24.1 MiB | Pass |

| Check | Result |
| --- | --- |
| Direct MQTT delivery | 29,114,000 expected and received across 192 benchmark samples; zero duplicates |
| Profile results | 18 of 20 passed: 14 of 16 performance profiles and all 4 delivery-only smoke profiles |
| 64 KiB CPU budget | 3.905× broker CPU ratio against a 4.0× cap on this AMD runner |
| MQTT ↔ WAMP translation | No benchmark yet; the live gateway is pending |
| Typed FlatBuffers PPT parity | No accepted performance result yet; outer-envelope measurements appear below |

| Hosted run and CPU | WS 5 rate × | WS 3.1.1 rate × | TCP 3.1.1 rate × | 64 KiB CPU × | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Required limit | ≥0.700 | ≥0.700 | ≥0.750 | ≤4.000 | — |
| [Measured `38910e96`](https://github.com/konsultaner/connectanum-dart/actions/runs/40690921222/job/122825185662), EPYC 7763 | 0.687 | 0.682 | 0.914 | 3.905 | Fail |
| [Prior retry](https://github.com/konsultaner/connectanum-dart/actions/runs/39788086482/job/122798346858), EPYC 7763 | 0.657 | 0.647 | 0.718 | 3.952 | Fail |
| [First exact-head run](https://github.com/konsultaner/connectanum-dart/actions/runs/39788086482/job/119859421236), EPYC 7763 | 0.656 | 0.653 | 0.830 | 3.696 | Fail |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39778169837/job/119822330473), EPYC 9V45 | 0.822 | 0.813 | 0.994 | 3.455 | Pass |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39411135727), Intel Xeon 6973P-C | — | — | — | 5.000 | Fail |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967), Intel Xeon 8573C | — | — | — | 4.294 | Fail |

The [raw results](../../docs/benchmarks/mqtt-hosted-pr128-38910e96.json)
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
