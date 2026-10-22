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

    def capture(self, *, identity=None, rpc=None, allocator_attribution=False):
        def reply(uri, method):
            target = next(t for t in self.targets if t.uri == uri)
            return {'type': 'VM', 'pid': target.pid} if method == 'getVM' else copy.deepcopy(self.usage)
        with mock.patch.object(memory, 'discover_vm_services', return_value=self.targets), \
                mock.patch.object(memory, 'identity_matches', side_effect=identity or [True] * 4), \
                mock.patch.object(memory, 'memory_rpc', side_effect=rpc or reply):
            return memory.capture_owned_memory(10, self.row, self.root, allocator_attribution=allocator_attribution)

    def allocator_reply(self, uri, method, isolate_id=None):
        target = next(t for t in self.targets if t.uri == uri)
        if method == 'getVM':
            return {'type': 'VM', 'pid': target.pid, 'isolates': [{'id': 'isolates/1', 'name': 'main'}]}
        if method == 'getProcessMemoryUsage': return copy.deepcopy(self.usage)
        self.assertEqual(isolate_id, 'isolates/1')
        if method == 'getMemoryUsage':
            return {'type': 'MemoryUsage', 'externalUsage': 112, 'heapUsage': 100, 'heapCapacity': 200}
        self.assertEqual(method, memory.ALLOCATOR_METHOD)
        return {'type': 'ConnectanumAllocatorDiagnostic', 'pid': target.pid, 'glibc_version': '2.39',
                'malloc_info_xml': '<malloc version="1"><heap nr="0"><total type="rest" size="10"/></heap>'
                '<total type="fast" size="1"/><total type="rest" size="10"/>'
                '<total type="mmap" size="30"/><system type="current" size="100"/></malloc>'}

    def test_allocator_attribution_preserves_xml_and_external_usage_without_double_counting(self):
        result = self.capture(rpc=self.allocator_reply, allocator_attribution=True)
        self.assertEqual(result['status'], 'complete')
        role = result['roles']['worker']
        self.assertEqual(role['allocator_counters']['arena_free_rest_bytes'], 10)
        self.assertEqual(role['isolate_memory_usage']['isolates/1']['externalUsage'], 112)
        self.assertIn('<heap nr="0">', role['allocator_diagnostic']['malloc_info_xml'])
        self.assertNotIn('privateToken', json.dumps(result))

    def test_allocator_failure_discards_unverified_evidence_and_preserves_other_role(self):
        for failure in ('pid', 'isolate', 'external', 'xml'):
            def reply(uri, method, isolate_id=None):
                value = self.allocator_reply(uri, method, isolate_id)
                if uri == self.targets[0].uri:
                    if failure == 'pid' and method == memory.ALLOCATOR_METHOD: value['pid'] = 999
                    if failure == 'isolate' and method == 'getVM': value['isolates'][0]['name'] = 'unrelated'
                    if failure == 'external' and method == 'getMemoryUsage': value['externalUsage'] = True
                    if failure == 'xml' and method == memory.ALLOCATOR_METHOD: value['malloc_info_xml'] = '<bad/>'
                return value
            with self.subTest(failure=failure):
                result = self.capture(rpc=reply, allocator_attribution=True)
                self.assertEqual(result['status'], 'failed')
                self.assertNotIn('allocator_diagnostic', result['roles']['worker'])
                self.assertNotIn('linux_smaps', result['roles']['worker'])
                self.assertIn('allocator_diagnostic', result['roles']['router'])

    def test_allocator_xml_rejects_unsupported_duplicate_missing_and_unsafe_totals(self):
        sample = self.allocator_reply(self.targets[0].uri, memory.ALLOCATOR_METHOD, 'isolates/1')
        xml = sample['malloc_info_xml']
        for invalid in (xml.replace('version="1"', 'version="2"'),
                        xml.replace('<heap nr="0">', '<heap nr="0"/><heap nr="0">'),
                        xml.replace('<total type="rest" size="10"/>', ''),
                        xml.replace('</malloc>', '<total type="rest" size="2"/></malloc>'),
                        xml.replace('size="100"', 'size="-1"'),
                        xml.replace('size="100"', 'size="18446744073709551616"'),
                        '<!DOCTYPE malloc><malloc version="1"/>', 'x' * 524289):
            with self.subTest(xml=invalid[:50]), self.assertRaises(ValueError):
                memory.validate_allocator_counters({**sample, 'malloc_info_xml': invalid}, 20)

    def test_allocator_rpc_is_isolate_scoped_and_does_not_enable_heap_or_gc_actions(self):
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = json.dumps(self.allocator_reply(self.targets[0].uri, memory.ALLOCATOR_METHOD, 'isolates/1')).encode()
        with mock.patch.object(memory.urllib.request, 'urlopen', return_value=response) as request:
            memory.memory_rpc(self.targets[0].uri, memory.ALLOCATOR_METHOD, 'isolates/1')
            self.assertTrue(request.call_args.args[0].endswith('ext.connectanum.diagnosticMallocInfo?isolateId=isolates%2F1'))
        for method, identifier in ((memory.ALLOCATOR_METHOD, None), ('getMemoryUsage', 'groups/1'),
                                   ('getAllocationProfile', 'isolates/1'), ('invoke', 'isolates/1')):
            with self.assertRaises(ValueError): memory.memory_rpc(self.targets[0].uri, method, identifier)

    def test_resident_compiler_heap_disqualifies_allocator_attribution(self):
        self.usage['root']['children'].append({'name': 'IsolateGroup kernel-service', 'size': 280 * 1024**2, 'children': []})
        result = self.capture(rpc=self.allocator_reply, allocator_attribution=True)
        self.assertEqual(result['status'], 'failed')
        role = result['roles']['worker']
        self.assertEqual(role['failure_phase'], 'kernel_service_exclusion')
        self.assertEqual(role['validation_error'], 'Compiler service is resident in allocator diagnostic')
        self.assertEqual(role['error_site']['function'], 'capture_target_memory')
        self.assertNotIn('linux_smaps', role)

    def test_external_errors_retain_safe_phase_and_site_without_private_message(self):
        def fail(uri, method): raise ValueError('http://127.0.0.1/privateToken=/')
        result = self.capture(rpc=fail)
        role = result['roles']['worker']
        self.assertEqual(role['failure_phase'], 'getVM')
        self.assertIn('error_site', role)
        self.assertNotIn('validation_error', role)
        self.assertNotIn('privateToken', json.dumps(result))

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
