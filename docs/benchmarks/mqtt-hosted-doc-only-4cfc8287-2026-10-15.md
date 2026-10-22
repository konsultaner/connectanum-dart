# GitHub-hosted MQTT repeat on `4cfc8287` — 2026-10-15

The [MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38777377437/job/116569087333) passed all twenty unchanged profile gates on AMD EPYC 9V74, Ubuntu 24.04, runner image `20261012.334.1` and Mosquitto 2.0.18. The source is unchanged from the red `77d4c1f3` MQTT job, which ran on EPYC 7763. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38777377437/artifacts/11996317076), [archived summaries](mqtt-hosted-doc-only-4cfc8287-2026-10-15-summaries.json) and [192 raw rows](mqtt-hosted-doc-only-4cfc8287-2026-10-15-raw.jsonl) preserve the complete result.

Paho/Connectanum interoperability passes. All 192 rows deliver exact bytes and counts without duplicates. Scoped MQTT Dart coverage is 642/642 executable lines and the Python gate is 268/268. Every latency, broker CPU and RSS limit passes.

| Native profile | Connectanum/s | Mosquitto/s | Throughput ratio | Floor | Broker CPU ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 TCP, 128 B | 92,597 | 97,172 | 0.9529 | 0.7500 | 1.475 |
| MQTT 3.1.1 TCP, 128 B | 89,138 | 87,746 | 1.0159 | 0.7500 | 1.354 |
| MQTT 5 WS, 128 B | 45,786 | 57,646 | 0.7942 | 0.7000 | 1.836 |
| MQTT 3.1.1 WS, 128 B | 45,434 | 58,165 | 0.7811 | 0.7000 | 1.925 |
| MQTT 5 TCP, 64 KiB | 5,612 | 5,894 | 0.9523 | 0.7500 | 3.188 |

This green job does not establish a release margin across hosts: the same production source failed four native 128 B throughput floors on the preceding EPYC 7763 run. The broader workflow also has a separate [Dart VM Coverage job failure](https://github.com/konsultaner/connectanum-dart/actions/runs/38777377437/job/116573823689) before tests. Its shared FFI artifact was built with Rust 1.99.0, then consumed by a job where the moving `stable` channel installed Rust 1.99.1. Both jobs checked out merge commit `19ac0de4`, and the downloaded artifact SHA matched. The artifact identity correctly rejected the different toolchain; the follow-up pins the shared setup to one exact version.

Keep [performance issue #127](https://github.com/konsultaner/connectanum-dart/issues/127), draft PR #128 and milestone #2 open. WAMP↔MQTT translation performance and post-drain memory remain unmeasured under [#131](https://github.com/konsultaner/connectanum-dart/issues/131) until the live gateway exists.
