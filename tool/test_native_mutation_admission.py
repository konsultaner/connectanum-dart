#!/usr/bin/env python3
"""Admission budgets must not weaken reserve or imply mutation completion."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import native_mutation_admission as admission
from native_mutation_resources import DiskLimits


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.scratch = self.root / 'scratch'
        self.evidence = self.root / 'evidence'
        self.scratch.mkdir()
        self.evidence.mkdir()
        self.limits = DiskLimits(40, 15)

    def plan(self, **kwargs):
        return admission.plan_admission(self.scratch, self.evidence, self.limits,
                                        workers=kwargs.pop('workers', 4),
                                        evidence_bytes=kwargs.pop('evidence_bytes', 10), **kwargs)

    def test_shared_filesystem_sums_all_workers_and_evidence_at_exact_boundary(self):
        with patch.object(admission, 'available_bytes', side_effect=[110, 110]):
            report = self.plan()
        self.assertTrue(report['admitted'])
        self.assertEqual(len(report['filesystems']), 1)
        self.assertEqual(report['filesystems'][0]['requiredBytes'], 110)
        self.assertEqual(report['filesystems'][0]['roles'], ['scratch', 'evidence'])
        self.assertEqual(report['reserveBytes'], 40)
        self.assertEqual(report['cacheBudgetBytes'], 60)

    def test_one_byte_short_or_second_observation_drop_rejects(self):
        for values in ([109, 110], [110, 109]):
            with self.subTest(values=values):
                with patch.object(admission, 'available_bytes', side_effect=values):
                    report = self.plan()
                self.assertFalse(report['admitted'])
                self.assertEqual(report['filesystems'][0]['availableBytes'], 109)

    def test_separate_filesystems_require_reserve_on_both_not_minimum_shared_budget(self):
        with patch.object(admission, 'filesystem_device', side_effect=[1, 2]), \
                patch.object(admission, 'available_bytes', side_effect=[100, 50]):
            report = self.plan()
        self.assertTrue(report['admitted'])
        self.assertEqual([row['requiredBytes'] for row in report['filesystems']], [100, 50])
        with patch.object(admission, 'filesystem_device', side_effect=[1, 2]), \
                patch.object(admission, 'available_bytes', side_effect=[100, 49]):
            self.assertFalse(self.plan()['admitted'])

    def test_measured_lean_cap_can_fit_without_lowering_reserve_or_workers(self):
        gib = 1024 ** 3
        for cap, admitted in [(3 * gib, False), (3 * gib // 2, True)]:
            with self.subTest(cap=cap), patch.object(admission, 'available_bytes', return_value=12 * gib):
                report = admission.plan_admission(self.scratch, self.evidence,
                                                  DiskLimits(4 * gib, cap), 4, gib)
            self.assertEqual(report['admitted'], admitted)
            self.assertEqual(report['reserveBytes'], 4 * gib)
            self.assertEqual(report['workers'], 4)

    def test_invalid_counts_allowances_and_observations_fail_closed(self):
        for workers in (0, -1, True, 4.0):
            with self.subTest(workers=workers), self.assertRaises(ValueError):
                self.plan(workers=workers)
        for amount in (-1, True, float('nan'), 1.5):
            with self.subTest(evidence_bytes=amount), self.assertRaises(ValueError):
                self.plan(evidence_bytes=amount)
        for amount in (-1, True, float('nan'), 110.0):
            with self.subTest(available=amount), patch.object(admission, 'available_bytes', return_value=amount):
                with self.assertRaises(ValueError):
                    self.plan()

    def test_observation_failure_and_missing_directory_do_not_admit(self):
        with patch.object(admission, 'available_bytes', side_effect=OSError('unavailable')):
            with self.assertRaises(OSError):
                self.plan()
        with self.assertRaises(FileNotFoundError):
            admission.plan_admission(self.root / 'missing', self.evidence, self.limits, 4)
        with self.assertRaises(NotADirectoryError):
            file = self.root / 'not-a-directory'
            file.write_text('keep')
            admission.plan_admission(file, self.evidence, self.limits, 4)

    def test_observation_preserves_files_and_never_grants_completion_or_kill_credit(self):
        retained = self.evidence / 'raw-log'
        retained.write_text('partial mutation evidence')
        with patch.object(admission, 'available_bytes', return_value=110):
            report = self.plan()
        self.assertEqual(retained.read_text(), 'partial mutation evidence')
        self.assertEqual(list(self.evidence.iterdir()), [retained])
        for key in ('complete', 'gatePassed', 'score', 'killed', 'profilePromoted'):
            self.assertNotIn(key, report)
        self.assertTrue(report['observationOnly'])

    def test_cli_rejects_unsafe_admission_without_starting_workers(self):
        result = subprocess.run([sys.executable, str(Path(admission.__file__)),
                                 '--scratch', str(self.scratch), '--evidence', str(self.evidence),
                                 '--workers', '4', '--max-cache-gib', '1000000'],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(result.stdout)['admitted'])
        self.assertEqual(list(self.scratch.iterdir()), [])
        self.assertEqual(list(self.evidence.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
