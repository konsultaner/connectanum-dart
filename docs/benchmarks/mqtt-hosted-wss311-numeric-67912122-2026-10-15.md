# Hosted MQTT 3.1.1 WSS numeric gate checkpoint

The [MQTT CI job](https://github.com/konsultaner/connectanum-dart/actions/runs/38691238629/job/116277540272) on PR head `67912122` passes all 20 profiles and 192 exact matched rows, with no duplicates. Paho and Connectanum MQTT 5/3.1.1 TCP/TLS/WS/WSS interoperability and the scoped 642/642 MQTT Dart and 254/254 Python benchmark-gate executable-line checks pass. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38691238629/artifacts/11953035474) is preserved as [192 raw rows](mqtt-hosted-wss311-numeric-67912122-2026-10-15-raw.jsonl) and [20 summaries](mqtt-hosted-wss311-numeric-67912122-2026-10-15-summaries.json). The clean PR merge checkout is `26e207fe` on an AMD EPYC 9V74 80-Core Processor with `ubuntu24` image `20261004.327.1` and pinned Mosquitto 2.0.18.

The first **hosted hard numeric gate** for MQTT 3.1.1 WSS sustained traffic passes five order-balanced 200,000-publication pairs. Connectanum's median is 136,063 delivered/s versus Mosquitto's 27,523/s: a 4.944× ratio with paired ratios from 4.929× to 5.023×. Its p95/p99 ratios are 0.189/0.188, broker CPU ratio is 0.432, and peak Connectanum broker RSS is 25.5 MB. The checked-in budget requires throughput ≥2.0×, p95 ≤0.8×, p99 ≤0.9×, CPU ≤1.5× and RSS ≤64 MiB. Every raw row has exact per-subscriber count and zero duplicates.

The two native WS single-publication throughput profiles also pass their unchanged 0.700× floors, but have less margin than the sustained WSS profile:

| Profile | Current ratio | Floor | Previous hosted ratio | Current broker CPU seconds per million |
| --- | ---: | ---: | ---: | ---: |
| Native WS MQTT 5, 128 B | 0.782× | 0.700× | 0.677× | 29.50 |
| Native WS MQTT 3.1.1, 128 B | 0.785× | 0.700× | 0.671× | 29.75 |

The previous [red checkpoint](mqtt-hosted-wss311-sustained-d97c10b4-2026-10-15.md) used an EPYC 7763 and image `20261012.334.1`; this run uses a different CPU model and image version. Both native and Mosquitto absolute WS rates changed. The passing result establishes exact-head CI proof of the new WSS budget, while repeatability and a controlled release margin for native WS remain open. Keep [#127](https://github.com/konsultaner/connectanum-dart/issues/127) and the milestone open.
