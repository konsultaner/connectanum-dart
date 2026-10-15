# Native MQTT WebSocket buffered-frame batching

Clean-source macOS arm64 benchmark on `29fb8e0c` against Mosquitto 2.1.2. The native MQTT WebSocket reader batches complete frames already in its 16 KiB input buffer into bounded 64 KiB chunks before handing them to Dart. Five order-balanced matched pairs per numeric profile publish 200,000 messages per broker; the WSS single-message smoke uses three pairs of 2,000. All 46 broker/client rows deliver the exact count and bytes in order without duplicates. Each summary records `git_dirty: false`, source and executable hashes, native-library hash, toolchain, budget and host provenance.

| Profile | Throughput vs Mosquitto | p95 latency | p99 latency | Broker CPU | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| MQTT 5 WS single | 0.867× | 1.272× | 1.140× | 2.847× | Pass |
| MQTT 3.1.1 WS single | 0.896× | 1.169× | 1.111× | 2.794× | Pass |
| MQTT 3.1.1 TCP single control | 0.961× | 1.064× | 1.068× | 2.024× | Pass |
| MQTT 5 WSS batch 64 | 3.918× | 0.297× | 0.408× | 0.423× | Pass |
| MQTT 5 WSS single correctness smoke | 2.864× | 0.382× | 0.349× | 1.000× | Pass |

The raw and summary files for [WS 5](mqtt-native-ws-frame-batch-29fb8e0c-ws5-raw.jsonl), [WS 3.1.1](mqtt-native-ws-frame-batch-29fb8e0c-ws311-raw.jsonl), [TCP 3.1.1](mqtt-native-ws-frame-batch-29fb8e0c-tcp311-raw.jsonl), [WSS 5 batch](mqtt-native-ws-frame-batch-29fb8e0c-wss5batch-raw.jsonl) and [WSS 5 smoke](mqtt-native-ws-frame-batch-29fb8e0c-wss5smoke-raw.jsonl) are retained beside this record. Summaries: [WS 5](mqtt-native-ws-frame-batch-29fb8e0c-ws5-summary.json), [WS 3.1.1](mqtt-native-ws-frame-batch-29fb8e0c-ws311-summary.json), [TCP 3.1.1](mqtt-native-ws-frame-batch-29fb8e0c-tcp311-summary.json), [WSS 5 batch](mqtt-native-ws-frame-batch-29fb8e0c-wss5batch-summary.json), and [WSS 5 smoke](mqtt-native-ws-frame-batch-29fb8e0c-wss5smoke-summary.json).

The preceding clean-source WS 5/3.1.1 throughput ratios were 0.871/0.891; these results are 0.867/0.896. Both router and Mosquitto absolute throughput also declined slightly between the two runs. The dirty-tree diagnostic increase to 0.922/0.916 is therefore **not reproduced** as a clean-source throughput gain. The bounded chunk reduction is established by a fail-first Rust test, and all unchanged local budgets pass, but neither proves a throughput improvement. Require hosted Linux evidence and controlled repeatability before closing the performance issue or accepting a release margin. The direct Mosquitto WSS MQTT 3.1.1 reference interaction remains unresolved and has no accepted numeric gate.
