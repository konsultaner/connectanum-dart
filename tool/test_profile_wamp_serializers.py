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
        for case_id, (implementation, construction), mode in [(key, value, mode) for key, value in expected.items() for mode in ('none', 'complete', 'missing', 'non-linux')]:
            native = mode != 'none'
            requested = native and mode != 'non-linux'
            with self.subTest(case=case_id, symbols=mode), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'profile output'
                library = Path(directory) / 'native library.so'
                library.write_bytes(b'unit-test fixture, never executed')
                args = profiler.parse_args(['--output', str(output), '--native-lib', str(library),
                                            '--case', case_id, '--dart', 'unit-test-dart', *(['--perf', 'unit-test-perf'] if native else [])])
                target = {'client_impl': implementation, 'payload_construction': construction}
                warmups = []
                probes = []

                def launch(command, **kwargs):
                    self.assertEqual('--generate-perf-events-symbols' in command, requested)

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
                    self.assertEqual(dart_args[4], 'unit-test-perf' if native else '')
                    self.assertEqual(dart_args[3], str(output.resolve()))
                    self.assertTrue((output / 'probe.dart').is_file())
                    if mode == 'complete':
                        for codec in ('cbor', 'msgpack', 'flatbuffers'):
                            (output / f'{codec}-router.perf-map').write_text('1000 10 fixture symbol; never real samples\n')
                            (output / f'{codec}-router-perf-symbols.json').write_text(json.dumps({
                                'pid': 12345, 'source': '/tmp/perf-12345.map', 'status': 'retained'}))
                    return SimpleNamespace(returncode=0)

                def checked(command, **kwargs):
                    if command == ['unit-test-dart', '--version']:
                        return 'Dart version fixture; not a real profile'
                    if command == ['unit-test-perf', '--version']:
                        return 'perf fixture, never executed'
                    return subprocess.check_output(command, **kwargs)

                commands = SimpleNamespace(Popen=launch, run=probe, check_output=checked,
                                           PIPE=subprocess.PIPE, STDOUT=subprocess.STDOUT,
                                           TimeoutExpired=subprocess.TimeoutExpired)
                with mock.patch.object(profiler, 'subprocess', commands), \
                        mock.patch.object(profiler.platform, 'system', return_value='Darwin' if mode == 'non-linux' else 'Linux'), \
                        mock.patch.object(profiler.urllib.request, 'urlopen', post), \
                        mock.patch.object(profiler.campaign, 'interfering_jobs', return_value=[]), \
                        mock.patch.object(profiler.campaign, 'stop_process_group', return_value=True):
                    self.assertEqual(profiler.profile(args), 1 if mode == 'missing' else 0)
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
                self.assertEqual(audit['router_perf_symbols']['requested'], requested)
                self.assertEqual(audit['router_perf_symbols']['status'], {'none':'not_requested', 'non-linux':'not_requested', 'complete':'retained', 'missing':'incomplete'}[mode])
                self.assertEqual(len(audit['router_perf_symbols']['maps']), 3 if mode == 'complete' else 0)
                self.assertEqual(audit['probe_exit'], 0)
                self.assertEqual(bool(audit['router_perf_symbols']['findings']), mode == 'missing')


class RouterSymbolMapTests(unittest.TestCase):
    def fixture(self, output):
        for codec in ('cbor', 'msgpack', 'flatbuffers'):
            (output / f'{codec}-router.perf-map').write_text('1000 10 *fixture symbol\n2000 20 plain fixture\n')
            (output / f'{codec}-router-perf-symbols.json').write_text(json.dumps({
                'pid': 12345, 'source': '/tmp/perf-12345.map', 'status': 'retained'}))

    def test_complete_maps_keep_pid_and_hash_attribution(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            self.fixture(output)
            result = profiler.router_symbol_map_audit(output, 12345, True)
            self.assertEqual(result['status'], 'retained')
            self.assertEqual(result['findings'], [])
            self.assertEqual({item['pid'] for item in result['maps']}, {12345})
            self.assertEqual({item['entries'] for item in result['maps']}, {2})
            self.assertTrue(all(len(item['sha256']) == 64 for item in result['maps']))
            self.assertEqual(result['client_jit_symbols'], 'not_requested')

    def test_bad_maps_remain_incomplete(self):
        for defect in ['missing map', 'missing attribution', 'empty', 'foreign PID', 'foreign source',
                       'invalid JSON', 'non-object', 'malformed record', 'zero address', 'negative size',
                       'nul name', 'invalid UTF8']:
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as folder:
                output = Path(folder)
                self.fixture(output)
                path = output / 'cbor-router.perf-map'
                meta = output / 'cbor-router-perf-symbols.json'
                if defect == 'missing map': path.unlink()
                elif defect == 'missing attribution': meta.unlink()
                elif defect == 'empty': path.write_bytes(b'')
                elif defect == 'foreign PID': meta.write_text(json.dumps({'pid': 9, 'source': '/tmp/perf-9.map', 'status': 'retained'}))
                elif defect == 'foreign source': meta.write_text(json.dumps({'pid': 12345, 'source': '/tmp/perf-9.map', 'status': 'retained'}))
                elif defect == 'invalid JSON': meta.write_text('{')
                elif defect == 'non-object': meta.write_text('[]')
                elif defect == 'malformed record': path.write_text('1000 10\n')
                elif defect == 'zero address': path.write_text('0 10 zero\n')
                elif defect == 'negative size': path.write_text('1000 -1 negative\n')
                elif defect == 'nul name': path.write_bytes(b'1000 10 bad\x00name\n')
                elif defect == 'invalid UTF8': path.write_bytes(b'1000 10 \xff\n')
                result = profiler.router_symbol_map_audit(output, 12345, True)
                self.assertEqual(result['status'], 'incomplete')
                self.assertTrue(result['findings'])
                self.assertEqual(len(result['maps']), 2)

    def test_no_perf_does_not_read_maps(self):
        result = profiler.router_symbol_map_audit(Path('/not/a/real/profile'), 12345, False)
        self.assertEqual(result['status'], 'not_requested')
        self.assertEqual(result['findings'], [])

    def test_reused_jit_addresses_are_explicit(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            self.fixture(output)
            with (output / 'cbor-router.perf-map').open('a') as stream:
                stream.write('1000 10 replacement fixture\n')
            result = profiler.router_symbol_map_audit(output, 12345, True)
            self.assertEqual(result['status'], 'retained')
            self.assertEqual(result['maps'][0]['ambiguous_start_addresses'], 1)


if __name__ == '__main__':
    unittest.main()
