# Hosted MQTT pinned-reference checkpoint

The [MQTT CI job](https://github.com/konsultaner/connectanum-dart/actions/runs/38678805553/job/116238659445) on PR head `447b882b` passes Paho and Connectanum MQTT 5/3.1.1 QoS 0 interoperability over TCP/TLS/WS/WSS, scoped 642/642 Dart and 237/237 Python executable-line gates, and all 19 benchmark profiles. The clean PR merge checkout is `fa8ef518`; the runner is Ubuntu 24.04, Linux x86_64, with the explicitly checked Mosquitto 2.0.18 reference. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38678805553/artifacts/11947479078) is retained as [182 raw rows](mqtt-hosted-pinned-wss311-447b882b-2026-10-15-raw.jsonl) and [19 summaries](mqtt-hosted-pinned-wss311-447b882b-2026-10-15-summaries.json). Every row has exact per-subscriber delivery and zero duplicates.

| Sustained profile | Throughput vs Mosquitto | Connectanum delivered/s | Mosquitto delivered/s | Previous same-source ratio |
| --- | ---: | ---: | ---: | ---: |
| Native TCP MQTT 3.1.1, 128 B | 1.005× | 112,782 | 112,233 | 0.725× |
| Native WS MQTT 5, 128 B | 0.843× | 58,172 | 68,983 | 0.668× |
| Native WS MQTT 3.1.1, 128 B | 0.850× | 58,270 | 68,516 | 0.663× |

These three profiles now clear their unchanged 0.750/0.700/0.700 throughput floors; all other throughput, p95/p99 latency, broker CPU and RSS limits pass too. The new MQTT 3.1.1 WSS correctness smoke delivers 2,000/2,000 ordered publications in each of three matched pairs against both brokers (six exact rows). Its 3.413× median throughput ratio is diagnostic, not a sustained performance budget. The Mosquitto 2.1.2 direct WSS 3.1.1 incompatibility observed locally remains open.

The router and benchmark data path is unchanged from the [previous hosted run](mqtt-hosted-frame-batch-rerun-81fb47e3-2026-10-15.md), whose three ratios missed the same floors. The GitHub merge commits have the same `master` parent `73d840c9`; between PR heads, changes are workflow, budget fixture, test and documentation. Native WS absolute throughput rose from about 32,500 to 58,200 deliveries/s; Mosquitto rose from about 49,000 to 69,000/s. This variation cannot be credited to frame batching or another source optimization. Preserve the green CI checkpoint and unchanged budgets, but require controlled hardware and repeatable margin before calling MQTT performance release-ready.
