#!/usr/bin/env python3
"""Matched local MQTT QoS 0 benchmark and conservative regression gate."""

import argparse
import json
import os
from pathlib import Path
import socket
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUDGET = ROOT / "tool" / "mqtt_benchmark_budget.json"


def compare(rows, budget):
    profile = budget["profile"]
    repeats = budget["repetitions"]
    count = budget["messages_per_run"]
    grouped = {name: [row for row in rows if row["target"] == name]
               for name in ("connectanum", "mosquitto")}
    for name, samples in grouped.items():
        if len(samples) != repeats:
            raise ValueError(f"{name}: expected {repeats} runs, got {len(samples)}")
        for row in samples:
            if (row["profile"] != profile or row["sent"] != count or
                    row["received"] != count or row["duplicates"] != 0):
                raise ValueError(f"{name}: invalid workload or delivery result: {row}")
    def median(name, key):
        return statistics.median(row[key] for row in grouped[name])

    throughput_ratio = (median("connectanum", "throughput_delivered_per_sec") /
                        median("mosquitto", "throughput_delivered_per_sec"))
    p95_ratio = (median("connectanum", "latency_p95_us") /
                 median("mosquitto", "latency_p95_us"))
    p99_ratio = (median("connectanum", "latency_p99_us") /
                 median("mosquitto", "latency_p99_us"))
    result = {
        "profile": profile,
        "runs_per_target": repeats,
        "messages_per_run": count,
        "connectanum_delivered_per_sec_median": median(
            "connectanum", "throughput_delivered_per_sec"),
        "mosquitto_delivered_per_sec_median": median(
            "mosquitto", "throughput_delivered_per_sec"),
        "throughput_ratio": throughput_ratio,
        "p95_ratio": p95_ratio,
        "p99_ratio": p99_ratio,
        "budgets": budget,
    }
    result["passed"] = (
        throughput_ratio >= budget["min_delivered_throughput_ratio_vs_mosquitto"] and
        p95_ratio <= budget["max_p95_latency_ratio_vs_mosquitto"] and
        p99_ratio <= budget["max_p99_latency_ratio_vs_mosquitto"])
    return result


def available_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def wait_for_listener(port, process):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Mosquitto exited before listening")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise TimeoutError("Mosquitto did not listen within five seconds")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--budget", type=Path, default=DEFAULT_BUDGET)
    parser.add_argument("--mosquitto", default="mosquitto")
    args = parser.parse_args()
    budget = json.loads(args.budget.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    port = available_port()
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "mosquitto.conf"
        config.write_text(f"listener {port} 127.0.0.1\nallow_anonymous true\n"
                          "persistence false\nlog_dest none\n")
        broker = subprocess.Popen([args.mosquitto, "-c", str(config)],
                                  stdout=subprocess.DEVNULL,
                                  stderr=subprocess.PIPE, text=True)
        try:
            wait_for_listener(port, broker)
            rows = []
            raw = args.output / "raw.jsonl"
            for repeat in range(1, budget["repetitions"] + 1):
                for target, extra in (("connectanum", []),
                                      ("mosquitto", ["127.0.0.1", str(port)])):
                    env = dict(os.environ,
                               MQTT_BENCH_MESSAGES=str(budget["messages_per_run"]))
                    process = subprocess.run(
                        ["dart", "run", "benchmark/mqtt_qos0.dart", *extra],
                        cwd=ROOT / "packages" / "connectanum_router",
                        env=env, capture_output=True, text=True, timeout=90)
                    if process.returncode:
                        raise RuntimeError(f"{target} run {repeat}: {process.stderr}")
                    row = json.loads(process.stdout.strip().splitlines()[-1])
                    row.update(target=target, run=repeat)
                    rows.append(row)
                    raw.write_text("".join(json.dumps(item, sort_keys=True) + "\n"
                                           for item in rows))
            summary = compare(rows, budget)
            (args.output / "summary.json").write_text(
                json.dumps(summary, indent=2, sort_keys=True) + "\n")
            print(json.dumps(summary, sort_keys=True))
            if not summary["passed"]:
                raise SystemExit("MQTT QoS 0 performance budget failed")
        finally:
            broker.terminate()
            try:
                broker.wait(timeout=5)
            except subprocess.TimeoutExpired:
                broker.kill()
                broker.wait()


if __name__ == "__main__":
    main()
