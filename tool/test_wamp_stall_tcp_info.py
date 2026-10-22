import json
import subprocess
import unittest
from unittest import mock

import wamp_stall_tcp_info as tcp


class TcpInfoTests(unittest.TestCase):
    def setUp(self):
        self.target = object()
        self.entry = {'family': 'tcp', 'state_hex': '01', 'inode': 400,
                      'local_hex': '0100007F:1F93', 'remote_hex': '0100007F:AB3E'}
        self.text = b'ESTAB 0 16 127.0.0.1:8083 127.0.0.1:43838 ino:400 skmem:(r0,rb100) bytes_acked:100\n'
        self.identity = mock.patch.object(tcp, 'identity_matches', return_value=True).start()
        self.addCleanup(mock.patch.stopall)
        self.runner = mock.patch.object(tcp.subprocess, 'run', side_effect=self.respond).start()

    def respond(self, command, **kwargs):
        kwargs['stdout'].write(self.text)
        return subprocess.CompletedProcess(command, 0)

    def capture(self, ports=(8083,)):
        return tcp.capture_tcp_info(self.target, [self.entry], ports)

    def test_exact_tuple_and_inode_are_verified_before_retaining_info(self):
        result = self.capture()
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['sockets'][0]['ss'], self.text.decode().strip())
        command = self.runner.call_args.args[0]
        self.assertEqual(command, ['ss', '-H', '-O', '-n', '-t', '-4', '-i', '-m', '-e', '-o',
                                   'state', 'established', 'src', '127.0.0.1:8083',
                                   'dst', '127.0.0.1:43838'])
        self.assertEqual(self.runner.call_args.kwargs['timeout'], 2)
        self.assertNotIn('shell', self.runner.call_args.kwargs)

    def test_single_state_output_without_state_column_is_validated(self):
        self.text = self.text.removeprefix(b'ESTAB ')
        self.assertEqual(self.capture()['errors'], [])
        self.assertEqual(len(self.capture()['sockets']), 1)

    def test_unselected_ports_and_no_ports_do_not_execute_ss(self):
        self.assertEqual(self.capture((8080,))['sockets'], [])
        self.assertEqual(self.capture(())['sockets'], [])
        self.runner.assert_not_called()

    def test_invalid_endpoint_nonloopback_and_invalid_port_never_execute(self):
        for value in ['invalid', '08080808:1F93', '0100007F:0000', '0100007F:12345']:
            with self.subTest(value=value):
                self.entry['local_hex'] = value
                self.assertEqual(len(self.capture()['errors']), 1)
        self.runner.assert_not_called()
        for port in [0, 65536, True, '8083']:
            with self.assertRaises(ValueError):
                self.capture((port,))

    def test_ipv6_and_nonestablished_sockets_are_explicitly_out_of_scope(self):
        for key, value in [('family', 'tcp6'), ('state_hex', '0A')]:
            original = self.entry[key]
            self.entry[key] = value
            self.assertEqual(self.capture()['sockets'], [])
            self.entry[key] = original
        self.runner.assert_not_called()

    def test_foreign_inode_tuple_multiline_or_unbounded_text_is_never_retained(self):
        valid = self.text
        for text in [valid.replace(b'ino:400', b'ino:999'), valid.replace(b':43838', b':43839'),
                     valid + b'foreign-secret\n', b'x' * 16385]:
            with self.subTest(length=len(text)):
                self.text = text
                result = self.capture()
                self.assertEqual(result['sockets'], [])
                self.assertEqual(len(result['errors']), 1)
                self.assertNotIn('foreign-secret', json.dumps(result))

    def test_socket_disappearing_between_snapshots_is_explicit(self):
        self.text = b''
        result = self.capture()
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['sockets'], [])
        self.assertEqual(result['unavailable'][0]['inode'], 400)

    def test_missing_tool_timeout_and_failure_are_explicit_without_raw_stderr(self):
        for error in [FileNotFoundError('private-argv'), subprocess.TimeoutExpired('private-argv', 2)]:
            self.runner.side_effect = error
            result = self.capture()
            self.assertEqual(result['sockets'], [])
            self.assertNotIn('private-argv', json.dumps(result))
            self.assertEqual(len(result['errors']), 1)
        self.runner.side_effect = None
        self.runner.return_value = subprocess.CompletedProcess([], 1)
        self.assertEqual(len(self.capture()['errors']), 1)

    def test_identity_changes_discard_all_observations(self):
        for identities in [[False], [True, False], [True, True, False]]:
            with self.subTest(identities=identities):
                self.identity.side_effect = identities
                self.assertEqual(list(self.capture()), ['error'])

    def test_socket_count_is_bounded(self):
        result = tcp.capture_tcp_info(self.target, [self.entry] * 20, (8083,))
        self.assertEqual(len(result['sockets']), 8)
        self.assertEqual(self.runner.call_count, 8)
        self.assertEqual(result['errors'], [{'error': 'socket limit reached'}])


if __name__ == '__main__':
    unittest.main()
