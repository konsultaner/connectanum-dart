import fcntl
import json
import os
import signal
import sys
import tempfile
import threading
import tomllib
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import run_wamp_serializer_campaign as campaign


class CampaignTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cases = campaign.primary_cases()[:1]
        self.runs = campaign.schedule(self.cases, 1, 1, 42)
        self.manifest = {
            'execution': {'status': 'planned'}, 'overlap_detected': False,
            'warmup_runs': [self.runs[0]], 'measured_runs': [self.runs[1]],
        }
        # These fake-process tests are functional fixtures, never timed acceptance runs.
        quiet_host = mock.patch.object(campaign, 'interfering_jobs', return_value=[])
        quiet_host.start()
        self.addCleanup(quiet_host.stop)

    def test_complete_matrix_and_balanced_reproducible_pairs(self):
        cases = campaign.primary_cases()
        self.assertEqual(len(cases), 48)
        self.assertEqual(len({c['id'] for c in cases}), 48)
        runs = campaign.schedule(cases, 3, 7, 42)
        self.assertEqual(runs, campaign.schedule(cases, 3, 7, 42))
        self.assertNotEqual(runs, campaign.schedule(cases, 3, 7, 43))
        expected = {v for c in cases for v in c['workloads'].values()}
        for run in runs:
            self.assertEqual(len(run['order']), 144)
            self.assertEqual(set(run['order']), expected)
        for case in cases:
            orders = []
            for run in runs[3:]:
                ordered = [codec for name in run['order'] for codec, value in case['workloads'].items() if name == value]
                orders.append(tuple(ordered))
                positions = [run['order'].index(case['workloads'][codec]) for codec in ordered]
                self.assertEqual(positions, list(range(positions[0], positions[0] + 3)))
            self.assertEqual(len(set(orders)), 6)
            self.assertEqual({order[0] for order in orders}, set(campaign.compare.CODECS))

    def test_toml_keeps_equivalent_typed_workloads_and_actual_hash(self):
        digest = campaign.write_scenarios(self.root, self.cases, self.runs, 10000, 1000, 2, 4)
        self.assertEqual(digest, campaign.scenario_directory_hash(self.root / 'scenarios'))
        for path in sorted((self.root / 'scenarios').glob('*.toml')):
            scenario = tomllib.loads(path.read_text())
            self.assertEqual(scenario['name'], path.stem)
            for workload in scenario['workloads']:
                self.assertEqual(workload['ppt_serializer'], workload['serializer'])
                self.assertEqual(workload['ppt_scheme'], 'x_connectanum_bench_typed')
                self.assertEqual(workload['request_bytes'], 65536)
                self.assertEqual(workload['iterations'], 1000)
                self.assertEqual(workload['minimum_duration_ms'], 10000)
                self.assertEqual(workload['peer_count'], 1)
        path.write_text(path.read_text() + '# changed\n')
        self.assertNotEqual(digest, campaign.scenario_directory_hash(self.root / 'scenarios'))

    def fake_driver(self, behavior='complete'):
        campaign.write_scenarios(self.root, self.cases, self.runs, 1, 1, 1, 1)
        script = self.root / 'fake_driver.py'
        # Synthetic timestamps and reports are test fixtures, never campaign evidence.
        script.write_text('''import json, pathlib, subprocess, sys, time, tomllib
root = pathlib.Path(sys.argv[1])
behavior = sys.argv[2]
if behavior == 'hang':
    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
    (root / 'child.pid').write_text(str(child.pid))
    time.sleep(60)
index = 0
with (root / 'driver-results.jsonl').open('wb') as stream:
    for path in sorted((root / 'scenarios').glob('*.toml')):
        scenario = tomllib.loads(path.read_text())
        for workload in scenario['workloads']:
            report = {'scenario': scenario['name'], 'workload': workload['name'],
                      'started_at_ms': 1790000000000 + index * 2,
                      'completed_at_ms': 1790000000001 + index * 2,
                      'client_process_metrics': {'pid': 123},
                      'server_process_metrics': {'pid': 456}}
            line = json.dumps(report).encode() + b'\\n'
            stream.write(line[:17]); stream.flush(); time.sleep(0.01)
            if behavior == 'truncated': sys.exit(0)
            stream.write(line[17:]); stream.flush()
            index += 1
            if behavior == 'failure': sys.exit(7)
''')
        return [sys.executable, str(script), str(self.root), behavior]

    def test_tails_split_lines_and_preserves_every_raw_report(self):
        campaign.execute(self.root, self.manifest, self.runs, self.fake_driver(), self.root, 5)
        self.assertEqual(self.manifest['execution']['status'], 'completed')
        self.assertEqual(self.manifest['execution']['driver_exit_code'], 0)
        self.assertTrue(self.manifest['execution']['process_group_stopped'])
        split = b''.join((self.root / r['results']).read_bytes() for r in self.runs)
        self.assertEqual(split, (self.root / 'driver-results.jsonl').read_bytes())
        self.assertTrue(all(r['status'] == 'completed' for r in self.runs))

    def test_partial_failure_keeps_exit_code_and_reports(self):
        with self.assertRaisesRegex(campaign.compare.CampaignError, 'driver exit 7'):
            campaign.execute(self.root, self.manifest, self.runs, self.fake_driver('failure'), self.root, 5)
        execution = json.loads((self.root / 'manifest.json').read_text())['execution']
        self.assertEqual(execution['status'], 'failed')
        self.assertEqual(execution['driver_exit_code'], 7)
        self.assertTrue(execution['process_group_stopped'])
        self.assertEqual(self.runs[0]['rows_completed'], 1)
        self.assertEqual((self.root / self.runs[0]['results']).read_bytes(), (self.root / 'driver-results.jsonl').read_bytes())

    def test_truncated_output_is_retained_and_never_parsed(self):
        with self.assertRaisesRegex(campaign.compare.CampaignError, 'truncated'):
            campaign.execute(self.root, self.manifest, self.runs, self.fake_driver('truncated'), self.root, 5)
        self.assertGreater((self.root / 'driver-results.jsonl').stat().st_size, 0)
        self.assertEqual(self.runs[0]['rows_completed'], 0)

    def test_busy_host_refuses_launch_and_retains_failed_manifest(self):
        command = self.fake_driver()
        with mock.patch.object(campaign, 'interfering_jobs', return_value=[{'pid': 123, 'program': 'cargo'}]):
            with mock.patch.object(campaign.subprocess, 'Popen') as launch:
                with self.assertRaisesRegex(campaign.compare.CampaignError, 'jobs are running'):
                    campaign.execute(self.root, self.manifest, self.runs, command, self.root, 5)
                launch.assert_not_called()
        self.assertTrue(self.manifest['overlap_detected'])
        self.assertEqual(self.manifest['execution']['status'], 'failed')
        self.assertTrue((self.root / 'manifest.json').exists())

    def test_cancellation_stops_real_descendant_and_retains_manifest(self):
        command = self.fake_driver('hang')
        timer = threading.Timer(0.3, lambda: os.kill(os.getpid(), signal.SIGINT))
        timer.start()
        try:
            with self.assertRaises(KeyboardInterrupt):
                campaign.execute(self.root, self.manifest, self.runs, command, self.root, 5)
        finally:
            timer.cancel()
            timer.join()
        execution = json.loads((self.root / 'manifest.json').read_text())['execution']
        self.assertEqual(execution['status'], 'interrupted')
        self.assertTrue(execution['process_group_stopped'])
        self.assertTrue((self.root / 'child.pid').exists())
        self.assertFalse(campaign.group_alive(execution['pid']))

    def test_recorder_rejects_wrong_attribution_and_overlap(self):
        recorder = campaign.Recorder(self.root, self.manifest, self.runs)
        def row(index, start, end):
            return json.dumps({'scenario': self.runs[0]['scenario'], 'workload': self.runs[0]['order'][index],
                               'started_at_ms': start, 'completed_at_ms': end,
                               'client_process_metrics': {'pid': 123},
                               'server_process_metrics': {'pid': 456}}).encode()
        with self.assertRaisesRegex(campaign.compare.CampaignError, 'attribution'):
            recorder.append(row(1, 100, 110))
        recorder.append(row(0, 100, 110))
        with self.assertRaisesRegex(campaign.compare.CampaignError, 'overlaps'):
            recorder.append(row(1, 109, 120))
        self.assertTrue(self.manifest['overlap_detected'])
        self.assertEqual(self.runs[0]['rows_completed'], 1)

    def test_restarted_client_cannot_claim_warmup_continuity(self):
        recorder = campaign.Recorder(self.root, self.manifest, self.runs)
        for index, pid in enumerate((123, 789)):
            line = json.dumps({
                'scenario': self.runs[0]['scenario'], 'workload': self.runs[0]['order'][index],
                'started_at_ms': 100 + index * 2, 'completed_at_ms': 101 + index * 2,
                'client_process_metrics': {'pid': pid}, 'server_process_metrics': {'pid': 456},
            }).encode()
            if index == 0:
                recorder.append(line)
            else:
                with self.assertRaisesRegex(campaign.compare.CampaignError, 'warmup'):
                    recorder.append(line)
        self.assertEqual(self.runs[0]['rows_completed'], 1)

    def cli_args(self, output):
        source = self.root / 'input'
        source.write_bytes(b'input')
        policy = (Path(__file__).resolve().parents[1] / 'native/bench/artifact_gate/wamp_flatbuffers_performance.json')
        return ['--output', str(output), '--driver', sys.executable, '--native-lib', str(source),
                '--router-config', str(source), '--runner-image', 'test fixture', '--policy', str(policy),
                '--diagnostic', '--prepare-only']

    def test_existing_output_is_preserved_and_host_lock_excludes_second_runner(self):
        output = self.root / 'output'
        output.mkdir()
        existing = output / 'manifest.json'
        existing.write_text('original')
        with mock.patch.object(campaign, 'LOCK', self.root / 'lock'):
            self.assertEqual(campaign.main(self.cli_args(output)), 2)
            self.assertEqual(existing.read_text(), 'original')
            with campaign.LOCK.open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                other = self.root / 'other'
                self.assertEqual(campaign.main(self.cli_args(other)), 2)
                self.assertFalse(other.exists())

    def test_nonfinite_deadline_is_rejected_before_creating_output(self):
        output = self.root / 'output'
        for value in ('nan', 'inf', '-inf'):
            with self.subTest(value=value):
                self.assertEqual(campaign.main(self.cli_args(output) + ['--campaign-timeout-seconds=' + value]), 2)
                self.assertFalse(output.exists())

    def primary_cli_args(self, output):
        return [arg for arg in self.cli_args(output) if arg != '--diagnostic']

    def test_primary_cli_rejects_each_reduced_acceptance_floor_before_launch(self):
        for option, value in (('--warmups', '2'), ('--repetitions', '6'),
                              ('--duration-ms', '9999'), ('--samples', '999')):
            with self.subTest(option=option):
                output = self.root / option.removeprefix('--')
                with mock.patch.object(campaign.platform, 'system', return_value='Linux'):
                    with mock.patch.object(campaign, 'execute') as execute:
                        self.assertEqual(campaign.main(self.primary_cli_args(output) + [option, value]), 2)
                        execute.assert_not_called()
                self.assertFalse(output.exists())

    def test_primary_cli_rejects_subset_and_invalid_environment_before_launch(self):
        output = self.root / 'output'
        args = self.primary_cli_args(output)
        with mock.patch.object(campaign, 'execute') as execute:
            self.assertEqual(campaign.main(args + ['--case', campaign.primary_cases()[0]['id']]), 2)
            with mock.patch.object(campaign.platform, 'system', return_value='Darwin'):
                self.assertEqual(campaign.main(args), 2)
            with mock.patch.object(campaign.platform, 'system', return_value='Linux'):
                changed_policy = self.root / 'changed-policy.json'
                original = json.loads(campaign.POLICY.read_text())
                original['minimum_samples_per_run'] = 999
                changed_policy.write_text(json.dumps(original))
                self.assertEqual(campaign.main(args + ['--policy', str(changed_policy)]), 2)
                with mock.patch.object(campaign, 'command_output', return_value=' M tracked.dart'):
                    self.assertEqual(campaign.main(args), 2)
            execute.assert_not_called()
        self.assertFalse(output.exists())

    def test_primary_prepare_keeps_all_1440_rows_and_policy_inputs(self):
        output = self.root / 'output'
        source_root = self.root / 'source'
        lockfiles = ('pubspec.lock', 'native/bench/Cargo.lock', 'native/transport/Cargo.lock')
        for name in lockfiles:
            path = source_root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('synthetic lock fixture: ' + name + '\n').encode())
        with (mock.patch.object(campaign.platform, 'system', return_value='Linux'),
              mock.patch.object(campaign, 'command_output', return_value=''),
              mock.patch.object(campaign, 'ROOT', source_root),
              mock.patch.object(campaign, 'LOCK', self.root / 'lock'),
              mock.patch.object(campaign, 'execute') as execute):
            self.assertEqual(campaign.main(self.primary_cli_args(output)), 0)
            execute.assert_not_called()
        # This is preparation with synthetic platform metadata, never timing evidence.
        manifest = json.loads((output / 'manifest.json').read_text())
        self.assertEqual(manifest['execution']['status'], 'planned')
        self.assertEqual(manifest['metadata']['campaign_kind'], 'primary')
        self.assertEqual(len(manifest['cases']), 48)
        self.assertEqual(len(manifest['warmup_runs']), 3)
        self.assertEqual(len(manifest['measured_runs']), 7)
        runs = manifest['warmup_runs'] + manifest['measured_runs']
        self.assertEqual(sum(len(run['order']) for run in runs), 1440)
        for path in (output / 'scenarios').glob('*.toml'):
            workloads = tomllib.loads(path.read_text())['workloads']
            self.assertEqual(len(workloads), 144)
            for workload in workloads:
                self.assertEqual(workload['minimum_duration_ms'], 10000)
                self.assertEqual(workload['iterations'], 1000)
        self.assertEqual((output / 'inputs/policy.json').read_bytes(), campaign.POLICY.read_bytes())
        self.assertEqual(set(manifest['metadata']['lockfiles_sha256']), set(lockfiles))
        for name in lockfiles:
            self.assertEqual((output / 'inputs' / name).read_bytes(), (source_root / name).read_bytes())
            self.assertEqual(manifest['metadata']['lockfiles_sha256'][name], campaign.sha256(source_root / name))
        self.assertFalse((output / 'comparison.json').exists())

    def test_deadline_stops_real_descendant_and_retains_failed_manifest(self):
        command = self.fake_driver('hang')
        with self.assertRaisesRegex(campaign.compare.CampaignError, 'deadline exceeded'):
            campaign.execute(self.root, self.manifest, self.runs, command, self.root, 0.3)
        execution = json.loads((self.root / 'manifest.json').read_text())['execution']
        self.assertEqual(execution['status'], 'failed')
        self.assertTrue(execution['process_group_stopped'])
        self.assertTrue((self.root / 'child.pid').exists())
        self.assertFalse(campaign.group_alive(execution['pid']))


if __name__ == '__main__':
    unittest.main()
