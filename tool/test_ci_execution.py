#!/usr/bin/env python3
"""Execution contracts for CI sharing and complete mutation shards."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
import re
import platform
import unittest
from unittest.mock import patch

import ci_native_artifact
import merge_dart_mutation_shards as merger

import run_dart_mutations as runner

ROOT = Path(__file__).resolve().parents[1]


class CompositeSetupTests(unittest.TestCase):
    def test_nested_dart_setup_does_not_register_a_matcher_from_the_parent_path(self):
        action = (ROOT / '.github/actions/setup-ci/action.yml').read_text()
        dart_step = action.split('uses: dart-lang/setup-dart@v1', 1)[1].split(
            '    - ', 1)[0]
        # setup-dart defaults to true and resolves dart-analyzer.json relative to
        # the parent composite's GITHUB_ACTION_PATH, where it does not exist.
        # Explicitly opting out prevents a runner error before any checks run.
        self.assertRegex(dart_step, r"(?m)^\s+problem-matcher:\s*'false'\s*$")
        self.assertIn('sdk: 3.13.1', dart_step)
        fast = (ROOT / 'bin/test-ci-fast').read_text()
        self.assertIn('dart analyze', fast)
        self.assertIn('set -euo pipefail', fast)


class ShardingTests(unittest.TestCase):
    def inventory(self, count=23):
        return [{'file': 'packages/fixture/lib/a.dart', 'offset': index,
                 'length': 1, 'original': '+', 'replacement': '-', 'operator': 'binary'}
                for index in range(count)]

    def test_shards_are_balanced_complete_disjoint_and_order_independent(self):
        mutations = self.inventory()
        shards = [runner.partition_mutations(mutations, index, 6) for index in range(6)]
        self.assertEqual(sum(map(len, shards)), len(mutations))
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 1)
        self.assertEqual({runner.mutation_id(m) for part in shards for m in part},
                         {runner.mutation_id(m) for m in mutations})
        self.assertEqual(shards, [runner.partition_mutations(list(reversed(mutations)), i, 6)
                                  for i in range(6)])

    def test_invalid_or_duplicate_inventory_is_rejected(self):
        for index, count in ((-1, 6), (6, 6), (0, 0), (True, 6)):
            with self.subTest(index=index, count=count), self.assertRaises(ValueError):
                runner.partition_mutations(self.inventory(), index, count)
        with self.assertRaises(ValueError):
            runner.partition_mutations(self.inventory() * 2, 0, 6)


    def test_main_shards_execute_baselines_and_defer_score_until_aggregation(self):
        import sys
        source = 'bool a = true; bool b = true;'
        file = 'packages/fixture/lib/a.dart'
        mutations = [{'file': file, 'offset': offset, 'length': 4, 'line': 1,
                      'original': 'true', 'replacement': 'false', 'operator': 'boolean'}
                     for offset in (9, 24)]
        passed = '\n'.join(json.dumps(e) for e in (
            {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success'},
            {'type': 'done', 'success': True}))
        calls = []
        def snapshot(work, support_files):
            for name, text in ((file, source), ('packages/fixture/test/a_test.dart', 'contract')):
                path = work / name; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
        def execute(command, cwd, timeout):
            if command[1:3] == ['pub', 'get']: return 0, ''
            if command[1] == 'tool/dart_mutations.dart': return 0, json.dumps(mutations)
            calls.append((cwd / file).read_text())
            return 0, passed  # intentional survivors: a shard must not enforce a separate floor
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / 'config.json'
            config.write_text(json.dumps({'fixture': {'sources': [file],
                'tests': ['packages/fixture/test/a_test.dart']}}))
            equivalents = root / 'equivalents.json'; equivalents.write_text('{}')
            for index in range(2):
                args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                    '--output', str(root / str(index)), '--target', 'fixture',
                    '--shard-index', str(index), '--shard-count', '2']
                with patch.object(sys, 'argv', args), patch.object(runner, 'snapshot', snapshot), \
                     patch.object(runner, 'run', execute), \
                     patch.object(runner.subprocess, 'check_output', return_value='commit'):
                    self.assertEqual(runner.main(), 0)
                report = json.loads((root / str(index) / 'mutation-report.json').read_text())
                self.assertTrue(report['shardComplete'])
                self.assertFalse(report['complete'])
                self.assertIsNone(report['gate']['passed'])
                self.assertEqual(report['targets']['fixture']['inventory'], mutations)
                self.assertEqual(len(report['targets']['fixture']['outcomes']), 1)
                self.assertEqual(calls[-3], source)
                self.assertEqual(calls[-1], source)
                self.assertNotEqual(calls[-2], source)


class RequiredGateTests(unittest.TestCase):
    def execute(self, needs):
        return subprocess.run(['python3', str(ROOT / 'tool/check_ci_needs.py')],
            env=dict(os.environ, CONNECTANUM_CI_NEEDS=json.dumps(needs)),
            capture_output=True, text=True, timeout=10)

    def test_required_gate_accepts_only_complete_success(self):
        names = ('fast', 'verification', 'wamp-app', 'flatbuffers-binding', 'native-memory',
                 'mutation-gates', 'mcp-mutations', 'browser-coverage')
        needs = {name: {'result': 'success'} for name in names}
        self.assertEqual(self.execute(needs).returncode, 0)
        for status in ('failure', 'skipped', 'cancelled', 'pending', None):
            broken = copy.deepcopy(needs)
            broken['verification']['result'] = status
            with self.subTest(status=status):
                self.assertNotEqual(self.execute(broken).returncode, 0)
        for broken in ({}, {k: v for k, v in needs.items() if k != 'mcp-mutations'}):
            self.assertNotEqual(self.execute(broken).returncode, 0)


class AggregateTests(unittest.TestCase):
    def fixture(self, root, survivor=None):
        inventory = ShardingTests().inventory(20)
        passed = '\n'.join(json.dumps(e) for e in (
            {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success'},
            {'type': 'done', 'success': True}))
        killed = '\n'.join(json.dumps(e) for e in (
            {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
            {'type': 'error', 'testID': 1, 'isFailure': True, 'error': 'Expected true'},
            {'type': 'testDone', 'testID': 1, 'result': 'failure'},
            {'type': 'done', 'success': False}))
        digest = lambda text: runner.hashlib.sha256(text.encode()).hexdigest()
        target = {'sources': ['fixture'], 'tests': ['contract'], 'generated': 20,
                  'selected': 20, 'inventory': inventory, 'equivalenceReasons': {}}
        expected = {'schemaVersion': 1, 'scope': ['fixture'], 'commit': 'same-commit',
                    'executionTimeoutSeconds': 45, 'targets': {'fixture': target},
                    'complete': False, 'baselineOnly': False,
                    'gate': {'metric': 'adjustedAssertionScoreLowerBound', 'threshold': 95,
                             'passed': None}}
        paths = []
        for index in range(6):
            directory = root / str(index)
            directory.mkdir()
            assigned = runner.partition_mutations(inventory, index, 6)
            outcomes = []
            for mutation in assigned:
                identifier = runner.mutation_id(mutation)
                status = 'survived' if identifier == survivor else 'killed'
                log = passed if status == 'survived' else killed
                log_name = identifier + '.log'
                (directory / log_name).write_text(log)
                outcomes.append({**mutation, 'id': identifier, 'status': status,
                                 'log': log_name, 'logSha256': digest(log),
                                 'mutationInputUnchanged': True,
                                 'exitCode': 0 if status == 'survived' else 1})
                if status == 'killed':
                    outcomes[-1]['killEvidence'] = runner.kill_evidence(status, log)
            result = {**target, 'assigned': len(assigned), 'outcomes': outcomes}
            for name, label in (('baseline', 'baseline'), ('restoredBaseline', 'restored-baseline')):
                result.update({name: 'survived', name + 'ExitCode': 0,
                               name + 'LogSha256': digest(passed)})
                (directory / f'fixture-{label}.log').write_text(passed)
            report = {**expected, 'targets': {'fixture': result},
                      'shard': {'index': index, 'count': 6}, 'shardComplete': True}
            path = directory / 'mutation-report.json'
            path.write_text(json.dumps(report))
            paths.append(path)
        return paths, expected

    def test_complete_union_uses_global_score_not_per_shard_floor(self):
        with tempfile.TemporaryDirectory() as temp:
            survivor = runner.mutation_id(ShardingTests().inventory(20)[0])
            paths, expected = self.fixture(Path(temp), survivor)
            report = merger.merge(paths, expected, 6)
            self.assertTrue(report['complete'])
            self.assertTrue(report['gate']['passed'])
            self.assertEqual(report['targets']['fixture']['adjustedAssertionScoreLowerBound'], 95)
            self.assertEqual(len(report['targets']['fixture']['outcomes']), 20)
            self.assertEqual(report['targets']['fixture']['baseline'], 'survived')
            self.assertEqual(report['targets']['fixture']['restoredBaseline'], 'survived')
            self.assertEqual(len(report['targets']['fixture']['shardBaselineEvidence']), 12)
            expected['gate']['threshold'] = 95.01
            for path in paths:
                data = json.loads(path.read_text()); data['gate']['threshold'] = 95.01
                path.write_text(json.dumps(data))
            self.assertFalse(merger.merge(paths, expected, 6)['gate']['passed'])

    def test_missing_duplicate_incomplete_stale_or_corrupt_shards_fail_closed(self):
        changes = (
            lambda r: r.update(commit='stale'),
            lambda r: r.update(shardComplete=False),
            lambda r: r['shard'].update(index=1),
            lambda r: r['targets']['fixture']['outcomes'].pop(),
            lambda r: r['targets']['fixture'].update(restoredBaseline='error'),
            lambda r: r['targets']['fixture']['outcomes'][0].update(equivalence='invented'),
            lambda r: r['targets']['fixture']['outcomes'][0].update(logSha256='wrong'),
            lambda r: r['targets']['fixture']['outcomes'][0].update(id='not-assigned'),
        )
        for change in changes:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temp:
                paths, expected = self.fixture(Path(temp))
                report = json.loads(paths[0].read_text()); change(report)
                paths[0].write_text(json.dumps(report))
                with self.assertRaises(ValueError): merger.merge(paths, expected, 6)
        with tempfile.TemporaryDirectory() as temp:
            paths, expected = self.fixture(Path(temp))
            with self.assertRaises(ValueError): merger.merge(paths[:-1], expected, 6)
            with self.assertRaises(ValueError): merger.merge([paths[1], *paths[1:]], expected, 6)
            (paths[0].parent / 'fixture-baseline.log').write_text('truncated')
            with self.assertRaises(ValueError): merger.merge(paths, expected, 6)


class LaneExecutionTests(unittest.TestCase):
    def execute(self, ci, failed=''):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'bin').mkdir()
            shutil.copy2(ROOT / 'bin/test-all', root / 'bin/test-all')
            for package in ('connectanum_core', 'connectanum_client', 'connectanum_router', 'connectanum_bench'):
                (root / 'packages' / package).mkdir(parents=True)
            log = root / 'calls'
            common = 'ROOT_DIR="' + str(root) + '"\n' + r"""
