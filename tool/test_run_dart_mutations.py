import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import run_dart_mutations as runner

sys.path.insert(0, str(Path(__file__).parent))
from run_dart_mutations import apply_mutation, classify, mutation_id, run, summarize, validate_equivalents


def events(*items):
    return '\n'.join(json.dumps(item) for item in items)


class MutationRunnerTests(unittest.TestCase):
    def test_only_a_real_failed_test_counts_as_a_kill(self):
        output = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'denies unknown users'}},
            {'type': 'testDone', 'testID': 1, 'result': 'failure', 'hidden': False},
            {'type': 'done', 'success': False},
        )
        self.assertEqual(classify(1, output), 'killed')
        self.assertEqual(classify(0, output), 'error')
        self.assertEqual(classify(None, output), 'timeout')
        self.assertEqual(classify(-9, ''), 'error')

    def test_compilation_failure_is_never_a_kill(self):
        output = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'loading test.dart'}},
            {'type': 'error', 'testID': 1, 'error': 'Error: Compilation failed.'},
            {'type': 'testDone', 'testID': 1, 'result': 'error', 'hidden': False},
            {'type': 'done', 'success': False},
        )
        self.assertEqual(classify(1, output), 'compileError')
        self.assertNotEqual(classify(1, 'Error: Compilation failed.'), 'killed')

    def test_signal_exit_never_counts_as_a_kill_even_after_failure_records(self):
        output = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
            {'type': 'testDone', 'testID': 1, 'result': 'failure'},
            {'type': 'done', 'success': False},
        )
        for signal_exit in (-9, -11, -15):
            with self.subTest(returncode=signal_exit):
                self.assertEqual(classify(signal_exit, output), 'error')

    def test_success_requires_nonempty_completed_unskipped_suite(self):
        started = {'type': 'testStart', 'test': {'id': 1, 'name': 'allows valid request'}}
        completed = {'type': 'testDone', 'testID': 1, 'result': 'success', 'skipped': False}
        done = {'type': 'done', 'success': True}
        self.assertEqual(classify(0, events(started, completed, done)), 'survived')
        self.assertEqual(classify(0, events(done)), 'error')
        self.assertEqual(classify(0, events(started, completed)), 'error')
        self.assertEqual(classify(0, events(started, {**completed, 'skipped': True}, done)), 'error')

    def test_runtime_loading_errors_are_not_compile_errors_or_kills(self):
        output = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'loading test.dart'}},
            {'type': 'error', 'testID': 1, 'error': 'StateError: invalid initial state'},
            {'type': 'testDone', 'testID': 1, 'result': 'error'},
            {'type': 'done', 'success': False},
        )
        self.assertEqual(classify(1, output), 'error')
        self.assertEqual(classify(1, output.replace('StateError: invalid initial state', 'source.dart:1:2: Error: Invalid type')), 'compileError')
        self.assertEqual(classify(1, output + '\n' + events({'type': 'print', 'message': 'source.dart:1:2:\nError: Invalid type\nError: Compilation failed.'})), 'compileError')

    def test_main_isolates_mutation_and_requires_restored_baseline(self):
        self.exercise_main('killed', 0)
        self.exercise_main('survived', 1)
        self.exercise_main('timeout', 1)
        self.exercise_main('signal', 1)

    def test_failed_baselines_never_produce_complete_evidence(self):
        self.exercise_main('baselineFailure', None)
        self.exercise_main('restoredFailure', None)

    def test_empty_or_non_mapping_targets_cannot_pass_without_running_tests(self):
        for invalid in ({}, [], None):
            with self.subTest(config=invalid), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                config = root / 'config.json'
                config.write_text(json.dumps(invalid))
                equivalents = root / 'equivalents.json'
                equivalents.write_text('{}')
                output = root / 'result'
                args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                        '--output', str(output)]
                with patch.object(sys, 'argv', args), patch.object(sys, 'stderr'), \
                     patch.object(runner, 'snapshot') as snapshot, \
                     patch.object(runner, 'run', return_value=(0, '')) as command, \
                     patch.object(runner.subprocess, 'check_output', return_value='commit'):
                    with self.assertRaises(SystemExit) as failure:
                        runner.main()
                    self.assertEqual(failure.exception.code, 2)
                    snapshot.assert_not_called()
                    command.assert_not_called()
                self.assertFalse(output.exists())

    def exercise_main(self, status, expected_code):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'config.json'
            equivalents = root / 'equivalents.json'
            equivalents.write_text('{}')
            source_path = 'packages/core/lib/a.dart'
            test_path = 'packages/core/test/a_test.dart'
            config.write_text(json.dumps({'fixture': {'sources': [source_path], 'tests': [test_path]}}))
            source = 'bool f() => true;'
            mutation = {'file': source_path, 'offset': 12, 'length': 4, 'line': 1,
                        'original': 'true', 'replacement': 'false', 'operator': 'boolean'}
            passed = events({'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                            {'type': 'testDone', 'testID': 1, 'result': 'success'},
                            {'type': 'done', 'success': True})
            seen = []
            def fake_snapshot(work):
                for name, data in [(source_path, source), (test_path, 'test fixture')]:
                    path = work / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(data)
            def fake_run(command, work, timeout):
                self.assertNotEqual(work, runner.ROOT)
                if command[1:3] == ['pub', 'get']:
                    return 0, ''
                if command[1] == 'tool/dart_mutations.dart':
                    return 0, json.dumps([mutation])
                current = (work / source_path).read_text()
                seen.append(current)
                if (status == 'baselineFailure' or
                        status == 'restoredFailure' and len(seen) == 3):
                    return -9, ''
                if current == source or status == 'survived':
                    return 0, passed
                if status == 'timeout':
                    return None, ''
                return (-9 if status == 'signal' else 1), passed.replace('"result": "success"', '"result": "failure"').replace('"success": true', '"success": false')
            args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                    '--output', str(root / 'result')]
            with patch.object(sys, 'argv', args), patch.object(runner, 'snapshot', fake_snapshot), \
                 patch.object(runner, 'run', fake_run), patch.object(runner.subprocess, 'check_output', return_value='commit'):
                if expected_code is None:
                    with self.assertRaises(RuntimeError):
                        runner.main()
                else:
                    self.assertEqual(runner.main(), expected_code)
            self.assertEqual(seen, [source] if status == 'baselineFailure'
                             else [source, 'bool f() => false;', source])
            report = json.loads((root / 'result/mutation-report.json').read_text())
            self.assertEqual(report['complete'], expected_code is not None)
            if expected_code is not None:
                target = report['targets']['fixture']
                self.assertEqual(target['restoredBaseline'], 'survived')
                self.assertEqual(target['baselineExitCode'], 0)
                self.assertEqual(target['restoredBaselineExitCode'], 0)
                if status == 'signal':
                    self.assertEqual(target['counts'], {'error': 1})
                    self.assertEqual(target['score'], 0)
                    self.assertEqual(target['outcomes'][0]['exitCode'], -9)

    def test_timeout_and_infrastructure_errors_do_not_inflate_score(self):
        result = summarize([{'status': s} for s in ['killed', 'survived', 'timeout', 'error', 'compileError']])
        self.assertEqual(result['score'], 25)
        self.assertEqual(result['viable'], 4)
        self.assertIsNone(summarize([{'status': 'compileError'}])['score'])

    def test_utf16_offsets_preserve_non_ascii_prefix(self):
        source = "// \U0001f512\nreturn a == b;"
        offset = len(source[:source.index('==')].encode('utf-16-le')) // 2
        mutation = {'offset': offset, 'length': 2, 'original': '==', 'replacement': '!='}
        self.assertEqual(apply_mutation(source, mutation), "// \U0001f512\nreturn a != b;")
        self.assertEqual(mutation_id(mutation), mutation_id(dict(reversed(list(mutation.items())))))
        with self.assertRaises(ValueError):
            apply_mutation(source, {**mutation, 'offset': 0})

    def test_equivalence_preserves_raw_score_and_is_pinned_to_source(self):
        mutation = {'file': 'a.dart', 'replacement': 'false'}
        identifier = mutation_id(mutation)
        entry = {'sourceHash': 'hash', 'reason': 'Both branches return the same value without side effects.'}
        self.assertEqual(validate_equivalents({identifier: entry}, [mutation], {'a.dart': 'hash'}),
                         {identifier: entry['reason']})
        for invalid in ({'stale': entry}, {identifier: {**entry, 'sourceHash': 'changed'}},
                        {identifier: {**entry, 'reason': ''}}):
            with self.assertRaises(ValueError):
                validate_equivalents(invalid, [mutation], {'a.dart': 'hash'})
        summary = summarize([{'status': 'killed'}, {'status': 'survived', 'equivalence': entry['reason']}])
        self.assertEqual(summary['score'], 50)
        self.assertEqual(summary['adjustedScore'], 100)
        self.assertEqual(summary['equivalent'], 1)

    def test_command_timeout_kills_the_process_group(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'late'
            child = "import time,pathlib;time.sleep(1);pathlib.Path('late').touch()"
            parent = f'import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",{child!r}]);time.sleep(5)'
            code, _ = run([sys.executable, '-c', parent], directory, .1)
            self.assertIsNone(code)
            run([sys.executable, '-c', 'import time;time.sleep(1.2)'], directory, 3)
            self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
