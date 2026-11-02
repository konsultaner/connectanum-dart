#!/usr/bin/env python3
"""Small functional native-path controls, never original gate observations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import mqtt_dart_copy_probe as probe
import mqtt_copy_census_client as fresh
import mqtt_copy_census_support as support
import run_mqtt_dart_copy_census as census
import run_mqtt_benchmark_gate as gate


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stop(process):
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


def check(output, decoder_controls, baseline_receipt, runtime=None, fresh_client=False,
          ffi_census=False, body_nonce_base=194000000):
    if output.exists():
        raise ValueError("Never overwrite retained native controls")
    before = json.loads(baseline_receipt.read_text())
    library = Path(before["own_native"]).resolve()
    if (before["source"] != probe.SOURCE or before["test-fast_exit"] != 0 or
            Path(before["worktree"]).resolve() != probe.ROOT.resolve() or
            not library.is_relative_to(probe.ROOT / "native/transport/target") or
            digest(library) != before["own_native_sha256"]):
        raise ValueError("Only this checkout's verified own baseline library is permitted")
    for key in ("CONNECTANUM_NATIVE_RUNTIME_THREADS", "LD_PRELOAD", "LD_AUDIT",
                "DYLD_INSERT_LIBRARIES"):
        if os.environ.get(key) is not None:
            raise ValueError("Original automatic runtime/loader policy required: " + key)
    runtime = runtime or shutil.which("dartaotruntime")
    if runtime is None:
        raise ValueError("Provide --runtime from the same standard Dart SDK")
    compiler_version = subprocess.run(
        ["dart", "--version"], capture_output=True, text=True, check=True)
    runtime_version = subprocess.run(
        [str(runtime), "--version"], capture_output=True, text=True, check=True)
    compiler_identity = (compiler_version.stdout + compiler_version.stderr).strip()
    if (runtime_version.stdout + runtime_version.stderr).strip() != compiler_identity:
        raise ValueError("AOT runtime must equal the actual compiler SDK")
    shadows = {n: decoder_controls / n for n in ("original", "instrumented")}
    completion = json.loads((decoder_controls / "completion.json").read_text())
    if completion["source"] != probe.SOURCE or completion["preflight_passed"] is not True:
        raise ValueError("Real source/decoder controls must pass first")
    for directory in shadows.values():
        probe.verify_shadow(directory)
        probe.verify_workspace_packages(directory / "source")
    output.mkdir(parents=True)
    broker, client = output / "broker.aot", output / "client"
    generated_client = (fresh.write_client(shadows["original"] / "source") if fresh_client else None)
    for label, kind, source, destination, shadow in [
        ("broker", "aot-snapshot", "mqtt_native_router_server.dart", broker, "instrumented"),
        ("client", "exe", "mqtt_qos0.dart", client, "original"),
    ]:
        with (output / (label + "-compile.log")).open("w") as log:
            result = subprocess.run(
                ["dart", "compile", kind,
                 str(generated_client) if label == "client" and fresh_client else "benchmark/" + source,
                 "-o", str(destination)],
                cwd=shadows[shadow] / "source/packages/connectanum_router",
                stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError("Actual shadow/original " + label + " compilation failed")
    for directory in shadows.values():
        probe.verify_shadow(directory)
        probe.verify_workspace_packages(directory / "source")
    hashes = {"native": digest(library), "broker": digest(broker), "client": digest(client)}
    broker_library = library
    if ffi_census:
        native_dir = output / "native"
        native_dir.mkdir()
        actual = native_dir / "libct_ffi.so"
        shutil.copy2(library, actual)
        if digest(actual) != hashes["native"]:
            raise ValueError("Own native copy changed")
        broker_library = native_dir / "census.so"
        support.compile_shim(probe.ROOT / "tool/mqtt_ffi_census.c", native_dir, broker_library)
        hashes["shim"] = digest(broker_library)
    (output / "inputs.json").write_text(json.dumps({
        "source": probe.SOURCE, "diagnostic_only": True, "capture_ready": False,
        "native_source": "own unchanged fresh baseline; not a borrowed parent binary",
        "baseline_receipt_sha256": digest(baseline_receipt), "hashes": hashes,
        "SDK": compiler_identity, "AOT_runtime_sha256": digest(Path(runtime)),
        "fresh_per_publication_client": fresh_client,
        "independent_C_forwarding_counters": ffi_census,
        "fresh_body_nonce_base": body_nonce_base,
        "scope": "Functional controls only, no gate budget/window/sample or acceptance result.",
    }, indent=2) + "\n")
    observed = []
    # These 100-message fixtures are separate functional controls. They do not
    # change or supply rows to the future full five-profile count-only capture.
    for name, transport, mqtt_version, messages in [
        ("zero", "tcp", "311", 0),
        ("tcp311", "tcp", "311", 100),
        ("ws5", "ws", "5", 100),
    ]:
        directory = output / name
        directory.mkdir()
        target = directory / "counts.json"
        port = gate.available_port()
        env = gate.workload_environment({
            "messages_per_run": max(messages, 100), "payload_bytes": 128,
            "mqtt_version": mqtt_version, "subscribers": 1,
        }, transport)
        env.pop("CONNECTANUM_NATIVE_LIB", None)
        nonce = body_nonce_base + (1 if name == "tcp311" else 2)
        if fresh_client:
            env["MQTT_COPY_CENSUS_BODY_NONCE"] = str(nonce)
        broker_env = {**env, "CONNECTANUM_NATIVE_LIB": str(broker_library),
                      "CONNECTANUM_MQTT_DART_COPY_CENSUS_OUTPUT": str(target)}
        ffi_path = directory / "ffi-counts.json"
        if ffi_census:
            broker_env["CONNECTANUM_MQTT_CENSUS_OUTPUT"] = str(ffi_path)
        with (directory / "broker.log").open("w") as log:
            process = subprocess.Popen(
                [str(runtime), str(broker), str(port)], env=broker_env,
                stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
            primary = None
            try:
                gate.wait_for_listener(port, process)
                if messages:
                    result = subprocess.run([str(client), "127.0.0.1", str(port)], env=env,
                                            capture_output=True, text=True, timeout=60)
                    (directory / "client-stdout.log").write_text(result.stdout)
                    (directory / "client-stderr.log").write_text(result.stderr)
                    row = gate.checked_client_row(result, "functional-preflight-only", 1,
                                                  broker_log=directory / "broker.log")
                    if (row["sent"] != messages or row["received"] != messages or
                            row["received_per_subscriber"] != [messages] or
                            row["duplicates"] != 0 or row["payload_bytes"] != 128 or
                            row["mqtt_version"] != mqtt_version or
                            row["transport"] != transport or row["warmup"] != 100):
                        raise ValueError("Actual functional full-body delivery control failed")
                    if fresh_client and (row.get("fresh_body_nonce") != nonce or
                                         row.get("fresh_bodies_generated") != messages + 100):
                        raise ValueError("Fresh message/body/pattern producer not observed")
                    (directory / "client-row.json").write_text(json.dumps(row, indent=2) + "\n")
            except BaseException as error:
                primary = error
                (directory / "primary-error.txt").write_text(repr(error) + "\n")
                raise
            finally:
                try:
                    status = stop(process)
                    (directory / "broker-exit.txt").write_text(str(status) + "\n")
                    if status:
                        raise ValueError("Functional broker cleanup failed")
                except BaseException as cleanup:
                    (directory / "cleanup-error.txt").write_text(repr(cleanup) + "\n")
                    if primary is None:
                        raise
        values = json.loads(target.read_text())
        if (values["diagnostic_only"] is not True or
                values["kind"] != "mqtt_dart_logical_copy_requests"):
            raise ValueError("Missing actual instrumentation")
        counts = values["counts"]
        if len(counts) != 14 or any(type(v) is not int or v < 0 for v in counts.values()):
            raise ValueError("Malformed counters")
        if messages:
            if not all(counts[n] > 0 for n in [
                "native_poll_copy_requests", "native_poll_copy_bytes",
                "body_constructor_requests", "body_copy_bytes", "frames_completed",
            ]):
                raise ValueError("Actual native receive/decoder path not observed")
        elif any(counts.values()):
            raise ValueError("No-data native control must have zero logical copy requests")
        if ffi_census:
            ffi = json.loads(ffi_path.read_text())
            support.validate_counts(ffi)
            if messages:
                census.validate_dart_counts(values, ffi)
            elif ffi["poll_positive"] or ffi["poll_bytes"]:
                raise ValueError("Independent C no-data control must also be zero")
        observed.append({"fixture": name, "messages": messages, "counts": counts})
        prior = digest(target)
        # Exercise atomic freshness with the actual compiled CLI. This must
        # fail before native startup and leave the earlier evidence untouched.
        rejected = subprocess.run(
            [str(runtime), str(broker), str(gate.available_port())],
            env=broker_env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
        (directory / "existing-output-guard.log").write_text(rejected.stdout + rejected.stderr)
        (directory / "existing-output-guard-result.json").write_text(json.dumps({
            "exit": rejected.returncode, "prior_sha256": prior,
            "after_sha256": digest(target),
            "stdout_sha256": hashlib.sha256(rejected.stdout.encode()).hexdigest(),
            "stderr_sha256": hashlib.sha256(rejected.stderr.encode()).hexdigest(),
        }, indent=2) + "\n")
        if (rejected.returncode == 0 or digest(target) != prior or
                not any(name in rejected.stderr for name in
                        ("FileSystemException", "PathExistsException")) or
                str(target) not in rejected.stderr or
                "exists" not in rejected.stderr.lower() or
                "ready " in rejected.stdout):
            raise ValueError("Atomic evidence freshness guard failed")
    for directory in shadows.values():
        probe.verify_shadow(directory)
        probe.verify_workspace_packages(directory / "source")
    after = {"native": digest(library), "broker": digest(broker), "client": digest(client)}
    if ffi_census:
        after["shim"] = digest(broker_library)
        if digest(output / "native/libct_ffi.so") != hashes["native"]:
            raise ValueError("Own linked native bytes changed")
    if hashes != after:
        raise ValueError("Functional input binaries changed")
    if fresh_client and generated_client.read_bytes() != fresh.instrument(
            (shadows["original"] / "source" / fresh.CLIENT_SOURCE).read_bytes()):
        raise ValueError("Fresh client source changed")
    summary = {
        "source": probe.SOURCE, "functional_preflight_passed": True,
        "fixtures": observed, "binaries_sha256": hashes, "capture_ready": False,
        "fresh_per_publication_client": fresh_client,
        "independent_C_forwarding_counters": ffi_census,
        "scope": "Own native zero/positive receive and decoder, full-body functional "
                 "fixtures and actual CLI atomic-output guard. No timing/gate/cause "
                 "or acceptance claim; original numerical results never rerun.",
    }
    (output / "completion.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--decoder-controls", required=True, type=Path)
    parser.add_argument("--baseline-receipt", required=True, type=Path)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--fresh-client", action="store_true")
    parser.add_argument("--ffi-census", action="store_true")
    parser.add_argument("--body-nonce-base", type=int, default=194000000)
    args = parser.parse_args()
    print(json.dumps(check(args.output, args.decoder_controls,
                           args.baseline_receipt, args.runtime, args.fresh_client,
                           args.ffi_census, args.body_nonce_base), indent=2))


if __name__ == "__main__":
    main()
