"""Process ownership and evidence checks for the Linux MQTT diagnostic."""
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import profile_mqtt_native as profiler


class FakeProcess:
    pid = 42

    def __init__(self):
        self.returncode = None
        self.signals = []
        self.terminated = False
        self.killed = False
        self.hang = False

    def poll(self):
        return self.returncode

    def send_signal(self, value):
        self.signals.append(value)

    def wait(self, timeout=None):
        if self.hang and not self.killed:
            raise subprocess.TimeoutExpired("perf", timeout)
        if self.returncode is None:
            self.returncode = 0
        return self.returncode

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True
        self.returncode = -9


class NativeMqttProfileTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.library = self.root / "input.so"
        self.library.write_bytes(b"native library")
        self.output = self.root / "profile"
        self.budget = {"messages_per_run": 5, "repetitions": 5, "payload_bytes": 128,
                       "profile": "mqtt5-ws-test", "transport": "ws"}
        self.broker = FakeProcess()
        self.sampler = FakeProcess()
        self.popen = self.enterContext(patch.object(
            profiler.subprocess, "Popen", side_effect=[self.broker, self.sampler]))
        self.enterContext(patch.object(profiler, "wait_for_listener"))
        self.enterContext(patch.object(profiler, "available_port", return_value=12345))
        self.enterContext(patch.object(profiler.time, "sleep"))
        self.enterContext(patch.object(profiler, "provenance", return_value={"cpu_model": "test CPU"}))
        self.row = {"sent": 5, "received": 5, "received_per_subscriber": [5], "duplicates": 0}
        self.client = self.enterContext(patch.object(
            profiler, "run_client_with_cpu", side_effect=lambda *_: (
                subprocess.CompletedProcess([], 0, json.dumps(self.row), ""), 0.1)))
        self.symbols = "DartWorker mqtt-broker.aot MqttQos0Broker._publish\nct_poll_mqtt_chunk\n"
        self.commands = []
        self.enterContext(patch.object(profiler.subprocess, "run", side_effect=self.run_command))

    def run_command(self, command, **kwargs):
        self.commands.append(command)
        if command[0] == "dart":
            Path(command[-1]).write_bytes(b"AOT binary")
        elif command[1] == "--version":
            return subprocess.CompletedProcess(command, 0, "Dart SDK version: test", "")
        else:
            kwargs["stdout"].write(self.symbols)
        return subprocess.CompletedProcess(command, 0)

    def profile(self):
        return profiler.profile_native(self.budget, self.library, self.output, "test-perf")

    def test_success_retains_exact_rows_and_uses_snapshot_for_symbols(self):
        metadata = self.profile()
        self.assertTrue(metadata["diagnosticOnly"])
        self.assertEqual(metadata["budget"], self.budget)
        self.assertEqual(metadata["runtimeVersion"], "Dart SDK version: test")
        compiles = [command for command in self.commands if command[0] == "dart"]
        self.assertEqual(compiles[0][2], "aot-snapshot")
        self.assertEqual(compiles[1][2], "exe")
        self.assertEqual(self.client.call_count, 5)
        rows = [json.loads(line) for line in (self.output / "raw.jsonl").read_text().splitlines()]
        self.assertEqual([row["run"] for row in rows], [1, 2, 3, 4, 5])
        self.assertEqual(sum(row["received"] for row in rows), 25)
        self.assertEqual((self.output / "libct_ffi.so").read_bytes(), self.library.read_bytes())
        self.assertEqual(self.sampler.signals, [signal.SIGINT])
        self.assertTrue(self.broker.terminated)
        self.assertFalse(self.sampler.killed)

    def test_perf_startup_failure_stops_broker_without_running_clients(self):
        self.popen.side_effect = [self.broker, OSError("perf unavailable")]
        with self.assertRaisesRegex(OSError, "perf unavailable"):
            self.profile()
        self.assertTrue(self.broker.terminated)
        self.client.assert_not_called()

    def test_failed_broker_readiness_does_not_start_profiler(self):
        profiler.wait_for_listener.side_effect = RuntimeError("broker startup failed")
        with self.assertRaisesRegex(RuntimeError, "broker startup failed"):
            self.profile()
        self.assertEqual(self.popen.call_count, 1)
        self.assertTrue(self.broker.terminated)
        self.client.assert_not_called()

    def test_client_crash_stops_sampler_and_broker(self):
        self.client.side_effect = RuntimeError("client crashed")
        with self.assertRaisesRegex(RuntimeError, "client crashed"):
            self.profile()
        self.assertEqual(self.sampler.signals, [signal.SIGINT])
        self.assertTrue(self.broker.terminated)

    def test_lost_delivery_is_rejected_and_retains_completed_rows(self):
        good = subprocess.CompletedProcess([], 0, json.dumps(self.row), "")
        bad = subprocess.CompletedProcess([], 0, json.dumps({**self.row, "received": 4}), "")
        self.client.side_effect = [(good, 0.1), (bad, 0.1)]
        with self.assertRaisesRegex(RuntimeError, "every message exactly"):
            self.profile()
        self.assertEqual(len((self.output / "raw.jsonl").read_text().splitlines()), 1)
        self.assertTrue(self.broker.terminated)
        self.assertEqual(self.sampler.signals, [signal.SIGINT])

    def test_early_perf_exit_prevents_unprofiled_workload(self):
        self.sampler.returncode = 1
        with self.assertRaisesRegex(RuntimeError, "before sampling"):
            self.profile()
        self.client.assert_not_called()
        self.assertTrue(self.broker.terminated)

    def test_stuck_perf_is_killed_and_broker_still_stops(self):
        self.sampler.hang = True
        with self.assertRaisesRegex(RuntimeError, "did not stop"):
            self.profile()
        self.assertTrue(self.sampler.killed)
        self.assertTrue(self.broker.terminated)

    def test_perf_failure_at_shutdown_rejects_capture_after_cleanup(self):
        def failed_wait(timeout=None):
            self.sampler.returncode = 1
            return 1
        self.sampler.wait = failed_wait
        with self.assertRaisesRegex(RuntimeError, "failed to record samples"):
            self.profile()
        self.assertTrue(self.broker.terminated)
        self.assertFalse((self.output / "profile.txt").exists())

    def test_unsymbolized_report_is_not_accepted_as_a_profile(self):
        self.symbols = "DartWorker [unknown] 0x12345\n"
        with self.assertRaisesRegex(RuntimeError, "no recognized Dart MQTT symbols"):
            self.profile()
        self.assertTrue(self.broker.terminated)
        self.assertEqual(self.sampler.signals, [signal.SIGINT])


if __name__ == "__main__":
    unittest.main()
