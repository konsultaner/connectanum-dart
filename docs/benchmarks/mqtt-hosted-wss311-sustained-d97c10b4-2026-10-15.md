# Hosted MQTT 3.1.1 WSS sustained checkpoint

The [MQTT CI job](https://github.com/konsultaner/connectanum-dart/actions/runs/38686705114/job/116263239069) on PR head `d97c10b4` ran all 20 profiles against the pinned Ubuntu 24.04/Mosquitto 2.0.18 reference. The clean PR merge checkout is `cb88dd04`, on `AMD EPYC 7763 64-Core Processor` with runner image `ubuntu24` version `20261012.334.1`. Paho and Connectanum MQTT 5/3.1.1 TCP/TLS/WS/WSS integration passed, as did exact 642/642 scoped MQTT Dart and 254/254 Python benchmark-gate executable lines. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38686705114/artifacts/11950989181) is preserved as [192 raw matched rows](mqtt-hosted-wss311-sustained-d97c10b4-2026-10-15-raw.jsonl) and [20 summaries](mqtt-hosted-wss311-sustained-d97c10b4-2026-10-15-summaries.json). Every row delivered its exact expected count with zero duplicates.

The new MQTT 3.1.1 WSS profile delivers 200,000 ordered 128-byte publications in each of five pairs for both brokers. Connectanum's median is 104,137 delivered/s versus Mosquitto's 17,492/s: a 5.953× ratio with paired ratios from 5.842× to 6.025×. Its p95/p99 ratios are 0.144/0.139, broker CPU ratio is 0.427, and peak Connectanum broker RSS is 25.2 MB. The profile was diagnostic on this run, requiring exact delivery; the next revision adds a provisional numeric CI budget of throughput ≥2.0×, p95 ≤0.8×, p99 ≤0.9×, CPU ≤1.5× and RSS ≤64 MiB. This is a hard CI gate for the pinned reference; a controlled release margin remains open. The saved ten raw rows pass that budget locally. Hosted proof of the numeric gate remains pending.

The job is **red** on two unchanged native WebSocket throughput floors, with all latency, CPU, RSS and exact-delivery checks passing:

| Profile | Current ratio | Floor | Prior hosted ratio | Current broker CPU seconds per million |
| --- | ---: | ---: | ---: | ---: |
| Native WS MQTT 5, 128 B | 0.677× | 0.700× | 0.837× | 45.85 |
| Native WS MQTT 3.1.1, 128 B | 0.671× | 0.700× | 0.848× | 44.20 |

The [prior host](mqtt-hosted-provenance-066e54d8-2026-10-15.md) reported an AMD EPYC 9V45, while this run used an EPYC 7763. Native WS absolute throughput fell from about 59,000 to 32,000–33,000 delivered/s; Mosquitto WS also fell from about 69,000–71,000 to 48,000–49,000/s. This hardware correlation is an observation, not proof of causation. Keep the unchanged WS floors and require a controlled, repeatable margin before closing [#127](https://github.com/konsultaner/connectanum-dart/issues/127) or the MQTT milestone.
