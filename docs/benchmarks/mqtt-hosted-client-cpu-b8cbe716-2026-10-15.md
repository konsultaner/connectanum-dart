# GitHub-hosted MQTT client CPU diagnostic on `b8cbe716` — 2026-10-15

The [GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38764776341/job/116525787391) completed Paho/Connectanum interoperability and all 20 matched broker profiles. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38764776341/artifacts/11990027645), [archived summaries](mqtt-hosted-client-cpu-b8cbe716-2026-10-15-summaries.json), and [192 raw rows](mqtt-hosted-client-cpu-b8cbe716-2026-10-15-raw.jsonl) preserve the Linux measurements. MQTT production code is unchanged from `4bbff885` on this head.

All 192 rows delivered exact bytes and counts without duplicates and include finite, nonnegative `client_cpu_seconds`. Scoped MQTT Dart coverage is 642/642 executable lines; the Python gate is 268/268. Sixteen of 20 profiles pass every unchanged budget. Only throughput misses:

| Native 128 B sustained profile | Connectanum/s | Mosquitto/s | Ratio | Floor | Client CPU seconds, C/M | Broker CPU seconds, C/M |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 TCP | 61,430 | 83,232 | 0.7381 | 0.7500 | 3.238 / 2.458 | 4.87 / 2.28 |
| MQTT 3.1.1 TCP | 61,054 | 82,230 | 0.7425 | 0.7500 | 3.272 / 2.512 | 4.94 / 2.34 |
| MQTT 5 WS | 33,028 | 49,216 | 0.6711 | 0.7000 | 6.006 / 4.139 | 8.99 / 3.74 |
| MQTT 3.1.1 WS | 33,509 | 49,608 | 0.6755 | 0.7000 | 5.917 / 4.107 | 8.91 / 3.71 |

All latency, broker CPU and RSS limits pass. The AOT client consumes about one CPU second per wall second on both targets in these sustained profiles. This shows a client-side ceiling in the current combined publisher/subscriber workload, but it does not assign the throughput gap solely to the client: Connectanum also uses more broker CPU, and broker output chunking can affect client work. A separate-process publisher/subscriber diagnostic would help attribute that cost without changing the existing matched gate. The host was AMD EPYC 7763 with four logical CPUs allocated, Ubuntu 24.04 and Mosquitto 2.0.18. The earlier [same-source run](mqtt-hosted-af9fe28f-2026-10-15.md) passed TCP narrowly and failed both WS floors on the same CPU model.

A local Apple M3 Ultra A/B trial removed the completed-future await from WebSocket `publish` and `publishBatch`, while retaining TCP flush and disconnect behavior. Across two five-pair 200,000-message baseline/candidate comparisons, Connectanum WS throughput moved 115,902→131,822 and 126,295→132,456 delivered/s; Mosquitto moved 144,132→152,171 and 143,890→150,702. Ratios moved 0.804→0.866 and 0.878→0.879. The [40 exact raw local rows](mqtt-client-ws-await-local-2026-10-15-raw.jsonl) preserve both comparisons. This is a measured client-path improvement, not evidence that the Linux broker gate is fixed. Keep [#127](https://github.com/konsultaner/connectanum-dart/issues/127), draft PR #128 and milestone #2 open with budgets unchanged.
