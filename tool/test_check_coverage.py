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


if __name__ == '__main__':
    unittest.main()
