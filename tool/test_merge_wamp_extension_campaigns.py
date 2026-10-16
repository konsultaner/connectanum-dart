"""Synthetic evidence exercises real guards; never benchmark acceptance data."""
import copy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import merge_wamp_extension_campaigns as merger
import test_wamp_serializer_compare as fixtures


class ArtifactSelectionTest(unittest.TestCase):
    source = 'a' * 40

    def artifact(self, shard, attempt=1, identity=1, **extra):
        return {'name': f'wamp-flatbuffers-primary-{self.source}-{attempt}-{shard}',
                'id': identity, 'expired': False, **extra}

    def test_retry_selects_latest_atomic_batch_without_splicing(self):
        rows = [self.artifact(name, identity=index + 1)
                for index, name in enumerate(merger.extensions.SHARDS)]
        rows.append(self.artifact('payload_sizes', attempt=2, identity=99))
        self.assertEqual(merger.select_artifact_ids([{'artifacts': rows}], self.source), [1, 99, 3])
        rows[-1]['expired'] = True
        with self.assertRaisesRegex(ValueError, 'expired'):
            merger.select_artifact_ids([{'artifacts': rows}], self.source)

    def test_missing_duplicate_and_malformed_artifacts_fail_closed(self):
        complete = [self.artifact(name, identity=index + 1)
                    for index, name in enumerate(merger.extensions.SHARDS)]
        for rows in [complete[:2], complete + [complete[0]],
                     complete + [self.artifact('unknown')],
                     [*complete[:2], self.artifact(merger.extensions.SHARDS[2], identity=True)]]:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                merger.select_artifact_ids([{'artifacts': rows}], self.source)


class MergeEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = 'a' * 40
        # Shrink only the declared test inventory, not policy, metrics or guards.
        # Separate canonical-inventory tests require all real 50 cases/1500 rows.
        self.cases = []
        for index, group in enumerate(('small_control', 'payload_sizes', 'encrypted_progressive_results')):
            identity = f'synthetic_{index}'
            self.cases.append({
                'id': identity, 'group': group, 'mode': 'rpc', 'transport': 'rawsocket',
                'secure_transport': False, 'client_impl': 'dart', 'construction': 'values',
                'payload_profile': 'wamp_envelope_cbor_args',
                'fields': {'peer_count': 1, 'request_bytes': 128, 'response_bytes': 128,
                           'path': 'bench.rpc.echo'},
                'workloads': {codec: f'{identity}_{codec}' for codec in merger.extensions.CODECS},
            })
        patch = mock.patch.object(merger.extensions, 'extension_cases',
                                  side_effect=lambda: copy.deepcopy(self.cases))
        patch.start()
        self.addCleanup(patch.stop)
        self.policy = merger.object_file(merger.campaign.POLICY)
        for index, shard in enumerate(merger.extensions.SHARDS):
            self.make_batch(shard, index)

    def make_batch(self, shard, index):
        root = self.root / shard / 'campaign'
        root.mkdir(parents=True)
        inputs = root / 'inputs'
        inputs.mkdir()
        repo = Path(__file__).resolve().parents[1]
        locks = {}
        for name in merger.LOCKFILES:
            path = inputs / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(repo / name, path)
            locks[name] = merger.campaign.sha256(path)
        shutil.copyfile(merger.campaign.POLICY, inputs / 'policy.json')
        (inputs / 'router_config.json').write_text('{"synthetic":true}\n')
        setup = root.parent / 'setup'
        setup.mkdir()
        artifacts = {}
        for key, name in [('driver', 'http_stream'), ('native_library', 'libct_ffi.so')]:
            (setup / name).write_text(f'explicit synthetic {key}\n')
            artifacts[key] = merger.campaign.sha256(setup / name)
        cases = merger.extensions.cases_for_shard(shard)
        runs = merger.campaign.schedule(cases, 3, 7, 42)
        scenario_hash = merger.campaign.write_scenarios(root, cases, runs, 10000, 1000, 1, 1)
        fixture = fixtures.WampSerializerCompareTest()
        all_rows = []
        for run_index, run in enumerate(runs):
            start = datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=run_index * 120)
            run.update(status='completed', rows_completed=len(run['order']),
                       started_at_utc=start.isoformat(),
                       completed_at_utc=(start + timedelta(seconds=100)).isoformat())
            rows = []
            for name in run['order']:
                codec = next(codec for codec in merger.extensions.CODECS if name.endswith('_' + codec))
                row = fixture._report(name, codec, run_index)
                row.update(iterations=1000, request_chunk_bytes=128, response_chunk_bytes=128)
                row['wamp_configuration'] = {
                    'serializer': codec, 'secure_transport': False, 'payload_bytes': 128,
                    'peer_count': 1, 'in_flight_per_session': 1,
                    **{key: None for key in ('peer_serializer', 'ppt_scheme', 'ppt_serializer',
                                            'ppt_cipher', 'ppt_keyid', 'payload_construction',
                                            'websocket_fragment_size')},
                }
                row['samples'] = [dict(row['samples'][0], iteration=i, request_bytes=128, response_bytes=128)
                                  for i in range(1000)]
                for process, base in [('client', 1000), ('server', 2000)]:
                    metrics = row[process + '_process_metrics']
                    metrics['pid'] = base + index * 10000
                    metrics['allocation_measurement'] = fixtures.allocation_fixture(metrics)
                volume = row['copy_metrics']['encoded_wamp_volume']
                volume.update(accepted_bytes=259000, known_accepted_bytes=259000,
                              components={'client_dart': 129000, 'router_dart': 0,
                                          'client_native': 0, 'router_native': 130000})
                rows.append(row)
            path = root / run['results']
            path.parent.mkdir(exist_ok=True)
            path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
            all_rows.extend(rows)
        (root / 'driver-results.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in all_rows))
        manifest = {
            'schema_version': 1, 'order_seed': 42, 'overlap_detected': False,
            'cases': cases, 'warmup_runs': [run for run in runs if run['kind'] == 'warmup'],
            'measured_runs': [run for run in runs if run['kind'] == 'measured'],
            'metadata': {
                'campaign_kind': 'extension_diagnostic', 'diagnostic_shard': shard,
                'diagnostic_inventory': merger.extensions.INVENTORY,
                'source_revision': self.source, 'working_tree_clean': True, 'inputs_unchanged': True,
                'scenario_sha256': scenario_hash, 'lockfiles_sha256': locks,
                'router_config_sha256': merger.campaign.sha256(inputs / 'router_config.json'),
                'policy_sha256': merger.campaign.sha256(merger.campaign.POLICY),
                'artifacts_sha256': artifacts, 'resource_mode': 'source_vm_metrics',
                'worker_lifetime': 'one_driver_and_stable_client_server_processes',
                'load_average': [0.0, 0.0, 0.0],
                'platform': {'os': 'Linux', 'kernel': 'synthetic', 'cpu_model': f'synthetic-{shard}',
                             'logical_cpu_count': 4, 'runner_image': 'synthetic',
                             'dart_version': 'synthetic Dart', 'rustc_version': 'synthetic Rust'},
            },
            'execution': {'status': 'completed', 'driver_exit_code': 0, 'process_group_stopped': True,
                          'observed_process_pids': {'client_process_metrics': 1000 + index * 10000,
                                                    'server_process_metrics': 2000 + index * 10000}},
        }
        (root / 'manifest.json').write_text(json.dumps(manifest))
        result = merger.compare.evaluate_campaign(manifest, root, self.policy)
        self.assertEqual(result['status'], 'diagnostic_shard_complete', result['findings'])
        (root / 'comparison.json').write_text(json.dumps(result))

    def manifest(self, shard='protocol'):
        return self.root / shard / 'campaign/manifest.json'

    def edit_manifest(self, action, shard='protocol'):
        path = self.manifest(shard)
        value = json.loads(path.read_text())
        action(value)
        path.write_text(json.dumps(value))

    def assert_failed(self, text):
        result, _ = merger.merge(self.root, self.source)
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(any(text in finding for finding in result['findings']), result['findings'])

    def test_complete_batches_preserve_per_case_results_and_hardware_scope(self):
        (self.root / 'protocol').rename(
            self.root / f'wamp-flatbuffers-primary-{self.source}-2-protocol')
        result, manifest = merger.merge(self.root, self.source)
        self.assertEqual(result['status'], 'diagnostic_complete', result['findings'])
        self.assertEqual(result['row_count'], 90)
        self.assertEqual(result['case_count'], 3)
        self.assertFalse(result['primary_acceptance_eligible'])
        self.assertEqual([case['id'] for case in result['cases']], [case['id'] for case in self.cases])
        self.assertEqual(result['cross_shard_absolute_comparisons'], 'not_comparable')
        self.assertEqual(len(manifest['execution_shards']), 3)
        protocol = next(shard for shard in manifest['execution_shards'] if shard['name'] == 'protocol')
        self.assertEqual(protocol['workflow_attempt'], 2)
        self.assertIn('-2-protocol', protocol['artifact_name'])
        self.assertIn('are not comparable', merger.markdown(result))

    def test_missing_and_duplicate_batches_cannot_complete(self):
        shutil.rmtree(self.root / 'payload_sizes')
        self.assert_failed('missing required')
        shutil.copytree(self.root / 'protocol', self.root / 'duplicate')
        self.assert_failed('duplicate')

    def test_source_scope_inputs_and_cancellation_are_not_trusted(self):
        for action, text in [
            (lambda m: m['metadata'].update(source_revision='b' * 40), 'different source'),
            (lambda m: m['metadata'].update(campaign_kind='primary'), 'different source'),
            (lambda m: m['metadata'].update(inputs_unchanged=False), 'inputs must remain'),
            (lambda m: m['execution'].update(status='cancelled'), 'did not complete'),
        ]:
            path = self.manifest()
            original = path.read_bytes()
            with self.subTest(text=text):
                self.edit_manifest(action)
                self.assert_failed(text)
            path.write_bytes(original)

    def test_policy_router_locks_and_native_binary_hashes_are_verified(self):
        root = self.manifest().parent
        for path in [root / 'inputs/policy.json', root / 'inputs/router_config.json',
                     root / 'inputs/pubspec.lock', root.parent / 'setup/libct_ffi.so']:
            original = path.read_bytes()
            with self.subTest(path=path):
                path.write_bytes(original + b'corrupt')
                self.assert_failed('hash differs')
            path.write_bytes(original)

    def test_inventory_and_row_omissions_do_not_balance_each_other(self):
        manifest = self.manifest().read_bytes()
        self.edit_manifest(lambda m: m['cases'][0].update(id='wrong-case'))
        self.assert_failed('inventory')
        self.manifest().write_bytes(manifest)
        root = self.manifest().parent
        data = json.loads(manifest)
        target = root / data['measured_runs'][0]['results']
        rows = [json.loads(line) for line in target.read_text().splitlines()]
        rows[0] = copy.deepcopy(rows[1])
        target.write_text(''.join(json.dumps(row) + '\n' for row in rows))
        # Keep the total and driver/per-pass equality: only per-codec coverage
        # detects this compensating omission and duplication.
        (root / 'driver-results.jsonl').write_text(''.join(
            (root / run['results']).read_text()
            for run in data['warmup_runs'] + data['measured_runs']))
        self.assert_failed('duplicate workload')

    def test_driver_stream_and_stored_conclusions_are_independently_checked(self):
        root = self.manifest().parent
        path = root / 'driver-results.jsonl'
        original = path.read_bytes()
        path.write_bytes(original + original.splitlines(keepends=True)[0])
        self.assert_failed('driver stream differs')
        path.write_bytes(original)
        conclusion = root / 'comparison.json'
        stored = json.loads(conclusion.read_text())
        stored['status'] = 'passed'
        conclusion.write_text(json.dumps(stored))
        self.assert_failed('raw recomputation')

    def test_recomputed_evidence_rejects_low_samples_pid_changes_and_unknown_copies(self):
        root = self.manifest().parent
        manifest = json.loads(self.manifest().read_text())
        path = root / manifest['measured_runs'][0]['results']
        original = path.read_text()
        for action, text in [
            (lambda r: r.update(samples=r['samples'][:10]), 'samples'),
            (lambda r: r['client_process_metrics'].update(pid=9090), 'PID'),
            (lambda r: r['copy_metrics']['coverage'].update(unknown_boundaries=['hidden']), 'unknown'),
        ]:
            with self.subTest(text=text):
                rows = [json.loads(line) for line in original.splitlines()]
                action(rows[0])
                path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
                self.assert_failed(text)
            path.write_text(original)

    def test_failed_ci_matrix_cannot_publish_completion_even_with_valid_raw_rows(self):
        output = self.root / 'aggregate'
        self.assertEqual(merger.main([
            'merge', '--root', str(self.root), '--source', self.source,
            '--jobs-result', 'failure', '--output', str(output),
        ]), 1)
        result = json.loads((output / 'comparison.json').read_text())
        self.assertEqual(result['status'], 'failed')
        self.assertFalse(result['primary_acceptance_eligible'])
        self.assertIn('not every case-batch CI job succeeded', result['findings'])


if __name__ == '__main__':
    unittest.main()