log() { printf '%s\n' "$*" >> "$TASK_LOG"; }
cd_repo_root() { cd "$ROOT_DIR"; }
dart_workspace_bootstrap() { log bootstrap; }
cargo_workspace_check() { log metadata; }
native_runtime_supported() { return 0; }
cargo_with_retry() { log cargo "$@"; }
build_native_ffi_test_release() { log native-build; }
ensure_chrome_env() { return 0; }
run_command_with_timeout() { shift 2; "$@"; }
"""
            consumers = ('run_mcp_server_package_smoke', 'run_mcp_client_package_smoke',
                'run_client_consumer_package_smoke', 'run_bench_cli_consumer_package_smoke',
                'run_router_hosted_mcp_example_smoke', 'run_mcp_consumer_package_smoke',
                'run_router_cli_consumer_package_smoke')
            for name in consumers:
                common += name + '() { log ' + name + '; }\n'
            (root / 'bin/common.sh').write_text(common)
            for name in ('test-native-coverage-tools', 'test-native-mutation-tools',
                         'test-tooling', 'test-coverage'):
                path = root / 'bin' / name
                path.write_text('#!/bin/bash\nprintf "%s\\n" "' + name + '" >> "$TASK_LOG"\n'
                                + '[[ "$TASK_FAILED" != "' + name + '" ]] || exit 73\n')
                path.chmod(0o755)
            for name in ('dart', 'python3'):
                path = root / name
                path.write_text('#!/bin/bash\nprintf "%s\\n" "' + name + ' $*" >> "$TASK_LOG"\n')
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       TASK_LOG=str(log), TASK_FAILED=failed, CONNECTANUM_CI_VERIFY='1' if ci else '0')
            result = subprocess.run(['bash', str(root / 'bin/test-all')], env=env,
                                    capture_output=True, text=True, timeout=10)
            return result, log.read_text().splitlines(), consumers

    def test_ci_collects_coverage_once_and_keeps_rust_and_all_consumers(self):
        result, calls, consumers = self.execute(True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.count('test-coverage'), 1)
        self.assertNotIn('test-tooling', calls)  # protected Fast Checks owns these
        self.assertFalse(any(line.startswith('dart test ') for line in calls))
        self.assertTrue(any('--features ffi-test -- --test-threads=1' in line for line in calls))
        for consumer in consumers: self.assertEqual(calls.count(consumer), 1)
        for failed in ('test-coverage', 'test-native-coverage-tools', 'test-native-mutation-tools'):
            result, calls, _ = self.execute(True, failed)
            self.assertEqual(result.returncode, 73)
            self.assertNotIn(consumers[-1], calls)

    def test_default_canonical_flow_still_runs_vm_and_browser_suites(self):
        result, calls, consumers = self.execute(False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('test-coverage', calls)
        self.assertEqual(calls.count('test-tooling'), 1)
        for package in ('connectanum_core', 'connectanum_mcp', 'connectanum'):
            self.assertIn(f'dart test packages/{package}/test', calls)
        self.assertTrue(any('-p chrome' in line for line in calls))
        for consumer in consumers: self.assertEqual(calls.count(consumer), 1)

    def test_grouping_preserves_all_34_original_targets_once(self):
        expected = set('router-authorization router-metrics-vm core-mcp-completion-vm core-mcp-completion-web core-registered-vm core-registered-web core-subscribed-vm core-subscribed-web core-metadata-vm core-metadata-web auth-server client-installer router-installer core-e2ee-vm bench-config bench-http-auth-vm core-lazy-vm core-lazy-web core-pem-pkcs8-vm core-pem-pkcs8-web client-message-binding-vm router-message-binding-vm bench-remote-auth-native mcp-library router-remote-wamp-vm router-config-loader-vm router-remote-authenticator-vm router-http-auth-vm core-scram-request-vm core-scram-request-web client-meta-cache-vm client-meta-cache-web core-base64-vm core-base64-web'.split())
        groups = json.loads((ROOT / 'tool/ci_mutation_groups.json').read_text())
        members = [target for targets in groups.values() for target in targets] + ['mcp-library']
        self.assertEqual(len(members), 34)
        self.assertEqual(set(members), expected)
        workflow = (ROOT / '.github/workflows/dart.yml').read_text()
        self.assertEqual(set(re.findall(r'- group: ([\w-]+)', workflow)), set(groups))
        needs = re.search(r'needs: \[(fast[^\]]+)\]', workflow)[1].split(', ')
        from check_ci_needs import REQUIRED
        self.assertEqual(set(needs), REQUIRED)


    def test_native_reuse_failure_propagates_even_from_a_conditional_caller(self):
        common = (ROOT / 'bin/common.sh').read_text()
        function = 'build_native_ffi_test_release() {' + common.split(
            'build_native_ffi_test_release() {', 1)[1].split('\n}', 1)[0] + '\n}'
        with tempfile.TemporaryDirectory() as temp:
            fake = Path(temp) / 'python3'
            fake.write_text('#!/bin/bash\nexit 73\n'); fake.chmod(0o755)
            env = dict(os.environ, PATH=temp + os.pathsep + os.environ['PATH'],
                       CONNECTANUM_CI_NATIVE_DIR='missing', ROOT_DIR=temp)
            command = 'set -euo pipefail\n' + function + '\n' + (
                'cargo_workspace_check() { exit 99; }\n'
                'if build_native_ffi_test_release; then exit 0; else exit 17; fi')
            result = subprocess.run(['bash', '-c', command], env=env, timeout=10)
            self.assertEqual(result.returncode, 17)


class NativeArtifactTests(unittest.TestCase):
    def test_prepare_replaces_stale_platform_library_only_from_a_valid_artifact(self):
        for system, filename in (('Linux', 'libct_ffi.so'), ('Darwin', 'libct_ffi.dylib'),
                                 ('Windows', 'ct_ffi.dll')):
            with self.subTest(system=system), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                library = root / 'built-library'; library.write_bytes(b'ffi-test')
                lock = root / 'native/transport/Cargo.lock'
                lock.parent.mkdir(parents=True); lock.write_text('resolved dependencies')
                with patch.object(ci_native_artifact, 'ROOT', root), \
                     patch.object(ci_native_artifact, 'identity', return_value={
                         'system': system, 'commit': 'fixture'}):
                    ci_native_artifact.record(root / 'artifact', library)
                    installed = root / 'native/transport/target/ffi-test/release' / filename
                    ci_native_artifact.verify(root / 'artifact')
                    self.assertFalse(installed.exists())  # verify stays read-only
                    self.assertEqual(ci_native_artifact.verify(root / 'artifact', prepare=True),
                                     installed.resolve())
                    self.assertEqual(installed.read_bytes(), b'ffi-test')
                    installed.write_bytes(b'stale build')
                    ci_native_artifact.verify(root / 'artifact', prepare=True)
                    self.assertEqual(installed.read_bytes(), b'ffi-test')
                    installed.write_bytes(b'leave untouched on invalid input')
                    (root / 'artifact/libct_ffi.so').write_bytes(b'corrupt')
                    with self.assertRaises(ValueError):
                        ci_native_artifact.verify(root / 'artifact', prepare=True)
                    self.assertEqual(installed.read_bytes(), b'leave untouched on invalid input')
                    self.assertEqual(list(installed.parent.glob(f'.{filename}.*')), [])

    @unittest.skipUnless(shutil.which('dart') and platform.system() in ('Linux', 'Darwin'),
                         'requires Dart and a supported native benchmark platform')
    def test_prepared_artifact_is_discovered_when_benchmarks_remove_the_override(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            package = root / 'packages/connectanum_bench'
            package.mkdir(parents=True)
            shutil.copy2(ROOT / 'packages/connectanum_bench/test/support/native_library.dart',
                         package / 'native_library.dart')
            probe = package / 'probe.dart'
            probe.write_text("import 'native_library.dart';\n"
                             "void main() { final path = nativeBenchTestLibrary();\n"
                             "  if (path == null) throw StateError('Native library missing');\n"
                             "  print(path); }\n")
            library = root / 'built-library'; library.write_bytes(b'ffi-test')
            lock = root / 'native/transport/Cargo.lock'
            lock.parent.mkdir(parents=True); lock.write_text('resolved dependencies')
            with patch.object(ci_native_artifact, 'ROOT', root), \
                 patch.object(ci_native_artifact, 'identity', return_value={
                     'system': platform.system(), 'commit': 'fixture'}):
                ci_native_artifact.record(root / 'artifact', library)
                ci_native_artifact.verify(root / 'artifact', prepare=True)
            env = dict(os.environ)
            env.pop('CONNECTANUM_NATIVE_LIB', None)
            result = subprocess.run(['dart', str(probe)], cwd=package, env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.strip()).read_bytes(), b'ffi-test')

    def test_reuse_rejects_different_source_flags_commit_toolchain_or_binary(self):
        identity = {'commit': 'head', 'sourceHashes': {'native.rs': 'source'},
                    'rustc': 'rust fixture', 'features': ['ffi-test'], 'profile': 'release',
                    'rustflags': '', 'system': 'Linux', 'machine': 'x86_64'}
        with tempfile.TemporaryDirectory() as temp, patch.object(ci_native_artifact, 'identity', return_value=identity):
            root = Path(temp); lib = root / 'library'; lib.write_bytes(b'ffi-test')
            native_lock = root / 'native/transport/Cargo.lock'
            native_lock.parent.mkdir(parents=True); native_lock.write_text('resolved dependencies')
            self.addCleanup(patch.stopall)
            patch.object(ci_native_artifact, 'ROOT', root).start()
            ci_native_artifact.record(root / 'artifact', lib)
            self.assertEqual(ci_native_artifact.verify(root / 'artifact').read_bytes(), b'ffi-test')
            native_lock.unlink()
            with self.assertRaises(ValueError): ci_native_artifact.verify(root / 'artifact')
            ci_native_artifact.verify(root / 'artifact', prepare=True)
            self.assertEqual(native_lock.read_text(), 'resolved dependencies')
            native_lock.write_text('different dependencies')
            with self.assertRaises(ValueError): ci_native_artifact.verify(root / 'artifact')
            native_lock.write_text('resolved dependencies')
            manifest = root / 'artifact/manifest.json'
            original = manifest.read_text()
            for key in ('commit', 'sourceHashes', 'rustc', 'features', 'profile', 'rustflags', 'machine'):
                changed = json.loads(original); changed[key] = 'different'
                manifest.write_text(json.dumps(changed))
                with self.subTest(key=key), self.assertRaises(ValueError):
                    ci_native_artifact.verify(root / 'artifact')
            manifest.write_text(original)
            (root / 'artifact/libct_ffi.so').write_bytes(b'production-or-corrupt')
            with self.assertRaises(ValueError): ci_native_artifact.verify(root / 'artifact')


if __name__ == '__main__':
    unittest.main()
