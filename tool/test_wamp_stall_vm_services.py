import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

import wamp_stall_vm_services as services


class OwnedVmServicesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.proc = Path(temporary.name)
        self.process(100, 99, children=())
        self.process(200, 100, children=(300, 201, 301))
        self.process(300, 200)
        self.process(201, 200, observer=(200, True))
        self.process(301, 200, observer=(300, False))
        thread = self.proc / '100/task/999'
        thread.mkdir()
        (thread / 'children').write_text('200')

    def process(self, pid, parent, children=(), observer=None, ticks=None):
        directory = self.proc / str(pid)
        (directory / 'task' / str(pid)).mkdir(parents=True, exist_ok=True)
        (directory / 'task' / str(pid) / 'children').write_text(' '.join(map(str, children)))
        fields = ['0'] * 20
        fields[0] = 'S'
        fields[1] = str(parent)
        fields[19] = str(pid * 100 if ticks is None else ticks)
        (directory / 'stat').write_text(f'{pid} (name (with) spaces) ' + ' '.join(fields))
        if observer:
            target, all_isolates = observer
            self.config(pid, {'pid': target, 'all_isolates': all_isolates,
                              'service_uri': f'http://127.0.0.1:{40000 + target}/secretToken=/'})
        else:
            (directory / 'cmdline').write_bytes(b'dart\0ordinary_app.dart\0')

    def config(self, observer, config):
        (self.proc / str(observer) / 'cmdline').write_bytes(
            b'/sdk/dart\0--packages=config.json\0/pkg/dart_vm_metrics_observer_main.dart\0'
            + json.dumps(config).encode() + b'\0')

    def test_discovers_only_owned_observers_across_all_parent_threads(self):
        self.process(9000, 1, observer=(300, False))
        read_bytes, read_text = Path.read_bytes, Path.read_text
        def guarded_bytes(path, *args, **kwargs):
            self.assertNotIn('9000', path.relative_to(self.proc).parts)
            return read_bytes(path, *args, **kwargs)
        def guarded_text(path, *args, **kwargs):
            self.assertNotIn('9000', path.relative_to(self.proc).parts)
            return read_text(path, *args, **kwargs)
        with mock.patch.object(Path, 'read_bytes', guarded_bytes), mock.patch.object(Path, 'read_text', guarded_text):
            targets = services.discover_vm_services(100, self.proc)
        self.assertEqual([(target.role, target.pid, target.observer_pid) for target in targets],
                         [('router', 200, 201), ('worker', 300, 301)])
        self.assertNotIn('secretToken', repr(targets))
        self.assertTrue(all(services.identity_matches(target, self.proc) for target in targets))

    def test_foreign_target_and_invalid_configuration_never_create_endpoints(self):
        for config in [
            {'pid': 9000, 'all_isolates': False, 'service_uri': 'http://127.0.0.1:1/token=/'},
            {'pid': True, 'all_isolates': False, 'service_uri': 'http://127.0.0.1:1/token=/'},
            {'pid': 300, 'all_isolates': 0, 'service_uri': 'http://127.0.0.1:1/token=/'},
            {'pid': 300, 'all_isolates': False, 'service_uri': 'https://example.invalid/token=/'},
            {'pid': 300, 'all_isolates': False, 'service_uri': 'file:///tmp/token/'},
            {'pid': 300, 'all_isolates': False, 'service_uri': 'http://127.0.0.1:1/token=/?query=1'},
        ]:
            with self.subTest(config=config):
                self.config(301, config)
                self.assertEqual([(target.role, target.pid) for target in services.discover_vm_services(100, self.proc)],
                                 [('router', 200)])

    def test_disappearing_target_and_malformed_argv_are_skipped(self):
        shutil.rmtree(self.proc / '300')
        self.assertEqual([target.role for target in services.discover_vm_services(100, self.proc)], ['router'])
        (self.proc / '201/cmdline').write_bytes(b'dart\0/pkg/dart_vm_metrics_observer_main.dart\0{bad\0')
        self.assertEqual(services.discover_vm_services(100, self.proc), [])

    def test_pid_reuse_and_reparenting_invalidate_captured_identities(self):
        worker = next(target for target in services.discover_vm_services(100, self.proc) if target.role == 'worker')
        for pid in [100, 300, 301]:
            with self.subTest(pid=pid):
                path = self.proc / str(pid) / 'stat'
                before = path.read_text()
                path.write_text(before.replace(str(pid * 100), str(pid * 100 + 1)))
                self.assertFalse(services.identity_matches(worker, self.proc))
                path.write_text(before)
        self.process(300, 1)
        self.assertFalse(services.identity_matches(worker, self.proc))

    def test_process_discovery_is_bounded(self):
        with self.assertRaisesRegex(ValueError, 'limit exceeded'):
            services.owned_processes(100, self.proc, limit=2)

    def test_loopback_numeric_endpoints_and_authentication_path(self):
        for uri in ['http://127.0.0.1:9000/token=/', 'http://[::1]:9000/token=/', 'http://127.0.0.1:9000/']:
            self.assertEqual(services.loopback_service_uri(uri), uri)
        for uri in ['http://example.invalid:9000/token=/', 'http://127.0.0.1:9000/token=/#fragment',
                    'http://user:pass@127.0.0.1:9000/token=/', 'http://127.0.0.1:0/',
                    'http://127.0.0.1:99999/', 'http://127.0.0.1:9000/token=', 'http://127.0.0.1:9000/?q=1']:
            with self.subTest(uri=uri), self.assertRaises(ValueError):
                services.loopback_service_uri(uri)


if __name__ == '__main__':
    unittest.main()
