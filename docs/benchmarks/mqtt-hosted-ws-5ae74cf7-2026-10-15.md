# Hosted MQTT WebSocket checkpoint on PR head `5ae74cf7`

The [MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38662372884/job/116186403240) passed Paho 2.1.0 interoperability and exact 642/642 scoped MQTT Dart plus 237/237 Python benchmark lines. Its 18 order-balanced broker profiles produced [176 raw rows](mqtt-hosted-ws-5ae74cf7-2026-10-15-raw.jsonl), each with exact bytes, count, order and zero duplicates. Fifteen [profile summaries](mqtt-hosted-ws-5ae74cf7-2026-10-15-summaries.json) pass their unchanged budgets. GitHub checked out PR merge source `3210edcf` for head `5ae74cf7`; every summary records that merge SHA and `git_dirty: false`.

| Failed profile | Throughput ratio | Required floor | p95 ratio | CPU ratio |
| --- | ---: | ---: | ---: | ---: |
| Native TCP MQTT 3.1.1, 128 B | 0.738 | 0.750 | 1.479 | 2.165 |
| Native WS MQTT 5, 128 B | 0.689 | 0.700 | 1.476 | 2.503 |
| Native WS MQTT 3.1.1, 128 B | 0.686 | 0.700 | 1.497 | 2.501 |

All three miss only throughput; their latency, CPU and RSS limits pass. The five WS pairs are tightly clustered around 0.68–0.69, so the WS miss is a real hosted margin problem on this source. Native TCP 3.1.1 varies more across pairs (0.663–0.778). MQTT 5 WSS batch and single-message smoke pass; the WSS batch throughput ratio is 5.197. The complete artifact is also [uploaded by CI](https://github.com/konsultaner/connectanum-dart/actions/runs/38662372884/artifacts/11939629215). Keep all numeric limits unchanged while testing the native read-ahead and bounded queue-coalescing candidate, then require another hosted run before closing #127.
