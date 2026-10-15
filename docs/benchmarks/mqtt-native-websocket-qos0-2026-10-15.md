# Native MQTT WebSocket QoS 0 benchmark checkpoint

Date: 2026-10-15. Status: clean-tree local source `a22ab4cf`; hosted Linux evidence pending.

The process-isolated AOT runner uses the same Connectanum client to publish to a native Connectanum router and Mosquitto 2.1.2 on separate loopback ports. Each numeric profile has five order-balanced pairs of 200,000 publications with 128-byte binary payloads and one subscriber. Every row checks exact payload bytes, order, count, and zero duplicates before throughput, p95/p99 publish-to-delivery latency, broker CPU and RSS are compared. The WSS control uses the same checked-in CA and server certificate for both brokers. WebSocket per-message compression is disabled in the client.

| Clean source profile | Connectanum/s | Mosquitto/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Max router RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 WS single, window 512 | 116,552 | 138,462 | 0.842 | 1.402 | 1.197 | 3.504 | 32.8 MiB |
| MQTT 3.1.1 WS single, window 512 | 125,185 | 139,726 | 0.896 | 1.239 | 1.227 | 3.263 | 32.8 MiB |
| MQTT 5 WSS batch 64, window 64 | 272,205 | 67,776 | 4.016 | 0.292 | 0.288 | 0.403 | 30.6 MiB |

The [WS 5](mqtt-native-websocket-a22ab4cf-ws5-summary.json), [WS 3.1.1](mqtt-native-websocket-a22ab4cf-ws311-summary.json), and [WSS 5 batch](mqtt-native-websocket-a22ab4cf-wss5-batch64-summary.json) summaries contain the checked-in numeric budgets and executable/native-library hashes. Their corresponding `-raw.jsonl` files preserve all 30 exact matched rows. Every summary records `git_dirty: false` and source `a22ab4cf`. The WS single broker CPU cost is still 3.3–3.5× Mosquitto; its provisional 5× budget guards against a larger regression while CPU optimization remains open. WSS batching materially reduces framing/FFI overhead and has a stricter numeric budget. These local ratios do not establish a hosted release margin.

The [MQTT 5 WSS single-message smoke](mqtt-native-websocket-a22ab4cf-wss5-smoke-summary.json) passes three matched pairs of 2,000 publications with exact delivery; its [six raw rows](mqtt-native-websocket-a22ab4cf-wss5-smoke-raw.jsonl) are retained. At 20,000 publications the Mosquitto WSS reference disconnects the Dart publisher with `Protocol error` after a few thousand messages. MQTT 3.1.1 WSS stalls even in a 2,000-message single-message smoke and in a 200,000-message batch profile. Independent Paho 2.1.0 MQTT 3.1.1 over WSS delivered 5,000 ordered 128-byte publications to the same Mosquitto listener; this narrows the failure to the Connectanum client/reference interaction under this load, without establishing which side is at fault. The WSS 3.1.1 matched performance gate is not accepted yet. Do not infer WSS 3.1.1 release readiness from the router's Paho interoperability tests.

The focused MQTT VM line gate reaches 642/642 executable lines across five current sources, and the benchmark Python gate reaches 237/237 lines after 41 unit regressions and a live WSS smoke. Full final-source `bin/verify` passes at exit 0. Native Rust and full repository coverage remain separate open requirements. Require hosted CI and a controlled release benchmark before using these budgets to close [#127](https://github.com/konsultaner/connectanum-dart/issues/127).
