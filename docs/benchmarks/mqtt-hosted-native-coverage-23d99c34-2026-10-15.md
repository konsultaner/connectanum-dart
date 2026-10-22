# GitHub Actions MQTT repeat on `23d99c34`

The [MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38795048061/job/116629532161) passes all twenty unchanged numeric profiles on AMD EPYC 9V74, Ubuntu 24.04, Mosquitto 2.0.18 and Dart 3.13.1. Paho and Connectanum MQTT 5/3.1.1 interoperability, scoped 642/642 MQTT Dart lines, 268/268 Python benchmark-gate lines, and [all 192 exact matched rows](mqtt-hosted-native-coverage-23d99c34-2026-10-15-raw.jsonl) pass: 29,114,000 deliveries, zero duplicates. [All profile summaries](mqtt-hosted-native-coverage-23d99c34-2026-10-15-summaries.json) and the [GitHub artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38795048061/artifacts/12002333087) preserve the evidence.

| Native profile | Throughput ratio | Floor | Connectanum / Mosquitto delivered/s |
| --- | ---: | ---: | ---: |
| MQTT 5 TCP 128 B | 0.9811 | 0.7500 | 69,283 / 70,619 |
| MQTT 3.1.1 TCP 128 B | 1.0149 | 0.7500 | 68,779 / 67,772 |
| MQTT 5 WS 128 B | 0.7834 | 0.7000 | 35,301 / 45,058 |
| MQTT 3.1.1 WS 128 B | 0.7845 | 0.7000 | 35,297 / 44,994 |

The MQTT 5 TCP 64 KiB broker CPU ratio is 3.095 below its unchanged 4.0 cap. This head adds native regressions and coverage evidence; its production MQTT transport and client are unchanged from the EPYC 7763 [red `44a59855` run](mqtt-hosted-44a59855-2026-10-15.md). This green hosted result therefore confirms host-sensitive margin, not a performance fix. Issue #127 and the release gate remain open. The later client flush-budget candidate has separate local evidence and still requires hosted proof.
