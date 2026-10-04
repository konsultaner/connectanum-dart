#!/usr/bin/env python3
"""Run observed native ownership groups with macOS GuardMalloc interposition."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time

GROUPS = (
    ('runtime::owned_buffers::tests::', 9),
    ('runtime::ffi::flatbuffers_e2ee_tests::', 9),
    ('runtime::ffi::segmented_forwarding_tests::', 9),
    ('runtime::native_frames::tests::', 14),
    ('runtime::external_leases::tests::', 7),
    ('runtime::external_lease_ffi::tests::', 8),
    ('runtime::external_network_tests::', 1),
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def observed_result(stdout, stderr, minimum):
    # Check actual loader output, not an environment variable or command echo.
    loaded = bool(re.search(r'^dyld\[\d+\]:.* /usr/lib/libgmalloc\.dylib$', stderr, re.M))
    summary = re.findall(r'^test result: ok\. (\d+) passed; (\d+) failed;.*$', stdout, re.M)
    if not loaded or len(summary) != 1:
        raise ValueError('Missing GuardMalloc loader or unique Rust test summary')
    passed, failed = map(int, summary[0])
    if failed or passed < minimum:
        raise ValueError(f'Observed {passed} cases, expected at least {minimum}, failed={failed}')
    return passed


def source_inventory(root):
    paths = []
    for directory, folders, names in os.walk(root / 'native/transport'):
        folders[:] = [name for name in folders if name not in {'target', '.git'}]
        paths.extend(Path(directory) / name for name in names
                     if name.endswith('.rs') or name in {'Cargo.toml', 'Cargo.lock'})
    paths.extend((root / 'schemas/wamp_flatbuffers').rglob('*'))
    return {str(p.relative_to(root)): sha(p) for p in sorted(paths) if p.is_file()}


def stop_process_group(child):
    # Every spawned command has its own process group; never signal a shared shell.
    errors = []
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            pass
        except OSError as error:
            errors.append(str(error))
        try:
            child.wait(timeout=2 if sig == signal.SIGTERM else 5)
        except subprocess.TimeoutExpired:
            if sig == signal.SIGKILL:
                errors.append('Command did not exit after SIGKILL')
    return '; '.join(errors) or None


def run_logged(command, cwd, destination, stem, timeout, environment=None, record=None):
    out = destination / f'{stem}.stdout.log'
    err = destination / f'{stem}.stderr.log'
    result = record if record is not None else {}
    result.update(command=command, stdoutLog=out.name, stderrLog=err.name,
                  startedUnix=time.time(), timedOut=False, deadlineSeconds=timeout)
    try:
        with out.open('w') as stdout, err.open('w') as stderr:
            child = subprocess.Popen(command, cwd=cwd, env=environment,
                                     stdout=stdout, stderr=stderr, start_new_session=True)
            result['pid'] = child.pid
            try:
                result['exitCode'] = child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                result['timedOut'] = True
                result['cleanupError'] = stop_process_group(child)
                result['exitCode'] = child.returncode
            except BaseException:
                result['interrupted'] = True
                result['cleanupError'] = stop_process_group(child)
                result['exitCode'] = child.returncode
                raise
    finally:
        result['completedUnix'] = time.time()
        for name, path in [('stdout', out), ('stderr', err)]:
            if path.is_file():
                result[name + 'Sha256'] = sha(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--group-timeout', type=float, default=120)
    args = parser.parse_args()
    if not math.isfinite(args.group_timeout) or args.group_timeout <= 0:
        parser.error('Finite positive group timeout required')
    root = args.repo.resolve(strict=True)
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    report_path = destination / 'report.json'
    report = {'status': 'running', 'instrumentation': 'macOS GuardMalloc',
              'startedUnix': time.time(), 'runnerSha256': sha(__file__), 'platform': platform.platform(),
              'machine': platform.machine(), 'groups': []}
    def save():
        report_path.write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        if sys.platform != 'darwin':
            raise RuntimeError('GuardMalloc requires macOS; no instrumentation pass on this platform')
        initial_sources = source_inventory(root)
        report['initialSourceHashes'] = initial_sources
        lock = root / 'native/transport/Cargo.lock'
        report['lockfileInitiallyPresent'] = lock.is_file()
        if not lock.is_file():
            resolution = {}
            report['dependencyResolution'] = resolution
            run_logged(['cargo', 'generate-lockfile'], root / 'native/transport',
                       destination, 'resolve', 180, record=resolution)
            save()
            if resolution['timedOut'] or resolution['exitCode'] != 0 or resolution.get('cleanupError'):
                raise RuntimeError('Native dependency resolution failed or timed out')
        current_sources = source_inventory(root)
        if {name: digest for name, digest in current_sources.items()
                if name != 'native/transport/Cargo.lock'} != {
                name: digest for name, digest in initial_sources.items()
                if name != 'native/transport/Cargo.lock'}:
            raise RuntimeError('Native source changed during dependency resolution')
        report['sourceHashes'] = current_sources
        (destination / 'Cargo.lock').write_bytes(lock.read_bytes())
        report['dependencyLockSha256'] = sha(lock)
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        report['head'] = head.stdout.strip() if head.returncode == 0 else None
        dirty = subprocess.run(['git', 'status', '--porcelain'], cwd=root, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        report['dirty'] = bool(dirty.stdout) if dirty.returncode == 0 else None
        command = ['cargo', 'test', '--locked', '-p', 'ct_ffi', '--features', 'ffi-test',
                   '--lib', '--no-run', '--message-format=json']
        build = {}
        report['build'] = build
        run_logged(command, root / 'native/transport', destination, 'build', 900, record=build)
        save()
        if build['timedOut'] or build['exitCode'] != 0 or build.get('cleanupError'):
            raise RuntimeError('Native ownership test compilation failed or timed out')
        artifacts = [json.loads(line) for line in
                     (destination / build['stdoutLog']).read_text().splitlines()
                     if line.startswith('{')]
        binaries = [item['executable'] for item in artifacts
                    if item.get('reason') == 'compiler-artifact' and item.get('executable')
                    and item.get('target', {}).get('name') == 'ct_ffi']
        if len(binaries) != 1:
            raise RuntimeError('Expected exactly one native ownership test executable')
        binary = Path(binaries[0])
        report['executableSha256'] = sha(binary)
        environment = dict(os.environ, DYLD_INSERT_LIBRARIES='/usr/lib/libgmalloc.dylib',
                           DYLD_PRINT_LIBRARIES='1', MallocScribble='1')
        for index, (group, minimum) in enumerate(GROUPS):
            entry = {'group': group, 'minimumCases': minimum, 'status': 'running'}
            report['groups'].append(entry)
            save()
            result = run_logged([str(binary), group, '--test-threads=1', '--nocapture'],
                                root, destination, str(index), args.group_timeout, environment, record=entry)
            entry.update(result)
            save()
            if result['timedOut'] or result['exitCode'] != 0 or result.get('cleanupError'):
                entry['status'] = 'failed'
                raise RuntimeError(f'Instrumented native group failed or timed out: {group}')
            entry.update(cases=observed_result(
                (destination / result['stdoutLog']).read_text(),
                (destination / result['stderrLog']).read_text(), minimum), status='passed')
            save()
        if (source_inventory(root) != report['sourceHashes'] or
                sha(binary) != report['executableSha256'] or
                sha(__file__) != report['runnerSha256']):
            raise RuntimeError('Native source or executable changed during instrumented checks')
        report.update(status='passed', cases=sum(x['cases'] for x in report['groups']),
                      completedUnix=time.time())
        save()
        print(f"GuardMalloc: {report['cases']} native ownership cases passed; report {report_path}")
        return 0
    except (Exception, KeyboardInterrupt) as error:
        for entry in report['groups']:
            if entry['status'] == 'running':
                entry['status'] = 'failed'
        report.update(status='failed', error=str(error), completedUnix=time.time())
        save()
        print(f'GuardMalloc failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
