#!/usr/bin/env python3
"""Whole-inventory guarantees for resumable native mutation collection."""

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import native_coverage
import native_mutation_batches as batches
import native_mutations
import run_native_mutations as collector
from test_native_mutations import SCOPE, assertion, log, outcome


def inventory(size=7):
    return [{'name': f'mutant {index}', 'file': 'ct_core/src/lib.rs',
             'genre': 'FnValue', 'replacement': str(index),
             'span': {'start': {'line': index + 1, 'column': 1},
                      'end': {'line': index + 1, 'column': 2}}}
            for index in range(size)]


class BatchSelectionTests(unittest.TestCase):
    def test_batches_are_deterministic_disjoint_and_exhaustive(self):
        candidates = inventory()
        selected = [collector.select_batch(candidates, index, 3) for index in range(3)]
        self.assertEqual([len(batch) for batch in selected], [3, 2, 2])
        identities = [native_mutations.identity(item) for batch in selected for item in batch]
        self.assertEqual(len(identities), len(set(identities)))
        self.assertEqual(set(identities), set(map(native_mutations.identity, candidates)))
        for index in range(3):
            self.assertEqual(collector.select_batch(list(reversed(candidates)), index, 3),
                             selected[index])

    def test_invalid_and_empty_batches_fail_closed(self):
        for index, count in [(-1, 3), (3, 3), (0, 0), (0, 8), (True, 3), (0, 1.5)]:
            with self.subTest(index=index, count=count), self.assertRaises(ValueError):
                collector.select_batch(inventory(), index, count)
        with self.assertRaises(ValueError):
            collector.select_batch([], 0, 1)

    def test_duplicate_names_or_identities_are_rejected(self):
        candidates = inventory()
        for duplicate in [copy.deepcopy(candidates[0]),
                          {**candidates[1], 'name': candidates[0]['name']}]:
            with self.subTest(duplicate=duplicate), self.assertRaises(ValueError):
                collector.select_batch([*candidates, duplicate], 0, 2)

    def test_cli_requires_clean_evidence_and_95_percent_without_overwriting(self):
        for clean, score, expected in [(True, 95, 0), (True, 94.99, 1),
                                        (False, 100, 1), (False, None, 1)]:
            with self.subTest(clean=clean, score=score), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary) / 'report.json'
                report = {'generated': 1, 'counts': {}, 'evidenceClean': clean,
                          'adjustedCandidateScore': score}
                argv = ['audit', '--analyzer', 'analyzer', '--output', str(output), 'batch']
                with patch('sys.argv', argv), patch.object(batches, 'audit_batches', return_value=report):
                    self.assertEqual(batches.main(), expected)
                    self.assertEqual(json.loads(output.read_text()), report)
                    with self.assertRaises(FileExistsError):
                        batches.main()

    def test_merge_rejects_missing_duplicate_and_changed_results(self):
        full = inventory()
        reports = [{'batch': {'index': index, 'count': 3}, 'host': 'fixture',
                    'baselineTests': ['test'], 'results': [
                        {'mutant': mutant, 'status': 'killed'}
                        for mutant in collector.select_batch(full, index, 3)]}
                   for index in range(3)]
        report = batches.combine_batches(list(reversed(reports)), full)
        self.assertEqual(report['counts'], {'killed': 7})
        self.assertEqual(report['adjustedCandidateScore'], 100)
        changed = copy.deepcopy(reports)
        changed[1]['results'][0]['status'] = 'timeout'
        report = batches.combine_batches(changed, full)
        self.assertFalse(report['evidenceClean'])
        self.assertAlmostEqual(report['adjustedCandidateScore'], 600 / 7)
        for candidate in (reports[:2], [reports[0], reports[0], reports[2]]):
            with self.assertRaises(ValueError):
                batches.combine_batches(candidate, full)
        for field, value in [('baselineTests', ['other']), ('host', 'other')]:
            changed = copy.deepcopy(reports)
            changed[1][field] = value
            with self.assertRaises(ValueError):
                batches.combine_batches(changed, full)
        changed = copy.deepcopy(reports)
        changed[1]['results'].pop()
        with self.assertRaises(ValueError):
            batches.combine_batches(changed, full)


class BatchEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.scope = copy.deepcopy(SCOPE)
        source = self.root / 'native/transport/core/src/lib.rs'
        source.parent.mkdir(parents=True)
        source.write_text('fixture source\n' * 80)
        self.scope['inputHashes'] = {str(source.relative_to(self.root)): native_coverage.digest(source)}
        inputs = dict(self.scope['inputHashes'])
        for name in collector.FIXTURES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('public fixture')
            inputs[name] = native_coverage.digest(path)
        tools = {name: native_coverage.digest(Path(collector.__file__).parent / name)
                 for name in collector.TOOL_INPUTS}
        self.directories = []
        full = [{**item, 'file': 'core/src/lib.rs'} for item in inventory(4)]
        for index in range(2):
            directory = self.root / f'batch-{index}'
            self.directories.append(directory)
            run = directory / 'mutants.out'
            (run / 'logs').mkdir(parents=True)
            selected = collector.select_batch(full, index, 2)
            self.write(directory / 'source-scopes.json', self.scope)
            self.write(directory / 'raw-inventory.json', full)
            self.write(directory / 'inventory-partition.json', collector.partition_inventory(full, self.scope))
            self.write(directory / 'filtered-inventory.json', full)
            self.write(directory / 'batch-inventory.json', selected)
            self.write(run / 'mutants.json', selected)
            outcomes = [outcome()]
            (run / 'logs/baseline.log').write_text(log())
            for number, mutant in enumerate(selected):
                item = outcome({'Failure': 101}, {'Mutant': mutant})
                item.update(summary='CaughtMutant', log_path=f'logs/mutant-{number}.log')
                (run / item['log_path']).write_text(log([('tests::expected', assertion())]))
                outcomes.append(item)
            self.write(run / 'outcomes.json', {
                'cargo_mutants_version': '27.1.0', 'end_time': 'finished',
                'total_mutants': len(selected), 'outcomes': outcomes})
            (directory / 'restored-baseline.log').write_text(log())
            manifest = {'complete': True, 'scope': 'core-all',
                        'cargoMutantsVersion': 'cargo-mutants 27.1.0',
                        'restoredExitCode': 0, 'campaignExitCode': 0,
                        'inputHashes': inputs, 'toolHashes': tools,
                        'batch': {'index': index, 'count': 2}}
            for key, name in [('rawInventorySha256', 'raw-inventory.json'),
                              ('partitionSha256', 'inventory-partition.json'),
                              ('filteredInventorySha256', 'filtered-inventory.json'),
                              ('batchInventorySha256', 'batch-inventory.json')]:
                manifest[key] = native_coverage.digest(directory / name)
            self.write(directory / 'run-manifest.json', manifest)
            report = native_mutations.audit(run, self.scope)
            report.update(batch=manifest['batch'], wholeComponentComplete=False,
                          scopeSha256=native_coverage.digest(directory / 'source-scopes.json'),
                          toolHashes=tools,
                          restoredBaselineLogSha256=native_coverage.digest(directory / 'restored-baseline.log'))
            self.write(directory / 'audited-results.json', report)

    @staticmethod
    def write(path, value):
        path.write_text(json.dumps(value))

    def audit(self, directories=None):
        with patch.object(native_coverage, 'snapshot', return_value=self.scope):
            return batches.audit_batches(self.root, directories or self.directories, Path('analyzer'))

    def test_raw_logs_are_reaudited_and_all_batches_required(self):
        report = self.audit()
        self.assertEqual(report['generated'], 4)
        self.assertEqual(report['counts'], {'killed': 4})
        self.assertTrue(report['evidenceClean'])
        with self.assertRaises(ValueError):
            self.audit(self.directories[:1])
        with self.assertRaises(ValueError):
            self.audit([self.directories[0]] * 2)
        path = self.directories[1] / 'mutants.out/logs/mutant-0.log'
        path.write_text(path.read_text() + '\nNo space left on device\n')
        with self.assertRaisesRegex(ValueError, 'retained evidence'):
            self.audit()

    def test_changed_snapshot_or_incomplete_batch_rejected(self):
        path = self.directories[1] / 'run-manifest.json'
        original = json.loads(path.read_text())
        for key, value in [('complete', False), ('campaignExitCode', None),
                           ('restoredExitCode', 1), ('inputHashes', {}), ('toolHashes', {})]:
            with self.subTest(key=key):
                self.write(path, {**original, key: value})
                with self.assertRaises(ValueError):
                    self.audit()
        self.write(path, original)
        source = self.root / next(iter(self.scope['inputHashes']))
        source.write_text('changed source')
        with self.assertRaisesRegex(ValueError, 'snapshot input changed'):
            self.audit()

    def test_changed_inventory_or_restored_baseline_rejected(self):
        directory = self.directories[1]
        path = directory / 'filtered-inventory.json'
        original = path.read_text()
        path.write_text('[]')
        with self.assertRaisesRegex(ValueError, 'inventory evidence changed'):
            self.audit()
        path.write_text(original)
        (directory / 'restored-baseline.log').write_text(log(names=['other_test']))
        with self.assertRaisesRegex(ValueError, 'restored baseline'):
            self.audit()

    def test_added_source_during_audit_is_not_hidden_by_existing_file_hashes(self):
        changed = {**self.scope, 'newSource': 'added'}
        with patch.object(native_coverage, 'snapshot', side_effect=[self.scope, changed]):
            with self.assertRaisesRegex(ValueError, 'inventory changed during'):
                batches.audit_batches(self.root, self.directories, Path('analyzer'))


