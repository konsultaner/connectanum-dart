"""Private read-only probe startup/cleanup smoke; never launches a workload."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import signal
import subprocess
import threading
import time

READY = b'__BPFTRACE_NOTIFY_PROBES_ATTACHED\n'
CAP = 1024 * 1024
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


def run_smoke(program, output):
    if os.geteuid() != 0:
        raise RuntimeError('Run this private smoke as root; it starts no workload')
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
    try:
        deadline = time.monotonic() + 90
        while not ready.wait(0.1):
            if process.poll() is not None:
                raise RuntimeError('Tracer exited before actual attachment marker')
            if time.monotonic() >= deadline:
                raise RuntimeError('Actual attachment marker was not observed')
        if process.poll() is not None:
            raise RuntimeError('Tracer was not alive after attachment')
        # Two seconds is the observation duration after actual readiness, not
        # a substitute for observing that all hooks have attached.
        time.sleep(2)
        if process.poll() is not None:
            raise RuntimeError('Tracer exited during smoke observation')
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
              'program_unchanged': program_unchanged,
              'observer_pid': os.getpid(), 'tracer_launcher_pid': process.pid,
              'started_monotonic_ns': started, 'finished_monotonic_ns': time.monotonic_ns(),
              'actual_attachment_marker_observed': ready.is_set(), 'begin_and_end': complete,
              'owned_tracer_stop_stages': stop_stages, 'tracer_stopped': stopped,
              'tracer_exit_code': process.returncode, 'reader_threads_stopped': readers_stopped,
              **snapshot, 'scope': 'Private attachment/owned cleanup smoke only. No workload or kernel-path/performance acceptance.'}
    result['passed'] = all([ready.is_set(), complete, program_unchanged, stop_stages == ['SIGINT'], stopped, process.returncode == 0,
                            result['reader_threads_stopped'], not snapshot['truncated'], snapshot['error_count'] == 0])
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--program', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(run_smoke(args.program, args.output))
