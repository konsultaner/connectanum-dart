# Native WebSocket source-control benchmark — 2026-10-15

A five-pair MQTT 5 WebSocket 128 B sustained benchmark on the local Apple M3 Ultra compared the new native regression/coverage patch with the native library rebuilt from unchanged head `44a59855`. Both used the same current Dart benchmark/client source, normal-release Rust profile, Mosquitto 2.1.2, 200,000 publications per broker in each pair, and the unchanged 0.70 throughput floor. [All three summaries and 30 raw rows](mqtt-native-coverage-local-ab-2026-10-15.json) retain source and executable hashes. Every row delivered exact bytes and counts with zero duplicates.

| Native library | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Broker CPU seconds |
| --- | ---: | ---: | ---: | ---: |
| Current patch, first run | 108,779 | 156,301 | 0.6960 | 3.73 |
| `44a59855` control | 105,930 | 157,953 | 0.6706 | 3.82 |
| Current patch, repeat | 108,037 | 164,475 | 0.6569 | 3.77 |

All three local runs miss the 0.70 throughput floor. The current patch did not produce an observed absolute throughput regression against the immediately adjacent control, but the varying reference throughput makes a ratio improvement claim unsupported. Earlier local runs on this Mac were faster; this A/B does not explain the host change. The GitHub Actions EPYC 7763 result remains the release decision, and no budget was changed.