class RealBatchTests(unittest.TestCase):
    def test_real_collector_batches_merge_without_reducing_test_inventory(self):
        analyzer = native_coverage.REPO / 'out/rust-coverage-scope-target/debug/connectanum-coverage-scope'
        subprocess.run(['cargo', 'build', '--quiet', '--locked', '--manifest-path',
                        str(native_coverage.REPO / 'tool/rust_coverage_scope/Cargo.toml'),
                        '--target-dir', str(analyzer.parent.parent)],
                       check=True, capture_output=True, timeout=120)
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / 'repo'
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
                (crate / 'src/lib.rs').write_text(
                    'pub fn enabled() -> bool {\n    true\n}\n'
                    'pub fn other() -> bool {\n    true\n}\n'
                    '#[cfg(test)]\nmod tests {\n'
                    '    #[test]\n    fn behavior() {\n'
                    '        assert!(super::enabled());\n'
                    '        assert!(super::other());\n    }\n}\n')
            for name in collector.FIXTURES:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('public fixture')
            subprocess.run(['cargo', 'generate-lockfile', '--offline'], cwd=workspace,
                           check=True, capture_output=True, timeout=30)
            directories = [base / f'batch-{index}' for index in range(2)]
            for index, directory in enumerate(directories):
                self.assertEqual(collector.collect(root, directory, analyzer, 'core-all',
                                                   batch=(index, 2)), 0)
                report = json.loads((directory / 'audited-results.json').read_text())
                self.assertFalse(report['wholeComponentComplete'])
                self.assertEqual(report['baselineTests'], ['tests::behavior', 'tests::behavior'])
            report = batches.audit_batches(root, directories, analyzer)
            self.assertEqual(report['generated'], 2)
            self.assertEqual(report['counts'], {'killed': 2})
            self.assertTrue(report['evidenceClean'])
            self.assertEqual(report['adjustedCandidateScore'], 100)


if __name__ == '__main__':
    unittest.main()
