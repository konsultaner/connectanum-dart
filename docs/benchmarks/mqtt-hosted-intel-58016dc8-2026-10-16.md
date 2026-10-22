# Hosted MQTT QoS 0 checkpoint — `58016dc8`

The [GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967) ran on Ubuntu 24.04 (runner image `20261012.334.1`), Intel Xeon Platinum 8573C, with Mosquitto 2.0.18. The pull request head was `58016dc8`; the job measured its clean GitHub merge commit `5e8d60b8`. Its [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/artifacts/12011978479) and [checked-in summaries and raw rows](mqtt-hosted-intel-58016dc8-2026-10-16.json) contain 20 profiles and 192 matched samples. In those finite runs, the received count matched all 29,114,000 expected deliveries with zero duplicates; this does not change MQTT QoS 0 delivery semantics. Paho/Connectanum MQTT 5 and 3.1.1 integration passed. The five scoped MQTT Dart sources reached 652/652 executable lines; the Python benchmark gate reached 268/268.

Each performance profile uses five Connectanum and five Mosquitto runs. Delivered/s is the median for each target; throughput ratio is Connectanum/Mosquitto. The CPU ratio compares broker CPU seconds, and RSS is Connectanum broker peak `VmHWM`. The table selects representative native-router paths from the full 20-profile artifact.

| MQTT QoS 0 profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Broker CPU ratio | Peak RSS | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| MQTT 5 TCP, 128 B, window 512 | 151,508 | 110,233 | 1.374 | 1.488 | 36.1 MiB | Pass |
| MQTT 3.1.1 TCP, 128 B, window 512 | 152,374 | 122,126 | 1.248 | 1.472 | 36.4 MiB | Pass |
| MQTT 5 WebSocket, 128 B, window 512 | 72,010 | 80,820 | 0.891 | 1.632 | 23.2 MiB | Pass |
| MQTT 3.1.1 WebSocket, 128 B, window 512 | 72,490 | 79,645 | 0.910 | 1.610 | 23.4 MiB | Pass |
| MQTT 5 TCP, 64 KiB, window 32 | 4,148 | 4,691 | 0.884 | **4.294** | 55.1 MiB | **Fail: CPU cap 4.0** |
| MQTT 5 WSS, 128 B, batch 64 | 104,604 | 20,995 | 4.982 | 0.376 | 23.2 MiB | Pass |

Nineteen of twenty unchanged profile gates passed. The 64 KiB profile passed its 0.75 throughput floor, p95/p99 latency limits, and 96 MiB RSS cap, but its median broker CPU seconds were 0.73 versus Mosquitto's 0.17, exceeding the 4.0 ratio cap. This made the MQTT job red; the workflow's Full Verify job then failed its MQTT prerequisite. The previous [same-production-source EPYC 9V74 run](mqtt-hosted-same-source-99106e8f-2026-10-15.md) passed all twenty profiles and measured a 3.143 CPU ratio for the same 64 KiB profile on the same runner image. This is cross-host evidence, not a controlled release margin. Keep the budget and direct performance issue #127 open.

These measurements cover direct MQTT→MQTT QoS 0 routing. The live WAMP↔MQTT gateway (#116/#117) and translation throughput, tail latency, and post-drain memory gate (#131) are still unimplemented and unmeasured. Do not use these numbers as translation results or as release approval for other MQTT QoS levels or session features.
