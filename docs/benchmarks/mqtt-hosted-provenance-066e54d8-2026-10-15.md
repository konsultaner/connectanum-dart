# Hosted MQTT benchmark provenance checkpoint

The [MQTT CI job](https://github.com/konsultaner/connectanum-dart/actions/runs/38683393161/job/116252986225) on PR head `066e54d8` passes Paho and Connectanum MQTT 5/3.1.1 QoS 0 interoperability over TCP/TLS/WS/WSS, exact 642/642 scoped MQTT Dart lines and 254/254 Python benchmark-gate lines, and all 19 benchmark profiles. The clean PR merge checkout is `c868dfea`. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38683393161/artifacts/11949137683) is retained as [182 raw rows](mqtt-hosted-provenance-066e54d8-2026-10-15-raw.jsonl) and [19 summaries](mqtt-hosted-provenance-066e54d8-2026-10-15-summaries.json); every matched row delivered its exact expected count without duplicates.

The new provenance fields identify the host as `AMD EPYC 9V45 96-Core Processor`, runner image `ubuntu24` version `20261012.334.1`, and Mosquitto `2.0.18`. Collection occurs after the timed samples. CPU and image identity make future same-source host comparisons auditable without changing the benchmark verdict.

| Sustained profile | Throughput vs Mosquitto | Paired run range | Previous hosted ratio |
| --- | ---: | ---: | ---: |
| Native TCP MQTT 3.1.1, 128 B | 1.003× | 0.904–1.041× | 1.005× |
| Native WS MQTT 5, 128 B | 0.837× | 0.829–0.855× | 0.843× |
| Native WS MQTT 3.1.1, 128 B | 0.848× | 0.835–0.862× | 0.850× |

All unchanged throughput, p95/p99 latency, broker CPU and RSS limits pass. These ratios are close to the [preceding pinned-reference checkpoint](mqtt-hosted-pinned-wss311-447b882b-2026-10-15.md), but the earlier run did not record its CPU model or runner image revision. The [earlier same-source red run](mqtt-hosted-frame-batch-rerun-81fb47e3-2026-10-15.md) remains evidence of shared-runner variation. Keep a controlled release margin and the sustained WSS 3.1.1 row open; this checkpoint alone does not close the MQTT performance milestone.
