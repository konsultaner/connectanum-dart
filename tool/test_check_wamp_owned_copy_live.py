"""Portable proof controls use synthetic fixtures and owned Python children."""
from collections import Counter
import copy
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_wamp_owned_copy_live as proof
import test_owned_copy_evidence as evidence


class CopyValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        evidence.OwnedCopyEvidenceTest.setUpClass()
        cls.fixtures = evidence.OwnedCopyEvidenceTest.fixtures
        cls.builder = evidence.OwnedCopyEvidenceTest()

    def report(self, native=False):
        fixture = next(x for x in self.fixtures if (x['client_impl'] == 'native') == native)
        return self.builder.report(fixture)

    def test_every_existing_dart_producer_fixture_passes_owned_validator(self):
        for fixture in self.fixtures:
            with self.subTest(name=fixture['name']):
                report = self.builder.report(fixture)
                counts = proof.validate_row(report, e2ee=True, transcode=True,
                    native_crypto=report['client_impl'] == 'native')
                self.assertEqual(counts['rows'], 1)
                self.assertEqual(counts['e2ee'], 1)
                self.assertEqual(counts['transcode'], 1)

    def test_missing_observations_or_scope_cannot_pass(self):
        for path, value in [(('samples',), []), (('samples',), None),
                            (('copy_metrics',), None),
                            (('copy_metrics', 'measurement_scope'), 'unknown')]:
            report = self.report()
            target = report
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            with self.subTest(path=path), self.assertRaises(ValueError):
                proof.validate_row(report, e2ee=True, transcode=True)

    def test_owned_gap_cannot_be_hidden_by_dependency_labels(self):
        report = self.report()
        report['copy_metrics']['e2ee_copy_breakdown']['unknown_boundaries'] = ['owned_buffer_clone']
        with self.assertRaises(ValueError):
            proof.validate_row(report, e2ee=True, transcode=True)

    def test_native_crypto_requires_positive_observed_component(self):
        for invalid in (None, True, 0, -1):
            report = self.report(native=True)
            report['copy_metrics']['e2ee_copy_breakdown']['components']['native_crypto'] = invalid
            with self.subTest(value=invalid), self.assertRaises(ValueError):
                proof.validate_row(report, e2ee=True, transcode=True, native_crypto=True)

    def test_zero_copy_requires_integer_zero_and_complete_native_instrumentation(self):
        good = self.report(native=True)
        good['copy_metrics']['optimized_payload_copy_bytes'] = 0
        self.assertEqual(proof.validate_row(good, e2ee=True, transcode=True,
                                           zero_copy=True)['zero_avoidable_payload_copy'], 1)
        for invalid in (None, False, True, 1, 0.0):
            report = copy.deepcopy(good)
            report['copy_metrics']['optimized_payload_copy_bytes'] = invalid
            with self.subTest(value=invalid), self.assertRaises(ValueError):
                proof.validate_row(report, e2ee=True, transcode=True, zero_copy=True)
        report = copy.deepcopy(good)
        report['copy_metrics']['native_codec_copy_breakdown']['client']['coverage_version'] = None
        with self.assertRaises(ValueError):
            proof.validate_row(report, e2ee=True, transcode=True, zero_copy=True)


