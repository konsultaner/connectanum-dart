"""Matched original file profiles; advisory, not a substitute for all gates."""
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path

root = Path.cwd()
out = root / "out/native-ws-matched"
out.mkdir(parents=True, exist_ok=True)
baseline = root / "out/native-ws-baseline"
subprocess.run(["git", "worktree", "add", "--detach", str(baseline), "f1d2d6ab"], check=True)
# Workspace locks are ignored, so the detached checkout needs the exact lock
# resolved by this run's bootstrap before enforcing dependency equality.
shutil.copyfile(root / "pubspec.lock", baseline / "pubspec.lock")
workers = {}
for name, tree in [("baseline", baseline), ("candidate", root)]:
    subprocess.run(["dart", "pub", "get", "--enforce-lockfile"], cwd=tree, check=True)
    bundle = out / (name + "-worker")
    subprocess.run(["dart", "build", "cli", "--target", "bin/wamp_client_worker.dart", "--output", str(bundle)], cwd=tree / "packages/connectanum_bench", check=True)
    workers[name] = bundle / "bundle/bin/wamp_client_worker"

lib = root / "native/transport/target/ffi-test/release/libct_ffi.so"
driver = root / "native/bench/target/release/http_stream"
original = root / "native/bench/scenarios/wamp_file_transfer_throughput.toml"
parts = original.read_text().split("[[workloads]]")
names = [f"{transport}_file_{codec}_64m_dart_buffered" for transport in ["rawsocket", "websocket"] for codec in ["cbor", "msgpack", "json"]]
blocks = [part for part in parts[1:] if any(f'name = "{name}"' in part for name in names)]
assert len(blocks) == len(names)
scenario = out / "original-dart-file-workloads.toml"
scenario.write_text(parts[0] + "[[workloads]]" + "[[workloads]]".join(blocks))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

inputs = [lib, driver, original, scenario]
inputs.extend(tree / "pubspec.lock" for tree in [root, baseline])
inputs.extend(p for worker in workers.values() for p in worker.parent.parent.rglob("*") if p.is_file())
inputs.extend(p for tree in [root, baseline] for p in tree.glob("packages/*/lib/**/*.dart"))
inputs.extend(p for p in root.glob("native/transport/*/src/**/*.rs"))
inputs.extend(p for p in root.glob("native/bench/scenarios/wamp_*.toml"))
inputs.extend(p for p in root.glob("native/bench/artifact_gate/wamp_*.json"))
frozen = {str(p.relative_to(root)): sha(p) for p in inputs}
(out / "frozen-inputs.json").write_text(json.dumps(frozen, indent=2) + "\n")
expected = json.loads((root / "docs/benchmarks/readbuf-investigation-source-hashes.json").read_text())
assert all(sha(root / name) == value for name, value in expected.items())
results = []
for index, name in enumerate(["baseline", "candidate", "candidate", "baseline"]):
    folder = out / f"{index}-{name}"
    command = [str(driver), "--native-lib", str(lib), "--scenario", str(scenario), "--results", str(folder / "results.jsonl"), "--artifact-dir", str(folder), "--router-worker-counts", "1", "--native-runtime-thread-counts", "1", "--workload-timeout-ms", "300000", "--wamp-worker-executable", str(workers[name])]
    started = time.monotonic()
    with (out / f"{index}-{name}.log").open("w") as log:
        subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
    summary = json.loads((folder / "results.summary.json").read_text())
    results.append({"index": index, "worker": name, "elapsedSeconds": time.monotonic() - started, "workloads": summary["workloads"]})
    assert frozen == {str(p.relative_to(root)): sha(p) for p in inputs}
    print(json.dumps({"index": index, "worker": name, "lifeMbps": {w["workload"]: w["lifecycle_throughput_mbps"] for w in summary["workloads"]}}), flush=True)
(out / "receipt.json").write_text(json.dumps({"qualified": False, "reason": "Matched six original profiles; all eight complete scenarios are a separate subsequent step", "passed": True, "frozenInputs": True, "results": results}, indent=2) + "\n")
