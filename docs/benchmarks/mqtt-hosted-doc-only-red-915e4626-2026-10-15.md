# Hosted MQTT performance repeat on documentation-only head

The [MQTT job on PR head `915e4626`](https://github.com/konsultaner/connectanum-dart/actions/runs/38717813963/job/116364683011) is red on four throughput gates. This head changes documentation only after code head `fe14951f`, whose [full 37-job workflow](https://github.com/konsultaner/connectanum-dart/actions/runs/38708672375) and MQTT gate passed. The red job ran on an AMD EPYC 7763, while the green job ran on an AMD EPYC 9V74. Both use the `ubuntu24` image `20261012.334.1` and pinned Mosquitto 2.0.18. The current source has not been shown to regress; the release margin across hosted hardware remains unresolved.

The [uploaded MQTT artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38717813963/artifacts/11963593867) contains the full output. [All twenty summaries](mqtt-hosted-doc-only-red-915e4626-2026-10-15-summaries.json) and [192 raw paired rows](mqtt-hosted-doc-only-red-915e4626-2026-10-15-raw.jsonl) are checked in. Every row delivered the expected count with zero duplicates. Sixteen profiles pass all unchanged numeric budgets; four native sustained profiles miss throughput only:

| Profile | Throughput versus Mosquitto | Minimum | Broker CPU ratio | CPU maximum |
| --- | ---: | ---: | ---: | ---: |
| MQTT 5 TCP 128 B | 0.700 | 0.750 | 2.249 | 2.500 |
| MQTT 3.1.1 TCP 128 B | 0.736 | 0.750 | 2.120 | 2.500 |
| MQTT 5 WS 128 B | 0.663 | 0.700 | 2.431 | 5.000 |
| MQTT 3.1.1 WS 128 B | 0.667 | 0.700 | 2.445 | 5.000 |

All four p95, p99 and RSS budgets pass. The 64 KiB native TCP CPU ratio is 3.952 versus the unchanged 4.0 cap, close enough to preserve as a separate risk. Paho and Connectanum TCP/TLS/WS/WSS interoperability plus scoped 642/642 MQTT Dart and 254/254 Python benchmark-gate lines pass in the job.

A later Apple M3 Ultra diagnostic on the same production source measured a clean five-pair native WS MQTT 5 baseline of 121,853 delivered/s (0.931 versus Mosquitto, 3.37 broker CPU seconds) and a Dart-only TCP MQTT 5 baseline of 416,442/s (0.987, 0.42 seconds). An exact-topic matcher shortcut measured 118,348/s on native WS and was reverted. Reusing a decoded publish frame for same-version peers measured 118,285/s and 3.48 CPU seconds on native WS; Dart-only TCP was essentially flat at 421,210/s and 0.41 seconds. It was reverted. These local comparisons do not isolate the hosted EPYC gap; they rule out those two shortcuts as supported improvements. Keep the unchanged budgets and issue #127 open while seeking controlled repeated measurements or a source-backed native transport improvement.
