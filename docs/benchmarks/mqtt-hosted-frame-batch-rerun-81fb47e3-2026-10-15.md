# Hosted MQTT same-source performance rerun

The [MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38676306306/job/116230875668) reruns the unchanged native WebSocket frame-batching source on PR head `81fb47e3` (clean GitHub merge checkout `45072197`). The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38676306306/artifacts/11946805586) is retained as [176 raw rows](mqtt-hosted-frame-batch-rerun-81fb47e3-2026-10-15-raw.jsonl) and [18 summaries](mqtt-hosted-frame-batch-rerun-81fb47e3-2026-10-15-summaries.json). Every row delivers its exact expected count without duplicates. The Linux x86_64 reference is Mosquitto 2.0.18.

Fifteen of eighteen numeric profiles pass, compared with fourteen of eighteen in the [previous hosted run](mqtt-hosted-frame-batch-56860cca-2026-10-15.md). Only throughput floors fail; all p95/p99 latency, CPU and RSS limits pass.

| Failed profile | Throughput vs Mosquitto | Required floor | Connectanum delivered/s | Mosquitto delivered/s |
| --- | ---: | ---: | ---: | ---: |
| Native TCP MQTT 3.1.1, 128 B | 0.725× | 0.750× | 60,519 | 83,438 |
| Native WS MQTT 5, 128 B | 0.668× | 0.700× | 32,613 | 48,835 |
| Native WS MQTT 3.1.1, 128 B | 0.663× | 0.700× | 32,497 | 49,028 |

Dart-only TCP MQTT 3.1.1 passes this time at 0.823× after failing at 0.702× on the previous head, with no source change in the benchmarked path. Native WS remains near 33,000 deliveries/s in both runs; frame batching has not demonstrated a live throughput gain. The native WS CPU cost is about 45–46 seconds per million delivered messages versus 19 seconds for Mosquitto in this run. This is a measured cost gap, not yet an attribution to a specific function. Keep the throughput budgets and release gate open while profiling and testing changes with matched repeats.

The next CI revision pins the MQTT runner to Ubuntu 24.04 and fails early if the installed Mosquitto reference differs from 2.0.18; it also adds a separate MQTT 3.1.1 WSS exact-delivery smoke. Those changes were not present in this rerun and need their own hosted result.
