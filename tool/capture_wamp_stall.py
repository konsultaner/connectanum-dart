#!/usr/bin/env python3
"""Replay original WAMP scenarios and retain stalled VM stacks, never acceptance."""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import math
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import threading
import time
import tomllib
import urllib.parse
import urllib.request

import run_wamp_serializer_campaign as campaign
from wamp_stall_vm_services import discover_vm_services, identity_matches
from wamp_stall_linux import capture_linux_state

ROOT = Path(__file__).resolve().parents[1]
PROC_ROOT = Path("/proc")
LOCKS = ("pubspec.lock", "native/bench/Cargo.lock", "native/transport/Cargo.lock",
         ".dart_tool/package_config.json")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_inputs(root, output):
    paths = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root,
    ).decode().split("\0")
    return {name: digest(root / name) for name in paths if name and (root / name).is_file()
            and not (root / name).resolve().is_relative_to(output)}


def dart_string(value):
    return json.dumps(str(value)).replace("$", "\\$")


def scenario_files(path):
    if path.is_file():
        return [path]
    if path.is_dir():
        # Match the native driver's nonrecursive, regular-file traversal.
        paths = sorted(entry for entry in path.iterdir() if not entry.is_symlink()
                       and entry.is_file() and entry.suffix.lower() == ".toml")
        if paths:
            return paths
    raise ValueError("scenario must be a TOML file or a directory containing regular TOML files")


def write_wrappers(root, output):
    for role, entry in (("worker", "wamp_client_main.dart"), ("router", "bench_main.dart")):
        uri = (root / "packages/connectanum_bench/tool" / entry).as_uri()
        extra = f", '--wamp-worker', {dart_string(output / 'worker.dart')}" if role == "router" else ""
        (output / f"{role}.dart").write_text(
            "import 'dart:developer';\nimport 'dart:io';\n"
            f"import {dart_string(uri)} as original;\n"
            "Future<void> main(List<String> args) async {\n"
            "  final uri = (await Service.getInfo()).serverUri;\n"
            f"  File({dart_string(output / (role + '-uri.txt'))}).writeAsStringSync(uri.toString());\n"
            f"  await original.main([...args{extra}]);\n}}\n"
        )


def rpc(uri, method, params=None):
    parsed = urllib.parse.urlsplit(uri)
    if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise ValueError("VM diagnostics require a local HTTP service URI")
    url = urllib.parse.urljoin(uri, method) + "?" + urllib.parse.urlencode(params or {})
    with urllib.request.urlopen(url, timeout=3) as response:
        data = json.load(response)
    if not isinstance(data, dict) or "error" in data:
        raise ValueError(f"VM RPC failed: {data!r}")
    result = data.get("result", data)
    if not isinstance(result, dict):
        raise ValueError("VM RPC did not return an object")
    expected_type = {"getVM": "VM", "getStack": "Stack"}.get(method)
    if expected_type is not None and result.get("type") != expected_type:
        raise ValueError(f"VM RPC did not return {expected_type}")
    if method == "getVM" and (type(result.get("pid")) is not int or result["pid"] <= 0 or
                               not isinstance(result.get("isolates"), list)):
        raise ValueError("VM RPC returned invalid process/isolate information")
    if method == "getStack" and not isinstance(result.get("frames"), list):
        raise ValueError("VM RPC returned invalid stack frames")
    return result


def capture_stacks(output, last_output, stop, driver_alive=lambda: True):
    snapshot = {"started_at_unix_seconds": time.time(), "last_output": last_output, "roles": {},
                "driver_alive_at_start": driver_alive()}
    for role in ("worker", "router"):
        if stop.is_set() or not driver_alive():
            break
        try:
            uri = (output / f"{role}-uri.txt").read_text().strip()
            vm = rpc(uri, "getVM")
            stacks = []
            for isolate in vm.get("isolates", []):
                if stop.is_set() or not driver_alive():
                    break
                entry = {"id": isolate["id"], "name": isolate.get("name")}
                try:
                    entry["stack"] = rpc(uri, "getStack", {"isolateId": isolate["id"], "limit": 100})
                except Exception as error:
                    entry["error"] = repr(error)
                stacks.append(entry)
            snapshot["roles"][role] = {"pid": vm.get("pid"), "isolates": stacks}
        except Exception as error:
            snapshot["roles"][role] = {"error": repr(error)}
    snapshot.update(completed_at_unix_seconds=time.time(), driver_alive_at_end=driver_alive(),
                    interrupted=stop.is_set() or not driver_alive())
    return snapshot


