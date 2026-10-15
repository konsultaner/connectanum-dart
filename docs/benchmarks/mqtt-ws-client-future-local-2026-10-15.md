# MQTT WebSocket client Future trial — 2026-10-15

The MQTT client previously created an `async` result for every QoS 0 WebSocket publication, although WebSocket sends have no flush to await. This candidate returns one completed Future for queued publications, returns the actual TCP/TLS flush Future at the existing 64 KiB threshold, and converts synchronous encode/send errors into failed Futures. The unchanged benchmark runs five matched Connectanum/Mosquitto pairs of 200,000 MQTT 5 WebSocket QoS 0 publications per variant on Apple M3 Ultra. It alternates the committed `b286419f` control and candidate twice. The [40 raw rows](mqtt-ws-client-future-local-2026-10-15.json) contain 8,000,000 exact deliveries with zero duplicates; each summary retains client binary hashes, CPU/RSS, latency and host provenance.

| Run order | Connectanum delivered/s | Mosquitto delivered/s | Paired throughput ratio | Connectanum client CPU seconds | Broker peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Control 1 | 102,006 | 148,601 | 0.6903 | 2.001 | 30.9 MB |
| Candidate 1 | 111,345 | 157,613 | 0.7157 | 1.836 | 31.3 MB |
| Control 2 | 107,463 | 153,635 | 0.7017 | 1.905 | 30.8 MB |
| Candidate 2 | 115,742 | 152,748 | 0.7546 | 1.771 | 30.9 MB |

The candidate improves absolute local Connectanum throughput by 9.2% and 7.7% in adjacent comparisons while using less client CPU. Both candidate runs pass the unchanged local 0.70 throughput ratio and other latency, broker CPU and 64 MiB broker RSS budgets; the controls fail the aggregate throughput gate. The local result does not establish a Linux release margin. GitHub Actions on this exact source and repeated hosted proof are still required. The independent WAMP↔MQTT translation and memory gate remains open until live gateway paths exist.
