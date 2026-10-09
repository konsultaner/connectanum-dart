#!/usr/bin/env python3
"""Exercise the negotiated FlatBuffers profile with an independent Python peer.

The peer uses generated readers/builders and independent transport/CBOR runtimes.
It is not an Autobahn session implementation. Bare upstream frames are rejected
by the current strict profile; this check does not implement upstream-subset mode.
"""

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

from generate_wamp_flatbuffers import ROOT, SCHEMA, verify_inputs


CHECKS = [
    "upstream-only-peer-rejected-before-credentials",
    "nonadvertising-peer-abort-before-credentials",
    "invalid-ticket-abort",
    "distinct-ticket-sessions",
    "fragmented-rpc-empty-small-large-wide-id-utf8-binary-kwargs",
    "progressive-and-final-result",
    "callee-error-remaps-request",
    "killnowait-cancel-interrupt",
    "acknowledged-pubsub",
    "unsubscribe-unregister-missing-procedure",
    "goodbye",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_router(command, environment, timeout=120):
    """Bound the owned router and peer process group on POSIX runners."""
    child = subprocess.Popen(
        command, cwd=ROOT, env=environment,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        start_new_session=os.name == "posix",
    )
    try:
        output, _ = child.communicate(timeout=timeout)
        return child.returncode, output
    except BaseException:
        if os.name == "posix":
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        else:
            child.terminate()
        try:
            child.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            else:
                child.kill()
            child.communicate(timeout=5)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flatc", default=os.environ.get("FLATC", "flatc"))
    parser.add_argument("--native-library", default=os.environ.get("CONNECTANUM_NATIVE_LIB"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not __debug__:
        parser.error("Python assertions must be enabled")
    manifest = verify_inputs(ROOT)
    expected = {"flatbuffers": manifest["python_runtime"]["version"],
                "cbor2": "5.7.1", "websockets": "15.0.1"}
    versions = {name: importlib.metadata.version(name) for name in expected}
    if versions != expected:
        parser.error("Install the pinned tool/flatbuffers_peer_requirements.txt")
    actual = subprocess.check_output([args.flatc, "--version"], text=True).strip()
    if actual != "flatc version " + manifest["flatc"]:
        parser.error("Pinned flatc version required")
    if not args.native_library or not Path(args.native_library).is_file():
        parser.error("A built native library is required (--native-library)")
    native = Path(args.native_library).resolve()
    if args.output.exists():
        parser.error("Choose a fresh output directory")
    args.output.mkdir(parents=True)
    output = args.output.resolve()
    peer = ROOT / "tool/flatbuffers_live_peer.py"
    router = ROOT / "packages/connectanum_router/tool/flatbuffers_live_peer_router.dart"
    report = {
        "status": "running", "startedUnix": time.time(),
        "profile": "connectanum-metadata-v1", "upstreamRevision": manifest["upstream"]["revision"],
        "schemaSha256": sha(ROOT / SCHEMA / "wamp.fbs"),
        "manifestSha256": sha(ROOT / SCHEMA / "manifest.json"),
        "flatcVersion": actual, "runtimeVersions": versions,
        "nativeLibrary": str(native), "nativeLibrarySha256": sha(native),
        "peerSha256": sha(peer), "routerSha256": sha(router), "transports": {},
        "limitations": "Independent generated-schema peer, not Autobahn session compatibility, TLS, all-platform, performance, copy-count or upstream-subset acceptance.",
    }
    report_path = output / "report.json"

    def save():
        report_path.write_text(json.dumps(report, indent=2) + "\n")

    save()
    try:
        with tempfile.TemporaryDirectory(prefix="connectanum-flatbuffers-live-") as directory:
            generated = Path(directory) / "python"
            subprocess.run([args.flatc, "--python", "--python-typing", "--gen-all",
                            "-o", str(generated), str(ROOT / SCHEMA / "wamp.fbs")], check=True)
            report["generatedBindings"] = {
                str(p.relative_to(generated)): sha(p)
                for p in sorted(generated.rglob("*.py"))
            }
            save()
            for transport in ("rawsocket", "websocket"):
                command = ["dart", "--packages=.dart_tool/package_config.json", str(router),
                           sys.executable, str(peer), str(generated), transport]
                code, log = run_router(command, dict(os.environ, CONNECTANUM_NATIVE_LIB=str(native),
                                                    PYTHONDONTWRITEBYTECODE="1"))
                log_path = output / (transport + ".log")
                log_path.write_text(log)
                entry = {"exitCode": code, "logSha256": sha(log_path)}
                report["transports"][transport] = entry
                save()
                if code:
                    raise RuntimeError(f"{transport} peer failed; see {log_path}")
                results = []
                for line in log.splitlines():
                    try:
                        value = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if isinstance(value, dict) and value.get("schema") == report["profile"]:
                        results.append(value)
                if len(results) != 1:
                    raise RuntimeError(f"{transport} did not emit exactly one peer result")
                result = results[0]
                if (result.get("status") != "passed" or result.get("transport") != transport
                        or result.get("checks") != CHECKS
                        or result.get("flatbuffersRuntime") != versions["flatbuffers"]
                        or result.get("cborRuntime") != versions["cbor2"]
                        or result.get("websocketRuntime") != versions["websockets"]):
                    raise RuntimeError(f"{transport} result contract failed: {result!r}")
                entry["result"] = result
                save()
        if sha(native) != report["nativeLibrarySha256"]:
            raise RuntimeError("Native library changed during live verification")
        if sha(peer) != report["peerSha256"] or sha(router) != report["routerSha256"]:
            raise RuntimeError("Peer inputs changed during live verification")
        report["status"] = "passed"
    except BaseException as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        report["completedUnix"] = time.time()
        save()
    print(json.dumps({"status": report["status"], "profile": report["profile"],
                      "transports": list(report["transports"]), "report": str(report_path)}))


if __name__ == "__main__":
    main()
