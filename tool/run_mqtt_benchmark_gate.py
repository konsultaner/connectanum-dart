#!/usr/bin/env python3
"""Matched local MQTT QoS 0 benchmark and conservative regression gate."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import socket
import statistics
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUDGET = ROOT / "tool" / "mqtt_benchmark_budget.json"


def compare(rows, budget):
    profile = budget["profile"]
    publish_mode = budget.get("publish_mode", "single")
    gate = budget["gate"]
    if gate not in ("correctness", "performance"):
        raise ValueError(f"invalid MQTT benchmark gate: {gate}")
    repeats = budget["repetitions"]
    count = budget["messages_per_run"]
    subscribers = budget.get("subscribers", 1)
    if type(subscribers) is not int or subscribers < 1:
        raise ValueError("MQTT benchmark requires at least one subscriber")
    deliveries = count * subscribers
    payload_bytes = budget["payload_bytes"]
    window = budget.get("window_messages", 0)
    if len(rows) != 2 * repeats:
        raise ValueError(f"expected {2 * repeats} matched broker runs, got {len(rows)}")
    grouped = {name: [row for row in rows if row["target"] == name]
               for name in ("connectanum", "mosquitto")}
    for name, samples in grouped.items():
        if len(samples) != repeats:
            raise ValueError(f"{name}: expected {repeats} runs, got {len(samples)}")
        if {row["run"] for row in samples} != set(range(1, repeats + 1)):
            raise ValueError(f"{name}: missing or duplicate run identifiers")
        for row in samples:
            if (row["profile"] != profile or
                    row.get("publish_mode", "single") != publish_mode or
                    row.get("window_messages", 0) != window or
                    row["payload_bytes"] != payload_bytes or
                    row.get("subscribers") != subscribers or
                    row["sent"] != count or
                    row["received"] != deliveries or
                    row.get("received_per_subscriber") != [count] * subscribers or
                    row["duplicates"] != 0):
                raise ValueError(f"{name}: invalid workload or delivery result: {row}")
            cpu = row.get("broker_cpu_seconds", -1)
            rss = row.get("broker_rss_bytes", 0)
            if (not math.isfinite(cpu) or cpu < 0 or
                    not math.isfinite(rss) or rss <= 0):
                raise ValueError(f"{name}: missing broker process metrics: {row}")
            for metric in ("throughput_delivered_per_sec", "latency_p95_us",
                           "latency_p99_us"):
                if not math.isfinite(row[metric]) or row[metric] <= 0:
                    raise ValueError(f"{name}: invalid {metric}: {row[metric]}")
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
        "publish_mode": publish_mode,
        "gate": gate,
        "runs_per_target": repeats,
        "messages_per_run": count,
        "subscribers": subscribers,
        "deliveries_per_run": deliveries,
        "connectanum_delivered_per_sec_median": median(
            "connectanum", "throughput_delivered_per_sec"),
        "mosquitto_delivered_per_sec_median": median(
            "mosquitto", "throughput_delivered_per_sec"),
        "connectanum_payload_mib_per_sec_median": (
            median("connectanum", "throughput_delivered_per_sec") *
            payload_bytes / 1048576),
        "mosquitto_payload_mib_per_sec_median": (
            median("mosquitto", "throughput_delivered_per_sec") *
            payload_bytes / 1048576),
        "throughput_ratio": throughput_ratio,
        "p95_ratio": p95_ratio,
        "p99_ratio": p99_ratio,
        "connectanum_broker_cpu_seconds_median": median(
            "connectanum", "broker_cpu_seconds"),
        "mosquitto_broker_cpu_seconds_median": median(
            "mosquitto", "broker_cpu_seconds"),
        "connectanum_broker_rss_bytes_max": max(
            row["broker_rss_bytes"] for row in grouped["connectanum"]),
        "mosquitto_broker_rss_bytes_max": max(
            row["broker_rss_bytes"] for row in grouped["mosquitto"]),
        "budgets": budget,
    }
    mosquitto_cpu = result["mosquitto_broker_cpu_seconds_median"]
    result["broker_cpu_ratio"] = (
        result["connectanum_broker_cpu_seconds_median"] / mosquitto_cpu
        if mosquitto_cpu > 0 else None)
    result["connectanum_broker_cpu_seconds_per_million"] = (
        result["connectanum_broker_cpu_seconds_median"] * 1_000_000 / deliveries)
    result["mosquitto_broker_cpu_seconds_per_million"] = (
        mosquitto_cpu * 1_000_000 / deliveries)
    if gate == "correctness":
        result["passed"] = True
    else:
        result["passed"] = (
            throughput_ratio >= budget["min_delivered_throughput_ratio_vs_mosquitto"] and
            p95_ratio <= budget["max_p95_latency_ratio_vs_mosquitto"] and
            p99_ratio <= budget["max_p99_latency_ratio_vs_mosquitto"] and
            result["connectanum_broker_rss_bytes_max"] <=
            budget["max_connectanum_broker_rss_bytes"] and
            result["broker_cpu_ratio"] is not None and
            result["broker_cpu_ratio"] <= budget["max_broker_cpu_ratio_vs_mosquitto"])
    return result


def available_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def targets_for_repeat(repeat, connectanum_port, mosquitto_port):
    targets = (("connectanum", connectanum_port),
               ("mosquitto", mosquitto_port))
    return targets if repeat % 2 else tuple(reversed(targets))


def wait_for_listener(port, process, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"broker exited before listening: {process.args}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise TimeoutError(f"broker did not listen within {timeout} seconds")


def _parse_cpu_time(raw):
    """Parse the cumulative process CPU time printed by macOS ps."""
    fields = raw.split(":")
    if len(fields) not in (2, 3):
        raise ValueError(f"invalid ps CPU time: {raw}")
    seconds = float(fields[-1]) + 60 * int(fields[-2])
    return seconds + (3600 * int(fields[0]) if len(fields) == 3 else 0)


def process_metrics(pid):
    """Return broker CPU seconds, current RSS and high-water RSS."""
    if sys.platform == "linux":
        stat = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
        cpu = (int(stat[11]) + int(stat[12])) / os.sysconf("SC_CLK_TCK")
        status = Path(f"/proc/{pid}/status").read_text()
        def memory(label):
            return next(int(line.split()[1]) * 1024
                        for line in status.splitlines() if line.startswith(label))
        return cpu, memory("VmRSS:"), memory("VmHWM:")
    output = subprocess.check_output(
        ["ps", "-o", "time=", "-o", "rss=", "-p", str(pid)], text=True)
    cpu_raw, rss_kib = output.split()
    rss = int(rss_kib) * 1024
    return _parse_cpu_time(cpu_raw), rss, rss


def stop_broker(broker):
    broker.terminate()
    try:
        broker.wait(timeout=5)
    except subprocess.TimeoutExpired:
        broker.kill()
        broker.wait()


def mosquitto_version(mosquitto):
    # Some Mosquitto builds print help and a version while exiting with code 3.
    process = subprocess.run([mosquitto, "-h"], cwd=ROOT, capture_output=True,
                             text=True, timeout=10)
    for line in (process.stdout + process.stderr).splitlines():
        version = line.strip()
        if version.startswith("mosquitto version "):
            return version
    raise RuntimeError("Mosquitto help output did not contain a version")


def provenance(broker_exe, client_exe, mosquitto):
    def command_output(argv):
        process = subprocess.run(argv, cwd=ROOT, capture_output=True,
                                 text=True, check=True, timeout=10)
        return (process.stdout + process.stderr).strip()

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    return {
        "git_commit": command_output(["git", "rev-parse", "HEAD"]),
        "git_dirty": bool(command_output(["git", "status", "--porcelain"])),
        "dart_version": command_output(["dart", "--version"]),
        "mosquitto_version": mosquitto_version(mosquitto),
        "os": platform.system(),
        "architecture": platform.machine(),
        "logical_cpus": os.cpu_count(),
        "broker_rss_measurement": ("Linux VmHWM" if sys.platform == "linux"
                                   else "ps before/after snapshots"),
        "broker_exe_sha256": digest(broker_exe),
        "client_exe_sha256": digest(client_exe),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--budget", type=Path, default=DEFAULT_BUDGET)
    parser.add_argument("--mosquitto", default="mosquitto")
    args = parser.parse_args()
    budget = json.loads(args.budget.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    port = available_port()
    connectanum_port = available_port()
    while connectanum_port == port:
        connectanum_port = available_port()
    with tempfile.TemporaryDirectory() as tmp:
        broker_exe = Path(tmp) / "mqtt-broker"
        client_exe = Path(tmp) / "mqtt-bench-client"
        for source, output in (("mqtt_broker_server.dart", broker_exe),
                               ("mqtt_qos0.dart", client_exe)):
            subprocess.run(
                ["dart", "compile", "exe", f"benchmark/{source}", "-o", str(output)],
                cwd=ROOT / "packages" / "connectanum_router", check=True,
                capture_output=True, text=True)
        config = Path(tmp) / "mosquitto.conf"
        config.write_text(f"listener {port} 127.0.0.1\nallow_anonymous true\n"
                          "persistence false\nlog_dest none\n")
        brokers = {}
        try:
            brokers["connectanum"] = subprocess.Popen(
                [str(broker_exe), str(connectanum_port)],
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE, text=True)
            brokers["mosquitto"] = subprocess.Popen(
                [args.mosquitto, "-c", str(config)],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            wait_for_listener(connectanum_port, brokers["connectanum"])
            wait_for_listener(port, brokers["mosquitto"])
            rows = []
            raw = args.output / "raw.jsonl"
            for repeat in range(1, budget["repetitions"] + 1):
                for target, target_port in targets_for_repeat(
                        repeat, connectanum_port, port):
                    env = dict(os.environ,
                               MQTT_BENCH_MESSAGES=str(budget["messages_per_run"]),
                               MQTT_BENCH_WINDOW=str(budget.get("window_messages", 0)),
                               MQTT_BENCH_SUBSCRIBERS=str(budget.get("subscribers", 1)),
                               MQTT_BENCH_MODE=budget.get("publish_mode", "single"))
                    before_cpu, _, before_peak_rss = process_metrics(
                        brokers[target].pid)
                    process = subprocess.run(
                        [str(client_exe), "127.0.0.1", str(target_port)],
                        env=env, capture_output=True, text=True, timeout=90)
                    after_cpu, _, after_peak_rss = process_metrics(
                        brokers[target].pid)
                    if process.returncode:
                        raise RuntimeError(f"{target} run {repeat}: {process.stderr}")
                    row = json.loads(process.stdout.strip().splitlines()[-1])
                    row.update(target=target, run=repeat,
                               broker_cpu_seconds=round(after_cpu - before_cpu, 4),
                               broker_rss_bytes=max(before_peak_rss, after_peak_rss))
                    rows.append(row)
                    raw.write_text("".join(json.dumps(item, sort_keys=True) + "\n"
                                           for item in rows))
            summary = compare(rows, budget)
            summary["provenance"] = provenance(broker_exe, client_exe, args.mosquitto)
            (args.output / "summary.json").write_text(
                json.dumps(summary, indent=2, sort_keys=True) + "\n")
            print(json.dumps(summary, sort_keys=True))
            if not summary["passed"]:
                raise SystemExit("MQTT QoS 0 performance budget failed")
        finally:
            for broker in brokers.values():
                stop_broker(broker)


if __name__ == "__main__":
    main()
