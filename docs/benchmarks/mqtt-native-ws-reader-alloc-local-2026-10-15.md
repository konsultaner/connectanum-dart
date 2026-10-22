# Native MQTT WebSocket reader allocation trial — 2026-10-15

The `f39ad37e` production source was compared with a native-only candidate that avoided allocating `vec![bytes]` for each complete, single-frame MQTT WebSocket message. The control and candidate were built as normal Rust release libraries with distinct SHA-256 hashes; the Dart client and broker source was unchanged. On Apple M3 Ultra, three sequential five-pair MQTT 5 WebSocket runs used the unchanged `tool/mqtt_native_ws_sustained_benchmark_budget.json`. [All 30 raw rows](mqtt-native-ws-reader-alloc-local-2026-10-15.json) contain 6,000,000 exact deliveries and zero duplicates.

| Order | Native library | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Local gate |
| --- | --- | ---: | ---: | ---: | --- |
| Control 1 | `049a549b` | 106,370 | 138,963 | 0.7655 | Pass |
| Candidate | `14e533fa` | 103,895 | 143,356 | 0.7247 | Pass |
| Control 2 | `049a549b` | 105,028 | 136,273 | 0.7707 | Pass |

All eight focused native WebSocket reader regressions and `bin/test-fast` passed with the candidate. The candidate's lower absolute Connectanum throughput and ratio between two stronger controls do not support a performance improvement. The code change was reverted; direct MQTT issue #127 and its unchanged hosted WS floor remain open. This local trial is not a cross-host release measurement.
