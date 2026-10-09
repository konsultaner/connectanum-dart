import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('guard', Path(__file__).with_name('run_native_guardmalloc.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
LOADER = 'dyld[123]: <123> /usr/lib/libgmalloc.dylib\n'
OK = 'test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n'

class GuardMallocChecks(unittest.TestCase):
    def test_requires_actual_loader_and_one_positive_success(self):
        self.assertEqual(guard.observed_result(OK, LOADER, 9), 9)
        for out, err, minimum in [
            (OK, '', 9), (OK, 'DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib', 9),
            (OK, LOADER, 10), (OK.replace('9 passed', '0 passed'), LOADER, 1),
            (OK.replace('0 failed', '1 failed'), LOADER, 9), (OK + OK, LOADER, 9),
            (OK.replace('result: ok', 'result: FAILED'), LOADER, 9), ('', LOADER, 9),
        ]:
            with self.subTest(out=out, err=err, minimum=minimum):
                with self.assertRaises(ValueError):
                    guard.observed_result(out, err, minimum)

    @unittest.skipUnless(os.name == "posix", "Owned process groups require POSIX")
    def test_logs_nonzero_failure_and_partial_timeout(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder)
            result = guard.run_logged([sys.executable, '-c', 'print("fail", flush=True);raise SystemExit(7)'], destination, destination, 'fail', 5)
            self.assertEqual(result['exitCode'], 7)
            self.assertFalse(result['timedOut'])
            self.assertEqual((destination / result['stdoutLog']).read_text(), 'fail\n')
            self.assertEqual(result['stdoutSha256'], guard.sha(destination / result['stdoutLog']))
            command = [sys.executable, '-c', 'import time,sys;print("partial",flush=True);print("error",file=sys.stderr,flush=True);time.sleep(10)']
            result = guard.run_logged(command, destination, destination, 'timeout', .2)
            self.assertTrue(result['timedOut'])
            self.assertNotEqual(result['exitCode'], 0)
            self.assertEqual((destination / result['stdoutLog']).read_text(), 'partial\n')
            self.assertEqual((destination / result['stderrLog']).read_text(), 'error\n')

    @unittest.skipUnless(os.name == "posix", "Owned process groups require POSIX")
    def test_timeout_stops_owned_descendant_even_when_it_ignores_term(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder)
            child_code = 'import signal,time,pathlib;signal.signal(signal.SIGTERM,signal.SIG_IGN);print("ready",flush=True);time.sleep(1);pathlib.Path("escaped").write_text("bad")'
            parent_code = f'import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",{child_code!r}]);time.sleep(10)'
            result = guard.run_logged([sys.executable, '-c', parent_code], destination, destination, 'descendant', .3)
            self.assertTrue(result['timedOut'])
            self.assertIn('ready', (destination / result['stdoutLog']).read_text())
            time.sleep(1)
            self.assertFalse((destination / 'escaped').exists())

    @unittest.skipUnless(os.name == "posix", "Owned process groups require POSIX")
    def test_cleanup_failure_and_interrupt_retain_a_failure_record(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder)
            child = mock.Mock(pid=123, returncode=None)
            child.wait.side_effect = subprocess.TimeoutExpired('test', .2)
            with mock.patch.object(guard.os, 'killpg'), mock.patch.object(guard.subprocess, 'Popen', return_value=child):
                record = {}
                result = guard.run_logged(['test'], destination, destination, 'unreaped', .2, record=record)
                self.assertIs(result, record)
                self.assertTrue(result['timedOut'])
                self.assertIsNone(result['exitCode'])
                self.assertIn('SIGKILL', result['cleanupError'])
                self.assertIn('stderrSha256', result)
            child.wait.side_effect = [KeyboardInterrupt(), 0, 0]
            child.returncode = 0
            with mock.patch.object(guard.os, 'killpg'), mock.patch.object(guard.subprocess, 'Popen', return_value=child):
                record = {}
                with self.assertRaises(KeyboardInterrupt):
                    guard.run_logged(['test'], destination, destination, 'interrupted', .2, record=record)
                self.assertTrue(record['interrupted'])
                self.assertIn('stdoutSha256', record)

    def test_rejects_nonfinite_and_nonpositive_timeouts(self):
        for value in ('nan', 'inf', '-inf', '0', '-1'):
            with self.subTest(value=value):
                result = subprocess.run([sys.executable, guard.__file__, '--output', 'unused-guard-test-output', '--group-timeout=' + value], capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn('Finite positive', result.stderr)

if __name__ == '__main__':
    unittest.main()
