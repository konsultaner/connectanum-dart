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
TLS_CERT_DIR = ROOT / "packages" / "connectanum_router" / "test" / "certs"
TLS_CA = TLS_CERT_DIR / "remote_auth_ca_cert.pem"
TLS_CERT = TLS_CERT_DIR / "remote_auth_server_cert.pem"
TLS_KEY = TLS_CERT_DIR / "remote_auth_server_key.pem"


def workload_environment(budget, transport):
    env = dict(os.environ)
    env.pop("MQTT_BENCH_TLS_CA", None)
    env.update(MQTT_BENCH_VERSION=budget.get("mqtt_version", "5"),
               MQTT_BENCH_MESSAGES=str(budget["messages_per_run"]),
               MQTT_BENCH_WINDOW=str(budget.get("window_messages", 0)),
               MQTT_BENCH_SUBSCRIBERS=str(budget.get("subscribers", 1)),
               MQTT_BENCH_PAYLOAD_BYTES=str(budget["payload_bytes"]),
               MQTT_BENCH_MODE=budget.get("publish_mode", "single"))
    if transport == "tls":
        env["MQTT_BENCH_TLS_CA"] = str(TLS_CA)
    return env


def compare(rows, budget):
    profile = budget["profile"]
    mqtt_version = budget.get("mqtt_version", "5")
    transport = budget.get("transport", "tcp")
    if mqtt_version not in ("5", "311"):
        raise ValueError(f"invalid MQTT version: {mqtt_version}")
    if transport not in ("tcp", "tls"):
        raise ValueError(f"invalid MQTT transport: {transport}")
    if not profile.startswith(f"mqtt{mqtt_version}-{transport}-"):
        raise ValueError(f"MQTT benchmark profile/version/transport mismatch: {profile}")
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
                    row.get("mqtt_version") != mqtt_version or
                    row.get("transport", "tcp") != transport or
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
    paired = {name: {row["run"]: row for row in samples}
              for name, samples in grouped.items()}
    paired_throughput_ratios = [
        paired["connectanum"][run]["throughput_delivered_per_sec"] /
        paired["mosquitto"][run]["throughput_delivered_per_sec"]
        for run in range(1, repeats + 1)]
    result = {
        "profile": profile,
        "mqtt_version": mqtt_version,
        "transport": transport,
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
        "paired_throughput_ratio_median": statistics.median(paired_throughput_ratios),
        "paired_throughput_ratio_min": min(paired_throughput_ratios),
        "paired_throughput_ratio_max": max(paired_throughput_ratios),
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


def choose_broker_ports():
    mosquitto_port = available_port()
    connectanum_port = available_port()
    while connectanum_port == mosquitto_port:
        connectanum_port = available_port()
    return mosquitto_port, connectanum_port


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


def checked_client_row(process, target, repeat, broker_log=None):
    if process.returncode:
        details = process.stderr
        if broker_log is not None:
            details += "\nBroker stderr tail:\n" + Path(broker_log).read_text()[-4000:]
        raise RuntimeError(f"{target} run {repeat}: {details}")
    return json.loads(process.stdout.strip().splitlines()[-1])


def require_budget(summary):
    if not summary["passed"]:
        raise SystemExit("MQTT QoS 0 performance budget failed")


def require_exact_line_coverage(report_path):
    report = json.loads(Path(report_path).read_text())
    totals = report.get("totals", {})
    if (set(report.get("files", {})) != {"tool/run_mqtt_benchmark_gate.py"} or
            totals.get("num_statements", 0) <= 0 or
            totals.get("missing_lines") != 0 or
            totals.get("excluded_lines") != 0):
        raise ValueError("MQTT benchmark gate requires exact 100% executable-line coverage")
    return totals["num_statements"]


def provenance(broker_exe, client_exe, mosquitto, native_lib=None,
               transport="tcp"):
    def command_output(argv):
        process = subprocess.run(argv, cwd=ROOT, capture_output=True,
                                 text=True, check=True, timeout=10)
        return (process.stdout + process.stderr).strip()

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    result = {
        "broker_mode": "native-router" if native_lib is not None else "dart-broker",
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
    if native_lib is not None:
        result["native_lib_sha256"] = digest(native_lib)
    if transport == "tls":
        result["tls_ca_sha256"] = digest(TLS_CA)
        result["tls_cert_sha256"] = digest(TLS_CERT)
        result["tls_key_sha256"] = digest(TLS_KEY)
    return result


def mosquitto_config(port, transport):
    config = (f"listener {port} 127.0.0.1\nallow_anonymous true\n"
              "persistence false\nlog_dest none\n")
    if transport == "tls":
        config += f"certfile {TLS_CERT}\nkeyfile {TLS_KEY}\n"
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--budget", type=Path, default=DEFAULT_BUDGET)
    parser.add_argument("--mosquitto", default="mosquitto")
    parser.add_argument("--native-router", action="store_true",
                        help="benchmark native MQTT listener instead of Dart-only broker")
    args = parser.parse_args()
    native_lib = None
    if args.native_router:
        configured = os.environ.get("CONNECTANUM_NATIVE_LIB")
        if not configured:
            parser.error("--native-router requires CONNECTANUM_NATIVE_LIB")
        native_lib = Path(configured).resolve()
        if not native_lib.is_file():
            parser.error(f"native library not found: {native_lib}")
    budget = json.loads(args.budget.read_text())
    transport = budget.get("transport", "tcp")
    if transport not in ("tcp", "tls"):
        parser.error(f"invalid MQTT transport: {transport}")
    if transport == "tls" and not args.native_router:
        parser.error("TLS benchmark requires --native-router")
    args.output.mkdir(parents=True, exist_ok=True)
    port, connectanum_port = choose_broker_ports()
    with tempfile.TemporaryDirectory() as tmp:
        broker_exe = Path(tmp) / "mqtt-broker"
        client_exe = Path(tmp) / "mqtt-bench-client"
        broker_source = ("mqtt_native_router_server.dart" if args.native_router
                         else "mqtt_broker_server.dart")
        for source, output in ((broker_source, broker_exe),
                               ("mqtt_qos0.dart", client_exe)):
            subprocess.run(
                ["dart", "compile", "exe", f"benchmark/{source}", "-o", str(output)],
                cwd=ROOT / "packages" / "connectanum_router", check=True,
                capture_output=True, text=True)
        config = Path(tmp) / "mosquitto.conf"
        config.write_text(mosquitto_config(port, transport))
        brokers = {}
        broker_logs = {target: args.output / f"{target}-broker-stderr.log"
                       for target in ("connectanum", "mosquitto")}
        broker_stderr = {target: path.open("w")
                         for target, path in broker_logs.items()}
        try:
            brokers["connectanum"] = subprocess.Popen(
                [str(broker_exe), str(connectanum_port)] +
                ([str(TLS_CERT), str(TLS_KEY)] if transport == "tls" else []),
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                stderr=broker_stderr["connectanum"], text=True)
            brokers["mosquitto"] = subprocess.Popen(
                [args.mosquitto, "-c", str(config)],
                stdout=subprocess.DEVNULL,
                stderr=broker_stderr["mosquitto"], text=True)
            wait_for_listener(connectanum_port, brokers["connectanum"])
            wait_for_listener(port, brokers["mosquitto"])
            rows = []
            raw = args.output / "raw.jsonl"
            for repeat in range(1, budget["repetitions"] + 1):
                for target, target_port in targets_for_repeat(
                        repeat, connectanum_port, port):
                    env = workload_environment(budget, transport)
                    before_cpu, _, before_peak_rss = process_metrics(
                        brokers[target].pid)
                    process = subprocess.run(
                        [str(client_exe), "127.0.0.1", str(target_port)],
                        env=env, capture_output=True, text=True, timeout=90)
                    after_cpu, _, after_peak_rss = process_metrics(
                        brokers[target].pid)
                    row = checked_client_row(
                        process, target, repeat, broker_log=broker_logs[target])
                    row.update(target=target, run=repeat,
                               broker_cpu_seconds=round(after_cpu - before_cpu, 4),
                               broker_rss_bytes=max(before_peak_rss, after_peak_rss))
                    rows.append(row)
                    raw.write_text("".join(json.dumps(item, sort_keys=True) + "\n"
                                           for item in rows))
            summary = compare(rows, budget)
            summary["provenance"] = provenance(
                broker_exe, client_exe, args.mosquitto, native_lib, transport)
            (args.output / "summary.json").write_text(
                json.dumps(summary, indent=2, sort_keys=True) + "\n")
            print(json.dumps(summary, sort_keys=True))
            require_budget(summary)
        finally:
            for broker in brokers.values():
                stop_broker(broker)
            for stderr in broker_stderr.values():
                stderr.close()


if __name__ == "__main__":
    main()
