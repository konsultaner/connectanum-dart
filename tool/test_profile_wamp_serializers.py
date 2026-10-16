#!/usr/bin/env python3
"""Check CPU diagnostic attribution without running a performance workload."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import profile_wamp_serializers as profiler


class ProfileSelectionTests(unittest.TestCase):
    def test_default_preserves_native_buffer_profile(self):
        args = profiler.parse_args(['--output', 'unused', '--native-lib', 'unused'])
        self.assertEqual(args.profile_case, 'rpc_rawsocket_clear_native_native_buffer')
        self.assertEqual(profiler.profile_target(args.profile_case), {
            'client_impl': 'native', 'payload_construction': 'native_buffer',
        })

    def test_unsupported_case_cannot_start_profiling(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'absent'
            argv = ['profile', '--output', str(output), '--native-lib', 'unused',
                    '--case', 'rpc_websocket_tls_dart_values']
            with mock.patch.object(sys, 'argv', argv), \
                    mock.patch.object(profiler, 'profile') as execute, \
                    contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    profiler.main()
            self.assertEqual(raised.exception.code, 2)
            execute.assert_not_called()
            self.assertFalse(output.exists())

    def test_direct_invalid_target_is_rejected_before_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'absent'
            args = SimpleNamespace(profile_case='unknown', output=output)
            with self.assertRaisesRegex(ValueError, 'Unsupported CPU profile case'):
                profiler.profile(args)
            self.assertFalse(output.exists())

    def test_each_call_gets_an_independent_target(self):
        target = profiler.profile_target(profiler.DEFAULT_CASE)
        target['client_impl'] = 'changed'
        self.assertEqual(profiler.profile_target(profiler.DEFAULT_CASE)['client_impl'], 'native')

    def test_warmup_probe_and_audit_agree_for_every_declared_case(self):
        expected = {
            'rpc_rawsocket_clear_dart_values': ('dart', 'values'),
            'rpc_rawsocket_clear_native_native_buffer': ('native', 'native_buffer'),
            'rpc_rawsocket_clear_native_pre_encoded_span': ('native', 'pre_encoded_span'),
        }
        self.assertEqual(set(profiler.PROFILE_CASES), set(expected))
        for case_id, (implementation, construction) in expected.items():
            with self.subTest(case=case_id), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'profile output'
                library = Path(directory) / 'native library.so'
                library.write_bytes(b'unit-test fixture, never executed')
                args = profiler.parse_args(['--output', str(output), '--native-lib', str(library),
                                            '--case', case_id, '--dart', 'unit-test-dart'])
                target = {'client_impl': implementation, 'payload_construction': construction}
                warmups = []
                probes = []

                def launch(command, **kwargs):
                    Path(kwargs['env']['CONNECTANUM_BENCH_PROFILE_WORKER_URI']).write_text(
                        'http://127.0.0.1:2/test/')
                    return SimpleNamespace(
                        stdout=io.StringIO('The Dart VM service is listening on http://127.0.0.1:1/test/\nREADY\n'),
                        stdin=io.StringIO(), pid=12345, returncode=0,
                        wait=lambda **_: 0, poll=lambda: 0,
                    )

                def post(request, **kwargs):
                    warmups.append(json.loads(request.data))
                    return io.BytesIO(b'{}')

                def probe(command, **kwargs):
                    probes.append(command)
                    # Dart removes its executable/options/script from main's arguments.
                    dart_args = command[3:]
                    self.assertEqual(len(dart_args), 6)
                    self.assertEqual(json.loads(dart_args[5]), target)
                    self.assertEqual(dart_args[4], '')  # native perf remains explicitly unmeasured
                    self.assertEqual(dart_args[3], str(output))
                    self.assertTrue((output / 'probe.dart').is_file())
                    return SimpleNamespace(returncode=0)

                def checked(command, **kwargs):
                    if command == ['unit-test-dart', '--version']:
                        return 'Dart version fixture; not a real profile'
                    return subprocess.check_output(command, **kwargs)

                commands = SimpleNamespace(Popen=launch, run=probe, check_output=checked,
                                           PIPE=subprocess.PIPE, STDOUT=subprocess.STDOUT,
                                           TimeoutExpired=subprocess.TimeoutExpired)
                with mock.patch.object(profiler, 'subprocess', commands), \
                        mock.patch.object(profiler.urllib.request, 'urlopen', post), \
                        mock.patch.object(profiler.campaign, 'interfering_jobs', return_value=[]), \
                        mock.patch.object(profiler.campaign, 'stop_process_group', return_value=True):
                    self.assertEqual(profiler.profile(args), 0)
                self.assertEqual(len(warmups), 1)
                self.assertEqual(len(probes), 1)
                self.assertEqual({key: warmups[0][key] for key in target}, target)
                self.assertEqual(json.loads((output / 'initial-request.json').read_text()), warmups[0])
                audit = json.loads((output / 'source-audit.json').read_text())
                self.assertEqual(audit['case_id'], case_id)
                self.assertEqual(audit['requested_configuration'], target)
                self.assertEqual(audit['kind'], 'cpu_profile_only_never_acceptance')
                self.assertTrue(audit['inputs_unchanged'])
                self.assertTrue(audit['process_group_stopped'])


if __name__ == '__main__':
    unittest.main()
