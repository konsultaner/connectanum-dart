import copy
import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

import wamp_rss_memory as memory
from wamp_stall_vm_services import ProcessIdentity, VmServiceTarget


class MemoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.targets = [VmServiceTarget(role, pid, pid + 1, 10,
            ProcessIdentity(10, 50 + pid), ProcessIdentity(10, 80 + pid), ProcessIdentity(1, 30),
            f'http://127.0.0.1:{4000 + pid}/privateToken=/') for role, pid in (('worker', 20), ('router', 40))]
        self.row = {'workload': 'actual_workload', 'completed_at_ms': 100,
                    'client_process_metrics': {'pid': 20}, 'server_process_metrics': {'pid': 40}}
        self.usage = {'type': 'ProcessMemoryUsage', 'root': {'name': 'Process', 'size': 200,
            'children': [{'name': 'Future bucket', 'size': 150, 'children': [
                {'name': 'Nested retained size', 'size': 125, 'children': []}]}]}}
        for target in self.targets:
            path = self.root / str(target.pid)
            path.mkdir()
            (path / 'smaps').write_text('1000-2000 rw-p 00000000 00:00 0\nRss: 4 kB\n')

    def capture(self, *, identity=None, rpc=None):
        def reply(uri, method):
            target = next(t for t in self.targets if t.uri == uri)
            return {'type': 'VM', 'pid': target.pid} if method == 'getVM' else copy.deepcopy(self.usage)
        with mock.patch.object(memory, 'discover_vm_services', return_value=self.targets), \
                mock.patch.object(memory, 'identity_matches', side_effect=identity or [True] * 4), \
                mock.patch.object(memory, 'memory_rpc', side_effect=rpc or reply):
            return memory.capture_owned_memory(10, self.row, self.root)

    def test_raw_retained_tree_preserves_unknown_buckets_without_double_counting(self):
        result = self.capture()
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['roles']['worker']['process_memory_usage'], self.usage)
        self.assertEqual(result['roles']['worker']['bucket_count'], 3)
        self.assertNotIn('privateToken', json.dumps(result))
        self.assertEqual(result['roles']['worker']['driver_start_ticks'], 30)

    def test_identity_change_discards_unverified_maps_and_keeps_valid_other_role(self):
        result = self.capture(identity=[True, False, True, True])
        self.assertEqual(result['status'], 'failed')
        self.assertNotIn('linux_smaps', result['roles']['worker'])
        self.assertNotIn('process_memory_usage', result['roles']['worker'])
        self.assertIn('linux_smaps', result['roles']['router'])

    def test_wrong_vm_pid_cannot_produce_memory_evidence(self):
        result = self.capture(rpc=lambda uri, method: {'type': 'VM', 'pid': 999})
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(all('error' in role for role in result['roles'].values()))

    def test_oversized_empty_or_missing_maps_remain_explicit_failures(self):
        path = self.root / '20/smaps'
        for content in ('', 'x' * (8 * 1024 * 1024 + 1)):
            path.write_text(content)
            self.assertEqual(self.capture()['status'], 'failed')
        path.unlink()
        self.assertEqual(self.capture()['status'], 'failed')

    def test_bucket_types_depth_and_node_count_are_bounded(self):
        for invalid in (None, {'name': 'bad', 'size': True, 'children': []}):
            with self.assertRaises(ValueError): memory.validate_memory_tree(invalid)
        tree = {'name': 'root', 'size': 1, 'children': []}
        cursor = tree
        for index in range(17):
            child = {'name': str(index), 'size': 1, 'children': []}
            cursor['children'].append(child)
            cursor = child
        with self.assertRaisesRegex(ValueError, 'limits'):memory.validate_memory_tree(tree)
        tree['children'] = [{'name': 'leaf', 'size': 1, 'children': []}] * 512
        with self.assertRaisesRegex(ValueError, 'limits'):memory.validate_memory_tree(tree)

    def test_rpc_is_bounded_and_never_returns_error_payload_as_zero(self):
        response = mock.MagicMock()
        response.__enter__.return_value = response
        for raw in (b'x' * 524289, b'{"error":{"message":"privateToken"}}', b'{"type":"Wrong"}'):
            response.read.return_value = raw
            with mock.patch.object(memory.urllib.request, 'urlopen', return_value=response) as request:
                with self.assertRaises(ValueError): memory.memory_rpc(self.targets[0].uri, 'getProcessMemoryUsage')
                self.assertEqual(request.call_args.kwargs['timeout'], 1)
                response.read.assert_called_with(524289)
        with self.assertRaises(ValueError):memory.memory_rpc(self.targets[0].uri, 'requestHeapSnapshot')

    def test_colliding_or_invalid_policy_rejects_before_starting_a_thread(self):
        process = mock.Mock(pid=10)
        with mock.patch.object(memory.threading, 'Thread') as thread:
            for warmups, measured in ((3, 1), (0, 7), (True, 7), (3, False)):
                with self.subTest(warmups=warmups, measured=measured), self.assertRaises(ValueError):
                    memory.MemoryAttribution(process, self.root, {'minimum_warmup_runs': warmups, 'minimum_repetitions': measured})
            thread.assert_not_called()

    def test_partial_reports_wait_for_newline_and_capture_only_third_and_ninth(self):
        process = mock.Mock(pid=10)
        process.poll.return_value = None
        path = self.root / 'reports.jsonl'
        path.write_text('')
        observed = []
        def capture(pid, row):
            observed.append(row['number'])
            return {'status': 'complete', 'roles': {}}
        def await_count(count):
            deadline = time.monotonic() + 3
            while len(observed) < count and time.monotonic() < deadline:time.sleep(0.01)
            self.assertEqual(len(observed), count)
        with mock.patch.object(memory, 'capture_owned_memory', side_effect=capture):
            observer = memory.MemoryAttribution(process, self.root, {'minimum_warmup_runs': 3, 'minimum_repetitions': 7})
            try:
                with path.open('a', newline='') as stream:
                    for number in range(1, 11):
                        value = {**self.row, 'number': number}
                        encoded = json.dumps(value)
                        stream.write(encoded)
                        stream.flush()
                        if number in (3, 9):
                            time.sleep(0.08)
                            self.assertEqual(len(observed), 0 if number == 3 else 1)
                        stream.write('\r\n')
                        stream.flush()
                        if number in (3, 9):await_count(1 if number == 3 else 2)
            finally:result = observer.finish()
        self.assertEqual(observed, [3, 9])
        self.assertEqual(result['status'], 'complete')
        self.assertTrue(result['thread_stopped'])
        raw_lines = path.read_bytes().splitlines(keepends=True)
        for stage in result['snapshots'].values():
            snapshot = json.loads((self.root / stage).read_text())
            line = raw_lines[snapshot['after_complete_report_count'] - 1]
            self.assertEqual(snapshot['report_line_sha256'], hashlib.sha256(line).hexdigest())

    def test_discovery_exception_still_saves_failed_snapshot_without_private_uri(self):
        process = mock.Mock(pid=10)
        process.poll.return_value = None
        (self.root / 'reports.jsonl').write_text(''.join(json.dumps(self.row) + '\n' for _ in range(3)))
        with mock.patch.object(memory, 'capture_owned_memory', side_effect=ValueError('http://127.0.0.1/privateToken=/')):
            observer = memory.MemoryAttribution(process, self.root, {'minimum_warmup_runs': 3, 'minimum_repetitions': 7})
            deadline = time.monotonic() + 3
            while not observer.snapshots and time.monotonic() < deadline:time.sleep(0.01)
            result = observer.finish()
        snapshot = (self.root / 'memory-after_warmup_report.json').read_text()
        self.assertEqual(result['status'], 'failed')
        self.assertNotIn('privateToken', snapshot)
        self.assertEqual(json.loads(snapshot)['error'], 'ValueError')

    def test_failed_snapshot_is_retained_and_missing_stages_never_succeed(self):
        process = mock.Mock(pid=10)
        process.poll.return_value = None
        (self.root / 'reports.jsonl').write_text(''.join(json.dumps(self.row) + '\n' for _ in range(3)))
        with mock.patch.object(memory, 'capture_owned_memory', return_value={'status': 'failed', 'roles': {'worker': {'error': 'OSError'}}}):
            observer = memory.MemoryAttribution(process, self.root, {'minimum_warmup_runs': 3, 'minimum_repetitions': 7})
            deadline = time.monotonic() + 3
            while not observer.snapshots and time.monotonic() < deadline:time.sleep(0.01)
            result = observer.finish()
        self.assertEqual(result['status'], 'failed')
        self.assertTrue((self.root / 'memory-after_warmup_report.json').exists())
        self.assertIn('before_last_report', result['missing_stages'])


if __name__ == '__main__':
    unittest.main()
