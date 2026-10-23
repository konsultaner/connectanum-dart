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



class TcpEnvironmentTests(unittest.TestCase):
    def tcp_snapshot(self, directory, text):
        proc = Path(directory)
        path = proc / '42/net/netstat'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return linux.capture_tcp_environment(proc / '42', proc)

    def test_tcp_counters_use_owned_namespace_and_retain_only_known_integer_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            other = proc / 'net/netstat'
            other.parent.mkdir()
            other.write_text('TcpExt: PruneCalled\nTcpExt: 999\n')
            snapshot = self.tcp_snapshot(directory,
                'IpExt: Other\nIpExt: 8\n'
                'TcpExt: PruneCalled RcvPruned TCPRcvCollapsed UnknownFixture\n'
                'TcpExt: 3 0 18446744073709551615 918273\n')
            self.assertEqual((proc / '42/net/netstat').read_text().splitlines()[-1],
                             'TcpExt: 3 0 18446744073709551615 918273')
        record = snapshot['records']['namespace_tcp_ext']
        self.assertEqual(record['counters'], {
            'PruneCalled': 3, 'RcvPruned': 0, 'TCPRcvCollapsed': 18446744073709551615})
        self.assertTrue(all(type(value) is int for value in record['counters'].values()))
        self.assertIn('TCPMemoryPressures', record['missing_fields'])
        self.assertNotIn('RcvPruned', record['missing_fields'])
        self.assertNotIn('UnknownFixture', repr(record))
        self.assertIn('namespace', record['scope'])
        self.assertIn('cumulative', record['scope'])

    def test_missing_tcp_fields_remain_missing_instead_of_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.tcp_snapshot(directory, 'TcpExt: PruneCalled\nTcpExt: 0\n')
        record = snapshot['records']['namespace_tcp_ext']
        self.assertEqual(record['counters'], {'PruneCalled': 0})
        self.assertIn('RcvPruned', record['missing_fields'])
        self.assertNotIn('PruneCalled', record['missing_fields'])

    def test_malformed_tcp_pairs_fail_explicitly_without_partial_or_raw_records(self):
        for text in (
            '', 'TcpExt: PruneCalled\n', 'TcpExt:\nTcpExt:\n',
            'TcpExt: 1\nTcpExt: 1\n',
            'TcpExt: PruneCalled\nTcpExt: ١\n',
            'TcpExt: PruneCalled RcvPruned\nTcpExt: 1\n',
            'TcpExt: PruneCalled PruneCalled\nTcpExt: 1 2\n',
            'TcpExt: PruneCalled\nTcpExt: 1\nTcpExt: 2\n',
            'TcpExt: PruneCalled\nTcpExt: -1\n',
            'TcpExt: PruneCalled\nTcpExt: 1.0\n',
            'TcpExt: PruneCalled\nTcpExt: not-a-counter\n',
            'TcpExt: PruneCalled\nTcpExt: 18446744073709551616\n',
            'TcpExt: PruneCalled UnknownFixture\nTcpExt: 1 malformed\n',
        ):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as directory:
                snapshot = self.tcp_snapshot(directory, text)
            self.assertNotIn('namespace_tcp_ext', snapshot['records'])
            self.assertIn({'record': 'namespace_tcp_ext', 'error': 'ValueError'}, snapshot['errors'])
            self.assertNotIn('not-a-counter', repr(snapshot))

    def test_tcp_counter_record_limit_is_inclusive_and_never_unbounded(self):
        prefix = 'TcpExt: PruneCalled\nTcpExt: 7\n'
        for size in (65536, 65537):
            with self.subTest(size=size), tempfile.TemporaryDirectory() as directory:
                snapshot = self.tcp_snapshot(directory, prefix + ' ' * (size - len(prefix)))
            if size == 65536:
                self.assertEqual(snapshot['records']['namespace_tcp_ext']['counters']['PruneCalled'], 7)
            else:
                self.assertNotIn('namespace_tcp_ext', snapshot['records'])
                self.assertIn({'record': 'namespace_tcp_ext', 'error': 'ValueError'}, snapshot['errors'])

    def test_missing_or_unreadable_tcp_table_is_unavailable_without_namespace_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            other = proc / 'net/netstat'
            other.parent.mkdir()
            other.write_text('TcpExt: PruneCalled\nTcpExt: 999\n')
            snapshot = linux.capture_tcp_environment(proc / '42', proc)
            self.assertNotIn('namespace_tcp_ext', snapshot['records'])
            self.assertIn({'record': 'namespace_tcp_ext', 'error': 'FileNotFoundError'}, snapshot['errors'])
            with mock.patch.object(linux, 'bounded_text', side_effect=PermissionError):
                snapshot = linux.capture_tcp_environment(proc / '42', proc)
            self.assertNotIn('namespace_tcp_ext', snapshot['records'])
            self.assertIn({'record': 'namespace_tcp_ext', 'error': 'PermissionError'}, snapshot['errors'])

    def test_fixed_read_only_records_and_explicit_missing_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            path = proc / 'sys/net/ipv4/tcp_rmem'
            path.parent.mkdir(parents=True)
            path.write_text('4096 131072 6291456\n')
            (proc / 'meminfo').write_text('MemTotal: 10 kB\nMemAvailable: 8 kB\nSecretFixture: omitted\n')
            snapshot = linux.capture_tcp_environment(proc / '42', proc)
        self.assertEqual(snapshot['records']['tcp_rmem'], '4096 131072 6291456')
        self.assertEqual(snapshot['records']['host_memory'], {'MemTotal': '10 kB', 'MemAvailable': '8 kB'})
        self.assertIn('namespace_sockstat', {item['record'] for item in snapshot['errors']})
        self.assertIn('read-only', snapshot['scope'])

    def test_oversized_record_is_reported_without_unbounded_retention(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            path = proc / 'pressure/memory'
            path.parent.mkdir(parents=True)
            path.write_text('x' * 4097)
            snapshot = linux.capture_tcp_environment(proc / '42', proc)
        self.assertNotIn('memory_pressure', snapshot['records'])
        self.assertIn({'record': 'memory_pressure', 'error': 'ValueError'}, snapshot['errors'])

if __name__ == '__main__':
    unittest.main()
