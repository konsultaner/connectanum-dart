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
| Typed FlatBuffers parity | No accepted performance result yet |

The [benchmark report](../../docs/benchmarks/mqtt-hosted-intel-58016dc8-2026-10-16.md)
and [raw results](../../docs/benchmarks/mqtt-hosted-intel-58016dc8-2026-10-16.json)
include the workload settings, limits, and runner details. These results describe
this measured run; QoS 0 does not guarantee delivery in every deployment.

## WAMP throughput

These tables show a local benchmark snapshot for JSON, MessagePack, and CBOR.
Each cell gives **sustained / full-lifecycle throughput** in Gbit/s. The snapshot
was recorded on 2026-08-24; the [WAMP benchmark contract](../../docs/wamp_profile_benchmarks.md)
contains the test setup and limits. FlatBuffers performance parity is still
pending.

### 64 MiB file transfer

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| Native RawSocket | 16.102 / 14.913 | 18.242 / 16.843 | 19.174 / 17.180 |
| Dart RawSocket, buffered | 5.292 / 4.804 | 9.491 / 8.013 | 12.007 / 9.630 |
| Native RawSocket TLS | 13.262 / 12.504 | 18.340 / 16.943 | 17.324 / 15.966 |
| Native WebSocket | 15.663 / 14.437 | 19.407 / 17.748 | 19.057 / 17.180 |
| Dart WebSocket, buffered | 2.351 / 2.239 | 9.430 / 7.697 | 9.370 / 7.483 |
| Native WebSocket TLS | 12.874 / 12.014 | 18.155 / 16.424 | 16.951 / 15.203 |
| Native RawSocket + E2EE | 8.725 / 8.397 | 20.843 / 19.131 | 21.182 / 19.303 |
| Native RawSocket TLS + E2EE | 8.592 / 8.244 | 18.097 / 16.777 | 17.853 / 16.487 |
| Native WebSocket + E2EE | 8.516 / 8.142 | 20.891 / 18.921 | 19.218 / 17.424 |
| Native WebSocket TLS + E2EE | 8.329 / 7.932 | 17.339 / 15.704 | 15.701 / 14.413 |

Files use 4 MiB chunks.

### Large RPC frames

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| Native RawSocket | 13.612 / 4.965 | 21.246 / 6.638 | 19.525 / 4.914 |
| Native WebSocket | 6.816 / 5.949 | 9.132 / 7.809 | 6.644 / 5.674 |
| Native RawSocket TLS | 8.820 / 4.146 | 11.417 / 5.150 | 10.798 / 4.067 |
| Native WebSocket TLS | 5.578 / 4.965 | 6.613 / 5.828 | 5.276 / 4.628 |
| Dart RawSocket | 2.411 / 1.851 | 19.749 / 6.547 | 18.651 / 4.810 |
| Dart WebSocket | 2.616 / 2.475 | 7.886 / 6.883 | 7.306 / 6.216 |
| Dart RawSocket TLS reference[^dart-tls] | 0.741 / 0.678 | 0.989 / 0.896 | 0.987 / 0.858 |
| Dart WebSocket TLS reference[^dart-tls] | 0.717 / 0.706 | 0.934 / 0.917 | 0.929 / 0.906 |

RawSocket frames are 64 MiB; WebSocket frames are 8 MiB.

### WebSocket fragmentation and Pub/Sub

| Transport and workload | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| WebSocket RPC, contiguous | 18.156 / 14.364 | 26.577 / 19.089 | 12.631 / 10.154 |
| WebSocket RPC, 4 KiB fragments | 8.761 / 7.683 | 11.047 / 9.460 | 7.444 / 6.557 |
| WebSocket Pub/Sub, contiguous | 6.962 / 6.032 | 11.818 / 9.673 | 4.229 / 3.825 |
| WebSocket Pub/Sub, 4 KiB fragments | 6.706 / 5.884 | 7.232 / 6.363 | 4.515 / 4.090 |
| WebSocket TLS RPC, contiguous | 9.469 / 8.212 | 12.251 / 10.399 | 7.977 / 6.961 |
| WebSocket TLS RPC, 4 KiB fragments | 8.134 / 7.206 | 8.981 / 7.954 | 6.969 / 6.180 |
| WebSocket TLS Pub/Sub, contiguous | 3.472 / 3.208 | 4.715 / 4.265 | 2.725 / 2.540 |
| WebSocket TLS Pub/Sub, 4 KiB fragments | 3.635 / 3.363 | 4.620 / 4.215 | 2.517 / 2.355 |

Fragmented rows use 4 MiB payloads split into 4 KiB frames with four messages
in flight. The [hosted WAMP profile run](https://github.com/konsultaner/connectanum-dart/actions/runs/29580331118)
passed its performance policies. These measurements are workload-specific.

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
