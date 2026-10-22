# Native MQTT QoS 0 backpressure benchmark checkpoint

Date: 2026-10-14. Source: `f58c0dab` on an Apple M3 Ultra. This is a clean-tree local comparison, not a cross-machine release claim.

The broker retries a full native outbound queue in FIFO order with a 4 MiB per-peer limit. Fresh traffic now probes the queued head immediately; a 1 ms timer still retries when traffic stops. This follow-up was prompted by a [hosted disconnect](https://github.com/konsultaner/connectanum-dart/actions/runs/38616556441/job/116033811975) and a subsequent [hosted throughput miss](https://github.com/konsultaner/connectanum-dart/actions/runs/38621243972/job/116049839954) at 0.732× Mosquitto against the unchanged 0.75 floor. The exact cause of the earlier generic EOF was not observable from its log, while a deterministic test proves the queue-full close path.

Six process-isolated native-router profiles use the same AOT Connectanum benchmark client against Connectanum and Mosquitto. Each profile has five order-balanced pairs and records exact bytes, order, counts and duplicates before numeric budgets. Sustained profiles publish 200,000 128-byte messages per run with a 512-message window; fan-out has four subscribers. TLS peers verify the checked-in CA. All 60 local raw broker/client rows are exact with zero duplicates. The summaries retain binary/native-library hashes, machine details, budgets and `git_dirty: false`.

| Profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Peak Connectanum RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 TCP sustained | 394,972 | 404,820 | 0.976 | 1.043 | 1.025 | 2.023 | 40.7 MiB |
| MQTT 3.1.1 TCP sustained | 387,292 | 406,889 | 0.952 | 1.067 | 1.112 | 2.070 | 39.9 MiB |
| MQTT 5 TCP batch | 706,944 | 418,410 | 1.690 | 0.711 | 0.725 | 0.390 | 30.6 MiB |
| MQTT 5 TCP fan-out ×4 | 1,288,818 | 583,082 | 2.210 | 0.502 | 0.445 | 0.290 | 35.9 MiB |
| MQTT 5 TLS sustained | 382,535 | 72,718 | 5.261 | 0.126 | 0.118 | 0.803 | 31.0 MiB |
| MQTT 3.1.1 TLS sustained | 395,070 | 71,892 | 5.495 | 0.113 | 0.102 | 0.793 | 30.8 MiB |

Each row passes its existing checked-in throughput, p95/p99, broker CPU and RSS limits. MQTT 5 native TCP returns to the previous clean local throughput ratio of 0.976 before retry was added. Hosted Linux proof of the eager-drain change and controlled release measurements remain pending.

| Profile | Summary | Raw matched rows |
| --- | --- | --- |
| MQTT 5 TCP sustained | [summary](mqtt-backpressure-f58c0dab-native5-summary.json) | [raw](mqtt-backpressure-f58c0dab-native5-raw.jsonl) |
| MQTT 3.1.1 TCP sustained | [summary](mqtt-backpressure-f58c0dab-native311-summary.json) | [raw](mqtt-backpressure-f58c0dab-native311-raw.jsonl) |
| MQTT 5 TCP batch | [summary](mqtt-backpressure-f58c0dab-batch-summary.json) | [raw](mqtt-backpressure-f58c0dab-batch-raw.jsonl) |
| MQTT 5 TCP fan-out ×4 | [summary](mqtt-backpressure-f58c0dab-fanout-summary.json) | [raw](mqtt-backpressure-f58c0dab-fanout-raw.jsonl) |
| MQTT 5 TLS sustained | [summary](mqtt-backpressure-f58c0dab-tls5-summary.json) | [raw](mqtt-backpressure-f58c0dab-tls5-raw.jsonl) |
| MQTT 3.1.1 TLS sustained | [summary](mqtt-backpressure-f58c0dab-tls311-summary.json) | [raw](mqtt-backpressure-f58c0dab-tls311-raw.jsonl) |
