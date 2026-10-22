# MQTT 3.1.1 WebSocket client Future check — 2026-10-15

This clean-source follow-up checks the WebSocket Future candidate from `e78e5843` against the preceding `b286419f` client on Apple M3 Ultra. The unchanged five-pair, 200,000-publication MQTT 3.1.1 WebSocket profile alternates candidate, control, candidate. The [30 raw rows](mqtt-ws311-client-future-local-2026-10-15.json) retain binary hashes and process provenance, with 6,000,000 exact deliveries and zero duplicates.

| Run order | Connectanum delivered/s | Mosquitto delivered/s | Aggregate throughput ratio | Client CPU seconds | Passed |
| --- | ---: | ---: | ---: | ---: | --- |
| Candidate 1 | 108,289 | 162,644 | 0.6658 | 1.886 | No |
| Control | 102,825 | 161,378 | 0.6372 | 1.985 | No |
| Candidate 2 | 105,406 | 164,245 | 0.6418 | 1.939 | No |

Both implementations miss the unchanged 0.70 throughput floor on this local host. Latency, broker CPU and 64 MiB broker RSS limits pass in all three runs. The candidate's absolute Connectanum throughput and client CPU improve in both adjacent comparisons, but the local gain does not establish a stable throughput-ratio margin. The hosted MQTT 5/3.1.1 WebSocket profiles and controlled release-hardware repeat remain required; direct MQTT performance issue #127 stays open.
