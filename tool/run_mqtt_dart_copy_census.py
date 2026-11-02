#!/usr/bin/env python3
"""Count logical Dart copies on exact AD48 inputs; never a performance gate.

The shadow broker and fresh-body client are separately compiled. Actual original
native bytes are held constant; the original client/AOT are retained witnesses.
Whole-lifetime counters include startup, warmup and cleanup; constructor requests
are not physical heap allocations.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

import mqtt_dart_copy_probe as probe
import mqtt_copy_census_client as fresh
import mqtt_copy_census_support as support
import run_mqtt_benchmark_gate as gate

SOURCE_RUN = 41395075328
NATIVE = "c648757abcad4879611d7fa06774fe30ed377948ee55894a9f6f0e741fdf04b8"
CLIENT = "3020a016d00618264a0da6e15def15232bb0f0771c30bb4661dec0943159d0db"
PARENT_AOT = "296aa4f897e38bcd8b58095565b84f7a0f7acffc6acf42b0ed4cd14299a9fa87"
SDK = 'Dart SDK version: 3.13.1 (stable) (Tue Aug 18 01:00:59 2026 -0700) on "linux_x64"'
PROFILES = ("ws_sustained", "ws_v311_sustained", "sustained", "v311_sustained", "64k_sustained")
ARTIFACTS = {
    13119578041: ("mqtt-native-profile", "3a2948cbb1310ee49ec91de5bf8591c253325cf26fb96e8386d1361a1df9c25d"),
    13119975536: ("wamp-native-ppt-view-diagnostic-" + probe.SOURCE + "-1", "192aecf85ed064ac1c86dde07225b1c257374ddfc18ca9a138da8180ef196b81"),
}
COUNTERS = (
    "native_poll_copy_requests", "native_poll_copy_bytes",
    "body_constructor_requests", "body_constructor_requested_bytes",
    "zero_body_constructor_requests", "growth_constructor_requests",
    "growth_constructor_requested_bytes", "nonempty_growth_copy_requests",
    "growth_copy_bytes", "nonempty_body_copy_requests", "body_copy_bytes",
    "frames_completed", "completed_body_bytes", "nonempty_frames_completed",
)
TOOLS = (
    "tool/mqtt_dart_copy_probe.py", "tool/check_mqtt_dart_copy_probe.py",
    "tool/check_mqtt_dart_copy_native.py", "tool/test_mqtt_dart_copy_probe.py",
    "tool/mqtt_copy_census_support.py", "tool/mqtt_ffi_census.c",
    "tool/run_mqtt_dart_copy_census.py", "tool/test_mqtt_dart_copy_census.py",
    "tool/fetch_mqtt_dart_copy_inputs.py", "tool/mqtt_copy_census_client.py",
    ".github/workflows/mqtt-profile.yml",
)


def read(path):
    return json.loads(path.read_text())


def source_bytes(name):
    return subprocess.check_output(["git", "show", probe.SOURCE + ":" + name], cwd=probe.ROOT)


def budgets():
    values = {}
    for name in PROFILES:
        path = "tool/mqtt_native_" + name + "_benchmark_budget.json"
        encoded = source_bytes(path)
        if (probe.ROOT / path).read_bytes() != encoded:
            raise ValueError("Original budget changed")
        budget = json.loads(encoded)
        if budget["repetitions"] != 5 or budget.get("subscribers", 1) != 1:
            raise ValueError("All original repetitions/subscribers required")
        values[name] = budget
    if sum(v["messages_per_run"] * 5 for v in values.values()) != 4025000:
        raise ValueError("Original full workload inventory changed")
    return values


def verify_inputs(root):
    run = read(root / "source-run.json")
    if (run["id"] != SOURCE_RUN or run["head_sha"] != probe.SOURCE or
            run["run_attempt"] != 1 or run["status"] != "completed" or
            run["conclusion"] != "failure"):
        raise ValueError("Wrong completed original source/run/attempt")
    jobs = read(root / "source-jobs.json")
    permitted = {125114532993: "MQTT QoS 0 interoperability and benchmark gate",
                 125146079113: "Full Verify"}
    failed = {j["databaseId"]: j["name"] for j in jobs["jobs"] if j["conclusion"] != "success"}
    if (jobs["headSha"] != probe.SOURCE or jobs["status"] != "completed" or
            jobs["conclusion"] != "failure" or len(jobs["jobs"]) != 39 or
            any(j["status"] != "completed" for j in jobs["jobs"]) or failed != permitted or
            any(j["conclusion"] != "failure" for j in jobs["jobs"] if j["databaseId"] in permitted)):
        raise ValueError("Resolve any additional correctness/setup CI failure first")
    original = next(j for j in jobs["jobs"] if j["databaseId"] == 125114532993)
    if (original["startedAt"] != "2026-11-02T05:37:10Z" or
            original["completedAt"] != "2026-11-02T05:55:15Z"):
        raise ValueError("Original numerical execution changed")
    artifacts = read(root / "source-artifacts.json")
    if isinstance(artifacts, dict):
        artifacts = artifacts["artifacts"]
    for ident, (name, wanted) in ARTIFACTS.items():
        artifact = next(a for a in artifacts if a["id"] == ident)
        expected_run = SOURCE_RUN if ident == 13119578041 else 41395078952
        if (artifact["name"] != name or artifact["digest"] != "sha256:" + wanted or
                artifact["expired"] or
                artifact["workflow_run"]["id"] != expected_run or
                artifact["workflow_run"]["head_sha"] != probe.SOURCE or
                support.digest(root / (str(ident) + ".zip")) != wanted):
            raise ValueError("Original artifact identity/ZIP changed")
    profile = root / "mqtt-native-profile/ws_sustained"
    metadata = read(profile / "provenance.json")
    receipt = read(profile / "report-provenance.json")
    info = metadata["provenance"]
    expected = {"libct_ffi.so": NATIVE, "mqtt-client": CLIENT, "mqtt-broker.aot": PARENT_AOT}
    if (metadata["diagnosticOnly"] is not True or metadata["runtimeVersion"] != SDK or
            info["git_commit"] != probe.SOURCE or info["git_dirty"] or
            info["native_lib_sha256"] != NATIVE or info["client_exe_sha256"] != CLIENT or
            info["broker_exe_sha256"] != PARENT_AOT or
            support.digest(profile / "provenance.json") != receipt["sourceProvenanceSha256"]):
        raise ValueError("Original profile source/runtime identity changed")
    for name, wanted in expected.items():
        if support.digest(profile / name) != wanted:
            raise ValueError("Actual original native/client/AOT bytes changed")
    copy = root / "copy"
    inputs = read(copy / "wamp-native-ppt-view/inputs.json")
    if (inputs["head"] != probe.SOURCE or inputs["library_sha256"] != NATIVE or
            inputs["archive_sha256"] != probe.ARCHIVE_SHA256):
        raise ValueError("Own source/copy binding changed")
    lock_root = copy / "wamp-native-ppt-copy-proof/protocol/campaign/inputs"
    for name, wanted in probe.LOCKS.items():
        if support.digest(lock_root / name) != wanted:
            raise ValueError("Original lock binding changed")
    if inputs["source_inputs"]["pubspec.lock"] != probe.LOCKS["pubspec.lock"]:
        raise ValueError("Original resolved Dart lock receipt changed")
    if (probe.ROOT / "tool/run_mqtt_benchmark_gate.py").read_bytes() != source_bytes("tool/run_mqtt_benchmark_gate.py"):
        raise ValueError("Original workload helper changed")
    return profile, lock_root


def verify_declaration(declaration):
    if (declaration.get("capture_ready") is not True or
            declaration.get("runtime_source") != probe.SOURCE or
            declaration.get("source_run") != SOURCE_RUN or
            declaration.get("profiles") != list(PROFILES) or
            declaration.get("rows_required") != 25 or
            declaration.get("fresh_verified_deliveries_required") != 4025000 or
            declaration.get("native_sha256") != NATIVE or
            declaration.get("original_client_witness_sha256") != CLIENT or
            declaration.get("client_mode") != "fresh-per-publication-v1" or
            type(declaration.get("fresh_body_nonce_base")) is not int or
            declaration["fresh_body_nonce_base"] != 196000000):
        raise ValueError("Capture not ready or wrong predeclaration")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=probe.ROOT, text=True).strip()
    if (declaration.get("tool_revision") != head or
            subprocess.check_output(["git", "status", "--porcelain"], cwd=probe.ROOT)):
        raise ValueError("Frozen clean declared tool revision required")
    expected = {name: support.digest(probe.ROOT / name) for name in TOOLS}
    if declaration.get("tool_sha256") != expected:
        raise ValueError("Declared tool bytes changed")
    proof = declaration.get("own_canonical", {})
    if (proof.get("head") != head or proof.get("complete_pass") is not True or
            not all(isinstance(proof.get(n), str) and len(proof[n]) == 64 for n in
                    ("log_sha256", "receipt_sha256", "native_sha256", "tree_sha256"))):
        raise ValueError("Own frozen tooling canonical required before capture")
    if (declaration.get("controls_passed") is not True or
            declaration.get("root_review_complete") is not True or
            not all(isinstance(declaration.get(n), str) and len(declaration[n]) == 64 for n in
                    ("controls_receipt_sha256", "root_review_sha256"))):
        raise ValueError("Completed real controls and independent root review required")
    # This tools-only child must have exactly the frozen original runtime.
    changed = subprocess.check_output(
        ["git", "diff", "--name-only", probe.SOURCE, "HEAD", "--", "packages", "native", "bin"],
        cwd=probe.ROOT, text=True)
    if changed:
        raise ValueError("Tools-only diagnostic cannot change runtime/native/scripts")


def validate_dart_counts(value, ffi):
    if (value.get("diagnostic_only") is not True or
            value.get("kind") != "mqtt_dart_logical_copy_requests"):
        raise ValueError("Missing logical-request label")
    counts = value["counts"]
    if set(counts) != set(COUNTERS) or any(type(v) is not int or v < 0 for v in counts.values()):
        raise ValueError("Malformed logical request counters")
    if (counts["native_poll_copy_requests"] != ffi["poll_positive"] or
            counts["native_poll_copy_bytes"] != ffi["poll_bytes"]):
        raise ValueError("Actual Dart/native poll conservation failed")
    # The original native API uses negative terminal polls to close peers;
    # whole-lifetime error counts remain in the evidence, never recast as copies.
    # Delivery/integrity and cleanup are verified separately, as in the original
    # forwarding census. Do not invent an error-free-lifetime acceptance gate.
    if not ffi["send_calls"] or not ffi["arm_calls"]:
        raise ValueError("Actual native send/poll/arm control failed")
    bounds = ffi["size_upper_bounds"]
    lower = [1, *[n + 1 for n in bounds[:-1]]]
    if not (sum(n * c for n, c in zip(lower, ffi["poll_sizes"])) <= ffi["poll_bytes"] <=
            sum(n * c for n, c in zip(bounds, ffi["poll_sizes"]))):
        raise ValueError("Native histogram byte conservation failed")
    if (counts["body_constructor_requests"] != counts["frames_completed"] or
            counts["frames_completed"] - counts["zero_body_constructor_requests"] != counts["nonempty_frames_completed"] or
            counts["body_copy_bytes"] != counts["completed_body_bytes"] or
            counts["completed_body_bytes"] > counts["native_poll_copy_bytes"] or
            counts["growth_copy_bytes"] > counts["growth_constructor_requested_bytes"] or
            counts["nonempty_growth_copy_requests"] > counts["growth_constructor_requests"]):
        raise ValueError("Decoder body/frame/request conservation failed")
    if not all(counts[n] > 0 for n in ("native_poll_copy_requests", "body_copy_bytes", "frames_completed")):
        raise ValueError("Actual owned native receive/decoder not observed")


def check_environment():
    if platform.system() != "Linux":
        raise ValueError("Linux retained original bytes required")
    for name in ("CONNECTANUM_NATIVE_RUNTIME_THREADS", "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT"):
        if name in os.environ:
            raise ValueError("Original automatic worker/loader policy required")
    for command in ("dart", "dartaotruntime"):
        result = subprocess.run([command, "--version"], capture_output=True, text=True, check=True)
        if (result.stdout + result.stderr).strip() != SDK:
            raise ValueError("Actual original standard Dart SDK required")


def capture(inputs, output, declaration_path):
    declaration = read(declaration_path)
    verify_declaration(declaration)
    check_environment()
    profile, lock_root = verify_inputs(inputs)
    original_budgets = budgets()
    if output.exists():
        raise ValueError("Never overwrite any retained output, including partial failures")
    shadow = output / "shadow"
    source = probe.prepare(shadow, lock_root)
    probe.verify_shadow(shadow)
    broker = output / "instrumented-broker.aot"
    with (output / "compile.log").open("w") as stream:
        subprocess.run(["dart", "pub", "get", "--enforce-lockfile"], cwd=source,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
        probe.verify_shadow(shadow)
        probe.verify_workspace_packages(source)
        subprocess.run(["dart", "compile", "aot-snapshot", "benchmark/mqtt_native_router_server.dart",
                        "-o", str(broker)], cwd=source / "packages/connectanum_router",
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    probe.verify_shadow(shadow)
    probe.verify_workspace_packages(source)
    client_shadow = output / "client-shadow"
    client_source = probe.prepare(client_shadow, lock_root, original=True)
    with (output / "client-compile.log").open("w") as stream:
        subprocess.run(["dart", "pub", "get", "--enforce-lockfile"], cwd=client_source,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
        fresh_path = fresh.write_client(client_source)
        client = output / "fresh-client"
        subprocess.run(["dart", "compile", "exe", str(fresh_path), "-o", str(client)],
                       cwd=client_source, stdout=stream, stderr=subprocess.STDOUT, check=True)
    probe.verify_shadow(client_shadow)
    probe.verify_workspace_packages(client_source)
    native_dir = output / "native"
    native_dir.mkdir()
    native = native_dir / "libct_ffi.so"
    shutil.copy2(profile / "libct_ffi.so", native)
    shutil.copy2(profile / "mqtt-client", output / "original-client-witness")
    # The original uninstrumented AOT is a retained provenance witness only.
    shutil.copy2(profile / "mqtt-broker.aot", output / "original-broker-witness.aot")
    if support.digest(native) != NATIVE or support.digest(output / "original-client-witness") != CLIENT:
        raise ValueError("Retained actual byte copy changed")
    shim_source = probe.ROOT / "tool/mqtt_ffi_census.c"
    shim = native_dir / "mqtt-census.so"
    support.compile_shim(shim_source, native_dir, shim)
    linked = subprocess.check_output(["ldd", str(shim)], text=True)
    if str(native) not in linked:
        raise ValueError("Shim is not linked to actual retained original native")
    (output / "linked-libraries.txt").write_text(linked)
    binaries = {str(p.relative_to(output)): support.digest(p) for p in (broker, native, client, shim)}
    provenance = {"diagnostic_only": True, "runtime_source": probe.SOURCE, "source_run": SOURCE_RUN,
                  "tool_revision": declaration["tool_revision"], "binaries_sha256": binaries,
                  "declaration_sha256": support.digest(declaration_path), "SDK": SDK,
                  "fresh_client_source_sha256": support.digest(fresh_path),
                  "original_client_witness_sha256": CLIENT,
                  "client_mode": "fresh-per-publication-v1",
                  "cpu_model": gate.cpu_model(), "rows_required": 25,
                  "fresh_verified_deliveries_required": 4025000,
                  "scope": "Logical constructor/copy requests; whole broker life including warmup/cleanup. Not heap allocations, RSS, timing, causal repair, gate retry or strict acceptance."}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    shutil.copy2(declaration_path, output / "predeclaration.json")
    rows = []
    for name, budget in original_budgets.items():
        (output / (name + "-budget.json")).write_text(json.dumps(budget, indent=2) + "\n")
        for repeat in range(1, 6):
            prefix = name + "-" + str(repeat)
            env = gate.workload_environment(budget, budget.get("transport", "tcp"))
            nonce = declaration["fresh_body_nonce_base"] + len(rows) + 1
            env["MQTT_COPY_CENSUS_BODY_NONCE"] = str(nonce)
            broker_env = {**env, "CONNECTANUM_NATIVE_LIB": str(shim),
                          "CONNECTANUM_MQTT_CENSUS_OUTPUT": str(output / (prefix + "-ffi.json")),
                          "CONNECTANUM_MQTT_DART_COPY_CENSUS_OUTPUT": str(output / (prefix + "-dart.json"))}
            port = gate.available_port()
            primary = None
            with (output / (prefix + "-broker.log")).open("w") as stream:
                process = subprocess.Popen(["dartaotruntime", str(broker), str(port)], env=broker_env,
                                           stdin=subprocess.PIPE, stdout=stream, stderr=subprocess.STDOUT)
                try:
                    gate.wait_for_listener(port, process)
                    result, _ = gate.run_client_with_cpu(client, port, env)
                    (output / (prefix + "-stdout.log")).write_text(result.stdout)
                    (output / (prefix + "-stderr.log")).write_text(result.stderr)
                    row = gate.checked_client_row(result, "count-only-diagnostic", repeat,
                                                  broker_log=output / (prefix + "-broker.log"))
                    support.validate_row(row, budget)
                    if (row.get("fresh_body_nonce") != nonce or
                            row.get("fresh_bodies_generated") != budget["messages_per_run"] + 100):
                        raise ValueError("Fresh body/pattern production or nonce inventory changed")
                    row.update(profile_key=name, run=repeat)
                    rows.append(row)
                    (output / "raw.jsonl").write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
                except BaseException as error:
                    primary = error
                    (output / (prefix + "-primary-error.txt")).write_text(repr(error) + "\n")
                    if isinstance(error, subprocess.TimeoutExpired):
                        for kind in ("stdout", "stderr"):
                            value = getattr(error, kind, None)
                            if value is not None:
                                if isinstance(value, bytes):
                                    value = value.decode("utf8", errors="replace")
                                (output / (prefix + "-" + kind + ".log")).write_text(value)
                    raise
                finally:
                    try:
                        status = support.stop_broker(process)
                        (output / (prefix + "-broker-exit.txt")).write_text(str(status) + "\n")
                        if status:
                            raise ValueError("Actual broker/counter cleanup failed")
                    except BaseException as error:
                        (output / (prefix + "-cleanup-error.txt")).write_text(repr(error) + "\n")
                        if primary is None:
                            raise
            ffi = read(output / (prefix + "-ffi.json"))
            support.validate_counts(ffi)
            validate_dart_counts(read(output / (prefix + "-dart.json")), ffi)
            print(prefix, "complete", flush=True)
    verify_inputs(inputs)
    verify_declaration(declaration)
    probe.verify_shadow(shadow)
    probe.verify_workspace_packages(source)
    probe.verify_shadow(client_shadow)
    probe.verify_workspace_packages(client_source)
    if fresh_path.read_bytes() != fresh.instrument((client_source / fresh.CLIENT_SOURCE).read_bytes()):
        raise ValueError("Measured fresh client source changed")
    if budgets() != original_budgets or any(support.digest(output / p) != h for p, h in binaries.items()):
        raise ValueError("Inputs changed during capture")
    if len(rows) != 25 or sum(r["received"] for r in rows) != 4025000:
        raise ValueError("Incomplete predeclared whole capture")
    if ([(r["profile_key"], r["run"]) for r in rows] !=
            [(name, repeat) for name in PROFILES for repeat in range(1, 6)] or
            [r["fresh_body_nonce"] for r in rows] != list(range(196000001, 196000026))):
        raise ValueError("Complete original profile/order/fresh nonce inventory changed")
    (output / "completion.json").write_text(json.dumps({
        "complete": True, "rows": 25, "fresh_verified_deliveries": 4025000,
        "all_original_inputs_unchanged": True, "diagnostic_only": True,
    }, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--declaration", type=Path, required=True)
    args = parser.parse_args()
    capture(args.inputs.resolve(), args.output.resolve(), args.declaration.resolve())


if __name__ == "__main__":
    main()
