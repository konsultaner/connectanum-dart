from pathlib import Path
import json
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
from check_coverage import findings, read_lcov, report


class CoverageTests(unittest.TestCase):
    def test_vm_benchmark_and_oauth_token_floors_protect_98_percent(self):
        policy = json.loads((Path(__file__).parent / 'coverage_policy.json').read_text())
        token_source = 'packages/connectanum_client/lib/src/mcp/oauth_token_exchange.dart'
        bench_source = 'packages/connectanum_bench/lib/src/benchmark_runner.dart'
        self.assertGreaterEqual(policy['packages']['connectanum_bench'], 98)
        self.assertGreaterEqual(policy['files'].get(token_source, 0), 98)
        self.assertIn(token_source, policy['requiredSources'])
        focused_policy = {
            'target': policy['target'],
            'packages': {'connectanum_bench': policy['packages']['connectanum_bench']},
            'files': {token_source: policy['files'][token_source]},
        }
        with tempfile.TemporaryDirectory() as directory:
            sources = {name: {line: int(line <= 98) for line in range(1, 101)}
                       for name in (token_source, bench_source)}
            self.assertEqual(findings(report(sources, Path(directory)), focused_policy), [])
            for source in sources:
                with self.subTest(source=source):
                    sources[source][98] = 0
                    result = findings(report(sources, Path(directory)), focused_policy)
                    label = token_source if source == token_source else 'connectanum_bench'
                    self.assertIn(f'{label}: 97.000% below 98%', result)
                    sources[source][98] = 1

    def test_browser_policy_gates_both_measured_packages(self):
        policy = json.loads((Path(__file__).parent / 'browser_coverage_policy.json').read_text())
        self.assertEqual(policy['target'], 98)
        for package in ('connectanum_core', 'connectanum_client'):
            with self.subTest(package=package):
                self.assertIn(package, policy['packages'])
                self.assertGreaterEqual(policy['packages'][package], 96)
                with tempfile.TemporaryDirectory() as directory:
                    result = report({}, Path(directory), runtime='chrome')
                    self.assertIn(f'{package}: no executable coverage data', findings(result, policy))

    def test_browser_client_regression_fails_even_with_perfect_core(self):
        policy = json.loads((Path(__file__).parent / 'browser_coverage_policy.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            result = report({
                'packages/connectanum_core/lib/core.dart': {1: 1},
                'packages/connectanum_client/lib/client.dart': {
                    line: int(line <= 9629) for line in range(1, 10001)
                },
            }, Path(directory), runtime='chrome')
            package_policy = {'target': policy['target'], 'packages': policy['packages']}
            self.assertEqual(findings(result, package_policy), [])
            result['packages']['connectanum_client']['covered'] -= 1
            result['packages']['connectanum_client']['percent'] = 96.28
            self.assertIn('connectanum_client: 96.280% below 96.29%',
                          findings(result, package_policy))
            self.assertIn('connectanum_client: 96.280% below 98%',
                          findings(result, package_policy, require_target=True))

    def test_decimal_threshold_equality_and_one_line_regression(self):
        source = 'packages/core/lib/core.dart'
        policy = {'target': 96.29, 'packages': {'core': 96.29},
                  'files': {source: 96.29},
                  'components': {'library': {'floor': 96.29, 'sources': [source]}}}
        with tempfile.TemporaryDirectory() as directory:
            for covered in (9629, 9628):
                result = report({source: {line: int(line <= covered)
                                         for line in range(1, 10001)}}, Path(directory))
                result['unmeasuredScopes'] = []
                expected = ([] if covered == 9629 else [
                    f'{name}: 96.280% below 96.29%' for name in ('core', source, 'library')])
                for target in (False, True):
                    with self.subTest(covered=covered, target=target):
                        self.assertEqual(findings(result, policy, require_target=target), expected)

    def test_application_scope_is_separate_and_cannot_include_tests_or_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'app.info'
            accepted = {
                'examples/wamp_app/shared/lib/protocol.dart',
                'examples/wamp_app/server/bin/server.dart',
                'examples/wamp_app/client/lib/main.dart',
            }
            rejected = [
                'examples/wamp_app/shared/test/protocol_test.dart',
                'examples/wamp_app/shared/lib/../test/fake.dart',
                'examples/wamp_app/shared/lib//fake.dart',
                'examples/wamp_app/shared/lib/./fake.dart',
                'examples/wamp_app/unrecognized/lib/main.dart',
                'examples/unrelated/shared/lib/main.dart',
                'packages/core/lib/main.dart',
            ]
            path.write_text(''.join(f'SF:{source}\nDA:1,1\nDA:2,0\nend_of_record\n'
                                    for source in sorted(accepted) + rejected)
                            + 'SF:C:\\repo\\examples\\wamp_app\\shared\\lib\\protocol.dart\nDA:2,1\n'
                            + 'end_of_record\nSF:/repo/examples/wamp_app/client/lib/main.dart\nDA:3,0\n')
            sources = read_lcov([path], scope='application')
            self.assertEqual(set(sources), accepted)
            result = report(sources, root, scope='application')
            self.assertEqual(result['overall'], {'covered': 4, 'total': 7, 'percent': 400 / 7})
            self.assertEqual(result['packages']['shared']['percent'], 100)
            self.assertEqual(result['packages']['server']['percent'], 50)
            self.assertEqual(result['packages']['client']['percent'], 100 / 3)
            self.assertIn('package libraries', result['unmeasuredScopes'])
            self.assertIn('browser-only code', result['unmeasuredScopes'])
            self.assertEqual(set(read_lcov([path])), {'packages/core/lib/main.dart'})

    def test_application_inventory_retains_unmeasured_components_and_required_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('shared/lib/api.dart', 'shared/lib/missing.dart',
                         'server/bin/main.dart', 'client/lib/main.dart',
                         'shared/test/api_test.dart'):
                path = root / 'examples/wamp_app' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            source = 'examples/wamp_app/shared/lib/api.dart'
            result = report({source: {1: 1}}, root, scope='application')
            self.assertEqual(result['unmeasuredSources'], [
                'examples/wamp_app/client/lib/main.dart',
                'examples/wamp_app/server/bin/main.dart',
                'examples/wamp_app/shared/lib/missing.dart'])
            policy = {'target': 98, 'sourceScope': 'application', 'packages': {'shared': 98},
                      'requiredSources': [source, 'examples/wamp_app/shared/lib/missing.dart']}
            self.assertEqual(findings(result, policy), [
                'examples/wamp_app/shared/lib/missing.dart: previously measured source missing from coverage'])
            self.assertIn('shared: no executable coverage data',
                          findings(report({}, root, scope='application'), policy))
            policy['requiredSources'] = [source]
            policy['componentPackages'] = ['shared']
            self.assertIn(f'{source}: expected exactly one component, found 0', findings(result, policy))
            policy['components'] = {'api': {'floor': 98, 'sources': [source]}}
            self.assertEqual(findings(result, policy), [])

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

    def test_packaging_scope_is_separate_and_rejects_test_path_inflation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mixed.info'
            path.write_text(''.join(f'SF:{name}\nDA:1,1\nDA:2,0\nend_of_record\n' for name in [
                'packages/core/lib/a.dart', 'packages/core/hook/build.dart',
                'packages/core/bin/main.dart', 'packages/core/tool/install.dart',
                'packages/core/test/hook/build_test.dart',
                'packages/core/test/lib/unit_test.dart',
                'packages/core/hook/../test/unit_test.dart',
                'packages/core/lib/../test/unit_test.dart',
                'examples/app/bin/main.dart']))
            library = read_lcov([path])
            packaging = read_lcov([path], scope='packaging')
            self.assertEqual(list(library), ['packages/core/lib/a.dart'])
            self.assertEqual(set(packaging), {
                'packages/core/hook/build.dart', 'packages/core/bin/main.dart',
                'packages/core/tool/install.dart'})
            self.assertEqual(report(packaging, Path(directory), scope='packaging')['overall'],
                             {'covered': 3, 'total': 6, 'percent': 50})

    def test_packaging_inventory_and_floors_fail_closed_for_omitted_entry_points(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for source in ('hook/build.dart', 'tool/install.dart', 'bin/main.dart',
                           'lib/api.dart', 'test/hook_test.dart'):
                path = root / 'packages/core' / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            result = report({'packages/core/hook/build.dart': {1: 1}}, root, scope='packaging')
            self.assertEqual(result['sourceScope'], 'packaging')
            self.assertEqual(result['unmeasuredSources'], [
                'packages/core/bin/main.dart', 'packages/core/tool/install.dart'])
            policy = {'target': 98, 'sourceScope': 'packaging', 'files': {
                'packages/core/hook/build.dart': 98, 'packages/core/tool/install.dart': 98}}
            self.assertEqual(findings(result, policy), [
                'packages/core/tool/install.dart: no executable coverage data'])
            self.assertTrue(any('Unmeasured runtimes/scopes' in p for p in
                                findings(result, policy, require_target=True)))
            policy['sourceScope'] = 'library'
            self.assertIn('Coverage source scope packaging does not match policy library',
                          findings(result, policy))

    def test_windows_packaging_source_normalization_matches_unix(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'windows.info'
            path.write_text('SF:C:\\repo\\packages\\core\\hook\\build.dart\nDA:1,1\n'
                            'end_of_record\nSF:/tmp/repo/packages/core/hook/build.dart\nDA:2,0\n')
            self.assertEqual(read_lcov([path], scope='packaging'), {
                'packages/core/hook/build.dart': {1: 1, 2: 0}})

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
