import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import smoke_wamp_stall_discovery as smoke


class SmokeCaptureTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        self.uri = 'http://127.0.0.1:4567/secretToken=/'
        self.snapshot = {'roles': {'worker': {
            'pid': 100, 'observer_pid': 101,
            'isolates': [{'stack': {'frames': []}}],
            'linux': {'threads': [{'tid': 100}], 'tcp': [{'inode': 400}],
                      'tcp_info': {'sockets': [{'inode': 400, 'local': '127.0.0.1:8083'}], 'errors': []}},
        }}}

    def capture(self):
        with mock.patch.object(smoke.diagnostic, 'capture_original_stacks',
                               return_value=self.snapshot) as capture:
            smoke.capture_smoke_snapshot(self.output, 100, 101, self.uri, 8083)
        return capture

    def test_explicit_owned_socket_port_is_independent_of_vm_service_frontend(self):
        capture = self.capture()
        self.assertEqual(capture.call_args.kwargs['application_ports'], (8083,))
        self.assertEqual(json.loads((self.output / 'snapshot.json').read_text()), self.snapshot)

    def test_no_matching_tcp_info_is_failure_with_retained_owned_snapshot(self):
        self.snapshot['roles']['worker']['linux']['tcp_info']['sockets'] = []
        with self.assertRaisesRegex(RuntimeError, 'Owned TCP_INFO observation failed'):
            self.capture()
        self.assertEqual(json.loads((self.output / 'snapshot.json').read_text()), self.snapshot)

    def test_different_owned_socket_cannot_satisfy_positive_listener_proof(self):
        self.snapshot['roles']['worker']['linux']['tcp_info']['sockets'][0]['local'] = '127.0.0.1:4567'
        with self.assertRaisesRegex(RuntimeError, 'Owned TCP_INFO observation failed'):
            self.capture()
        self.assertTrue((self.output / 'snapshot.json').exists())

    def test_pid_and_collector_errors_remain_failures(self):
        original = copy.deepcopy(self.snapshot)
        for field, value in [('pid', 999), ('observer_pid', 999)]:
            self.snapshot = copy.deepcopy(original)
            self.snapshot['roles']['worker'][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, 'discovery or stack'):
                self.capture()
        self.snapshot = copy.deepcopy(original)
        self.snapshot['roles']['worker']['linux']['tcp_info']['errors'] = [{'error': 'ValueError'}]
        with self.assertRaisesRegex(RuntimeError, 'Owned TCP_INFO observation failed'):
            self.capture()

    def test_unredacted_credentials_are_rejected_before_persisting(self):
        self.snapshot['unexpected'] = self.uri
        with self.assertRaisesRegex(RuntimeError, 'not redacted'):
            self.capture()
        self.assertFalse((self.output / 'snapshot.json').exists())


if __name__ == '__main__':
    unittest.main()
