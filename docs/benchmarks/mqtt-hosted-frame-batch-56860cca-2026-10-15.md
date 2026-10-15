# Hosted MQTT checkpoint after native WebSocket frame batching

The [GitHub MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38674683783/job/116225476431) on PR head `56860cca` passes independent Paho/Connectanum MQTT 5 and 3.1.1 interoperability over TCP/TLS/WS/WSS, the focused 642/642 MQTT Dart and 237/237 Python executable-line gates, and all 176 matched broker/client delivery rows. Every row has exact per-subscriber delivery with no duplicates. GitHub checked out clean PR merge source `a68fb41f`; Mosquitto is 2.0.18 on Linux x86_64. The uploaded [artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38674683783/artifacts/11945453453) is retained here as [raw rows](mqtt-hosted-frame-batch-56860cca-2026-10-15-raw.jsonl) and [18 profile summaries](mqtt-hosted-frame-batch-56860cca-2026-10-15-summaries.json).

Fourteen of eighteen unchanged numeric gates pass. Four fail **throughput only**; all p95, p99, CPU and RSS limits pass.

| Failed profile | Throughput vs Mosquitto | Required floor | Connectanum delivered/s | Mosquitto delivered/s |
| --- | ---: | ---: | ---: | ---: |
| Dart-only TCP MQTT 3.1.1, 128 B | 0.702× | 0.750× | 58,739 | 83,718 |
| Native TCP MQTT 3.1.1, 128 B | 0.733× | 0.750× | 61,493 | 83,949 |
| Native WS MQTT 5, 128 B | 0.662× | 0.700× | 33,113 | 49,989 |
| Native WS MQTT 3.1.1, 128 B | 0.645× | 0.700× | 33,702 | 52,250 |

The previous hosted head `7a70978c` had six throughput misses, including Dart-only and native TCP MQTT 5. Those two MQTT 5 TCP profiles pass here at 0.813× and 0.754×; the other four remain below their floors. Native WS MQTT 5/3.1.1 absolute throughput stays near 33,000/s across both hosted heads, while the Mosquitto reference varies from about 48,000 to 52,000/s. The bounded frame batching test proves fewer native-to-Dart chunks when complete frames share a read buffer, but this hosted workload does not show a WS throughput gain. Keep the existing budgets, the performance issue and the milestone open; investigate the shared Dart publication path and measure proposed changes with matched repeats before accepting them.
