# Hosted bounded MQTT client flush — `b286419f`

[GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38801008933/job/116650643141) ran on Ubuntu 24.04, AMD EPYC 7763, with the pinned Mosquitto 2.0.18 reference. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38801008933/artifacts/12005138473) and [checked-in summaries plus raw rows](mqtt-hosted-client-flush-b286419f-2026-10-15.json) retain all 20 unchanged profiles, 192 matched rows and 29,114,000 exact deliveries with zero duplicates. Paho and Connectanum exchange passed over TCP/TLS/WS/WSS. Scoped MQTT Dart coverage is 649/649 executable lines; the benchmark Python gate is 268/268.

| Native profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Floor | Broker CPU ratio | Peak RSS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| MQTT 5 TCP 128 B | 72,499 | 83,045 | 0.8730 | 0.7500 | 1.829 | 29.7 MB | Pass |
| MQTT 3.1.1 TCP 128 B | 72,855 | 83,740 | 0.8700 | 0.7500 | 1.897 | 35.0 MB | Pass |
| MQTT 5 WS 128 B | 33,339 | 48,918 | 0.6815 | 0.7000 | 2.398 | 24.1 MB | Fail |
| MQTT 3.1.1 WS 128 B | 33,459 | 48,839 | 0.6851 | 0.7000 | 2.376 | 23.7 MB | Fail |
| MQTT 5 TCP 64 KiB | 4,176 | 4,919 | 0.8490 | 0.7500 | 3.905 | 60.7 MB | Pass |
| MQTT 3.1.1 WSS sustained | 104,939 | 17,013 | 6.1680 | 2.0000 | 0.433 | 25.0 MB | Pass |

The only two failures are the native WS 128 B throughput floors. All other 18 profiles pass, including every p95/p99 latency, broker CPU and RSS budget. The bounded 64 KiB TCP/TLS client flush candidate has a clear local matched gain and passes both native TCP 128 B floors on this hosted EPYC 7763 run; earlier source on the same CPU model missed them, though GitHub-hosted machine variation prevents a single-run causal claim. The WS absolute rates remain near 33,000 delivered/s and need a separate improvement or controlled release runner. No budget was changed. Direct MQTT performance issue #127, draft PR #128 and milestone #2 remain open; WAMP↔MQTT gateway and translation memory gate #131 are still unimplemented.
