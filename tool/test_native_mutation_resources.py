#!/usr/bin/env python3
"""Resource exhaustion must preserve evidence without granting completion."""

import json
import hashlib
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import native_mutation_resources as resources
from run_dart_mutations import run


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.work = self.root / 'owned'
        self.work.mkdir()
        self.output = self.root / 'evidence'
        self.output.mkdir()
        self.cancel = threading.Event()
        self.real_competing_processes = resources.competing_processes
        process_snapshot = patch.object(resources, 'competing_processes', return_value=[])
        process_snapshot.start()
        self.addCleanup(process_snapshot.stop)

    def guard(self, reserve=1, maximum=1024 * 1024, interval=.01):
        return resources.DiskGuard(self.work, self.output, self.cancel,
                                   resources.DiskLimits(reserve, maximum, interval))

    @staticmethod
    def companion(pid=101, script='ollama_companion.py', role='review'):
        return {'pid': pid, 'ppid': 7, 'state': 'S', 'executable': 'Python',
                'script': script, 'role': role}

    def test_process_parser_detects_only_active_companion_requests(self):
        processes = '''
  101   7 501 S  /opt/homebrew/bin/Python /skills/ollama_companion.py review --prompt secret
  102   7 501 S  /usr/bin/Python /skills/llama_companion.py tests --file source.dart
  103   1 501 S  /Applications/Ollama/llama-server --model cached.gguf
  104   7 501 S  /usr/bin/Python -m unittest test_ollama_companion.py
  105   7 501 S  /bin/zsh -c python3 /skills/ollama_companion.py review
  106   7 501 Z  /usr/bin/Python /skills/ollama_companion.py review
  107   7 777 S  /usr/bin/Python /skills/ollama_companion.py review
  108   7 501 S  rg ollama_companion.py
'''
        detected = resources.parse_competing_processes(processes, uid=501)
        self.assertEqual(detected, [self.companion(),
                                   self.companion(102, 'llama_companion.py', 'tests')])
        self.assertNotIn('secret', json.dumps(detected))
        self.assertNotIn('/skills/', json.dumps(detected))

    def test_detector_uses_a_bounded_process_snapshot(self):
        completed = type('Completed', (), {'stdout':
            ' 101 7 501 S /usr/bin/Python /skills/ollama_companion.py review\n'})()
        with patch.object(resources.subprocess, 'run', return_value=completed) as run, \
                patch.object(resources.time, 'sleep') as sleep:
            self.assertEqual(self.real_competing_processes(), [self.companion()])
        run.assert_called_once_with(
            ['ps', '-ww', '-axo', 'pid=,ppid=,uid=,state=,args='],
            capture_output=True, text=True, check=True, timeout=5)
        sleep.assert_not_called()

    def test_detector_retries_a_transient_snapshot_timeout_from_scratch(self):
        timed_out = resources.subprocess.TimeoutExpired(
            cmd=['ps'], timeout=5,
            output=' 999 7 501 S /usr/bin/Python /skills/ollama_companion.py ask\n')
        completed = type('Completed', (), {'stdout':
            ' 101 7 501 S /usr/bin/Python /skills/ollama_companion.py review\n'})()
        with patch.object(resources.subprocess, 'run',
                          side_effect=(timed_out, completed)) as run, \
                patch.object(resources.time, 'sleep') as sleep:
            self.assertEqual(self.real_competing_processes(), [self.companion()])
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[0], run.call_args_list[1])
        sleep.assert_called_once_with(resources.PROCESS_SNAPSHOT_RETRY_SECONDS)

    def test_detector_persistent_snapshot_timeout_still_fails_closed(self):
        timed_out = resources.subprocess.TimeoutExpired(cmd=['ps'], timeout=5)
        with patch.object(resources.subprocess, 'run', side_effect=timed_out) as run, \
                patch.object(resources.time, 'sleep') as sleep, \
                self.assertRaises(resources.subprocess.TimeoutExpired):
            self.real_competing_processes()
        self.assertEqual(run.call_count, resources.PROCESS_SNAPSHOT_ATTEMPTS)
        self.assertEqual(sleep.call_count, resources.PROCESS_SNAPSHOT_ATTEMPTS - 1)

    def test_detector_does_not_retry_a_non_timeout_snapshot_failure(self):
        denied = resources.subprocess.CalledProcessError(1, ['ps'])
        with patch.object(resources.subprocess, 'run', side_effect=denied) as run, \
                patch.object(resources.time, 'sleep') as sleep, \
                self.assertRaises(resources.subprocess.CalledProcessError):
            self.real_competing_processes()
        self.assertEqual(run.call_count, 1)
        sleep.assert_not_called()

    def test_active_companion_blocks_start_without_signalling_foreign_process(self):
        process = self.companion()
        with patch.object(resources, 'competing_processes', return_value=[process]), \
                patch.object(os, 'kill') as signal_process, \
                self.assertRaisesRegex(RuntimeError, 'competing local inference'):
            with self.guard():
                self.fail('Unsafe mutation worker started')
        signal_process.assert_not_called()
        self.assertTrue(self.cancel.is_set())
        summary = json.loads((self.output / 'resource-summary.json').read_text())
        self.assertFalse(summary['withinLimits'])
        self.assertEqual(summary['competingProcesses'], [process])
        self.assertNotIn('complete', summary)
        self.assertNotIn('gatePassed', summary)

    def test_midrun_companion_cancels_owned_work_without_signalling_foreign_process(self):
        process = self.companion()
        snapshots = iter(([], [process], []))
        with patch.object(resources, 'competing_processes', side_effect=lambda: next(snapshots)), \
                patch.object(os, 'kill') as signal_process, \
                self.assertRaisesRegex(RuntimeError, 'competing local inference'):
            with self.guard(interval=.01) as guard:
                self.assertTrue(self.cancel.wait(3))
                guard.check()
        signal_process.assert_not_called()
        summary = json.loads((self.output / 'resource-summary.json').read_text())
        self.assertEqual(summary['competingProcesses'], [process])
        rows = [json.loads(line) for line in
                (self.output / 'resources.jsonl').read_text().splitlines()]
        self.assertTrue(any(row['competingProcesses'] == [process] for row in rows))

    def test_audit_rejects_success_evidence_containing_competing_inference(self):
        with patch.object(resources, 'competing_processes', return_value=[]):
            with self.guard():
                pass
        process = self.companion()
        samples = self.output / 'resources.jsonl'
        rows = [json.loads(line) for line in samples.read_text().splitlines()]
        rows[-1]['competingProcesses'] = [process]
        samples.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
        summary_path = self.output / 'resource-summary.json'
        summary = json.loads(summary_path.read_text())
        summary['competingProcesses'] = [process]
        summary['peakCompetingProcesses'] = 1
        summary_path.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'competing'):
            resources.validate_evidence(self.output, self.manifest())

    def test_payload_growth_cannot_bypass_private_scratch_limit(self):
        temporary = self.work / 'tmp'
        temporary.mkdir()
        with self.assertRaisesRegex(RuntimeError, 'scratch'):
            with self.guard(maximum=512) as guard:
                (temporary / 'payload').write_bytes(b'x' * 1024)
                self.assertTrue(self.cancel.wait(3))
                guard.check()
        self.assertFalse(json.loads((self.output / 'resource-summary.json').read_text())['withinLimits'])

    def test_cache_and_payload_share_the_existing_private_budget(self):
        for name in ('target', 'tmp'):
            path = self.work / name
            path.mkdir()
            (path / 'data').write_bytes(b'x' * 1024)
        usage = resources.tree_usage(self.work / 'target')
        maximum = max(usage['logicalBytes'], usage['allocatedBytes'])
        with self.assertRaisesRegex(RuntimeError, 'scratch'):
            with self.guard(maximum=maximum):
                pass

    def test_temporary_usage_is_measured_and_independently_reaudited(self):
        temporary = self.work / 'tmp'
        temporary.mkdir()
        (temporary / 'payload').write_bytes(b'x' * 1024)
        with self.guard():
            pass
        path = self.output / 'resource-summary.json'
        summary = json.loads(path.read_text())
        self.assertEqual(summary['schemaVersion'], 3)
        self.assertEqual(summary['peakTemporaryLogicalBytes'], 1024)
        self.assertGreater(summary['peakTemporaryAllocatedBytes'], 0)
        resources.validate_evidence(self.output, self.manifest())
        summary['peakTemporaryLogicalBytes'] += 1
        path.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'summary'):
            resources.validate_evidence(self.output, self.manifest())

    def test_private_temporary_manifest_cannot_downgrade_to_legacy_schema(self):
        with self.guard():
            pass
        path = self.output / 'resource-summary.json'
        summary = json.loads(path.read_text())
        summary['schemaVersion'] = 1
        path.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'schema 2 or later'):
            resources.validate_evidence(self.output, {**self.manifest(), 'privateTemporaryDirectory': 'tmp'})

    def test_schema_two_rejects_missing_or_invalid_temporary_samples(self):
        with self.guard():
            pass
        path = self.output / 'resources.jsonl'
        original = path.read_text()
        for temporary in (None, [], {}, {'logicalBytes': 0},
                          {'logicalBytes': False, 'allocatedBytes': 0},
                          {'logicalBytes': 0, 'allocatedBytes': -1}):
            with self.subTest(temporary=temporary):
                rows = [json.loads(line) for line in original.splitlines()]
                if temporary is None:
                    rows[-1].pop('temporary')
                else:
                    rows[-1]['temporary'] = temporary
                path.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
                with self.assertRaisesRegex(ValueError, 'temporary|byte count'):
                    resources.validate_evidence(self.output, self.manifest())

    def test_audit_summary_byte_counts_and_samples_require_integers(self):
        with self.guard():
            pass
        path = self.output / 'resource-summary.json'
        original = json.loads(path.read_text())
        names = ('minimumAvailableBytes', 'peakCacheLogicalBytes', 'peakCacheAllocatedBytes',
                 'peakTemporaryLogicalBytes', 'peakTemporaryAllocatedBytes',
                 'peakScratchLogicalBytes', 'peakScratchAllocatedBytes', 'samples')
        for name in names:
            values = [float(original[name])]
            if original[name] == 0:
                values.append(False)
            for value in values:
                with self.subTest(name=name, value=value):
                    path.write_text(json.dumps({**original, name: value}))
                    with self.assertRaises(ValueError):
                        resources.validate_evidence(self.output, self.manifest())

    def test_historical_schema_one_still_requires_matching_cache_evidence(self):
        with self.guard():
            pass
        path = self.output / 'resource-summary.json'
        summary = json.loads(path.read_text())
        summary['schemaVersion'] = 1
        summary.pop('competingProcesses')
        summary.pop('peakCompetingProcesses')
        path.write_text(json.dumps(summary))
        samples = self.output / 'resources.jsonl'
        rows = [json.loads(line) for line in samples.read_text().splitlines()]
        for row in rows:
            row.pop('temporary')
            row.pop('competingProcesses')
        samples.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
        manifest = self.manifest()
        manifest.pop('resourceSchemaVersion')
        resources.validate_evidence(self.output, manifest)
        summary['peakCacheAllocatedBytes'] += 1
        path.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'summary'):
            resources.validate_evidence(self.output, self.manifest())

    def test_historical_schema_two_still_requires_matching_temporary_evidence(self):
        with patch.object(resources, 'competing_processes', return_value=[]):
            with self.guard():
                pass
        summary_path = self.output / 'resource-summary.json'
        summary = json.loads(summary_path.read_text())
        summary['schemaVersion'] = 2
        summary.pop('competingProcesses')
        summary.pop('peakCompetingProcesses')
        summary_path.write_text(json.dumps(summary))
        samples = self.output / 'resources.jsonl'
        rows = [json.loads(line) for line in samples.read_text().splitlines()]
        for row in rows:
            row.pop('competingProcesses')
        samples.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
        manifest = self.manifest()
        manifest.pop('resourceSchemaVersion')
        resources.validate_evidence(self.output, manifest)

    def test_current_manifest_cannot_downgrade_competing_process_evidence(self):
        with self.guard():
            pass
        manifest = self.manifest()
        summary_path = self.output / 'resource-summary.json'
        summary = json.loads(summary_path.read_text())
        summary['schemaVersion'] = 2
        summary.pop('competingProcesses')
        summary.pop('peakCompetingProcesses')
        summary_path.write_text(json.dumps(summary))
        samples = self.output / 'resources.jsonl'
        rows = [json.loads(line) for line in samples.read_text().splitlines()]
        for row in rows:
            row.pop('competingProcesses')
        samples.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
        manifest['resourceSummarySha256'] = hashlib.sha256(summary_path.read_bytes()).hexdigest()
        manifest['resourceSamplesSha256'] = hashlib.sha256(samples.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, 'schema differs'):
            resources.validate_evidence(self.output, manifest)

    def test_tree_counts_logical_and_allocated_bytes_once_without_following_links(self):
        cache = self.work / 'target'
        cache.mkdir()
        source = cache / 'object'
        source.write_bytes(b'x' * 1024)
        os.link(source, cache / 'hard-link')
        unrelated = self.root / 'unrelated'
        unrelated.mkdir()
        (unrelated / 'keep').write_bytes(b'y' * 8192)
        (cache / 'symlink').symlink_to(unrelated, target_is_directory=True)
        size = resources.tree_usage(cache)
        self.assertEqual(size['logicalBytes'], 1024)
        self.assertEqual(size['allocatedBytes'], source.stat().st_blocks * 512)
        self.assertEqual(size['files'], 1)
        self.assertEqual(size['skippedSymlinks'], 1)
        self.assertEqual((unrelated / 'keep').stat().st_size, 8192)

    def test_missing_cache_is_empty_but_symlink_root_is_rejected(self):
        self.assertEqual(resources.tree_usage(self.work / 'target')['files'], 0)
        (self.work / 'target').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            resources.tree_usage(self.work / 'target')

    def test_incremental_measurement_cannot_follow_a_linked_parent_directory(self):
        cache = self.work / 'target'
        cache.mkdir()
        unrelated = self.root / 'other'
        (unrelated / 'incremental').mkdir(parents=True)
        (unrelated / 'incremental/keep').write_bytes(b'x' * 8192)
        (cache / 'debug').symlink_to(unrelated, target_is_directory=True)
        with self.assertRaises(OSError):
            resources.tree_usage(cache, ('debug', 'incremental'))
        self.assertEqual((unrelated / 'incremental/keep').stat().st_size, 8192)

    def test_invalid_limits_reject_zero_negative_nonfinite_and_boolean_values(self):
        for limits in [(0, 1, 1), (1, 0, 1), (True, 1, 1), (1, True, 1),
                       (1, 1, 0), (1, 1, float('nan')), (1, 1, float('inf'))]:
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                resources.DiskLimits(*limits)

    def test_reserve_exhaustion_at_start_never_starts_a_worker(self):
        with patch.object(resources, 'available_bytes', return_value=0):
            with self.assertRaisesRegex(RuntimeError, 'reserve'):
                with self.guard():
                    self.fail('Unsafe worker started')
        self.assertTrue(self.cancel.is_set())
        summary = json.loads((self.output / 'resource-summary.json').read_text())
        self.assertIn('reserve', summary['failure'])
        self.assertFalse(summary['withinLimits'])

    def test_growth_cancels_and_keeps_raw_evidence_and_unrelated_files(self):
        (self.output / 'raw-log').write_text('partial evidence')
        unrelated = self.root / 'keep'
        unrelated.write_text('not owned')
        with self.assertRaisesRegex(RuntimeError, 'cache'):
            with self.guard(maximum=16) as guard:
                cache = self.work / 'target'
                cache.mkdir()
                (cache / 'object').write_bytes(b'x' * 32)
                self.assertTrue(self.cancel.wait(3))
                guard.check()
        self.assertEqual((self.output / 'raw-log').read_text(), 'partial evidence')
        self.assertEqual(unrelated.read_text(), 'not owned')
        self.assertFalse((self.output / 'audited-results.json').exists())
        self.assertFalse((self.output / 'combined.json').exists())

    def test_sampling_error_fails_closed_and_thread_always_finishes(self):
        guard = self.guard()
        with self.assertRaisesRegex(RuntimeError, 'sampling'):
            with guard:
                with patch.object(resources, 'tree_usage', side_effect=PermissionError('denied')):
                    self.assertTrue(self.cancel.wait(3))
                    guard.check()
        self.assertFalse(guard.thread.is_alive())

    def test_companion_detection_error_fails_closed_before_worker_start(self):
        guard = self.guard()
        with patch.object(resources, 'competing_processes', side_effect=OSError('denied')), \
                self.assertRaisesRegex(RuntimeError, 'sampling'):
            with guard:
                self.fail('Unsafe mutation worker started')
        self.assertTrue(self.cancel.is_set())
        self.assertIsNone(guard.thread)
        summary = json.loads((self.output / 'resource-summary.json').read_text())
        self.assertFalse(summary['withinLimits'])
        self.assertIn('OSError: denied', summary['failure'])

    def test_post_command_final_sample_can_prevent_false_completion(self):
        with self.assertRaisesRegex(RuntimeError, 'reserve'):
            with self.guard() as guard:
                with patch.object(resources, 'available_bytes', return_value=0):
                    guard.finish()
                guard.check()

    def test_external_cancellation_is_not_reported_as_success(self):
        with self.assertRaisesRegex(RuntimeError, 'cancelled'):
            with self.guard() as guard:
                self.cancel.set()
                guard.check()
        summary = json.loads((self.output / 'resource-summary.json').read_text())
        self.assertFalse(summary['withinLimits'])

    def test_success_retains_samples_and_idempotent_summary_without_thread(self):
        with self.guard() as guard:
            guard.finish()
            guard.check()
            summary = guard.summary
            guard.finish()
            self.assertEqual(guard.summary, summary)
        self.assertFalse(guard.thread.is_alive())
        self.assertTrue(summary['withinLimits'])
        samples = [json.loads(line) for line in
                   (self.output / 'resources.jsonl').read_text().splitlines()]
        self.assertGreaterEqual(len(samples), 2)
        self.assertEqual(summary['samples'], len(samples))
        self.assertNotIn('complete', summary)
        self.assertNotIn('gatePassed', summary)

    def manifest(self):
        summary = json.loads((self.output / 'resource-summary.json').read_text())
        return {'resourceLimits': summary['limits'],
                'resourceSchemaVersion': summary['schemaVersion'],
                'resourceSummarySha256': hashlib.sha256(
                    (self.output / 'resource-summary.json').read_bytes()).hexdigest(),
                'resourceSamplesSha256': hashlib.sha256(
                    (self.output / 'resources.jsonl').read_bytes()).hexdigest()}

    def test_audit_rechecks_limits_and_hashes_not_only_success_flag(self):
        with self.guard():
            pass
        manifest = self.manifest()
        resources.validate_evidence(self.output, manifest)
        path = self.output / 'resources.jsonl'
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        rows[-1]['availableBytes'] = 0
        path.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
        with self.assertRaisesRegex(ValueError, 'hash'):
            resources.validate_evidence(self.output, manifest)
        with self.assertRaisesRegex(ValueError, 'limits'):
            resources.validate_evidence(self.output, self.manifest())

    def test_audit_rejects_missing_policy_cancelled_and_inconsistent_summary(self):
        with self.guard():
            pass
        with self.assertRaisesRegex(ValueError, 'policy'):
            resources.validate_evidence(self.output, {})
        path = self.output / 'resource-summary.json'
        original = json.loads(path.read_text())
        for changes in [{'withinLimits': False, 'failure': 'cancelled'}, {'samples': 1},
                        {'peakCacheAllocatedBytes': 999}]:
            with self.subTest(changes=changes):
                path.write_text(json.dumps({**original, **changes}))
                with self.assertRaises(ValueError):
                    resources.validate_evidence(self.output, self.manifest())

    def test_existing_samples_are_never_overwritten(self):
        path = self.output / 'resources.jsonl'
        path.write_text('retained evidence')
        with self.assertRaises(FileExistsError):
            with self.guard():
                self.fail('Reused resource evidence')
        self.assertEqual(path.read_text(), 'retained evidence')
        self.assertFalse((self.output / 'resource-summary.json').exists())

    def test_guard_cancels_real_owned_process_before_workspace_cleanup(self):
        marker = self.work / 'alive'
        script = ('import pathlib,time; '
                  f'pathlib.Path({str(marker)!r}).write_text("started"); time.sleep(30)')
        result = []
        with self.assertRaisesRegex(RuntimeError, 'reserve'):
            with self.guard(interval=.01) as guard:
                worker = threading.Thread(target=lambda: result.append(
                    run(['python3', '-c', script], self.work, 40, cancel_event=self.cancel)))
                worker.start()
                deadline = time.monotonic() + 5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(marker.exists())
                with patch.object(resources, 'available_bytes', return_value=0):
                    self.assertTrue(self.cancel.wait(3))
                    worker.join(5)
                self.assertFalse(worker.is_alive())
                self.assertIsNone(result[0][0])
                self.assertIn('connectanumInfrastructureError', result[0][1])
                guard.check()


if __name__ == '__main__':
    unittest.main()
