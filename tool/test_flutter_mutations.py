"""Opt-in real Flutter mutation/reporter tests; never substitute for app scores.

CONNECTANUM_RUN_FLUTTER_MUTATION_TESTS=1 python3 tool/test_flutter_mutations.py
Set CONNECTANUM_FLUTTER_MUTATION_TEST_PLATFORM=chrome and optionally
CONNECTANUM_FLUTTER_MUTATION_TEST_COMPILER=dart2wasm for browser evidence.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import run_dart_mutations as runner


@unittest.skipUnless(os.environ.get('CONNECTANUM_RUN_FLUTTER_MUTATION_TESTS') == '1',
                     'Opt-in real Flutter SDK/reporter integration')
class FlutterMutationTests(unittest.TestCase):
    def test_real_compilation_and_reporter_evidence(self):
        platform = os.environ.get('CONNECTANUM_FLUTTER_MUTATION_TEST_PLATFORM', 'vm')
        compiler = os.environ.get('CONNECTANUM_FLUTTER_MUTATION_TEST_COMPILER',
                                  'dartdevc' if platform == 'chrome' else 'vm')
        app = 'examples/wamp_app/client'
        source = f'{app}/lib/flag.dart'
        cases = {
            'assertion': ('test', 'expect(enabled(), isTrue);'),
            'widget_assertion': ('testWidgets', 'expect(enabled(), isTrue);'),
            'error_only': ('test', "if (!enabled()) throw StateError('controlled runtime error');"),
            'widget_error': ('testWidgets', "if (!enabled()) throw StateError('controlled widget error');"),
            'widget_timeout': ('testWidgets', "if (!enabled()) throw TimeoutException('controlled deadline');"),
            'timeout': ('test', 'if (!enabled()) await Future<void>.delayed(const Duration(seconds: 10));'),
        }
        if platform == 'vm':
            cases['crash'] = ('test', 'if (!enabled()) exit(2);')

        def snapshot(work, support_files):
            self.assertEqual(support_files, [])
            (work / 'pubspec.yaml').write_text(
                'name: mutation_driver\nenvironment:\n  sdk: ^3.13.1\n'
                'dependencies:\n  analyzer: any\n')
            shutil.copy2(runner.ROOT / 'pubspec.lock', work / 'pubspec.lock')
            (work / 'tool').mkdir()
            shutil.copy2(runner.ROOT / 'tool/dart_mutations.dart', work / 'tool/dart_mutations.dart')
            (work / app / 'lib').mkdir(parents=True)
            (work / source).write_text('bool enabled() => 1 == 1;\n')
            (work / app / 'pubspec.yaml').write_text(
                'name: mutation_flutter_fixture\nenvironment:\n  sdk: ^3.13.1\n'
                'dependencies:\n  flutter:\n    sdk: flutter\n'
                'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n')
            shutil.copy2(runner.ROOT / app / 'pubspec.lock', work / app / 'pubspec.lock')
            tests = work / app / 'test'
            tests.mkdir()
            for name, (kind, body) in cases.items():
                imports = "import 'dart:io';\n" if name == 'crash' else ''
                callback = '(tester)' if kind == 'testWidgets' else '()'
                # testWidgets supplies its own timeout instead of inheriting the
                # runner flag. Bound intentional deadline controls explicitly.
                (tests / f'{name}_test.dart').write_text(
                    imports + "import 'dart:async';\nimport 'package:flutter_test/flutter_test.dart';\n"
                    "import 'package:mutation_flutter_fixture/flag.dart';\n"
                    f"void main() {{ {kind}('contract', {callback} async {{ {body} }}, "
                    "timeout: const Timeout(Duration(seconds: 2))); }\n")
            # Materialize the fixture's own lock before the runner freezes it.
            code, output = runner.run(['flutter', 'pub', 'get', '--offline'], work / app, 120)
            self.assertEqual(code, 0, output)
            shutil.rmtree(work / app / '.dart_tool')

        with tempfile.TemporaryDirectory(prefix='flutter-mutation-controls-') as directory:
            root = Path(directory)
            config = root / 'config.json'
            config.write_text(json.dumps({name: {
                'sources': [source], 'tests': [f'{app}/test/{name}_test.dart'],
                'testRoot': app, 'testRunner': 'flutter', 'platform': platform,
                'compiler': compiler, 'testTimeoutSeconds': 2,
            } for name in cases}))
            equivalents = root / 'equivalents.json'
            equivalents.write_text('{}')
            output = root / 'report'
            args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                    '--output', str(output), '--timeout', '180']
            try:
                with patch.object(sys, 'argv', args), patch.object(runner, 'snapshot', snapshot):
                    self.assertEqual(runner.main(), 1)
                report = json.loads((output / 'mutation-report.json').read_text())
                self.assertTrue(report['complete'])
                for name, target in report['targets'].items():
                    with self.subTest(case=name):
                        self.assertEqual(target['generated'], 1)
                        self.assertEqual(target['baseline'], 'survived')
                        self.assertEqual(target['restoredBaseline'], 'survived')
                        self.assertTrue(target['applicationInputsUnchanged'])
                        self.assertEqual(target['compiler'], compiler)
                        outcome = target['outcomes'][0]
                        log = (output / outcome['log']).read_text()
                        if name == 'assertion':
                            self.assertEqual(outcome['killEvidence']['cause'], 'assertion', log)
                            self.assertTrue(target['gatePassed'])
                        elif name == 'widget_assertion':
                            self.assertEqual(outcome['status'], 'killed', log)
                            self.assertEqual(outcome['killEvidence']['cause'], 'mixed', log)
                            self.assertEqual(outcome['killEvidence']['assertionFailures'], 1, log)
                            self.assertEqual(outcome['killEvidence']['testErrors'], 1, log)
                            self.assertTrue(target['gatePassed'])
                        else:
                            self.assertFalse(target['gatePassed'], log)
                            self.assertEqual(target['assertionScoreLowerBound'], 0, log)
                            self.assertEqual(outcome['status'],
                                             {'timeout': 'timeout', 'widget_timeout': 'timeout',
                                              'crash': 'error'}.get(name, 'killed'), log)
            finally:
                evidence = os.environ.get('CONNECTANUM_FLUTTER_MUTATION_EVIDENCE')
                if not evidence and (base := os.environ.get('CONNECTANUM_FLUTTER_MUTATION_EVIDENCE_ROOT')):
                    evidence = str(Path(base) / f'{platform}-{compiler}')
                if evidence and output.exists():
                    shutil.copytree(output, evidence)
                    shutil.copy2(config, Path(evidence) / 'fixture-config.json')
                    shutil.copy2(__file__, Path(evidence) / 'fixture-driver.py')
                    shutil.copy2(Path(__file__).with_name('flutter_mutation_test_config.dart.txt'),
                                 Path(evidence) / 'flutter-reporter.dart.txt')


if __name__ == '__main__':
    unittest.main()
