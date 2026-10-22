#!/usr/bin/env python3
"""Test diagnostic evidence and owned-process cleanup without a performance workload."""
import contextlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

import capture_wamp_stall as diagnostic


class WorkflowToolchainTests(unittest.TestCase):
    def test_effective_toolchain_overrides_repository_stable_for_all_diagnostics(self):
        text = (diagnostic.ROOT / '.github/workflows/wamp-profile-benchmarks.yml').read_text()
        for job in ('linux-flatbuffers-primary', 'linux-flatbuffers-cpu-profile',
                    'linux-flatbuffers-native-view-probe'):
            with self.subTest(job=job):
                block = text.split('\n  ' + job + ':\n', 1)[1]
                block = re.split(r'\n  [\w-]+:\n', block, maxsplit=1)[0]
                requested = re.search(r'dtolnay/rust-toolchain@([0-9.]+)', block).group(1)
                effective = re.search(r'(?m)^      RUSTUP_TOOLCHAIN: ([0-9.]+)$', block)
                self.assertIsNotNone(effective, 'rust-toolchain.toml stable overrides rustup default')
                self.assertEqual(effective.group(1), requested)


class SocketOptionLaunchTests(unittest.TestCase):
    def test_disabled_mode_preserves_exact_driver_argv(self):
        command = ['/owned driver', '--scenario', '$literal']
        launch, metadata = diagnostic.socket_option_launch(command, Path('/capture'), False)
        self.assertIs(launch, command)
        self.assertIsNone(metadata)

    def test_trace_launches_only_owned_descendants_with_unchanged_driver_argv(self):
        command = ['/owned driver', '--scenario', '$literal']
        with mock.patch.object(diagnostic.shutil, 'which', return_value='/usr/bin/strace'), \
                mock.patch.object(diagnostic.subprocess, 'check_output', return_value='strace -- version 6.8\n'):
            launch, metadata = diagnostic.socket_option_launch(command, Path('/capture'), True)
        self.assertEqual(launch[launch.index('--') + 1:], command)
        self.assertIn('--seccomp-bpf', launch)
        self.assertIn('trace=setsockopt', launch)
        self.assertNotIn('-p', launch)
        self.assertEqual(metadata['path'], 'socket-options.log')
        self.assertIn('perturbs', metadata['scope'])

    def test_missing_tool_rejects_before_launch(self):
        with mock.patch.object(diagnostic.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'requires strace'):
                diagnostic.socket_option_launch(['driver'], Path('/capture'), True)


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

    def test_original_process_mode_preserves_entrypoint_router_and_control_url(self):
        self.args.original_processes = True
        self.args.control_base = "https://127.0.0.1:1/bench"
        proc = self.base / "proc"
        proc.mkdir()
        self.driver_script("output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        with mock.patch.object(diagnostic, "PROC_ROOT", proc, create=True):
            code, result = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "completed")
        inputs = json.loads((self.output / "inputs.json").read_text())
        command = inputs["command"]
        self.assertNotIn("--bench-main", command)
        self.assertEqual(command[command.index("--router-config") + 1], str(self.config.resolve()))
        self.assertEqual(command[command.index("--control-base") + 1], self.args.control_base)
        self.assertEqual((self.output / "router.json").read_bytes(), self.config.read_bytes())
        self.assertFalse((self.output / "router.dart").exists())
        self.assertFalse((self.output / "worker.dart").exists())
        self.assertTrue(result["files_unchanged"])
        self.assertEqual(set(inputs['resolved_input_files']), set(diagnostic.LOCKS))
        for name, path in inputs['resolved_input_files'].items():
            self.assertEqual((self.output / path).read_bytes(), (self.root / name).read_bytes())
            self.assertFalse(any(part.startswith('.') for part in Path(path).parts),
                             'Artifact uploads omit hidden path components by default')

    def traced_fixture(self, trace_text):
        self.args.original_processes = True
        self.args.trace_socket_options = True
        self.args.control_base = 'https://127.0.0.1:1/bench'
        self.driver_script("output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        tracer = self.base / 'fixture-tracer'
        tracer.write_text(f"#!{sys.executable}\nimport subprocess,sys\nfrom pathlib import Path\n"
                          + f"Path({str(self.output / 'socket-options.log')!r}).write_text({trace_text!r})\n"
                          + "raise SystemExit(subprocess.run(sys.argv[1:]).returncode)\n")
        tracer.chmod(0o755)
        def launch(command, output, enabled):
            self.assertTrue(enabled)
            return [str(tracer), *command], {'path': 'socket-options.log', 'tool': 'unit fixture'}
        with mock.patch.object(diagnostic, 'socket_option_launch', side_effect=launch), \
                mock.patch.object(diagnostic, 'PROC_ROOT', self.base):
            return self.execute()

    def test_traced_launch_retains_original_command_positive_calls_and_digest(self):
        code, result = self.traced_fixture('123 setsockopt(8, SOL_SOCKET, SO_RCVBUF, [65536], 4) = 0\n')
        self.assertEqual(code, 0)
        self.assertEqual(result['socket_option_trace']['observed_option_calls'], 1)
        self.assertEqual(result['socket_option_trace']['sha256'], diagnostic.digest(self.output / 'socket-options.log'))
        inputs = json.loads((self.output / 'inputs.json').read_text())
        self.assertEqual(inputs['command'][0], str(self.driver.resolve()))
        self.assertNotEqual(inputs['command'][0], inputs['launch_command'][0])
        self.assertTrue(result['process_group_stopped'])

    def test_empty_trace_cannot_claim_observed_absence_of_buffer_option(self):
        code, result = self.traced_fixture('')
        self.assertEqual(code, 1)
        self.assertEqual(result['rows'], 1)
        self.assertIn('no observed calls', result['failure'])
        self.assertTrue(result['process_group_stopped'])

    def original_target(self):
        target = mock.Mock()
        target.role, target.pid, target.observer_pid = "worker", 42, 43
        target.identity.start_ticks = 100
        target.uri = "http://127.0.0.1:40000/secretToken=/"
        return target

    def test_package_resolution_change_cannot_pass(self):
        self.driver_script("Path('.dart_tool/package_config.json').write_text('changed')\n"
                           "output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
        code, result = self.execute()
        self.assertEqual(code, 1)
        self.assertFalse(result['locks_unchanged'])
        self.assertEqual(result['changed_locks'], ['.dart_tool/package_config.json'])

    def test_original_capture_verifies_pid_before_stack_and_redacts_credentials(self):
        target = self.original_target()
        def rpc(uri, method, params=None):
            if method == "getVM":
                return {"pid": 42, "isolates": [{"id": "isolates/1", "name": "main"}]}
            return {"type": "Stack", "test_uri": target.uri}
        with mock.patch.object(diagnostic, "discover_vm_services", return_value=[target]), \
                mock.patch.object(diagnostic, "identity_matches", return_value=True), \
                mock.patch.object(diagnostic, "rpc", side_effect=rpc) as call:
            snapshot = diagnostic.capture_original_stacks(10, target.uri, threading.Event())
        self.assertEqual([args.args[1] for args in call.call_args_list], ["getVM", "getStack"])
        self.assertEqual(snapshot["roles"]["worker"]["pid"], 42)
        self.assertEqual(snapshot["roles"]["worker"]["isolates"][0]["stack"]["type"], "Stack")
        self.assertNotIn("secretToken", json.dumps(snapshot))

    def test_original_capture_rejects_wrong_pid_and_changed_identity(self):
        target = self.original_target()
        for vm_pid, identities in [(99, [True]), (42, [True, False])]:
            with self.subTest(vm_pid=vm_pid), \
                    mock.patch.object(diagnostic, "discover_vm_services", return_value=[target]), \
                    mock.patch.object(diagnostic, "identity_matches", side_effect=identities), \
                    mock.patch.object(diagnostic, "rpc", return_value={"pid": vm_pid, "isolates": []}) as call:
                snapshot = diagnostic.capture_original_stacks(10, "waiting", threading.Event())
            self.assertEqual([args.args[1] for args in call.call_args_list], ["getVM"])
            self.assertIn("identity", snapshot["roles"]["worker"]["error"])

    def test_original_capture_keeps_rpc_errors_without_authentication_urls(self):
        target = self.original_target()
        with mock.patch.object(diagnostic, "discover_vm_services", return_value=[target]), \
                mock.patch.object(diagnostic, "identity_matches", return_value=True), \
                mock.patch.object(diagnostic, "rpc", side_effect=ValueError("RPC failed: " + target.uri)):
            snapshot = diagnostic.capture_original_stacks(10, "waiting", threading.Event())
        self.assertIn("RPC failed", snapshot["roles"]["worker"]["error"])
        self.assertNotIn("secretToken", json.dumps(snapshot))

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

    def test_directory_preserves_file_and_internal_order_with_repeated_workloads(self):
        directory = self.base / 'scenarios'
        directory.mkdir()
        def content(names):
            return 'name="fixture"\n' + ''.join(
                f'[[workloads]]\nname="{name}"\niterations=2\nminimum_duration_ms=50\n' for name in names)
        (directory / '02-measured.toml').write_text(content(['A', 'C']))
        (directory / '01-warmup.TOML').write_text(content(['B', 'A']))
        (directory / 'notes.txt').write_text('not TOML')
        (directory / 'nested').mkdir()
        (directory / 'nested/ignored.toml').write_text('not TOML')
        (directory / 'ignored.toml').symlink_to(self.root / 'source.txt')
        self.args.scenario = directory
        reports = [{'workload': name, 'samples': [{}, {}], 'data_window_elapsed_ms': 50}
                   for name in ['B', 'A', 'A', 'C']]
        raw = ''.join(json.dumps(row) + '\n' for row in reports)
        self.driver_script("assert Path(args[args.index('--scenario')+1]).is_dir()\n" +
                           f"output.write_text({raw!r})\n")
        code, result = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual(result['rows'], 4)
        self.assertTrue(result['scenario_inventory_unchanged'])
        inputs = json.loads((self.output / 'inputs.json').read_text())
        self.assertEqual(inputs['workload_order'], ['B', 'A', 'A', 'C'])
        self.assertEqual([Path(path).name for path in inputs['scenario_files']],
                         ['01-warmup.TOML', '02-measured.toml'])
        for path in diagnostic.scenario_files(directory):
            self.assertEqual((self.output / 'scenarios' / path.name).read_bytes(), path.read_bytes())

    def test_duplicate_names_within_one_file_reject_before_launch(self):
        self.driver_script('sys.exit(0)\n')
        self.scenario.write_text(self.scenario.read_text() +
            '[[workloads]]\nname="first"\niterations=2\nminimum_duration_ms=50\n')
        with self.assertRaisesRegex(ValueError, 'uniquely named'):
            diagnostic.run(self.args, self.root)
        self.assertFalse(self.output.exists())

    def test_added_and_removed_original_scenarios_cannot_pass(self):
        for mutation in ('added', 'removed', 'changed'):
            with self.subTest(mutation=mutation):
                directory = self.base / mutation
                directory.mkdir()
                original = directory / '01.toml'
                original.write_bytes(self.scenario.read_bytes())
                self.args.scenario = directory
                self.output = self.root / ('inventory-' + mutation)
                self.args.output = self.output
                action = (f'Path({str(directory / "02.toml")!r}).write_text("new")' if mutation == 'added'
                          else f'Path({str(original)!r}).unlink()' if mutation == 'removed'
                          else f'Path({str(original)!r}).write_text("changed")')
                self.driver_script(action + '\n' +
                    "output.write_text(json.dumps({'workload':'first','samples':[{},{}],'data_window_elapsed_ms':50})+'\\n')\n")
                code, result = self.execute()
                self.assertNotEqual(code, 0)
                self.assertEqual(result['scenario_inventory_unchanged'], mutation == 'changed')
                if mutation == 'changed':
                    self.assertFalse(result['files_unchanged'])
                self.assertEqual(result['driver_exit_code'], 0)

    def test_scenario_copy_collision_never_overwrites_evidence(self):
        directory = self.base / 'scenarios'
        directory.mkdir()
        (directory / '01.toml').write_bytes(self.scenario.read_bytes())
        self.args.scenario = directory
        self.driver_script('sys.exit(0)\n')
        original_mkdir = Path.mkdir
        destination = self.output.resolve() / 'scenarios/01.toml'
        def mkdir(path, *args, **kwargs):
            original_mkdir(path, *args, **kwargs)
            if path == destination.parent:
                destination.write_bytes(b'existing evidence')
        with mock.patch.object(Path, 'mkdir', mkdir):
            with self.assertRaisesRegex(ValueError, 'filename collision'):
                diagnostic.run(self.args, self.root)
        self.assertEqual(destination.read_bytes(), b'existing evidence')

    def test_failure_keeps_exit_code_and_cleans_descendant_group(self):
        self.driver_script("child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'])\n"
                           "(output.parent/'child.pid').write_text(str(child.pid))\nsys.exit(7)\n")
        code, result = self.execute()
        self.assertEqual(code, 7)
        self.assertEqual(result["driver_exit_code"], 7)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(result["process_group_stopped"])
        child = int((self.output / "child.pid").read_text())
        state = subprocess.run(["ps", "-p", str(child), "-o", "stat="],
                               capture_output=True, text=True, check=False).stdout.strip()
        # A dead orphan may remain a zombie until the host reaps it.
        self.assertTrue(not state or state.startswith("Z"), state)

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





class ListenerPortTests(unittest.TestCase):
    def test_application_ports_ignore_control_listener_and_deduplicate(self):
        config = {'router': {'listeners': [
            {'endpoint': '127.0.0.1:8080', 'protocols': ['http', 'http2']},
            {'endpoint': '127.0.0.1:8083', 'protocols': ['rawsocket', 'websocket']},
            {'endpoint': '[::1]:8083', 'protocols': ['websocket']},
            {'endpoint': '127.0.0.1:8081', 'protocols': ['rawsocket']},
        ]}}
        self.assertEqual(diagnostic.application_listener_ports(config), [8081, 8083])

    def test_non_numeric_nonloopback_ambiguous_and_zero_ports_are_rejected(self):
        for endpoint in ['localhost:8083', '8.8.8.8:8083', '127.0.0.1:0',
                         '127.0.0.1:65536', '127.0.0.1', 'user@127.0.0.1:8083',
                         '127.0.0.1:8083/path', '127.0.0.1:8083?query']:
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError):
                diagnostic.application_listener_ports({'router': {'listeners': [
                    {'endpoint': endpoint, 'protocols': ['websocket']}]}})


if __name__ == "__main__":
    unittest.main()
