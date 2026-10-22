import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import wamp_stall_linux as linux
from wamp_stall_vm_services import ProcessIdentity, VmServiceTarget


class LinuxStallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.proc = Path(temporary.name)
        for pid, parent in [(100, 99), (200, 100), (201, 100)]:
            root = self.proc / str(pid)
            root.mkdir()
            (root / 'stat').write_text(self.stat(pid, parent))
        self.target = VmServiceTarget('worker', 200, 201, 100,
                                     ProcessIdentity(100, 20000), ProcessIdentity(100, 20100),
                                     ProcessIdentity(99, 10000), 'http://127.0.0.1:1/secretToken=/')
        root = self.proc / '200'
        (root / 'status').write_text('Name:\tDartVM\nVmRSS:\t42 kB\nThreads:\t1\n')
        task = root / 'task/200'
        task.mkdir(parents=True)
        (task / 'stat').write_text(self.stat(200, 100))
        (task / 'wchan').write_text('ep_poll\n')
        (root / 'fd').mkdir()
        (root / 'fd/3').symlink_to('socket:[400]')
        (root / 'fd/4').symlink_to('/private/unrelated-file-do-not-retain')
        (root / 'net').mkdir()
        (root / 'net/tcp').write_text('header\n' + self.tcp(400) + self.tcp(999))
        (root / 'net/tcp6').write_text('header\n')

    def stat(self, pid, parent):
        fields = ['0'] * 20
        fields[0], fields[1] = 'S', str(parent)
        fields[11], fields[12], fields[19] = '12', '7', str(pid * 100)
        return f'{pid} (Dart (worker)) ' + ' '.join(fields)

    def tcp(self, inode):
        return f'0: 0100007F:1F90 0100007F:1234 01 00000010:00000020 00:00000000 00000003 1000 0 {inode}\n'

    def test_only_owned_socket_inodes_and_bounded_thread_fields_are_retained(self):
        result = linux.capture_linux_state(self.target, self.proc)
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['status'], {'VmRSS': '42 kB', 'Threads': '1'})
        self.assertEqual(result['threads'][0]['user_ticks'], 12)
        self.assertEqual(result['threads'][0]['system_ticks'], 7)
        self.assertEqual(result['threads'][0]['wait_channel'], 'ep_poll')
        self.assertEqual([s['inode'] for s in result['tcp']], [400])
        self.assertEqual((result['tcp'][0]['tx_queue_bytes'], result['tcp'][0]['rx_queue_bytes']), (16, 32))
        self.assertEqual(result['tcp'][0]['retransmits'], 3)
        self.assertNotIn('unrelated-file', json.dumps(result))
        self.assertNotIn('secretToken', json.dumps(result))

    def test_tcp_info_receives_only_owned_socket_inventory_and_selected_ports(self):
        with mock.patch.object(linux, 'capture_tcp_info', return_value={'sockets': []}) as capture:
            result = linux.capture_linux_state(self.target, self.proc, application_ports=(8083,))
        capture.assert_called_once_with(self.target, result['tcp'], (8083,), self.proc)
        self.assertEqual([entry['inode'] for entry in capture.call_args.args[1]], [400])

    def test_changed_identity_rejects_observation_before_reading_descriptors(self):
        (self.proc / '200/stat').write_text(self.stat(200, 1))
        with mock.patch.object(linux.os, 'readlink', side_effect=AssertionError('must not inspect foreign PID')):
            result = linux.capture_linux_state(self.target, self.proc)
        self.assertIn('before', result['error'])

    def test_identity_change_during_read_discards_observations(self):
        with mock.patch.object(linux, 'identity_matches', side_effect=[True, False]):
            result = linux.capture_linux_state(self.target, self.proc)
        self.assertEqual(list(result), ['error'])
        self.assertIn('during', result['error'])

    def test_missing_thread_channel_and_table_remain_explicit(self):
        (self.proc / '200/task/200/wchan').unlink()
        (self.proc / '200/net/tcp6').unlink()
        result = linux.capture_linux_state(self.target, self.proc)
        self.assertEqual(result['threads'][0]['wait_channel_error'], 'FileNotFoundError')
        self.assertEqual(result['errors'], [{'record': 'tcp6', 'error': 'FileNotFoundError'}])
        self.assertEqual(len(result['tcp']), 1)

    def test_descriptor_and_thread_inventory_limits_are_reported(self):
        root = self.proc / '200'
        for tid in range(300, 429):
            (root / 'task' / str(tid)).mkdir()
        for fd in range(10, 523):
            (root / 'fd' / str(fd)).symlink_to('/not-retained')
        result = linux.capture_linux_state(self.target, self.proc)
        self.assertTrue(result['thread_inventory_truncated'])
        self.assertTrue(result['fd_inventory_truncated'])
        self.assertEqual(len(result['threads']), 128)

    def test_malformed_and_oversized_tables_are_explicit_not_empty_success(self):
        path = self.proc / '200/net/tcp'
        for text in ['header\n' + self.tcp(400).replace('00000010:', 'bad-queue:'), 'x' * (2 * 1024 * 1024 + 1)]:
            with self.subTest(size=len(text)):
                path.write_text(text)
                result = linux.capture_linux_state(self.target, self.proc)
                self.assertEqual(result['errors'], [{'record': 'tcp', 'error': 'ValueError'}])


if __name__ == '__main__':
    unittest.main()
