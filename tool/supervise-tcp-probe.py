"""Private independent observer wrapper; never signals or cancels the workload."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import threading
import time

READY = b'TCP_OBSERVER_CONTROL_READY\n'
CAP = 1024 * 1024
LINE_CAP = 4096


def environment_digest():
    return hashlib.sha256(json.dumps(dict(os.environ), sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def drain(pipe, path, ready, state, is_stdout):
    retained = 0
    try:
        with path.open('wb') as output:
            while True:
                line = pipe.readline(LINE_CAP + 1)
                if not line:
                    break
                keep = min(len(line), max(0, CAP - retained))
                output.write(line[:keep]); retained += keep
                if keep != len(line) or len(line) > LINE_CAP:
                    state['output_incomplete'] = True
                if is_stdout and line == READY:
                    state['ready_monotonic_ns'] = time.monotonic_ns()
                    ready.set()
    except Exception as failure:
        state['reader_error'] = type(failure).__name__
    finally:
        pipe.close()


def wait_ready(observer, ready, seconds=100):
    deadline = time.monotonic() + seconds
    while not ready.wait(.1):
        if observer.poll() is not None:
            raise RuntimeError('Observer exited before readiness; workload not started')
        if time.monotonic() >= deadline:
            raise RuntimeError('Observer readiness deadline; workload not started')
    if observer.poll() is not None:
        raise RuntimeError('Observer not alive after readiness; workload not started')


def run(observer_command, workload_command, output):
    if os.geteuid() == 0:
        raise RuntimeError('Workload supervisor must remain unprivileged')
    if not workload_command:
        raise ValueError('Original workload command required')
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    ready = threading.Event()
    state = {'output_incomplete': False, 'reader_error': None, 'ready_monotonic_ns': None}
    result = {'supervisor_pid': os.getpid(), 'supervisor_uid': os.getuid(), 'supervisor_euid': os.geteuid(),
              'cwd': str(Path.cwd()), 'environment_sha256': environment_digest(),
              'observer_command': observer_command, 'workload_command': workload_command,
              'workload_started': False, 'workload_completed': False, 'workload_exit_code': None,
              'errors': [], 'scope': 'Private observer diagnostic; unchanged independent workload; never acceptance.'}
    observer = subprocess.Popen(observer_command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
    readers = [threading.Thread(target=drain, args=(pipe, output / name, ready, state, stdout), daemon=True)
               for pipe, name, stdout in [(observer.stdout, 'observer.stdout.txt', True),
                                           (observer.stderr, 'observer.stderr.txt', False)]]
    for reader in readers: reader.start()
    try:
        wait_ready(observer, ready)
        result['workload_started_monotonic_ns'] = time.monotonic_ns()
        # No env, UID, argv or session rewrite. The original capture controller
        # retains all of its own deadlines, process groups and cleanup duties.
        workload = subprocess.Popen(workload_command)
        result['workload_pid'] = workload.pid
        result['workload_started'] = True
        # Deliberately independent of observer status: never cancel a started run.
        result['workload_exit_code'] = workload.wait()
        result['workload_completed'] = True
        result['workload_finished_monotonic_ns'] = time.monotonic_ns()
    except Exception as failure:
        result['errors'].append(type(failure).__name__ + ': ' + str(failure)[:256])
    finally:
        try:
            observer.stdin.write(b'STOP\n'); observer.stdin.flush()
        except (BrokenPipeError, OSError) as failure:
            result['errors'].append('Observer control: ' + type(failure).__name__)
        finally:
            try: observer.stdin.close()
            except OSError: pass
        try:
            observer.wait(timeout=35)
        except subprocess.TimeoutExpired:
            result['errors'].append('Root observer did not finish; bounded root deadline remains active')
        for reader in readers: reader.join(timeout=5)
    result.update(state)
    result['observer_exit_code'] = observer.poll()
    result['readers_stopped'] = all(not reader.is_alive() for reader in readers)
    result['passed'] = (result['workload_completed'] and result['workload_exit_code'] == 0
                        and result['observer_exit_code'] == 0 and result['readers_stopped']
                        and not result['errors'] and not state['output_incomplete'] and not state['reader_error'])
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return result['workload_exit_code'] if result['workload_exit_code'] else (0 if result['passed'] else 1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root-observer', type=Path, required=True)
    parser.add_argument('--program', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-seconds', type=float, default=20000)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    observer = ['sudo', '-n', '/usr/bin/python3', str(args.root_observer.resolve(strict=True)),
                '--program', str(args.program.resolve(strict=True)), '--output', str(args.output.resolve() / 'root'),
                '--controlled', '--max-seconds', str(args.max_seconds)]
    raise SystemExit(run(observer, command, args.output))
