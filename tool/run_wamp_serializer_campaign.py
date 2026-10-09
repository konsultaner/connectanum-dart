#!/usr/bin/env python3
"""Run and retain a paired WAMP serializer campaign; missing evidence fails closed."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import itertools
import json
import math
import os
import platform
import random
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import wamp_serializer_compare as compare

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "native/bench/artifact_gate/wamp_flatbuffers_performance.json"
LOCK = Path(tempfile.gettempdir()) / "connectanum-wamp-performance-campaign.lock"


def primary_cases() -> list[dict[str, Any]]:
    cases = []
    for mode, transport, secure, client, construction in itertools.product(
        ("rpc", "pubsub"), ("rawsocket", "websocket"), (False, True),
        ("dart", "native"), ("values", "native_buffer", "pre_encoded_span"),
    ):
        case_id = "_".join((mode, transport, "tls" if secure else "clear", client, construction))
        cases.append({
            "id": case_id, "construction": construction, "mode": mode,
            "transport": transport, "secure_transport": secure, "client_impl": client,
            "workloads": {codec: f"{case_id}_{codec}" for codec in compare.CODECS},
        })
    return cases


def schedule(cases: list[dict[str, Any]], warmups: int, repetitions: int, seed: int) -> list[dict[str, Any]]:
    rng = random.Random(seed)
    permutations = list(itertools.permutations(compare.CODECS))
    orders: dict[str, list[tuple[str, ...]]] = {}
    for case in cases:
        orders[case["id"]] = []
        while len(orders[case["id"]]) < repetitions:
            block = permutations.copy()
            rng.shuffle(block)
            orders[case["id"]].extend(block)
    runs = []
    for index in range(warmups + repetitions):
        warmup = index < warmups
        run_id = f"{index:04d}_{'warmup' if warmup else 'measured'}"
        shuffled_cases = cases.copy()
        rng.shuffle(shuffled_cases)
        order = []
        for case in shuffled_cases:
            codecs = rng.choice(permutations) if warmup else orders[case["id"]][index - warmups]
            order.extend(case["workloads"][codec] for codec in codecs)
        runs.append({
            "scenario": run_id, "kind": "warmup" if warmup else "measured",
            "index": index + 1 if warmup else index - warmups + 1,
            "order": order, "results": f"runs/{run_id}.jsonl", "status": "planned",
            "rows_completed": 0,
        })
    return runs


def write_scenarios(output: Path, cases: list[dict[str, Any]], runs: list[dict[str, Any]],
                    duration_ms: int, samples: int, concurrency: int, in_flight: int) -> str:
    by_workload = {name: (case, codec) for case in cases for codec, name in case["workloads"].items()}
    directory = output / "scenarios"
    directory.mkdir()
    for run in runs:
        lines = [f'name = {json.dumps(run["scenario"])}', 'description = "Paired typed WAMP serializer campaign"']
        for name in run["order"]:
            case, codec = by_workload[name]
            fields = {
                "name": name, "protocol": f'wamp_{case["transport"]}_{case["mode"]}',
                "client_impl": case["client_impl"], "serializer": codec,
                "iterations": samples, "minimum_duration_ms": duration_ms,
                "concurrency": concurrency, "in_flight_per_session": in_flight,
                "peer_count": 1, "request_bytes": 65536, "response_bytes": 65536,
                "secure_transport": case["secure_transport"],
                "path": "bench.rpc.echo" if case["mode"] == "rpc" else "bench.wamp.topic",
                "ppt_scheme": "x_connectanum_bench_typed", "ppt_serializer": codec,
                "payload_construction": case["construction"],
            }
            lines.extend(["", "[[workloads]]", *(
                f"{key} = {json.dumps(value)}" for key, value in fields.items()
            )])
        data = ("\n".join(lines) + "\n").encode()
        path = directory / f'{run["scenario"]}.toml'
        path.write_bytes(data)
    return scenario_directory_hash(directory)


def scenario_directory_hash(directory: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(directory.glob("*.toml")):
        digest.update(path.name.encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def command_output(command: list[str], root: Path = ROOT) -> str:
    return subprocess.check_output(command, cwd=root, text=True, stderr=subprocess.STDOUT).strip()


def system_state() -> dict[str, Any]:
    def read(path: Path) -> str | None:
        try:
            return path.read_text().strip()
        except OSError:
            return None
    return {
        "load_average": list(os.getloadavg()),
        "thermal_celsius_milli": {str(p): read(p) for p in sorted(Path("/sys/class/thermal").glob("thermal_zone*/temp"))},
        "cpu_scaling_governor": read(Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")),
        "power_supply": {str(p): read(p) for p in sorted(Path("/sys/class/power_supply").glob("*/online"))},
        "virtualization_product": read(Path("/sys/class/dmi/id/product_name")),
    }


def metadata(root: Path, args: argparse.Namespace, scenario_hash: str) -> dict[str, Any]:
    cpu_model = platform.processor() or "unavailable"
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text().splitlines():
            if line.startswith(("model name", "Hardware", "Processor")) and ":" in line:
                cpu_model = line.split(":", 1)[1].strip()
                break
    lockfiles = ("pubspec.lock", "native/bench/Cargo.lock", "native/transport/Cargo.lock")
    return {
        "campaign_kind": "diagnostic" if args.diagnostic else "primary",
        "source_revision": command_output(["git", "rev-parse", "HEAD"], root),
        "working_tree_clean": not command_output(["git", "status", "--porcelain"], root),
        "scenario_sha256": scenario_hash,
        "lockfiles_sha256": {name: sha256(root / name) for name in lockfiles},
        "artifacts_sha256": {"driver": sha256(args.driver), "native_library": sha256(args.native_lib)},
        "router_config_sha256": sha256(args.router_config),
        "policy_sha256": sha256(args.policy),
        "platform": {
            "os": platform.system(), "kernel": platform.release(), "cpu_model": cpu_model,
            "logical_cpu_count": os.cpu_count(), "runner_image": args.runner_image,
            "dart_version": command_output([args.dart, "--version"], root),
            "rustc_version": command_output(["rustc", "--version"], root),
            "os_release": Path("/etc/os-release").read_text() if Path("/etc/os-release").exists() else None,
        },
        "load_average": list(os.getloadavg()), "system_state_before": system_state(),
        "resource_mode": "source_vm_metrics", "worker_lifetime": "one_driver_and_stable_client_server_processes",
    }


def write_manifest(output: Path, manifest: dict[str, Any]) -> None:
    temporary = output / "manifest.json.tmp"
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    temporary.replace(output / "manifest.json")


class Recorder:
    def __init__(self, output: Path, manifest: dict[str, Any], runs: list[dict[str, Any]]):
        self.output, self.manifest, self.runs = output, manifest, runs
        self.run_index = 0
        self.previous_end = 0
        (output / "runs").mkdir()

    def append(self, line: bytes) -> None:
        if self.run_index == len(self.runs):
            raise compare.CampaignError("driver produced unexpected extra reports")
        report = json.loads(line)
        run = self.runs[self.run_index]
        expected = run["order"][run["rows_completed"]]
        if report.get("scenario") != run["scenario"] or report.get("workload") != expected:
            raise compare.CampaignError(f"report attribution mismatch: expected {run['scenario']}/{expected}")
        start, end = report.get("started_at_ms"), report.get("completed_at_ms")
        if any(isinstance(v, bool) or not isinstance(v, int) or v <= 0 for v in (start, end)) or end <= start:
            raise compare.CampaignError("report has invalid observed start/end timestamps")
        if start < self.previous_end:
            self.manifest["overlap_detected"] = True
            raise compare.CampaignError("workload overlaps the preceding workload")
        pids = {}
        for name in ("client_process_metrics", "server_process_metrics"):
            metrics = report.get(name)
            pid = metrics.get("pid") if isinstance(metrics, dict) else None
            if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
                raise compare.CampaignError(f"report is missing a valid {name}.pid")
            pids[name] = pid
        execution = self.manifest["execution"]
        if execution.setdefault("observed_process_pids", pids) != pids:
            raise compare.CampaignError("client/server process changed; warmup cannot carry across passes")
        self.previous_end = end
        utc = lambda ms: datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat()
        if run["rows_completed"] == 0:
            run.update(status="running", started_at_utc=utc(start))
        with (self.output / run["results"]).open("ab") as stream:
            stream.write(line + b"\n")
        run.update(completed_at_utc=utc(end), rows_completed=run["rows_completed"] + 1)
        if run["rows_completed"] == len(run["order"]):
            run["status"] = "completed"
            run["system_state_after"] = system_state()
            self.run_index += 1
            print(f"Completed {run['scenario']} ({len(run['order'])} rows)", flush=True)
        write_manifest(self.output, self.manifest)


def group_alive(group: int) -> bool:
    if Path("/proc/self/stat").exists():
        # Zombies cannot execute or keep sockets open; container PID 1 may reap them later.
        for path in Path("/proc").glob("[0-9]*/stat"):
            try:
                fields = path.read_text().rsplit(")", 1)[1].split()
                if fields[0] != "Z" and int(fields[2]) == group:
                    return True
            except (OSError, ValueError, IndexError):
                continue
        return False
    # macOS can return EPERM rather than ESRCH for a disappearing process group.
    # Inspect live members instead of mistaking that race for a cleanup failure.
    rows = subprocess.check_output(["ps", "-axo", "pgid=,stat="], text=True)
    return any(int(fields[0]) == group and not fields[1].startswith("Z")
               for row in rows.splitlines() if len(fields := row.split()) >= 2)


def stop_process_group(process: subprocess.Popen) -> bool:
    for sig, grace in ((signal.SIGTERM, 3), (signal.SIGKILL, 3)):
        if group_alive(process.pid):
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + grace
        while group_alive(process.pid) and time.monotonic() < deadline:
            process.poll()
            time.sleep(0.05)
    process.wait(timeout=1)
    return not group_alive(process.pid)


def interfering_jobs(owned_group: int | None = None) -> list[dict[str, Any]]:
    jobs = []
    for path in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            pid = int(path.parent.name)
            if pid == os.getpid() or (owned_group is not None and os.getpgid(pid) == owned_group):
                continue
            argv = path.read_bytes().decode(errors="replace").split("\0")
            executable = Path(argv[0]).name
            busy = executable in {"cargo", "rustc"} or (
                executable in {"dart", "flutter"} and any(v in {"test", "compile"} for v in argv[1:])
            ) or (executable.startswith("python") and any("mutations" in Path(v).name for v in argv[1:2]))
            if busy:
                jobs.append({"pid": pid, "program": executable})
        except (OSError, ValueError, IndexError):
            continue
    return jobs


def execute(output: Path, manifest: dict[str, Any], runs: list[dict[str, Any]], command: list[str],
            root: Path, timeout_seconds: float) -> None:
    recorder = Recorder(output, manifest, runs)
    execution = manifest["execution"]
    execution.update(status="running", command=command, started_at_utc=datetime.now(timezone.utc).isoformat())
    write_manifest(output, manifest)
    process = None
    try:
        jobs = interfering_jobs()
        if jobs:
            manifest["overlap_detected"] = True
            execution["interfering_jobs"] = jobs
            raise compare.CampaignError("build, test or mutation jobs are running; campaign was not started")
        with (output / "driver.log").open("wb") as log:
            process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True, stdin=subprocess.DEVNULL,
                                       env={**os.environ, "CONNECTANUM_SKIP_NATIVE_BUILD": "1",
                                            "CONNECTANUM_BENCH_WAMP_REUSE_WORKER": "1"})
            execution["pid"] = process.pid
            deadline = time.monotonic() + timeout_seconds
            pending = b""
            reader = None
            next_check = 0.0
            try:
                while True:
                    if reader is None and (output / "driver-results.jsonl").exists():
                        reader = (output / "driver-results.jsonl").open("rb")
                    chunk = reader.read(65536) if reader is not None else b""
                    pending += chunk
                    while b"\n" in pending:
                        line, pending = pending.split(b"\n", 1)
                        recorder.append(line)
                    status = process.poll()
                    if status is not None and not chunk:
                        if pending:
                            raise compare.CampaignError("driver ended with a truncated JSONL report")
                        execution["driver_exit_code"] = status
                        if status != 0 or recorder.run_index != len(runs):
                            raise compare.CampaignError(f"driver exit {status}; completed {recorder.run_index}/{len(runs)} passes")
                        break
                    now = time.monotonic()
                    if now >= deadline:
                        raise compare.CampaignError("campaign execution deadline exceeded")
                    if now >= next_check:
                        jobs = interfering_jobs(process.pid)
                        if jobs:
                            manifest["overlap_detected"] = True
                            execution["interfering_jobs"] = jobs
                            raise compare.CampaignError("build, test or mutation job overlapped the campaign")
                        next_check = now + 2
                    if not chunk:
                        time.sleep(0.05)
            finally:
                if reader is not None:
                    reader.close()
        execution["status"] = "completed"
    except BaseException as error:
        execution.update(status="interrupted" if isinstance(error, KeyboardInterrupt) else "failed", error=str(error))
        raise
    finally:
        try:
            if process is not None:
                execution["process_group_stopped"] = stop_process_group(process)
                execution["driver_exit_code"] = process.returncode
                if not execution["process_group_stopped"]:
                    execution["status"] = "failed"
        except BaseException as error:
            execution.update(status="failed", teardown_error=str(error), process_group_stopped=False)
            raise
        finally:
            execution["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
            write_manifest(output, manifest)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New directory; existing output is never overwritten")
    parser.add_argument("--driver", required=True, type=Path, help="Prebuilt release http_stream executable")
    parser.add_argument("--native-lib", required=True, type=Path)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--router-config", type=Path, default=ROOT / "native/bench/bench_router.json")
    parser.add_argument("--control-base", default="https://127.0.0.1:8080/bench")
    parser.add_argument("--policy", type=Path, default=POLICY)
    parser.add_argument("--runner-image", required=True)
    parser.add_argument("--seed", type=int, default=20261005)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--repetitions", type=int, default=7)
    parser.add_argument("--duration-ms", type=int, default=10000)
    parser.add_argument("--samples", type=int, default=1000)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--in-flight", type=int, default=1)
    parser.add_argument("--router-workers", type=int, default=1)
    parser.add_argument("--native-threads", type=int, default=1)
    parser.add_argument("--workload-timeout-ms", type=int, default=300000)
    parser.add_argument("--campaign-timeout-seconds", type=float)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--diagnostic", action="store_true", help="Allow short/subset/dirty-tree runs; never acceptance evidence")
    parser.add_argument("--case", action="append", default=[], help="Exact case ID; requires --diagnostic")
    args = parser.parse_args(argv)
    output = args.output.resolve()
    manifest = None
    try:
        policy = json.loads(args.policy.read_text())
        for name in ("warmups", "repetitions", "duration_ms", "samples", "concurrency", "in_flight", "router_workers", "native_threads", "workload_timeout_ms"):
            if getattr(args, name) <= 0:
                raise compare.CampaignError(f"--{name.replace('_', '-')} must be positive")
        if not args.seed or (args.campaign_timeout_seconds is not None and (
            not math.isfinite(args.campaign_timeout_seconds) or args.campaign_timeout_seconds <= 0
        )):
            raise compare.CampaignError("seed must be nonzero and campaign deadline must be positive")
        cases = primary_cases()
        if args.case:
            if not args.diagnostic or not set(args.case) <= {case["id"] for case in cases}:
                raise compare.CampaignError("case selection requires --diagnostic and exact primary case IDs")
            cases = [case for case in cases if case["id"] in args.case]
        if not args.diagnostic:
            if platform.system() != "Linux":
                raise compare.CampaignError("primary acceptance campaigns require Linux process metrics")
            for name, key in (("warmups", "minimum_warmup_runs"), ("repetitions", "minimum_repetitions"), ("duration_ms", "minimum_duration_ms"), ("samples", "minimum_samples_per_run")):
                if getattr(args, name) < policy[key]:
                    raise compare.CampaignError(f"--{name.replace('_', '-')} is below the unchanged policy")
            if sha256(args.policy) != sha256(POLICY):
                raise compare.CampaignError("primary campaigns require the checked-in acceptance policy")
            if command_output(["git", "status", "--porcelain"]):
                raise compare.CampaignError("primary campaigns require a clean working tree")
        for name in ("driver", "native_lib", "router_config", "policy"):
            path = getattr(args, name).resolve(strict=True)
            if not path.is_file():
                raise compare.CampaignError(f"{name} is not a file")
            setattr(args, name, path)
        with LOCK.open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise compare.CampaignError("another WAMP campaign holds the host lock") from error
            output.mkdir(parents=True, exist_ok=False)
            runs = schedule(cases, args.warmups, args.repetitions, args.seed)
            scenario_hash = write_scenarios(output, cases, runs, args.duration_ms, args.samples, args.concurrency, args.in_flight)
            manifest = {
                "schema_version": 1, "order_seed": args.seed, "overlap_detected": False,
                "cases": cases, "warmup_runs": [r for r in runs if r["kind"] == "warmup"],
                "measured_runs": [r for r in runs if r["kind"] == "measured"],
                "metadata": metadata(ROOT, args, scenario_hash), "execution": {"status": "planned"},
            }
            inputs = output / "inputs"
            inputs.mkdir()
            for name, path in (("router_config.json", args.router_config), ("policy.json", args.policy)):
                shutil.copyfile(path, inputs / name)
            for name in manifest["metadata"]["lockfiles_sha256"]:
                destination = inputs / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, destination)
            write_manifest(output, manifest)
            if args.prepare_only:
                print(f"Prepared {len(cases)} cases; no benchmark executed: {output}")
                return 0
            command = [str(args.driver), "--dart", args.dart, "--native-lib", str(args.native_lib),
                       "--router-config", str(args.router_config), "--control-base", args.control_base,
                       "--scenario", str(output / "scenarios"), "--results", str(output / "driver-results.jsonl"),
                       "--results-only", "--skip-wamp-worker-aot", "--collect-wamp-vm-metrics",
                       "--router-worker-counts", str(args.router_workers), "--native-runtime-thread-counts", str(args.native_threads),
                       "--workload-timeout-ms", str(args.workload_timeout_ms)]
            timeout = args.campaign_timeout_seconds or (len(cases) * 3 * len(runs) * args.workload_timeout_ms / 1000 + 120)
            execute(output, manifest, runs, command, ROOT, timeout)
            after = metadata(ROOT, args, scenario_directory_hash(output / "scenarios"))
            keys = ("source_revision", "working_tree_clean", "scenario_sha256", "lockfiles_sha256", "artifacts_sha256", "router_config_sha256", "policy_sha256")
            manifest["metadata"]["inputs_unchanged"] = all(after[key] == manifest["metadata"][key] for key in keys)
            manifest["metadata"]["system_state_after"] = system_state()
            write_manifest(output, manifest)
            result = compare.evaluate_campaign(manifest, output, policy)
            (output / "comparison.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
            (output / "comparison.md").write_text(compare.render_markdown(result))
            print(f"Comparison {result['status']}: {output / 'comparison.md'}")
            return 0 if result["status"] == "passed" else 1
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        if manifest is not None:
            (output / "comparison-error.txt").write_text(f"Campaign incomplete or invalid: {error}\n")
        print(f"WAMP campaign failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
