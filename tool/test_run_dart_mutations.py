import json
import os
from pathlib import Path
import signal
import socket
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import run_dart_mutations as runner

sys.path.insert(0, str(Path(__file__).parent))
from run_dart_mutations import apply_mutation, classify, mutation_id, run, summarize, validate_equivalents


def events(*items):
    return '\n'.join(json.dumps(item) for item in items)


class MutationRunnerTests(unittest.TestCase):
    def test_production_sources_accept_package_entry_points_but_not_test_paths(self):
        runner.validate_sources([
            'packages/client/lib/src/installer.dart',
            'packages/client/hook/build.dart',
            'packages/client/bin/main.dart',
            'packages/client/tool/install.dart',
        ])
        for sources in ([], 'packages/client/lib/a.dart', [None],
                        ['packages/client/test/lib/fake.dart'],
                        ['packages/client/test/hook/build.dart'],
                        ['packages/client/lib/../test/fake.dart'],
                        ['packages/client//lib/a.dart'],
                        ['packages/client/lib/a.py'],
                        ['/tmp/packages/client/lib/a.dart']):
            with self.subTest(sources=sources), self.assertRaises(ValueError):
                runner.validate_sources(sources)

    def test_normal_exit_reaps_orphans_and_invalidates_apparent_test_results(self):
        child = (
            "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',0)); "
            "s.listen(); print(s.getsockname()[1],flush=True); time.sleep(60)"
        )
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code):
                output = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                    {'type': 'testDone', 'testID': 1,
                     'result': 'success' if exit_code == 0 else 'failure'},
                    {'type': 'done', 'success': exit_code == 0},
                )
                parent = (
                    'import subprocess,sys,json\n'
                    f'p=subprocess.Popen([sys.executable,"-c",{child!r}], '
                    'stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)\n'
                    'port=int(p.stdout.readline())\n'
                    'print(json.dumps({"pid":p.pid,"port":port}),flush=True)\n'
                    f'print({output!r},flush=True)\n'
                    f'sys.exit({exit_code})\n'
                )
                code, actual = run([sys.executable, '-c', parent], runner.ROOT, 5)
                owned = json.loads(actual.splitlines()[0])
                try:
                    self.assertEqual(code, exit_code)
                    self.assertEqual(classify(code, actual), 'error', actual)
                    deadline = time.monotonic() + 1
                    while True:
                        try:
                            with socket.socket() as probe:
                                probe.bind(('127.0.0.1', owned['port']))
                            break
                        except OSError:
                            if time.monotonic() >= deadline:
                                self.fail('The test-owned child still holds its listening port')
                            time.sleep(0.01)
                finally:
                    try:
                        os.kill(owned['pid'], signal.SIGKILL)
                    except ProcessLookupError:
                        pass

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

    def test_isolated_suites_classify_independently_and_stop_after_failure(self):
        passed = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success'},
            {'type': 'done', 'success': True},
        )
        failed = passed.replace('"result": "success"', '"result": "failure"').replace(
            '"success": true', '"success": false')
        setup_failed = failed.replace('"contract"', '"group (setUpAll)"')
        commands = [['dart', 'test', name] for name in ('a.dart', 'b.dart', 'c.dart')]
        for code, output, expected in ((1, failed, 'killed'),
                                       (1, setup_failed, 'error'),
                                       (None, '', 'timeout')):
            with self.subTest(status=expected), patch.object(
                    runner, 'run', side_effect=[(0, passed), (code, output)]) as command:
                actual_code, log, status = runner.run_test_commands(commands, runner.ROOT, 45)
                self.assertEqual((actual_code, status), (code, expected))
                self.assertEqual(command.call_count, 2)
                self.assertNotIn('c.dart', log)
                self.assertIn('connectanumTestCommand', log)
        with patch.object(runner, 'run', return_value=(0, passed)) as command:
            code, _, status = runner.run_test_commands(commands, runner.ROOT, 45)
            self.assertEqual((code, status), (0, 'survived'))
            self.assertEqual(command.call_count, 3)

    def test_isolated_suites_share_one_process_deadline(self):
        passed = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success'},
            {'type': 'done', 'success': True},
        )
        with patch.object(runner.time, 'monotonic', side_effect=[100, 101, 104]), \
             patch.object(runner, 'run', side_effect=[(0, passed), (None, '')]) as command:
            _, _, status = runner.run_test_commands([['first'], ['second']], runner.ROOT, 5)
        self.assertEqual(status, 'timeout')
        self.assertEqual([call.args[2] for call in command.call_args_list], [4, 1])
        for commands, timeout in (([], 5), ([['test']], 0),
                                  ([['test']], float('nan')), ([['test']], float('inf'))):
            with self.assertRaises(ValueError):
                runner.run_test_commands(commands, runner.ROOT, timeout)

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

    def test_failed_suite_fixtures_never_count_as_mutation_kills(self):
        for name in ('(setUpAll)', 'router (setUpAll)', 'router (tearDownAll)'):
            output = events(
                {'type': 'testStart', 'test': {'id': 1, 'name': name}},
                {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                {'type': 'done', 'success': False},
            )
            with self.subTest(name=name):
                self.assertEqual(classify(1, output), 'error')

    def test_real_dart_reporter_distinguishes_fixture_failures_and_kills(self):
        cases = [
            ('healthy', '', 'expect(1, 1);', 'survived'),
            ('assertion', '', 'expect(1, 2);', 'killed'),
            ('startup', "setUpAll(() => throw StateError('startup'));",
             'expect(1, 1);', 'error'),
            ('shutdown', "tearDownAll(() => throw StateError('shutdown'));",
             'expect(1, 1);', 'error'),
            ('shutdown_after_failure', "tearDownAll(() => throw StateError('shutdown'));",
             'expect(1, 2);', 'error'),
            ('timeout', '', 'await Future<void>.delayed(const Duration(seconds: 5));',
             'timeout'),
            ('abrupt_exit', '', 'exit(2);', 'error'),
        ]
        with tempfile.TemporaryDirectory(prefix='mutation-reporter-',
                                         dir=runner.ROOT / '.dart_tool') as directory:
            for name, lifecycle, body, expected in cases:
                with self.subTest(case=name):
                    source = Path(directory) / f'{name}_test.dart'
                    source.write_text(
                        "import 'dart:io';\nimport 'package:test/test.dart';\n"
                        "void main() { group('fixture isolation', () {\n"
                        f"{lifecycle}\n"
                        f"test('contract', () async {{ {body} }});\n"
                        "}); }\n"
                    )
                    code, output = run(
                        ['dart', 'test', str(source), '--reporter=json',
                         '--concurrency=1', '--timeout=1s'], runner.ROOT, 45,
                    )
                    self.assertEqual(classify(code, output), expected, output)

    def test_native_artifact_is_required_and_hashed_not_silently_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'library.bin'
            library.write_bytes(b'native fixture')
            with patch.dict(runner.os.environ, {}, clear=True):
                with self.assertRaisesRegex(ValueError, 'CONNECTANUM_NATIVE_LIB'):
                    runner.native_artifact()
            with patch.dict(runner.os.environ, {'CONNECTANUM_NATIVE_LIB': str(library)}):
                artifact = runner.native_artifact()
                self.assertEqual(artifact['path'], str(library.resolve()))
                self.assertEqual(artifact['sha256'], runner.hashlib.sha256(b'native fixture').hexdigest())
                library.unlink()
                with self.assertRaisesRegex(ValueError, 'existing file'):
                    runner.native_artifact()

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

    def test_directory_targets_record_and_run_stable_test_file_order(self):
        self.exercise_main('killed', 0, directory_tests=True)

    def test_native_target_records_support_artifact_and_test_deadline(self):
        self.exercise_main('killed', 0, native=True, directory_tests=True)

    def test_native_artifact_change_invalidates_completed_mutants(self):
        self.exercise_main('artifactChanged', None, native=True)

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

    def exercise_main(self, status, expected_code, directory_tests=False, native=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'config.json'
            equivalents = root / 'equivalents.json'
            equivalents.write_text('{}')
            source_path = 'packages/core/lib/a.dart'
            test_path = 'packages/core/test/a_test.dart'
            selected = ['packages/core/test'] if directory_tests else [test_path]
            target = {'sources': [source_path], 'tests': selected}
            library = root / 'native.bin'
            library.write_bytes(b'native baseline')
            if native:
                target.update(requiresNativeLibrary=True, testTimeoutSeconds=20, isolateTestFiles=True,
                              supportFiles=['packages/core/example/server.dart'])
            config.write_text(json.dumps({'fixture': target}))
            source = 'bool f() => true;'
            mutation = {'file': source_path, 'offset': 12, 'length': 4, 'line': 1,
                        'original': 'true', 'replacement': 'false', 'operator': 'boolean'}
            passed = events({'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                            {'type': 'testDone', 'testID': 1, 'result': 'success'},
                            {'type': 'done', 'success': True})
            seen = []
            def fake_snapshot(work):
                files = [(source_path, source)]
                if native:
                    files.append(('packages/core/example/server.dart', 'example fixture'))
                if directory_tests:
                    files.extend([('packages/core/test/z_test.dart', 'last test'),
                                  ('packages/core/test/support/helper.dart', 'helper')])
                files.append((test_path, 'test fixture'))
                for name, data in files:
                    path = work / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(data)
            def fake_run(command, work, timeout):
                self.assertNotEqual(work, runner.ROOT)
                if command[1:3] == ['pub', 'get']:
                    return 0, ''
                if command[1] == 'tool/dart_mutations.dart':
                    return 0, json.dumps([mutation])
                if directory_tests:
                    selected = [arg for arg in command if arg.startswith('packages/core/test')]
                    if native:
                        self.assertEqual(len(selected), 1)
                        self.assertIn(selected[0], [test_path, 'packages/core/test/z_test.dart'])
                    else:
                        self.assertEqual(selected, [test_path, 'packages/core/test/z_test.dart'])
                current = (work / source_path).read_text()
                seen.append(current)
                if native:
                    self.assertIn('--timeout=20s', command)
                    self.assertNotIn('--fail-fast', command)
                    if status == 'artifactChanged' and len(seen) == 3:
                        library.write_bytes(b'replaced artifact')
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
                 patch.object(runner, 'run', fake_run), patch.object(runner.subprocess, 'check_output', return_value='commit'), \
                 patch.dict(runner.os.environ, {'CONNECTANUM_NATIVE_LIB': str(library)}):
                if expected_code is None:
                    with self.assertRaises(RuntimeError):
                        runner.main()
                else:
                    self.assertEqual(runner.main(), expected_code)
            expected_seen = [source] if status == 'baselineFailure' else [source, 'bool f() => false;', source]
            if native and directory_tests:
                expected_seen = [source, source, 'bool f() => false;', source, source]
            self.assertEqual(seen, expected_seen)
            report = json.loads((root / 'result/mutation-report.json').read_text())
            self.assertEqual(report['complete'], expected_code is not None)
            if status == 'artifactChanged':
                self.assertFalse(report['targets']['fixture']['nativeArtifactUnchanged'])
            if expected_code is not None:
                target = report['targets']['fixture']
                self.assertEqual(target['restoredBaseline'], 'survived')
                self.assertEqual(target['baselineExitCode'], 0)
                self.assertEqual(target['restoredBaselineExitCode'], 0)
                if directory_tests:
                    self.assertEqual(target['resolvedTests'],
                                     [test_path, 'packages/core/test/z_test.dart'])
                    self.assertIn('packages/core/test/support/helper.dart', target['testHashes'])
                if native:
                    self.assertEqual(len(target['testCommands']), 2 if directory_tests else 1)
                    if directory_tests:
                        self.assertNotIn('testCommand', target)
                    self.assertTrue(target['nativeArtifactUnchanged'])
                    self.assertEqual(target['nativeArtifact']['sha256'],
                                     runner.hashlib.sha256(b'native baseline').hexdigest())
                    self.assertEqual(target['supportHashes'], {
                        'packages/core/example/server.dart':
                            runner.hashlib.sha256(b'example fixture').hexdigest(),
                    })
                if status == 'signal':
                    self.assertEqual(target['counts'], {'error': 1})
                    self.assertEqual(target['score'], 0)
                    self.assertEqual(target['outcomes'][0]['exitCode'], -9)

    def test_timeout_and_infrastructure_errors_do_not_inflate_score(self):
        result = summarize([{'status': s} for s in ['killed', 'survived', 'timeout', 'error', 'compileError']])
        self.assertEqual(result['score'], 25)
        self.assertEqual(result['viable'], 4)
        self.assertIsNone(summarize([{'status': 'compileError'}])['score'])

    def test_assertion_failure_cannot_hide_another_test_timeout(self):
        output = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'assertion'}},
            {'type': 'testDone', 'testID': 1, 'result': 'failure'},
            {'type': 'testStart', 'test': {'id': 2, 'name': 'missing callback'}},
            {'type': 'error', 'testID': 2,
             'error': 'TimeoutException: Test timed out after 5 seconds.'},
            {'type': 'testDone', 'testID': 2, 'result': 'error'},
            {'type': 'done', 'success': False},
        )
        self.assertEqual(classify(1, output), 'timeout')

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
