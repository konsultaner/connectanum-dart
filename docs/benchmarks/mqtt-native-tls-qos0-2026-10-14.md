# Native MQTT TLS QoS 0 benchmark checkpoint

Date: 2026-10-14. Status: five-pair local diagnostic passes; clean-tree and hosted evidence pending.

The existing process-isolated MQTT benchmark runner now measures the native TLS listener and a Mosquitto TLS listener with the same AOT Connectanum client, 128-byte binary payload, 200,000 publications per run, one subscriber and a window of 512. Five order-balanced pairs run for each MQTT version. Both clients validate the checked-in test CA; the broker processes use the same server certificate and key. Every run verifies exact payload bytes, order, count and zero duplicates before applying throughput, p95/p99 publish-to-delivery latency, broker CPU and RSS budgets. The certificate and key hashes are part of benchmark provenance. This loopback fixture tests TLS transport and server authentication; MQTT principal authorization is still pending.

The provisional secure budgets match the cleartext native gate: delivered throughput at least 0.75× Mosquitto, p95 at most 2.0×, p99 at most 2.25×, broker CPU at most 2.5× and Connectanum RSS at most 64 MiB. The first local diagnostic used a correctness-only budget before those limits were checked in. The later local numeric runs also pass these limits. [Mosquitto's TLS listener configuration](https://mosquitto.org/man/mosquitto-conf-5.html) uses `certfile` and `keyfile` for the server certificate.

| Dirty-tree Apple M3 Ultra diagnostic | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Connectanum RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 TLS | 388,050 | 76,493 | 5.073 | 0.131 | 0.138 | 0.803 | 32.6 MB |
| MQTT 3.1.1 TLS | 397,104 | 76,214 | 5.210 | 0.123 | 0.122 | 0.730 | 32.4 MB |

These local numbers are diagnostics, not a cross-machine speedup claim. Clean-tree local and hosted Linux evidence, TLS fan-out, mixed MQTT/WAMP traffic, overload/backpressure, and controlled release runs remain open. The Python benchmark gate passes exact 223/223 executable lines after adding TLS controls; five scoped MQTT Dart sources pass 531/531 executable VM lines. Focused native TLS MQTT/HTTPS, Paho and untrusted-certificate tests, `bin/test-fast` and full `bin/verify` pass.
