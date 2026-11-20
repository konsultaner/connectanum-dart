"""Unqualified, same-host comparison of original Dart file workloads."""
from pathlib import Path
import hashlib, json, os, statistics, subprocess, time

root = Path.cwd()
out = root / 'out/wamp-profile-diagnostics'
out.mkdir(parents=True, exist_ok=True)
lib = Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
source = root / 'packages/connectanum_client/lib/src/transport/websocket/websocket_transport_io.dart'
original = source.read_text()
old = '''      final builder = BytesBuilder(copy: false);
      for (final fragment in fragments) {
        builder.add(fragment);
      }
      final serializedMessage = builder.takeBytes();'''
new = '''      final length = fragments.fold<int>(0, (length, part) => length + part.length);
      final Uint8List serializedMessage;
      if (fragments.length > 1 && length >= 65536) {
        serializedMessage = malloc<ffi.Uint8>(length).asTypedList(length, finalizer: malloc.nativeFree);
        var offset = 0;
        for (final part in fragments) {
          serializedMessage.setRange(offset, offset + part.length, part);
          offset += part.length;
        }
      } else {
        final builder = BytesBuilder(copy: false);
        for (final fragment in fragments) { builder.add(fragment); }
        serializedMessage = builder.takeBytes();
      }'''
assert original.count(old) == 1
candidate = original.replace("import 'dart:async';", "import 'dart:async';\nimport 'dart:ffi' as ffi;\nimport 'package:ffi/ffi.dart';").replace(old, new)
(out / 'baseline-transport.dart').write_text(original)
(out / 'candidate-transport.dart').write_text(candidate)
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
    for label, text in [('baseline', original), ('candidate', candidate)]:
        source.write_text(text)
        (out / (label + '-sources.json')).write_text(json.dumps(sources(), indent=2) + '\n')
        build = out / (label + '-worker')
        with (out / (label + '-build.log')).open('w') as log:
            subprocess.run(['dart', 'build', 'cli', '--target', 'bin/wamp_client_worker.dart', '--output', str(build)], cwd=root / 'packages/connectanum_bench', stdout=log, stderr=subprocess.STDOUT, check=True)
        worker = build / 'bundle/bin/wamp_client_worker'
        assert worker.is_file()
        workers.append(worker)
finally:
    source.write_text(original)
assert sources() == initial
bundles = [{str(p.relative_to(worker.parent.parent)): sha(p) for p in worker.parent.parent.rglob('*') if p.is_file()} for worker in workers]
assert bundles[0]['lib/libdartaotwamp_client_worker.so'] != bundles[1]['lib/libdartaotwamp_client_worker.so']
(out / 'bundle-hashes.json').write_text(json.dumps(bundles, indent=2) + '\n')
inputs = {str(p): sha(p) for p in [lib, canonical, scenario, root / 'native/bench/bench_router.json', *(p for worker in workers for p in worker.parent.parent.rglob('*') if p.is_file())]}
(out / 'input-hashes.json').write_text(json.dumps(inputs, indent=2) + '\n')
for iteration in range(4):
    for choice in ([0, 1] if iteration % 2 == 0 else [1, 0]):
        label = 'candidate' if choice else 'baseline'
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
        entry = values.setdefault(row['workload'], {'baseline': [], 'candidate': []})
        label = 'candidate' if path.parent.name.endswith('candidate') else 'baseline'
        entry[label].append({'dataMs': row['data_window_elapsed_ms'], 'lifecycleMs': row['completed_at_ms'] - row['started_at_ms']})
(out / 'matched-results.json').write_text(json.dumps(values, indent=2) + '\n')
for name, both in values.items():
    print(json.dumps({'workload': name, **{label: {k: statistics.median(r[k] for r in rows) for k in ['dataMs', 'lifecycleMs']} for label, rows in both.items()}}), flush=True)
