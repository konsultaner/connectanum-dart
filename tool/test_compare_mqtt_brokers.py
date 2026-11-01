import os
import subprocess
import sys
import textwrap
import unittest
import tempfile
from pathlib import Path
import compare_mqtt_brokers as m

class SourceAndCleanupTests(unittest.TestCase):

    def child(self, code):
        return subprocess.Popen([sys.executable, '-c', code], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_graceful_stdin_close_and_reap(self):
        p = self.child('import sys;sys.stdin.read()')
        self.assertEqual(m.clean_stop(p), 0)
        self.assertIsNotNone(p.poll())

    def test_early_failure_exit_is_not_success(self):
        p = self.child('import sys;sys.exit(7)')
        p.wait(timeout=5)
        self.assertEqual(m.clean_stop(p), 7)
        self.assertTrue(p.stdin.closed)

    def test_timeout_kills_and_reaps(self):
        p = self.child('import sys,time;sys.stdin.read();time.sleep(30)')
        with self.assertRaises(subprocess.TimeoutExpired):
            m.clean_stop(p, timeout=0.05)
        self.assertIsNotNone(p.poll())

    def test_exact_clean_source_required(self):
        with tempfile.TemporaryDirectory(prefix='mqtt-source-identity-') as temp:
            root = Path(temp)
            for args in [('init', '-q'), ('config', 'user.name', 'Source fixture'), ('config', 'user.email', 'fixture@example.invalid'), ('config', 'commit.gpgsign', 'false')]:
                subprocess.run(['git', *args], cwd=root, check=True, stdout=subprocess.DEVNULL)
            (root / 'input').write_text('original\n')
            subprocess.run(['git', 'add', 'input'], cwd=root, check=True)
            subprocess.run(['git', 'commit', '-qm', 'fixture'], cwd=root, check=True)
            head = m.git(root, 'rev-parse', 'HEAD')
            self.assertEqual(m.identity(root, head), head)
            with self.assertRaises(ValueError):
                m.identity(root, head[:12])
            with self.assertRaises(ValueError):
                m.identity(root, '0' * 40)
            (root / 'input').write_text('dirty\n')
            with self.assertRaises(ValueError):
                m.identity(root, head)

    def test_changed_delivery_configuration_rejected(self):
        budget = {'messages_per_run': 3, 'payload_bytes': 128, 'window_messages': 3}
        row = {'sent': 3, 'received': 3, 'received_per_subscriber': [3], 'duplicates': 0, 'mqtt_version': '5', 'transport': 'tcp', 'payload_bytes': 128, 'window_messages': 3, 'publish_mode': 'single', 'subscribers': 1}
        m.raw_row(row, budget)
        for key, value in [('received', 2), ('duplicates', 1), ('payload_bytes', 64), ('window_messages', 2), ('mqtt_version', '3.1.1')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                m.raw_row({**row, key: value}, budget)
class BinaryInputGuardsTests(unittest.TestCase):
    def test_actual_binary_bytes_are_guarded(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            files = {name: root / name for name in ('native', 'baseline', 'candidate', 'client')}
            for name, path in files.items():
                path.write_bytes(name.encode())
            exes = {k: files[k] for k in ('baseline', 'candidate')}
            provenance = {'native_sha256': m.digest(files['native']),
                          'broker_sha256': {k: m.digest(v) for k, v in exes.items()},
                          'client_sha256': m.digest(files['client'])}
            m.verify_binaries(files['native'], exes, files['client'], provenance)
            for name, path in files.items():
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'binary changed'):
                    m.verify_binaries(files['native'], exes, files['client'], provenance)
                path.write_bytes(original)

    def test_shared_native_or_client_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            roots = [Path(temp) / name for name in ('a', 'b')]
            names = ['native/transport/lib.rs', 'native/transport/Cargo.lock',
                     'pubspec.lock', 'packages/connectanum_client/lib/src/mqtt/client.dart',
                     'packages/connectanum_core/lib/src/mqtt/frame.dart',
                     'packages/connectanum_router/benchmark/mqtt_qos0.dart']
            for root in roots:
                root.mkdir()
                subprocess.run(['git', 'init', '-q'], cwd=root, check=True)
                for name in names:
                    path = root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(name)
                subprocess.run(['git', 'add', '.'], cwd=root, check=True)
            expected = m.shared_inputs(*roots)
            self.assertEqual(set(expected), set(names))
            for name in names:
                path = roots[1] / name
                original = path.read_text()
                path.write_text(original + 'changed')
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'input differs'):
                    m.shared_inputs(*roots)
                path.write_text(original)


class WorkflowModeTests(unittest.TestCase):
    def test_source_mode_validation_rejects_partial_or_mixed_requests(self):
        workflow = (Path(__file__).resolve().parents[1] /
                    '.github/workflows/mqtt-profile.yml').read_text()
        block = workflow.split('- name: Validate mutually exclusive diagnostic inputs', 1)[1]
        script = textwrap.dedent(block.split('run: |', 1)[1].split('      - uses:', 1)[0])
        env = {**os.environ, 'SOURCE_BASELINE_REF': 'a' * 40,
               'SOURCE_CANDIDATE_REF': 'b' * 40, 'SOURCE_LOCKS_RUN': '123',
               'RECOVER_RUN': '', 'COMPARE_WORKERS': '', 'PROBE_INTEL': 'false'}
        self.assertEqual(subprocess.run(['bash', '-c', script], env=env).returncode, 0)
        invalid = [('SOURCE_BASELINE_REF', ''), ('SOURCE_CANDIDATE_REF', 'short'),
                   ('SOURCE_CANDIDATE_REF', 'a' * 40), ('SOURCE_LOCKS_RUN', 'bad'),
                   ('RECOVER_RUN', '123'), ('COMPARE_WORKERS', '1'),
                   ('PROBE_INTEL', 'true')]
        for key, value in invalid:
            with self.subTest(key=key, value=value):
                result = subprocess.run(['bash', '-c', script], env={**env, key: value})
                self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
