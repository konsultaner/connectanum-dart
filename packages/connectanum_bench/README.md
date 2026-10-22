# connectanum_bench

Connectanum benchmark results for MQTT publish/subscribe and WAMP transports.
The package runs the WAMP and HTTP workloads; the MQTT runner lives under
`packages/connectanum_router/benchmark/`.

## MQTT publish and subscribe

This table contains every QoS 0 profile from one [GitHub Actions run](https://github.com/konsultaner/connectanum-dart/actions/runs/39778169837/job/119822330473)
on Ubuntu 24.04 and AMD EPYC 9V45, compared with Mosquitto 2.0.18.
C / M means Connectanum / Mosquitto. Higher delivered rate is better; lower
latency and broker CPU ratios are better. Peak RSS is Connectanum broker memory.
Workload counts are publications per run; fan-out rates count deliveries to all
subscribers. WS means WebSocket and WSS means secure WebSocket. Smoke rows check
delivery and have no numeric performance gate.

| Broker | MQTT / link | Workload | Delivered/s C / M | Rate × | p95 / p99 C/M × | Broker CPU C/M × | Peak RSS | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Dart | 5 / TCP | 128 B, 2k, single smoke | 108,672 / 116,503 | 0.933 | 1.154 / 1.153 | 1.000 | 10.3 MiB | Delivery pass |
| Dart | 5 / TCP | 128 B, 200k, single | 112,741 / 122,324 | 0.922 | 1.226 / 1.212 | 1.369 | 11.3 MiB | Pass |
| Dart | 3.1.1 / TCP | 128 B, 200k, single | 122,929 / 120,647 | 1.019 | 1.171 / 1.176 | 1.210 | 17.8 MiB | Pass |
| Dart | 5 / TCP | 128 B, 200k, batch 512 | 969,673 / 116,675 | 8.311 | 0.125 / 0.164 | 0.061 | 17.8 MiB | Pass |
| Dart | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 1,424,157 / 173,202 | 8.223 | 0.087 / 0.100 | 0.064 | 10.3 MiB | Pass |
| Native | 5 / TCP | 128 B, 2k, single smoke | 144,791 / 121,212 | 1.195 | 0.937 / 0.950 | 1.000 | 22.3 MiB | Delivery pass |
| Native | 5 / TCP | 128 B, 200k, single | 126,899 / 124,492 | 1.019 | 1.094 / 1.044 | 1.453 | 31.4 MiB | Pass |
| Native | 3.1.1 / TCP | 128 B, 200k, single | 126,097 / 126,921 | 0.994 | 1.046 / 1.024 | 1.399 | 26.1 MiB | Pass |
| Native | 5 / TCP | 1 KiB, 100k, single | 98,337 / 8,898 | 11.051 | 0.059 / 0.068 | 1.366 | 41.3 MiB | Pass |
| Native | 5 / TCP | 64 KiB, 5k, single | 7,609 / 7,377 | 1.031 | 1.098 / 1.086 | 3.455 | 66.4 MiB | Pass |
| Native | 5 / TCP | 128 B, 200k, batch 512 | 901,990 / 114,632 | 7.869 | 0.143 / 0.162 | 0.071 | 28.3 MiB | Pass |
| Native | 5 / TCP | 128 B, 50k, 4 subscribers, batch 128 | 1,336,300 / 160,513 | 8.325 | 0.102 / 0.110 | 0.081 | 22.1 MiB | Pass |
| Native | 5 / TLS | 128 B, 200k, single | 378,211 / 42,486 | 8.902 | 0.107 / 0.110 | 0.457 | 24.6 MiB | Pass |
| Native | 3.1.1 / TLS | 128 B, 200k, single | 382,555 / 42,050 | 9.098 | 0.108 / 0.105 | 0.453 | 24.5 MiB | Pass |
| Native | 5 / WS | 128 B, 200k, single | 56,860 / 69,151 | 0.822 | 1.233 / 1.253 | 1.669 | 22.8 MiB | Pass |
| Native | 3.1.1 / WS | 128 B, 200k, single | 56,057 / 68,920 | 0.813 | 1.253 / 1.254 | 1.654 | 23.3 MiB | Pass |
| Native | 5 / WSS | 128 B, 2k, single smoke | 127,934 / 31,873 | 4.014 | 0.254 / 0.316 | 0.500 | 23.5 MiB | Delivery pass |
| Native | 5 / WSS | 128 B, 200k, batch 64 | 202,812 / 35,752 | 5.673 | 0.209 / 0.214 | 0.206 | 23.8 MiB | Pass |
| Native | 3.1.1 / WSS | 128 B, 2k, single smoke | 99,330 / 30,057 | 3.305 | 0.368 / 0.487 | 0.500 | 23.3 MiB | Delivery pass |
| Native | 3.1.1 / WSS | 128 B, 200k, single | 215,624 / 39,084 | 5.517 | 0.176 / 0.175 | 0.314 | 24.5 MiB | Pass |

| Check | Result |
| --- | --- |
| Direct MQTT delivery | 29,114,000 expected and received across 192 benchmark samples; zero duplicates |
| Profile results | 20 of 20 passed: all 16 performance profiles and 4 delivery-only smoke profiles |
| 64 KiB CPU budget | 3.455× broker CPU ratio against a 4.0× cap on this AMD runner |
| MQTT ↔ WAMP translation | No benchmark yet; the live gateway is pending |
| Typed FlatBuffers PPT parity | No accepted performance result yet; outer-envelope measurements appear below |

| 64 KiB check | Runner | Broker CPU C/M × | Gate |
| --- | --- | ---: | --- |
| [Current run](https://github.com/konsultaner/connectanum-dart/actions/runs/39778169837/job/119822330473) | AMD EPYC 9V45 | 3.455 | Pass |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/39411135727) | Intel Xeon 6973P-C | 5.000 | CPU cap missed |
| [Earlier run](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967) | Intel Xeon Platinum 8573C | 4.294 | CPU cap missed |

The [raw results](../../docs/benchmarks/mqtt-hosted-amd-fccc7566.json)
include workload settings, limits, and runner details. These results describe
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