class PortableProofTests(unittest.TestCase):
    def test_complete_original_owned_inventory_and_payload_inputs(self):
        groups = proof.owned_groups()
        self.assertEqual({k: len(v) for k, v in groups.items()},
                         {'expanded': 72, 'cbor_pubsub_progressive': 32, 'typed_pubsub': 16})
        cases = [case for values in groups.values() for case in values]
        self.assertEqual(len({json.dumps(case, sort_keys=True) for case in cases}), 120)
        self.assertEqual(Counter(case['mode'] for case in cases),
                         Counter(rpc=56, file_transfer=16, pubsub=32, progressive_rpc=16))
        self.assertEqual(sum(case['ppt_scheme'] == 'wamp' for case in cases), 96)
        self.assertEqual(sum(case['ppt_scheme'] == 'wamp' and case['client_impl'] == 'native' for case in cases), 48)
        self.assertTrue(all(case['iterations'] == 2 and case['payload_bytes'] == 65536 for case in cases))
        self.assertEqual({case['ppt_cipher'] for case in cases if 'ppt_cipher' in case},
                         {'xsalsa20poly1305', 'aes256gcm'})
        self.assertEqual({case['peer_serializer'] for case in cases}, {'cbor', 'msgpack', 'json'})

    def test_production_guard_rejects_linux_and_macos_test_oracles(self):
        for symbol in ('ct_test_owned_buffer_live_handles', '_ct_test_owned_buffer_live_handles'):
            with self.subTest(symbol=symbol), mock.patch.object(proof.subprocess, 'check_output', return_value='0 T ' + symbol):
                with self.assertRaisesRegex(ValueError, 'production library'):
                    proof.production_exports(Path('synthetic.so'))
        for missing in ('', 'nm: no symbols', '0 T unrelated_symbol'):
            with mock.patch.object(proof.subprocess, 'check_output', return_value=missing):
                with self.assertRaisesRegex(ValueError, 'public C API'):
                    proof.production_exports(Path('synthetic.so'))
        with mock.patch.object(proof.subprocess, 'check_output', return_value='0 T ct_version\n'):
            self.assertIn('ct_version', proof.production_exports(Path('synthetic.so')))

    def fixture(self, folder):
        root = Path(folder)
        (root / '.gitignore').write_text('out/\nlocks/\n.dart_tool/\n')
        for name in (*proof.LOCKS, 'source.dart'):
            p = root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('# explicit synthetic test input\n')
        for command in (['git', 'init', '-q'], ['git', 'add', '.'],
                        ['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                         'commit', '-qm', 'synthetic copy-proof fixture']):
            subprocess.run(command, cwd=root, check=True, capture_output=True)
        configuration = root / '.dart_tool/package_config.json'
        configuration.parent.mkdir()
        configuration.write_text(json.dumps({'packages': [
            {'name': name, 'rootUri': '../packages/' + name}
            for name in ('connectanum_core', 'connectanum_client', 'connectanum_bench')]}))
        out = root / 'out'
        out.mkdir()
        library, driver = out / 'native.so', out / 'driver'
        library.write_bytes(b'synthetic native artifact')
        driver.write_bytes(b'synthetic driver artifact')
        args = SimpleNamespace(output=out / 'proof', native_lib=library,
                               driver=driver, resource_lock=root / 'locks/machine.lock', dart='dart')
        return root, args

    @staticmethod
    def group(root, output, library, dart, router, control, cases):
        encrypted = sum(case['ppt_scheme'] == 'wamp' for case in cases)
        native = sum(case['ppt_scheme'] == 'wamp' and case['client_impl'] == 'native' for case in cases)
        return {'name': output.name, 'counts': dict(Counter(rows=len(cases), encoded_volume=len(cases),
                e2ee=encrypted, native_crypto=native, transcode=len(cases)))}

    def execute(self, root, args, *, short=None, exports='0 T ct_version\n'):
        with mock.patch.object(proof, 'production_exports', return_value=exports), \
                mock.patch.object(proof, 'private_router', return_value=(root / 'router.json', 'https://localhost/bench')), \
                mock.patch.object(proof, 'run_group', side_effect=self.group), \
                mock.patch.object(proof, 'run_short_batches', side_effect=short or (lambda *args: {'synthetic': True})), \
                redirect_stdout(io.StringIO()):
            code = proof.run(args, root)
        return code, json.loads((args.output / 'result.json').read_text())

    @unittest.skipUnless(os.name == 'posix', 'POSIX process/resource ownership')
    def test_invariant_inputs_and_production_artifacts_have_explicit_nonperformance_status(self):
        with tempfile.TemporaryDirectory() as folder:
            root, args = self.fixture(folder)
            code, result = self.execute(root, args)
            self.assertEqual(code, 0)
            self.assertEqual(result['status'], 'copy_correctness_complete_not_performance_acceptance')
            self.assertTrue(result['source_inputs_unchanged'])
            self.assertTrue(result['binaries_unchanged'])

    @unittest.skipUnless(os.name == 'posix', 'POSIX process/resource ownership')
    def test_source_or_binary_changes_invalidate_completed_counts(self):
        for source in (True, False):
            with self.subTest(source=source), tempfile.TemporaryDirectory() as folder:
                root, args = self.fixture(folder)
                def change(*_):
                    (root / 'source.dart' if source else args.native_lib).write_text('changed')
                    return {'synthetic': True}
                code, result = self.execute(root, args, short=change)
                self.assertEqual(code, 1)
                self.assertEqual(result['status'], 'failed')
                self.assertEqual(result['source_inputs_unchanged'], not source)
                self.assertEqual(result['binaries_unchanged'], source)

    @unittest.skipUnless(os.name == 'posix', 'POSIX process/resource ownership')
    def test_pipeline_failure_retains_partial_receipt_and_releases_lease(self):
        with tempfile.TemporaryDirectory() as folder:
            root, args = self.fixture(folder)
            def fail(*_):
                raise RuntimeError('synthetic observed gap')
            code, result = self.execute(root, args, short=fail)
            self.assertEqual(code, 1)
            self.assertIn('synthetic observed gap', result['error'])
            with proof.lifetime.resource_lease(args.resource_lock):
                pass

    @unittest.skipUnless(os.name == 'posix', 'POSIX process/resource ownership')
    def test_wrong_package_source_graph_prevents_native_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root, args = self.fixture(folder)
            path = root / '.dart_tool/package_config.json'
            config = json.loads(path.read_text())
            config['packages'][0]['rootUri'] = 'file:///tmp/unrelated-core'
            path.write_text(json.dumps(config))
            with mock.patch.object(proof, 'run_group') as launch:
                with self.assertRaises(ValueError):
                    proof.run(args, root)
            launch.assert_not_called()
            self.assertFalse(args.output.exists())

    @unittest.skipUnless(os.name == 'posix', 'POSIX process/resource ownership')
    def test_existing_resource_holder_prevents_output_and_native_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root, args = self.fixture(folder)
            with proof.lifetime.resource_lease(args.resource_lock), mock.patch.object(proof, 'run_group') as launch:
                with self.assertRaises(BlockingIOError):
                    proof.run(args, root)
            launch.assert_not_called()
            self.assertFalse(args.output.exists())

    def test_short_controller_cannot_claim_timing_acceptance_or_an_unexpected_exit(self):
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                def controller(argv):
                    output = Path(argv[argv.index('--output') + 1])
                    output.mkdir()
                    (output / 'manifest.json').write_text('{}')
                    return exit_code
                with mock.patch.object(proof.campaign, 'main', side_effect=controller):
                    with self.assertRaisesRegex(ValueError, 'unexpected timing acceptance'):
                        proof.run_short_batches(root, root, root / 'synthetic.so',
                            root / 'synthetic-driver', 'dart', root / 'router.json', 'https://localhost')

    @unittest.skipUnless(os.name == 'posix', 'POSIX child ownership')
    def test_startup_failure_stops_only_real_owned_python_child_and_retains_cleanup(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            children = []
            # Save the two real constructors separately; Thread also needs Event.
            real_popen = subprocess.Popen
            real_event = proof.threading.Event
            ready = real_event()
            ready.wait = mock.Mock(return_value=False)
            pending = [ready]
            def event():
                return pending.pop() if pending else real_event()
            def launch(*args, **kwargs):
                if args[0][0] != 'dart':
                    return real_popen(*args, **kwargs)
                child = real_popen([sys.executable, '-u', '-c', 'input()'], **kwargs)
                children.append(child)
                return child
            output = root / 'failed'
            with mock.patch.object(proof.subprocess, 'Popen', side_effect=launch), \
                    mock.patch.object(proof.threading, 'Event', side_effect=event):
                with self.assertRaisesRegex(RuntimeError, 'did not become ready'):
                    proof.run_group(root, output, root / 'synthetic.so', 'dart',
                                    root / 'router.json', 'https://localhost/bench', [])
            cleanup = json.loads((output / 'cleanup.json').read_text())
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0].returncode, 0)
            self.assertTrue(cleanup['process_group_stopped'])
            self.assertTrue(cleanup['reader_stopped'])
            self.assertEqual(cleanup['reader_errors'], [])


if __name__ == '__main__':
    unittest.main()
