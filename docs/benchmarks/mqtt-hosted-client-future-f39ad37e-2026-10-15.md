# Hosted MQTT client Future candidate — `f39ad37e`

The [GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38805388511/job/116665829454) ran the unchanged 20-profile gate on Ubuntu 24.04, AMD EPYC 7763, with pinned Mosquitto 2.0.18. Its [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38805388511/artifacts/12008501758) and [checked-in summaries and raw rows](mqtt-hosted-client-future-f39ad37e-2026-10-15.json) preserve 192 matched rows and 29,114,000 exact deliveries with zero duplicates. Independent Paho/Connectanum MQTT 5/3.1.1 exchange passed. Scoped MQTT Dart coverage is 652/652 executable lines and the Python benchmark gate is 268/268.

| Native profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Floor | Broker CPU ratio | Peak RSS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| MQTT 5 TCP 128 B | 75,213 | 80,407 | 0.9354 | 0.7500 | 1.733 | 36.4 MB | Pass |
| MQTT 3.1.1 TCP 128 B | 75,071 | 81,458 | 0.9216 | 0.7500 | 1.894 | 36.5 MB | Pass |
| MQTT 5 WS 128 B | 33,941 | 49,481 | 0.6859 | 0.7000 | 2.410 | 23.3 MB | Fail |
| MQTT 3.1.1 WS 128 B | 34,005 | 50,133 | 0.6783 | 0.7000 | 2.385 | 23.7 MB | Fail |
| MQTT 5 TCP 64 KiB | 4,162 | 4,727 | 0.8803 | 0.7500 | 3.682 | 58.7 MB | Pass |
| MQTT 3.1.1 WSS sustained | 107,511 | 16,912 | 6.3569 | 2.0000 | 0.428 | 25.2 MB | Pass |

Only the two native WS 128 B throughput floors fail; all other 18 profiles and every p95/p99 latency, broker CPU and RSS limit pass. On the preceding [`b286419f` hosted job](mqtt-hosted-client-flush-b286419f-2026-10-15.md), the same CPU model and runner image measured WS ratios 0.6815/0.6851. The current source measures 0.6859/0.6783, while Connectanum client CPU falls from 5.956/5.925 to 5.854/5.837 seconds per 200,000 MQTT 5/3.1.1 WS deliveries. That small client CPU gain does not produce a release-margin throughput gain. Distinct hosted machines and run conditions prevent a causal ratio claim from these two runs. No budget changed; keep direct performance issue #127, draft PR #128 and milestone #2 open. A same-production-source hosted repeat should check run-to-run variance. WAMP↔MQTT gateway and translation memory gate #131 remain unimplemented.
