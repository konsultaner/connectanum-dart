"""Private read-only probe startup/cleanup smoke; never launches a workload."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import selectors
import sys
import os
import signal
import subprocess
import threading
import time

READY = b'__BPFTRACE_NOTIFY_PROBES_ATTACHED\n'
CAP = 64 * 1024 * 1024
LINE_CAP = 4096


def record_error(state, lock, message):
    with lock:
        state['error_count'] += 1
        if len(state['errors']) < 8:
            state['errors'].append(message[:512])


def read_output(pipe, path, ready, state, lock, is_stderr):
    retained = 0
    try:
        with path.open('wb') as target:
            while True:
                line = pipe.readline(LINE_CAP + 1)
                if not line:
                    break
                if len(line) > LINE_CAP:
                    record_error(state, lock, 'oversized output line')
                allowed = min(len(line), max(0, CAP - retained))
                target.write(line[:allowed])
                retained += allowed
                if allowed != len(line):
                    with lock:
                        state['truncated'] = True
                if is_stderr and line == READY:
                    with lock:
                        state['ready_at_monotonic_ns'] = time.monotonic_ns()
                    ready.set()
                if any(word in line.lower() for word in [b'lost ', b'error:', b'warning:']):
                    record_error(state, lock, line.decode(errors='replace').strip())
    except Exception as failure:
        record_error(state, lock, type(failure).__name__ + ': ' + str(failure)[:256])
    finally:
        pipe.close()


def stop_owned_tracer(process):
    """The root smoke owns a new process session; never signal another group."""
    stages = []
    for kind, wait in [(signal.SIGINT, 10), (signal.SIGTERM, 5), (signal.SIGKILL, 5)]:
        if process.poll() is not None:
            return stages, True
        if os.getpgid(process.pid) != process.pid:
            # Still our direct child; do not signal an unexpected process group.
            process.kill()
            stages.append('direct-child-kill-after-group-mismatch')
        else:
            os.killpg(process.pid, kind)
            stages.append(kind.name)
        try:
            process.wait(timeout=wait)
            return stages, True
        except subprocess.TimeoutExpired:
            continue
    return stages, process.poll() is not None


def validate_control_seconds(value):
    if not math.isfinite(value) or not 0 < value <= 20000:
        raise ValueError('control deadline must be finite, positive and at most 20000 seconds')
    return value


def wait_control(descriptor, process, max_seconds):
    """Bounded IPC only; this root process never owns or launches a workload."""
    validate_control_seconds(max_seconds)
    deadline = time.monotonic() + max_seconds
    pending = b''
    with selectors.DefaultSelector() as selector:
        selector.register(descriptor, selectors.EVENT_READ)
        while True:
            if process.poll() is not None:
                raise RuntimeError('Tracer exited during controlled observation')
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('Controlled observation deadline expired')
            if not selector.select(min(.1, remaining)):
                continue
            chunk = os.read(descriptor, 64)
            if not chunk:
                if pending:
                    raise RuntimeError('Incomplete control command at EOF')
                return 'EOF'
            pending += chunk
            if len(pending) > 5 or not b'STOP\n'.startswith(pending):
                raise RuntimeError('Invalid or oversized control command')
            if pending == b'STOP\n':
                return 'STOP'


def run_smoke(program, output, control_descriptor=None, max_seconds=20000):
    if os.geteuid() != 0:
        raise RuntimeError('Run this private smoke as root; it starts no workload')
    if control_descriptor is not None:
        validate_control_seconds(max_seconds)
    program = program.resolve(strict=True)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    version = subprocess.check_output(['bpftrace', '--version'], text=True).strip()
    if version != 'bpftrace v0.20.2':
        raise RuntimeError('This private readiness contract requires bpftrace v0.20.2')
    program_hash = hashlib.sha256(program.read_bytes()).hexdigest()
    command = ['bpftrace', '-q', str(program)]
    environment = {**os.environ, '__BPFTRACE_NOTIFY_PROBES_ATTACHED': '1'}
    state = {'errors': [], 'error_count': 0, 'truncated': False, 'ready_at_monotonic_ns': None}
    ready = threading.Event()
    lock = threading.Lock()
    started = time.monotonic_ns()
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True, env=environment)
    readers = [threading.Thread(target=read_output, args=(pipe, output / name, ready, state, lock, error), daemon=True)
               for pipe, name, error in [(process.stdout, 'trace.txt', False),
                                         (process.stderr, 'trace.stderr.txt', True)]]
    for reader in readers:
        reader.start()
    stop_stages = []
    stopped = False
    stop_reason = None
    try:
        deadline = time.monotonic() + 90
        while not ready.wait(0.1):
            if process.poll() is not None:
                raise RuntimeError('Tracer exited before actual attachment marker')
            if time.monotonic() >= deadline:
                raise RuntimeError('Actual attachment marker was not observed')
        if process.poll() is not None:
            raise RuntimeError('Tracer was not alive after attachment')
        if control_descriptor is None:
            # A duration after actual attachment, not a readiness substitute.
            time.sleep(2)
            if process.poll() is not None:
                raise RuntimeError('Tracer exited during smoke observation')
            stop_reason = 'SMOKE_DURATION'
        else:
            print('TCP_OBSERVER_CONTROL_READY', flush=True)
            stop_reason = wait_control(control_descriptor, process, max_seconds)
    except Exception as failure:
        record_error(state, lock, str(failure))
    finally:
        try:
            stop_stages, stopped = stop_owned_tracer(process)
        except OSError as failure:
            record_error(state, lock, 'Tracer stop failed: ' + str(failure))
        if not stopped:
            record_error(state, lock, 'Tracer did not stop; no replay is permitted')
        if stop_stages != ['SIGINT']:
            record_error(state, lock, 'Tracer did not complete the expected graceful stop')
        for reader in readers:
            reader.join(timeout=5)
    readers_stopped = all(not reader.is_alive() for reader in readers)
    text = ''
    if readers_stopped:
        try:
            text = (output / 'trace.txt').read_text(errors='replace')
        except OSError as failure:
            record_error(state, lock, 'Trace read failed: ' + str(failure))
    else:
        record_error(state, lock, 'Trace readers did not finish; no partial file is accepted')
    complete = (text.count('TCP_PRUNE_BEGIN\n') == 1 and text.count('TCP_PRUNE_END\n') == 1
                and text.index('TCP_PRUNE_BEGIN\n') < text.index('TCP_PRUNE_END\n'))
    with lock:
        snapshot = {**state, 'errors': list(state['errors'])}
    try:
        program_unchanged = hashlib.sha256(program.read_bytes()).hexdigest() == program_hash
    except OSError:
        program_unchanged = False
    result = {'command': command, 'version': version, 'program_sha256': program_hash,
              'program_unchanged': program_unchanged, 'per_stream_output_cap_bytes': CAP,
              'observer_pid': os.getpid(), 'observer_uid': os.getuid(), 'stop_reason': stop_reason,
              'control_max_seconds': max_seconds if control_descriptor is not None else None, 'tracer_launcher_pid': process.pid,
              'started_monotonic_ns': started, 'finished_monotonic_ns': time.monotonic_ns(),
              'actual_attachment_marker_observed': ready.is_set(), 'begin_and_end': complete,
              'owned_tracer_stop_stages': stop_stages, 'tracer_stopped': stopped,
              'tracer_exit_code': process.returncode, 'reader_threads_stopped': readers_stopped,
              **snapshot, 'scope': 'Private attachment/owned cleanup smoke only. No workload or kernel-path/performance acceptance.'}
    result['passed'] = all([ready.is_set(), stop_reason is not None, complete, program_unchanged, stop_stages == ['SIGINT'], stopped, process.returncode == 0,
                            result['reader_threads_stopped'], not snapshot['truncated'], snapshot['error_count'] == 0])
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--program', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--controlled', action='store_true')
    parser.add_argument('--max-seconds', type=float, default=20000)
    args = parser.parse_args()
    raise SystemExit(run_smoke(args.program, args.output, sys.stdin.fileno() if args.controlled else None, args.max_seconds))