def redact_debug_text(value):
    return re.sub(
        r"((?:https?|wss?)://(?:127\.[0-9.]+|\[::1\]|localhost):[0-9]+)/[A-Za-z0-9_-]{8,}={0,2}",
        r"\1/<vm-service>", value,
    )


def capture_original_stacks(driver_pid, last_output, stop, driver_alive=lambda: True):
    snapshot = {"started_at_unix_seconds": time.time(), "last_output": redact_debug_text(last_output),
                "roles": {}, "driver_alive_at_start": driver_alive(), "endpoint_source": "owned metrics observers"}
    private_uris = []
    try:
        targets = discover_vm_services(driver_pid, PROC_ROOT)
        if not targets:
            snapshot["discovery_error"] = "No existing owned metrics observer endpoints are available"
        for target in targets:
            if stop.is_set() or not driver_alive():
                break
            key = target.role if target.role not in snapshot["roles"] else f"{target.role}:{target.pid}"
            record = {"pid": target.pid, "observer_pid": target.observer_pid,
                      "start_ticks": target.identity.start_ticks, "isolates": []}
            snapshot["roles"][key] = record
            private_uris.append(target.uri)
            try:
                if not identity_matches(target, PROC_ROOT):
                    raise ValueError("VM process identity changed before observation")
                vm = rpc(target.uri, "getVM")
                if (type(vm.get("pid")) is not int or vm["pid"] != target.pid
                        or not identity_matches(target, PROC_ROOT)):
                    raise ValueError("VM endpoint does not match the owned process identity")
                record["linux"] = capture_linux_state(target, PROC_ROOT)
                isolates = vm.get("isolates")
                if not isinstance(isolates, list) or len(isolates) > 32:
                    raise ValueError("Invalid or excessive VM isolate inventory")
                for isolate in isolates:
                    if stop.is_set() or not driver_alive():
                        break
                    if not identity_matches(target, PROC_ROOT):
                        record["identity_changed"] = True
                        break
                    if not isinstance(isolate, dict) or not isinstance(isolate.get("id"), str):
                        raise ValueError("Invalid VM isolate reference")
                    entry = {"id": isolate["id"], "name": isolate.get("name")}
                    try:
                        stack = rpc(target.uri, "getStack", {"isolateId": isolate["id"], "limit": 100})
                        if not identity_matches(target, PROC_ROOT):
                            raise ValueError("VM process identity changed during stack observation")
                        entry["stack"] = stack
                    except Exception as error:
                        entry["error"] = repr(error)
                    record["isolates"].append(entry)
            except Exception as error:
                record["error"] = repr(error)
    except Exception as error:
        snapshot["discovery_error"] = repr(error)
    snapshot.update(completed_at_unix_seconds=time.time(), driver_alive_at_end=driver_alive(),
                    interrupted=stop.is_set() or not driver_alive())
    encoded = json.dumps(snapshot)
    for uri in private_uris:
        encoded = encoded.replace(uri, "<vm-service>")
        path = urllib.parse.urlsplit(uri).path
        if path != "/":
            encoded = encoded.replace(path, "<vm-service-path>")
    return json.loads(redact_debug_text(encoded))


