# Controlled MQTT broker source comparison

The predeclared [diagnostic run](https://github.com/konsultaner/connectanum-dart/actions/runs/41324624381)
compares `7476ff6e5c89b583ae32d317439e3774fc379e45` with
`4ec3878f6ee01bb73c4ff262b20d21c6d0bc73b7` on one EPYC 9V74 host,
using standard Dart 3.13.1 and Rust 1.99.0. This isolates the same-version
forwarding header change; it does not repeat the Mosquitto acceptance gate.

All fifty rows / 8.05 million fully verified deliveries are retained. Independent
reproduction checks complete exact source archives, 1,432 shared source inputs,
canonical candidate locks, all original client rows and alternating AB/BA order,
all successful broker exits and actual native/broker/client bytes. One shared
native build rehashes to the exact original MQTT `f9a7a6e5…` bytes. Both source
legs use one unchanged client and the same original windows, payloads, warmup,
publication mode and five repetitions. No body generation/check or ownership
boundary changes. The normal CPU/Intel jobs are skipped; no acceptance gate is
rerun. The tool-only source is `e2becb6e70457c92cc5936463706c000e4c38fc8`.

| Profile | Candidate/baseline median-rate ratio | Baseline/candidate broker CPU seconds |
| --- | ---: | ---: |
| WebSocket 5, 128 B | 0.99713216 | 8.43 / 8.46 |
| WebSocket 3.1.1, 128 B | 0.99273349 | 8.20 / 8.24 |
| TCP 5, 128 B | 0.98054777 | 3.57 / 3.69 |
| TCP 3.1.1, 128 B | 0.99704652 | 3.69 / 3.72 |
| TCP 5, 64 KiB | 0.99630477 | 0.46 / 0.46 |

All five MQTT 5 TCP pairs are slower; WebSocket pairs are mixed. These controlled
results do not support adopting `4ec3878f` as a CI repair. The measured public
header component improvement remains valid component evidence, and does not
establish network throughput, RAM parity or a cause for the old 7763 failure.
Retain the candidate and all failed acceptance evidence unchanged. A genuine
future repair needs a separate controlled change and its own complete final
verification/acceptance. Do not select a favorable unchanged numerical rerun.

[Complete independent audit and every pair](2026-11-01-mqtt-broker-source-comparison-audit.json).
