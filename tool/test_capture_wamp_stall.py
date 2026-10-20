#!/usr/bin/env python3
"""Test diagnostic evidence and owned-process cleanup without a performance workload."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

import capture_wamp_stall as diagnostic


@unittest.skipUnless(os.name == "posix", "diagnostic owns POSIX process groups")
class StallDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        for command in (["git", "init", "-q"], ["git", "config", "user.email", "fixture@example.invalid"],
                        ["git", "config", "user.name", "Fixture"]):
            subprocess.run(command, cwd=self.root, check=True)
        (self.root / "source.txt").write_text("unchanged\n")
        subprocess.run(["git", "add", "source.txt"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=self.root, check=True)
        for name in diagnostic.LOCKS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("resolved fixture\n")
        self.driver = self.base / "driver"
        self.library = self.base / "library"
        self.library.write_bytes(b"unit fixture, never loaded")
        self.scenario = self.base / "scenario.toml"
        self.scenario.write_text('name="fixture"\n[[workloads]]\nname="first"\niterations=2\nminimum_duration_ms=50\n')
        self.config = self.base / "router.json"
        self.config.write_text(json.dumps({"router": {"listeners": [{
            "endpoint": "127.0.0.1:1", "protocols": ["http1", "http3"], "http": {"http3": {}},
        }]}}))
        self.output = self.root / "diagnostic output $literal"
        self.args = diagnostic.parse_args([
            "--output", str(self.output), "--scenario", str(self.scenario),
            "--driver", str(self.driver), "--native-lib", str(self.library),
            "--router-config", str(self.config), "--dart", sys.executable,
        ])

    def driver_script(self, body):
        self.driver.write_text(f"#!{sys.executable}\n" +
            "import json,os,subprocess,sys,time\nfrom pathlib import Path\n" +
            "args=sys.argv[1:]\noutput=Path(args[args.index('--results')+1])\n" + body)
        self.driver.chmod(0o755)

    def execute(self):
        with contextlib.redirect_stdout(io.StringIO()):
            code = diagnostic.run(self.args, self.root)
        return code, json.loads((self.output / "result.json").read_text())

    def test_success_preserves_scenario_floors_timeout_and_provenance(self):
        self.driver_script("output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        code, result = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["kind"], "stall_reproduction_never_acceptance")
        self.assertTrue(result["inputs_unchanged"])
        self.assertTrue(result["locks_unchanged"])
        self.assertTrue(result["files_unchanged"])
        self.assertTrue(result["process_group_stopped"])
        self.assertEqual((self.output / "scenario.toml").read_bytes(), self.scenario.read_bytes())
        inputs = json.loads((self.output / "inputs.json").read_text())
        command = inputs["command"]
        self.assertEqual(command[command.index("--workload-timeout-ms") + 1], "300000")
        self.assertEqual(inputs["workload_order"], ["first"])
        self.assertIn("\\$literal", (self.output / "router.dart").read_text())

    def test_failure_keeps_exit_code_and_cleans_descendant_group(self):
        self.driver_script("child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'])\n"
                           "(output.parent/'child.pid').write_text(str(child.pid))\nsys.exit(7)\n")
        code, result = self.execute()
        self.assertEqual(code, 7)
        self.assertEqual(result["driver_exit_code"], 7)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(result["process_group_stopped"])
        child = int((self.output / "child.pid").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)

    def test_startup_failure_writes_a_failed_result(self):
        self.driver.write_bytes(b"not an executable image")
        self.driver.chmod(0o755)
        code, result = self.execute()
        self.assertNotEqual(code, 0)
        self.assertIsNone(result["driver_exit_code"])
        self.assertIn("OSError", result["failure"])
        self.assertEqual(result["status"], "failed")

    def test_changed_source_and_ignored_lock_cannot_pass(self):
        self.driver_script("Path('source.txt').write_text('changed')\nPath('pubspec.lock').write_text('changed')\n"
                           "Path('added-source.txt').write_text('new')\n"
                           "output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        code, result = self.execute()
        self.assertNotEqual(code, 0)
        self.assertFalse(result["inputs_unchanged"])
        self.assertFalse(result["locks_unchanged"])
        self.assertIn("source.txt", result["changed"])
        self.assertIn("added-source.txt", result["changed"])
        self.assertEqual(result["changed_locks"], ["pubspec.lock"])

    def test_changed_library_and_scenario_cannot_pass(self):
        self.driver_script("Path(args[args.index('--native-lib')+1]).write_bytes(b'changed')\n"
                           "Path(args[args.index('--scenario')+1]).write_text('changed')\n"
                           "output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        code, result = self.execute()
        self.assertNotEqual(code, 0)
        self.assertFalse(result["files_unchanged"])
        self.assertIn(str(self.library.resolve()), result["changed_files"])
        self.assertIn(str((self.output / "scenario.toml").resolve()), result["changed_files"])

    def test_incomplete_reordered_truncated_or_short_reports_remain_failed(self):
        for label, rows in (
            ("incomplete", ""),
            ("wrong-order", json.dumps({"workload": "other", "samples": [{}, {}], "data_window_elapsed_ms": 50}) + "\n"),
            ("truncated", '{"workload":'),
            ("short-samples", json.dumps({"workload": "first", "samples": [{}], "data_window_elapsed_ms": 50}) + "\n"),
            ("short-duration", json.dumps({"workload": "first", "samples": [{}, {}], "data_window_elapsed_ms": 49}) + "\n"),
        ):
            with self.subTest(label=label):
                self.args.output = self.root / label
                self.output = self.args.output
                self.driver_script(f"output.write_text({rows!r})\n")
                code, result = self.execute()
                self.assertNotEqual(code, 0)
                self.assertEqual(result["driver_exit_code"], 0)
                self.assertEqual(result["status"], "failed")

    def test_stall_evidence_is_bounded_and_deadline_cleans_the_worker(self):
        self.driver_script("print('waiting',flush=True)\ntime.sleep(60)\n")
        self.args.stall_seconds = 0.03
        self.args.max_seconds = 0.3
        with mock.patch.object(diagnostic, "capture_stacks", return_value={"roles": {}}) as capture:
            code, result = self.execute()
        self.assertNotEqual(code, 0)
        self.assertIn("TimeoutExpired", result["failure"])
        self.assertGreaterEqual(len(result["stalls"]), 1)
        self.assertLessEqual(len(result["stalls"]), 6)  # At most three per distinct output line.
        self.assertEqual(len(result["stalls"]), capture.call_count)
        self.assertTrue(result["process_group_stopped"])
        self.assertTrue(result["monitor_stopped"])
        self.assertTrue(result["reader_stopped"])

    def test_rpc_errors_and_failed_isolate_reads_are_evidence(self):
        for role in ("worker", "router"):
            (self.base / f"{role}-uri.txt").write_text("http://127.0.0.1:1/token/")
        vm = {"pid": 42, "isolates": [{"id": "isolates/1", "name": "main"}]}
        with mock.patch.object(diagnostic, "rpc", side_effect=[vm, ValueError("stack failed"), OSError("VM closed")]):
            result = diagnostic.capture_stacks(self.base, "waiting", threading.Event())
        self.assertIn("stack failed", result["roles"]["worker"]["isolates"][0]["error"])
        self.assertIn("VM closed", result["roles"]["router"]["error"])
        self.assertLessEqual(result["started_at_unix_seconds"], result["completed_at_unix_seconds"])
        with self.assertRaisesRegex(ValueError, "local HTTP"):
            diagnostic.rpc("https://example.invalid/", "getVM")

    def test_rpc_rejects_remote_errors_sentinels_and_invalid_shapes(self):
        for method, payload in (
            ("getVM", {"error": {"message": "failure"}}),
            ("getVM", {"type": "VM", "pid": 42}),
            ("getStack", {"type": "Sentinel", "kind": "Collected"}),
            ("getStack", {"type": "Stack", "frames": "invalid"}),
        ):
            with self.subTest(method=method, payload=payload), \
                    mock.patch.object(diagnostic.urllib.request, "urlopen", return_value=io.StringIO(json.dumps(payload))):
                with self.assertRaises(ValueError):
                    diagnostic.rpc("http://127.0.0.1:1/token/", method)

    def test_background_capture_failure_cannot_be_a_completed_claim(self):
        self.driver_script("time.sleep(0.15)\n"
                           "output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        self.args.stall_seconds = 0.01
        with mock.patch.object(diagnostic, "capture_stacks", side_effect=OSError("capture failed")):
            code, result = self.execute()
        self.assertNotEqual(code, 0)
        self.assertEqual(result["driver_exit_code"], 0)
        self.assertTrue(any("capture failed" in error for error in result["background_errors"]))

    def test_invalid_limits_and_existing_output_do_not_launch(self):
        self.driver_script("sys.exit(0)\n")
        for value in (0, -1, float("nan"), float("inf")):
            with self.subTest(value=value):
                self.args.stall_seconds = value
                with self.assertRaises(ValueError):
                    diagnostic.run(self.args, self.root)
                self.assertFalse(self.output.exists())
        self.args.stall_seconds = 60
        self.output.mkdir()
        (self.output / "keep").write_text("existing evidence")
        with self.assertRaises(FileExistsError):
            diagnostic.run(self.args, self.root)
        self.assertEqual((self.output / "keep").read_text(), "existing evidence")


if __name__ == "__main__":
    unittest.main()
