from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
from check_coverage import findings, read_lcov, report


class CoverageTests(unittest.TestCase):
    def test_duplicate_records_and_reports_union_lines_and_hits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b = root / 'a.info', root / 'b.info'
            a.write_text('SF:/runner/work/repo/packages/core/lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n')
            b.write_text('SF:packages/core/lib/a.dart\nDA:1,0\nDA:2,1\nDA:3,0\nend_of_record\n')
            unmeasured = root / 'packages/core/lib/missing.dart'
            unmeasured.parent.mkdir(parents=True)
            unmeasured.touch()
            result = report(read_lcov([a, b]), root)
            self.assertEqual(result['overall']['covered'], 2)
            self.assertEqual(result['overall']['total'], 3)
            self.assertEqual(result['files']['packages/core/lib/a.dart']['uncovered'], [3])
            self.assertEqual(result['unmeasuredSources'], ['packages/core/lib/missing.dart'])

    def test_no_data_cannot_pass_and_rounding_cannot_hide_regression(self):
        policy = {'target': 98, 'packages': {'core': 98}, 'files': {}}
        with tempfile.TemporaryDirectory() as directory:
            result = report({}, Path(directory))
            self.assertTrue(findings(result, policy))
            result = report({'packages/core/lib/a.dart': {n: int(n < 97999) for n in range(100000)}}, Path(directory))
            self.assertTrue(findings(result, policy))
            policy['packages']['core'] = 97
            self.assertFalse(findings(result, policy))
            self.assertTrue(findings(result, policy, require_target=True))

    def test_negative_or_invalid_line_counts_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.info'
            for record in ['DA:1,-1', 'DA:0,1', 'DA:hello,1']:
                path.write_text('SF:packages/core/lib/a.dart\n' + record + '\n')
                with self.assertRaises(ValueError):
                    read_lcov([path])

    def test_missing_file_cannot_improve_package_percentage(self):
        policy = {'target': 98, 'packages': {'core': 90},
                  'requiredSources': ['packages/core/lib/easy.dart',
                                      'packages/core/lib/difficult.dart']}
        with tempfile.TemporaryDirectory() as directory:
            result = report({'packages/core/lib/easy.dart': {1: 1}}, Path(directory))
            self.assertEqual(result['packages']['core']['percent'], 100)
            self.assertEqual(findings(result, policy), [
                'packages/core/lib/difficult.dart: previously measured source missing from coverage'])

    def test_test_and_executable_sources_cannot_inflate_library_measurement(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mixed.info'
            path.write_text(''.join(f'SF:{name}\nDA:1,1\nend_of_record\n' for name in [
                'packages/core/test/a_test.dart', 'packages/core/bin/main.dart',
                'native/core/lib.rs', 'packages/core/lib/a.dart']))
            self.assertEqual(read_lcov([path]), {'packages/core/lib/a.dart': {1: 1}})

    def test_strict_target_reports_unmeasured_scopes_and_unlisted_files(self):
        with tempfile.TemporaryDirectory() as directory:
            result = report({'packages/core/lib/a.dart': {1: 0}}, Path(directory))
            problems = findings(result, {'target': 98}, require_target=True)
            self.assertIn('packages/core/lib/a.dart: 0.000% below 98%', problems)
            self.assertTrue(any('Unmeasured runtimes/scopes' in item for item in problems))

    def test_component_floors_preserve_existing_scope_without_hiding_new_lines(self):
        policy = {'target': 98, 'components': {
            'library': {'floor': 98, 'sources': ['packages/core/lib/api.dart']},
            'cli': {'floor': 10, 'sources': ['packages/core/lib/cli.dart']},
        }}
        with tempfile.TemporaryDirectory() as directory:
            result = report({
                'packages/core/lib/api.dart': {n: int(n < 98) for n in range(100)},
                'packages/core/lib/cli.dart': {n: int(n < 10) for n in range(100)},
            }, Path(directory))
            self.assertEqual(result['packages']['core']['percent'], 54)
            self.assertEqual(result['overall']['total'], 200)
            self.assertEqual(findings(result, policy), [])
            result['files']['packages/core/lib/api.dart']['covered'] = 97
            self.assertIn('library: 97.000% below 98%', findings(result, policy))
            self.assertIn('cli: 10.000% below 98%', findings(result, policy, require_target=True))

    def test_component_missing_source_cannot_be_hidden_by_covered_neighbor(self):
        policy = {'target': 98, 'components': {
            'library': {'floor': 98, 'sources': [
                'packages/core/lib/a.dart', 'packages/core/lib/b.dart']},
        }}
        with tempfile.TemporaryDirectory() as directory:
            result = report({'packages/core/lib/a.dart': {1: 1}}, Path(directory))
            self.assertIn('library: missing executable coverage for packages/core/lib/b.dart',
                          findings(result, policy))
            self.assertIn('library: no executable coverage data',
                          findings(report({}, Path(directory)), policy))

    def test_invalid_component_scope_or_floor_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            result = report({}, Path(directory))
            for definition in [
                {'floor': 98, 'sources': []},
                {'floor': 98, 'sources': ['a', 'a']},
                {'floor': -1, 'sources': ['a']},
                {'floor': 101, 'sources': ['a']},
                {'floor': float('nan'), 'sources': ['a']},
                {'floor': '98', 'sources': ['a']},
            ]:
                with self.subTest(definition=definition), self.assertRaises(ValueError):
                    findings(result, {'target': 98, 'components': {'bad': definition}})

    def test_component_partition_cannot_drop_new_or_existing_production_sources(self):
        policy = {'target': 98, 'componentPackages': ['core'], 'components': {
            'library': {'floor': 98, 'sources': ['packages/core/lib/api.dart']},
        }}
        with tempfile.TemporaryDirectory() as directory:
            result = report({
                'packages/core/lib/api.dart': {1: 1},
                'packages/core/lib/new_cli.dart': {1: 0},
            }, Path(directory))
            self.assertIn('packages/core/lib/new_cli.dart: expected exactly one component, found 0',
                          findings(result, policy))
            policy['components']['cli'] = {
                'floor': 0, 'sources': ['packages/core/lib/new_cli.dart']}
            self.assertEqual(findings(result, policy), [])
            policy['components']['duplicate'] = policy['components']['cli']
            self.assertIn('packages/core/lib/new_cli.dart: expected exactly one component, found 2',
                          findings(result, policy))
            self.assertEqual(result['overall'], {'covered': 1, 'total': 2, 'percent': 50})

    def test_required_component_package_needs_measurement(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertIn('core: no executable coverage data', findings(
                report({}, Path(directory)), {'target': 98, 'componentPackages': ['core']}))


if __name__ == '__main__':
    unittest.main()
