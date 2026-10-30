"""Process ownership and evidence checks for the Linux MQTT diagnostic."""
import json
import os
from pathlib import Path
import signal
import shlex
import re
import subprocess
import sys
import tempfile
import textwrap
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
        self.output.mkdir()
        (self.output / "perf.data").write_bytes(b"perf capture")
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
        report = next(command for command in self.commands if command[0] == "test-perf")
        self.assertEqual(report[report.index("--percent-limit") + 1], "0")

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

    def test_expected_sigint_shutdown_accepts_finalized_samples(self):
        def interrupted_wait(timeout=None):
            self.sampler.returncode = -signal.SIGINT
            return self.sampler.returncode
        self.sampler.wait = interrupted_wait
        self.profile()
        self.assertTrue((self.output / "profile.txt").is_file())
        status = json.loads((self.output / "sampler-status.json").read_text())
        self.assertEqual(status, {"returncode": -signal.SIGINT, "sentSigint": True})

    def test_sampler_must_remain_alive_until_requested_shutdown(self):
        with patch.object(self.sampler, "poll", side_effect=[None] * 6 + [0]):
            with self.assertRaisesRegex(RuntimeError, "failed to record samples"):
                self.profile()
        self.assertTrue(self.broker.terminated)
        self.assertFalse((self.output / "profile.txt").exists())

    def test_sampler_exit_during_traffic_is_rejected_even_with_zero_status(self):
        def client_exit(*_):
            self.sampler.returncode = 0
            return subprocess.CompletedProcess([], 0, json.dumps(self.row), ""), 0.1
        self.client.side_effect = client_exit
        with self.assertRaisesRegex(RuntimeError, "stopped during"):
            self.profile()
        self.assertTrue(self.broker.terminated)
        self.assertFalse((self.output / "profile.txt").exists())

    def test_recovery_renders_original_samples_without_starting_new_processes(self):
        self.profile()
        before = (self.output / "provenance.json").read_bytes()
        rows = (self.output / "raw.jsonl").read_bytes()
        profiler.render_profile(self.output, "test-perf")
        self.assertEqual(self.popen.call_count, 2)
        self.assertEqual((self.output / "provenance.json").read_bytes(), before)
        self.assertEqual((self.output / "raw.jsonl").read_bytes(), rows)
        report = json.loads((self.output / "report-provenance.json").read_text())
        self.assertEqual(len(report["perfDataSha256"]), 64)

    def test_report_only_cli_does_not_require_a_broker_library_or_budget(self):
        with patch.object(profiler.sys, "platform", "linux"), patch.object(
            profiler.sys, "argv", ["profile", "--report-only", "--output", str(self.output)]
        ), patch.object(profiler, "render_profile") as render:
            profiler.main()
        render.assert_called_once_with(self.output, "perf")

    def test_recovery_rejects_incomplete_archived_workload(self):
        self.profile()
        rows = (self.output / "raw.jsonl").read_text().splitlines()
        (self.output / "raw.jsonl").write_text("\n".join(rows[:-1]) + "\n")
        self.commands.clear()
        with self.assertRaisesRegex(RuntimeError, "repetitions are incomplete"):
            profiler.render_profile(self.output, "test-perf")
        self.assertEqual(self.commands, [])

    def test_unsymbolized_report_is_not_accepted_as_a_profile(self):
        self.symbols = "DartWorker [unknown] 0x12345\n"
        with self.assertRaisesRegex(RuntimeError, "no recognized Dart MQTT symbols"):
            self.profile()
        self.assertTrue(self.broker.terminated)
        self.assertEqual(self.sampler.signals, [signal.SIGINT])

class PerfToolDiscoveryTest(unittest.TestCase):
    def test_perf_discovery_follows_installed_tool_symlinks(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory(prefix="mqtt tools ")))
        tools = root / "linux-tools"
        real = root / "versioned-tools"
        tools.mkdir()
        real.mkdir()
        binary = real / "perf"
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
        (tools / "6.8.0-generic").symlink_to(real, target_is_directory=True)
        workflow = (profiler.ROOT / ".github/actions/profile-mqtt/action.yml").read_text()
        selector = re.search(r'perf_binary="\$\(([^\n]+)\)"', workflow)[1]
        command = selector.replace("/usr/lib/linux-tools", shlex.quote(str(tools)))
        result = subprocess.run(["bash", "-c", command], capture_output=True, text=True, check=True)
        self.assertEqual(Path(result.stdout.strip()).resolve(), binary.resolve())

    def test_recovery_action_does_not_resample_or_replace_capture_version(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory(prefix="mqtt recovery ")))
        tools = root / "tools"
        tools.mkdir()
        perf = tools / "perf"
        perf.write_text("#!/bin/sh\necho perf-report-version\n")
        perf.chmod(0o755)
        python = root / "python3"
        python.write_text(
            f"#!{sys.executable}\nimport json,os,sys\n"
            "with open(os.environ['FAKE_ARGS'], 'a') as log:\n"
            " log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        )
        python.chmod(0o755)
        output = root / "out/mqtt-native-profile"
        output.mkdir(parents=True)
        (output / "perf-version.txt").write_text("original capture version")
        action = (profiler.ROOT / ".github/actions/profile-mqtt/action.yml").read_text()
        block = textwrap.dedent(action.split("      run: |\n")[2])
        block = block.replace("/usr/lib/linux-tools", shlex.quote(str(tools)))
        log = root / "arguments.jsonl"
        for mode in ("true", "false"):
            log.write_text("")
            subprocess.run(["bash", "-c", block], cwd=root, check=True,
                           env={**os.environ, "MQTT_REPORT_ONLY": mode, "FAKE_ARGS": str(log),
                                "PATH": f"{root}:{os.environ['PATH']}"})
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(calls), 2)
            self.assertTrue(all(("--report-only" in call) == (mode == "true") for call in calls))
            self.assertTrue(all(("--budget" in call) == (mode == "false") for call in calls))
            if mode == "true":
                self.assertEqual((output / "perf-version.txt").read_text(), "original capture version")


if __name__ == "__main__":
    unittest.main()
