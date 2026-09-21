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
import audit_mutation_kill_evidence as evidence_audit

sys.path.insert(0, str(Path(__file__).parent))
from run_dart_mutations import apply_mutation, classify, mutation_id, run, summarize, validate_equivalents


def events(*items):
    return '\n'.join(json.dumps(item) for item in items)


def write_reporter_fixture_dependencies(work):
    (work / 'pubspec.yaml').write_text(
        "name: mutation_oracle_fixture\nenvironment:\n  sdk: ^3.10.0\n"
        "dev_dependencies:\n  test: any\n")
    # Offline fixtures must use the dependencies bootstrap actually resolved.
    (work / 'pubspec.lock').write_bytes((runner.ROOT / 'pubspec.lock').read_bytes())


class MutationRunnerTests(unittest.TestCase):
    def test_http_context_target_covers_complete_source_and_native_integration(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        self.assertIn('router-http-context-vm', targets)
        target = targets['router-http-context-vm']
        self.assertEqual(target['sources'], [
            'packages/connectanum_router/lib/src/router/http/http_context.dart'])
        self.assertEqual(set(target['tests']), {
            'packages/connectanum_router/test/http_context_regression_test.dart',
            'packages/connectanum_router/test/http_snapshot_metadata_regression_test.dart',
            'packages/connectanum_router/test/http_response_transition_regression_test.dart',
            'packages/connectanum_router/test/native_http_request_body_test.dart',
            'packages/connectanum_router/test/router_runtime_test.dart',
            'packages/connectanum_router/test/router_integration_native_test.dart'})
        self.assertTrue(target['requiresNativeLibrary'])
        self.assertTrue(target['isolateTestFiles'])
        self.assertEqual(target['testRoot'], 'packages/connectanum_router')
        self.assertIn('packages/connectanum_router/test/support/native_lib.dart',
                      target['supportFiles'])
        for name in ('http3_cert.pem', 'http3_key.pem', 'http3_ca_cert.pem'):
            self.assertIn(f'packages/connectanum_router/test/certs/{name}',
                          target['supportFiles'])
        self.assertNotIn('testName', target)
        self.assertNotIn('threshold', target)

    def test_workload_diagnostics_are_registered_and_hashed(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['bench-wamp-workload-vm']
        suite = runner.ROOT / target['tests'][0]
        self.assertIn(
            'packages/connectanum_bench/test/wamp_workload_diagnostics_regression_test.dart',
            target['supportFiles'])
        self.assertRegex(
            suite.read_text(),
            r"import '\.\./wamp_workload_diagnostics_regression_test\.dart'\s+as workload_diagnostics;",
        )
        self.assertIn('workload_diagnostics.main', suite.read_text())

    def test_mcp_discovery_target_includes_full_source_and_consumer_tests(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        self.assertIn('client-mcp-discovery-vm', targets)
        target = targets['client-mcp-discovery-vm']
        self.assertEqual(target['sources'], [
            'packages/connectanum_client/lib/src/mcp/authorization_discovery.dart'])
        self.assertEqual(target['tests'], ['packages/connectanum_client/test/mcp'])
        self.assertNotIn('testName', target)
        self.assertNotIn('threshold', target)

    def test_oauth_token_exchange_target_includes_full_source_and_consumer_tests(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        self.assertIn('client-oauth-token-exchange-vm', targets)
        target = targets['client-oauth-token-exchange-vm']
        self.assertEqual(target['sources'], [
            'packages/connectanum_client/lib/src/mcp/oauth_token_exchange.dart'])
        self.assertEqual(target['tests'], ['packages/connectanum_client/test/mcp'])
        self.assertNotIn('testName', target)
        self.assertNotIn('threshold', target)

    def test_reporter_fixture_reuses_workspace_lock_not_a_local_test_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / 'workspace'
            work = root / 'fixture'
            workspace.mkdir()
            work.mkdir()
            for version in ('1.31.2', '1.32.0'):
                with self.subTest(version=version):
                    lock = (f'packages:\n  test:\n    version: "{version}"\n'
                            '  test_api:\n    version: "0.7.14"\n')
                    (workspace / 'pubspec.lock').write_text(lock)
                    with patch.object(runner, 'ROOT', workspace):
                        write_reporter_fixture_dependencies(work)
                    self.assertEqual((work / 'pubspec.lock').read_text(), lock)
                    manifest = (work / 'pubspec.yaml').read_text()
                    self.assertIn('  test: any\n', manifest)
                    self.assertNotIn(version, manifest)

    def test_http_auth_target_is_complete_and_required_in_ci(self):
        target = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())['router-http-auth-vm']
        self.assertEqual(target['sources'], [
            'packages/connectanum_router/lib/src/router/auth/http_auth_provider.dart'])
        self.assertEqual(set(target['tests']), {
            'packages/connectanum_router/test/http_auth_provider_test.dart',
            'packages/connectanum_router/test/http_auth_provider_regression_test.dart',
            'packages/connectanum_router/test/http_auth_claim_matching_test.dart'})
        workflow = (runner.ROOT / '.github/workflows/dart.yml').read_text()
        matrix = workflow.split('target: [', 1)[1].split(']', 1)[0]
        self.assertIn('router-http-auth-vm', [item.strip() for item in matrix.split(',')])
        audit = (runner.ROOT / 'bin/audit-github-deployment-chain').read_text()
        self.assertIn("'router-http-auth-vm Mutation Gate'", audit)

    def test_saved_kill_audit_is_pinned_and_never_overwrites_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = events(
                {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                {'type': 'error', 'testID': 1, 'isFailure': False, 'error': 'bad state'},
                {'type': 'testDone', 'testID': 1, 'result': 'error'},
                {'type': 'done', 'success': False},
            )
            (root / 'mutant.log').write_text(log)
            original = {'schemaVersion': 1, 'complete': False, 'runnerSha256': 'historical',
                        'targets': {'fixture': {'generated': 2, 'score': 100,
                            'sourceHashes': {'lib/source.dart': 'original'},
                            'outcomes': [{'id': 'mutant', 'status': 'killed',
                                          'exitCode': 1, 'log': 'mutant.log'}]}}}
            source = root / 'mutation-report.json'
            source.write_text(json.dumps(original))
            initial_bytes = source.read_bytes()
            output = root / 'kill-evidence.json'
            with patch.object(sys, 'argv', ['audit', str(source), '--output', str(output)]):
                self.assertEqual(evidence_audit.main(), 0)
                with self.assertRaises(FileExistsError):
                    evidence_audit.main()
            result = json.loads(output.read_text())
            self.assertEqual(source.read_bytes(), initial_bytes)
            self.assertEqual((root / 'mutant.log').read_text(), log)
            self.assertFalse(result['complete'])
            self.assertEqual(result['runnerSha256'], 'historical')
            self.assertEqual(result['targets']['fixture']['sourceHashes'], {'lib/source.dart': 'original'})
            self.assertEqual(result['targets']['fixture']['score'], 100)
            self.assertEqual(result['targets']['fixture']['assertionScoreLowerBound'], 0)
            self.assertEqual(result['targets']['fixture']['killCauseCounts']['testError'], 1)
            self.assertEqual(result['killEvidenceAudit']['sourceReportSha256'],
                             runner.hashlib.sha256(initial_bytes).hexdigest())
            self.assertEqual(result['targets']['fixture']['outcomes'][0]['logSha256'],
                             runner.hashlib.sha256(log.encode()).hexdigest())
            with self.assertRaisesRegex(ValueError, 'original campaign'):
                evidence_audit.audit(output)
            for filename in ('../mutant.log', str(root / 'mutant.log'), 'missing.log'):
                original['targets']['fixture']['outcomes'][0]['log'] = filename
                source.write_text(json.dumps(original))
                with self.assertRaises((ValueError, FileNotFoundError)):
                    evidence_audit.audit(source)

    def test_saved_kill_audit_rejects_crashes_and_inconsistent_scores(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = {'schemaVersion': 1, 'targets': {'fixture': {'score': 100,
                'outcomes': [{'id': 'mutant', 'status': 'killed', 'exitCode': -9,
                              'log': 'mutant.log'}]}}}
            source = root / 'mutation-report.json'
            (root / 'mutant.log').write_text('crashed')
            source.write_text(json.dumps(original))
            for reclassify_deadlines in (False, True):
                with self.subTest(reclassify_deadlines=reclassify_deadlines):
                    with self.assertRaisesRegex(ValueError, 'saved kill classifies as error'):
                        evidence_audit.audit(source, reclassify_deadlines=reclassify_deadlines)
            original['targets']['fixture']['outcomes'] = [{'status': 'survived'}]
            source.write_text(json.dumps(original))
            with self.assertRaisesRegex(ValueError, 'saved score'):
                evidence_audit.audit(source)

    def test_saved_kill_audit_rejects_symlink_logs_outside_report_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reports = root / 'reports'
            reports.mkdir()
            external = root / 'private.log'
            external.write_text('must not be read as mutation evidence')
            (reports / 'linked.log').symlink_to(external)
            source = reports / 'report.json'
            source.write_text(json.dumps({'schemaVersion': 1, 'targets': {'fixture': {
                'outcomes': [{'id': 'mutant', 'status': 'killed', 'exitCode': 1,
                              'log': 'linked.log'}]}}}))
            with self.assertRaisesRegex(ValueError, 'escapes report directory'):
                evidence_audit.audit(source)

    def test_kill_evidence_distinguishes_assertions_errors_and_missing_events(self):
        for flags, cause in (([True], 'assertion'), ([False], 'testError'),
                             ([True, False], 'mixed'), ([None], 'unknown'),
                             ([], 'unknown'), (['true'], 'unknown')):
            with self.subTest(flags=flags):
                output = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                    *({'type': 'error', 'testID': 1, 'error': 'failure',
                       'isFailure': flag} for flag in flags),
                    {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                    {'type': 'done', 'success': False},
                )
                evidence = runner.kill_evidence('killed', output)
                self.assertEqual(evidence['cause'], cause)
                self.assertEqual(evidence['assertionFailures'], flags.count(True))
                self.assertEqual(evidence['testErrors'], flags.count(False))
        for status in ('survived', 'timeout', 'error', 'compileError'):
            self.assertIsNone(runner.kill_evidence(status, output))

    def test_kill_evidence_does_not_credit_unrelated_or_hidden_errors(self):
        output = events(
            {'type': 'testStart', 'test': {'id': 1, 'name': 'passed contract'}},
            {'type': 'error', 'testID': 1, 'isFailure': True},
            {'type': 'testDone', 'testID': 1, 'result': 'success'},
            {'type': 'testStart', 'test': {'id': 2, 'name': 'failed contract'}},
            {'type': 'error', 'testID': 2, 'isFailure': False},
            {'type': 'testDone', 'testID': 2, 'result': 'error'},
            {'type': 'error', 'testID': 100, 'isFailure': True},
            {'type': 'testStart', 'test': {'id': 3, 'name': 'hidden'}},
            {'type': 'error', 'testID': 3, 'isFailure': True},
            {'type': 'testDone', 'testID': 3, 'result': 'failure', 'hidden': True},
            {'type': 'done', 'success': False},
        )
        self.assertEqual(runner.kill_evidence('killed', output), {
            'cause': 'testError', 'assertionFailures': 0, 'testErrors': 1,
            'unclassifiedFailures': 0,
        })

    def test_kill_evidence_resets_test_ids_between_isolated_commands(self):
        output = events(
            {'type': 'connectanumTestCommand', 'status': 'survived'},
            {'type': 'testStart', 'test': {'id': 1, 'name': 'previous contract'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success'},
            {'type': 'done', 'success': True},
            {'type': 'connectanumTestCommand', 'status': 'killed'},
            {'type': 'testStart', 'test': {'id': 1, 'name': 'current contract'}},
            {'type': 'error', 'testID': 1, 'isFailure': True},
            {'type': 'testDone', 'testID': 1, 'result': 'failure'},
            {'type': 'done', 'success': False},
        )
        self.assertEqual(runner.kill_evidence('killed', output)['cause'], 'assertion')
        self.assertEqual(runner.kill_evidence('killed', output)['assertionFailures'], 1)

    def test_assertion_diagnostics_preserve_conventional_denominator(self):
        outcomes = [
            {'status': 'killed', 'killEvidence': {'cause': cause}}
            for cause in ('assertion', 'testError', 'mixed')
        ] + [{'status': 'killed'}, {'status': 'survived', 'equivalence': 'justified'},
             {'status': 'timeout'}, {'status': 'error'}, {'status': 'compileError'}]
        summary = summarize(outcomes)
        self.assertEqual(summary['viable'], 7)
        self.assertAlmostEqual(summary['score'], 400 / 7)
        self.assertAlmostEqual(summary['adjustedScore'], 400 / 6)
        self.assertEqual(summary['killCauseCounts'], {
            'assertion': 1, 'testError': 1, 'mixed': 1, 'unknown': 1,
        })
        self.assertFalse(summary['killEvidenceComplete'])
        self.assertAlmostEqual(summary['assertionScoreLowerBound'], 200 / 7)
        self.assertAlmostEqual(summary['adjustedAssertionScoreLowerBound'], 200 / 6)

    def test_snapshot_preserves_standalone_application_inputs_and_ignored_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'repo'
            destination = Path(directory) / 'snapshot'
            contents = {
                'pubspec.yaml': b'workspace: []',
                'examples/wamp_app/shared/pubspec.yaml': b'name: protocol',
                'examples/wamp_app/shared/pubspec.lock': b'pinned protocol dependencies',
                'examples/wamp_app/shared/lib/a.dart': b'bool f() => true;',
                'examples/wamp_app/shared/test/a_test.dart': b'test oracle',
                'examples/wamp_app/server/pubspec.yaml': b'name: server',
                'examples/wamp_app/client/pubspec.yaml': b'name: client',
                'examples/wamp_app/unrelated/secret.txt': b'not a component',
            }
            for name, data in contents.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            listed = '\0'.join(name for name in contents if not name.endswith('.lock')).encode()
            with patch.object(runner, 'ROOT', root), \
                 patch.object(runner.subprocess, 'check_output', return_value=listed):
                runner.snapshot(destination)
            for name, data in contents.items():
                if '/unrelated/' in name:
                    self.assertFalse((destination / name).exists())
                else:
                    self.assertEqual((destination / name).read_bytes(), data)
            (destination / 'examples/wamp_app/shared/lib/a.dart').write_text('changed')
            self.assertEqual((root / 'examples/wamp_app/shared/lib/a.dart').read_bytes(),
                             b'bool f() => true;')

    def test_snapshot_copies_only_declared_external_support_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'repo'
            destination = Path(directory) / 'snapshot'
            contents = {
                'packages/core/lib/a.dart': b'bool f() => true;',
                'examples/quickstart/router.yaml': b'realms: [public]\n',
                'examples/unrelated.yaml': b'unrelated',
                'pubspec.lock': b'pinned dependencies',
            }
            for name, data in contents.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            listed = '\0'.join(name for name in contents if name != 'pubspec.lock').encode()
            with patch.object(runner, 'ROOT', root), \
                 patch.object(runner.subprocess, 'check_output', return_value=listed):
                runner.snapshot(destination, ['examples/quickstart/router.yaml'])
            self.assertEqual(sorted(str(path.relative_to(destination))
                                    for path in destination.rglob('*') if path.is_file()),
                             ['examples/quickstart/router.yaml', 'packages/core/lib/a.dart',
                              'pubspec.lock'])
            for name in ('examples/quickstart/router.yaml', 'packages/core/lib/a.dart', 'pubspec.lock'):
                self.assertEqual((destination / name).read_bytes(), contents[name])
            (destination / 'examples/quickstart/router.yaml').write_text('mutated')
            self.assertEqual((root / 'examples/quickstart/router.yaml').read_bytes(),
                             contents['examples/quickstart/router.yaml'])

    def test_snapshot_rejects_invalid_missing_and_unlisted_support_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'repo'
            root.mkdir()
            (root / 'ignored.yaml').write_text('not an input')
            for name in ('', '.', '../outside.yaml', str(root / 'ignored.yaml'),
                         'missing.yaml', 'ignored.yaml', 'directory', None, 42):
                with self.subTest(name=name), patch.object(runner, 'ROOT', root), \
                     patch.object(runner.subprocess, 'check_output',
                                  return_value=b'missing.yaml\0directory\0'):
                    (root / 'directory').mkdir(exist_ok=True)
                    with self.assertRaisesRegex(ValueError, 'support file'):
                        runner.snapshot(Path(directory) / 'snapshot', [name])

    def test_snapshot_rejects_ignored_application_lockfile_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'repo'
            package = root / 'examples/wamp_app/shared'
            package.mkdir(parents=True)
            (package / 'pubspec.lock').symlink_to(Path(directory) / 'outside.lock')
            with patch.object(runner, 'ROOT', root), \
                 patch.object(runner.subprocess, 'check_output', return_value=b''):
                with self.assertRaisesRegex(ValueError, 'symlink'):
                    runner.snapshot(Path(directory) / 'snapshot')

    def test_application_target_inventories_every_shared_production_file(self):
        target = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())['app-shared-vm']
        actual = {str(path.relative_to(runner.ROOT))
                  for path in (runner.ROOT / 'examples/wamp_app/shared/lib').rglob('*.dart')}
        self.assertEqual(set(target['sources']), actual)
        self.assertEqual(len(target['sources']), len(actual))
        self.assertEqual(target['tests'], ['examples/wamp_app/shared/test'])
        self.assertEqual(target['testRoot'], 'examples/wamp_app/shared')

    def test_mcp_library_target_keeps_complete_component_and_package_scope(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        policy = json.loads((runner.ROOT / 'tool/coverage_policy.json').read_text())
        target = targets['mcp-library']
        cli = 'packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart'
        actual = {str(path.relative_to(runner.ROOT))
                  for path in (runner.ROOT / 'packages/connectanum_mcp/lib/src').rglob('*.dart')}
        self.assertEqual(set(target['sources']), actual - {cli})
        self.assertEqual(len(target['sources']), len(actual) - 1)
        self.assertEqual(set(target['sources']),
                         set(policy['components']['connectanum_mcp_library']['sources']))
        self.assertEqual(set(targets['mcp']['sources']), actual)
        self.assertEqual(target['tests'], ['packages/connectanum_mcp/test'])
        self.assertIn(cli, targets['mcp-cli-native']['sources'])
        self.assertTrue(targets['mcp-cli-native']['requiresNativeLibrary'])

    def test_pem_pkcs8_targets_share_tests_and_record_key_fixtures(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        for runtime in ('vm', 'web'):
            with self.subTest(runtime=runtime):
                target = targets[f'core-pem-pkcs8-{runtime}']
                self.assertEqual(set(target['sources']), {
                    'packages/connectanum_core/lib/src/authentication/cryptosign/pem.dart',
                    'packages/connectanum_core/lib/src/authentication/cryptosign/pkcs8.dart',
                })
                self.assertEqual(target['tests'], [
                    'packages/connectanum_core/test/authentication/cryptosign_authentication_test.dart',
                    'packages/connectanum_core/test/authentication/cryptosign/key_file_boundaries_test.dart',
                ])
                self.assertIn('packages/connectanum_core/test/authentication/cryptosign/keys.dart',
                              target['supportFiles'])
                self.assertEqual(target.get('platform', 'vm'),
                                 'chrome' if runtime == 'web' else 'vm')

    def test_serializer_targets_hash_and_execute_independent_ppt_regressions(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        prefix = 'packages/connectanum_core/test'
        suites = {
            'serializer_inbound_metadata_test.dart': 'inbound_metadata',
            'serializer_ppt_fragment_precedence_test.dart': 'ppt_fragments',
        }
        wrapper = (runner.ROOT / prefix / 'support/serializer_mutation_suite.dart').read_text()
        for filename, alias in suites.items():
            self.assertIn(f"import '../serializer/{filename}'", wrapper)
            self.assertRegex(wrapper, rf"group\('[^']+', {alias}\.main\);")
            for name in ('core-msgpack-serializer-vm', 'core-cbor-serializer-vm',
                         'core-cbor-serializer-web', 'core-msgpack-serializer-web'):
                with self.subTest(target=name, suite=filename):
                    self.assertIn(f'{prefix}/serializer/{filename}',
                                  targets[name]['supportFiles'])

    def test_lazy_payload_targets_include_contract_suite_on_both_runtimes(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        prefix = 'packages/connectanum_core'
        suites = [f'{prefix}/test/message_{name}_test.dart' for name in [
            'payload_contract', 'lazy_payload_regression', 'invocation', 'result',
        ]]
        for runtime in ['vm', 'web']:
            self.assertEqual(targets[f'core-lazy-{runtime}']['supportFiles'], suites)
        self.assertEqual(targets['core-lazy-vm']['tests'], [
            f'{prefix}/test/support/lazy_payload_vm_mutation_suite.dart',
        ])
        vm_wrapper = (runner.ROOT / targets['core-lazy-vm']['tests'][0]).read_text()
        self.assertIn("group('payload contract', payload_contract.main);", vm_wrapper)
        self.assertLess(vm_wrapper.index("group('payload contract'"),
                        vm_wrapper.index("group('lazy payload'"))
        browser = targets['core-lazy-web']
        self.assertEqual(browser['tests'], [
            f'{prefix}/test/support/lazy_payload_mutation_suite.dart',
        ])
        self.assertEqual(browser['platform'], 'chrome')
        wrapper = (runner.ROOT / browser['tests'][0]).read_text()
        self.assertIn("import '../message_payload_contract_test.dart' as payload_contract;", wrapper)
        self.assertIn("group('payload contract', payload_contract.main);", wrapper)

    def test_native_binding_targets_inventory_sources_tests_and_shared_oracles(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        for package, directory in [('client', 'transport/native'), ('router', 'native')]:
            with self.subTest(package=package):
                target = targets[f'{package}-message-binding-vm']
                prefix = f'packages/connectanum_{package}'
                self.assertEqual(target['sources'], [
                    f'{prefix}/lib/src/{directory}/message_binding.dart',
                ])
                self.assertEqual(target['tests'], [
                    f'{prefix}/test/{directory}/message_binding_test.dart',
                ])
                self.assertIn(
                    'packages/connectanum_core/test/support/native_role_contract.dart',
                    target['supportFiles'],
                )
                self.assertEqual(target.get('platform', 'vm'), 'vm')

    def test_remote_auth_benchmark_target_includes_native_and_certificate_inputs(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['bench-remote-auth-native']
        prefix = 'packages/connectanum_bench'
        self.assertEqual(target['sources'], [
            f'{prefix}/lib/src/remote_auth_bench_harness.dart',
        ])
        self.assertEqual(set(target['tests']), {
            f'{prefix}/test/remote_auth_bench_harness_test.dart',
            f'{prefix}/test/remote_auth_bench_harness_integration_test.dart',
        })
        self.assertEqual(set(target['supportFiles']), {
            f'packages/connectanum_router/test/certs/remote_auth_{name}.pem'
            for name in ['ca_cert', 'server_cert', 'server_key',
                         'client_cert', 'client_key']
        })
        self.assertTrue(target['requiresNativeLibrary'])
        self.assertTrue(target['isolateTestFiles'])
        self.assertEqual(target['testRoot'], prefix)

    def test_remote_authenticator_target_includes_direct_and_worker_regressions(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['router-remote-authenticator-vm']
        prefix = 'packages/connectanum_router'
        self.assertEqual(target['sources'], [
            f'{prefix}/lib/src/router/auth/remote_authenticator.dart',
        ])
        self.assertEqual(set(target['tests']), {
            f'{prefix}/test/remote_authenticator_test.dart',
            f'{prefix}/test/router_worker_auth_test.dart',
        })

    def test_router_config_target_covers_loader_and_validation_inputs(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['router-config-loader-vm']
        prefix = 'packages/connectanum_router'
        self.assertEqual(target['sources'], [
            f'{prefix}/lib/src/router/config/router_config_loader.dart',
        ])
        self.assertEqual(set(target['tests']), {
            f'{prefix}/test/router_config_loader_test.dart',
            f'{prefix}/test/router_config_loader_validation_test.dart',
            f'{prefix}/test/router_json_test.dart',
            f'{prefix}/test/router_settings_regression_test.dart',
            f'{prefix}/test/router_settings_open_metrics_regression_test.dart',
        })
        self.assertEqual(target['supportFiles'], [
            'examples/quickstart/router.yaml',
            'packages/connectanum_router/test/support/config_assertions.dart',
        ])

    def test_remote_wamp_target_covers_whole_delegate_and_wire_fixtures(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['router-remote-wamp-vm']
        prefix = 'packages/connectanum_router'
        self.assertEqual(target['sources'], [
            f'{prefix}/lib/src/router/auth/remote_wamp_delegate.dart',
        ])
        self.assertEqual(set(target['tests']), {
            f'{prefix}/test/remote_wamp_delegate_test.dart',
            f'{prefix}/test/remote_wamp_delegate_wire_test.dart',
            f'{prefix}/test/remote_wamp_delegate_tls_test.dart',
        })
        self.assertEqual(set(target['supportFiles']), {
            f'{prefix}/test/certs/remote_auth_ca_cert.pem',
            f'{prefix}/test/certs/remote_auth_client_cert.pem',
            f'{prefix}/test/certs/remote_auth_client_key.pem',
            f'{prefix}/test/certs/remote_auth_server_cert.pem',
            f'{prefix}/test/certs/remote_auth_server_key.pem',
            f'{prefix}/test/certs/http3_ca_cert.pem',
            f'{prefix}/test/certs/http3_cert.pem',
            f'{prefix}/test/certs/http3_key.pem',
            f'{prefix}/test/support/remote_tls_trust_probe.dart',
            'packages/connectanum_core/test/authentication/cryptosign/keys.dart',
        })
        self.assertEqual(target['testRoot'], prefix)

    def test_native_transports_target_includes_file_wire_regressions(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['client-native-transports-vm']
        prefix = 'packages/connectanum_client'
        self.assertEqual(target['sources'], [
            f'{prefix}/lib/src/transport/native/native_transports_io.dart',
        ])
        self.assertEqual(set(target['tests']), {
            f'{prefix}/test/transport/native/native_transports_test.dart',
            f'{prefix}/test/transport/native/runtime_file_segment_test.dart',
        })
        self.assertEqual(target['supportFiles'], [
            f'{prefix}/test/test_support/native_runtime_support.dart',
        ])
        self.assertTrue(target['requiresNativeLibrary'])
        self.assertTrue(target['isolateTestFiles'])

    def test_meta_cache_targets_preserve_full_source_and_portable_regressions(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        prefix = 'packages/connectanum_client'
        for runtime in ('vm', 'web'):
            with self.subTest(runtime=runtime):
                target = targets[f'client-meta-cache-{runtime}']
                self.assertEqual(target['sources'], [
                    f'{prefix}/lib/src/meta/meta_state_cache.dart',
                ])
                self.assertEqual(target['tests'], [
                    f'{prefix}/test/meta_state_cache_test.dart',
                ])
                self.assertNotIn('testName', target)
                self.assertNotIn('maxMutants', target)
                self.assertEqual(target.get('platform', 'vm'),
                                 'chrome' if runtime == 'web' else 'vm')
                if runtime == 'web':
                    self.assertEqual(target['testRoot'], prefix)

    def test_native_runtime_target_includes_all_direct_runtime_regressions(self):
        targets = json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['client-native-runtime-vm']
        self.assertEqual(target['sources'], [
            'packages/connectanum_client/lib/src/transport/native/runtime.dart',
        ])
        direct_tests = {
            str(path.relative_to(runner.ROOT))
            for path in (runner.ROOT / 'packages/connectanum_client/test').rglob('*_test.dart')
            if 'package:connectanum_client/src/transport/native/runtime.dart' in path.read_text()
        }
        self.assertTrue(direct_tests)
        self.assertLessEqual(direct_tests, set(target['tests']))
        self.assertEqual(len(target['tests']), len(set(target['tests'])))
        self.assertTrue(target['requiresNativeLibrary'])
        self.assertTrue(target['isolateTestFiles'])

    def test_snapshot_rejects_symlink_files_and_ancestor_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'repo'
            root.mkdir()
            outside = Path(directory) / 'outside'
            outside.mkdir()
            (outside / 'fixture.yaml').write_text('outside')
            (root / 'linked.yaml').symlink_to(outside / 'fixture.yaml')
            (root / 'examples').symlink_to(outside, target_is_directory=True)
            for name in ('linked.yaml', 'examples/fixture.yaml'):
                with self.subTest(name=name), patch.object(runner, 'ROOT', root), \
                     patch.object(runner.subprocess, 'check_output', return_value=name.encode()):
                    with self.assertRaisesRegex(ValueError, 'symlink'):
                        runner.snapshot(Path(directory) / 'snapshot', [name])

    def test_process_census_distinguishes_live_zombie_and_unrelated_groups(self):
        output = runner.subprocess.CompletedProcess([], 0, stdout=(
            ' 10 20 S /sdk/dartvm\n 11 20 Z defunct\n 12 20 Z+ defunct\n 13 20 X dead\n'
            ' 14 20 D /Applications/Google Chrome\n 15 20 T python\n 16 99 R unrelated\n\n'), stderr='')
        with patch.object(runner.subprocess, 'run', return_value=output) as command:
            self.assertEqual(runner.live_process_group_members(20), [
                {'pid': 10, 'state': 'S', 'executable': '/sdk/dartvm'},
                {'pid': 14, 'state': 'D', 'executable': '/Applications/Google Chrome'},
                {'pid': 15, 'state': 'T', 'executable': 'python'},
            ])
            self.assertTrue(command.call_args.kwargs['check'])
            self.assertEqual(command.call_args.args[0],
                             ['ps', '-eo', 'pid=,pgid=,stat=,comm='])

    def test_process_inspection_failure_is_an_infrastructure_error(self):
        with patch.object(runner, 'live_process_group_members',
                          side_effect=OSError('ps unavailable')):
            code, output = run([sys.executable, '-c', 'print("finished")'], runner.ROOT, 5)
        self.assertEqual(code, 0)
        self.assertEqual(classify(code, output), 'error')
        self.assertIn('Could not inspect remaining test processes', output)
        self.assertIn('ps unavailable', output)

    @unittest.skipUnless(sys.platform == 'linux', 'Linux child subreaper contract')
    def test_zombie_descendants_do_not_invalidate_completed_results(self):
        import ctypes

        libc = ctypes.CDLL(None, use_errno=True)
        previous = ctypes.c_int()
        self.assertEqual(libc.prctl(37, ctypes.byref(previous), 0, 0, 0), 0)
        self.assertEqual(libc.prctl(36, 1, 0, 0, 0), 0)
        child_pid = None
        try:
            for exit_code, expected in ((0, 'survived'), (1, 'killed')):
                output = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                    {'type': 'testDone', 'testID': 1,
                     'result': 'success' if exit_code == 0 else 'failure'},
                    {'type': 'done', 'success': exit_code == 0},
                )
                parent = (
                    'import os,sys,json\n'
                    'pid=os.fork()\n'
                    'if pid == 0: os._exit(0)\n'
                    'os.waitid(os.P_PID,pid,os.WEXITED|os.WNOWAIT)\n'
                    'print(json.dumps({"pid":pid,"pgid":os.getpgrp()}),flush=True)\n'
                    f'print({output!r},flush=True)\n'
                    f'sys.exit({exit_code})\n'
                )
                code, actual = run([sys.executable, '-c', parent], runner.ROOT, 5)
                owned = json.loads(actual.splitlines()[0])
                child_pid = owned['pid']
                # The child remains an unreaped zombie adopted by this test.
                status = Path(f'/proc/{child_pid}/stat').read_text().rsplit(')', 1)[1]
                self.assertEqual(status.split()[0], 'Z')
                os.killpg(owned['pgid'], signal.SIGKILL)
                self.assertEqual(code, exit_code)
                self.assertEqual(classify(code, actual), expected, actual)
                os.waitpid(child_pid, 0)
                child_pid = None
        finally:
            if child_pid is not None:
                os.waitpid(child_pid, 0)
            self.assertEqual(libc.prctl(36, previous.value, 0, 0, 0), 0)

    def test_production_sources_accept_package_entry_points_but_not_test_paths(self):
        runner.validate_sources([
            'packages/client/lib/src/installer.dart',
            'packages/client/hook/build.dart',
            'packages/client/bin/main.dart',
            'packages/client/tool/install.dart',
            'examples/wamp_app/shared/lib/src/protocol.dart',
            'examples/wamp_app/server/bin/server.dart',
            'examples/wamp_app/client/lib/main.dart',
        ])
        for sources in ([], 'packages/client/lib/a.dart', [None],
                        ['packages/client/test/lib/fake.dart'],
                        ['packages/client/test/hook/build.dart'],
                        ['packages/client/lib/../test/fake.dart'],
                        ['packages/client//lib/a.dart'],
                        ['packages/client/lib/a.py'],
                        ['/tmp/packages/client/lib/a.dart'],
                        ['examples/wamp_app/shared/test/fake.dart'],
                        ['examples/wamp_app/shared/lib/../test/fake.dart'],
                        ['examples/wamp_app/shared/tool/fake.dart'],
                        ['examples/wamp_app/other/lib/fake.dart'],
                        ['examples/other/shared/lib/fake.dart']):
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
                    diagnostic = json.loads(actual.splitlines()[-1])
                    self.assertEqual(diagnostic['processes'][0]['pid'], owned['pid'])
                    self.assertTrue(diagnostic['processes'][0]['executable'])
                    self.assertNotIn(child, diagnostic['processes'][0]['executable'])
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
            ('test_error', '', "throw StateError('mutated path');", 'killed'),
            ('mixed_failure', '',
             "addTearDown(() => throw StateError('cleanup')); expect(1, 2);", 'killed'),
            ('startup', "setUpAll(() => throw StateError('startup'));",
             'expect(1, 1);', 'error'),
            ('shutdown', "tearDownAll(() => throw StateError('shutdown'));",
             'expect(1, 1);', 'error'),
            ('shutdown_after_failure', "tearDownAll(() => throw StateError('shutdown'));",
             'expect(1, 2);', 'error'),
            ('timeout', '', 'await Future<void>.delayed(const Duration(seconds: 5));',
             'timeout'),
            ('future_timeout', '',
             'await Future<void>.delayed(const Duration(seconds: 5))'
             '.timeout(const Duration(milliseconds: 1));', 'timeout'),
            ('wrapped_timeout', '',
             "await expectLater(Future<void>.error(TimeoutException('elapsed')), "
             "throwsA(isA<FormatException>()));", 'timeout'),
            ('legacy_poll_timeout', '', 'await _WorkerFixture().waitFor();', 'timeout'),
            ('poll_deadline', '', "fail('Condition not met within 0:00:02.000000');",
             'timeout'),
            ('event_deadline', '', "fail('Timed out waiting for subscription events');",
             'timeout'),
            ('timeout_text_assertion', '',
             "expect('TimeoutException: absent', 'expected payload');", 'killed'),
            ('abrupt_exit', '', 'exit(2);', 'error'),
        ]
        with tempfile.TemporaryDirectory(prefix='mutation-reporter-',
                                         dir=runner.ROOT / '.dart_tool') as directory:
            for name, lifecycle, body, expected in cases:
                with self.subTest(case=name):
                    source = Path(directory) / f'{name}_test.dart'
                    source.write_text(
                        "import 'dart:io';\nimport 'dart:async';\nimport 'package:test/test.dart';\n"
                        "class _WorkerFixture { Future<void> waitFor() async { "
                        "expect(false, isTrue, reason: 'Controlled child did not reach its barrier.'); } }\n"
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
                    evidence = runner.kill_evidence(expected, output)
                    if name in ('assertion', 'timeout_text_assertion'):
                        self.assertEqual(evidence['cause'], 'assertion', output)
                    elif name == 'test_error':
                        self.assertEqual(evidence['cause'], 'testError', output)
                    elif name == 'mixed_failure':
                        self.assertEqual(evidence['cause'], 'mixed', output)
                    else:
                        self.assertIsNone(evidence, output)

    def test_real_vm_campaign_preserves_later_assertions_and_terminal_failures(self):
        source_path = 'packages/fixture/lib/flag.dart'
        source = 'bool enabled() => true;'
        mutation = {'file': source_path, 'offset': source.index('true'), 'length': 4,
                    'line': 1, 'original': 'true', 'replacement': 'false',
                    'operator': 'boolean'}
        cases = {
            'assertion': 'expect(enabled(), isTrue);',
            'error_only': 'expect(1, 1);',
            'timeout': 'if (!enabled()) await Future<void>.delayed(const Duration(seconds: 5));',
            'exit': 'if (!enabled()) exit(2);',
        }
        real_run = runner.run

        def create_fixture(work, support_files):
            self.assertEqual(support_files, [])
            write_reporter_fixture_dependencies(work)
            production = work / source_path
            production.parent.mkdir(parents=True)
            production.write_text(source)
            for name, body in cases.items():
                test = work / f'packages/fixture/test/{name}_test.dart'
                test.parent.mkdir(parents=True, exist_ok=True)
                test.write_text(
                    "import 'dart:io';\nimport 'package:test/test.dart';\n"
                    "import '../lib/flag.dart';\nvoid main() {\n"
                    "test('early runtime rejection', () {\n"
                    "  if (!enabled()) throw StateError('controlled runtime rejection');\n"
                    "});\n"
                    f"test('later behavior', () async {{ {body} }});\n"
                    "}\n")

        def execute(command, cwd, timeout):
            if command[1] == 'tool/dart_mutations.dart':
                return 0, json.dumps([mutation])
            return real_run(command, cwd, timeout)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'config.json'
            config.write_text(json.dumps({name: {
                'sources': [source_path],
                'tests': [f'packages/fixture/test/{name}_test.dart'],
                'testTimeoutSeconds': 1,
            } for name in cases}))
            equivalents = root / 'equivalents.json'
            equivalents.write_text('{}')
            output = root / 'report'
            args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                    '--output', str(output), '--timeout', '45']
            with patch.object(sys, 'argv', args), \
                 patch.object(runner, 'snapshot', side_effect=create_fixture), \
                 patch.object(runner, 'run', side_effect=execute):
                self.assertEqual(runner.main(), 1)
            report = json.loads((output / 'mutation-report.json').read_text())
            self.assertTrue(report['complete'])
            self.assertEqual(report['gate']['threshold'], 95)
            for name, target in report['targets'].items():
                with self.subTest(case=name):
                    self.assertEqual(target['generated'], 1)
                    self.assertEqual(target['viable'], 1)
                    self.assertEqual(target['baselineExitCode'], 0)
                    self.assertEqual(target['restoredBaselineExitCode'], 0)
                    self.assertEqual(target['testHashes'].keys(),
                                     {f'packages/fixture/test/{name}_test.dart'})
                    outcome = target['outcomes'][0]
                    log = (output / outcome['log']).read_text()
                    self.assertEqual(outcome['status'],
                                     {'timeout': 'timeout', 'exit': 'error'}.get(name, 'killed'), log)
                    if name == 'assertion':
                        self.assertEqual(outcome['killEvidence'], {
                            'cause': 'mixed', 'assertionFailures': 1,
                            'testErrors': 1, 'unclassifiedFailures': 0,
                        }, log)
                        self.assertEqual(target['assertionScoreLowerBound'], 100)
                        self.assertEqual(target['adjustedAssertionScoreLowerBound'], 100)
                        self.assertTrue(target['gatePassed'])
                    else:
                        self.assertEqual(target['assertionScoreLowerBound'], 0)
                        self.assertFalse(target['gatePassed'])
                        if name == 'error_only':
                            self.assertEqual(outcome['killEvidence']['cause'], 'testError', log)
                        else:
                            self.assertNotIn('killEvidence', outcome)

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

    def test_main_rejects_test_errors_even_with_perfect_conventional_score(self):
        self.exercise_main('testError', 1)

    def test_main_rejects_unclassified_detections(self):
        self.exercise_main('unknown', 1)

    def test_list_records_inventory_without_claiming_a_gate_pass(self):
        self.exercise_main('killed', 0, listing=True)

    def test_assertion_gate_threshold_and_outcome_boundaries(self):
        assertion = {'status': 'killed', 'killEvidence': {'cause': 'assertion'}}
        mixed = {'status': 'killed', 'killEvidence': {'cause': 'mixed'}}
        test_error = {'status': 'killed', 'killEvidence': {'cause': 'testError'}}
        unknown = {'status': 'killed'}
        equivalent = {'status': 'survived', 'equivalence': 'Individually validated equivalent'}
        cases = [
            ('exact threshold', [assertion] * 19 + [{'status': 'survived'}], 95, True),
            ('below threshold', [assertion] * 19 + [{'status': 'survived'}], 95.01, False),
            ('test errors are not assertions', [assertion] * 18 + [test_error] * 2, 95, False),
            ('mixed has real assertions', [mixed], 100, True),
            ('unknown despite sufficient score', [assertion] * 19 + [unknown], 95, False),
            ('unknown at zero threshold', [unknown], 0, False),
            ('crash despite sufficient score', [assertion] * 19 + [{'status': 'error'}], 95, False),
            ('timeout despite sufficient score', [assertion] * 19 + [{'status': 'timeout'}], 95, False),
            ('compile errors have no credit', [assertion, {'status': 'compileError'}], 100, True),
            ('only compile errors', [{'status': 'compileError'}], 0, False),
            ('empty inventory', [], 0, False),
            ('only equivalents', [equivalent], 0, False),
            ('equivalents only adjust denominator', [assertion] * 9 + [equivalent], 100, True),
        ]
        for name, outcomes, threshold, expected in cases:
            with self.subTest(name=name):
                summary = summarize(outcomes)
                original = json.dumps(summary, sort_keys=True)
                self.assertEqual(runner.passes_assertion_gate(summary, threshold), expected)
                self.assertEqual(json.dumps(summary, sort_keys=True), original)

    def test_standalone_application_resolves_and_tests_in_its_own_directory(self):
        self.exercise_main('killed', 0, application=True)

    def test_standalone_resolution_failure_leaves_incomplete_evidence(self):
        self.exercise_main('resolutionFailure', None, application=True)

    def test_failed_baselines_never_produce_complete_evidence(self):
        self.exercise_main('baselineFailure', None)
        self.exercise_main('restoredFailure', None)

    def test_directory_targets_record_and_run_stable_test_file_order(self):
        self.exercise_main('killed', 0, directory_tests=True)

    def test_browser_commands_finish_suites_instead_of_fail_fast_shutdown(self):
        for status, expected in [('killed', 0), ('survived', 1)]:
            with self.subTest(status=status):
                self.exercise_main(status, expected, directory_tests=True, browser=True)

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

    def test_duplicate_configuration_keys_fail_before_starting_a_campaign(self):
        duplicate_documents = [
            '{"same": {}, "same": {}}',
            r'{"same": {}, "\u0073ame": {}}',
            '{"same": {"sources": ["a"], "sources": ["b"]}}',
            '{"same": {"tests": ["a"], "tests": ["b"]}}',
        ]
        for filename, duplicate in [(name, document) for name in ('config', 'equivalents')
                                    for document in duplicate_documents]:
            with self.subTest(file=filename, document=duplicate), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                config = root / 'config.json'
                config.write_text(duplicate if filename == 'config' else '{"same": {}}')
                equivalents = root / 'equivalents.json'
                equivalents.write_text(duplicate if filename == 'equivalents' else '{}')
                output = root / 'result'
                args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                        '--output', str(output)]
                with patch.object(sys, 'argv', args), patch.object(sys, 'stderr'), \
                     patch.object(runner, 'snapshot', side_effect=AssertionError('campaign started')) as snapshot, \
                     patch.object(runner, 'run') as command, \
                     patch.object(runner.subprocess, 'check_output', return_value='commit'):
                    with self.assertRaises(SystemExit) as failure:
                        runner.main()
                    self.assertEqual(failure.exception.code, 2)
                    snapshot.assert_not_called()
                    command.assert_not_called()
                self.assertFalse(output.exists())

    def test_checked_in_target_manifest_has_unique_keys(self):
        def unique(pairs):
            result = {}
            for key, value in pairs:
                self.assertNotIn(key, result, f'Duplicate mutation configuration key: {key}')
                result[key] = value
            return result

        json.loads((runner.ROOT / 'tool/mutation_targets.json').read_text(), object_pairs_hook=unique)

    def exercise_main(self, status, expected_code, directory_tests=False, native=False,
                      browser=False, application=False, listing=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'config.json'
            equivalents = root / 'equivalents.json'
            equivalents.write_text('{}')
            package_root = 'examples/wamp_app/shared' if application else 'packages/core'
            source_path = f'{package_root}/lib/a.dart'
            test_path = f'{package_root}/test/a_test.dart'
            selected = ['packages/core/test'] if directory_tests else [test_path]
            target = {'sources': [source_path], 'tests': selected}
            if browser:
                target['platform'] = 'chrome'
            if application:
                target['testRoot'] = package_root
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
            dependency_cwds = []
            def fake_snapshot(work, support_files):
                self.assertEqual(support_files, target.get('supportFiles', []))
                files = [(source_path, source)]
                if application:
                    files.extend([(f'{package_root}/pubspec.yaml', 'name: fixture'),
                                  (f'{package_root}/pubspec.lock', 'pinned dependencies')])
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
                    self.assertIn('--offline', command)
                    dependency_cwds.append(work)
                    if application and work.parts[-3:] == ('examples', 'wamp_app', 'shared'):
                        if status == 'resolutionFailure':
                            return 65, 'standalone dependency resolution failed'
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
                if application:
                    self.assertEqual(work.parts[-3:], ('examples', 'wamp_app', 'shared'))
                    self.assertIn('test/a_test.dart', command)
                    current = (work / 'lib/a.dart').read_text()
                else:
                    current = (work / source_path).read_text()
                seen.append(current)
                self.assertNotIn('--fail-fast', command)
                if browser:
                    self.assertIn('--compiler=dart2js', command)
                    self.assertEqual(command[command.index('--platform') + 1], 'chrome')
                if native:
                    self.assertIn('--timeout=20s', command)
                    if status == 'artifactChanged' and len(seen) == 3:
                        library.write_bytes(b'replaced artifact')
                if (status == 'baselineFailure' or
                        status == 'restoredFailure' and len(seen) == 3):
                    return -9, ''
                if current == source or status == 'survived':
                    return 0, passed
                if status == 'timeout':
                    return None, ''
                failures = [] if status == 'unknown' else [
                    {'type': 'error', 'testID': 1, 'isFailure': status != 'testError',
                     'error': 'Expected true' if status != 'testError' else 'StateError: invalid state'}]
                return (-9 if status == 'signal' else 1), events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                    *failures,
                    {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                    {'type': 'done', 'success': False},
                )
            args = ['runner', '--config', str(config), '--equivalents', str(equivalents),
                    '--output', str(root / 'result')]
            if listing:
                args.append('--list')
            with patch.object(sys, 'argv', args), patch.object(runner, 'snapshot', fake_snapshot), \
                 patch.object(runner, 'run', fake_run), patch.object(runner.subprocess, 'check_output', return_value='commit'), \
                 patch.dict(runner.os.environ, {'CONNECTANUM_NATIVE_LIB': str(library)}):
                if expected_code is None:
                    with self.assertRaises(RuntimeError):
                        runner.main()
                else:
                    self.assertEqual(runner.main(), expected_code)
            expected_seen = [source] if status == 'baselineFailure' else [source, 'bool f() => false;', source]
            if status == 'resolutionFailure':
                expected_seen = []
            if native and directory_tests:
                expected_seen = [source, source, 'bool f() => false;', source, source]
            if listing:
                expected_seen = []
            self.assertEqual(seen, expected_seen)
            if application:
                self.assertEqual(len(dependency_cwds), 2)
                self.assertEqual(dependency_cwds[1], dependency_cwds[0] / package_root)
            report = json.loads((root / 'result/mutation-report.json').read_text())
            complete = expected_code is not None and not listing
            self.assertEqual(report['complete'], complete)
            self.assertEqual(report['gate'], {
                'metric': 'adjustedAssertionScoreLowerBound', 'threshold': 95,
                'passed': expected_code == 0 if complete else None,
            })
            if complete:
                self.assertEqual(report['targets']['fixture']['gatePassed'], expected_code == 0)
            else:
                for result in report['targets'].values():
                    self.assertNotIn('gatePassed', result)
            if listing:
                self.assertEqual(report['targets']['fixture']['inventory'], [mutation])
            if status == 'artifactChanged':
                self.assertFalse(report['targets']['fixture']['nativeArtifactUnchanged'])
            if complete:
                target = report['targets']['fixture']
                if application:
                    self.assertEqual(target['dependencyHashes'], {
                        f'{package_root}/pubspec.yaml': runner.hashlib.sha256(b'name: fixture').hexdigest(),
                        f'{package_root}/pubspec.lock': runner.hashlib.sha256(b'pinned dependencies').hexdigest(),
                    })
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
                if target['outcomes'][0]['status'] == 'killed':
                    cause = status if status in ('unknown', 'testError') else 'assertion'
                    self.assertEqual(report['killEvidenceVersion'], 1)
                    self.assertEqual(target['outcomes'][0]['killEvidence']['cause'], cause)
                    self.assertEqual(target['killCauseCounts'][cause], 1)
                    self.assertEqual(target['killEvidenceComplete'], cause != 'unknown')
                    self.assertEqual(target['score'], 100)
                    self.assertEqual(target['adjustedScore'], 100)
                    self.assertEqual(target['assertionScoreLowerBound'],
                                     100 if cause == 'assertion' else 0)

    def test_timeout_and_infrastructure_errors_do_not_inflate_score(self):
        result = summarize([{'status': s} for s in ['killed', 'survived', 'timeout', 'error', 'compileError']])
        self.assertEqual(result['score'], 25)
        self.assertEqual(result['viable'], 4)
        self.assertIsNone(summarize([{'status': 'compileError'}])['score'])

    def test_same_mutant_retains_independent_runtime_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_name = 'packages/core/lib/a.dart'
            test_name = 'packages/core/test/a_test.dart'
            source = 'bool f() => true;'
            mutation = {'file': source_name, 'offset': 12, 'length': 4, 'line': 1,
                        'original': 'true', 'replacement': 'false', 'operator': 'boolean'}
            config = root / 'config.json'
            config.write_text(json.dumps({
                name: {'sources': [source_name], 'tests': [test_name], 'platform': platform}
                for name, platform in [('fixture-vm', 'vm'), ('fixture-web', 'chrome')]
            }))
            equivalents = root / 'equivalents.json'
            equivalents.write_text('{}')
            output = root / 'result'

            def snapshot(work, support):
                for name, contents in [(source_name, source), (test_name, 'fixture')]:
                    path = work / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(contents)

            def run_fixture(command, work, timeout):
                if command[1:3] == ['pub', 'get']:
                    return 0, ''
                if command[1] == 'tool/dart_mutations.dart':
                    return 0, json.dumps([mutation])
                mutated = (work / source_name).read_text() != source
                platform = command[command.index('--platform') + 1]
                log = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': platform}},
                    *([{'type': 'error', 'testID': 1, 'isFailure': True,
                        'error': 'Expected true'}] if mutated else []),
                    {'type': 'testDone', 'testID': 1,
                     'result': 'failure' if mutated else 'success'},
                    {'type': 'done', 'success': not mutated},
                )
                return (1 if mutated else 0), log

            with patch.object(sys, 'argv', ['runner', '--config', str(config),
                                           '--equivalents', str(equivalents), '--output', str(output)]), \
                 patch.object(runner, 'snapshot', snapshot), patch.object(runner, 'run', run_fixture), \
                 patch.object(runner.subprocess, 'check_output', return_value='commit'):
                self.assertEqual(runner.main(), 0)
            report = json.loads((output / 'mutation-report.json').read_text())
            logs = []
            for name, platform in [('fixture-vm', 'vm'), ('fixture-web', 'chrome')]:
                outcome = report['targets'][name]['outcomes'][0]
                log = output / outcome.get('log', f'{outcome["id"]}.log')
                logs.append(log)
                self.assertIn(f'"name": "{platform}"', log.read_text())
            self.assertEqual(len(set(logs)), 2)

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

    def test_helper_deadlines_are_not_assertion_kills(self):
        for message in (
            'TimeoutException after 0:00:02.000000: Future not completed',
            'TimeoutException: event missing',
            'Condition not met within 0:00:02.000000',
            'Timed out waiting for native connection on listener 1',
        ):
            with self.subTest(message=message):
                output = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'assertion'}},
                    {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                    {'type': 'testStart', 'test': {'id': 2, 'name': 'missing callback'}},
                    {'type': 'error', 'testID': 2, 'error': message, 'isFailure': True},
                    {'type': 'testDone', 'testID': 2, 'result': 'failure'},
                    {'type': 'done', 'success': False},
                )
                self.assertEqual(classify(1, output), 'timeout')

    def test_wrapped_and_legacy_deadlines_are_not_assertion_kills(self):
        for message, stack in (
            ("Expected: throws <Instance of 'FormatException'>\n"
             "  Actual: <Instance of 'Future<void>'>\n"
             "   Which: threw TimeoutException:<TimeoutException after 0:00:02.000000: Future not completed>\n", ''),
            ('Expected: true\n  Actual: <false>\nControlled child did not reach its barrier.\n',
             'test/native_wamp_worker_lifecycle_test.dart 562:5 _WorkerFixture.waitFor'),
        ):
            with self.subTest(message=message):
                output = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'deadline'}},
                    {'type': 'error', 'testID': 1, 'error': message,
                     'stackTrace': stack, 'isFailure': True},
                    {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                    {'type': 'done', 'success': False},
                )
                self.assertEqual(classify(1, output), 'timeout')

    def test_timeout_business_text_remains_an_assertion(self):
        for message, stack in (
            ("Expected: 'TimeoutException: absent'\n  Actual: 'wrong payload'\n", ''),
            ('Expected: true\n  Actual: <false>\nControlled child did not reach its barrier.\n', ''),
            ('Which: threw StateError:<TimeoutException in business data>\n', ''),
            ('Expected: true\n  Actual: <false>\nDifferent contract.\n', '_WorkerFixture.waitFor'),
        ):
            with self.subTest(message=message, stack=stack):
                output = events(
                    {'type': 'testStart', 'test': {'id': 1, 'name': 'contract'}},
                    {'type': 'error', 'testID': 1, 'error': message,
                     'stackTrace': stack, 'isFailure': True},
                    {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                    {'type': 'done', 'success': False},
                )
                self.assertEqual(classify(1, output), 'killed')

    def test_deadline_audit_requires_opt_in_and_preserves_original_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = events(
                {'type': 'testStart', 'test': {'id': 1, 'name': 'deadline'}},
                {'type': 'error', 'testID': 1, 'isFailure': True,
                 'error': 'Which: threw TimeoutException:<TimeoutException: elapsed>'},
                {'type': 'testDone', 'testID': 1, 'result': 'failure'},
                {'type': 'done', 'success': False},
            )
            (root / 'mutant.log').write_text(log)
            outcomes = [{'id': 'deadline', 'status': 'killed', 'exitCode': 1,
                         'log': 'mutant.log', 'killEvidence': {'cause': 'assertion'}}]
            old_summary = runner.summarize(outcomes)
            original = {'schemaVersion': 1, 'complete': True,
                        'runnerSha256': 'historical-runner',
                        'gate': {'threshold': 95, 'passed': True},
                        'targets': {'fixture': {**old_summary, 'generated': 1,
                            'gatePassed': True, 'sourceHashes': {'lib/a.dart': 'source-hash'},
                            'testHashes': {'test/a.dart': 'test-hash'}, 'outcomes': outcomes}}}
            source = root / 'report.json'
            source.write_text(json.dumps(original))
            original_bytes = source.read_bytes()
            with self.assertRaisesRegex(ValueError, 'saved kill classifies as timeout'):
                evidence_audit.audit(source)
            corrected = evidence_audit.audit(source, reclassify_deadlines=True)
            self.assertEqual(source.read_bytes(), original_bytes)
            self.assertEqual((root / 'mutant.log').read_text(), log)
            target = corrected['targets']['fixture']
            self.assertEqual(target['sourceHashes'], {'lib/a.dart': 'source-hash'})
            self.assertEqual(target['testHashes'], {'test/a.dart': 'test-hash'})
            self.assertEqual(target['counts'], {'timeout': 1})
            self.assertEqual(target['viable'], 1)
            self.assertEqual(target['assertionScoreLowerBound'], 0)
            self.assertFalse(target['gatePassed'])
            self.assertFalse(corrected['gate']['passed'])
            self.assertEqual(target['historicalSummary']['score'], 100)
            self.assertEqual(target['historicalSummary']['counts'], {'killed': 1})
            self.assertEqual(target['outcomes'][0]['historicalStatus'], 'killed')
            self.assertNotIn('killEvidence', target['outcomes'][0])
            self.assertEqual(corrected['killEvidenceAudit']['sourceReportSha256'],
                             runner.hashlib.sha256(original_bytes).hexdigest())
            self.assertEqual(target['outcomes'][0]['logSha256'], runner.hashlib.sha256(log.encode()).hexdigest())
            self.assertEqual(corrected['killEvidenceAudit']['reclassifiedDeadlines'], 1)
            with patch.object(sys, 'argv', ['audit', str(source), '--output', str(root / 'new.json'),
                                          '--reclassify-deadlines']):
                self.assertEqual(evidence_audit.main(), 0)
                with self.assertRaises(FileExistsError):
                    evidence_audit.main()
            original['targets']['fixture']['score'] = 0
            source.write_text(json.dumps(original))
            with self.assertRaisesRegex(ValueError, 'saved score'):
                evidence_audit.audit(source, reclassify_deadlines=True)

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
