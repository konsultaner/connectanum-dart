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

    def guard(self, reserve=1, maximum=1024 * 1024, interval=.01):
        return resources.DiskGuard(self.work, self.output, self.cancel,
                                   resources.DiskLimits(reserve, maximum, interval))

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
        return {'resourceLimits': json.loads((self.output / 'resource-summary.json').read_text())['limits'],
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
