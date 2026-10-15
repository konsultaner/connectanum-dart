# MQTT client Future TCP regression check — 2026-10-15

The clean `f39ad37e` WebSocket Future candidate also returns the real `Socket.flush()` Future at the existing 64 KiB TCP/TLS threshold. Two unchanged local M3 Ultra native-router profiles check this path against Mosquitto 2.1.2. The [20 raw rows](mqtt-client-future-tcp-clean-2026-10-15.json) contain 2,050,000 exact deliveries and zero duplicates, with source/binary and machine provenance.

| Profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Broker CPU ratio | Peak broker RSS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| MQTT 5 TCP 128 B | 512,640 | 523,363 | 0.9795 | 1.750 | 36.6 MB | Pass |
| MQTT 5 TCP 64 KiB | 10,574 | 10,955 | 0.9652 | 2.188 | 79.7 MB | Pass |

Both pass their unchanged throughput, latency, broker CPU and RSS budgets. The 64 KiB profile's RSS cap is 96 MiB; the 128 B cap is 64 MiB. The result checks for a local TCP regression from the Future change; it does not establish hosted WebSocket margin or WAMP↔MQTT translation performance.
