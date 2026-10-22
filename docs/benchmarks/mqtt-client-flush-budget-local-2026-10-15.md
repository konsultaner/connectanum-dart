# Bounded MQTT client flush trial — 2026-10-15

On the local Apple M3 Ultra, the Connectanum MQTT client previously awaited `Socket.flush()` after every TCP/TLS QoS 0 publication. This trial queues each packet and awaits a TCP/TLS flush after 64 KiB of submitted wire bytes; `publishBatch` and `close` still flush. The benchmark uses the same Dart client against the native Connectanum router and Mosquitto 2.1.2. Every one of the [70 raw rows](mqtt-client-flush-budget-local-2026-10-15.json) has exact bytes and counts, for 12,050,000 deliveries and zero duplicates. All seven local profiles pass their unchanged throughput, p95/p99, broker CPU and RSS budgets.

| Profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 / p99 ratio | Broker CPU ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| TCP 128 B, flush each packet | 410,389 | 454,736 | 0.902 | 1.155 / 1.172 | 2.103 |
| TCP 128 B, no periodic flush | 514,048 | 500,294 | 1.027 | 1.189 / 1.228 | 1.684 |
| TCP 128 B, no periodic flush repeat | 569,178 | 540,374 | 1.053 | 1.181 / 1.319 | 1.743 |
| TCP 128 B, 64 KiB flush cap | 513,242 | 518,613 | 0.990 | 1.246 / 1.282 | 1.757 |
| TLS 128 B, no periodic flush | 522,103 | 77,373 | 6.748 | 0.141 / 0.143 | 0.533 |
| TLS 128 B, 64 KiB flush cap | 523,467 | 76,949 | 6.803 | 0.135 / 0.142 | 0.567 |
| TCP 64 KiB payload, 64 KiB flush cap | 10,369 | 10,707 | 0.968 | 1.032 / 1.034 | 2.188 |

The bounded candidate improves absolute local Connectanum TCP 128 B throughput by about 25% against the immediately preceding per-packet-flush control while retaining periodic backpressure. The measured ratio also improves locally, but these runs do not establish a Linux release margin. The raw rows show client high-water RSS of 31.1 MiB for the bounded candidate versus 30.7 MiB for the per-packet-flush control; broker peak RSS is 35.6 versus 32.7 MiB, both below the unchanged 64 MiB cap. The client API now documents that QoS 0 `publish` completion means queued, with periodic flushing; `close` drains queued data. A live regression sends more than the flush threshold, mixes single and batch publishes, then closes immediately and verifies ordered byte-exact delivery. Hosted GitHub Actions on the candidate is required before changing issue #127's status. WebSocket's native 128 B throughput gate remains a separate open problem.
