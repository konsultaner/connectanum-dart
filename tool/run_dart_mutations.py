#!/usr/bin/env python3
"""Run analyzer-generated Dart mutants in an isolated workspace, fail closed."""

import argparse
import collections
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
APPLICATION_ROOTS = tuple(f'examples/wamp_app/{name}' for name in ('shared', 'server', 'client'))


def live_process_group_members(group):
    result = subprocess.run(
        ['ps', '-eo', 'pid=,pgid=,stat=,comm='], capture_output=True,
        text=True, check=True, timeout=5,
    )
    members = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        pid, pgid, state, executable = line.split(maxsplit=3)
        if int(pgid) == group and state[0] not in ('Z', 'X'):
            # Keep executable identity for triage, never command-line arguments.
            members.append({'pid': int(pid), 'state': state, 'executable': executable})
    return members


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
        # Linux killpg succeeds for zombie-only groups too. Inspect before
        # signaling so killing a live fixture cannot erase the leak evidence.
        inspection_error = None
        members = []
        try:
            members = live_process_group_members(process.pid)
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            inspection_error = str(error)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if members or inspection_error is not None:
            output += '\n' + json.dumps({
                'type': 'connectanumInfrastructureError',
                'reason': ('Could not inspect remaining test processes'
                           if inspection_error is not None else
                           'Test command left descendants alive after exit'),
                'processes': members,
                'inspectionError': inspection_error,
            }) + '\n'
        return process.returncode, output


def machine_events(output):
    events = []
    for line in output.splitlines():
        try:
            event = json.loads(line)
            if isinstance(event, dict):
                events.append(event)
        except json.JSONDecodeError:
            pass
    return events


def classify(returncode, output):
    if returncode is None:
        return 'timeout'
    if returncode < 0:
        return 'error'
    events = machine_events(output)
    if any(e.get('type') == 'connectanumInfrastructureError' for e in events):
        return 'error'
    tests = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    done = [e for e in events if e.get('type') == 'done']
    completed = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
    real = [e for e in completed if e.get('testID') in tests
            and not tests[e['testID']]['name'].startswith('loading ')
            and not re.search(r'\((?:setUpAll|tearDownAll)\)$', tests[e['testID']]['name'])]
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
        # Polling helpers use fail(), but an elapsed deadline is not a behavioral kill.
        timeout_prefixes = ('TimeoutException:', 'TimeoutException after ',
                            'Test timed out after ', 'Condition not met within ',
                            'Timed out waiting for ')
        if any(e.get('type') == 'error' and
               e.get('error', '').startswith(timeout_prefixes) for e in events):
            return 'timeout'
        if any(e.get('result') in ('error', 'failure') for e in real):
            return 'killed'
    return 'error'


def kill_evidence(status, output):
    """Describe completed test detections without upgrading their classification."""
    if status != 'killed':
        return None
    # Isolated test files reuse reporter IDs; only the final failed command
    # contributes evidence. Earlier commands have already passed classification.
    events = []
    for event in machine_events(output):
        if event.get('type') in ('connectanumTestCommand', 'start'):
            events = []
        events.append(event)
    tests = {event['test']['id']: event['test'] for event in events
             if event.get('type') == 'testStart'}
    failed = {event['testID'] for event in events
              if event.get('type') == 'testDone' and not event.get('hidden')
              and event.get('result') in ('failure', 'error')
              and event.get('testID') in tests
              and not tests[event['testID']]['name'].startswith('loading ')
              and not re.search(r'\((?:setUpAll|tearDownAll)\)$',
                                tests[event['testID']]['name'])}
    assertions = errors = unknown = 0
    for identifier in failed:
        failures = [event for event in events
                    if event.get('type') == 'error' and event.get('testID') == identifier]
        if not failures:
            unknown += 1
        for event in failures:
            if event.get('isFailure') is True:
                assertions += 1
            elif event.get('isFailure') is False:
                errors += 1
            else:
                unknown += 1
    cause = ('unknown' if unknown or not (assertions or errors) else
             'mixed' if assertions and errors else
             'assertion' if assertions else 'testError')
    return {'cause': cause, 'assertionFailures': assertions, 'testErrors': errors,
            'unclassifiedFailures': unknown}


