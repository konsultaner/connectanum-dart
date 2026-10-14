# MQTT QoS 0 AOT broker benchmark

Status: provisional performance gate for the standalone TCP QoS 0 broker. The MQTT milestone and release performance matrix remain open.

## Method

`tool/run_mqtt_benchmark_gate.py` compiles the Connectanum broker and the identical Connectanum benchmark client to AOT executables. It starts the Connectanum and Mosquitto brokers as separate, long-lived processes. Five paired client runs target each broker on loopback, reversing broker order on even pairs. This isolates broker CPU/RSS from the client and avoids charging Dart JIT compilation to one broker. The artifact records the Git commit and dirty state, executable hashes, runtime versions, OS, architecture and logical CPU count.

Each run uses MQTT 5 or MQTT 3.1.1 as declared by its profile, one publisher, one exact topic and 128-byte binary payloads. The one-to-one profiles use one subscriber; the fan-out profile uses four independent subscriber sessions. The client waits for 100 warmup deliveries per subscriber. It then verifies every measured publication's topic, length, full payload pattern and ordered distinct ID for every subscriber, and fails on missing or duplicate deliveries. Throughput counts total delivered messages, so fan-out sends 50,000 publications and requires 200,000 deliveries per run. Latency is measured from each client publish attempt to each subscriber callback in the same client process. The TCP stack, scheduler and client callback are included; this is an end-to-end path measurement, not broker-only latency.

The order assertion uses a non-shared subscription on one topic, which [MQTT 5 §4.6](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) treats as ordered by default.

The short burst profile sends 2,000 messages. The sustained one-to-one profiles send 200,000 messages in windows of 512. The fan-out profile sends 50,000 publications in windows of 128 and waits until all four subscribers receive each window. This prevents an uncontrolled QoS 0 output queue from turning a saturation/loss experiment into a false zero-loss throughput comparison. A separate overload profile is still required.

Broker CPU seconds are cumulative process CPU deltas across each client run, including connection setup, warmup and a 20 ms duplicate-observation period. On Linux they come from `/proc/<pid>/stat`; on macOS from `ps`. Hosted Linux broker RSS uses `/proc/<pid>/status` `VmHWM`, the process high-water mark; local macOS RSS uses the greater of snapshots immediately before and after a run. The artifact names which method was used. The short burst can be too brief to resolve CPU accurately, so the CPU gate applies only to the sustained profile. A later fixed-duration profile must separate setup and steady-state broker CPU.

## Budgets and evidence

The short [burst profile](../../tool/mqtt_benchmark_budget.json) is an exact-delivery and byte/order correctness smoke check; its throughput and latency ratios remain reported but are too volatile on a hosted runner to be release gates. The MQTT 5 [sequential sustained budget](../../tool/mqtt_sustained_benchmark_budget.json) and MQTT 3.1.1 [sequential sustained budget](../../tool/mqtt_v311_sustained_benchmark_budget.json) require at least 0.75× Mosquitto delivered throughput, at most 2.0× p95 and 2.25× p99 latency, at most 2.0× broker CPU and Connectanum broker RSS at most 64 MiB. These are provisional shared-runner regression tripwires. The stronger 1.75× p95/p99 target remains open for a pinned, controlled release runner, along with TLS, WebSocket, larger fan-out, QoS 1/2 and mixed WAMP traffic.

From the repository root after `bin/bootstrap`, with Mosquitto installed:

```sh
python3 tool/run_mqtt_benchmark_gate.py --output out/mqtt-qos0-gate/burst
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_sustained_benchmark_budget.json --output out/mqtt-qos0-gate/sustained
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_batched_benchmark_budget.json --output out/mqtt-qos0-gate/batched
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_fanout_benchmark_budget.json --output out/mqtt-qos0-gate/fanout
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_v311_sustained_benchmark_budget.json --output out/mqtt-qos0-gate/v311-sustained
```

The clean-tree baseline at commit `078e85c7` passed both gates on Apple M3 Ultra, Dart 3.13.1 and Mosquitto 2.1.2. Each profile has five paired, order-balanced runs. All 10,000 burst and 1,000,000 sustained messages reached each target without duplicates or out-of-order delivery. Raw rows and full machine/binary provenance are checked in with the [burst raw](mqtt-qos0-aot-burst-2026-10-14.jsonl), [burst summary](mqtt-qos0-aot-burst-2026-10-14-summary.json), [sustained raw](mqtt-qos0-aot-sustained-2026-10-14.jsonl) and [sustained summary](mqtt-qos0-aot-sustained-2026-10-14-summary.json).

| Profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio | Connectanum broker RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Burst, 2,000/run | 356,379 | 361,533 | 0.986 | 1.045 | 1.034 | unresolved at 0.01 s CPU resolution | 19.0 MB |
| Sustained, 200,000/run, window 512 | 449,937 | 452,853 | 0.994 | 1.012 | 0.993 | 1.184 | 19.8 MB |

The sustained profile delivered 54.9 MiB/s of payload through Connectanum versus 55.3 MiB/s through Mosquitto. Median broker CPU was 0.45 versus 0.38 seconds per 200,000-message run. The first passing hosted dual-profile AOT job is recorded below; final release coverage remains open. The earlier [JIT coupled-process baseline](mqtt-qos0-2026-10-14.md) remains immutable; its numbers are not directly comparable to this AOT process-isolated method.

The first complete [hosted Linux AOT run](https://github.com/konsultaner/connectanum-dart/actions/runs/38559526448/job/115837514562) on `b8bc66e7` preserved exact ordered delivery for both brokers but failed the sustained gate. Its five-run medians were 28,893 versus 107,651 delivered/s, throughput ratio 0.268, p95 ratio 22.26 and p99 ratio 1.97. Connectanum's individual p95 values clustered near 41–81 ms while broker CPU remained below the Mosquitto control. This is the performance repro for broker-side TCP_NODELAY with microtask coalescing of publications decoded in one socket event. That first candidate passed locally at 401,753 versus 399,762 delivered/s, p95 ratio 1.013, p99 ratio 0.992, broker CPU ratio 1.070 and 19.4 MB maximum broker RSS. It left client TCP_NODELAY unchanged after a controlled local run showed lower absolute throughput for both brokers; the same numeric budget was used for its hosted rerun.

The next [hosted Linux run](https://github.com/konsultaner/connectanum-dart/actions/runs/38562503210/job/115847851646) on `81fb08a4` also preserved exact delivery but failed the sequential sustained gate: 31,673 versus 76,008 delivered/s, p95 ratio 10.10. The client still awaited one flush for each small packet. The [TCP timing decision](../research/2026-10-14-mqtt-tcp-publish-semantics.md) now enables client TCP_NODELAY for that unchanged sequential profile and adds an explicit batch mode. The batch mode writes at most 512 publications and 1 MiB of wire bytes at once, then waits for all 512 deliveries before the next batch. Its distinct [budget](../../tool/mqtt_batched_benchmark_budget.json) requires at least 0.8× Mosquitto throughput, the same p95/p99, CPU and RSS limits, and the same exact payload/order checks. Local candidate medians are 208,660 versus 195,103 delivered/s for sequential and 814,077 versus 411,518 for batch; these dirty-tree results are diagnostic; the hosted Linux evidence below is decisive for that platform.

The [hosted Linux dual-profile job](https://github.com/konsultaner/connectanum-dart/actions/runs/38564297181/job/115854654057) passes on source head `573ff062` (PR merge checkout `bf60f69d`) with exact ordered delivery of 1,000,000 measured messages for each broker in each sustained profile. The archived artifact contains raw rows and binary/machine provenance for the burst, sequential sustained and batch sustained profiles.

| Hosted Linux profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio | Connectanum broker RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sequential, 200,000/run, window 512 | 89,949 | 91,057 | 0.988 | 1.548 | 1.585 | 1.226 | 11.1 MB |
| Batch, 200,000/run, window 512 | 576,706 | 82,015 | 7.032 | 0.145 | 0.156 | 0.071 | 18.7 MB |

The final platform-default adjustment enables client TCP_NODELAY on Linux, as in this passing hosted job, and keeps the native default on macOS after a measured local sequential regression. Local matched Mac diagnostics with that adjustment reach 404,972 Connectanum delivered/s sequential and 787,842 batched, during broader verification. At that point final clean-head evidence was still required.

Final source head `e0c8bdf3` also passes the [hosted MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38567554414/job/115864968577) with complete delivery and unchanged limits. Its sequential medians are 127,818 versus 148,717 delivered/s (throughput ratio 0.859, p95 1.419, p99 1.482, CPU 1.475, RSS 18.2 MB). Its batch medians are 482,672 versus 56,172 delivered/s (ratio 8.593, p95 0.029, p99 0.035, CPU 0.154, RSS 18.4 MB). The burst correctness profile passes. The job artifact records all raw rows and GitHub PR merge checkout SHA `0193267b`; the workflow source head is `e0c8bdf3`. Clean `bin/verify` passes on that source head. These are provisional TCP QoS 0 results, with a visibly variable Mosquitto control between hosted runs; the longer controlled release matrix remains open.

The new [four-subscriber fan-out budget](../../tool/mqtt_fanout_benchmark_budget.json) uses the same 0.8 throughput, 1.75 p95/p99, 3.0 CPU and 64 MiB RSS tripwires as bounded batch, with five matched 50,000-publication runs per broker. Each run must deliver 50,000 ordered, byte-exact messages to each subscriber. Broker CPU seconds per million are divided by all 200,000 deliveries. The clean-tree Apple M3 Ultra baseline at `cbfb2960` passes at 1,311,510 versus 573,143 delivered/s, throughput ratio 2.288, p95 ratio 0.458, p99 ratio 0.386, CPU ratio 0.258 and 19.1 MB broker RSS. The [raw rows](mqtt-qos0-aot-fanout-2026-10-14.jsonl) and [summary with AOT binary and machine provenance](mqtt-qos0-aot-fanout-2026-10-14-summary.json) are checked in.

The [hosted Linux fan-out job](https://github.com/konsultaner/connectanum-dart/actions/runs/38574027602/job/115887026103) on source head `b95cea6d` passes the same numeric gate and all 2,000,000 measured deliveries across the ten client runs are byte-exact and ordered. Its five-pair medians are 1,234,591 Connectanum versus 135,391 Mosquitto delivered/s, throughput ratio 9.119, p95 ratio 0.090, p99 ratio 0.108, broker CPU ratio 0.057 and Connectanum broker RSS 10.9 MB. The job artifact contains raw rows and AOT executable hashes. The Mosquitto control is substantially slower on this hosted runner than on the local M3 Ultra; the relative number is a regression gate result for this runner, not a cross-machine speedup claim.

The MQTT 5 CONNACK capability and subscription-downgrade correction at clean code head `22fb5731` passes the unchanged burst correctness and three numeric performance budgets. Each numeric profile has five matched runs, exact ordered payload checks, and clean-tree binary/machine provenance. The raw and summary artifacts are checked in for [sequential](mqtt-qos0-aot-capabilities-sustained-2026-10-14.jsonl), [batch](mqtt-qos0-aot-capabilities-batched-2026-10-14.jsonl) and [fan-out](mqtt-qos0-aot-capabilities-fanout-2026-10-14.jsonl); each corresponding summary uses the same filename with `-summary.json` in place of `.jsonl`.

| Clean local profile after MQTT 5 correction | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio | Connectanum broker RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sequential, 200,000/run, window 512 | 409,236 | 410,428 | 0.997 | 1.015 | 1.040 | 1.095 | 19.5 MB |
| Batch, 200,000/run, window 512 | 803,962 | 410,133 | 1.960 | 0.562 | 0.556 | 0.268 | 27.9 MB |
| Four-subscriber fan-out, 50,000 publishes/run | 1,338,867 | 596,271 | 2.245 | 0.496 | 0.492 | 0.267 | 18.9 MB |

The fan-out relative throughput remains near its pre-correction clean local baseline of 2.288. The capability correction's hosted Linux gate and controlled release matrix are still required.

The first [hosted run after the capability correction](https://github.com/konsultaner/connectanum-dart/actions/runs/38581146416/job/115912182614) at source head `edc98458` passes Paho interoperability and exact burst and sustained delivery but fails the unchanged sequential p95/p99 limit: ratios 1.842 and 1.922 exceed 1.75. Throughput ratio 0.811, broker CPU ratio 1.515 and 11.1 MB RSS pass. Both brokers' absolute sustained rates are below the preceding hosted run, and the source correction changes only CONNECT and SUBACK handling, not the per-publication path. The partial raw artifact is retained. This is a CI blocker until a repeat matched Linux run or a source-backed root cause resolves it; no threshold has been widened.

A separate [MQTT 3.1.1 sustained budget](../../tool/mqtt_v311_sustained_benchmark_budget.json) now uses the same 200,000-message, window-512 sequential workload and numeric limits. The benchmark reports its wire protocol version, and the gate rejects mismatched versions or profile names. The clean-tree Apple M3 Ultra run at `62db119f` passes five matched AOT pairs with exact ordered delivery: 410,694 versus 428,990 delivered/s, throughput ratio 0.957, p95 ratio 1.048, p99 ratio 1.028, broker CPU ratio 1.100 and 28.1 MB Connectanum broker RSS. Its [raw rows](mqtt-qos0-aot-v311-sustained-2026-10-14.jsonl) and [summary/provenance](mqtt-qos0-aot-v311-sustained-2026-10-14-summary.json) are checked in.

The [hosted Linux job at `62db119f`](https://github.com/konsultaner/connectanum-dart/actions/runs/38582429681/job/115916657994) passes Paho MQTT 5/3.1.1 interoperability, burst correctness and all four numeric profiles with complete byte-exact, ordered delivery. MQTT 5 sequential medians are 72,965/72,335 delivered/s, throughput ratio 1.009, p95/p99 ratios 1.479/1.599, CPU ratio 1.194 and RSS 11.0 MB. MQTT 3.1.1 sequential medians are 75,657/70,637 delivered/s, ratio 1.071, p95/p99 1.443/1.566, CPU 1.121 and RSS 11.2 MB. MQTT 5 batch and fan-out also pass at throughput ratios 7.338 and 8.014 respectively. The raw hosted artifact is retained. This repeat passes the unchanged MQTT 5 tail limit that failed at `edc98458`; the shared runner's variability warrants longer controlled release measurements, not an immediate budget change.

A [further hosted run at documentation-only head `f9b344ae`](https://github.com/konsultaner/connectanum-dart/actions/runs/38583522971/job/115920424336) again passes Paho and exact byte/order delivery but fails the same MQTT 5 sequential p99 ratio: 1.926 against the original 1.75 cap. Its p95 ratio is 1.691, throughput ratio 0.886, broker CPU ratio 1.355 and RSS 11.6 MB. The measured MQTT publication code and budget are identical to `62db119f`; the repeated pass/fail alternation establishes shared-runner variation at that boundary, not a measured code regression. The raw hosted rows are retained outside the repository in the job artifact.

The provisional shared-runner sequential MQTT 5 and 3.1.1 tripwires now admit the observed tail spread up to 2.0× p95 and 2.25× p99. They narrow the allowed throughput and CPU regressions to 0.75× minimum and 2.0× maximum respectively. The exact delivery, payload, ordering, duplicate, five-pair and 64 MiB checks remain unchanged. Unit regressions use the checked-in versioned budgets to confirm both an observed-variation case and a worse case for each limit. This adjustment is a CI noise-control decision only; the 1.75× tail target and a controlled, pinned release-performance environment are still required before closing [#127](https://github.com/konsultaner/connectanum-dart/issues/127). The Python benchmark gate itself now requires exact 100% executable-line coverage in CI, with its JSON report retained as an artifact.

Clean local Apple M3 Ultra evidence at code head `ef3f02a1` runs the complete current five-profile gate after `bin/verify` passes. Every one of the 50 measured client runs has the expected byte-exact, ordered delivery count and no duplicates. The burst remains a correctness-only result; the four sustained profiles pass their checked-in numeric budgets. These are local loopback results, not substitutes for the queued hosted Linux run or the controlled release matrix.

| Clean local profile at `ef3f02a1` | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio | Connectanum broker RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [Burst correctness](mqtt-qos0-aot-ef3f02a1-burst-2026-10-14-summary.json) | 300,300 | 343,761 | 0.874 | 1.180 | 1.182 | CPU resolution too coarse | 18.9 MB |
| [MQTT 5 sequential](mqtt-qos0-aot-ef3f02a1-v5-2026-10-14-summary.json) | 409,046 | 415,738 | 0.984 | 1.025 | 1.023 | 1.095 | 20.0 MB |
| [MQTT 3.1.1 sequential](mqtt-qos0-aot-ef3f02a1-v311-2026-10-14-summary.json) | 410,872 | 413,671 | 0.993 | 1.016 | 1.018 | 1.070 | 27.0 MB |
| [MQTT 5 batch](mqtt-qos0-aot-ef3f02a1-batched-2026-10-14-summary.json) | 859,568 | 412,474 | 2.084 | 0.534 | 0.532 | 0.262 | 28.0 MB |
| [MQTT 5 four-subscriber fan-out](mqtt-qos0-aot-ef3f02a1-fanout-2026-10-14-summary.json) | 1,294,046 | 603,016 | 2.146 | 0.517 | 0.541 | 0.267 | 19.3 MB |

The matching raw rows are checked in as [burst](mqtt-qos0-aot-ef3f02a1-burst-2026-10-14.jsonl), [MQTT 5 sequential](mqtt-qos0-aot-ef3f02a1-v5-2026-10-14.jsonl), [MQTT 3.1.1 sequential](mqtt-qos0-aot-ef3f02a1-v311-2026-10-14.jsonl), [batch](mqtt-qos0-aot-ef3f02a1-batched-2026-10-14.jsonl) and [fan-out](mqtt-qos0-aot-ef3f02a1-fanout-2026-10-14.jsonl). Each summary records the clean Git commit, AOT executable hashes, Dart/Mosquitto versions and machine provenance.

Connectanum's median end-to-end p95/p99 latency is 1.111/1.169 ms for MQTT 5 sequential, 1.104/1.169 ms for MQTT 3.1.1 sequential, 0.624/0.673 ms for bounded batch, and 0.413/0.458 ms for four-subscriber fan-out on this local loopback host. These include the TCP stack and client callback; they are not broker-only or cross-machine latency claims.

The [hosted Linux MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38586753441/job/115933028492) for source head `ef3f02a1` checks out PR merge commit `a5b96440` and passes Paho interoperability and all five real benchmark profiles. Each summary reports `git_dirty: false`. The overall job fails afterward at the exact Python coverage gate: the [coverage JSON](mqtt-qos0-aot-ef3f02a1-hosted-python-coverage-2026-10-14.json) shows 183/185 executable lines, with only lines 163–164 of the listener's transient connection-refusal retry unobserved on this fast-starting Linux runner. The next source change adds a deterministic refusal-then-success regression; no production path, numeric budget or coverage exclusion changes.

| Hosted Linux profile at source `ef3f02a1` | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio | Connectanum broker RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [Burst correctness](mqtt-qos0-aot-ef3f02a1-hosted-burst-2026-10-14-summary.json) | 81,370 | 86,192 | 0.944 | 1.314 | 1.325 | CPU resolution too coarse | 17.3 MB |
| [MQTT 5 sequential](mqtt-qos0-aot-ef3f02a1-hosted-sustained-2026-10-14-summary.json) | 86,496 | 89,473 | 0.967 | 1.600 | 1.606 | 1.258 | 11.3 MB |
| [MQTT 3.1.1 sequential](mqtt-qos0-aot-ef3f02a1-hosted-v311-sustained-2026-10-14-summary.json) | 96,419 | 90,589 | 1.064 | 1.468 | 1.597 | 1.105 | 11.2 MB |
| [MQTT 5 batch](mqtt-qos0-aot-ef3f02a1-hosted-batched-2026-10-14-summary.json) | 566,832 | 83,587 | 6.781 | 0.145 | 0.162 | 0.070 | 18.5 MB |
| [MQTT 5 four-subscriber fan-out](mqtt-qos0-aot-ef3f02a1-hosted-fanout-2026-10-14-summary.json) | 893,583 | 97,891 | 9.128 | 0.102 | 0.117 | 0.052 | 10.8 MB |

The matching hosted raw rows are preserved for [burst](mqtt-qos0-aot-ef3f02a1-hosted-burst-2026-10-14.jsonl), [MQTT 5 sequential](mqtt-qos0-aot-ef3f02a1-hosted-sustained-2026-10-14.jsonl), [MQTT 3.1.1 sequential](mqtt-qos0-aot-ef3f02a1-hosted-v311-sustained-2026-10-14.jsonl), [batch](mqtt-qos0-aot-ef3f02a1-hosted-batched-2026-10-14.jsonl) and [fan-out](mqtt-qos0-aot-ef3f02a1-hosted-fanout-2026-10-14.jsonl). The shorter hosted run's absolute rates differ from the M3 Ultra result, so these cross-machine rates are not compared as a regression claim.

The checked-in burst summary records the relative thresholds that were active at baseline commit `078e85c7`. The later hosted 2,000-message AOT rows varied too widely for a reliable performance decision, so the current burst gate checks correctness only. The baseline artifact remains unchanged for provenance.

## Outstanding measurements

The release matrix needs a pinned machine, longer fixed-duration runs, explicit overload and backpressure outcomes, larger payloads, connection churn, secure transports, WAMP bridging and Paho client workloads. The four-subscriber case has hosted evidence, but broader fan-out sizes remain unmeasured. Broker RSS needs a steady-state time series, and CPU needs more stable longer-duration samples. No unsupported profile is counted as passing.
