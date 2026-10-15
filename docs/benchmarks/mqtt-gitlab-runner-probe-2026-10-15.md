# GitLab MQTT benchmark runner probe — 2026-10-15

The [GitLab pipeline 9953](https://git.konsultaner.de/connectanum/connectanum-dart/-/pipelines/9953) ran the existing native MQTT benchmark gate twice on the same Linux runner. Its [benchmark job 24828](https://git.konsultaner.de/connectanum/connectanum-dart/-/jobs/24828) failed the unchanged budgets and uploaded all [raw and summary artifacts](https://git.konsultaner.de/connectanum/connectanum-dart/-/jobs/24828/artifacts/browse/out/mqtt-gitlab/). This is diagnostic evidence, not a replacement for the GitHub Actions release gate.

The [ten complete summaries](mqtt-gitlab-runner-probe-2026-10-15-summaries.json) and [100 raw matched rows](mqtt-gitlab-runner-probe-2026-10-15-raw.jsonl) are checked in so this record remains usable after the GitLab artifact expires. Each archived row includes its repeat and profile name beside the original benchmark row.

## Environment and scope

- GitLab instance runner #6 (`linux-x64`), Docker executor, AMD Ryzen Threadripper PRO 5975WX, x86_64, cgroup CPU set `0-1` and two available logical CPUs. It is shared with other projects. The job asserted runner ID, CPU model, and CPU set before sampling. The runner job history shows no other GitLab job on #6 from 13:12:46 to 13:22:48 UTC; workloads outside GitLab are unknown.
- Pinned Ubuntu 24.04 image digest `sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55`, Dart 3.13.1, Rust 1.95.0, and Mosquitto 2.0.18. The diagnostic commit `b7dd651d` differs from MQTT source head `4bbff885` only by `.gitlab-ci.yml`. Broker, client, benchmark code and all budget files are identical.
- Five five-pair native profiles per repeat: MQTT 5/3.1.1 TCP and WebSocket with 128-byte payloads, plus MQTT 5 TCP with 64 KiB payloads. Two full repeats produced 100 matched broker/client rows. All 16.1 million publications were received, with zero duplicates; each raw file has ten rows. Every run records binary hashes, clean Git state, broker CPU/RSS and latency.

## Results

Ratios compare Connectanum with Mosquitto. The columns show repeat 1 / repeat 2. The throughput floor is 0.75 for TCP and 0.70 for WebSocket; all other limits are those in the checked-in profile budgets. Every profile failed at least one budget in both repeats. All broker CPU and RSS limits passed.

| Native profile | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio |
| --- | ---: | ---: | ---: | ---: |
| MQTT 5 TCP, 128 B | 0.700 / 0.847 | 2.295 / 1.373 | 2.758 / 2.828 | 1.718 / 1.234 |
| MQTT 3.1.1 TCP, 128 B | 0.74995 / 0.692 | 2.114 / 2.150 | 2.777 / 2.663 | 1.480 / 1.711 |
| MQTT 5 WS, 128 B | 0.594 / 0.601 | 2.397 / 2.050 | 3.382 / 2.618 | 2.159 / 2.126 |
| MQTT 3.1.1 WS, 128 B | 0.618 / 0.649 | 2.034 / 2.166 | 2.402 / 2.624 | 2.044 / 1.857 |
| MQTT 5 TCP, 64 KiB | 0.607 / 0.601 | 2.069 / 2.234 | 1.905 / 2.091 | 3.560 / 2.806 |

The same-host MQTT 5 TCP throughput ratio changed from 0.700 to 0.847, and the five matched-pair ratios within repeat 2 ranged from 0.534 to 1.137. MQTT 3.1.1 TCP moved from 0.74995 to 0.692. Hardware identity therefore did not remove measurement variation. The shared two-CPU allocation also differs from the GitHub-hosted machines used for the existing budgets, so these red results cannot by themselves isolate a source regression.

Local `bin/test-fast` and the final `bin/verify` retry passed on the identical MQTT source. The first full verification attempt stopped in Dart2Wasm when temporary disk space ran out; cleaning generated Cargo build artifacts recovered space and the full retry passed, including Chrome and Dart2Wasm.

## Decision

Keep GitHub Actions as the primary CI and preserve its unchanged MQTT budgets. The repository currently has zero registered GitHub self-hosted runners. Runner #6 provides a targetable Linux diagnostic host but is not a dedicated, controlled release benchmark runner. Do not promote this GitLab job to a release gate or close [#127](https://github.com/konsultaner/connectanum-dart/issues/127) from this evidence. A dedicated runner with reserved CPUs and a fixed software image, or a measured implementation improvement with repeated hosted proof, is still needed for a reliable release margin.
