#!/usr/bin/env python3
"""Capture a Linux CPU profile separately from MQTT acceptance measurements."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from run_mqtt_benchmark_gate import (
    ROOT, available_port, checked_client_row, provenance, run_client_with_cpu,
    stop_broker, wait_for_listener, workload_environment,
)


def stop_profiler(process):
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        raise RuntimeError("perf did not stop after SIGINT")


def validate_delivery(row, budget):
    messages = budget["messages_per_run"]
    subscribers = budget.get("subscribers", 1)
    if (row["sent"] != messages or row["received"] != messages * subscribers
            or row["received_per_subscriber"] != [messages] * subscribers
            or row["duplicates"] != 0):
        raise RuntimeError("profile workload did not deliver every message exactly")


def profile_native(budget, library, output, perf="perf", runtime="dartaotruntime"):
    transport = budget.get("transport", "tcp")
    if transport not in ("tcp", "ws"):
        raise ValueError("native profiling supports cleartext TCP and WebSocket")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    native = output / "libct_ffi.so"
    shutil.copy2(library, native)
    env = workload_environment(budget, transport)
    env["CONNECTANUM_NATIVE_LIB"] = str(native)
    runtime_version = subprocess.run(
        [str(runtime), "--version"], check=True, capture_output=True, text=True, timeout=10,
    )
    broker_snapshot = output / "mqtt-broker.aot"
    client = output / "mqtt-client"
    for kind, source, destination in (
        ("aot-snapshot", "mqtt_native_router_server.dart", broker_snapshot),
        ("exe", "mqtt_qos0.dart", client),
    ):
        subprocess.run(
            ["dart", "compile", kind, f"benchmark/{source}", "-o", str(destination)],
            cwd=ROOT / "packages/connectanum_router", env=env,
            check=True, capture_output=True, text=True, timeout=180,
        )
    metadata = {
        "diagnosticOnly": True,
        "brokerRuntime": "dartaotruntime",
        "runtimePath": str(runtime),
        "runtimeVersion": (runtime_version.stdout + runtime_version.stderr).strip(),
        "budget": budget,
        "provenance": provenance(broker_snapshot, client, "mosquitto", native, transport),
    }
    (output / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    port = available_port()
    broker_log = output / "broker-stderr.log"
    rows = output / "raw.jsonl"
    rows.write_text("")
    with (output / "broker-stdout.log").open("w") as stdout, broker_log.open("w") as stderr, (output / "perf.log").open("w") as perf_log:
        broker = subprocess.Popen(
            [str(runtime), str(broker_snapshot), str(port)], env=env,
            stdin=subprocess.PIPE, stdout=stdout, stderr=stderr,
        )
        sampler = None
        try:
            wait_for_listener(port, broker)
            sampler = subprocess.Popen(
                [str(perf), "record", "-e", "cpu-clock", "-F", "499",
                 "--call-graph", "dwarf,8192", "-p", str(broker.pid),
                 "-o", str(output / "perf.data")],
                stdout=subprocess.DEVNULL, stderr=perf_log,
            )
            time.sleep(0.25)
            if sampler.poll() is not None:
                raise RuntimeError("perf exited before sampling; inspect perf.log")
            for repeat in range(1, budget["repetitions"] + 1):
                result, _ = run_client_with_cpu(client, port, env)
                row = checked_client_row(result, "connectanum", repeat, broker_log)
                validate_delivery(row, budget)
                row["run"] = repeat
                with rows.open("a") as raw:
                    raw.write(json.dumps(row, sort_keys=True) + "\n")
        finally:
            try:
                if sampler is not None:
                    stop_profiler(sampler)
            finally:
                stop_broker(broker)
    if sampler.returncode != 0:
        raise RuntimeError("perf failed to record samples; inspect perf.log")
    report = output / "profile.txt"
    with report.open("w") as stream:
        subprocess.run(
            [str(perf), "report", "--stdio", "--no-children", "--sort", "comm,dso,symbol",
             "--percent-limit", "0.5", "-i", str(output / "perf.data")],
            stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=60,
        )
    symbols = report.read_text()
    if not any(name in symbols for name in ("Mqtt", "_Peer", "_drainMqtt")):
        raise RuntimeError("profile has no recognized Dart MQTT symbols; inspect profile.txt")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--budget", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--perf", default="perf")
    parser.add_argument("--runtime", default="dartaotruntime")
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("perf profiling requires Linux")
    library = Path(os.environ.get("CONNECTANUM_NATIVE_LIB", ""))
    if not library.is_file():
        parser.error("CONNECTANUM_NATIVE_LIB must name a native library")
    profile_native(json.loads(args.budget.read_text()), library, args.output, args.perf, args.runtime)


if __name__ == "__main__":
    main()
