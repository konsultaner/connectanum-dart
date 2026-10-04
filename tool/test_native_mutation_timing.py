#!/usr/bin/env python3
"""Timing estimates never grant completion or mutation credit."""

import copy
import unittest

import native_mutation_timing as timing


class TimingTests(unittest.TestCase):
    def sample(self):
        mutants = [{'file': 'core/src/first.rs', 'name': 'first'},
                   {'file': 'core/src/second.rs', 'name': 'second'}]
        outcomes = [{'scenario': 'Baseline', 'phase_results': [
            {'phase': 'Build', 'duration': 4}, {'phase': 'Test', 'duration': 6}]}]
        outcomes += [{'scenario': {'Mutant': mutant}, 'phase_results': [
            {'phase': 'Build', 'duration': 2}, {'phase': 'Test', 'duration': 8}]}
                     for mutant in mutants]
        return mutants, copy.deepcopy([{'elapsedSeconds': 35, 'outcomes': outcomes,
                                        'restoredSeconds': 5}])

    def test_phase_breakdown_and_extrapolation_are_not_a_score(self):
        full, runs = self.sample()
        full += [{'file': 'core/src/unmeasured.rs', 'name': f'other {index}'}
                 for index in range(8)]
        report = timing.summarize(full, runs, elapsed=40, jobs=2, full_batches=2)
        self.assertEqual(report['sampledMutants'], 2)
        self.assertEqual(report['mutationBuildSeconds'], 4)
        self.assertEqual(report['mutationTestSeconds'], 16)
        self.assertEqual(report['baselineSeconds'], 10)
        self.assertEqual(report['restoredSeconds'], 5)
        self.assertEqual(report['unmeasuredFiles'], ['core/src/unmeasured.rs'])
        self.assertEqual(report['estimatedFullSerialWorkSeconds'], 130)
        self.assertAlmostEqual(report['effectiveParallelism'], 35 / 40)
        self.assertAlmostEqual(report['estimatedFullWallSeconds'], 130 * 40 / 35)
        self.assertFalse(report['wholeComponentComplete'])
        self.assertTrue(report['timingOnly'])
        for field in ('score', 'adjustedCandidateScore', 'gatePassed'):
            self.assertNotIn(field, report)

    def test_missing_invalid_or_impossible_durations_fail_closed(self):
        for value in (None, -1, True, float('inf'), float('nan'), '10'):
            full, runs = self.sample()
            runs[0]['outcomes'][1]['phase_results'][0]['duration'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                timing.summarize(full, runs, elapsed=40, jobs=2, full_batches=2)
        full, runs = self.sample()
        runs[0]['elapsedSeconds'] = 2
        with self.assertRaises(ValueError):
            timing.summarize(full, runs, elapsed=40, jobs=2, full_batches=2)

    def test_duplicates_empty_samples_and_unknown_mutants_are_rejected(self):
        for kind in ('duplicate', 'empty', 'unknown', 'missing-baseline'):
            full, runs = self.sample()
            if kind == 'duplicate':
                runs.append(copy.deepcopy(runs[0]))
            elif kind == 'empty':
                runs = []
            elif kind == 'unknown':
                runs[0]['outcomes'][1]['scenario']['Mutant']['name'] = 'unknown'
            else:
                runs[0]['outcomes'].pop(0)
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                timing.summarize(full, runs, elapsed=40, jobs=2, full_batches=2)

    def test_more_workers_do_not_create_impossible_linear_speedup(self):
        full, runs = self.sample()
        report = timing.summarize(full, runs, elapsed=40, jobs=32, full_batches=2)
        self.assertAlmostEqual(report['effectiveParallelism'], .875)
        self.assertEqual(report['configuredWorkers'], 32)

    def test_projected_batch_count_also_bounds_parallelism(self):
        full, runs = self.sample()
        second = copy.deepcopy(runs[0])
        for outcome in second['outcomes'][1:]:
            mutant = outcome['scenario']['Mutant']
            mutant['name'] += ' other'
            full.append(mutant)
        report = timing.summarize(full, [*runs, second], elapsed=20, jobs=4, full_batches=1)
        self.assertEqual(report['effectiveParallelism'], 1)
        self.assertEqual(report['estimatedFullWallSeconds'], 55)


if __name__ == '__main__':
    unittest.main()
