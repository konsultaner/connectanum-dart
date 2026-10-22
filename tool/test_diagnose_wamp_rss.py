import argparse
import copy
import json
from pathlib import Path
import tempfile
import tomllib
import unittest
from unittest import mock

import diagnose_wamp_rss as diagnostic


class RssControlTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.launched_environments = []
        self.case = next(c for c in diagnostic.campaign.primary_cases() if c['id'] == diagnostic.CASES[0])
        self.policy = json.loads(diagnostic.campaign.POLICY.read_text())

    def rows(self, codec, *, client=100, server=200):
        result = []
        for i in range(self.policy['minimum_warmup_runs'] + self.policy['minimum_repetitions']):
            start = 1_790_000_000_000 + i * 11_000
            result.append({
                'workload': self.case['workloads'][codec], 'protocol': 'wamp_rawsocket_rpc',
                'client_impl': 'native', 'request_chunk_bytes': 65536, 'response_chunk_bytes': 65536,
                'data_window_elapsed_ms': 10000,
                'started_at_ms': start, 'completed_at_ms': start + 10_000,
                'samples': [{'worker': 0, 'iteration': n, 'latency_ms': 1.25,
                             'request_bytes': 65536, 'response_bytes': 65536} for n in range(2)],
                'wamp_configuration': {'serializer': codec, 'peer_serializer': None, 'peer_count': 1,
                    'payload_bytes': 65536, 'secure_transport': False, 'ppt_scheme': 'x_connectanum_bench_typed',
                    'ppt_serializer': codec, 'payload_construction': 'native_buffer', 'ppt_cipher': None, 'ppt_keyid': None},
                'client_process_metrics': {'pid': client, 'rss_before_bytes': 100, 'peak_rss_during_bytes': 120, 'current_rss_bytes': 110},
                'server_process_metrics': {'pid': server, 'rss_before_bytes': 200, 'peak_rss_during_bytes': 230, 'current_rss_bytes': 210},
            })
        return result

    def test_real_driver_report_shape_accepts_workload_timestamps_without_sample_timestamps(self):
        rows = self.rows('flatbuffers')
        self.assertNotIn('started_at_us', rows[0]['samples'][0])
        policy = dict(self.policy, minimum_samples_per_run=2)
        with mock.patch.object(diagnostic.compare, '_validate_evidence', return_value=[]):
            result = diagnostic.validate_rows(rows, self.case, 'flatbuffers', policy)
        self.assertEqual(len(result['measured']), 7)

    def test_missing_or_invalid_report_timestamp_is_rejected(self):
        policy = dict(self.policy, minimum_samples_per_run=2)
        for value in (None, True, -1, '1000'):
            rows = self.rows('flatbuffers')
            rows[0]['started_at_ms'] = value
            with mock.patch.object(diagnostic.compare, '_validate_evidence', return_value=[]):
                with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'timestamps'):
                    diagnostic.validate_rows(rows, self.case, 'flatbuffers', policy)

    def test_generated_control_preserves_real_policy_and_exact_codec_configuration(self):
        pair = self.root / 'pair'
        runs, digest = diagnostic.prepare_pair(pair, self.case, 'flatbuffers', self.policy)
        files = sorted((pair / 'scenarios').glob('*.toml'))
        self.assertEqual(len(files), 10)
        for path, run in zip(files, runs):
            workloads = tomllib.loads(path.read_text())['workloads']
            self.assertEqual(len(workloads), 1)
            row = workloads[0]
            self.assertEqual(row['name'], self.case['workloads']['flatbuffers'])
            self.assertEqual(row['serializer'], 'flatbuffers')
            self.assertEqual(row['ppt_serializer'], 'flatbuffers')
            self.assertEqual(row['payload_construction'], 'native_buffer')
            self.assertEqual((row['iterations'], row['minimum_duration_ms']), (1000, 10000))
            self.assertEqual((row['concurrency'], row['in_flight_per_session']), (1, 1))
            self.assertEqual((row['request_bytes'], row['response_bytes']), (65536, 65536))
        self.assertEqual(digest, diagnostic.campaign.scenario_directory_hash(pair / 'scenarios'))

    def test_truncated_or_replayed_rows_cannot_claim_complete_pair(self):
        policy = dict(self.policy, minimum_samples_per_run=2)
        with mock.patch.object(diagnostic.compare, '_validate_evidence', return_value=[]):
            rows = self.rows('flatbuffers')
            valid = diagnostic.validate_rows(rows, self.case, 'flatbuffers', policy)
            self.assertEqual(len(valid['measured']), 7)
            with self.assertRaisesRegex(ValueError, 'Expected 10'):
                diagnostic.validate_rows(rows[:-1], self.case, 'flatbuffers', policy)
            rows[-1] = copy.deepcopy(rows[0])
            with self.assertRaisesRegex(ValueError, 'Replayed'):
                diagnostic.validate_rows(rows, self.case, 'flatbuffers', policy)

    def test_wrong_config_pid_or_missing_rss_is_rejected(self):
        policy = dict(self.policy, minimum_samples_per_run=2)
        mutations = [lambda rows: rows[2]['wamp_configuration'].update(peer_count=True),
                     lambda rows: rows[2]['server_process_metrics'].update(pid=999),
                     lambda rows: rows[2]['client_process_metrics'].update(peak_rss_during_bytes=None)]
        with mock.patch.object(diagnostic.compare, '_validate_evidence', return_value=[]):
            for mutation in mutations:
                rows = self.rows('flatbuffers')
                mutation(rows)
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    diagnostic.validate_rows(rows, self.case, 'flatbuffers', policy)

    def execute(self, *, corrupt=None, cleanup=True, launch_error=None, wait_error=None):
        self.policy['minimum_samples_per_run'] = 2  # Unit fixture only; generation test pins real floors.
        policy = self.root / 'policy.json'
        policy.write_text(json.dumps(self.policy))
        for name in diagnostic.RESOLVED:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixed resolved input')
        for name in ['driver', 'native.so', 'router.json', 'source.txt']:
            (self.root / name).write_text('fixed fixture')
        args = argparse.Namespace(output=self.root / 'output', driver=self.root / 'driver', native_lib=self.root / 'native.so',
                                  router_config=self.root / 'router.json', dart='dart', case=self.case['id'])
        calls = []
        def output(command, **kwargs):
            if command[0] == 'nm': return '0000 T ct_runtime_new\n'
            if command[:3] == ['git', 'status', '--porcelain']: return ''
            if command[:3] == ['git', 'rev-parse', 'HEAD']: return 'fixed-head\n'
            raise AssertionError(command)
        def inputs(root):
            return {name: diagnostic.campaign.sha256(root / name) for name in ['source.txt', 'added.txt'] if (root / name).exists()}
        def popen(command, **kwargs):
            index = len(calls)
            calls.append(command)
            self.launched_environments.append(kwargs.get('env'))
            if launch_error:
                raise launch_error
            pair = Path(command[command.index('--scenario') + 1]).parent
            codec = diagnostic.SEQUENCE[index]
            rows = self.rows(codec, client=100 + index * 10, server=200 + index * 10)
            kwargs['stdout'].write('http://127.0.0.1:9123/privateToken=/ws\n')
            def wait(timeout):
                if wait_error:
                    raise wait_error
                if corrupt and index == 0:corrupt(rows, pair)
                (pair / 'reports.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in rows))
                return 0
            return argparse.Namespace(pid=3000 + index, wait=wait)
        with mock.patch.object(diagnostic.platform, 'system', return_value='Linux'), \
                mock.patch.object(diagnostic.platform, 'uname', return_value=argparse.Namespace(_asdict=lambda: {'system': 'Linux', 'machine': 'fixture'})), \
                mock.patch.object(diagnostic.campaign, 'POLICY', policy), \
                mock.patch.object(diagnostic.campaign, 'LOCK', self.root / 'lock'), \
                mock.patch.object(diagnostic.subprocess, 'check_output', side_effect=output), \
                mock.patch.object(diagnostic.subprocess, 'Popen', side_effect=popen), \
                mock.patch.object(diagnostic.campaign, 'stop_process_group', return_value=cleanup if not isinstance(cleanup, Exception) else False, side_effect=cleanup if isinstance(cleanup, Exception) else None), \
                mock.patch.object(diagnostic, 'source_inputs', side_effect=inputs), \
                mock.patch.object(diagnostic.compare, '_validate_evidence', return_value=[]):
            code = diagnostic.run(args, root=self.root)
        return code, json.loads((args.output / 'result.json').read_text()), calls

    def test_each_pair_preserves_canonical_worker_reuse_and_native_build_environment(self):
        code, result, calls = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual(len(self.launched_environments), 6)
        for environment in self.launched_environments:
            self.assertIsNotNone(environment)
            self.assertEqual(environment['CONNECTANUM_SKIP_NATIVE_BUILD'], '1')
            self.assertEqual(environment['CONNECTANUM_BENCH_WAMP_REUSE_WORKER'], '1')
        manifest = json.loads((self.root / 'output/inputs.json').read_text())
        self.assertEqual(manifest['driver_environment'], {
            'CONNECTANUM_SKIP_NATIVE_BUILD': '1', 'CONNECTANUM_BENCH_WAMP_REUSE_WORKER': '1'})

    def test_complete_control_is_always_ineligible_and_retains_separate_pairs(self):
        code, result, calls = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual(result['status'], 'diagnostic_complete_never_acceptance')
        self.assertFalse(result['primary_acceptance_eligible'])
        self.assertTrue(result['inputs_unchanged'])
        self.assertEqual(len(calls), 6)
        self.assertEqual([pair['codec'] for pair in result['pairs']], list(diagnostic.SEQUENCE))
        self.assertEqual(sum(pair['rows'] for pair in result['pairs']), 60)
        self.assertEqual(len({pair['driver_pid'] for pair in result['pairs']}), 6)
        for log in (self.root / 'output').glob('*/driver.log'):
            self.assertNotIn('privateToken', log.read_text())

    def test_zero_driver_exit_with_partial_rows_stops_after_retaining_failure(self):
        code, result, calls = self.execute(corrupt=lambda rows, pair: rows.pop())
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual(result['pairs'][0]['status'], 'failed')
        self.assertTrue(result['pairs'][0]['process_group_stopped'])
        self.assertTrue((self.root / 'output/00-flatbuffers/reports.jsonl').exists())

    def test_orphaned_process_group_prevents_next_codec_pair(self):
        code, result, calls = self.execute(cleanup=False)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn('cleanup', result['error'])

    def test_changed_scenario_or_new_source_is_not_a_complete_control(self):
        def mutate(rows, pair):
            (self.root / 'added.txt').write_text('new source during execution')
        code, result, calls = self.execute(corrupt=mutate)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn('added.txt', result['changed'])

    def test_scenario_mutation_is_retained_as_failed_not_complete(self):
        def mutate(rows, pair):
            path = next((pair / 'scenarios').glob('*.toml'))
            path.write_text(path.read_text() + '\n# changed during execution\n')
        code, result, calls = self.execute(corrupt=mutate)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn('Scenario inputs changed', result['error'])

    def test_changed_native_library_aborts_before_another_pair(self):
        def mutate(rows, pair):
            (self.root / 'native.so').write_text('different binary')
        code, result, calls = self.execute(corrupt=mutate)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn('native_library', result['changed'])

    def test_resolved_copy_race_never_starts_a_driver(self):
        original = diagnostic.shutil.copyfile
        def mutate(source, destination):
            if Path(source).name == 'pubspec.lock':
                Path(source).write_text('changed during retention')
            return original(source, destination)
        with mock.patch.object(diagnostic.shutil, 'copyfile', side_effect=mutate):
            with self.assertRaisesRegex(ValueError, 'Resolved input changed'):
                self.execute()
        self.assertFalse((self.root / 'output/result.json').exists())

    def test_resolved_source_changed_after_copy_aborts_before_driver(self):
        original = diagnostic.shutil.copyfile
        def mutate(source, destination):
            result = original(source, destination)
            if Path(source).name == 'pubspec.lock':
                Path(source).write_text('changed after retention')
            return result
        with mock.patch.object(diagnostic.shutil, 'copyfile', side_effect=mutate):
            code, result, calls = self.execute()
        self.assertEqual(code, 1)
        self.assertEqual(calls, [])
        self.assertIn('pubspec.lock', result['changed'])

    def test_cleanup_exception_still_redacts_and_records_failed_pair(self):
        code, result, calls = self.execute(cleanup=RuntimeError('cleanup failed'))
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertFalse(result['pairs'][0]['process_group_stopped'])
        self.assertEqual(result['pairs'][0]['cleanup_error'], 'cleanup failed')
        self.assertNotIn('privateToken', (self.root / 'output/00-flatbuffers/driver.log').read_text())

    def test_deadline_guard_never_starts_a_pair_without_its_minimum_floor_budget(self):
        self.policy['minimum_warmup_runs'] = 2000
        code, result, calls = self.execute()
        self.assertEqual(code, 1)
        self.assertEqual(calls, [])
        self.assertIn('deadline exhausted before next pair', result['error'])
        self.assertEqual(result['pairs'], [])

    def test_launch_exception_preserves_original_error_without_missing_exit_code(self):
        code, result, calls = self.execute(launch_error=OSError('fixture launch failure'))
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual(result['error'], 'fixture launch failure')
        self.assertNotIn('exit_code', result['pairs'][0])
        self.assertEqual(result['pairs'][0]['status'], 'failed')
        self.assertTrue((self.root / 'output/00-flatbuffers/execution.json').exists())

    def test_wait_exception_still_cleans_redacts_and_preserves_original_error(self):
        code, result, calls = self.execute(wait_error=TimeoutError('fixture wait deadline'))
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual(result['error'], 'fixture wait deadline')
        self.assertNotIn('exit_code', result['pairs'][0])
        self.assertTrue(result['pairs'][0]['process_group_stopped'])
        self.assertNotIn('privateToken', (self.root / 'output/00-flatbuffers/driver.log').read_text())


if __name__ == '__main__':
    unittest.main()
