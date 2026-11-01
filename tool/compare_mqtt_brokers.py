"""Compare two MQTT Dart broker revisions on one host; never an acceptance gate."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path
PROFILES = ('ws_sustained', 'ws_v311_sustained', 'sustained', 'v311_sustained', '64k_sustained')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True, timeout=30).strip()

def identity(root, expected):
    if len(expected) != 40 or any((c not in '0123456789abcdef' for c in expected)):
        raise ValueError('expected source must be a full commit SHA')
    if git(root, 'rev-parse', 'HEAD') != expected:
        raise ValueError('source HEAD differs from declared revision')
    if git(root, 'status', '--porcelain'):
        raise ValueError('source checkout is dirty')
    return expected

def clean_stop(process, timeout=10):
    """Graceful stdin shutdown; always reap, retaining unexpected exit/timeout."""
    try:
        if process.stdin is not None and (not process.stdin.closed):
            try:
                process.stdin.close()
            except (BrokenPipeError, OSError):
                pass
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        raise

def raw_row(row, budget):
    count = budget['messages_per_run']
    subscribers = budget.get('subscribers', 1)
    if not (row['sent'] == count and row['received'] == count * subscribers and (row['received_per_subscriber'] == [count] * subscribers) and (row['duplicates'] == 0)):
        raise ValueError('delivery or duplicate mismatch')
    required = {'mqtt_version': budget.get('mqtt_version', '5'), 'transport': budget.get('transport', 'tcp'), 'payload_bytes': budget['payload_bytes'], 'window_messages': budget.get('window_messages', 0), 'publish_mode': budget.get('publish_mode', 'single'), 'subscribers': subscribers}
    if any((row[k] != v for k, v in required.items())):
        raise ValueError('client changed declared workload')

def shared_inputs(base, candidate):
    # This probe isolates router-broker changes, keeping the client/core/native
    # implementation and all their declared inputs unchanged.
    names = git(candidate, 'ls-files', 'native/transport',
                'packages/connectanum_client', 'packages/connectanum_core').splitlines()
    names += ['native/transport/Cargo.lock', 'pubspec.lock',
              'packages/connectanum_router/benchmark/mqtt_qos0.dart']
    hashes = {}
    for name in names:
        value = digest(candidate / name)
        if digest(base / name) != value:
            raise ValueError('shared native/client input differs: ' + name)
        hashes[name] = value
    return hashes


def verify_binaries(native, exes, client, provenance):
    if (digest(native) != provenance['native_sha256'] or
            any(digest(path) != provenance['broker_sha256'][leg]
                for leg, path in exes.items()) or
            digest(client) != provenance['client_sha256']):
        raise ValueError('binary changed during capture')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for n in ['baseline', 'candidate', 'native_lib', 'output']:
        parser.add_argument('--' + n.replace('_', '-'), type=Path, required=True)
    for n in ['baseline_ref', 'candidate_ref']:
        parser.add_argument('--' + n.replace('_', '-'), required=True)
    args = parser.parse_args(argv)
    base = args.baseline.resolve()
    candidate = args.candidate.resolve()
    output = args.output.resolve()
    native = args.native_lib.resolve()
    identity(base, args.baseline_ref)
    identity(candidate, args.candidate_ref)
    if not native.is_file():
        raise ValueError('native library missing')
    if output.exists() and any(output.iterdir()):
        raise ValueError('refusing to overwrite retained comparison')
    output.mkdir(parents=True, exist_ok=True)
    shared = shared_inputs(base, candidate)
    tool_root = Path(__file__).resolve().parent
    sys.path.insert(0, str(tool_root))
    import run_mqtt_benchmark_gate as gate
    budgets = {}
    for profile in PROFILES:
        name = f'tool/mqtt_native_{profile}_benchmark_budget.json'
        data = (candidate / name).read_bytes()
        if data != (base / name).read_bytes():
            raise ValueError('comparison substituted budget: ' + name)
        budget = json.loads(data)
        if budget['repetitions'] != 5:
            raise ValueError('comparison requires all five declared repetitions')
        budgets[profile] = budget
        (output / f'{profile}-budget.json').write_bytes(data)
    setup = {'diagnosticOnly': True, 'baseline_source': args.baseline_ref,
             'candidate_source': args.candidate_ref,
             'native_sha256': digest(native),
             'tool_sha256': digest(Path(__file__)),
             'budget_hashes': {p: digest(output / f'{p}-budget.json') for p in PROFILES}}
    (output / 'setup-provenance.json').write_text(json.dumps(setup, indent=2) + '\n')
    exes = {k: output / f'{k}-broker' for k in ['baseline', 'candidate']}
    client = output / 'mqtt-client'
    for source, exe, root in [('mqtt_native_router_server.dart', exes['baseline'], base), ('mqtt_native_router_server.dart', exes['candidate'], candidate), ('mqtt_qos0.dart', client, candidate)]:
        with (output / f'{exe.name}-compile.log').open('w') as log:
            subprocess.run(['dart', 'compile', 'exe', f'benchmark/{source}', '-o', str(exe)], cwd=root / 'packages/connectanum_router', stdout=log, stderr=subprocess.STDOUT, check=True)
    sdk = subprocess.check_output(['dart', '--version'], text=True, timeout=10).strip()
    native_sha = digest(native)
    provenance = {'diagnosticOnly': True, 'baseline_source': args.baseline_ref, 'candidate_source': args.candidate_ref, 'SDK': sdk, 'native_sha256': native_sha, 'broker_sha256': {k: digest(v) for k, v in exes.items()}, 'client_sha256': digest(client), 'shared_native_client_inputs_verified': len(shared), 'shared_source_hashes': shared, 'same_native_client_bytes_for_both_legs': True, 'schedule': 'five pairs per profile, AB/BA alternating, all rows retained', 'scope': 'Same-runner Dart broker source comparison, not a Mosquitto gate or FlatBuffers/RSS acceptance.'}
    provenance['platform'] = {
        'os': platform.system(), 'kernel': platform.release(),
        'architecture': platform.machine(), 'logical_cpus': os.cpu_count(),
        'cpu_model': gate.cpu_model(), 'runner_image': os.environ.get('ImageOS'),
        'runner_image_version': os.environ.get('ImageVersion'),
        'native_runtime_threads': os.environ.get('CONNECTANUM_NATIVE_RUNTIME_THREADS'),
        'rustc': subprocess.check_output(['rustc', '-Vv'], text=True, timeout=10).strip(),
    }
    provenance['tool_revision'] = git(tool_root.parent, 'rev-parse', 'HEAD')
    provenance['tool_sha256'] = digest(Path(__file__))
    provenance['helper_sha256'] = digest(tool_root / 'run_mqtt_benchmark_gate.py')
    (output / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    rows = []
    for profile, budget in budgets.items():
        for repeat in range(1, 6):
            for leg in ['baseline', 'candidate'] if repeat % 2 else ['candidate', 'baseline']:
                prefix = f'{profile}-{repeat}-{leg}'
                env = gate.workload_environment(budget, budget.get('transport', 'tcp'))
                env['CONNECTANUM_NATIVE_LIB'] = str(native)
                port = gate.available_port()
                broker_log = output / f'{prefix}-broker.log'
                row = None
                with broker_log.open('w') as stream:
                    process = subprocess.Popen([str(exes[leg]), str(port)], env=env, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=stream, text=True)
                    primary = None
                    try:
                        gate.wait_for_listener(port, process)
                        before_cpu, _, before_rss = gate.process_metrics(process.pid)
                        result, client_cpu = gate.run_client_with_cpu(client, port, env)
                        after_cpu, _, after_rss = gate.process_metrics(process.pid)
                        (output / f'{prefix}-stdout.log').write_text(result.stdout)
                        (output / f'{prefix}-stderr.log').write_text(result.stderr)
                        row = gate.checked_client_row(result, leg, repeat, broker_log=broker_log)
                        raw_row(row, budget)
                        row.update(leg=leg, run=repeat, case=profile, broker_cpu_seconds=round(after_cpu - before_cpu, 4), client_cpu_seconds=client_cpu, broker_rss_bytes=max(before_rss, after_rss))
                        rows.append(row)
                        (output / 'raw.jsonl').write_text(''.join((json.dumps(r, sort_keys=True) + '\n' for r in rows)))
                        print(profile, repeat, leg, flush=True)
                    except BaseException as error:
                        primary = error
                        (output / f'{prefix}-primary-error.txt').write_text(repr(error) + '\n')
                        if isinstance(error, subprocess.TimeoutExpired):
                            for key in ('stdout', 'stderr'):
                                data = getattr(error, key, None)
                                if data is not None:
                                    if isinstance(data, bytes):
                                        data = data.decode('utf-8', errors='replace')
                                    (output / f'{prefix}-{key}.log').write_text(data)
                        raise
                    finally:
                        try:
                            exitcode = clean_stop(process)
                            (output / f'{prefix}-broker-exit.txt').write_text(str(exitcode) + '\n')
                            if exitcode != 0:
                                raise RuntimeError(f'broker exited {exitcode}')
                        except BaseException as cleanup:
                            (output / f'{prefix}-cleanup-error.txt').write_text(repr(cleanup) + '\n')
                            if primary is None:
                                raise
    identity(base, args.baseline_ref)
    identity(candidate, args.candidate_ref)
    if subprocess.check_output(['dart', '--version'], text=True, timeout=10).strip() != sdk:
        raise ValueError('SDK changed during capture')
    if shared_inputs(base, candidate) != shared:
        raise ValueError('shared native/client inputs changed during capture')
    verify_binaries(native, exes, client, provenance)
    summary = {'diagnosticOnly': True, 'rows': len(rows), 'delivered': sum((r['received'] for r in rows)), 'provenance': provenance, 'profiles': []}
    for profile in PROFILES:
        subset = [r for r in rows if r['case'] == profile]
        pairs = []
        for repeat in range(1, 6):
            b = next((r for r in subset if r['leg'] == 'baseline' and r['run'] == repeat))
            c = next((r for r in subset if r['leg'] == 'candidate' and r['run'] == repeat))
            pairs.append(c['throughput_delivered_per_sec'] / b['throughput_delivered_per_sec'])
        rates = {leg: statistics.median((r['throughput_delivered_per_sec'] for r in subset if r['leg'] == leg)) for leg in exes}
        summary['profiles'].append({'profile': profile, 'paired_throughput_ratios': pairs, 'median_paired_ratio': statistics.median(pairs), 'throughput_ratio_of_medians': rates['candidate'] / rates['baseline'], 'median_rates': rates, 'broker_cpu_medians': {leg: statistics.median((r['broker_cpu_seconds'] for r in subset if r['leg'] == leg)) for leg in exes}})
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
if __name__ == '__main__':
    main()
