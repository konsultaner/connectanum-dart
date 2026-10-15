# Same-version MQTT wire forwarding trial — 2026-10-15

A Dart broker candidate forwarded `MqttFrame.encode()` after validating a property-free QoS 0 PUBLISH when publisher and subscriber used the same MQTT version. Mixed-version subscribers still used `encodePublish`. Existing native and cross-version integration passed when run from the router package root. The adjacent control was the prior broker source; the native release library, MQTT clients, Mosquitto 2.1.2 and unchanged 200,000-publication five-pair budgets were held fixed on Apple M3 Ultra. [All 60 raw rows](mqtt-same-version-wire-forward-local-2026-10-15.json) contain 12,000,000 exact deliveries and zero duplicates.

| Version and order | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Local gate |
| --- | ---: | ---: | ---: | --- |
| MQTT 5 candidate 1 | 115,396 | 151,026 | 0.7641 | Pass |
| MQTT 5 control | 101,092 | 147,709 | 0.6844 | Fail |
| MQTT 5 candidate 2 | 104,769 | 147,995 | 0.7079 | Pass |
| MQTT 3.1.1 candidate 1 | 135,982 | 153,363 | 0.8867 | Pass |
| MQTT 3.1.1 control | 136,019 | 153,947 | 0.8835 | Pass |
| MQTT 3.1.1 candidate 2 | 119,394 | 152,419 | 0.7833 | Pass |

The MQTT 5 candidate clears the local floor twice, but the second result is only 0.0079 above it. The MQTT 3.1.1 candidate has no repeatable advantage over its adjacent control and regresses in the second run. This experiment does not establish a reliable cross-version or cross-host performance gain, so the code was reverted. Hosted release margin on EPYC 7763 remains open under #127; no budget changed.
