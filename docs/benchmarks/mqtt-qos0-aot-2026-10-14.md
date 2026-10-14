# MQTT QoS 0 AOT broker benchmark

Status: provisional performance gate for the standalone TCP QoS 0 broker. The MQTT milestone and release performance matrix remain open.

## Method

`tool/run_mqtt_benchmark_gate.py` compiles the Connectanum broker and the identical Connectanum benchmark client to AOT executables. It starts the Connectanum and Mosquitto brokers as separate, long-lived processes. Five paired client runs target each broker on loopback, reversing broker order on even pairs. This isolates broker CPU/RSS from the client and avoids charging Dart JIT compilation to one broker. The artifact records the Git commit and dirty state, executable hashes, runtime versions, OS, architecture and logical CPU count.

Each run uses MQTT 5, a single publisher and subscriber, one exact topic and 128-byte binary payloads. The client waits for 100 warmup deliveries. It then verifies every measured publication's topic, length, full payload pattern and ordered distinct ID, and fails on missing or duplicate deliveries. Throughput counts delivered messages only. Latency is measured from each client publish attempt to the subscriber callback in the same client process. The TCP stack, scheduler and client callback are included; this is an end-to-end path measurement, not broker-only latency.

The order assertion uses a non-shared subscription on one topic, which [MQTT 5 §4.6](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) treats as ordered by default.

The short burst profile sends 2,000 messages. The sustained profile sends 200,000 messages in windows of 512 and waits for each window to arrive before offering more. This prevents an uncontrolled QoS 0 output queue from turning a saturation/loss experiment into a false zero-loss throughput comparison. A separate overload profile is still required.

Broker CPU seconds are cumulative process CPU deltas across each client run, including connection setup, warmup and a 20 ms duplicate-observation period. On Linux they come from `/proc/<pid>/stat`; on macOS from `ps`. Hosted Linux broker RSS uses `/proc/<pid>/status` `VmHWM`, the process high-water mark; local macOS RSS uses the greater of snapshots immediately before and after a run. The artifact names which method was used. The short burst can be too brief to resolve CPU accurately, so the CPU gate applies only to the sustained profile. A later fixed-duration profile must separate setup and steady-state broker CPU.

## Budgets and evidence

The short [burst profile](../../tool/mqtt_benchmark_budget.json) is an exact-delivery and byte/order correctness smoke check; its throughput and latency ratios remain reported but are too volatile on a hosted runner to be release gates. The [sustained budget](../../tool/mqtt_sustained_benchmark_budget.json) requires at least 0.65× Mosquitto delivered throughput, at most 1.75× p95/p99 latency, at most 3× broker CPU and Connectanum broker RSS at most 64 MiB. These are initial regression tripwires for one profile, not release targets or claims for TLS, WebSocket, fan-out, QoS 1/2 or mixed WAMP traffic.

From the repository root after `bin/bootstrap`, with Mosquitto installed:

```sh
python3 tool/run_mqtt_benchmark_gate.py --output out/mqtt-qos0-gate/burst
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_sustained_benchmark_budget.json --output out/mqtt-qos0-gate/sustained
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_batched_benchmark_budget.json --output out/mqtt-qos0-gate/batched
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

The final platform-default adjustment enables client TCP_NODELAY on Linux, as in this passing hosted job, and keeps the native default on macOS after a measured local sequential regression. Local matched Mac diagnostics with that adjustment reach 404,972 Connectanum delivered/s sequential and 787,842 batched, during broader verification. Final clean-head evidence is still required.

The checked-in burst summary records the relative thresholds that were active at baseline commit `078e85c7`. The later hosted 2,000-message AOT rows varied too widely for a reliable performance decision, so the current burst gate checks correctness only. The baseline artifact remains unchanged for provenance.

## Outstanding measurements

The release matrix needs a pinned machine, longer fixed-duration runs, explicit overload and backpressure outcomes, fan-out, larger payloads, connection churn, secure transports, WAMP bridging and Paho client workloads. Broker RSS needs a steady-state time series, and CPU needs more stable longer-duration samples. No unsupported profile is counted as passing.
