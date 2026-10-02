#!/usr/bin/env python3
"""Adversarial and real-libtest checks for native mutation evidence."""

import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import native_mutations as audit
import native_coverage
import run_native_mutations as collector


SCOPE = {
    'host': {'system': 'fixture', 'machine': 'fixture'},
    'sources': {'native/transport/core/src/lib.rs': {
        'classification': 'production-candidate', 'lineCount': 80,
        'excludedLines': list(range(40, 81)),
    }},
}
MUTANT = {'file': 'core/src/lib.rs', 'name': 'replace == with !=',
          'genre': 'BinaryOperator', 'replacement': '!=',
          'span': {'start': {'line': 4, 'column': 1}, 'end': {'line': 4, 'column': 3}}}


def outcome(status='Success', scenario='Baseline'):
    return {'scenario': scenario, 'summary': 'Success', 'log_path': 'logs/baseline.log',
            'phase_results': [{'phase': 'Build', 'process_status': 'Success'},
                              {'phase': 'Test', 'process_status': status}]}


def log(failures=(), names=None):
    names = names or ['tests::expected']
    result = f'running {len(names)} tests\n'
    for name in names:
        result += f'test {name} ... {"FAILED" if name in dict(failures) else "ok"}\n'
    if failures:
        result += '\nfailures:\n\n'
        for name, body in failures:
            result += f'---- {name} stdout ----\n{body}\n'
        result += 'failures:\n' + ''.join(f'    {name}\n' for name, _ in failures)
    result += (f'\ntest result: {"FAILED" if failures else "ok"}. '
               f'{len(names) - len(failures)} passed; {len(failures)} failed; '
               '0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n')
    return result


def assertion(line=50, message='assertion `left == right` failed'):
    return f"thread 'tests::expected' (123) panicked at core/src/lib.rs:{line}:5:\n{message}\n"


class NativeMutationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        target = native_coverage.REPO / 'out/rust-coverage-scope-target'
        subprocess.run([
            'cargo', 'build', '--quiet', '--locked', '--manifest-path',
            str(native_coverage.REPO / 'tool/rust_coverage_scope/Cargo.toml'),
            '--target-dir', str(target),
        ], check=True)
        cls.analyzer = target / 'debug/connectanum-coverage-scope'

    def test_complete_success_and_explicit_test_assertion(self):
        self.assertEqual(audit.classify(outcome(), log(), SCOPE, None), 'survived')
        failed = log([('tests::expected', assertion())])
        self.assertEqual(audit.classify(outcome({'Failure': 101}), failed, SCOPE, MUTANT), 'killed')

    def test_multiple_explicit_assertions_are_parsed_as_separate_failures(self):
        names = ['tests::expected', 'tests::another_expected']
        failed = log([(name, assertion().replace("'tests::expected'", repr(name)))
                      for name in names], names)
        self.assertEqual([block[1] for block in audit.FAILURE.finditer(failed)], names)
        self.assertEqual(audit.classify(outcome({'Failure': 101}), failed, SCOPE, MUTANT), 'killed')

    def test_extra_failure_header_cannot_be_hidden_in_assertion_output(self):
        for name in ('tests::unreported', 'tests::expected'):
            with self.subTest(extra_header=name):
                body = assertion() + f'\n---- {name} stdout ----\n' + assertion()
                failed = log([('tests::expected', body)])
                self.assertEqual(audit.classify(outcome({'Failure': 101}), failed, SCOPE, MUTANT), 'error')

    def test_production_assertions_panics_and_unwraps_are_not_kills(self):
        for body in [assertion(10), assertion(message='boom'),
                     assertion(message='called `Result::unwrap()` on an `Err` value'),
                     assertion().replace('core/src/lib.rs', 'unknown.rs')]:
            with self.subTest(body=body):
                self.assertEqual(audit.classify(outcome({'Failure': 101}),
                    log([('tests::expected', body)]), SCOPE, MUTANT), 'error')

    def test_assertion_cannot_hide_another_runtime_failure(self):
        failed = log([('a', assertion()), ('b', assertion(message='boom'))], ['a', 'b'])
        self.assertEqual(audit.classify(outcome({'Failure': 101}), failed, SCOPE, MUTANT), 'error')

    def test_assertion_block_must_belong_to_the_failed_test(self):
        failed = log([('tests::expected', assertion())]).replace(
            '---- tests::expected stdout ----', '---- unrelated stdout ----')
        self.assertEqual(audit.classify(outcome({'Failure': 101}), failed, SCOPE, MUTANT), 'error')

    def test_signals_timeouts_and_crashes_override_assertions(self):
        failed = log([('tests::expected', assertion())])
        for status, suffix, expected in [
                ({'Signalled': 6}, '', 'error'), ('Timeout', '', 'timeout'),
                ({'Failure': 101}, '\nprocess failed (signal: 6, SIGABRT)\n', 'error'),
                ({'Failure': 101}, '\nfatal runtime error: stack overflow\n', 'error'),
                ({'Failure': 1}, '', 'error')]:
            with self.subTest(status=status, suffix=suffix):
                self.assertEqual(audit.classify(outcome(status), failed + suffix, SCOPE, MUTANT), expected)

    def test_empty_incomplete_skipped_and_inconsistent_suites_fail_closed(self):
        for text in [
                '', 'assertion failed: false',
                'running 0 tests\ntest result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;',
                log().replace('0 ignored', '1 ignored'),
                log().replace('0 measured', '1 measured'),
                log().replace('running 1 tests', 'running 2 tests'),
                log().replace('test tests::expected ... ok\n', ''),
                log().replace('test result: ok.', 'test result: FAILED.')]:
            with self.subTest(text=text):
                self.assertEqual(audit.classify(outcome(), text, SCOPE, None), 'error')

    def test_build_errors_and_build_timeouts_are_separate(self):
        failed = outcome()
        failed['phase_results'] = [{'phase': 'Build', 'process_status': {'Failure': 101}}]
        self.assertEqual(audit.classify(failed, 'error[E0308]: mismatched types', SCOPE, MUTANT), 'compileError')
        for text in ['failed to get dependency', 'linker failed',
                     'error[E0308]: mismatch\nfailed to run custom build']:
            self.assertEqual(audit.classify(failed, text, SCOPE, MUTANT), 'error')
        failed['phase_results'][0]['process_status'] = 'Timeout'
        self.assertEqual(audit.classify(failed, '', SCOPE, MUTANT), 'timeout')

    def test_cast_comparison_syntax_error_requires_mutated_source_location(self):
        failed = outcome()
        failed['phase_results'] = [{'phase': 'Build', 'process_status': {'Failure': 101}}]
        diagnostic = (
            'error: `<` is interpreted as a start of generic arguments for `u64`, not a comparison\n'
            '   --> core/src/lib.rs:4:8\n'
            '    |\n4 | if bytes.len() as u64 < max_body {\n'
        )
        self.assertEqual(audit.classify(failed, diagnostic, SCOPE, MUTANT), 'compileError')
        for text in [
                diagnostic.replace('core/src/lib.rs', 'dependency/src/lib.rs'),
                diagnostic.replace(':4:8', ':5:8'),
                diagnostic.replace('   --> core/src/lib.rs:4:8\n', ''),
                diagnostic.replace('error: `<`', 'warning: `<`'),
                diagnostic + 'failed to run custom build',
                diagnostic + 'No space left on device',
                diagnostic + 'signal: 9, SIGKILL']:
            with self.subTest(text=text):
                self.assertEqual(audit.classify(failed, text, SCOPE, MUTANT), 'error')
        self.assertEqual(audit.classify(failed, diagnostic, SCOPE, None), 'error')
        self.assertEqual(audit.classify(outcome({'Failure': 101}), diagnostic, SCOPE, MUTANT), 'error')
        failed['phase_results'][0]['process_status'] = 'Timeout'
        self.assertEqual(audit.classify(failed, diagnostic, SCOPE, MUTANT), 'timeout')

    def test_multiline_mutation_maps_test_locations_but_not_replacement_panics(self):
        mutant = copy.deepcopy(MUTANT)
        scope = copy.deepcopy(SCOPE)
        scope['sources']['native/transport/core/src/lib.rs']['excludedLines'] = [50]
        mutant['span']['end']['line'] = 24
        self.assertTrue(audit.test_assertion(assertion(30), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(4), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(10), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(29), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(31), scope, mutant))
        mutant['replacement'] = 'one\ntwo\nthree'
        self.assertTrue(audit.test_assertion(assertion(32), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(6), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(31), scope, mutant))
        self.assertFalse(audit.test_assertion(assertion(33), scope, mutant))

    def campaign(self, directory, status='killed'):
        (directory / 'logs').mkdir()
        (directory / 'logs/baseline.log').write_text(log())
        item = outcome({'Failure': 101} if status == 'killed' else 'Success', {'Mutant': MUTANT})
        item.update(summary='CaughtMutant' if status == 'killed' else 'MissedMutant', log_path='logs/mutant.log')
        (directory / 'logs/mutant.log').write_text(log([('tests::expected', assertion())]) if status == 'killed' else log())
        (directory / 'mutants.json').write_text(json.dumps([MUTANT]))
        run = {'cargo_mutants_version': '27.1.0', 'end_time': 'completed',
               'total_mutants': 1, 'outcomes': [outcome(), item]}
        (directory / 'outcomes.json').write_text(json.dumps(run))
        return run

    def test_complete_campaign_reports_hashes_raw_counts_and_operator_inventory(self):
        for status, score in [('killed', 100), ('survived', 0)]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.campaign(root, status)
                report = audit.audit(root, SCOPE)
                self.assertTrue(report['evidenceClean'])
                self.assertFalse(report['productionReadinessEstablished'])
                self.assertEqual(report['counts'], {status: 1})
                self.assertEqual(report['rawCandidateScore'], score)
                self.assertEqual(report['adjustedCandidateScore'], score)
                self.assertEqual(report['equivalents'], [])
                self.assertEqual(report['operators'], {'BinaryOperator': {status: 1}})
                self.assertEqual(len(report['results'][0]['logSha256']), 64)

    def test_mixed_failure_diagnostics_do_not_increase_mutation_scores(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.campaign(root)
            names = ['tests::expected', 'tests::runtime']
            (root / 'logs/baseline.log').write_text(log(names=names))
            (root / 'logs/mutant.log').write_text(log([
                ('tests::expected', assertion()),
                ('tests::runtime', assertion(10, 'attempt to subtract with overflow')),
            ], names))
            report = audit.audit(root, SCOPE)
            self.assertEqual(report['counts'], {'error': 1})
            self.assertEqual(report['rawCandidateScore'], 0)
            self.assertEqual(report['adjustedCandidateScore'], 0)
            self.assertFalse(report['evidenceClean'])
            self.assertEqual(report['results'][0]['failureEvidence'], {
                'diagnosticOnly': True,
                'crashDetected': False,
                'failures': [
                    {'test': 'tests::expected', 'kind': 'testAssertion'},
                    {'test': 'tests::runtime', 'kind': 'nonAssertion'},
                ],
            })

    def test_failure_diagnostics_require_unique_reported_test_and_test_source(self):
        for failed, expected in [
            (log([('tests::expected', assertion())]), ['testAssertion']),
            (log([('tests::expected', assertion(10))]), ['nonAssertion']),
            (log([('tests::expected', assertion(message='boom'))]), ['nonAssertion']),
            (log([('tests::expected', assertion())]).replace(
                '---- tests::expected stdout ----', '---- injected stdout ----'), ['unmatched']),
            (log([('tests::expected', assertion())]).replace(
                'test tests::expected ... FAILED', 'test tests::expected ... ok'), ['unmatched']),
            (log([('tests::expected', assertion() +
                  '\n---- tests::expected stdout ----\n' + assertion())]),
             ['unmatched', 'unmatched']),
        ]:
            with self.subTest(log=failed):
                evidence = audit.failure_evidence(failed, SCOPE, MUTANT)
                self.assertTrue(evidence['diagnosticOnly'])
                self.assertEqual([item['kind'] for item in evidence['failures']], expected)
        crashed = log([('tests::expected', assertion())]) + '\nSIGSEGV\n'
        self.assertTrue(audit.failure_evidence(crashed, SCOPE, MUTANT)['crashDetected'])
        self.assertEqual(audit.classify(outcome({'Failure': 101}), crashed, SCOPE, MUTANT), 'error')

    def test_corrupt_incomplete_duplicate_and_unbaselined_inventories_are_rejected(self):
        for change in [
                lambda run: run.update(end_time=None),
                lambda run: run.update(cargo_mutants_version='unknown'),
                lambda run: run.update(total_mutants=2),
                lambda run: run['outcomes'].pop(),
                lambda run: run['outcomes'].pop(0),
                lambda run: run['outcomes'].append(run['outcomes'][0]),
                lambda run: run['outcomes'].append(run['outcomes'][1]),
                lambda run: run['outcomes'][1]['scenario']['Mutant'].update(replacement='invented'),
                lambda run: run['outcomes'][1].update(summary='MissedMutant'),
                lambda run: run['outcomes'][0].update(summary='Failure'),
                lambda run: run['outcomes'][1].update(log_path='logs/baseline.log'),
        ]:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                run = self.campaign(root)
                change(run)
                (root / 'outcomes.json').write_text(json.dumps(run))
                with self.assertRaises(ValueError):
                    audit.audit(root, SCOPE)

    def test_failed_baseline_and_missing_or_changed_test_set_cannot_pass(self):
        for replacement in [log(names=['tests::different']), log(names=['extra', 'tests::expected'])]:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.campaign(root)
                (root / 'logs/baseline.log').write_text(replacement)
                report = audit.audit(root, SCOPE)
                self.assertFalse(report['evidenceClean'])
                self.assertEqual(report['counts'], {'error': 1})
                self.assertEqual(report['rawCandidateScore'], 0)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.campaign(root)
            (root / 'logs/baseline.log').write_text('')
            with self.assertRaises(ValueError):
                audit.audit(root, SCOPE)

    def test_generated_test_mutants_and_log_path_escapes_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run = self.campaign(root)
            scope = copy.deepcopy(SCOPE)
            scope['sources']['native/transport/' + MUTANT['file']]['excludedLines'].append(4)
            with self.assertRaises(ValueError):
                audit.audit(root, scope)
            for path in ['../outside.log', '/tmp/outside.log']:
                run['outcomes'][1]['log_path'] = path
                (root / 'outcomes.json').write_text(json.dumps(run))
                with self.assertRaises(ValueError):
                    audit.audit(root, SCOPE)
            (root / 'outside-link').symlink_to(root.parent)
            with self.assertRaises(ValueError):
                audit.read_log(root, 'outside-link/file')

    def test_whole_production_body_with_nested_test_lines_stays_in_inventory(self):
        mutant = copy.deepcopy(MUTANT)
        mutant.update(genre='FnValue', replacement='0',
                      span={'start': {'line': 2, 'column': 5},
                            'end': {'line': 4, 'column': 11}})
        scope = copy.deepcopy(SCOPE)
        source = scope['sources']['native/transport/' + mutant['file']]
        source['excludedLines'].append(3)
        source['productionFunctionBodies'] = [
            {'name': 'actual', 'span': {'start': [2, 4], 'end': [4, 10]}}]
        with tempfile.TemporaryDirectory() as temporary, patch(__name__ + '.MUTANT', mutant):
            root = Path(temporary)
            self.campaign(root, 'survived')
            report = audit.audit(root, scope)
            self.assertEqual(report['counts'], {'survived': 1})
            self.assertEqual(report['rawCandidateScore'], 0)
            self.assertEqual(report['generated'], 1)
            self.assertEqual(report['equivalents'], [])

    def test_nested_test_overlap_requires_exact_ast_production_body_and_fnvalue(self):
        valid = copy.deepcopy(MUTANT)
        valid.update(genre='FnValue', replacement='0',
                     span={'start': {'line': 2, 'column': 5},
                           'end': {'line': 4, 'column': 11}})
        for variant in ['operator', 'missing', 'empty', 'line', 'column', 'test-only', 'unknown']:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                mutant = copy.deepcopy(valid)
                scope = copy.deepcopy(SCOPE)
                source = scope['sources']['native/transport/' + mutant['file']]
                source['excludedLines'].append(3)
                source['productionFunctionBodies'] = [
                    {'name': 'actual', 'span': {'start': [2, 4], 'end': [4, 10]}}]
                if variant == 'operator':
                    mutant['genre'] = 'BinaryOperator'
                elif variant == 'missing':
                    source.pop('productionFunctionBodies')
                elif variant == 'empty':
                    source['productionFunctionBodies'] = []
                elif variant == 'line':
                    mutant['span']['start']['line'] = 1
                elif variant == 'column':
                    mutant['span']['start']['column'] = 4
                elif variant == 'test-only':
                    source['classification'] = 'test-only'
                else:
                    source['productionFunctionBodies'][0]['span']['end'] = [40, 10]
                with patch(__name__ + '.MUTANT', mutant):
                    root = Path(temporary)
                    self.campaign(root)
                    with self.assertRaises(ValueError):
                        audit.audit(root, scope)

    def test_real_function_replacement_spanning_debug_code_uses_assertions_not_crashes(self):
        source = '''pub fn identity(value: i32) -> i32 {
    let output = value;
    #[cfg(test)] { std::hint::black_box(value); }
    output
}
#[cfg(test)] mod tests {
    #[test] fn identity_is_not_a_constant() {
        assert_eq!(super::identity(24), 24);
    }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'src').mkdir()
            (root / 'src/lib.rs').write_text(source)
            (root / 'Cargo.toml').write_text(
                '[package]\nname="mixed_scope_fixture"\nversion="0.0.0"\n'
                'edition="2021"\n[workspace]\n')
            result = subprocess.run(
                ['cargo', 'mutants', '--no-config', '--jobs', '1', '--timeout', '10',
                 '--build-timeout', '30', '--output', str(root / 'evidence'),
                 '--', '--lib', '--', '--test-threads=1'], cwd=root,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout)
            scope = native_coverage.snapshot(root, {'fixture': 'src/lib.rs'}, self.analyzer)
            self.assertEqual(scope['sources']['src/lib.rs']['productionFunctionBodies'], [
                {'name': 'identity', 'span': {'start': [2, 4], 'end': [4, 10]}}])
            report = audit.audit(root / 'evidence/mutants.out', scope)
            self.assertTrue(report['evidenceClean'])
            self.assertGreater(report['generated'], 0)
            self.assertIn('FnValue', report['operators'])
            self.assertEqual(report['counts'], {'killed': report['generated']})
            self.assertEqual(report['equivalents'], [])

    def test_same_line_test_regions_do_not_admit_test_only_mutations(self):
        for genre in ['FnValue', 'BinaryOperator']:
            with self.subTest(genre=genre), tempfile.TemporaryDirectory() as temporary:
                mutant = copy.deepcopy(MUTANT)
                mutant.update(genre=genre, span={
                    'start': {'line': 4, 'column': 7},
                    'end': {'line': 4, 'column': 10}})
                scope = copy.deepcopy(SCOPE)
                source = scope['sources']['native/transport/' + mutant['file']]
                source['exclusions'] = [{'reason': 'nested test', 'span': {
                    'start': [4, 6], 'end': [4, 9]}}]
                source['mixedLines'] = [4]
                source['productionFunctionBodies'] = [{'name': 'outer', 'span': {
                    'start': [4, 0], 'end': [4, 20]}}]
                with patch(__name__ + '.MUTANT', mutant):
                    root = Path(temporary)
                    self.campaign(root)
                    with self.assertRaisesRegex(ValueError, 'test/helper-only'):
                        audit.audit(root, scope)

    def test_production_mutation_adjacent_to_same_line_test_region_is_retained(self):
        scope = copy.deepcopy(SCOPE)
        source = scope['sources']['native/transport/' + MUTANT['file']]
        source['mixedLines'] = [4]
        source['exclusions'] = [{'reason': 'nested test', 'span': {
            'start': [4, 2], 'end': [4, 9]}}]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.campaign(root, 'survived')
            report = audit.audit(root, scope)
            self.assertEqual(report['counts'], {'survived': 1})

    def test_real_rust_assertion_is_distinguished_from_production_panics(self):
        source = '''fn actual() -> i32 {
    match std::env::var("MUTATION_CASE").as_deref() {
        Ok("assert") => 2,
        Ok("panic") => panic!("production error"),
        Ok("unwrap") => None::<i32>.unwrap(),
        Ok("production-assert") => { assert!(false, "production invariant"); 1 },
        _ => 1,
    }
}
#[cfg(test)] mod tests {
    #[test] fn expected() {
        if std::env::var("MUTATION_CASE").as_deref() == Ok("custom-assert") {
            assert!(false, "plain TCP sendfile: Ok(None)");
        }
        if std::env::var("MUTATION_CASE").as_deref() == Ok("custom-comparison") {
            assert_eq!(false, true, "HTTP settings must survive parsing");
        }
        if std::env::var("MUTATION_CASE").as_deref() == Ok("plain-assert") {
            assert!(false);
        }
        assert_eq!(super::actual(), 1);
    }
    #[test] fn another_expected() { assert_eq!(super::actual(), 1); }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'src').mkdir()
            (root / 'src/lib.rs').write_text(source)
            subprocess.run(['rustc', '--edition=2021', '--test', 'src/lib.rs', '-o', 'suite'],
                           cwd=root, check=True, capture_output=True, timeout=30)
            lines = source.splitlines()
            test_start = lines.index('#[cfg(test)] mod tests {') + 1
            scope = {'sources': {'src/lib.rs': {'lineCount': len(lines),
                'classification': 'production-candidate',
                'excludedLines': list(range(test_start, len(lines) + 1))}}}
            for case, expected in [('clean', 'survived'), ('assert', 'killed'),
                                   ('panic', 'error'), ('unwrap', 'error'),
                                   ('production-assert', 'error'),
                                   ('custom-assert', 'error'), ('custom-comparison', 'killed'),
                                   ('plain-assert', 'killed')]:
                with self.subTest(case=case):
                    result = subprocess.run([str(root / 'suite'), '--test-threads=1'],
                        cwd=root, env={**os.environ, 'MUTATION_CASE': case},
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10)
                    status = 'Success' if result.returncode == 0 else {'Failure': result.returncode}
                    self.assertEqual(audit.classify(outcome(status), result.stdout, scope, None), expected, result.stdout)

    def test_real_cargo_mutants_inventory_with_multiline_function_replacements(self):
        source = '''pub fn identity(value: i32) -> i32 {
    value
}
#[cfg(test)] mod tests {
    #[test] fn identity_is_not_a_constant() {
        assert_eq!(super::identity(24), 24);
    }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'src').mkdir()
            (root / 'src/lib.rs').write_text(source)
            (root / 'Cargo.toml').write_text(
                '[package]\nname = "mutation_evidence_fixture"\nversion = "0.0.0"\n'
                'edition = "2021"\n[workspace]\n')
            result = subprocess.run(['cargo', 'mutants', '--no-config', '--jobs', '1',
                '--timeout', '10', '--build-timeout', '30', '--output', str(root / 'evidence'),
                '--', '--lib', '--', '--test-threads=1'], cwd=root,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout)
            scope = {'host': SCOPE['host'], 'sources': {'src/lib.rs': {
                'classification': 'production-candidate', 'lineCount': 8,
                # Pin the assertion line alone to detect even one-line shifts.
                'excludedLines': [6],
            }}}
            report = audit.audit(root / 'evidence/mutants.out', scope)
            self.assertTrue(report['evidenceClean'], report)
            self.assertGreater(report['generated'], 0)
            self.assertEqual(report['counts'], {'killed': report['generated']})

    def test_snapshot_includes_external_tls_inputs_but_not_shared_targets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, work = Path(temporary) / 'repo', Path(temporary) / 'private'
            source = root / 'native/transport/ct_core/src/lib.rs'
            source.parent.mkdir(parents=True)
            source.write_text('''#[test] fn sibling_fixtures_are_available() {
    assert_eq!(include_str!("../../../bench/bench_tls.crt"), "public-certificate");
    assert_eq!(include_str!("../../../bench/bench_tls.key"), "public-test-key");
}
''')
            for relative, content in zip(collector.FIXTURES, ['public-certificate', 'public-test-key']):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            target = root / 'native/transport/target/do-not-copy'
            target.parent.mkdir()
            target.write_text('shared build cache')
            paths = [str(source.relative_to(root)), *collector.FIXTURES]
            hashes = {path: collector.native_coverage.digest(root / path) for path in paths}
            collector.copy_inputs(root, work, hashes)
            self.assertFalse((work / 'native/transport/target').exists())
            subprocess.run(['rustc', '--test', str(source.relative_to(root)), '-o', 'suite'],
                           cwd=work, capture_output=True, check=True, timeout=30)
            subprocess.run([str(work / 'suite')], cwd=work, capture_output=True, check=True, timeout=10)
            (work / source.relative_to(root)).write_text('mutated private copy')
            with self.assertRaises(ValueError):
                collector.verify_inputs(work, hashes)
            collector.verify_inputs(root, hashes)
            self.assertEqual(target.read_text(), 'shared build cache')

    def test_missing_or_changed_snapshot_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'source').write_text('source')
            hashes = {'source': collector.native_coverage.digest(root / 'source')}
            (root / 'source').write_text('changed')
            with self.assertRaises(ValueError):
                collector.verify_inputs(root, hashes)
            (root / 'source').unlink()
            with self.assertRaises(FileNotFoundError):
                collector.verify_inputs(root, hashes)

    def test_snapshot_materializes_symlinks_without_mutating_their_targets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, work = Path(temporary) / 'repo', Path(temporary) / 'private'
            transport = root / 'native/transport'
            transport.mkdir(parents=True)
            shared = root / 'shared'
            shared.mkdir()
            (shared / 'lib.rs').write_text('original source')
            (transport / 'src').symlink_to(shared, target_is_directory=True)
            (transport / 'linked.rs').symlink_to(shared / 'lib.rs')
            for relative in collector.FIXTURES:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
            paths = ['native/transport/src/lib.rs', 'native/transport/linked.rs',
                     *collector.FIXTURES]
            hashes = {path: collector.native_coverage.digest(root / path) for path in paths}
            collector.copy_inputs(root, work, hashes)
            self.assertFalse((work / 'native/transport/src').is_symlink())
            self.assertFalse((work / 'native/transport/linked.rs').is_symlink())
            for relative in paths[:2]:
                (work / relative).write_text('mutant')
            collector.verify_inputs(root, hashes)
            self.assertEqual((shared / 'lib.rs').read_text(), 'original source')

    def test_campaign_and_restoration_only_use_the_private_workspace(self):
        work = Path('/private/test work')
        campaign, restored = collector.commands(work, Path('/evidence'))
        self.assertIn('--in-place', campaign)
        self.assertNotIn('--jobs', campaign)
        self.assertIn('--cargo-arg=--locked', campaign)
        for command in [campaign, restored]:
            self.assertEqual(command[:2], ['env', 'CARGO_TARGET_DIR=/private/test work/target'])
            self.assertEqual(command[command.index('--manifest-path') + 1],
                             '/private/test work/native/transport/Cargo.toml')
            self.assertEqual(command[-3:], ['--', 'rawsocket::tests', '--test-threads=1'])

    def test_whole_component_commands_keep_workspace_integration_tests(self):
        for target, package in [('core-all', 'ct_core'), ('ffi-all', 'ct_ffi')]:
            with self.subTest(target=target):
                campaign, restored = collector.commands(Path('/private/work'), Path('/evidence'), target)
                self.assertEqual(campaign[campaign.index('--package') + 1], package)
                self.assertEqual(campaign[campaign.index('--test-workspace') + 1], 'false')
                self.assertEqual(campaign[campaign.index('--timeout') + 1], '180')
                self.assertIn('--cargo-arg=--workspace', campaign)
                self.assertIn('--workspace', restored)
                for command in (campaign, restored):
                    self.assertIn('--all-targets', command)
                    self.assertIn('--no-fail-fast', command)
                    self.assertNotIn('--lib', command)
                    self.assertNotIn('--file', command)
                    self.assertEqual(command[-2:], ['--', '--test-threads=1'])
                self.assertIn('--cargo-arg=--locked', campaign)
                self.assertIn('--locked', restored)

    def test_real_campaign_baseline_and_mutants_use_the_same_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            root = work / 'native/transport'
            root.mkdir(parents=True)
            (root / 'Cargo.toml').write_text(
                '[workspace]\nmembers = ["ct_core", "ct_ffi"]\nresolver = "2"\n')
            for package in ('ct_core', 'ct_ffi'):
                crate = root / package
                (crate / 'src').mkdir(parents=True)
                (crate / 'Cargo.toml').write_text(
                    f'[package]\nname = "{package}"\nversion = "0.0.0"\n'
                    'edition = "2021"\n[features]\nffi-test = []\n')
                (crate / 'src/lib.rs').write_text(
                    'pub fn enabled() -> bool { true }\n'
                    f'#[test]\nfn {package}_assertion() {{ assert!(enabled()); }}\n')
            subprocess.run(['cargo', 'generate-lockfile', '--offline'], cwd=root,
                           check=True, capture_output=True, timeout=30)
            expected = ['ct_core_assertion', 'ct_ffi_assertion']
            for target in ('core-all', 'ffi-all'):
                with self.subTest(target=target):
                    output = work / target
                    campaign, restored = collector.commands(work, output, target)
                    result = subprocess.run(campaign, cwd=work, text=True,
                                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                            timeout=120)
                    self.assertEqual(result.returncode, 0, result.stdout)
                    directory = output / 'mutants.out'
                    outcomes = json.loads((directory / 'outcomes.json').read_text())['outcomes']
                    self.assertEqual(len(outcomes), 2, outcomes)
                    self.assertEqual(sum(item['scenario'] == 'Baseline' for item in outcomes), 1)
                    for item in outcomes:
                        log_text = (directory / item['log_path']).read_text()
                        tests = audit.TEST.findall(log_text)
                        self.assertEqual(sorted(name for name, _ in tests), expected, log_text)
                        failures = [name for name, status in tests if status == 'FAILED']
                        self.assertEqual(failures, [] if item['scenario'] == 'Baseline' else
                                         [('ct_core' if target == 'core-all' else 'ct_ffi') + '_assertion'])
                    result = subprocess.run(restored, cwd=work, text=True,
                                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                            timeout=90)
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(sorted(audit.TEST.findall(result.stdout)),
                                     [(name, 'ok') for name in expected])

    def test_whole_workspace_assertion_does_not_skip_later_test_binary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Cargo.toml').write_text(
                '[workspace]\nmembers = ["first", "second"]\nresolver = "2"\n')
            scope = {'sources': {}}
            for name, expected in [('first', 2), ('second', 1)]:
                crate = root / name
                (crate / 'src').mkdir(parents=True)
                (crate / 'Cargo.toml').write_text(
                    f'[package]\nname = "{name}"\nversion = "0.0.0"\nedition = "2021"\n')
                (crate / 'src/lib.rs').write_text(
                    f'#[test]\nfn {name}_assertion() {{ assert_eq!(1, {expected}); }}\n')
                scope['sources'][f'{name}/src/lib.rs'] = {
                    'classification': 'test-only', 'lineCount': 2, 'excludedLines': [1, 2]}
            result = subprocess.run(
                ['cargo', 'test', '--offline', '--workspace', '--all-targets', '--no-fail-fast',
                 '--', '--test-threads=1'], cwd=root, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, timeout=90)
            self.assertEqual(result.returncode, 101, result.stdout)
            self.assertEqual(sorted(audit.TEST.findall(result.stdout)),
                             [('first_assertion', 'FAILED'), ('second_assertion', 'ok')])
            self.assertEqual(audit.classify(outcome({'Failure': 101}), result.stdout, scope, None),
                             'killed', result.stdout)

    def test_inventory_partition_retains_nested_production_body_and_pins_helper(self):
        scope = copy.deepcopy(SCOPE)
        path = 'native/transport/' + MUTANT['file']
        scope['inputHashes'] = {path: 'ab' * 32}
        source = scope['sources'][path]
        source['exclusions'] = [{'reason': '#[cfg(test)]', 'span': {
            'start': [40, 0], 'end': [45, 10]}}]
        source['productionFunctionBodies'] = [{'name': 'outer', 'span': {
            'start': [2, 0], 'end': [50, 10]}}]
        parent = copy.deepcopy(MUTANT)
        parent.update(name='outer', genre='FnValue', span={
            'start': {'line': 2, 'column': 1}, 'end': {'line': 50, 'column': 11}})
        helper = copy.deepcopy(MUTANT)
        helper.update(name='helper', span={
            'start': {'line': 41, 'column': 1}, 'end': {'line': 41, 'column': 3}})
        result = collector.partition_inventory([parent, helper, MUTANT], scope)
        self.assertEqual(result['production'], [parent, MUTANT])
        self.assertEqual(result['excluded'], [{
            'mutant': helper, 'source': path, 'sourceSha256': 'ab' * 32,
            'reason': '#[cfg(test)]', 'span': source['exclusions'][0]['span']}])

    def test_inventory_partition_fails_closed_on_unproved_exclusions(self):
        for variant in ['partial', 'missing-span', 'missing-hash', 'unknown-source',
                        'invalid-range', 'duplicate', 'empty']:
            with self.subTest(variant=variant):
                scope = copy.deepcopy(SCOPE)
                path = 'native/transport/' + MUTANT['file']
                scope['inputHashes'] = {path: 'ab' * 32}
                source = scope['sources'][path]
                source['exclusions'] = [{'reason': '#[cfg(test)]', 'span': {
                    'start': [40, 0], 'end': [45, 10]}}]
                mutant = copy.deepcopy(MUTANT)
                mutant['span'] = {'start': {'line': 41, 'column': 1},
                                  'end': {'line': 41, 'column': 3}}
                inventory = [mutant]
                if variant == 'partial':
                    mutant['span']['start']['line'] = 39
                elif variant == 'missing-span':
                    source['exclusions'] = []
                elif variant == 'missing-hash':
                    scope['inputHashes'] = {}
                elif variant == 'unknown-source':
                    mutant['file'] = 'missing.rs'
                elif variant == 'invalid-range':
                    mutant['span']['end']['line'] = 90
                elif variant == 'duplicate':
                    inventory.append(copy.deepcopy(mutant))
                else:
                    inventory = []
                with self.assertRaises(ValueError):
                    collector.partition_inventory(inventory, scope)

    def test_whole_inventory_preflight_rejects_filter_drift_and_preserves_raw(self):
        for filtered in ([MUTANT], [], [MUTANT, MUTANT]):
            with self.subTest(filtered=len(filtered)), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)
                with patch.object(collector.subprocess, 'check_output', side_effect=[
                        json.dumps([MUTANT]), json.dumps(filtered)]) as command:
                    if len(filtered) == 1:
                        result = collector.prepare_inventory(output, output, SCOPE, 'core-all')
                        self.assertEqual(result, {'production': [MUTANT], 'excluded': []})
                    else:
                        with self.assertRaisesRegex(RuntimeError, 'Filtered inventory differs'):
                            collector.prepare_inventory(output, output, SCOPE, 'core-all')
                    self.assertEqual(command.call_count, 2)
                    for call in command.call_args_list:
                        self.assertIn('--no-config', call.args[0])
                        self.assertIn('--list', call.args[0])
                        self.assertNotIn('--file', call.args[0])
                self.assertEqual(json.loads((output / 'raw-inventory.json').read_text()), [MUTANT])
                self.assertEqual(json.loads((output / 'filtered-inventory.json').read_text()), filtered)

    def test_helper_exclusion_regex_is_exact_and_not_a_name_prefix(self):
        name = 'ct_ffi/src/lib.rs:10:1: replace fn[0] -> Result<(), E> with Ok(())'
        campaign, _ = collector.commands(Path('/work'), Path('/out'), 'ffi-all',
                                         [{'mutant': {'name': name}}])
        regex = campaign[campaign.index('--exclude-re') + 1]
        self.assertIsNotNone(collector.re.fullmatch(regex, name))
        self.assertIsNone(collector.re.fullmatch(regex, name + ' extra'))
        self.assertIsNone(collector.re.fullmatch(regex, name.replace('fn[0]', 'fn0')))
        with self.assertRaises(ValueError):
            collector.commands(Path('/work'), Path('/out'), exclusions=[{'mutant': {'name': name}}])

    def test_explicit_targets_keep_complete_matching_private_commands(self):
        work = Path('/private/test work')
        for target, source, test_filter in [
                ('core-rawsocket', 'ct_core/src/rawsocket.rs', 'rawsocket::tests'),
                ('core-wamp', 'ct_core/src/wamp.rs', 'wamp::'),
                ('core-config', 'ct_core/src/config.rs', ''),
                ('core-protocol', 'ct_core/src/protocol.rs', '')]:
            with self.subTest(target=target):
                campaign, restored = collector.commands(work, Path('/evidence'), target)
                self.assertEqual(campaign[campaign.index('--file') + 1], source)
                self.assertEqual(campaign[campaign.index('--timeout') + 1],
                                 '90' if target == 'core-protocol' else '30')
                self.assertEqual(campaign[campaign.index('--build-timeout') + 1], '180')
                self.assertIn('--in-place', campaign)
                self.assertIn('--no-config', campaign)
                self.assertIn('--cargo-arg=--locked', campaign)
                for forbidden in ['--regex', '--exclude-re', '--shard', '--jobs', '--skip']:
                    self.assertNotIn(forbidden, campaign)
                for command in [campaign, restored]:
                    self.assertEqual(command[:2], ['env', 'CARGO_TARGET_DIR=/private/test work/target'])
                    self.assertEqual(command[command.index('--package') + 1], 'ct_core')
                    self.assertEqual(command[command.index('--manifest-path') + 1],
                                     '/private/test work/native/transport/Cargo.toml')
                    self.assertEqual(command[-4:], ['--lib', '--', test_filter, '--test-threads=1'])
        self.assertEqual(collector.commands(work, Path('/evidence')),
                         collector.commands(work, Path('/evidence'), 'core-rawsocket'))

    def test_unknown_native_target_fails_before_side_effects(self):
        for target in ['', 'wamp', '../core-wamp', 'core-wamp --regex .']:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                root, output = Path(temporary), Path(temporary) / 'evidence'
                with patch.object(collector.native_coverage, 'snapshot') as snapshot, \
                        patch.object(collector.subprocess, 'check_output') as version, \
                        patch.object(collector, 'run') as command:
                    with self.assertRaisesRegex(ValueError, 'Unknown native mutation target'):
                        collector.commands(root, output, target)
                    with self.assertRaisesRegex(ValueError, 'Unknown native mutation target'):
                        collector.collect(root, output, Path('analyzer'), target)
                    snapshot.assert_not_called()
                    version.assert_not_called()
                    command.assert_not_called()
                    self.assertFalse(output.exists())

    def test_cli_passes_default_and_explicit_targets_without_reinterpreting_paths(self):
        for target in [None, *collector.TARGETS]:
            with self.subTest(target=target):
                argv = ['collector', '--output', 'evidence with spaces', '--analyzer', 'analyzer with spaces']
                if target:
                    argv.extend(['--target', target])
                with patch('sys.argv', argv), patch.object(collector, 'collect', return_value=17) as collect:
                    self.assertEqual(collector.main(), 17)
                    collect.assert_called_once_with(
                        collector.native_coverage.REPO, Path('evidence with spaces').resolve(),
                        Path('analyzer with spaces').resolve(), target or 'core-rawsocket')
        with patch('sys.argv', ['collector', '--output', 'evidence', '--analyzer', 'analyzer',
                                '--target', 'invalid']), patch('sys.stderr'), \
                patch.object(collector, 'collect') as collect:
            with self.assertRaises(SystemExit) as error:
                collector.main()
            self.assertEqual(error.exception.code, 2)
            collect.assert_not_called()

    def test_wamp_target_is_recorded_even_when_campaign_times_out(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, output = Path(temporary) / 'repo', Path(temporary) / 'evidence'
            root.mkdir()
            with patch.object(collector.native_coverage, 'snapshot', return_value={**SCOPE, 'inputHashes': {}}), \
                    patch.object(collector.native_coverage, 'digest', return_value='hash'), \
                    patch.object(collector.subprocess, 'check_output', return_value='cargo-mutants 27.1.0\n'), \
                    patch.object(collector, 'copy_inputs'), \
                    patch.object(collector, 'run', return_value=(None, 'partial WAMP log')) as command, \
                    patch.object(collector.native_mutations, 'audit') as auditor:
                with self.assertRaisesRegex(RuntimeError, 'timed out'):
                    collector.collect(root, output, Path('analyzer'), 'core-wamp')
                auditor.assert_not_called()
                self.assertEqual(command.call_count, 1)
            manifest = json.loads((output / 'run-manifest.json').read_text())
            self.assertEqual(manifest['scope'], 'core-wamp')
            self.assertFalse(manifest['complete'])
            self.assertEqual(manifest['campaignCommand'][-3:], ['--', 'wamp::', '--test-threads=1'])
            self.assertEqual(manifest['restoredCommand'][-3:], ['--', 'wamp::', '--test-threads=1'])
            self.assertEqual((output / 'campaign.log').read_text(), 'partial WAMP log')
            self.assertFalse((output / 'audited-results.json').exists())

    def test_collector_retains_timeout_evidence_and_never_audits_it_as_complete(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, output = Path(temporary) / 'repo', Path(temporary) / 'evidence'
            root.mkdir()
            scope = {**SCOPE, 'inputHashes': {}}
            with patch.object(collector.native_coverage, 'snapshot', return_value=scope), \
                    patch.object(collector.native_coverage, 'digest', return_value='hash'), \
                    patch.object(collector.subprocess, 'check_output', return_value='cargo-mutants 27.1.0\n'), \
                    patch.object(collector, 'copy_inputs'), \
                    patch.object(collector, 'run', return_value=(None, 'partial log')) as command, \
                    patch.object(collector.native_mutations, 'audit') as auditor:
                with self.assertRaisesRegex(RuntimeError, 'timed out'):
                    collector.collect(root, output, Path('analyzer'))
                auditor.assert_not_called()
                self.assertEqual(command.call_count, 1)
            manifest = json.loads((output / 'run-manifest.json').read_text())
            self.assertFalse(manifest['complete'])
            self.assertIsNone(manifest['campaignExitCode'])
            self.assertEqual((output / 'campaign.log').read_text(), 'partial log')
            self.assertFalse((output / 'audited-results.json').exists())

    def test_collector_never_reuses_an_existing_evidence_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(FileExistsError):
                collector.collect(root, root, Path('analyzer'))

    def test_whole_collector_checks_executed_inventory_before_reporting_completion(self):
        for target in ('core-all', 'ffi-all'):
            for drift in (False, True):
                with self.subTest(target=target, drift=drift), tempfile.TemporaryDirectory() as temporary:
                    root, output = Path(temporary) / 'repo', Path(temporary) / 'evidence'
                    (root / 'native/transport').mkdir(parents=True)
                    for relative in collector.FIXTURES:
                        path = root / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text('fixture')

                    def prepare(_work, destination, _scope, selected):
                        self.assertEqual(selected, target)
                        partition = {'production': [MUTANT], 'excluded': []}
                        for filename, data in [('raw-inventory.json', [MUTANT]),
                                               ('filtered-inventory.json', [MUTANT]),
                                               ('inventory-partition.json', partition)]:
                            (destination / filename).write_text(json.dumps(data))
                        return partition

                    def command(args, _work, timeout):
                        if 'mutants' in args:
                            self.assertEqual(timeout, 86400)
                            self.assertIn('--all-targets', args)
                            directory = output / 'mutants.out'
                            directory.mkdir()
                            self.campaign(directory, 'survived')
                            if drift:
                                (directory / 'mutants.json').write_text('[]')
                            return 2, 'campaign completed with survivor'
                        self.assertIn('--workspace', args)
                        return 0, log()

                    with patch.object(collector.native_coverage, 'snapshot',
                                      return_value={**SCOPE, 'inputHashes': {}}), \
                            patch.object(collector.subprocess, 'check_output',
                                         return_value='cargo-mutants 27.1.0\n'), \
                            patch.object(collector, 'prepare_inventory', side_effect=prepare), \
                            patch.object(collector, 'run', side_effect=command) as run:
                        if drift:
                            with self.assertRaisesRegex(RuntimeError, 'Executed inventory differs'):
                                collector.collect(root, output, Path('analyzer'), target)
                            self.assertEqual(run.call_count, 1)
                            self.assertFalse((output / 'audited-results.json').exists())
                        else:
                            self.assertEqual(collector.collect(root, output, Path('analyzer'), target), 1)
                            self.assertEqual(run.call_count, 2)
                            report = json.loads((output / 'audited-results.json').read_text())
                            self.assertEqual(report['counts'], {'survived': 1})
                            self.assertEqual(report['rawCandidateScore'], 0)
                    manifest = json.loads((output / 'run-manifest.json').read_text())
                    self.assertEqual(manifest['complete'], not drift)
                    for key in ('rawInventorySha256', 'partitionSha256', 'filteredInventorySha256'):
                        self.assertRegex(manifest[key], '^[0-9a-f]{64}$')

    def test_collector_requires_restored_test_inventory_and_pins_its_tools(self):
        for restored_names, mutant_status in [(['tests::expected'], 'killed'),
                                              (['tests::expected'], 'survived'),
                                              (['tests::different'], 'killed')]:
            with self.subTest(restored=restored_names, mutant=mutant_status), tempfile.TemporaryDirectory() as temporary:
                root, output = Path(temporary) / 'repo', Path(temporary) / 'evidence'
                (root / 'native/transport').mkdir(parents=True)
                for relative in collector.FIXTURES:
                    path = root / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('fixture')

                def command(args, _work, _timeout):
                    if 'mutants' in args:
                        directory = output / 'mutants.out'
                        directory.mkdir()
                        self.campaign(directory, mutant_status)
                        return (2 if mutant_status == 'survived' else 0), 'complete campaign'
                    return 0, log(names=restored_names)

                with patch.object(collector.native_coverage, 'snapshot',
                                  return_value={**SCOPE, 'inputHashes': {}}), \
                        patch.object(collector.subprocess, 'check_output',
                                     return_value='cargo-mutants 27.1.0\n'), \
                        patch.object(collector, 'run', side_effect=command):
                    if restored_names == ['tests::expected']:
                        self.assertEqual(collector.collect(root, output, Path('analyzer')),
                                         1 if mutant_status == 'survived' else 0)
                        report = json.loads((output / 'audited-results.json').read_text())
                        self.assertEqual(report['counts'], {mutant_status: 1})
                        self.assertEqual(report['baselineTests'], restored_names)
                        self.assertEqual(set(report['toolHashes']), set(collector.TOOL_INPUTS))
                        for name, digest in report['toolHashes'].items():
                            self.assertEqual(digest, collector.native_coverage.digest(
                                Path(collector.__file__).parent / name))
                    else:
                        with self.assertRaisesRegex(RuntimeError, 'original test inventory'):
                            collector.collect(root, output, Path('analyzer'))
                        self.assertFalse((output / 'audited-results.json').exists())
                        manifest = json.loads((output / 'run-manifest.json').read_text())
                        self.assertFalse(manifest['complete'])


if __name__ == '__main__':
    unittest.main()
