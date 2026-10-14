# MQTT QoS 0 AOT broker benchmark

Status: provisional performance gate for the standalone TCP QoS 0 broker. The MQTT milestone and release performance matrix remain open.

## Method

`tool/run_mqtt_benchmark_gate.py` compiles the Connectanum broker and the identical Connectanum benchmark client to AOT executables. It starts the Connectanum and Mosquitto brokers as separate, long-lived processes. Five paired client runs target each broker on loopback, reversing broker order on even pairs. This isolates broker CPU/RSS from the client and avoids charging Dart JIT compilation to one broker. The artifact records the Git commit and dirty state, executable hashes, runtime versions, OS, architecture and logical CPU count.

Each run uses MQTT 5, a single publisher and subscriber, one exact topic and 128-byte binary payloads. The client waits for 100 warmup deliveries. It then verifies every measured publication's topic, length, full payload pattern and ordered distinct ID, and fails on missing or duplicate deliveries. Throughput counts delivered messages only. Latency is measured from each client publish attempt to the subscriber callback in the same client process. The TCP stack, scheduler and client callback are included; this is an end-to-end path measurement, not broker-only latency.

The order assertion uses a non-shared subscription on one topic, which [MQTT 5 §4.6](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) treats as ordered by default.

The short burst profile sends 2,000 messages. The sustained profile sends 200,000 messages in windows of 512 and waits for each window to arrive before offering more. This prevents an uncontrolled QoS 0 output queue from turning a saturation/loss experiment into a false zero-loss throughput comparison. A separate overload profile is still required.

Broker CPU seconds are cumulative process CPU deltas across each client run, including connection setup, warmup and a 20 ms duplicate-observation period. On Linux they come from `/proc/<pid>/stat`; on macOS from `ps`. Hosted Linux broker RSS uses `/proc/<pid>/status` `VmHWM`, the process high-water mark; local macOS RSS uses the greater of snapshots immediately before and after a run. The artifact names which method was used. The short burst can be too brief to resolve CPU accurately, so the CPU gate applies only to the sustained profile. A later fixed-duration profile must separate setup and steady-state broker CPU.

## Budgets and evidence

The short burst retains the conservative relative throughput and p95/p99 budgets in [`mqtt_benchmark_budget.json`](../../tool/mqtt_benchmark_budget.json). The [sustained budget](../../tool/mqtt_sustained_benchmark_budget.json) also requires Connectanum broker CPU at most 3× Mosquitto's and resident memory at most 64 MiB. These are initial regression tripwires for one profile, not release targets or claims for TLS, WebSocket, fan-out, QoS 1/2 or mixed WAMP traffic.

From the repository root after `bin/bootstrap`, with Mosquitto installed:

```sh
python3 tool/run_mqtt_benchmark_gate.py --output out/mqtt-qos0-gate/burst
python3 tool/run_mqtt_benchmark_gate.py --budget tool/mqtt_sustained_benchmark_budget.json --output out/mqtt-qos0-gate/sustained
```

The clean-tree baseline at commit `078e85c7` passed both gates on Apple M3 Ultra, Dart 3.13.1 and Mosquitto 2.1.2. Each profile has five paired, order-balanced runs. All 10,000 burst and 1,000,000 sustained messages reached each target without duplicates or out-of-order delivery. Raw rows and full machine/binary provenance are checked in with the [burst raw](mqtt-qos0-aot-burst-2026-10-14.jsonl), [burst summary](mqtt-qos0-aot-burst-2026-10-14-summary.json), [sustained raw](mqtt-qos0-aot-sustained-2026-10-14.jsonl) and [sustained summary](mqtt-qos0-aot-sustained-2026-10-14-summary.json).

| Profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | Broker CPU ratio | Connectanum broker RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Burst, 2,000/run | 356,379 | 361,533 | 0.986 | 1.045 | 1.034 | unresolved at 0.01 s CPU resolution | 19.0 MB |
| Sustained, 200,000/run, window 512 | 449,937 | 452,853 | 0.994 | 1.012 | 0.993 | 1.184 | 19.8 MB |

The sustained profile delivered 54.9 MiB/s of payload through Connectanum versus 55.3 MiB/s through Mosquitto. Median broker CPU was 0.45 versus 0.38 seconds per 200,000-message run. Hosted AOT artifacts remain pending. The earlier [JIT coupled-process baseline](mqtt-qos0-2026-10-14.md) remains immutable; its numbers are not directly comparable to this AOT process-isolated method.

## Outstanding measurements

The release matrix needs a pinned machine, longer fixed-duration runs, explicit overload and backpressure outcomes, fan-out, larger payloads, connection churn, secure transports, WAMP bridging and Paho client workloads. Broker RSS needs a steady-state time series, and CPU needs more stable longer-duration samples. No unsupported profile is counted as passing.
