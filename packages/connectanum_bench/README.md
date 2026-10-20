# connectanum_bench

Connectanum benchmark results for MQTT publish/subscribe and WAMP transports.
The package runs the WAMP and HTTP workloads; the MQTT runner lives under
`packages/connectanum_router/benchmark/`.

## MQTT publish and subscribe

This table contains every QoS 0 profile from one [GitHub Actions run](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967)
on Ubuntu 24.04 and Intel Xeon Platinum 8573C, compared with Mosquitto 2.0.18.
C / M means Connectanum / Mosquitto. Higher delivered rate is better; lower
latency and broker CPU ratios are better. Peak RSS is Connectanum broker memory.
Workload counts are publications per run; fan-out rates count deliveries to all
subscribers. WS means WebSocket and WSS means secure WebSocket. Smoke rows check
delivery and have no numeric performance gate.

| Broker | MQTT / link | Workload | Delivered/s C / M | Rate × | p95 / p99 C/M × | Broker CPU C/M × | Peak RSS | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Dart | 5 / TCP | 128 B, 2k, single smoke | 131,087 / 123,908 | 1.058 | 1.105 / 1.106 | 1.000 | 10.3 MiB | Delivery pass |
| Dart | 5 / TCP | 128 B, 200k, single | 150,256 / 120,204 | 1.250 | 1.357 / 1.316 | 1.268 | 11.0 MiB | Pass |
| Dart | 3.1.1 / TCP | 128 B, 200k, single | 149,874 / 114,030 | 1.314 | 1.331 / 1.403 | 1.292 | 10.7 MiB | Pass |
| Dart | 5 / TCP | 128 B, 200k, batch 512 | 560,320 / 50,061 | 11.193 | 0.025 / 0.028 | 0.117 | 18.1 MiB | Pass |
| Dart | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 851,238 / 183,194 | 4.647 | 0.230 / 0.247 | 0.105 | 10.6 MiB | Pass |
| Native | 5 / TCP | 128 B, 2k, single smoke | 183,756 / 146,843 | 1.251 | 0.897 / 0.898 | 1.000 | 31.6 MiB | Delivery pass |
| Native | 5 / TCP | 128 B, 200k, single | 151,508 / 110,233 | 1.374 | 1.174 / 1.107 | 1.488 | 36.1 MiB | Pass |
| Native | 3.1.1 / TCP | 128 B, 200k, single | 152,374 / 122,126 | 1.248 | 1.160 / 1.045 | 1.472 | 36.4 MiB | Pass |
| Native | 5 / TCP | 1 KiB, 100k, single | 102,876 / 9,036 | 11.385 | 0.052 / 0.059 | 1.420 | 40.7 MiB | Pass |
| Native | 5 / TCP | 64 KiB, 5k, single | 4,148 / 4,691 | 0.884 | 1.229 / 1.220 | **4.294** | 55.1 MiB | **CPU cap missed** |
| Native | 5 / TCP | 128 B, 200k, batch 512 | 513,632 / 50,250 | 10.222 | 0.026 / 0.030 | 0.156 | 28.6 MiB | Pass |
| Native | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 742,267 / 184,738 | 4.018 | 0.282 / 0.284 | 0.174 | 22.0 MiB | Pass |
| Native | 5 / TLS | 128 B, 200k, single | 238,548 / 23,219 | 10.274 | 0.089 / 0.082 | 0.680 | 24.2 MiB | Pass |
| Native | 3.1.1 / TLS | 128 B, 200k, single | 243,986 / 22,843 | 10.681 | 0.085 / 0.042 | 0.646 | 23.9 MiB | Pass |
| Native | 5 / WS | 128 B, 200k, single | 72,010 / 80,820 | 0.891 | 1.147 / 1.177 | 1.632 | 23.2 MiB | Pass |
| Native | 3.1.1 / WS | 128 B, 200k, single | 72,490 / 79,645 | 0.910 | 1.123 / 1.172 | 1.610 | 23.4 MiB | Pass |
| Native | 5 / WSS | 128 B, 2k, single smoke | 83,833 / 19,934 | 4.206 | 0.258 / 0.275 | 0.667 | 22.9 MiB | Delivery pass |
| Native | 5 / WSS | 128 B, 200k, batch 64 | 104,604 / 20,995 | 4.982 | 0.238 / 0.232 | 0.376 | 23.2 MiB | Pass |
| Native | 3.1.1 / WSS | 128 B, 2k, single smoke | 62,800 / 19,070 | 3.293 | 0.380 / 0.416 | 1.000 | 23.4 MiB | Delivery pass |
| Native | 3.1.1 / WSS | 128 B, 200k, single | 161,857 / 22,112 | 7.320 | 0.132 / 0.130 | 0.529 | 23.7 MiB | Pass |

| Check | Result |
| --- | --- |
| Direct MQTT delivery | 29,114,000 expected and received across 192 benchmark samples; zero duplicates |
| Profile results | 19 of 20 passed: 15 of 16 performance profiles and all 4 delivery-only smoke profiles |
| Open performance limit | The 64 KiB TCP broker CPU ratio was 4.294× against a 4.0× cap |
| MQTT ↔ WAMP translation | No benchmark yet; the live gateway is pending |
| Typed FlatBuffers PPT parity | No accepted performance result yet; outer-envelope measurements appear below |

The [benchmark report](../../docs/benchmarks/mqtt-hosted-intel-58016dc8-2026-10-16.md)
and [raw results](../../docs/benchmarks/mqtt-hosted-intel-58016dc8-2026-10-16.json)
include the workload settings, limits, and runner details. These results describe
this measured run; QoS 0 does not guarantee delivery in every deployment.

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
