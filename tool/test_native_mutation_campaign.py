#!/usr/bin/env python3
"""Parallel scheduling must preserve complete, independently audited evidence."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import native_coverage
import native_mutation_coordination as coordination
import native_mutation_batches as batches
import native_mutation_timing as timing
import run_native_mutation_campaign as campaign
import run_native_mutations as collector
from run_dart_mutations import run
import run_dart_mutations as runner
from test_native_mutation_batches import BatchEvidenceTests


class CampaignTests(BatchEvidenceTests):
    def collect(self, jobs=2, reuse=(), worker=None, sample_count=None):
        full = json.loads((self.directories[0] / 'filtered-inventory.json').read_text())

        def prepare(work, output, scope, target):
            for name in ('raw-inventory.json', 'inventory-partition.json', 'filtered-inventory.json'):
                (output / name).write_bytes((self.directories[0] / name).read_bytes())
            return collector.partition_inventory(full, scope)

        def collect(root, output, analyzer, target, batch=None, **kwargs):
            import shutil
            shutil.copytree(self.directories[batch[0]], output)
            return 0

        with patch.object(native_coverage, 'snapshot', return_value=self.scope), \
                patch.object(collector, 'prepare_inventory', side_effect=prepare), \
                patch.object(collector, 'collect', side_effect=worker or collect):
            return campaign.collect_campaign(self.root, self.root / 'parallel', Path('analyzer'),
                                             'core-all', 2, jobs, 1, reuse,
                                             sample_count=sample_count)

    def test_timing_pilot_is_deterministic_and_never_combines_partial_scores(self):
        self.assertEqual(campaign.sample_indices(16, 4), [0, 4, 8, 12])
        self.assertEqual(self.collect(jobs=1, sample_count=1), 0)
        output = self.root / 'parallel'
        manifest = json.loads((output / 'campaign-manifest.json').read_text())
        self.assertFalse(manifest['complete'])
        self.assertTrue(manifest['pilotComplete'])
        self.assertEqual(manifest['sampledBatchIndexes'], [0])
        self.assertNotIn('gatePassed', manifest)
        self.assertFalse((output / 'combined.json').exists())
        pilot = json.loads((output / 'pilot.json').read_text())
        self.assertTrue(pilot['timingOnly'])
        self.assertFalse(pilot['wholeComponentComplete'])
        self.assertEqual(pilot['sampledMutants'], 2)
        self.assertNotIn('adjustedCandidateScore', pilot)

    def test_pilot_limits_and_unrequested_reuse_are_rejected(self):
        for sample in (0, -1, True, 2, 3):
            with self.subTest(sample=sample), self.assertRaises(ValueError):
                self.collect(sample_count=sample)
        with self.assertRaisesRegex(ValueError, 'fresh'):
            self.collect(sample_count=1, reuse=self.directories[1:])

    def test_pilots_reject_even_valid_reuse_before_creating_output(self):
        with self.assertRaisesRegex(ValueError, 'fresh'):
            self.collect(sample_count=1, reuse=self.directories[:1])
        self.assertFalse((self.root / 'parallel').exists())

    def test_two_workers_overlap_and_complete_the_exact_union(self):
        import shutil
        barrier = threading.Barrier(2)
        roots = []

        def worker(root, output, analyzer, target, batch=None, **kwargs):
            roots.append(root)
            barrier.wait(timeout=5)
            shutil.copytree(self.directories[batch[0]], output)
            return 0

        self.assertEqual(self.collect(worker=worker), 0)
        report = json.loads((self.root / 'parallel/combined.json').read_text())
        self.assertEqual(report['generated'], 4)
        self.assertEqual(report['counts'], {'killed': 4})
        self.assertNotEqual(roots[0], self.root)
        self.assertEqual(roots[0], roots[1])
        manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
        self.assertTrue(manifest['complete'])
        self.assertEqual(manifest['maxConcurrentWorkers'], 2)
        self.assertGreater(manifest['elapsedSeconds'], 0)

    def test_reuse_reaudits_raw_evidence_without_rerunning_or_overwriting_it(self):
        before = (self.directories[0] / 'run-manifest.json').read_bytes()
        self.assertEqual(self.collect(reuse=self.directories), 0)
        self.assertEqual((self.directories[0] / 'run-manifest.json').read_bytes(), before)
        manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
        self.assertEqual(manifest['maxConcurrentWorkers'], 0)
        self.assertTrue(all(item['reused'] for item in manifest['batches']))
        self.assertFalse((self.root / 'parallel/batch-0000').exists())

    def test_corrupted_reuse_is_rejected_before_workers_start(self):
        path = self.directories[0] / 'mutants.out/logs/mutant-0.log'
        path.write_text(path.read_text() + '\nNo space left on device\n')
        from unittest.mock import Mock
        worker = Mock()
        with self.assertRaises(ValueError):
            self.collect(reuse=self.directories[:1], worker=worker)
        worker.assert_not_called()

    def test_duplicate_reused_indices_are_rejected(self):
        with self.assertRaises(ValueError):
            self.collect(reuse=[self.directories[0], self.directories[0]])

    def test_worker_failure_retains_incomplete_evidence_and_no_combined_score(self):
        def fail(root, output, analyzer, target, batch=None, **kwargs):
            output.mkdir()
            (output / 'failure.log').write_text('controlled infrastructure failure')
            raise RuntimeError('controlled infrastructure failure')

        with self.assertRaisesRegex(RuntimeError, 'Incomplete native batches'):
            self.collect(worker=fail)
        manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
        self.assertFalse(manifest['complete'])
        self.assertFalse((self.root / 'parallel/combined.json').exists())
        self.assertTrue((self.root / 'parallel/batch-0000/failure.log').exists())

    def test_worker_failure_cancels_queued_batches_before_collector_start(self):
        started = []

        def fail(root, output, analyzer, target, batch=None, **kwargs):
            started.append(batch[0])
            output.mkdir()
            (output / 'failure.log').write_text('restored baseline failed')
            raise RuntimeError('restored baseline failed')

        with self.assertRaisesRegex(RuntimeError, 'Incomplete native batches'):
            self.collect(jobs=1, worker=fail)
        self.assertEqual(started, [0])
        manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
        self.assertFalse(manifest['complete'])
        self.assertNotIn('gatePassed', manifest)
        self.assertFalse((self.root / 'parallel/combined.json').exists())
        self.assertFalse((self.root / 'parallel/batch-0001').exists())
        self.assertTrue((self.root / 'parallel/batch-0000/failure.log').exists())

    def test_unexpected_exit_cancels_queued_batches_before_collector_start(self):
        import shutil

        for code in (2, None, True, False, '1'):
            with self.subTest(code=code):
                started = []

                def fail(root, output, analyzer, target, batch=None, **kwargs):
                    started.append(batch[0])
                    return code

                with self.assertRaisesRegex(RuntimeError, 'Unexpected batch exit'):
                    self.collect(jobs=1, worker=fail)
                self.assertEqual(started, [0])
                manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
                self.assertFalse(manifest['complete'])
                self.assertNotIn('gatePassed', manifest)
                self.assertFalse((self.root / 'parallel/combined.json').exists())
                shutil.rmtree(self.root / 'parallel')

    def test_worker_failure_signals_active_owner_before_snapshot_cleanup(self):
        ready = threading.Barrier(2)
        observed = []
        roots = []

        def worker(root, output, analyzer, target, batch=None, cancel_event=None, **kwargs):
            roots.append(root)
            output.mkdir()
            ready.wait(timeout=5)
            if batch[0] == 0:
                raise RuntimeError('restored baseline failed')
            observed.append((cancel_event.wait(timeout=2), root.exists()))
            (output / 'cancelled.log').write_text('active owner settled')
            raise RuntimeError('active owner cancelled')

        with self.assertRaisesRegex(RuntimeError, 'Incomplete native batches'):
            self.collect(worker=worker)
        self.assertEqual(observed, [(True, True)])
        self.assertTrue(all(not root.exists() for root in roots))
        self.assertTrue((self.root / 'parallel/batch-0001/cancelled.log').exists())
        self.assertFalse((self.root / 'parallel/combined.json').exists())

    def test_failure_preserves_previously_completed_low_score_batch(self):
        import shutil

        def worker(root, output, analyzer, target, batch=None, **kwargs):
            if batch[0] == 0:
                shutil.copytree(self.directories[0], output)
                return 1
            output.mkdir()
            (output / 'failure.log').write_text('restored baseline failed')
            raise RuntimeError('restored baseline failed')

        with self.assertRaisesRegex(RuntimeError, 'Incomplete native batches'):
            self.collect(jobs=1, worker=worker)
        output = self.root / 'parallel'
        manifest = json.loads((output / 'campaign-manifest.json').read_text())
        self.assertEqual([(item['index'], item['exitCode']) for item in manifest['batches']], [(0, 1)])
        self.assertFalse(manifest['complete'])
        self.assertNotIn('gatePassed', manifest)
        self.assertTrue((output / 'batch-0000/audited-results.json').exists())
        self.assertTrue((output / 'batch-0001/failure.log').exists())
        self.assertFalse((output / 'combined.json').exists())

    def test_completed_low_score_or_unclean_evidence_still_fails_the_gate(self):
        import shutil
        original = batches.audit_batches
        started = []

        def worker(root, output, analyzer, target, batch=None, **kwargs):
            started.append(batch[0])
            shutil.copytree(self.directories[batch[0]], output)
            return 1

        def unclean(root, directories, analyzer):
            report = original(root, directories, analyzer)
            return {**report, 'evidenceClean': False}

        with patch.object(batches, 'audit_batches', side_effect=unclean):
            self.assertEqual(self.collect(jobs=1, worker=worker), 1)
        self.assertEqual(started, [0, 1])
        manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
        self.assertTrue(manifest['complete'])
        self.assertFalse(manifest['gatePassed'])

    def test_invalid_limits_or_overwrite_are_rejected(self):
        for count, jobs, build_jobs in [(0, 1, 1), (2, 0, 1), (2, 3, 1), (2, 1, 0),
                                       (True, 1, 1), (2, True, 1)]:
            with self.subTest(count=count, jobs=jobs, build_jobs=build_jobs), self.assertRaises(ValueError):
                campaign.collect_campaign(self.root, self.root / 'parallel', Path('analyzer'),
                                          'core-all', count, jobs, build_jobs)
        (self.root / 'parallel').mkdir()
        with self.assertRaises(FileExistsError):
            self.collect()

    def test_reuse_requires_the_same_full_inventory_and_partition(self):
        path = self.directories[0] / 'run-manifest.json'
        manifest = json.loads(path.read_text())
        manifest['batch']['count'] = 3
        path.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            self.collect(reuse=self.directories[:1])

    def test_single_worker_is_serial(self):
        self.assertEqual(self.collect(jobs=1), 0)
        manifest = json.loads((self.root / 'parallel/campaign-manifest.json').read_text())
        self.assertEqual(manifest['maxConcurrentWorkers'], 1)

    def test_source_change_while_workers_run_cannot_pass(self):
        import shutil

        def worker(root, output, analyzer, target, batch=None, **kwargs):
            shutil.copytree(self.directories[batch[0]], output)
            source = self.root / next(iter(self.scope['inputHashes']))
            source.write_text('changed source')
            return 0

        with self.assertRaisesRegex(ValueError, 'snapshot input changed'):
            self.collect(jobs=1, worker=worker)
        self.assertFalse((self.root / 'parallel/combined.json').exists())

    def test_build_parallelism_does_not_change_tests_or_deadlines(self):
        for build_jobs in (1, 4):
            commands = collector.commands(Path('/private/work'), Path('/evidence'),
                                          'core-all', build_jobs=build_jobs)
            for command in commands:
                self.assertIn(f'CARGO_BUILD_JOBS={build_jobs}', command)
                self.assertIn('--all-targets', command)
                self.assertIn('--no-fail-fast', command)
                self.assertEqual(command[-2:], ['--', '--test-threads=1'])
            self.assertEqual(commands[0][commands[0].index('--timeout') + 1], '180')
        for invalid in (True, 0, -1, 1.5):
            with self.assertRaises(ValueError):
                collector.commands(Path('/private/work'), Path('/evidence'), build_jobs=invalid)

    def test_build_environment_drift_rejects_reuse_without_logging_values(self):
        with patch.dict(os.environ, {'RUSTFLAGS': '--cfg stale_mutation_environment',
                                     'CARGO_REGISTRIES_TEST_TOKEN': 'do-not-retain-this-token'}):
            fingerprint = collector.execution_fingerprint()
            self.assertNotIn('do-not-retain-this-token', json.dumps(fingerprint))
            with self.assertRaisesRegex(ValueError, 'compiler/build environment'):
                self.collect(reuse=self.directories)


class CancellationTests(unittest.TestCase):
    def test_cancelled_parent_with_escaped_stdout_owner_cannot_hang_cleanup(self):
        cancel = threading.Event()
        timer = threading.Timer(.3, cancel.set)
        self.addCleanup(timer.cancel)
        child = 'import time;time.sleep(4)'
        parent = ('import subprocess,sys,time;'
                  f'p=subprocess.Popen([sys.executable,"-c",{child!r}],start_new_session=True);'
                  'print(p.pid,flush=True);time.sleep(10)')
        timer.start()
        started = time.monotonic()
        code, log = run([sys.executable, '-c', parent], '.', 5, cancel_event=cancel)
        escaped = int(log.splitlines()[0])
        try:
            self.assertIsNone(code)
            self.assertLess(time.monotonic() - started, 3)
            self.assertNotIn('Unresolved stdout pipe', log)
            self.assertEqual(runner.live_process_group_members(escaped), [])
        finally:
            try:
                os.kill(escaped, 9)
            except ProcessLookupError:
                pass

    def test_cancellation_kills_descendants_and_preserves_output_without_kill_credit(self):
        with tempfile.TemporaryDirectory() as directory:
            cancel = threading.Event()
            timer = threading.Timer(.4, cancel.set)
            self.addCleanup(timer.cancel)
            child = "import time,pathlib;time.sleep(1);pathlib.Path('late').touch()"
            parent = (f'import subprocess,sys,time;print("started",flush=True);'
                      f'subprocess.Popen([sys.executable,"-c",{child!r}]);time.sleep(10)')
            timer.start()
            code, log = run([sys.executable, '-c', parent], directory, 5, cancel_event=cancel)
            self.assertIsNone(code)
            self.assertIn('started', log)
            self.assertIn('cancelled', log)
            time.sleep(1.1)
            self.assertFalse((Path(directory) / 'late').exists())

    def test_pre_cancelled_command_never_starts(self):
        cancel = threading.Event()
        cancel.set()
        with patch('run_dart_mutations.subprocess.Popen') as start:
            code, log = run(['not-executed'], '.', 1, cancel_event=cancel)
        self.assertIsNone(code)
        self.assertIn('cancelled', log)
        start.assert_not_called()

    def test_detached_workers_are_cleaned_on_cancel_timeout_and_normal_exit(self):
        for mode in ('cancel', 'timeout', 'exit'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                cancel = threading.Event() if mode == 'cancel' else None
                timer = threading.Timer(.4, cancel.set) if cancel is not None else None
                if timer is not None:
                    self.addCleanup(timer.cancel)
                    timer.start()
                child = 'import time;time.sleep(60)'
                parent = ('import subprocess,sys,time;'
                          f'p=subprocess.Popen([sys.executable,"-c",{child!r}],'
                          'start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);'
                          'print(p.pid,flush=True);' +
                          ('time.sleep(10)' if mode != 'exit' else ''))
                # The unrelated process even shares the same working directory.
                with subprocess.Popen([sys.executable, '-c', child], cwd=directory,
                                      start_new_session=True) as unrelated:
                    try:
                        code, output = run([sys.executable, '-c', parent], directory,
                                           .6 if mode == 'timeout' else 5,
                                           cancel_event=cancel)
                        escaped = int(output.splitlines()[0])
                        try:
                            self.assertEqual(code, 0 if mode == 'exit' else None)
                            if mode == 'exit':
                                self.assertIn('connectanumInfrastructureError', output)
                            self.assertIsNone(unrelated.poll())
                            deadline = time.monotonic() + 1
                            while runner.live_process_group_members(escaped) and time.monotonic() < deadline:
                                time.sleep(.02)
                            self.assertEqual(runner.live_process_group_members(escaped), [], output)
                        finally:
                            try:
                                os.kill(escaped, 9)
                            except ProcessLookupError:
                                pass
                    finally:
                        unrelated.kill()
                        unrelated.wait(timeout=5)

    def test_reparented_worker_in_deleted_cwd_is_still_owned(self):
        with tempfile.TemporaryDirectory() as directory:
            private = Path(directory) / 'private'
            private.mkdir()
            child = 'import os,time;print(os.getpid(),flush=True);time.sleep(60)'
            parent = ('import os,subprocess,sys;'
                      f'p=subprocess.Popen([sys.executable,"-c",{child!r}],'
                      f'cwd={str(private)!r},start_new_session=True,'
                      'stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True);'
                      'pid=int(p.stdout.readline());p.stdout.close();'
                      f'os.rmdir({str(private)!r});print(pid,flush=True)')
            code, output = run([sys.executable, '-c', parent], directory, 5)
            escaped = int(output.splitlines()[0])
            try:
                self.assertEqual(code, 0)
                self.assertIn('connectanumInfrastructureError', output)
                self.assertEqual(runner.live_process_group_members(escaped), [])
                self.assertFalse(private.exists())
            finally:
                try:
                    os.kill(escaped, 9)
                except ProcessLookupError:
                    pass

    def test_concurrent_command_ownership_does_not_cross_attempts(self):
        from concurrent.futures import ThreadPoolExecutor

        cancel = threading.Event()
        timer = threading.Timer(.4, cancel.set)
        self.addCleanup(timer.cancel)
        child = 'import time;time.sleep(1)'
        parent = ('import subprocess,sys;'
                  f'p=subprocess.Popen([sys.executable,"-c",{child!r}],'
                  'start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);'
                  'print(p.pid,flush=True);code=p.wait();print("child_exit="+str(code),flush=True)')
        with ThreadPoolExecutor(max_workers=2) as pool:
            timer.start()
            interrupted = pool.submit(run, [sys.executable, '-c', parent], '.', 5,
                                      cancel_event=cancel)
            completed = pool.submit(run, [sys.executable, '-c', parent], '.', 5)
            code, output = interrupted.result(timeout=10)
            self.assertIsNone(code)
            self.assertIn('cancelled', output)
            code, output = completed.result(timeout=10)
            self.assertEqual(code, 0, output)
            self.assertIn('child_exit=0', output)
            self.assertNotIn('connectanumInfrastructureError', output)


def fixture(root, delay=200, marker=None):
    workspace = root / 'native/transport'
    workspace.mkdir(parents=True)
    (workspace / 'Cargo.toml').write_text(
        '[workspace]\nmembers = ["ct_core", "ct_ffi"]\nresolver = "2"\n')
    for package in ('ct_core', 'ct_ffi'):
        crate = workspace / package
        (crate / 'src').mkdir(parents=True)
        (crate / 'Cargo.toml').write_text(
            f'[package]\nname = "{package}"\nversion = "0.0.0"\n'
            'edition = "2021"\n[features]\nffi-test = []\n')
        functions = ''.join(f'pub fn value{index}() -> bool {{\n    true\n}}\n'
                            for index in range(8))
        assertions = ''.join(f'        assert!(super::value{index}());\n' for index in range(8))
        write_marker = f'        std::fs::write({json.dumps(str(marker))}, "late").unwrap();\n' if marker else ''
        (crate / 'src/lib.rs').write_text(functions + '#[cfg(test)]\nmod tests {\n'
            '    #[test]\n    fn behavior() {\n'
            f'        std::thread::sleep(std::time::Duration::from_millis({delay}));\n'
            + write_marker + assertions + '    }\n}\n')
    for name in collector.FIXTURES:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('public fixture')
    subprocess.run(['cargo', 'generate-lockfile', '--offline'], cwd=workspace,
                   check=True, capture_output=True, timeout=30)


class RealCampaignTests(unittest.TestCase):
    def setUp(self):
        process_snapshot = patch.object(collector.resources, 'competing_processes', return_value=[])
        process_snapshot.start()
        self.addCleanup(process_snapshot.stop)

    def test_real_guarded_campaign_rejects_competing_inference_without_score_or_signal(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
            fixture(root, delay=1)
            output = base / 'contended'
            process = {'pid': 811, 'ppid': 7, 'state': 'S', 'executable': 'Python',
                       'script': 'ollama_companion.py', 'role': 'review'}
            limits = collector.resources.DiskLimits(1, 1024 ** 3, .02)
            with patch.object(collector.resources, 'competing_processes', return_value=[process]), \
                    patch.object(os, 'kill') as signal_process, \
                    self.assertRaisesRegex(RuntimeError, 'competing local inference'):
                campaign.collect_campaign(root, output, self.analyzer,
                                          'core-all', 1, 1, 1,
                                          resource_limits=limits)
            signal_process.assert_not_called()
            manifest = json.loads((output / 'campaign-manifest.json').read_text())
            self.assertFalse(manifest['complete'])
            self.assertNotIn('gatePassed', manifest)
            self.assertFalse((output / 'combined.json').exists())
            summary = json.loads((output / 'batch-0000/resource-summary.json').read_text())
            self.assertEqual(summary['competingProcesses'], [process])
            self.assertFalse(summary['withinLimits'])

    def test_guarded_real_campaign_is_reauditable_and_reuse_requires_matching_limits(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
            fixture(root, delay=1)
            output = base / 'guarded'
            limits = collector.resources.DiskLimits(1, 1024 ** 3, .02)
            self.assertEqual(campaign.collect_campaign(root, output, self.analyzer,
                                                      'core-all', 4, 4, 1,
                                                      resource_limits=limits), 0)
            directories = sorted(output.glob('batch-*'))
            report = batches.audit_batches(root, directories, self.analyzer)
            self.assertEqual(report['counts'], {'killed': 8})
            self.assertTrue(report['evidenceClean'])
            self.assertEqual(report['resourceLimits']['reserve_bytes'], 1)
            self.assertEqual(report['resourceSchemaVersion'], collector.resources.SCHEMA_VERSION)
            for directory in directories:
                manifest = json.loads((directory / 'run-manifest.json').read_text())
                collector.resources.validate_evidence(directory, manifest)
                workspace = json.loads((directory / 'resource-summary.json').read_text())['workspace']
                self.assertFalse(Path(workspace).exists())
            self.assertEqual(campaign.collect_campaign(root, base / 'reuse', self.analyzer,
                                                      'core-all', 4, 4, 1, directories,
                                                      resource_limits=limits), 0)
            with self.assertRaisesRegex(ValueError, 'pinned campaign'):
                campaign.collect_campaign(root, base / 'mismatched-reuse', self.analyzer,
                                          'core-all', 4, 4, 1, directories,
                                          resource_limits=collector.resources.DiskLimits(2, 1024 ** 3, .02))

    def test_real_struct_field_shards_are_disjoint_exhaustive_and_assertion_killed(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
            fixture(root, delay=1)
            source = root / 'native/transport/ct_ffi/src/lib.rs'
            code = source.read_text().replace(
                '    fn behavior() {',
                '    fn behavior() {\n        assert!(super::pair().one);\n'
                '        assert!(super::pair().two);')
            source.write_text(code + '\n#[derive(Default)]\n'
                'pub struct Pair { pub one: bool, pub two: bool }\n'
                'pub fn pair() -> Pair {\n'
                '    Pair { one: true, two: true, ..Default::default() }\n}\n')
            output = base / 'struct-fields'
            self.assertEqual(campaign.collect_campaign(root, output, self.analyzer,
                                                      'ffi-all', 4, 2, 1), 0)
            report = json.loads((output / 'combined.json').read_text())
            fields = [item for item in report['results'] if item['mutant']['genre'] == 'StructField']
            self.assertEqual(len(fields), 2)
            self.assertEqual([item['status'] for item in fields], ['killed', 'killed'])
            self.assertTrue(report['wholeComponentComplete'])
            self.assertEqual(report['counts'], {'killed': report['generated']})
            for path in output.glob('batch-*'):
                manifest = json.loads((path / 'run-manifest.json').read_text())
                self.assertIn('--shard', manifest['campaignCommand'])
                self.assertIn('--all-targets', manifest['campaignCommand'])
                self.assertEqual(manifest['campaignCommand'][-2:], ['--', '--test-threads=1'])

    @classmethod
    def setUpClass(cls):
        cls.analyzer = native_coverage.REPO / 'out/rust-coverage-scope-target/debug/connectanum-coverage-scope'
        subprocess.run(['cargo', 'build', '--quiet', '--locked', '--manifest-path',
                        str(native_coverage.REPO / 'tool/rust_coverage_scope/Cargo.toml'),
                        '--target-dir', str(cls.analyzer.parent.parent)],
                       check=True, capture_output=True, timeout=120)

    def test_real_serial_and_parallel_campaigns_have_identical_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
            fixture(root)
            reports, timings = [], []
            for jobs in (1, 2, 4):
                output = base / f'jobs-{jobs}'
                self.assertEqual(campaign.collect_campaign(root, output, self.analyzer,
                                                          'core-all', 4, jobs, 1), 0)
                reports.append(json.loads((output / 'combined.json').read_text()))
                timings.append(json.loads((output / 'campaign-manifest.json').read_text()))
            self.assertEqual(reports[0]['generated'], 8)
            for key in ('generated', 'counts', 'baselineTests', 'inputHashes', 'toolHashes'):
                self.assertEqual(reports[0][key], reports[1][key])
            self.assertEqual([(item['mutant'], item['status']) for item in reports[0]['results']],
                             [(item['mutant'], item['status']) for item in reports[1]['results']])
            self.assertEqual(timings[0]['maxConcurrentWorkers'], 1)
            self.assertEqual(timings[1]['maxConcurrentWorkers'], 2)
            self.assertEqual(timings[2]['maxConcurrentWorkers'], 4)
            for key in ('generated', 'counts', 'baselineTests', 'inputHashes', 'toolHashes'):
                self.assertEqual(reports[0][key], reports[2][key])
            reuse = [Path(item['directory']) for item in timings[2]['batches']]
            self.assertEqual(campaign.collect_campaign(root, base / 'resumed', self.analyzer,
                                                      'core-all', 4, 2, 1, reuse), 0)
            print(json.dumps({'benchmark': 'controlled two-crate Cargo fixture, not production ETA',
                              'serialSeconds': timings[0]['elapsedSeconds'],
                              'parallelSeconds': timings[1]['elapsedSeconds'],
                              'speedup': timings[0]['elapsedSeconds'] / timings[1]['elapsedSeconds'],
                              'fourWorkerSeconds': timings[2]['elapsedSeconds'],
                              'fourWorkerSpeedup': timings[0]['elapsedSeconds'] / timings[2]['elapsedSeconds']}))

    def test_real_pilot_audits_timings_without_a_complete_campaign_or_score(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
            fixture(root, delay=1)
            output = base / 'pilot'
            self.assertEqual(campaign.collect_campaign(root, output, self.analyzer,
                                                      'core-all', 4, 2, 1, sample_count=2), 0)
            report = timing.analyze(root, output, self.analyzer, full_batches=4)
            self.assertEqual(report['generated'], 8)
            self.assertEqual(report['sampledMutants'], 4)
            self.assertEqual(len(report['sampleResults']), 4)
            self.assertTrue(report['sampleEvidenceClean'])
            self.assertFalse(report['wholeComponentComplete'])
            self.assertGreater(report['estimatedFullWallSeconds'], 0)
            self.assertEqual(report['unmeasuredFiles'], [])
            self.assertFalse((output / 'combined.json').exists())
            raw = output / 'batch-0000/mutants.out/outcomes.json'
            evidence = json.loads(raw.read_text())
            evidence['outcomes'][1]['phase_results'][0]['duration'] = -1
            raw.write_text(json.dumps(evidence))
            with self.assertRaises(ValueError):
                timing.analyze(root, output, self.analyzer, full_batches=4)

    def test_sigterm_cancels_real_cargo_groups_without_a_score_or_forced_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
            marker = base / 'late'
            fixture(root, delay=3000, marker=marker)
            output = base / 'evidence'
            launcher = ('import sys;sys.path.insert(0,sys.argv.pop(1));'
                        'import native_coverage,run_native_mutation_campaign as c;'
                        'from pathlib import Path;native_coverage.REPO=Path(sys.argv.pop(1));'
                        'sys.exit(c.main())')
            command = [sys.executable, '-c', launcher, str(Path(collector.__file__).parent),
                       str(root), '--analyzer', str(self.analyzer), '--output', str(output),
                       '--target', 'core-all', '--batches', '2', '--jobs', '2', '--cargo-jobs', '1']
            with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True,
                                  pass_fds=coordination.inherited_resource_lease_pass_fds()) as process:
                try:
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        manifests = list(output.glob('batch-*/run-manifest.json'))
                        if len(manifests) == 2:
                            break
                        if process.poll() is not None:
                            self.fail(process.communicate()[0])
                        time.sleep(.05)
                    self.assertEqual(len(manifests), 2)
                    process.terminate()
                    log = process.communicate(timeout=10)[0]
                    self.assertEqual(process.returncode, 130, log)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
            self.assertFalse((output / 'combined.json').exists())
            self.assertFalse(json.loads((output / 'campaign-manifest.json').read_text())['complete'])
            time.sleep(3.1)
            self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
