# Native MQTT WebSocket QoS 0 benchmark checkpoint

Date: 2026-10-15. Status: dirty-tree local candidate; clean-tree and hosted Linux evidence pending.

The process-isolated AOT runner uses the same Connectanum client to publish to a native Connectanum router and Mosquitto 2.1.2 on separate loopback ports. Each numeric profile has five order-balanced pairs of 200,000 publications with 128-byte binary payloads and one subscriber. Every row checks exact payload bytes, order, count, and zero duplicates before throughput, p95/p99 publish-to-delivery latency, broker CPU and RSS are compared. The WSS control uses the same checked-in CA and server certificate for both brokers. WebSocket per-message compression is disabled in the client.

| Candidate profile | Connectanum/s | Mosquitto/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Max router RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 WS single, window 512 | 116,819 | 134,291 | 0.870 | 1.308 | 1.142 | 3.309 | 32.8 MB |
| MQTT 3.1.1 WS single, window 512 | 120,633 | 133,071 | 0.907 | 1.158 | 1.086 | 3.234 | 33.5 MB |
| MQTT 5 WSS batch 64, window 64 | 268,421 | 67,510 | 3.976 | 0.307 | 0.322 | 0.405 | 32.2 MB |

The [WS 5](mqtt-native-websocket-candidate-ws5-summary.json), [WS 3.1.1](mqtt-native-websocket-candidate-ws311-summary.json), and [WSS 5 batch](mqtt-native-websocket-candidate-wss5-batch64-summary.json) summaries include the provisional checked-in numeric budgets and executable/native-library hashes. Their corresponding `-raw.jsonl` files preserve all 30 exact matched rows. These summaries disclose `git_dirty: true`; they establish a local development checkpoint, not a release margin or hosted result. The WS single CPU budget is 5× Mosquitto because the measured native path currently uses about 3.2–3.3×; CPU optimization remains open. WSS batching materially reduces framing/FFI overhead and has its own stricter numeric budget.

MQTT 5 WSS single-message delivery also passes a three-pair, 2,000-publication correctness smoke. At 20,000 publications the Mosquitto WSS reference disconnects the Dart publisher with `Protocol error` after a few thousand messages. MQTT 3.1.1 WSS stalls even in a 2,000-message single-message smoke and in a 200,000-message batch profile. Independent Paho 2.1.0 MQTT 3.1.1 over WSS delivered 5,000 ordered 128-byte publications to the same Mosquitto listener; this narrows the failure to the Connectanum client/reference interaction under this load, without establishing which side is at fault. The WSS 3.1.1 matched performance gate is not accepted yet. Do not infer WSS 3.1.1 release readiness from the router's Paho interoperability tests.

The focused MQTT VM line gate reaches 642/642 executable lines across five current sources, and the benchmark Python gate reaches 237/237 lines after 41 unit regressions and a live WSS smoke. Native Rust and full repository coverage remain separate open requirements. Run clean-tree profiles and hosted CI before using these budgets to close [#127](https://github.com/konsultaner/connectanum-dart/issues/127).
