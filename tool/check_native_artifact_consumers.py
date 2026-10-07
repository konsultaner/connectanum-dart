#!/usr/bin/env python3
"""Exercise public profiles using only the production library in a native bundle."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PROFILES = (
    ("connectanum_client", "test/transport/native/flatbuffers_profile_test.dart", 10),
    ("connectanum_client", "test/transport/flatbuffers_transport_profile_vm_test.dart", 22),
    ("connectanum_router", "test/router_flatbuffers_native_test.dart", 2),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unpack_library(
    archive: Path, checksum: Path, manifest_path: Path,
    expected_commit: str, output: Path,
) -> tuple[dict, Path]:
    checksum_fields = checksum.read_text(encoding="utf-8").split()
    if checksum_fields != [sha256(archive), archive.name]:
        raise ValueError("archive checksum or filename does not match")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1 or manifest.get("git_commit") != expected_commit:
        raise ValueError("manifest does not identify the expected source commit")
    stem = manifest.get("artifact", "")
    library_name = manifest.get("library_file", "")
    expected_name = {
        "linux": "libct_ffi.so", "darwin": "libct_ffi.dylib", "win32": "ct_ffi.dll",
    }.get(sys.platform)
    if not re.fullmatch(r"ct-ffi-[A-Za-z0-9_-]+", stem) or library_name != expected_name:
        raise ValueError("invalid artifact name or library for this host")
    if archive.name != f"{stem}.tar.gz":
        raise ValueError("archive name does not match its manifest")
    with tarfile.open(archive, "r:gz") as bundle:
        for name in (f"{stem}/manifest.json", f"{stem}/{library_name}"):
            members = [member for member in bundle.getmembers() if member.name == name]
            if len(members) != 1 or not members[0].isfile():
                raise ValueError(f"bundle must contain one regular file: {name}")
        embedded = bundle.extractfile(f"{stem}/manifest.json")
        assert embedded is not None
        if json.load(embedded) != manifest:
            raise ValueError("bundled and detached manifests differ")
        contents = bundle.extractfile(f"{stem}/{library_name}")
        assert contents is not None
        library_dir = Path(tempfile.mkdtemp(prefix="library-", dir=output))
        library = library_dir / library_name
        library.write_bytes(contents.read())
    return manifest, library.resolve()


def profile_results(log: str, expected_cases: int) -> dict:
    started = set()
    completed: dict[int, dict] = {}
    done = []
    errors = []
    for line in log.splitlines():
        # Build hooks may precede the first JSON event on the same line.
        start = line.find("{")
        if start < 0:
            continue
        try:
            event = json.loads(line[start:])
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "testStart":
            test_id = event["test"]["id"]
            if test_id in started:
                raise ValueError("duplicate test start")
            started.add(test_id)
        elif event.get("type") == "testDone":
            test_id = event["testID"]
            if test_id in completed:
                raise ValueError("duplicate test completion")
            completed[test_id] = event
        elif event.get("type") == "done":
            done.append(event)
        elif event.get("type") == "error":
            errors.append(event)
    public = [event for event in completed.values() if event.get("hidden") is False]
    if (len(done) != 1 or done[0].get("success") is not True or errors
            or started != completed.keys()
            or len(public) != expected_cases
            or any(event.get("result") != "success" or event.get("skipped") is not False
                   or type(event.get("hidden")) is not bool
                   for event in completed.values())):
        raise ValueError("profile has failed, skipped, omitted or unfinished cases")
    return {"passed_cases": len(public), "skipped_cases": 0, "runner_success": True}


def audit_production_library(library: Path) -> int:
    loaded = ctypes.CDLL(str(library))
    for symbol in ("ct_transport_copy_metrics_snapshot", "ct_transport_copy_metrics_snapshot_v2",
                   "ct_rustls_copy_metrics_snapshot"):
        getattr(loaded, symbol)
    test_symbols = set()
    for source in (ROOT / "native/transport/ct_ffi/src").rglob("*.rs"):
        test_symbols.update(re.findall(r'pub\s+extern\s+"C"\s+fn\s+(ct_test_\w+)\s*\(', source.read_text()))
    if not test_symbols:
        raise ValueError("no test-oracle inventory found")
    for symbol in sorted(test_symbols):
        if hasattr(loaded, symbol):
            raise ValueError(f"production bundle exports test oracle {symbol}")
    return len(test_symbols)


def audit_rustls_snapshot_abi(library: Path) -> dict:
    """Exercise the partial snapshot ABI before this fresh process starts TLS."""
    fields = ("outbound_chunk_copy_bytes_total", "queue_read_copy_bytes_total",
              "deframer_append_copy_bytes_total", "deframer_move_copy_bytes_total",
              "record_buffer_copy_bytes_total", "record_append_copy_bytes_total")

    class Snapshot(ctypes.Structure):
        _fields_ = [(name, ctypes.c_uint64) for name in fields]

    class Guarded(ctypes.Structure):
        _fields_ = [("head", ctypes.c_uint64), ("snapshot", Snapshot),
                    ("tail", ctypes.c_uint64)]

    if (ctypes.sizeof(Snapshot) != 48 or ctypes.alignment(Snapshot) != 8
            or Guarded.snapshot.offset != 8 or Guarded.tail.offset != 56):
        raise ValueError("partial Rustls snapshot layout differs from its native ABI")
    loaded = ctypes.CDLL(str(library))
    snapshot = loaded.ct_rustls_copy_metrics_snapshot
    snapshot.argtypes = [ctypes.POINTER(Snapshot)]
    snapshot.restype = ctypes.c_int32
    null_result = snapshot(None)
    if null_result != -4:
        raise ValueError("partial Rustls snapshot must reject a null output")
    guarded = Guarded()
    guarded.head = 0x123456789abcdef0
    guarded.tail = 0xfedcba9876543210
    ctypes.memset(ctypes.byref(guarded, Guarded.snapshot.offset), 0xa5, 48)
    if snapshot(ctypes.byref(guarded.snapshot)) != 0:
        raise ValueError("partial Rustls snapshot call failed")
    if guarded.head != 0x123456789abcdef0 or guarded.tail != 0xfedcba9876543210:
        raise ValueError("partial Rustls snapshot overwrote its surrounding guards")
    counters = {name: getattr(guarded.snapshot, name) for name in fields}
    if any(counters.values()):
        raise ValueError("fresh-process partial Rustls counters were not written as zero")
    return {"bytes": 48, "alignment": 8, "null_result": null_result,
            "head_tail_unchanged": True, "initial_counters": counters}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--checksum", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report: dict = {"schema_version": 1, "expected_commit": args.expected_commit,
                    "runtime_acceptance": False, "profiles": []}
    try:
        manifest, library = unpack_library(args.archive, args.checksum, args.manifest,
                                           args.expected_commit, output)
        report.update({"manifest": manifest, "archive_sha256": sha256(args.archive),
                       "library_sha256": sha256(library), "library": str(library),
                       "absent_test_oracles": audit_production_library(library)})
        report["partial_rustls_snapshot_abi"] = audit_rustls_snapshot_abi(library)
        dart = shutil.which("dart")
        if not dart:
            raise ValueError("Dart executable unavailable")
        # Windows must launch the executable rather than a shell wrapper.
        if sys.platform == "win32" and Path(dart).suffix.lower() in (".bat", ".cmd"):
            dart = str(Path(dart).with_suffix(".exe"))
            if not Path(dart).is_file():
                raise ValueError("Dart Windows executable unavailable")
        environment = {**os.environ, "CONNECTANUM_NATIVE_LIB": str(library),
                       "CONNECTANUM_SKIP_NATIVE_BUILD": "true",
                       "CONNECTANUM_FORWARD_NATIVE_PUBLISH": "1"}
        for index, (package, test_file, cases) in enumerate(PROFILES, 1):
            command = [dart, "test", "--reporter=json", "--exclude-tags=ffi-owner-oracles", test_file]
            log = output / f"profile-{index}.jsonl"
            try:
                result = subprocess.run(command, cwd=ROOT / "packages" / package,
                                        env=environment, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                                        errors="replace", timeout=240)
            except subprocess.TimeoutExpired as error:
                partial = error.stdout or b""
                log.write_text(partial.decode("utf-8", errors="replace")
                               if isinstance(partial, bytes) else partial, encoding="utf-8")
                report["profiles"].append({"package": package, "file": test_file,
                                           "command": command, "timed_out": True,
                                           "log": log.name, "log_sha256": sha256(log)})
                raise
            log.write_text(result.stdout, encoding="utf-8")
            record = {"package": package, "file": test_file, "command": command,
                      "exit": result.returncode, "log": log.name, "log_sha256": sha256(log)}
            report["profiles"].append(record)
            if result.returncode != 0:
                print(result.stdout, file=sys.stderr)
                raise ValueError(f"{package}/{test_file} exits {result.returncode}")
            record.update(profile_results(result.stdout, cases))
            if sha256(library) != report["library_sha256"]:
                raise ValueError("packaged library changed during consumer tests")
            print(f"{package}/{test_file}: {cases} public cases passed")
        report["runtime_acceptance"] = True
        return 0
    except (ValueError, OSError, AttributeError, TypeError, tarfile.TarError,
            subprocess.TimeoutExpired, KeyError) as error:
        report["error"] = str(error)
        print(f"Native artifact consumer check failed: {error}", file=sys.stderr)
        return 1
    finally:
        (output / "consumer-proof.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
