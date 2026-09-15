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
    def test_complete_success_and_explicit_test_assertion(self):
        self.assertEqual(audit.classify(outcome(), log(), SCOPE, None), 'survived')
        failed = log([('tests::expected', assertion())])
        self.assertEqual(audit.classify(outcome({'Failure': 101}), failed, SCOPE, MUTANT), 'killed')

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

    def test_real_rust_assertion_is_distinguished_from_production_panics(self):
        source = '''fn actual() -> i32 {
    match std::env::var("MUTATION_CASE").as_deref() {
        Ok("assert") => 2,
        Ok("panic") => panic!("production error"),
        Ok("production-assert") => { assert!(false, "production invariant"); 1 },
        _ => 1,
    }
}
#[cfg(test)] mod tests {
    #[test] fn expected() { assert_eq!(super::actual(), 1); }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'src').mkdir()
            (root / 'src/lib.rs').write_text(source)
            subprocess.run(['rustc', '--edition=2021', '--test', 'src/lib.rs', '-o', 'suite'],
                           cwd=root, check=True, capture_output=True, timeout=30)
            scope = {'sources': {'src/lib.rs': {'lineCount': 11,
                'classification': 'production-candidate', 'excludedLines': [9, 10, 11]}}}
            for case, expected in [('clean', 'survived'), ('assert', 'killed'),
                                   ('panic', 'error'), ('production-assert', 'error')]:
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
