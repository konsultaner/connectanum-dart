# Native MQTT WebSocket read-ahead and inbound coalescing

Clean-source macOS arm64 benchmark on `914ac550` against Mosquitto 2.1.2. The native MQTT WebSocket reader buffers 16 KiB of input; the Dart-facing poll coalesces queued chunks up to its existing 64 KiB cap. Five order-balanced matched pairs per numeric profile publish 200,000 messages per broker. Every one of the 46 broker/client raw rows across these five profiles delivers the expected count and bytes in order with zero duplicates. Every summary records `git_dirty: false`, the source commit, native-library hash, AOT executable hashes, budget and toolchain provenance. Local results establish a regression baseline; hosted Linux remains the release gate.

| Profile | Throughput vs Mosquitto | p95 latency | p99 latency | Broker CPU | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| MQTT 5 WS single | 0.871× | 1.238× | 1.219× | 2.874× | Pass |
| MQTT 3.1.1 WS single | 0.891× | 1.236× | 1.113× | 2.844× | Pass |
| MQTT 5 WSS batch 64 | 3.972× | 0.305× | 0.301× | 0.416× | Pass |
| MQTT 3.1.1 TCP single control | 0.967× | 1.052× | 1.083× | 2.024× | Pass |
| MQTT 5 WSS single correctness smoke | 2.845× | 0.384× | 0.373× | 1.000× | Pass |

The first four profiles each have ten [raw WS 5](mqtt-native-ws-optimized-914ac550-ws5-raw.jsonl), [raw WS 3.1.1](mqtt-native-ws-optimized-914ac550-ws311-raw.jsonl), [raw WSS 5 batch](mqtt-native-ws-optimized-914ac550-wss5batch-raw.jsonl), and [raw TCP 3.1.1](mqtt-native-ws-optimized-914ac550-tcp311-raw.jsonl) rows. The WSS single correctness smoke has [six raw rows](mqtt-native-ws-optimized-914ac550-wss5smoke-raw.jsonl) of 2,000 messages per broker. The matching [WS 5](mqtt-native-ws-optimized-914ac550-ws5-summary.json), [WS 3.1.1](mqtt-native-ws-optimized-914ac550-ws311-summary.json), [WSS 5 batch](mqtt-native-ws-optimized-914ac550-wss5batch-summary.json), [TCP 3.1.1](mqtt-native-ws-optimized-914ac550-tcp311-summary.json), and [WSS 5 smoke](mqtt-native-ws-optimized-914ac550-wss5smoke-summary.json) summaries retain all budget comparisons and provenance.

The unchanged WS 5/3.1.1 throughput floor is 0.70× and the TCP 3.1.1 floor is 0.75×. WSS batch requires at least 2.0×. The first hosted WS checkpoint failed three throughput gates despite exact delivery; this local optimization must pass a new hosted run before the performance issue can close. The Mosquitto direct-WSS MQTT 3.1.1 reference interaction remains under investigation, so it has no accepted numeric gate yet.
