#!/usr/bin/env python3
"""Run analyzer-generated Dart mutants in an isolated workspace, fail closed."""

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def run(command, cwd, timeout):
    with subprocess.Popen(
        command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, start_new_session=True,
    ) as process:
        try:
            output, _ = process.communicate(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            # Kill descendants as well: an orphaned Dart test can corrupt the
            # next result even when its parent shell has already exited.
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            if process.returncode is None:
                process.wait()
            if isinstance(error, KeyboardInterrupt):
                raise
            return None, output
        return process.returncode, output


def classify(returncode, output):
    if returncode is None:
        return 'timeout'
    if returncode < 0:
        return 'error'
    events = []
    for line in output.splitlines():
        try:
            event = json.loads(line)
            if isinstance(event, dict):
                events.append(event)
        except json.JSONDecodeError:
            pass
    tests = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    done = [e for e in events if e.get('type') == 'done']
    completed = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
    real = [e for e in completed if e.get('testID') in tests
            and not tests[e['testID']]['name'].startswith('loading ')]
    if not done or any(e.get('skipped') for e in completed):
        return 'error'
    # Compiler/load errors and infrastructure crashes are not assertion kills.
    if any(e.get('result') in ('error', 'failure') for e in completed
           if e.get('testID') not in {r['testID'] for r in real}):
        load_errors = [e.get('error', '') for e in events if e.get('type') == 'error']
        compiler_messages = [e.get('message', '') for e in events if e.get('type') == 'print']
        if (any(re.search(r'\.dart:\d+:\d+:\s+Error:', message) for message in load_errors + compiler_messages)
                or any('Compilation failed' in message for message in load_errors + compiler_messages)):
            return 'compileError'
        return 'error'
    if not real:
        return 'error'
    if returncode == 0 and done[-1].get('success') is True:
        return 'survived'
    if returncode != 0 and done[-1].get('success') is False:
        if any(e.get('type') == 'error' and 'Test timed out after' in e.get('error', '') for e in events):
            return 'timeout'
        if any(e.get('result') in ('error', 'failure') for e in real):
            return 'killed'
    return 'error'


def apply_mutation(source, mutation):
    data = source.encode('utf-16-le')
    start = mutation['offset'] * 2
    end = start + mutation['length'] * 2
    if data[start:end].decode('utf-16-le') != mutation['original']:
        raise ValueError('Mutation source does not match recorded AST offsets')
    return (data[:start] + mutation['replacement'].encode('utf-16-le') + data[end:]).decode('utf-16-le')


def mutation_id(mutation):
    return hashlib.sha256(json.dumps(mutation, sort_keys=True).encode()).hexdigest()[:20]


def summarize(outcomes):
    if any(item.get('equivalence') and item['status'] != 'survived' for item in outcomes):
        raise ValueError('Only observed survivors can have an equivalence justification')
    counts = dict(collections.Counter(item['status'] for item in outcomes))
    viable = sum(counts.get(s, 0) for s in ('killed', 'survived', 'timeout', 'error'))
    return {
        'counts': counts,
        'viable': viable,
        'score': 100 * counts.get('killed', 0) / viable if viable else None,
        'equivalent': sum(bool(item.get('equivalence')) for item in outcomes),
        'adjustedScore': (100 * counts.get('killed', 0) /
                          (viable - sum(bool(item.get('equivalence')) for item in outcomes)))
        if viable > sum(bool(item.get('equivalence')) for item in outcomes) else None,
    }


def validate_equivalents(entries, mutations, source_hashes):
    inventory = {mutation_id(m): m for m in mutations}
    validated = {}
    for identifier, entry in entries.items():
        mutation = inventory.get(identifier)
        if mutation is None or entry.get('sourceHash') != source_hashes.get(mutation['file']):
            raise ValueError(f'Stale equivalent-mutation justification: {identifier}')
        if not isinstance(entry.get('reason'), str) or len(entry['reason'].strip()) < 30:
            raise ValueError(f'Missing equivalent-mutation reasoning: {identifier}')
        validated[identifier] = entry['reason']
    return validated


def snapshot(destination):
    listed = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT,
    ).decode().split('\0')
    for name in set(listed) - {''}:
        path = Path(name)
        if path.parts[0] not in ('packages', 'tool') and name not in (
            'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'dart_test.yaml',
        ):
            continue
        source = ROOT / path
        if source.is_symlink():
            raise ValueError(f'Unsupported symlink in mutation snapshot: {name}')
        if not source.is_file():
            continue
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    # The ignored lockfile fixes the local dependency graph for all mutants.
    if (ROOT / 'pubspec.lock').is_file():
        shutil.copy2(ROOT / 'pubspec.lock', destination / 'pubspec.lock')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / 'tool/mutation_targets.json')
    parser.add_argument('--equivalents', type=Path, default=ROOT / 'tool/mutation_equivalents.json')
    parser.add_argument('--target', action='append')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=45)
    parser.add_argument('--threshold', type=float, default=95)
    parser.add_argument('--list', action='store_true')
    args = parser.parse_args()
    if not 0 <= args.threshold <= 100 or args.timeout <= 0:
        parser.error('threshold must be 0..100 and timeout must be positive')
    config = json.loads(args.config.read_text())
    if not isinstance(config, dict) or not config:
        parser.error('config must be a nonempty mapping of mutation targets')
    equivalents = json.loads(args.equivalents.read_text())
    selected = args.target or list(config)
    unknown = set(selected) - config.keys()
    if unknown:
        parser.error(f'Unknown targets: {sorted(unknown)}')
    if args.output.exists():
        parser.error('output already exists; use a fresh directory')
    args.output.mkdir(parents=True)
    report = {'schemaVersion': 1, 'scope': selected, 'targets': {}, 'complete': False,
              'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'operatorScope': ['binary', 'nullFallback', 'boolean', 'negation', 'condition']}
    report_path = args.output / 'mutation-report.json'

    def save():
        temporary_report = report_path.with_suffix('.tmp')
        temporary_report.write_text(json.dumps(report, indent=2) + '\n')
        temporary_report.replace(report_path)

    save()
    with tempfile.TemporaryDirectory(prefix='connectanum-mutations-') as temporary:
        work = Path(temporary)
        snapshot(work)
        code, output = run(['dart', 'pub', 'get', '--offline'], work, 120)
        if code != 0:
            raise RuntimeError('Isolated dependency resolution failed: ' + output[-2000:])
        for name in selected:
            target = config[name]
            sources = target['sources']
            for source in sources:
                if not source.startswith('packages/') or '/lib/' not in source or '..' in Path(source).parts:
                    raise ValueError(f'Invalid production mutation source: {source}')
            code, output = run(['dart', 'tool/dart_mutations.dart', *sources], work, 120)
            if code != 0:
                raise RuntimeError('Mutation generation failed: ' + output[-2000:])
            mutations = json.loads(output)
            if not mutations:
                raise ValueError(f'No mutations generated for {name}')
            result = {'sources': sources, 'tests': target['tests'], 'generated': len(mutations),
                      'platform': target.get('platform', 'vm'),
                      'sourceHashes': {source: hashlib.sha256((work / source).read_bytes()).hexdigest() for source in sources},
                      'baseline': 'notRun', 'outcomes': []}
            justified = validate_equivalents(equivalents.get(name, {}), mutations, result['sourceHashes'])
            test_files = set()
            runnable_tests = set()
            for test in target['tests']:
                test_path = work / test
                if test_path.is_dir():
                    test_files.update(test_path.rglob('*.dart'))
                    runnable_tests.update(test_path.rglob('*_test.dart'))
                else:
                    test_files.add(test_path)
                    runnable_tests.add(test_path)
            # Directory discovery order varies by filesystem. With fail-fast,
            # that can change an assertion kill into a different test's timeout.
            resolved_tests = sorted(str(path.relative_to(work)) for path in runnable_tests)
            if not resolved_tests:
                raise ValueError(f'No runnable test files for {name}')
            result['resolvedTests'] = resolved_tests
            result['testHashes'] = {str(path.relative_to(work)): hashlib.sha256(path.read_bytes()).hexdigest()
                                    for path in sorted(test_files)}
            report['targets'][name] = result
            if args.list:
                result['inventory'] = mutations
                save()
                continue
            command = ['dart', 'test', '--reporter=json', '--concurrency=1', '--fail-fast',
                       '--timeout=5s', *resolved_tests]
            platform = target.get('platform', 'vm')
            if platform not in ('vm', 'chrome'):
                raise ValueError(f'Unsupported test platform: {platform}')
            command.extend(['--platform', platform])
            if platform == 'chrome':
                command.append('--compiler=dart2js')
            test_root = Path(target.get('testRoot', '.'))
            if test_root.is_absolute() or '..' in test_root.parts:
                raise ValueError(f'Invalid test root: {test_root}')
            if test_root != Path('.'):
                command = [os.path.relpath(work / arg, work / test_root) if arg in resolved_tests else arg
                           for arg in command]
            test_cwd = work / test_root
            result['testCommand'] = command
            code, output = run(command, test_cwd, args.timeout)
            result['baseline'] = classify(code, output)
            result['baselineExitCode'] = code
            (args.output / f'{name}-baseline.log').write_text(output)
            if result['baseline'] != 'survived':
                save()
                raise RuntimeError(f'{name}: unmutated baseline did not pass ({result["baseline"]})')
            save()
            for index, mutation in enumerate(mutations):
                path = work / mutation['file']
                source = path.read_text()
                identifier = mutation_id(mutation)
                started = time.monotonic()
                try:
                    path.write_text(apply_mutation(source, mutation))
                    code, output = run(command, test_cwd, args.timeout)
                finally:
                    path.write_text(source)
                status = classify(code, output)
                outcome = {**mutation, 'id': identifier, 'status': status,
                           'exitCode': code,
                           'seconds': round(time.monotonic() - started, 3)}
                if identifier in justified:
                    if status != 'survived':
                        raise ValueError(f'Equivalent mutation no longer survives: {identifier}')
                    outcome['equivalence'] = justified[identifier]
                result['outcomes'].append(outcome)
                (args.output / f'{identifier}.log').write_text(output)
                result.update(summarize(result['outcomes']))
                save()
                print(f'{name} {index + 1}/{len(mutations)} {status}: '
                      f'{mutation["file"]}:{mutation["line"]} {mutation["operator"]}', flush=True)
            code, output = run(command, test_cwd, args.timeout)
            result['restoredBaseline'] = classify(code, output)
            result['restoredBaselineExitCode'] = code
            (args.output / f'{name}-restored-baseline.log').write_text(output)
            if result['restoredBaseline'] != 'survived':
                save()
                raise RuntimeError(f'{name}: restored baseline failed')
    report['complete'] = not args.list
    save()
    if args.list:
        return 0
    passed = all(
        target['adjustedScore'] is not None and target['adjustedScore'] >= args.threshold
        and not target['counts'].get('error') and not target['counts'].get('timeout')
        for target in report['targets'].values()
    )
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
