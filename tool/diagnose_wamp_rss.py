#!/usr/bin/env python3
"""Isolate codec RSS history in fresh process pairs; never parity acceptance."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import time

import capture_wamp_stall as capture
import run_wamp_serializer_campaign as campaign
import wamp_serializer_compare as compare

ROOT = Path(__file__).resolve().parents[1]
SEQUENCE = ('flatbuffers', 'cbor', 'msgpack', 'msgpack', 'cbor', 'flatbuffers')
CASES = ('rpc_rawsocket_clear_native_native_buffer', 'rpc_rawsocket_clear_dart_values')
DRIVER_ENVIRONMENT = {'CONNECTANUM_SKIP_NATIVE_BUILD': '1', 'CONNECTANUM_BENCH_WAMP_REUSE_WORKER': '1'}
RESOLVED = ('pubspec.lock', 'native/bench/Cargo.lock', 'native/transport/Cargo.lock', '.dart_tool/package_config.json')


def prepare_pair(output, case, codec, policy):
    output.mkdir()
    runs = campaign.schedule([case], policy['minimum_warmup_runs'], policy['minimum_repetitions'], 20261005)
    workload = case['workloads'][codec]
    runs = [dict(run, order=[name for name in run['order'] if name == workload]) for run in runs]
    assert all(run['order'] == [workload] for run in runs)
    digest = campaign.write_scenarios(output, [case], runs, policy['minimum_duration_ms'],
                                     policy['minimum_samples_per_run'], 1, 1)
    return runs, digest


def validate_rows(rows, case, codec, policy):
    count = policy['minimum_warmup_runs'] + policy['minimum_repetitions']
    if len(rows) != count:
        raise ValueError(f'Expected {count} complete rows, observed {len(rows)}')
    pids = {role: set() for role in ('client_process_metrics', 'server_process_metrics')}
    previous_end = None
    for row in rows:
        if (row['workload'] != case['workloads'][codec]
                or len(row['samples']) < policy['minimum_samples_per_run']
                or row['data_window_elapsed_ms'] < policy['minimum_duration_ms']):
            raise ValueError('Single-codec row differs from the canonical workload or floors')
        findings = compare._configuration_findings(row, case, codec, label='RSS control', required=True)
        findings += compare._validate_evidence(row, label='RSS control')
        if findings:
            raise ValueError('; '.join(findings))
        # WorkloadSample has no timestamps. The production driver records
        # wall-clock boundaries on WorkloadReport, separately from data duration.
        started, completed = row.get('started_at_ms'), row.get('completed_at_ms')
        if (any(type(value) is not int or value < 0 for value in (started, completed))
                or completed < started
                or (previous_end is not None and started < previous_end)):
            raise ValueError('Replayed, overlapping, or invalid workload report timestamps')
        previous_end = completed
        for role in pids:
            metrics = row[role]
            pids[role].add(metrics['pid'])
            if any(type(metrics.get(key)) is not int or metrics[key] <= 0
                   for key in ('rss_before_bytes', 'peak_rss_during_bytes', 'current_rss_bytes')):
                raise ValueError('Missing measured RSS boundaries')
    if any(len(values) != 1 for values in pids.values()) or pids['client_process_metrics'] == pids['server_process_metrics']:
        raise ValueError('Process identities changed or overlap within a fresh pair')
    measured = rows[policy['minimum_warmup_runs']:]
    return {'pids': {role: next(iter(values)) for role, values in pids.items()},
            'measured': [{'before': sum(r[role]['rss_before_bytes'] for role in pids),
                          'peak': sum(r[role]['peak_rss_during_bytes'] for role in pids),
                          'after': sum(r[role]['current_rss_bytes'] for role in pids)} for r in measured]}


def source_inputs(root):
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    return {name: campaign.sha256(root / name) for name in names if name and (root / name).is_file()}


def changed_inputs(root, sources, resolved, artifacts, head):
    after = source_inputs(root)
    changed = sorted(name for name in sources.keys() | after.keys() if sources.get(name) != after.get(name))
    changed += [name for name, digest in resolved.items() if not (root / name).is_file() or campaign.sha256(root / name) != digest]
    changed += [key for key, item in artifacts.items() if not Path(item['path']).is_file() or campaign.sha256(Path(item['path'])) != item['sha256']]
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() != head:
        changed.append('HEAD')
    return changed


def run(args, root=ROOT):
    if platform.system() != 'Linux':
        raise ValueError('This production-process RSS diagnostic requires Linux')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    files = {'driver': args.driver.resolve(strict=True), 'native_library': args.native_lib.resolve(strict=True),
             'router_config': args.router_config.resolve(strict=True)}
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip():
        raise ValueError('Diagnostic source must be committed and clean')
    exports = subprocess.check_output(['nm', '-D', '--defined-only', str(files['native_library'])], text=True)
    symbols = {line.split()[-1] for line in exports.splitlines() if line.split()}
    if not any(name.startswith('ct_') for name in symbols) or any(name.startswith('ct_test_') for name in symbols):
        raise ValueError('RSS control requires a production native library without test oracles')
    policy = json.loads(campaign.POLICY.read_text())
    case = next(case for case in campaign.primary_cases() if case['id'] == args.case)
    sources = source_inputs(root)
    resolved = {name: campaign.sha256(root / name) for name in RESOLVED}
    for name in RESOLVED:
        target = output / 'resolved-inputs' / name.replace('/', '__').lstrip('.')
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(root / name, target)
        if campaign.sha256(target) != resolved[name]:
            raise ValueError('Resolved input changed during retention')
    manifest = {'kind': 'fresh_process_rss_control_never_acceptance', 'primary_acceptance_eligible': False,
                'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                'case': case, 'sequence': SEQUENCE, 'source_inputs': sources, 'resolved_inputs': resolved,
                'driver_environment': DRIVER_ENVIRONMENT,
                'artifacts': {key: {'path': str(path), 'sha256': campaign.sha256(path)} for key, path in files.items()},
                'policy_sha256': campaign.sha256(campaign.POLICY), 'policy': policy,
                'platform': platform.uname()._asdict(), 'rustflags': os.environ.get('RUSTFLAGS'),
                'limitations': ['Fresh process pair per codec segment, unlike primary process lifetime',
                                'Two process pairs per codec; measured rows are nested observations',
                                'No forced GC, CPU profiling, acceptance substitution, or pooled runner values']}
    (output / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    started = time.monotonic()
    receipts = []
    error = None
    try:
        with campaign.LOCK.open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for index, codec in enumerate(SEQUENCE):
                remaining = 19800 - (time.monotonic() - started)
                if remaining < (policy['minimum_warmup_runs'] + policy['minimum_repetitions']) * policy['minimum_duration_ms'] / 1000:
                    raise TimeoutError('RSS control campaign deadline exhausted before next pair')
                if changed_inputs(root, sources, resolved, manifest['artifacts'], manifest['head']):
                    raise ValueError('Inputs changed before next process pair')
                pair = output / f'{index:02d}-{codec}'
                runs, digest = prepare_pair(pair, case, codec, policy)
                command = [str(files['driver']), '--dart', args.dart,
                           '--native-lib', str(files['native_library']), '--router-config', str(files['router_config']),
                           '--control-base', 'https://127.0.0.1:8080/bench', '--scenario', str(pair / 'scenarios'),
                           '--results', str(pair / 'reports.jsonl'), '--results-only', '--skip-wamp-worker-aot',
                           '--collect-wamp-vm-metrics', '--router-worker-counts', '1', '--native-runtime-thread-counts', '1',
                           '--workload-timeout-ms', '300000']
                receipt = {'index': index, 'codec': codec, 'command': command, 'runs': runs,
                           'scenario_sha256': digest, 'status': 'started'}
                receipts.append(receipt)
                process = None
                try:
                    with (pair / 'driver.log').open('w') as log:
                        process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
                                                   start_new_session=True, stdin=subprocess.DEVNULL,
                                                   env={**os.environ, **DRIVER_ENVIRONMENT})
                        receipt['driver_pid'] = process.pid
                        receipt['exit_code'] = process.wait(timeout=remaining)
                finally:
                    if process is not None:
                        try:
                            receipt['process_group_stopped'] = campaign.stop_process_group(process)
                        except Exception as cleanup_error:
                            receipt['process_group_stopped'] = False
                            receipt['cleanup_error'] = capture.redact_debug_text(str(cleanup_error))
                    log = pair / 'driver.log'
                    if log.exists():
                        temporary = pair / 'driver-redacted.log'
                        with log.open(errors='replace') as original, temporary.open('w') as redacted:
                            for line in original:
                                redacted.write(capture.redact_debug_text(line))
                        temporary.replace(log)
                    (pair / 'execution.json').write_text(json.dumps(receipt, indent=2) + '\n')
                if receipt['exit_code'] or not receipt['process_group_stopped']:
                    raise ValueError('Driver or owned process cleanup failed')
                if campaign.scenario_directory_hash(pair / 'scenarios') != digest:
                    raise ValueError('Scenario inputs changed during execution')
                rows = [json.loads(line) for line in (pair / 'reports.jsonl').read_text().splitlines() if line.strip()]
                receipt.update(validate_rows(rows, case, codec, policy), rows=len(rows), status='complete')
                if changed_inputs(root, sources, resolved, manifest['artifacts'], manifest['head']):
                    receipt['status'] = 'failed'
                    raise ValueError('Inputs changed during process pair')
                receipt['raw_sha256'] = campaign.sha256(pair / 'reports.jsonl')
                (pair / 'execution.json').write_text(json.dumps(receipt, indent=2) + '\n')
    except Exception as failure:
        error = capture.redact_debug_text(str(failure))
        if receipts and receipts[-1]['status'] != 'complete':
            receipts[-1].update(status='failed', error=error)
            pair_path = output / f"{receipts[-1]['index']:02d}-{receipts[-1]['codec']}"
            (pair_path / 'execution.json').write_text(json.dumps(receipts[-1], indent=2) + '\n')
    changed = changed_inputs(root, sources, resolved, manifest['artifacts'], manifest['head'])
    summary = {codec: [
        {'pair_index': item['index'], 'pids': item['pids'],
         'median_peak_bytes': statistics.median(row['peak'] for row in item['measured']),
         'median_peak_minus_before_bytes': statistics.median(row['peak'] - row['before'] for row in item['measured'])}
        for item in receipts if item['codec'] == codec and item['status'] == 'complete']
        for codec in compare.CODECS}
    result = {'kind': manifest['kind'], 'primary_acceptance_eligible': False, 'head': manifest['head'],
              'status': 'failed' if error or changed else 'diagnostic_complete_never_acceptance',
              'error': error, 'inputs_unchanged': not changed, 'changed': changed, 'pairs': receipts, 'summary': summary,
              'elapsed_seconds': time.monotonic() - started}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'kind': result['kind'], 'status': result['status'], 'completed_pairs': sum(r['status'] == 'complete' for r in receipts)}))
    return int(result['status'] == 'failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--driver', type=Path, required=True)
    parser.add_argument('--native-lib', type=Path, required=True)
    parser.add_argument('--router-config', type=Path, default=campaign.ROOT / 'native/bench/bench_router.json')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--case', choices=CASES, default=CASES[0])
    raise SystemExit(run(parser.parse_args(), root=campaign.ROOT))


if __name__ == '__main__':
    main()
