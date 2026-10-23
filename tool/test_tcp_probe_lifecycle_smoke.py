from pathlib import Path
from unittest import mock
import importlib.util
import io
import signal
import subprocess
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location('private_tcp_lifecycle', Path(__file__).with_name('tcp-probe-lifecycle-smoke.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FakeProcess:
    pid = 424242

    def __init__(self, failures=0, text=b'TCP_PRUNE_BEGIN\nTCP_PRUNE_END\n'):
        self.returncode = None
        self.failures = failures
        self.stdout = io.BytesIO(text)
        self.stderr = io.BytesIO(probe.READY)
        self.kill_called = False

    def poll(self):
        return self.returncode

    def wait(self, timeout):
        if self.failures:
            self.failures -= 1
            raise subprocess.TimeoutExpired('owned fake', timeout)
        self.returncode = 0
        return 0

    def kill(self):
        self.kill_called = True


class LifecycleTests(unittest.TestCase):
    def read(self, payload):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'output'
            state = {'errors': [], 'error_count': 0, 'truncated': False, 'ready_at_monotonic_ns': None}
            ready = threading.Event()
            probe.read_output(io.BytesIO(payload), target, ready, state, threading.Lock(), True)
            return target.read_bytes(), state, ready.is_set()

    def test_readline_splits_adjacent_messages_and_observes_exact_ready_line(self):
        raw = b'preceding line\n' + probe.READY + b'following line\n'
        data, state, ready = self.read(raw)
        self.assertEqual(data, raw)
        self.assertTrue(ready)
        self.assertEqual(state['error_count'], 0)

    def test_embedded_marker_is_not_attachment_proof(self):
        _, state, ready = self.read(b'not a marker: ' + probe.READY)
        self.assertFalse(ready)
        self.assertIsNone(state['ready_at_monotonic_ns'])

    def test_output_cap_and_error_list_are_bounded_while_pipe_is_drained(self):
        raw = (b'x' * (probe.LINE_CAP + 1)) * 400
        data, state, ready = self.read(raw)
        self.assertEqual(len(data), probe.CAP)
        self.assertTrue(state['truncated'])
        self.assertGreater(state['error_count'], 8)
        self.assertEqual(len(state['errors']), 8)
        self.assertFalse(ready)

    def test_lost_events_and_warnings_fail_explicitly(self):
        _, state, ready = self.read(b'Lost 2 events\nWARNING: incomplete capture\n' + probe.READY)
        self.assertTrue(ready)
        self.assertEqual(state['error_count'], 2)

    def test_stop_signals_only_owned_verified_group(self):
        process = FakeProcess()
        with mock.patch.object(probe.os, 'getpgid', return_value=process.pid), mock.patch.object(probe.os, 'killpg') as kill:
            stages, stopped = probe.stop_owned_tracer(process)
        self.assertTrue(stopped)
        self.assertEqual(stages, ['SIGINT'])
        kill.assert_called_once_with(process.pid, signal.SIGINT)

    def test_nonresponsive_tracer_is_escalated_and_cannot_be_graceful_success(self):
        process = FakeProcess(failures=2)
        with mock.patch.object(probe.os, 'getpgid', return_value=process.pid), mock.patch.object(probe.os, 'killpg') as kill:
            stages, stopped = probe.stop_owned_tracer(process)
        self.assertTrue(stopped)
        self.assertEqual(stages, ['SIGINT', 'SIGTERM', 'SIGKILL'])
        self.assertEqual(kill.call_args_list, [mock.call(process.pid, kind) for kind in [signal.SIGINT, signal.SIGTERM, signal.SIGKILL]])
        self.assertNotEqual(stages, ['SIGINT'])

    def test_group_mismatch_never_signals_an_unowned_group(self):
        process = FakeProcess()
        with mock.patch.object(probe.os, 'getpgid', return_value=process.pid + 1), mock.patch.object(probe.os, 'killpg') as kill:
            stages, stopped = probe.stop_owned_tracer(process)
        self.assertTrue(stopped)
        self.assertTrue(process.kill_called)
        self.assertEqual(stages, ['direct-child-kill-after-group-mismatch'])
        kill.assert_not_called()

    def test_exited_child_is_never_signalled(self):
        process = FakeProcess()
        process.returncode = 0
        with mock.patch.object(probe.os, 'killpg') as kill:
            self.assertEqual(probe.stop_owned_tracer(process), ([], True))
        kill.assert_not_called()

    def test_nonroot_controller_cannot_start_a_tracer(self):
        with mock.patch.object(probe.os, 'geteuid', return_value=1000), mock.patch.object(probe.subprocess, 'Popen') as start:
            with self.assertRaisesRegex(RuntimeError, 'root'):
                probe.run_smoke(Path('/not-opened'), Path('/not-created'))
        start.assert_not_called()

    def smoke(self, text):
        with tempfile.TemporaryDirectory() as directory:
            program = Path(directory) / 'program.bt'
            program.write_text('private fixture, never executed')
            process = FakeProcess(text=text)
            with mock.patch.object(probe.os, 'geteuid', return_value=0), mock.patch.object(probe.os, 'getpgid', return_value=process.pid), mock.patch.object(probe.os, 'killpg'), mock.patch.object(probe.subprocess, 'check_output', return_value='bpftrace v0.20.2\n'), mock.patch.object(probe.subprocess, 'Popen', return_value=process), mock.patch.object(probe.time, 'sleep'), mock.patch('builtins.print'):
                code = probe.run_smoke(program, Path(directory) / 'output')
            return code

    def test_ordered_complete_trace_and_owned_cleanup_can_pass(self):
        self.assertEqual(self.smoke(b'TCP_PRUNE_BEGIN\nTCP_PRUNE_END\n'), 0)

    def test_reversed_or_duplicate_markers_are_not_a_complete_trace(self):
        for text in [b'TCP_PRUNE_END\nTCP_PRUNE_BEGIN\n', b'TCP_PRUNE_BEGIN\nTCP_PRUNE_BEGIN\nTCP_PRUNE_END\n']:
            self.assertEqual(self.smoke(text), 1)


if __name__ == '__main__':
    unittest.main()
