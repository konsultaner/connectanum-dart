# GitHub-hosted MQTT repeat on `af9fe28f` — 2026-10-15

The [GitHub Actions MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38755420888/job/116493310987) completed its Paho/Connectanum interoperability step and all 20 matched profiles. It failed the unchanged native MQTT WebSocket throughput floors on AMD EPYC 7763. The [uploaded artifact](https://github.com/konsultaner/connectanum-dart/actions/runs/38755420888/artifacts/11983454529), [archived summaries](mqtt-hosted-af9fe28f-2026-10-15-summaries.json), and [192 aliased raw rows](mqtt-hosted-af9fe28f-2026-10-15-raw.jsonl) retain every sample. This documentation head has the same MQTT production source `4bbff885` as the earlier hosted repeats.

All 192 broker/client rows delivered the expected bytes and counts to every subscriber with zero duplicates. The uploaded coverage reports show 642/642 executable lines across the five scoped MQTT Dart sources and 254/254 Python gate lines. Eighteen of 20 profiles pass every unchanged budget. All latency, broker CPU and RSS limits pass. The two failures are throughput only:

| Native 128 B sustained profile | Connectanum delivered/s | Mosquitto delivered/s | Ratio | Unchanged floor | Broker CPU ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 WS | 32,756 | 49,097 | 0.6672 | 0.7000 | 2.404 |
| MQTT 3.1.1 WS | 32,892 | 49,118 | 0.6696 | 0.7000 | 2.421 |

Native MQTT 5/3.1.1 TCP sustained narrowly pass at 0.7501/0.7511 against 0.7500 floors. Native MQTT 5 TCP 64 KiB passes at 0.8708 throughput and 3.900 broker CPU against its 0.7500/4.0 limits. This is a further same-source EPYC 7763 repeat of the roughly 33,000/s native WS plateau; the earlier EPYC 9V74 green run measured about 45,000/s for Connectanum and 57,000/s for Mosquitto. The differing host results do not establish a release margin.

The next diagnostic candidate adds per-run AOT client-process CPU time to raw rows and per-target medians to summaries, using the serial harness's waited-child accounting. It leaves workload, budget values and verdict logic unchanged. A local Mac native MQTT 5 WS five-pair run with that candidate passed 10 exact rows and its unchanged budget; client CPU medians were 1.7655 seconds against Connectanum and 1.4303 seconds against Mosquitto. The Python gate reached exact 268/268 executable lines with unit tests plus live runs. These Mac figures are diagnostic only. Hosted Linux client-CPU evidence remains pending. Keep [#127](https://github.com/konsultaner/connectanum-dart/issues/127), draft PR #128 and milestone #2 open.
