# Hosted MQTT checkpoint after native WebSocket read-ahead

The [CI MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38667000458/job/116201245236) on PR head `7a70978c` passes Paho/Connectanum interoperability, exact 642/642 scoped MQTT Dart and 237/237 Python benchmark lines, and all 176 matched broker/client delivery rows. The uploaded [artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38667000458/artifacts/11942372900) is retained here as [raw rows](mqtt-hosted-optimized-7a70978c-2026-10-15-raw.jsonl) and [18 profile summaries](mqtt-hosted-optimized-7a70978c-2026-10-15-summaries.json). GitHub checked out clean PR merge source `7878f594` for head `7a70978c`.

Twelve unchanged profile gates pass. Six fail **throughput only**; every p95/p99, CPU and RSS limit passes.

| Failed profile | Throughput vs Mosquitto | Required floor | Connectanum delivered/s | Mosquitto delivered/s |
| --- | ---: | ---: | ---: | ---: |
| Dart-only TCP MQTT 5, 128 B | 0.745× | 0.750× | 63,243 | 84,894 |
| Dart-only TCP MQTT 3.1.1, 128 B | 0.713× | 0.750× | 57,889 | 81,210 |
| Native TCP MQTT 5, 128 B | 0.732× | 0.750× | 61,152 | 83,515 |
| Native TCP MQTT 3.1.1, 128 B | 0.722× | 0.750× | 60,594 | 83,870 |
| Native WS MQTT 5, 128 B | 0.680× | 0.700× | 33,303 | 48,946 |
| Native WS MQTT 3.1.1, 128 B | 0.676× | 0.700× | 32,681 | 48,315 |

The prior hosted WS run on head `5ae74cf7` measured native WS MQTT 5/3.1.1 at 33,170/33,399 delivered/s against Mosquitto 48,120/48,695. The native read-ahead/coalescing change reduced WS broker CPU ratio from 2.503/2.501 to 2.344/2.404, but did **not** increase hosted absolute WS throughput. The new Dart-only TCP failures occur outside the native change, and native TCP throughput is similarly flat. Treat the common Dart publication path and hosted variance as separate hypotheses, not as proof of either cause. Keep all numeric limits unchanged and the performance issue open.
