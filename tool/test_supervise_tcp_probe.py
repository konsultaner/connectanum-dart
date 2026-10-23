from pathlib import Path
from unittest import mock
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('private_supervisor', Path(__file__).with_name('supervise-tcp-probe.py'))
supervisor = importlib.util.module_from_spec(spec); spec.loader.exec_module(supervisor)

class FakeObserver:
    pid = 12345
    def __init__(self, failed=False):
        self.stdin = io.BytesIO(); self.stdout = io.BytesIO(supervisor.READY); self.stderr = io.BytesIO()
        self.returncode = None; self.failed = failed
    def poll(self): return self.returncode
    def wait(self, timeout): self.returncode = 1 if self.failed else 0; return self.returncode

class SupervisorTests(unittest.TestCase):
    def test_root_supervisor_rejected_before_any_launch(self):
        with mock.patch.object(supervisor.os, 'geteuid', return_value=0), mock.patch.object(supervisor.subprocess, 'Popen') as start:
            with self.assertRaisesRegex(RuntimeError, 'unprivileged'): supervisor.run(['observer'], ['original'], Path('/unused'))
        start.assert_not_called()

    def exercise(self, failed=False, workload_code=0):
        observer = FakeObserver(failed)
        workload = mock.Mock(pid=456, wait=mock.Mock(return_value=workload_code))
        def launch(command, **kwargs):
            if command == ['observer']:
                self.assertTrue(kwargs['start_new_session']); return observer
            self.assertEqual(command, ['original', '--max-seconds', '19800'])
            self.assertEqual(kwargs, {})
            if failed: observer.returncode = 1
            return workload
        with tempfile.TemporaryDirectory() as d:
            output = Path(d) / 'result'
            with mock.patch.object(supervisor.os, 'geteuid', return_value=1001), mock.patch.object(supervisor.subprocess, 'Popen', side_effect=launch) as start, mock.patch('builtins.print'):
                code = supervisor.run(['observer'], ['original', '--max-seconds', '19800'], output)
            result = json.loads((output / 'result.json').read_text())
        self.assertEqual(start.call_count, 2); workload.wait.assert_called_once_with()
        workload.kill.assert_not_called(); workload.terminate.assert_not_called(); workload.send_signal.assert_not_called()
        return code, result

    def test_observer_failure_after_launch_never_interrupts_original_workload(self):
        code, result = self.exercise(failed=True)
        self.assertEqual(code, 1); self.assertTrue(result['workload_completed']); self.assertEqual(result['workload_exit_code'], 0)

    def test_original_nonzero_result_is_preserved(self):
        code, result = self.exercise(workload_code=7)
        self.assertEqual(code, 7); self.assertTrue(result['workload_completed'])

    def test_success_requires_observer_and_original_workload_completion(self):
        code, result = self.exercise()
        self.assertEqual(code, 0); self.assertTrue(result['passed']); self.assertEqual(result['observer_exit_code'], 0)

    def test_no_observed_readiness_prevents_workload_launch(self):
        observer = FakeObserver(); observer.returncode = 1; observer.stdout = io.BytesIO()
        with tempfile.TemporaryDirectory() as d, mock.patch.object(supervisor.os, 'geteuid', return_value=1001), mock.patch.object(supervisor.subprocess, 'Popen', return_value=observer) as start, mock.patch('builtins.print'):
            self.assertEqual(supervisor.run(['observer'], ['original'], Path(d) / 'result'), 1)
        self.assertEqual(start.call_count, 1)

if __name__ == '__main__': unittest.main()
