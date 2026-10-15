# GitHub-hosted MQTT client await check on `77d4c1f3` — 2026-10-15

The [GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38771294254/job/116548899402) tested the WebSocket client publish change against the unchanged budgets on AMD EPYC 7763, Ubuntu 24.04, runner image `20261012.334.1` and Mosquitto 2.0.18. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38771294254/artifacts/11994585454), [archived summaries](mqtt-hosted-client-await-77d4c1f3-2026-10-15-summaries.json) and [192 raw rows](mqtt-hosted-client-await-77d4c1f3-2026-10-15-raw.jsonl) retain every profile. This is the same CPU model and runner image as the [preceding diagnostic](mqtt-hosted-client-cpu-b8cbe716-2026-10-15.md).

Paho/Connectanum interoperability passes. All 192 rows deliver exact bytes and counts without duplicates and include finite nonnegative client CPU; scoped MQTT Dart coverage is 642/642 executable lines and the Python gate is 268/268. Sixteen of 20 profiles pass. All latency, broker CPU and RSS limits pass; four native 128 B sustained throughput ratios remain below unchanged floors:

| Profile | Connectanum/s | Mosquitto/s | Ratio | Floor | Prior ratio | Client CPU seconds, C/M |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 TCP | 60,788 | 82,181 | 0.7397 | 0.7500 | 0.7381 | 3.285 / 2.535 |
| MQTT 3.1.1 TCP | 61,094 | 82,747 | 0.7383 | 0.7500 | 0.7425 | 3.246 / 2.519 |
| MQTT 5 WS | 33,684 | 49,553 | 0.6798 | 0.7000 | 0.6711 | 5.895 / 4.110 |
| MQTT 3.1.1 WS | 33,393 | 49,252 | 0.6780 | 0.7000 | 0.6755 | 5.939 / 4.136 |

The client change improves absolute MQTT 5 WS throughput by about 2% on this hosted pair, and local Apple A/B runs show a larger absolute gain. The paired Linux ratio remains short of the 0.7000 floor, and TCP is essentially unchanged. It is a client-path improvement, not a broker gate fix.

A separate local native-reader experiment waited up to 100 microseconds for another WebSocket frame before flushing a pending MQTT chunk. A five-pair 200,000-message comparison delivered all 20 rows exactly but regressed the MQTT 5 WS matched throughput ratio from 0.7546 to 0.6341, while p95 and broker CPU ratios improved. The [raw local rows](mqtt-ws-cross-read-wait-local-2026-10-15-raw.jsonl) retain the result. The experiment was reverted and is absent from `77d4c1f3`; a timer-based cross-read delay is not a viable fix at this setting.

Keep [#127](https://github.com/konsultaner/connectanum-dart/issues/127), draft PR #128 and milestone #2 open. Do not lower throughput floors or present this run as a release margin. WAMP↔MQTT translation throughput and post-drain memory remain a separate live-path gate in [#131](https://github.com/konsultaner/connectanum-dart/issues/131).
