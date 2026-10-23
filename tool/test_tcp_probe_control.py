from pathlib import Path
from unittest import mock
import importlib.util
import os
import subprocess
import tempfile
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location('private_tcp_control', Path(__file__).with_name('tcp-probe-lifecycle-smoke.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class ControlTests(unittest.TestCase):
    def control(self, content, closed=True, timeout=2, process=None):
        read, write = os.pipe()
        if content: os.write(write, content)
        if closed: os.close(write)
        try:
            return probe.wait_control(read, process or mock.Mock(poll=lambda: None), timeout)
        finally:
            os.close(read)
            if not closed: os.close(write)

    def test_stop_and_eof_are_distinct_explicit_terminations(self):
        self.assertEqual(self.control(b'STOP\n'), 'STOP')
        self.assertEqual(self.control(b''), 'EOF')

    def test_fragmented_command_is_reassembled_without_blocking_reader(self):
        read, write = os.pipe()
        def send():
            for part in [b'S', b'TO', b'P\n']:
                os.write(write, part)
                time.sleep(.01)
            os.close(write)
        thread = threading.Thread(target=send); thread.start()
        try: self.assertEqual(probe.wait_control(read, mock.Mock(poll=lambda: None), 2), 'STOP')
        finally: thread.join(); os.close(read)

    def test_invalid_oversized_and_partial_eof_cannot_pass(self):
        for payload in [b'FAIL\n', b'STOP\nx', b'x' * 100, b'STO']:
            with self.subTest(payload=payload[:10]), self.assertRaisesRegex(RuntimeError, 'control'):
                self.control(payload)

    def test_dead_tracer_cannot_be_accepted_as_stop(self):
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            self.control(b'STOP\n', process=mock.Mock(poll=lambda: 1))

    def test_missing_control_has_a_finite_deadline(self):
        with self.assertRaisesRegex(RuntimeError, 'deadline'):
            self.control(b'', closed=False, timeout=.01)

    def test_control_deadline_is_bounded_and_finite(self):
        for value in [0, -1, float('inf'), float('nan'), 20001]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                probe.validate_control_seconds(value)

if __name__ == '__main__': unittest.main()