def run(args, root=ROOT):
    if os.name != "posix":
        raise ValueError("WAMP stall diagnostics currently require POSIX process groups")
    for key in ("stall_seconds", "max_seconds"):
        value = getattr(args, key)
        if not math.isfinite(value) or value <= 0:
            raise ValueError(f"{key} must be finite and positive")
    if args.workload_timeout_ms <= 0:
        raise ValueError("workload timeout must be positive")
    original = getattr(args, "original_processes", False)
    control_base = getattr(args, "control_base", "https://127.0.0.1:8080/bench")
    if original:
        if not PROC_ROOT.is_dir():
            raise ValueError("Original-process VM discovery requires Linux procfs")
        control = urllib.parse.urlsplit(control_base)
        if (control.scheme not in ("http", "https") or control.username is not None
                or control.password is not None or control.port is None or not 0 < control.port < 65536
                or not ipaddress.ip_address(control.hostname or "").is_loopback):
            raise ValueError("Original-process control URL must be loopback HTTP(S)")
    files = {key: getattr(args, key).resolve(strict=True)
             for key in ("driver", "native_lib", "router_config", "scenario")}
    if any(not path.is_file() for key, path in files.items() if key != "scenario"):
        raise ValueError("diagnostic inputs must be files")
    scenarios = scenario_files(files["scenario"])
    expected = []
    for path in scenarios:
        workloads = tomllib.loads(path.read_text()).get("workloads", [])
        file_names = [workload["name"] for workload in workloads]
        if (not file_names or any(not isinstance(name, str) or not name for name in file_names) or
                len(set(file_names)) != len(file_names)):
            raise ValueError("each scenario must contain uniquely named workloads")
        expected.extend(workloads)
    names = [workload["name"] for workload in expected]
    for workload in expected:
        if (type(workload.get("iterations")) is not int or workload["iterations"] <= 0 or
                type(workload.get("minimum_duration_ms")) is not int or workload["minimum_duration_ms"] < 0):
            raise ValueError("scenario sample/duration floors must be nonnegative integers, with positive samples")
    config = json.loads(files["router_config"].read_text())
    if not config["router"]["listeners"]:
        raise ValueError("router config must have at least one listener")
    for name in LOCKS:
        if not (root / name).is_file():
            raise ValueError(f"resolved lock is missing: {name}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    inputs = source_inputs(root, output)
    locks = {name: digest(root / name) for name in LOCKS}
    resolved_files = {}
    for name, expected_hash in locks.items():
        retained = output / "resolved-inputs" / name
        retained.parent.mkdir(parents=True, exist_ok=True)
        retained.write_bytes((root / name).read_bytes())
        if digest(retained) != expected_hash:
            raise ValueError("resolved input changed during preparation")
        resolved_files[name] = str(retained.relative_to(output))
    if not original:
        write_wrappers(root, output)
    if files["scenario"].is_dir():
        copied_scenario = output / "scenarios"
        copied_scenario.mkdir()
        for path in scenarios:
            try:
                with (copied_scenario / path.name).open("xb") as destination:
                    destination.write(path.read_bytes())
            except FileExistsError as error:
                raise ValueError(f"scenario copy filename collision: {path.name}") from error
    else:
        copied_scenario = output / "scenario.toml"
        copied_scenario.write_bytes(scenarios[0].read_bytes())
    ports = []
    if original:
        (output / "router.json").write_bytes(files["router_config"].read_bytes())
    else:
        for listener in config["router"]["listeners"]:
            while True:
                with socket.socket() as sock:
                    sock.bind(("127.0.0.1", 0))
                    port = sock.getsockname()[1]
                if port not in ports:
                    break
            ports.append(port)
            listener["endpoint"] = f"127.0.0.1:{port}"
            if "http3" in listener["protocols"]:
                listener["protocols"].remove("http3")
                listener["http"].pop("http3", None)
        (output / "router.json").write_text(json.dumps(config, indent=2) + "\n")
    router_config = files["router_config"] if original else output / "router.json"
    scenario = files["scenario"] if original else copied_scenario
    entrypoint = [] if original else ["--bench-main", str(output / "router.dart")]
    control_base = control_base if original else f"https://127.0.0.1:{ports[0]}/bench"
    command = [str(files["driver"]), "--dart", args.dart, *entrypoint,
               "--native-lib", str(files["native_lib"]), "--router-config", str(router_config),
               "--control-base", control_base,
               "--scenario", str(scenario), "--results", str(output / "reports.jsonl"),
               "--results-only", "--skip-wamp-worker-aot", "--collect-wamp-vm-metrics",
               "--router-worker-counts", "1", "--native-runtime-thread-counts", "1",
               "--workload-timeout-ms", str(args.workload_timeout_ms)]
    generated = ("router.json",) if original else ("worker.dart", "router.dart", "router.json")
    hashes = {str(path): digest(path) for path in [*(path for key, path in files.items() if key != "scenario"),
              *scenarios, *scenario_files(copied_scenario), *(output / name for name in
              generated)]}
    provenance = {"kind": "stall_reproduction_never_acceptance", "mode": "original_processes" if original else "entrypoint_wrappers", "head": head, "inputs": inputs,
                  "resolved_locks": locks, "file_hashes": hashes, "command": command,
                  "resolved_input_files": resolved_files,
                  "platform": platform.uname()._asdict(),
                  "rustup_toolchain_env": os.environ.get("RUSTUP_TOOLCHAIN"),
                  "scenario_files": [str(path) for path in scenarios],
                  "workload_order": names, "stall_seconds": args.stall_seconds,
                  "max_seconds": args.max_seconds,
                  "limitations": (["Original package entrypoints, router config, listener ports and HTTP/3 retained",
                                   "Existing owned metrics endpoints; debug RPC may perturb scheduling",
                                   "Diagnostic replay cannot establish performance acceptance"] if original else
                                  ["URI-only VM wrappers; getStack after missing log progress",
                                   "ephemeral listener ports; unused HTTP/3 listener disabled",
                                   "diagnostic replay cannot establish performance acceptance"])}
    (output / "inputs.json").write_text(json.dumps(provenance, indent=2) + "\n")
    process = reader = watcher = None
    stop = threading.Event()
    activity = {"at": time.monotonic(), "line": ""}
    activity_lock = threading.Lock()
    stalls = []
    background_errors = []
    failure = None
    group_stopped = None

    def read():
        with process.stdout as stream, (output / "driver.log").open("wb") as log:
            for line in stream:
                if original:
                    line = redact_debug_text(line.decode(errors="replace")).encode()
                log.write(line)
                log.flush()
                with activity_lock:
                    activity.update(at=time.monotonic(), line=line.decode(errors="replace").rstrip())

    def monitor():
        captured = {}
        while not stop.wait(min(1, args.stall_seconds / 4)):
            if process.poll() is not None:
                return
            with activity_lock:
                progress_at, line = activity["at"], activity["line"]
            now = time.monotonic()
            count, prior = captured.get(progress_at, (0, 0))
            if now - progress_at < args.stall_seconds or count >= 3 or now - prior < args.stall_seconds:
                continue
            captured[progress_at] = (count + 1, now)
            snapshot = (capture_original_stacks(process.pid, line, stop, lambda: process.poll() is None)
                        if original else capture_stacks(output, line, stop, lambda: process.poll() is None))
            with activity_lock:
                snapshot["progress_changed_during_capture"] = activity["at"] != progress_at
                snapshot["last_output_at_completion"] = redact_debug_text(activity["line"]) if original else activity["line"]
            path = output / f"stall-{len(stalls) + 1}.json"
            path.write_text(json.dumps(snapshot, indent=2) + "\n")
            stalls.append(path.name)
            print(f"Captured stalled VM evidence: {path.name}", flush=True)

    def background(action):
        try:
            action()
        except Exception as error:
            background_errors.append(f"{action.__name__}: {type(error).__name__}: {error}")

    try:
        process = subprocess.Popen(command, cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True,
                                   env={**os.environ, "CONNECTANUM_SKIP_NATIVE_BUILD": "1",
                                        "CONNECTANUM_BENCH_WAMP_REUSE_WORKER": "1"})
        reader = threading.Thread(target=background, args=(read,), daemon=True)
        watcher = threading.Thread(target=background, args=(monitor,), daemon=True)
        reader.start()
        watcher.start()
        process.wait(timeout=args.max_seconds)
        if process.returncode != 0:
            failure = f"driver exited with code {process.returncode}"
    except BaseException as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        stop.set()
        if watcher is not None:
            watcher.join(timeout=8)
        if process is not None:
            group_stopped = campaign.stop_process_group(process)
        if reader is not None:
            reader.join(timeout=8)
    after = source_inputs(root, output)
    changed = sorted(name for name in inputs.keys() | after.keys() if inputs.get(name) != after.get(name))
    same_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == head
    changed_locks = [name for name, value in locks.items()
                     if not (root / name).is_file() or digest(root / name) != value]
    changed_files = [name for name, value in hashes.items()
                     if not Path(name).is_file() or digest(Path(name)) != value]
    try:
        scenario_inventory_unchanged = scenario_files(files["scenario"]) == scenarios
    except ValueError:
        scenario_inventory_unchanged = False
    reports = []
    try:
        raw = (output / "reports.jsonl").read_bytes()
        if not raw.endswith(b"\n"):
            raise ValueError("driver report ends with a truncated JSONL row")
        reports = [json.loads(line) for line in raw.splitlines()]
        if [report["workload"] for report in reports] != names:
            raise ValueError("driver report order/inventory does not match the replayed scenario")
        for workload, report in zip(expected, reports):
            if (len(report["samples"]) < workload["iterations"] or
                    report["data_window_elapsed_ms"] < workload["minimum_duration_ms"]):
                raise ValueError("driver did not preserve the scenario sample/duration floors")
    except Exception as error:
        failure = failure or f"{type(error).__name__}: {error}"
    code = process.returncode if process is not None else None
    result = {"kind": "stall_reproduction_never_acceptance", "mode": "original_processes" if original else "entrypoint_wrappers", "head": head, "driver_exit_code": code,
              "failure": failure, "rows": len(reports), "expected_rows": len(names), "stalls": stalls,
              "inputs_unchanged": not changed and same_head, "changed": changed,
              "locks_unchanged": not changed_locks, "changed_locks": changed_locks,
              "files_unchanged": not changed_files, "changed_files": changed_files,
              "scenario_inventory_unchanged": scenario_inventory_unchanged,
              "driver_log_sha256": digest(output / "driver.log") if (output / "driver.log").exists() else None,
              "reports_sha256": digest(output / "reports.jsonl") if (output / "reports.jsonl").exists() else None,
              "process_group_stopped": group_stopped,
              "background_errors": background_errors,
              "monitor_stopped": watcher is None or not watcher.is_alive(),
              "reader_stopped": reader is None or not reader.is_alive()}
    result["status"] = "completed" if (code == 0 and failure is None and result["inputs_unchanged"] and
        result["locks_unchanged"] and result["files_unchanged"] and group_stopped and not background_errors and
        scenario_inventory_unchanged and result["monitor_stopped"] and result["reader_stopped"]) else "failed"
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    return 0 if result["status"] == "completed" else code if code and code > 0 else 1


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("output", "scenario", "driver", "native-lib", "router-config"):
        parser.add_argument("--" + name, type=Path, required=True,
                            help="One TOML file or a directory of original scenarios" if name == "scenario" else None)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--original-processes", action="store_true",
                        help="Keep the original entrypoints/listeners and observe existing Linux VM services")
    parser.add_argument("--control-base", default="https://127.0.0.1:8080/bench")
    parser.add_argument("--stall-seconds", type=float, default=60)
    parser.add_argument("--max-seconds", type=float, default=1800)
    parser.add_argument("--workload-timeout-ms", type=int, default=300000)
    return parser.parse_args(argv)


def main(argv=None):
    try:
        return run(parse_args(argv))
    except (ValueError, OSError, KeyError) as error:
        print(f"WAMP stall diagnostic: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
