"""Actual two-second UID/env/control smoke. No WAMP observation."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys


def digest():
    return hashlib.sha256(json.dumps(dict(os.environ), sort_keys=True, separators=(',', ':')).encode()).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--program', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert os.geteuid() != 0
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False)
    helper = Path(__file__).with_name('tcp-probe-lifecycle-smoke.py').resolve(strict=True)
    supervisor_path = Path(__file__).with_name('supervise-tcp-probe.py').resolve(strict=True)
    spec = importlib.util.spec_from_file_location('private_supervisor_smoke', supervisor_path)
    supervisor = importlib.util.module_from_spec(spec); spec.loader.exec_module(supervisor)
    dummy = output / 'dummy.py'
    dummy.write_text('''from pathlib import Path
import hashlib,json,os,sys,time
start=time.monotonic_ns()
time.sleep(2)
Path(sys.argv[1]).write_text(json.dumps({'uid':os.getuid(),'euid':os.geteuid(),'pid':os.getpid(),'start':start,'finish':time.monotonic_ns(),'cwd':os.getcwd(),'argv':sys.argv,'environment_sha256':hashlib.sha256(json.dumps(dict(os.environ),sort_keys=True,separators=(',',':')).encode()).hexdigest()}))
''')
    program = args.program.resolve(strict=True)
    root_base = ['sudo', '-n', '/usr/bin/python3', str(helper), '--program', str(program), '--controlled', '--max-seconds', '60']
    # EOF is bounded and must stop its owned tracer gracefully without a workload.
    eof = subprocess.run(root_base + ['--output', str(output / 'eof')], input=b'', capture_output=True)
    (output / 'eof-driver.stdout').write_bytes(eof.stdout); (output / 'eof-driver.stderr').write_bytes(eof.stderr)
    assert eof.returncode == 0
    eof_result = json.loads((output / 'eof/result.json').read_text())
    assert eof_result['passed'] and eof_result['stop_reason'] == 'EOF'
    assert eof_result['observer_uid'] == 0 and eof_result['owned_tracer_stop_stages'] == ['SIGINT']
    command = [sys.executable, str(dummy), str(output / 'workload.json')]
    assert supervisor.run(root_base + ['--output', str(output / 'controlled/root')], command, output / 'controlled') == 0
    wrapper = json.loads((output / 'controlled/result.json').read_text())
    root = json.loads((output / 'controlled/root/result.json').read_text())
    workload = json.loads((output / 'workload.json').read_text())
    assert workload['uid'] == workload['euid'] == wrapper['supervisor_uid'] == os.getuid() != 0
    assert workload['environment_sha256'] == wrapper['environment_sha256'] == digest()
    assert workload['cwd'] == wrapper['cwd'] == str(Path.cwd())
    assert workload['finish'] - workload['start'] >= 2_000_000_000
    assert wrapper['workload_command'] == command
    assert root['passed'] and root['stop_reason'] == 'STOP' and root['observer_uid'] == 0
    assert root['ready_at_monotonic_ns'] <= wrapper['ready_monotonic_ns'] <= wrapper['workload_started_monotonic_ns'] <= workload['start'] < workload['finish'] <= wrapper['workload_finished_monotonic_ns'] <= root['finished_monotonic_ns']
    # Deliberate observer death after readiness cannot stop the sibling dummy.
    failed_observer = [sys.executable, '-c', "import time; print('TCP_OBSERVER_CONTROL_READY',flush=True);time.sleep(.2);raise SystemExit(9)"]
    failed_command = [sys.executable, str(dummy), str(output / 'surviving-workload.json')]
    assert supervisor.run(failed_observer, failed_command, output / 'observer-failure') == 1
    failed = json.loads((output / 'observer-failure/result.json').read_text())
    survivor = json.loads((output / 'surviving-workload.json').read_text())
    assert failed['workload_completed'] and failed['workload_exit_code'] == 0 and failed['observer_exit_code'] == 9
    assert survivor['uid'] == os.getuid() and survivor['finish'] - survivor['start'] >= 2_000_000_000
    assert survivor['environment_sha256'] == digest()
    result = {'passed': True, 'unprivileged_uid': os.getuid(), 'environment_preserved': True, 'command_preserved': True,
              'two_second_dummy_completed': True, 'graceful_stop_and_eof': True, 'failed_observer_did_not_cancel_dummy': True,
              'scope': 'Private Linux IPC/UID/lifecycle smoke only; no WAMP or performance acceptance.'}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
