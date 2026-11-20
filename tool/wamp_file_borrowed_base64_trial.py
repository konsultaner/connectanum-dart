"""Unqualified, same-host comparison of original Dart file workloads."""
from pathlib import Path
import hashlib, json, os, statistics, subprocess, time

root = Path.cwd()
out = root / 'out/wamp-profile-diagnostics'
out.mkdir(parents=True, exist_ok=True)
lib = Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
trial_files = json.loads((root / 'tool/borrowed_base64_trial_files.json').read_text())
candidate = {f: (root / f).read_bytes() for f in trial_files}
original = {f: subprocess.check_output(['git', 'show', '5ec2288e416b6fdd98842e841addb9d0bb35c269:' + f]) for f in trial_files}
middle = {f: subprocess.check_output(['git', 'show', '0e9fbec3:' + f]) for f in trial_files}
canonical = root / 'native/bench/scenarios/wamp_file_transfer_throughput.toml'
parts = canonical.read_text().split('[[workloads]]')
names = ['rawsocket_file_json_64m_dart_buffered', 'websocket_file_json_64m_dart_buffered', 'websocket_file_cbor_64m_dart_buffered', 'websocket_file_msgpack_64m_dart_buffered']
blocks = [b for b in parts[1:] if any('name = "' + n + '"' in b for n in names)]
assert len(blocks) == 4
scenario = out / 'file-subset.toml'
scenario.write_text(parts[0] + '[[workloads]]' + '[[workloads]]'.join(blocks))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def sources(): return {str(p.relative_to(root)): sha(p) for p in root.glob('packages/*/lib/**/*.dart')}
initial = sources()
workers = []
try:
    for label, texts in [('baseline', original), ('borrowed', middle), ('streaming', candidate)]:
        for f, text in texts.items(): (root / f).write_bytes(text)
        (out / (label + '-sources.json')).write_text(json.dumps(sources(), indent=2) + '\n')
        build = out / (label + '-worker')
        with (out / (label + '-build.log')).open('w') as log:
            subprocess.run(['dart', 'build', 'cli', '--target', 'bin/wamp_client_worker.dart', '--output', str(build)], cwd=root / 'packages/connectanum_bench', stdout=log, stderr=subprocess.STDOUT, check=True)
        worker = build / 'bundle/bin/wamp_client_worker'
        assert worker.is_file()
        workers.append(worker)
finally:
    for f, text in candidate.items(): (root / f).write_bytes(text)
assert sources() == initial
bundles = [{str(p.relative_to(worker.parent.parent)): sha(p) for p in worker.parent.parent.rglob('*') if p.is_file()} for worker in workers]
assert len({x['lib/libdartaotwamp_client_worker.so'] for x in bundles}) == 3
(out / 'bundle-hashes.json').write_text(json.dumps(bundles, indent=2) + '\n')
inputs = {str(p): sha(p) for p in [lib, canonical, scenario, root / 'native/bench/bench_router.json', *(p for worker in workers for p in worker.parent.parent.rglob('*') if p.is_file())]}
(out / 'input-hashes.json').write_text(json.dumps(inputs, indent=2) + '\n')
for iteration in range(4):
    for choice in [[0, 1, 2], [2, 1, 0], [1, 0, 2], [2, 0, 1]][iteration]:
        label = ['baseline', 'borrowed', 'streaming'][choice]
        folder = out / f'{iteration}-{label}'
        args = [str(root / 'native/bench/target/release/http_stream'), '--native-lib', str(lib), '--scenario', str(scenario), '--results', str(folder / 'results.jsonl'), '--artifact-dir', str(folder), '--router-worker-counts', '1', '--native-runtime-thread-counts', '1', '--workload-timeout-ms', '300000', '--wamp-worker-executable', str(workers[choice])]
        start = time.monotonic()
        with (out / f'{iteration}-{label}.log').open('w') as log:
            subprocess.run(args, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
        print(json.dumps({'round': iteration, 'candidate': bool(choice), 'elapsedSeconds': time.monotonic() - start}), flush=True)
assert sources() == initial
assert inputs == {str(Path(p)): sha(Path(p)) for p in inputs}
values = {}
for path in out.glob('*-*/results.jsonl'):
    for line in path.read_text().splitlines():
        row = json.loads(line)
        entry = values.setdefault(row['workload'], {'baseline': [], 'borrowed': [], 'streaming': []})
        label = path.parent.name.split('-', 1)[1]
        entry[label].append({'dataMs': row['data_window_elapsed_ms'], 'lifecycleMs': row['completed_at_ms'] - row['started_at_ms']})
(out / 'matched-results.json').write_text(json.dumps(values, indent=2) + '\n')
for name, both in values.items():
    print(json.dumps({'workload': name, **{label: {k: statistics.median(r[k] for r in rows) for k in ['dataMs', 'lifecycleMs']} for label, rows in both.items()}}), flush=True)
