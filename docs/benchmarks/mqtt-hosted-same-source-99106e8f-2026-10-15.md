# Hosted same-source MQTT repeat — `99106e8f`

The [GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38810194530/job/116682021349) passed all 20 unchanged profiles on Ubuntu 24.04, AMD EPYC 9V74, with pinned Mosquitto 2.0.18. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38810194530/artifacts/12009302149) and [checked-in raw rows](mqtt-hosted-same-source-99106e8f-2026-10-15.json) contain 192 matched samples, 29,114,000 exact deliveries and zero duplicates. Independent Paho/Connectanum MQTT 5/3.1.1 exchange passed. The five scoped MQTT Dart sources reach 652/652 executable lines, and the Python benchmark gate reaches 268/268.

| Native profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | Floor | Broker CPU ratio | Peak RSS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| MQTT 5 TCP 128 B | 80,299 | 70,248 | 1.1431 | 0.7500 | 1.227 | 31.0 MB | Pass |
| MQTT 3.1.1 TCP 128 B | 79,767 | 66,463 | 1.2002 | 0.7500 | 1.266 | 35.0 MB | Pass |
| MQTT 5 WS 128 B | 35,404 | 44,727 | 0.7916 | 0.7000 | 1.880 | 23.8 MB | Pass |
| MQTT 3.1.1 WS 128 B | 35,388 | 44,895 | 0.7883 | 0.7000 | 1.885 | 23.8 MB | Pass |
| MQTT 5 TCP 64 KiB | 4,390 | 4,621 | 0.9501 | 0.7500 | 3.143 | 62.8 MB | Pass |
| MQTT 3.1.1 WSS sustained | 109,357 | 21,323 | 5.1286 | 2.0000 | 0.426 | 25.1 MB | Pass |

Every other throughput, p95/p99 latency, broker CPU and RSS budget also passes. The immediately preceding [hosted job on `f39ad37e`](mqtt-hosted-client-future-f39ad37e-2026-10-15.md) has identical production and workflow source: intervening commits changed only documentation. It failed the two native WS throughput floors on EPYC 7763 at 0.6859/0.6783. In the MQTT 5 WS profile, Connectanum rises from 33,941 to 35,404 delivered/s on the EPYC 9V74 (+4.3%), while Mosquitto falls from 49,481 to 44,727 delivered/s (-9.6%); the MQTT 3.1.1 profile moves similarly. This comparison is a cross-host observation, not an isolated code effect. The passing repeat confirms host sensitivity but does not establish a safe margin on the slower ratio host. Keep direct performance issue #127 and the unchanged limits open. WAMP↔MQTT translation and its memory gate #131 remain unimplemented and unmeasured.
