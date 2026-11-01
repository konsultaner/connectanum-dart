#!/usr/bin/env python3
"""Count MQTT FFI calls using retained native/AOT/client bytes; never a gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

import run_mqtt_benchmark_gate as gate

SOURCE = "1152116064651ee01bd6fd52a798fee975d954bf"
SOURCE_RUN = 41351945654
NATIVE = "10c9aaa77b47ba4aa5d293ecd7d7517c1b7df25f2eab9494062ccbcb9fbc53f8"
LOCK = "0cb8ef90485ccae06b2981d023ea44d46c6309ba46a1186dffab581169f9f0c3"
PROFILES = ("ws_sustained", "ws_v311_sustained", "sustained", "v311_sustained", "64k_sustained")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_bytes(name):
    return subprocess.check_output(["git", "show", SOURCE + ":" + name], cwd=gate.ROOT)


def compile_shim(source, library_dir, destination):
    flags = (["-Wl,-needed_library," + str(library_dir / "libct_ffi.so")]
             if platform.system() == "Darwin" else ["-Wl,--no-as-needed", "-lct_ffi"])
    subprocess.run(["cc", "-std=c11", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                    str(source), "-L" + str(library_dir), *flags,
                    "-Wl,-rpath," + str(library_dir), "-o", str(destination),
                    *([] if platform.system() == "Darwin" else ["-ldl"])], check=True)


def verify_inputs(root):
    run = json.loads((root / "source-run.json").read_text())
    if run["id"] != SOURCE_RUN or run["head_sha"] != SOURCE or run["run_attempt"] != 1:
        raise ValueError("Wrong original source/run/attempt")
    # Do not start diagnostics past a new correctness failure. The original
    # measured MQTT failure and its unsuccessful dependent are the repair target.
    jobs = json.loads((root / "source-jobs.json").read_text())["jobs"]
    permitted = {"MQTT QoS 0 interoperability and benchmark gate", "Full Verify"}
    if any(j["status"] == "completed" and j["conclusion"] != "success"
           and j["name"] not in permitted for j in jobs):
        raise ValueError("Resolve additional original-source CI correctness failures first")
    profile = root / "mqtt-native-profile/ws_sustained"
    metadata = json.loads((profile / "provenance.json").read_text())
    receipt = json.loads((profile / "report-provenance.json").read_text())
    info = metadata["provenance"]
    if info["git_commit"] != SOURCE or info["git_dirty"] or not metadata["diagnosticOnly"]:
        raise ValueError("Profile source identity changed")
    expected = {"libct_ffi.so": info["native_lib_sha256"],
                "mqtt-broker.aot": info["broker_exe_sha256"], "mqtt-client": info["client_exe_sha256"]}
    if expected["libct_ffi.so"] != NATIVE:
        raise ValueError("Wrong actual measured native library")
    for name, wanted in expected.items():
        if digest(profile / name) != wanted:
            raise ValueError("Retained executable/native bytes changed: " + name)
    if digest(profile / "provenance.json") != receipt["sourceProvenanceSha256"]:
        raise ValueError("Profile provenance receipt mismatch")
    comparison = root / "mqtt-native-comparison/inputs"
    if digest(comparison / "candidate-libct_ffi.so") != NATIVE or digest(comparison / "Cargo.lock") != LOCK:
        raise ValueError("Matched native/lock receipt mismatch")
    archive = subprocess.check_output(["git", "archive", SOURCE], cwd=gate.ROOT)
    if (comparison / "candidate-source.tar").read_bytes() != archive:
        raise ValueError("Retained original source archive mismatch")
    if (gate.ROOT / "tool/run_mqtt_benchmark_gate.py").read_bytes() != source_bytes("tool/run_mqtt_benchmark_gate.py"):
        raise ValueError("Original workload helper changed")
    return profile, metadata, expected


def validate_counts(counts):
    if counts.get("diagnostic_only") is not True:
        raise ValueError("Missing diagnostic label")
    scalars = ["poll_calls", "poll_empty", "poll_errors", "poll_positive", "poll_bytes",
               "send_calls", "send_errors", "send_requested_positive_bytes", "arm_calls"]
    if any(type(counts[k]) is not int or counts[k] < 0 for k in scalars):
        raise ValueError("Invalid counters")
    if counts["poll_calls"] != sum(counts[k] for k in ("poll_empty", "poll_errors", "poll_positive")):
        raise ValueError("Poll result conservation mismatch")
    if counts["size_upper_bounds"] != [64,128,256,512,1024,4096,16384,65536,2147483647]:
        raise ValueError("Histogram bounds changed")
    for key in ["poll_sizes", "send_sizes"]:
        if len(counts[key]) != 9 or any(type(v) is not int or v < 0 for v in counts[key]):
            raise ValueError("Invalid histogram")
    if sum(counts["poll_sizes"]) != counts["poll_positive"] or sum(counts["send_sizes"]) > counts["send_calls"]:
        raise ValueError("Histogram conservation mismatch")
    if counts["send_errors"] > counts["send_calls"]:
        raise ValueError("Send result conservation mismatch")


def validate_row(row, budget):
    count = budget["messages_per_run"]
    fields = {"profile": budget["profile"], "sent": count, "received": count, "received_per_subscriber": [count],
              "duplicates": 0, "warmup": 100, "subscribers": 1,
              "payload_bytes": budget["payload_bytes"], "mqtt_version": budget.get("mqtt_version", "5"),
              "transport": budget.get("transport", "tcp"), "window_messages": budget.get("window_messages", 0),
              "publish_mode": budget.get("publish_mode", "single")}
    if any(row[k] != v for k, v in fields.items()):
        raise ValueError("Full original delivery/body/workload checks failed")


def stop_broker(process):
    """Allow existing stdin shutdown and the atexit counters to complete."""
    if process.stdin is not None and not process.stdin.closed:
        try:
            process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
    try:
        return process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Linux" or os.environ.get("CONNECTANUM_NATIVE_RUNTIME_THREADS") is not None:
        raise ValueError("Linux and original automatic worker policy required")
    if any(os.environ.get(key) for key in ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT")):
        raise ValueError("Unrelated loader interposition is not permitted")
    profile, metadata, expected = verify_inputs(args.inputs)
    version = subprocess.run(["dartaotruntime", "--version"], capture_output=True, text=True, check=True)
    if (version.stdout + version.stderr).strip() != metadata["runtimeVersion"]:
        raise ValueError("Runtime differs from retained AOT SDK")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError("Refusing to overwrite retained observations")
    output.mkdir(parents=True, exist_ok=True)
    native_dir = output / "native"
    native_dir.mkdir()
    native = native_dir / "libct_ffi.so"
    broker, client = output / "mqtt-broker.aot", output / "mqtt-client"
    for name, path in [("libct_ffi.so", native), ("mqtt-broker.aot", broker), ("mqtt-client", client)]:
        shutil.copy2(profile / name, path)
        if digest(path) != expected[name]: raise ValueError("Retained copy changed")
    shim_source = Path(__file__).with_name("mqtt_ffi_census.c")
    shim = native_dir / "mqtt-ffi-census.so"
    compile_shim(shim_source, native_dir, shim)
    # Verify the real ELF dependency is present, rather than silently using a
    # different/global native build. The forwarding unit control separately
    # proves that the three wrappers delegate and every other symbol resolves.
    linked = subprocess.check_output(["ldd", str(shim)], text=True)
    if str(native) not in linked:
        raise ValueError("Shim does not link the retained native library")
    (output / "linked-libraries.txt").write_text(linked)
    provenance = {"diagnostic_only": True, "runtime_source": SOURCE, "source_run": SOURCE_RUN,
                  "tool_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=gate.ROOT, text=True).strip(),
                  "native_sha256": NATIVE, "broker_sha256": digest(broker), "client_sha256": digest(client),
                  "shim_sha256": digest(shim), "shim_source_sha256": digest(shim_source),
                  "driver_sha256": digest(Path(__file__)), "helper_sha256": digest(gate.ROOT / "tool/run_mqtt_benchmark_gate.py"),
                  "SDK": (version.stdout + version.stderr).strip(), "cpu_model": gate.cpu_model(),
                  "scope": "Count-only instrumented diagnostic, not acceptance or a numerical gate retry. All original profiles/repetitions/windows/full fresh body checks. Counter overhead is uncalibrated; timings cannot establish repair.",
                  "counter_scope": "Entire fresh broker lifetime, including handshake/warmup/cleanup; counts are not an interior-window allocation or RAM measurement.",
                  "original_profiles": list(PROFILES), "rows_required": 25, "fresh_verified_deliveries_required": 4025000}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    rows = []
    for name in PROFILES:
        filename = "tool/mqtt_native_" + name + "_benchmark_budget.json"
        data = source_bytes(filename)
        if (gate.ROOT / filename).read_bytes() != data: raise ValueError("Original budget changed")
        budget = json.loads(data)
        if budget["repetitions"] != 5: raise ValueError("All five original repetitions required")
        (output / (name + "-budget.json")).write_bytes(data)
        for repeat in range(1, 6):
            prefix = name + "-" + str(repeat)
            env = gate.workload_environment(budget, budget.get("transport", "tcp"))
            # Only the broker loads the shim; the original client environment,
            # input generation, verification and native library bytes are intact.
            broker_env = env.copy()
            broker_env["CONNECTANUM_NATIVE_LIB"] = str(shim)
            census_file = output / (prefix + "-counts.json")
            broker_env["CONNECTANUM_MQTT_CENSUS_OUTPUT"] = str(census_file)
            log = output / (prefix + "-broker.log")
            port = gate.available_port()
            with log.open("w") as stream:
                process = subprocess.Popen(["dartaotruntime", str(broker), str(port)], env=broker_env,
                                           stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=stream)
                primary = None
                try:
                    gate.wait_for_listener(port, process)
                    result, cpu = gate.run_client_with_cpu(client, port, env)
                    (output / (prefix + "-stdout.log")).write_text(result.stdout)
                    (output / (prefix + "-stderr.log")).write_text(result.stderr)
                    row = gate.checked_client_row(result, "instrumented-diagnostic", repeat, broker_log=log)
                    validate_row(row, budget)
                    row.update(profile_key=name, run=repeat, client_cpu_seconds=cpu)
                    rows.append(row)
                    (output / "raw.jsonl").write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
                except BaseException as error:
                    primary = error
                    (output / (prefix + "-primary-error.txt")).write_text(repr(error) + "\n")
                    if isinstance(error, subprocess.TimeoutExpired):
                        for name in ("stdout", "stderr"):
                            data = getattr(error, name, None)
                            if data is not None:
                                if isinstance(data, bytes): data = data.decode("utf8", errors="replace")
                                (output / (prefix + "-" + name + ".log")).write_text(data)
                    raise
                finally:
                    try:
                        status = stop_broker(process)
                        (output / (prefix + "-broker-exit.txt")).write_text(str(status) + "\n")
                        if status: raise ValueError("Broker/counter cleanup failed")
                    except BaseException as cleanup:
                        (output / (prefix + "-cleanup-error.txt")).write_text(repr(cleanup) + "\n")
                        if primary is None: raise
            if process.returncode != 0: raise ValueError("Broker/counter cleanup failed")
            counts = json.loads(census_file.read_text())
            validate_counts(counts)
            if not counts["poll_positive"] or not counts["send_calls"] or not counts["arm_calls"]:
                raise ValueError("Shim did not observe the actual broker path")
            print(prefix, "complete", flush=True)
    verify_inputs(args.inputs)
    for path, wanted in [(native, NATIVE), (broker, provenance["broker_sha256"]), (client, provenance["client_sha256"]),
                         (shim, provenance["shim_sha256"]), (shim_source, provenance["shim_source_sha256"]),
                         (Path(__file__), provenance["driver_sha256"])]:
        if digest(path) != wanted: raise ValueError("Input/binary changed during diagnostic")
    if len(rows) != 25 or sum(r["received"] for r in rows) != 4025000:
        raise ValueError("Incomplete predeclared observations")
    (output / "completion.json").write_text(json.dumps({"complete": True, "rows": 25,
        "fresh_verified_deliveries": 4025000, "inputs_unchanged": True, "diagnostic_only": True}, indent=2) + "\n")


if __name__ == "__main__":
    main()