def run_test_commands(commands, cwd, timeout):
    if not commands or not math.isfinite(timeout) or timeout <= 0:
        raise ValueError('Test commands and a finite positive deadline are required')
    deadline = time.monotonic() + timeout
    logs = []
    for command in commands:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None, '\n'.join(logs), 'timeout'
        code, output = run(command, cwd, remaining)
        status = classify(code, output)
        if len(commands) == 1:
            return code, output, status
        logs.append(json.dumps({'type': 'connectanumTestCommand',
                                'command': command, 'timeoutSeconds': remaining,
                                'exitCode': code, 'status': status}))
        logs.append(output)
        if status != 'survived':
            return code, '\n'.join(logs), status
    return 0, '\n'.join(logs), 'survived'


def apply_mutation(source, mutation):
    data = source.encode('utf-16-le')
    start = mutation['offset'] * 2
    end = start + mutation['length'] * 2
    if data[start:end].decode('utf-16-le') != mutation['original']:
        raise ValueError('Mutation source does not match recorded AST offsets')
    return (data[:start] + mutation['replacement'].encode('utf-16-le') + data[end:]).decode('utf-16-le')


def mutation_id(mutation):
    return hashlib.sha256(json.dumps(mutation, sort_keys=True).encode()).hexdigest()[:20]


def validate_sources(sources):
    if not isinstance(sources, list) or not sources:
        raise ValueError('Production mutation sources must be a nonempty list')
    for source in sources:
        parts = source.split('/') if isinstance(source, str) else []
        package_source = (len(parts) >= 4 and parts[0] == 'packages'
                          and parts[2] in ('lib', 'bin', 'hook', 'tool'))
        application_source = (len(parts) >= 5 and '/'.join(parts[:3]) in APPLICATION_ROOTS
                              and parts[3] in ('lib', 'bin'))
        if not ((package_source or application_source)
                and source.endswith('.dart')
                and not any(part in ('', '.', '..') for part in parts)):
            raise ValueError(f'Invalid production mutation source: {source}')


def native_artifact():
    configured = os.environ.get('CONNECTANUM_NATIVE_LIB')
    if not configured:
        raise ValueError('CONNECTANUM_NATIVE_LIB is required for this native integration target; '
                         'use CONNECTANUM_MUTATIONS_NATIVE=1 bin/test-mutations.')
    path = Path(configured)
    if not path.is_absolute():
        raise ValueError('CONNECTANUM_NATIVE_LIB must identify an absolute path')
    path = path.resolve()
    if not path.is_file():
        raise ValueError('CONNECTANUM_NATIVE_LIB must identify an existing file')
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def summarize(outcomes):
    if any(item.get('equivalence') and item['status'] != 'survived' for item in outcomes):
        raise ValueError('Only observed survivors can have an equivalence justification')
    counts = dict(collections.Counter(item['status'] for item in outcomes))
    viable = sum(counts.get(s, 0) for s in ('killed', 'survived', 'timeout', 'error'))
    equivalent = sum(bool(item.get('equivalence')) for item in outcomes)
    causes = dict.fromkeys(('assertion', 'testError', 'mixed', 'unknown'), 0)
    for item in outcomes:
        if item['status'] == 'killed':
            cause = (item.get('killEvidence') or {}).get('cause', 'unknown')
            if cause not in causes:
                raise ValueError(f'Unknown mutation kill cause: {cause}')
            causes[cause] += 1
    assertion_detected = causes['assertion'] + causes['mixed']
    return {
        'counts': counts,
        'viable': viable,
        'score': 100 * counts.get('killed', 0) / viable if viable else None,
        'equivalent': equivalent,
        'adjustedScore': (100 * counts.get('killed', 0) /
                          (viable - sum(bool(item.get('equivalence')) for item in outcomes)))
        if viable > sum(bool(item.get('equivalence')) for item in outcomes) else None,
        'killCauseCounts': causes,
        'killEvidenceComplete': not causes['unknown'],
        'assertionScoreLowerBound': 100 * assertion_detected / viable if viable else None,
        'adjustedAssertionScoreLowerBound': 100 * assertion_detected / (viable - equivalent)
        if viable > equivalent else None,
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


def passes_assertion_gate(summary, threshold):
    """Conventional detections remain diagnostic, not assertion credit."""
    score = summary['adjustedAssertionScoreLowerBound']
    return (score is not None and score >= threshold
            and summary['killEvidenceComplete']
            and not summary['counts'].get('error')
            and not summary['counts'].get('timeout'))


def snapshot(destination, support_files=()):
    listed = set(subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT,
    ).decode().split('\0')) - {''}
    support = set()
    for name in support_files:
        if not isinstance(name, str) or not name or Path(name).is_absolute() or '..' in Path(name).parts:
            raise ValueError(f'Invalid mutation support file: {name}')
        if name not in listed or not (ROOT / name).is_file():
            raise ValueError(f'Missing or unlisted mutation support file: {name}')
        support.add(name)
    for name in sorted(listed):
        path = Path(name)
        application_input = any(name.startswith(f'{root}/') for root in APPLICATION_ROOTS)
        if not application_input and name not in support and path.parts[0] not in ('packages', 'tool') and name not in (
            'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'dart_test.yaml',
        ):
            continue
        source = ROOT / path
        if any((ROOT / part).is_symlink() for part in (path, *path.parents)):
            raise ValueError(f'Unsupported symlink in mutation snapshot: {name}')
        if not source.is_file():
            continue
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    # Include ignored lockfiles so standalone packages retain their own graph.
    for package_root in ('.', *APPLICATION_ROOTS):
        path = Path(package_root) / 'pubspec.lock'
        if any((ROOT / part).is_symlink() for part in (path, *path.parents)):
            raise ValueError(f'Unsupported symlink in mutation snapshot: {path}')
        if (ROOT / path).is_file():
            (destination / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, destination / path)


def unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / 'tool/mutation_targets.json')
    parser.add_argument('--equivalents', type=Path, default=ROOT / 'tool/mutation_equivalents.json')
    parser.add_argument('--target', action='append')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=45)
    parser.add_argument('--threshold', type=float, default=95,
                        help='minimum adjusted assertion-based mutation score (default: 95)')
    parser.add_argument('--list', action='store_true')
    args = parser.parse_args()
    if not 0 <= args.threshold <= 100 or args.timeout <= 0:
        parser.error('threshold must be 0..100 and timeout must be positive')
    try:
        config = json.loads(args.config.read_text(), object_pairs_hook=unique_json_object)
        equivalents = json.loads(args.equivalents.read_text(), object_pairs_hook=unique_json_object)
    except ValueError as error:
        parser.error(f'invalid mutation configuration: {error}')
    if not isinstance(config, dict) or not config:
        parser.error('config must be a nonempty mapping of mutation targets')
    selected = args.target or list(config)
    unknown = set(selected) - config.keys()
    if unknown:
        parser.error(f'Unknown targets: {sorted(unknown)}')
    if not args.list and any(config[name].get('requiresNativeLibrary') for name in selected):
        native_artifact()
    if args.output.exists():
        parser.error('output already exists; use a fresh directory')
    args.output.mkdir(parents=True)
    report = {'schemaVersion': 1, 'scope': selected, 'targets': {}, 'complete': False,
              'killEvidenceVersion': 1,
              'scoreDefinition': 'Completed test detection, including caught test errors',
              'gate': {'metric': 'adjustedAssertionScoreLowerBound',
                       'threshold': args.threshold, 'passed': None},
              'runnerSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
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
        snapshot(work, [path for name in selected for path in config[name].get('supportFiles', [])])
        code, output = run(['dart', 'pub', 'get', '--offline'], work, 120)
        if code != 0:
            raise RuntimeError('Isolated dependency resolution failed: ' + output[-2000:])
        for name in selected:
            target = config[name]
            sources = target['sources']
            validate_sources(sources)
            test_root = Path(target.get('testRoot', '.'))
            if test_root.is_absolute() or '..' in test_root.parts:
                raise ValueError(f'Invalid test root: {test_root}')
            dependency_hashes = {}
            if test_root.as_posix() in APPLICATION_ROOTS:
                code, output = run(['dart', 'pub', 'get', '--offline'], work / test_root, 120)
                (args.output / f'{name}-dependencies.log').write_text(output)
                if code != 0:
                    raise RuntimeError(f'{name}: isolated application dependency resolution failed: '
                                       + output[-2000:])
                dependency_hashes = {
                    str(path.relative_to(work)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for root in (Path('.'), *(Path(path) for path in APPLICATION_ROOTS))
                    for file in ('pubspec.yaml', 'pubspec.lock')
                    if (path := work / root / file).is_file()
                }
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
            if dependency_hashes:
                result['dependencyHashes'] = dependency_hashes
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
            support_files = target.get('supportFiles', [])
            for path in support_files:
                if Path(path).is_absolute() or '..' in Path(path).parts or not (work / path).is_file():
                    raise ValueError(f'Invalid mutation support file: {path}')
            result['supportHashes'] = {path: hashlib.sha256((work / path).read_bytes()).hexdigest()
                                       for path in support_files}
            report['targets'][name] = result
            if args.list:
                result['inventory'] = mutations
                save()
                continue
            artifact = native_artifact() if target.get('requiresNativeLibrary') else None
            if artifact:
                result['nativeArtifact'] = artifact
            test_timeout = target.get('testTimeoutSeconds', 5)
            if isinstance(test_timeout, bool) or not isinstance(test_timeout, (int, float)) or not math.isfinite(test_timeout) or test_timeout <= 0:
                raise ValueError('testTimeoutSeconds must be finite and positive')
            command = ['dart', 'test', '--reporter=json', '--concurrency=1', '--fail-fast',
                       f'--timeout={test_timeout}s', *resolved_tests]
            platform = target.get('platform', 'vm')
            if platform not in ('vm', 'chrome'):
                raise ValueError(f'Unsupported test platform: {platform}')
            command.extend(['--platform', platform])
            if platform == 'chrome':
                # Complete browser suites and their cleanup before shutting down
                # the compiler pool, rather than exiting with queued compiles.
                command.remove('--fail-fast')
                command.append('--compiler=dart2js')
            if test_root != Path('.'):
                command = [os.path.relpath(work / arg, work / test_root) if arg in resolved_tests else arg
                           for arg in command]
            test_cwd = work / test_root
            isolate_files = target.get('isolateTestFiles', False)
            if not isinstance(isolate_files, bool):
                raise ValueError('isolateTestFiles must be a boolean')
            test_arguments = [os.path.relpath(work / arg, test_cwd) for arg in resolved_tests]
            commands = [command]
            if isolate_files:
                # Dart fail-fast can skip tearDownAll even within one suite.
                # Finish each file's cleanup, then stop before the next file.
                command = [arg for arg in command if arg != '--fail-fast']
                commands = [[arg for arg in command if arg not in test_arguments or arg == selected]
                            for selected in test_arguments]
            result['testCommands'] = commands
            if len(commands) == 1:
                result['testCommand'] = commands[0]
            code, output, status = run_test_commands(commands, test_cwd, args.timeout)
            result['baseline'] = status
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
                    code, output, status = run_test_commands(commands, test_cwd, args.timeout)
                finally:
                    path.write_text(source)
                # The same mutation ID can run under several platforms/test targets.
                log_name = f'{hashlib.sha256(name.encode()).hexdigest()}-{identifier}.log'
                outcome = {**mutation, 'id': identifier, 'status': status, 'log': log_name,
                           'exitCode': code,
                           'seconds': round(time.monotonic() - started, 3)}
                evidence = kill_evidence(status, output)
                if evidence is not None:
                    outcome['killEvidence'] = evidence
                if identifier in justified:
                    if status != 'survived':
                        raise ValueError(f'Equivalent mutation no longer survives: {identifier}')
                    outcome['equivalence'] = justified[identifier]
                result['outcomes'].append(outcome)
                (args.output / log_name).write_text(output)
                result.update(summarize(result['outcomes']))
                save()
                print(f'{name} {index + 1}/{len(mutations)} {status}: '
                      f'{mutation["file"]}:{mutation["line"]} {mutation["operator"]}', flush=True)
            code, output, status = run_test_commands(commands, test_cwd, args.timeout)
            result['restoredBaseline'] = status
            result['restoredBaselineExitCode'] = code
            (args.output / f'{name}-restored-baseline.log').write_text(output)
            if artifact:
                result['nativeArtifactUnchanged'] = native_artifact() == artifact
                save()
                if not result['nativeArtifactUnchanged']:
                    raise RuntimeError('Native artifact changed during the mutation run; evidence is invalid')
            if result['restoredBaseline'] != 'survived':
                save()
                raise RuntimeError(f'{name}: restored baseline failed')
    report['complete'] = not args.list
    if not args.list:
        for name, target in report['targets'].items():
            target['gatePassed'] = passes_assertion_gate(target, args.threshold)
            print(f'{name}: assertion gate {"passed" if target["gatePassed"] else "failed"}; '
                  f'adjusted assertion score={target["adjustedAssertionScoreLowerBound"]}, '
                  f'conventional score={target["adjustedScore"]}, threshold={args.threshold}', flush=True)
        report['gate']['passed'] = all(target['gatePassed'] for target in report['targets'].values())
    save()
    if args.list:
        return 0
    return 0 if report['gate']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
