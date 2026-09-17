#!/usr/bin/env python3
"""Regression checks for repository verification scripts."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = REPO_ROOT / "bin" / "bootstrap"
COMMON = REPO_ROOT / "bin" / "common.sh"
CONNECTANUM_ROUTER = REPO_ROOT / "bin" / "connectanum-router"
CONNECTANUM_ROUTER_ALIAS = REPO_ROOT / "bin" / "connectanum_router"
CONNECTANUM_ROUTER_PACKAGE_BIN = (
    REPO_ROOT / "packages" / "connectanum_router" / "bin" / "connectanum_router.dart"
)
CONNECTANUM_ROUTER_PACKAGE_PUBSPEC = (
    REPO_ROOT / "packages" / "connectanum_router" / "pubspec.yaml"
)
CONNECTANUM_ROUTER_PACKAGE_LIB = (
    REPO_ROOT / "packages" / "connectanum_router" / "lib"
)
CONNECTANUM_ROUTER_SETTINGS = (
    CONNECTANUM_ROUTER_PACKAGE_LIB / "src" / "router" / "config" / "router_settings.dart"
)
CONNECTANUM_BENCH_PACKAGE_BIN = (
    REPO_ROOT / "packages" / "connectanum_bench" / "bin" / "router_bench.dart"
)
CONNECTANUM_BENCH_SERVICE_BIN = (
    REPO_ROOT
    / "packages"
    / "connectanum_bench"
    / "bin"
    / "bench_router_service.dart"
)
CONNECTANUM_BENCH_WORKER_BIN = (
    REPO_ROOT
    / "packages"
    / "connectanum_bench"
    / "bin"
    / "wamp_client_worker.dart"
)
CONNECTANUM_BENCH_PACKAGE_PUBSPEC = (
    REPO_ROOT / "packages" / "connectanum_bench" / "pubspec.yaml"
)
PACKAGE_NATIVE_ARTIFACT = REPO_ROOT / "bin" / "package-native-artifact"
TEST_ALL = REPO_ROOT / "bin" / "test-all"
TEST_FAST = REPO_ROOT / "bin" / "test-fast"
TEST_WAMP_APP = REPO_ROOT / "bin" / "test-wamp-app"
VERIFY = REPO_ROOT / "bin" / "verify"


class VerificationScriptsTest(unittest.TestCase):
    @unittest.skipIf(os.name == 'nt', 'The diagnostic launcher requires Bash')
    def test_wamp_diagnostics_collect_all_results_without_masking_failures(self):
        names = [
            'wamp_client_impl_throughput', 'wamp_payload_mode_throughput',
            'wamp_mixed_serializer_throughput',
            'wamp_websocket_fragmentation_throughput',
            'wamp_file_transfer_throughput',
            'wamp_large_rawsocket_frames_throughput',
            'wamp_file_transfer_heavy', 'wamp_large_rawsocket_frames_heavy',
        ]
        cases = [
            ('success', '', '', '0'),
            ('first gate', '', names[0], '0'),
            ('fragmentation gate', '', names[3], '0'),
            ('last gate', '', names[-1], '0'),
            ('workload', names[0], '', '0'),
            ('multiple failures', names[1], names[3], '0'),
            ('hardware unavailable', '', '', '1'),
        ]
        for label, failed_workload, failed_gate, hardware_failure in cases:
            with self.subTest(case=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                scripts = root / 'bin'
                scripts.mkdir()
                for name in ('common.sh', 'wamp-profile-diagnostics'):
                    shutil.copy2(REPO_ROOT / 'bin' / name, scripts / name)
                with (scripts / 'common.sh').open('a') as common:
                    common.write('\nbuild_native_ffi_test_release() { export CONNECTANUM_NATIVE_LIB="$ROOT_DIR/fake-library"; }\n')
                for directory in ('scenarios', 'artifact_gate'):
                    shutil.copytree(REPO_ROOT / 'native/bench' / directory,
                                    root / 'native/bench' / directory)
                commands = {
                    'cargo': '''#!/usr/bin/env bash
set -eu
if [[ "$1" == -V ]]; then printf 'cargo test\\n'; exit 0; fi
scenario=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --scenario ]]; then scenario="$2"; shift; fi
  shift
done
name="${scenario##*/}"
name="${name%.toml}"
printf 'workload:%s\\n' "$name" >> "$TRACE"
[[ "$name" != "$FAILED_WORKLOAD" ]] || exit 7
''',
                    'check-bench-artifacts': '''#!/usr/bin/env bash
set -eu
summary="$2"
directory="${summary%/*}"
name="${directory##*/}"
printf 'gate:%s\\n' "$name" >> "$TRACE"
[[ "$name" != "$FAILED_GATE" ]] || exit 9
''',
                    'dart': '#!/usr/bin/env bash\nprintf "Dart test\\n"\n',
                    'rustc': '#!/usr/bin/env bash\nprintf "rustc test\\n"\n',
                    'lscpu': '''#!/usr/bin/env bash
[[ "$HARDWARE_FAILURE" == 0 ]] || exit 8
printf 'Model name: fixture CPU\\nCPU(s): 4\\n'
''',
                }
                for name, source in commands.items():
                    executable = scripts / name
                    executable.write_text(source)
                    executable.chmod(0o755)
                trace = root / 'trace'
                output = root / 'results with spaces'
                result = subprocess.run(
                    ['bash', str(scripts / 'wamp-profile-diagnostics'),
                     '--out-dir', str(output)], cwd=root,
                    env=dict(os.environ, PATH=str(scripts) + os.pathsep + os.environ['PATH'],
                             TRACE=str(trace), FAILED_WORKLOAD=failed_workload,
                             FAILED_GATE=failed_gate, HARDWARE_FAILURE=hardware_failure),
                    capture_output=True, text=True, timeout=30,
                )
                lines = trace.read_text().splitlines()
                self.assertEqual([line for line in lines if line.startswith('workload:')],
                                 ['workload:' + name for name in names], result.stdout + result.stderr)
                self.assertEqual([line for line in lines if line.startswith('gate:')],
                                 ['gate:' + name for name in names if name != failed_workload])
                self.assertEqual(result.returncode, 1 if failed_workload or failed_gate else 0,
                                 result.stdout + result.stderr)
                rows = (output / 'diagnostics-summary.tsv').read_text().splitlines()
                self.assertEqual(rows[0], 'scenario\tworkload_exit\tgate_exit\tstatus')
                expected = []
                for name in names:
                    if name == failed_workload:
                        expected.append(f'{name}\t7\tnot_run\tworkload_failed')
                    elif name == failed_gate:
                        expected.append(f'{name}\t0\t9\tgate_failed')
                    else:
                        expected.append(f'{name}\t0\t0\tpassed')
                self.assertEqual(rows[1:], expected)
                hardware = (output / 'hardware-info.txt').read_text()
                self.assertIn('unavailable' if hardware_failure == '1' else 'fixture CPU', hardware)

    def test_browser_mutation_entrypoint_retains_and_hashes_all_original_suites(self):
        targets = json.loads((REPO_ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['core-lazy-web']
        self.assertEqual(target['sources'], targets['core-lazy-vm']['sources'])
        self.assertEqual(target['supportFiles'], targets['core-lazy-vm']['tests'])
        self.assertEqual(target['tests'], [
            'packages/connectanum_core/test/support/lazy_payload_mutation_suite.dart'])
        entrypoint = (REPO_ROOT / target['tests'][0]).read_text()
        for filename, alias, group in [
            ('message_lazy_payload_regression_test.dart', 'lazy_payload', 'lazy payload'),
            ('message_invocation_test.dart', 'invocation', 'invocation'),
            ('message_result_test.dart', 'result', 'result'),
        ]:
            self.assertIn(f"import '../{filename}' as {alias};", entrypoint)
            self.assertIn(f"group('{group}', {alias}.main);", entrypoint)

    def test_bench_http_mutations_include_complete_handler_and_test_inventory(self):
        targets = json.loads((REPO_ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['bench-http-stream-vm']
        root = REPO_ROOT / 'packages/connectanum_bench'
        entrypoint = root / 'test/support/http_stream_mutation_suite.dart'
        self.assertEqual(target['sources'], [
            'packages/connectanum_bench/lib/src/http_stream_handler.dart'])
        self.assertEqual(target['testRoot'], 'packages/connectanum_bench')
        self.assertEqual(target['tests'], [entrypoint.relative_to(REPO_ROOT).as_posix()])
        expected = set((root / 'test').glob('http_stream*_test.dart'))
        self.assertEqual(set(target['supportFiles']), {
            path.relative_to(REPO_ROOT).as_posix() for path in expected})
        source = entrypoint.read_text()
        imports = re.findall(r"import\s+'([^']+)'\s+as\s+(\w+);", source)
        self.assertEqual({(entrypoint.parent / path).resolve() for path, _ in imports}, expected)
        for path, alias in imports:
            self.assertRegex(source, rf"group\('[^']+', {alias}\.main\)")

    def test_bench_workload_mutations_hash_wire_suites_and_tls_fixtures(self):
        targets = json.loads((REPO_ROOT / 'tool/mutation_targets.json').read_text())
        target = targets['bench-wamp-workload-vm']
        root = REPO_ROOT / 'packages/connectanum_bench'
        entrypoint = root / 'test/support/wamp_workload_mutation_suite.dart'
        self.assertEqual(target['sources'], [
            'packages/connectanum_bench/lib/src/wamp_workload_runner.dart'])
        self.assertEqual(target['testRoot'], 'packages/connectanum_bench')
        self.assertEqual(target['tests'], [entrypoint.relative_to(REPO_ROOT).as_posix()])
        expected = {root / 'test' / name for name in [
            'wamp_workload_runner_test.dart', 'wamp_session_wire_regression_test.dart',
            'wamp_session_factory_test.dart', 'wamp_transport_targets_test.dart',
            'wamp_sample_test.dart',
        ]}
        fixtures = {'native/bench/bench_tls.crt', 'native/bench/bench_tls.key'}
        self.assertEqual(set(target['supportFiles']), fixtures | {
            path.relative_to(REPO_ROOT).as_posix() for path in expected})
        source = entrypoint.read_text()
        imports = re.findall(r"import\s+'([^']+)'\s+as\s+(\w+);", source)
        self.assertEqual({(entrypoint.parent / path).resolve() for path, _ in imports}, expected)
        for path, alias in imports:
            self.assertRegex(source, rf"group\('[^']+', {alias}\.main\)")

    def test_serializer_mutation_wrappers_preserve_complete_runtime_inventory(self):
        targets = json.loads((REPO_ROOT / 'tool/mutation_targets.json').read_text())
        root = REPO_ROOT / 'packages/connectanum_core/test'
        common = root / 'support/serializer_mutation_suite.dart'
        browser = root / 'support/serializer_web_mutation_suite.dart'
        original_files = set((root / 'serializer').rglob('*.dart')) | {
            root / 'serializer_challenge_welcome_test.dart',
            root / 'message_lazy_payload_regression_test.dart',
        }
        for runtime, entrypoint in [('vm', common), ('web', browser)]:
            for codec in ('cbor', 'msgpack'):
                target = targets[f'core-{codec}-serializer-{runtime}']
                with self.subTest(runtime=runtime, codec=codec):
                    self.assertEqual(target['tests'], [entrypoint.relative_to(REPO_ROOT).as_posix()])
                    expected_support = original_files | ({common} if runtime == 'web' else set())
                    self.assertEqual(set(target['supportFiles']),
                                     {path.relative_to(REPO_ROOT).as_posix() for path in expected_support})
        shared_source, browser_source = common.read_text(), browser.read_text()
        imports = re.findall(r"import\s+'([^']+)'\s+as\s+(\w+);", shared_source)
        actual = {(common.parent / path).resolve() for path, alias in imports}
        browser_only = root / 'serializer/msgpack/codec_fallback_web_test.dart'
        expected = {path for path in original_files if path.name.endswith('_test.dart')} - {browser_only}
        self.assertEqual(actual, expected)
        for path, alias in imports:
            self.assertRegex(shared_source, rf"group\('[^']+', {alias}\.main\)")
        self.assertIn("@TestOn('js')", browser_source)
        self.assertIn("import 'serializer_mutation_suite.dart' as serializers;", browser_source)
        self.assertIn("import '../serializer/msgpack/codec_fallback_web_test.dart' as fallback;", browser_source)
        self.assertIn('serializers.main();', browser_source)
        self.assertIn("group('msgpack JS fallback', fallback.main);", browser_source)

    @unittest.skipIf(os.name == 'nt', 'The application coverage launcher requires Bash')
    def test_app_shared_coverage_launcher_reports_and_fails_closed(self):
        scenarios = [(runtime, stage, expected) for runtime in ('vm', 'chrome')
                     for stage, expected in [('success', 0), ('resolve', 7), ('test', 8),
                                             ('format', 9), ('floor', 1)]]
        scenarios += [('', 'success', 0), ('chrome', 'no_chrome', 1), ('wasm', 'unsupported', 2)]
        for runtime, stage, expected in scenarios:
            with self.subTest(runtime=runtime, stage=stage), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                scripts, tooling = root / 'bin', root / 'tool'
                scripts.mkdir()
                tooling.mkdir()
                (root / 'examples/wamp_app/shared').mkdir(parents=True)
                for name in ('test-app-shared-coverage', 'common.sh'):
                    shutil.copy2(REPO_ROOT / 'bin' / name, scripts / name)
                with (scripts / 'common.sh').open('a') as common:
                    common.write('\nensure_chrome_env() { [[ "$STAGE" != no_chrome ]]; }\n')
                shutil.copy2(REPO_ROOT / 'tool/check_coverage.py', tooling / 'check_coverage.py')
                source = 'examples/wamp_app/shared/lib/api.dart'
                (tooling / 'coverage_app_shared_policy.json').write_text(json.dumps({
                    'target': 98, 'sourceScope': 'application',
                    'packages': {'shared': 98}, 'requiredSources': [source],
                }))
                dart = scripts / 'dart'
                dart.write_text('''#!/usr/bin/env bash
set -eu
printf '%s:%s\\n' "$PWD" "$*" >> "$TRACE"
if [[ "$1" == test ]]; then
  [[ "$STAGE" != test ]] || exit 8
elif [[ "$2" == get ]]; then
  [[ "$STAGE" != resolve ]] || exit 7
else
  [[ "$STAGE" != format ]] || exit 9
  output=''
  for arg in "$@"; do
    case "$arg" in --out=*) output="${arg#--out=}";; esac
  done
  hits=1
  [[ "$STAGE" != floor ]] || hits=0
  printf 'SF:examples/wamp_app/shared/lib/api.dart\\nDA:1,%s\\nend_of_record\\n' "$hits" > "$output"
fi
''')
                dart.chmod(0o755)
                output = root / 'reports with spaces'
                trace = root / 'trace'
                env = dict(os.environ, PATH=str(scripts) + os.pathsep + os.environ['PATH'],
                           STAGE=stage, TRACE=str(trace),
                           CONNECTANUM_APP_SHARED_COVERAGE_RUNTIME=runtime,
                           CONNECTANUM_APP_SHARED_COVERAGE_DIR='reports with spaces')
                command = ['bash', str(scripts / 'test-app-shared-coverage')]
                result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                if stage in ('no_chrome', 'unsupported'):
                    self.assertFalse(trace.exists())
                    self.assertFalse(output.exists())
                    self.assertIn('Chrome is required' if stage == 'no_chrome' else 'Unsupported', result.stderr)
                    continue
                calls = trace.read_text().splitlines()
                self.assertTrue(calls[0].endswith('/examples/wamp_app/shared:pub get'))
                self.assertEqual(len(calls), {'resolve': 1, 'test': 2}.get(stage, 3))
                if stage in ('success', 'floor'):
                    report = json.loads((output / 'summary.json').read_text())
                    self.assertEqual(report['sourceScope'], 'application')
                    self.assertEqual(report['measurement'], f"Dart {runtime or 'vm'} executable lines in LCOV")
                    self.assertEqual(report['packages']['shared']['covered'], int(stage == 'success'))
                    self.assertEqual(bool(report['findings']), stage == 'floor')
                    self.assertIn('--package=' + str(root / 'examples/wamp_app/shared'), calls[-1])
                    self.assertIn('--report-on=examples/wamp_app/shared/lib', calls[-1])
                    self.assertEqual('--check-ignore' in calls[-1], runtime != 'chrome')
                else:
                    self.assertFalse((output / 'summary.json').exists())
                if stage != 'resolve':
                    self.assertEqual('--platform=vm' in calls[1], runtime != 'chrome')
                    self.assertEqual('--platform=chrome' in calls[1], runtime == 'chrome')
                    self.assertEqual('--compiler=dart2js' in calls[1], runtime == 'chrome')
                    self.assertEqual('--concurrency=1' in calls[1], runtime == 'chrome')
                again = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(again.returncode, 2)
                self.assertEqual(trace.read_text().splitlines(), calls)

    @unittest.skipIf(os.name == "nt", "The fake Cargo executable uses a POSIX shell")
    def test_router_native_fixture_uses_cargo_freshness_after_build(self) -> None:
        helper = REPO_ROOT / "packages/connectanum_router/test/support/native_lib.dart"
        dart = shutil.which("dart")
        self.assertIsNotNone(dart)
        for legacy in (False, True):
            for outcome in ("success", "failure", "missing"):
                with self.subTest(legacy=legacy, outcome=outcome), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp).resolve()
                    source = root / "native/transport/ct_core/src/test_only.rs"
                    source.parent.mkdir(parents=True)
                    source.write_text("// A test-only change need not relink the release library.\n")
                    target = "legacy-message-handles-test" if legacy else "ffi-test"
                    filename = "libct_ffi.dylib" if os.uname().sysname == "Darwin" else "libct_ffi.so"
                    artifact = root / f"native/transport/target/{target}/release/{filename}"
                    artifact.parent.mkdir(parents=True)
                    if outcome != "missing":
                        artifact.write_bytes(b"fixture: path resolution only")
                        os.utime(artifact, (1700000000, 1700000000))
                    os.utime(source, (1700000100, 1700000100))
                    cargo = root / "cargo"
                    marker = root / "cargo-called"
                    cargo.write_text(
                        '#!/bin/sh\nprintf "%s\\n" "$@" > "$CARGO_CALL_MARKER"\n'
                        + ("exit 17\n" if outcome == "failure" else "exit 0\n")
                    )
                    cargo.chmod(0o755)
                    resolver = "resolveOrBuildLegacyMessageHandleNativeLib" if legacy else "resolveOrBuildNativeLib"
                    probe = root / "probe.dart"
                    probe.write_text(
                        f"import '{helper.as_uri()}';\n"
                        f"void main() {{ print({resolver}()); }}\n"
                    )
                    env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"],
                               CARGO_CALL_MARKER=str(marker))
                    env.pop("CONNECTANUM_NATIVE_LIB", None)
                    result = subprocess.run(
                        [dart, str(probe)], cwd=root, env=env, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(marker.exists(), result.stderr)
                    self.assertIn("ffi-test", marker.read_text())
                    self.assertEqual(
                        result.stdout.strip(),
                        str(artifact) if outcome == "success" else "null",
                        result.stderr,
                    )
                    if outcome == "failure":
                        self.assertIn("exit 17", result.stderr)

    def test_native_coverage_keeps_raw_evidence_and_pins_scopes_before_collection(self):
        for script in [TEST_FAST, TEST_ALL]:
            self.assertIn('"$ROOT_DIR/bin/test-native-coverage-tools"', script.read_text())
        script = (REPO_ROOT / "bin/test-native-coverage").read_text()
        self.assertLess(script.index("native_coverage.py snapshot"), script.index("cargo llvm-cov"))
        self.assertLess(script.index("cargo llvm-cov"), script.index("native_coverage.py filter"))
        self.assertIn('--output-path "$coverage_root/lcov.info"', script)
        self.assertIn('--output "$coverage_root/production.info"', script)
        self.assertIn('CONNECTANUM_TEST_LLVM_COVERAGE=1', script)
        tool_gate = (REPO_ROOT / "bin/test-native-coverage-tools").read_text()
        self.assertIn('--target-dir "$ROOT_DIR/out/rust-coverage-scope-target"', tool_gate)
        self.assertNotIn('native/transport/Cargo.toml', tool_gate)

    def test_client_hooks_run_in_regression_and_coverage_gates(self) -> None:
        for script in [TEST_FAST, TEST_ALL]:
            with self.subTest(script=script.name):
                self.assertIn(
                    "dart test packages/connectanum_client/test/hook",
                    [line.strip() for line in script.read_text().splitlines()],
                )
        self.assertIn(
            "run_package_coverage connectanum_client connectanum_client_hooks test/hook",
            (REPO_ROOT / "bin/test-coverage").read_text().splitlines(),
        )
        coverage = (REPO_ROOT / "bin/test-coverage").read_text()
        self.assertIn('--scope packaging', coverage)
        self.assertIn('--policy tool/coverage_packaging_policy.json', coverage)
        workflow = (REPO_ROOT / '.github/workflows/dart.yml').read_text()
        for artifact in ('packaging-lcov.info', 'packaging-summary.json'):
            self.assertIn(artifact, coverage)
            self.assertIn('out/coverage/' + artifact, workflow)

    def test_hosted_regression_jobs_run_real_llvm_fixture(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/dart.yml").read_text()
        for name, next_name, command in [
            ("fast", "wamp-app", "bin/test-fast"),
            ("verify", "coverage", "bin/verify"),
        ]:
            with self.subTest(job=name):
                job = workflow.split(f"\n  {name}:\n", 1)[1].split(
                    f"\n  {next_name}:\n", 1
                )[0]
                self.assertIn("components: rustfmt, clippy, llvm-tools-preview", job)
                installer = "run: cargo install cargo-llvm-cov --locked --version 0.9.1"
                self.assertIn(installer, job)
                self.assertLess(job.index(installer), job.index(f"run: {command}"))
                self.assertIn("CONNECTANUM_TEST_LLVM_COVERAGE: '1'", job)

    def test_hosted_regression_jobs_run_real_native_mutation_fixture(self) -> None:
        for script in [TEST_FAST, TEST_ALL]:
            self.assertIn('"$ROOT_DIR/bin/test-native-mutation-tools"', script.read_text())
        workflow = (REPO_ROOT / ".github/workflows/dart.yml").read_text()
        for name, next_name, command in [
            ("fast", "wamp-app", "bin/test-fast"),
            ("verify", "coverage", "bin/verify"),
        ]:
            with self.subTest(job=name):
                job = workflow.split(f"\n  {name}:\n", 1)[1].split(
                    f"\n  {next_name}:\n", 1
                )[0]
                installer = "run: cargo install cargo-mutants --locked --version 27.1.0"
                self.assertIn(installer, job)
                self.assertLess(job.index(installer), job.index(f"run: {command}"))

    def test_native_diagnostics_audits_instead_of_trusting_cargo_caught_count(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/mutation-diagnostics.yml").read_text()
        native_job = workflow.split("\n  rust:\n", 1)[1]
        self.assertIn("bin/collect-native-mutations --output out/mutations", native_job)
        self.assertNotIn("bin/test-native-mutations", native_job)
        self.assertIn("os: [ubuntu-latest, macos-latest]", native_job)
        self.assertIn("if: always()", native_job)

    def test_client_resource_restart_runs_in_both_gates(self) -> None:
        command = (
            "dart test packages/connectanum_client/test/transport/native/"
            "resource_restart_test.dart --concurrency=1"
        )
        for script in [TEST_FAST, TEST_ALL]:
            with self.subTest(script=script.name):
                self.assertIn(
                    command,
                    [line.strip() for line in script.read_text().splitlines()],
                )

    def test_client_message_abi_negotiation_runs_in_both_gates(self) -> None:
        command = (
            "dart test packages/connectanum_client/test/transport/native/"
            "message_handle_abi_test.dart"
        )
        for script in [TEST_FAST, TEST_ALL]:
            with self.subTest(script=script.name):
                self.assertIn(
                    command,
                    [line.strip() for line in script.read_text().splitlines()],
                )

    def test_full_verify_runs_native_benchmark_regressions(self) -> None:
        self.assertIn(
            "cargo_with_retry test --manifest-path native/bench/Cargo.toml",
            TEST_ALL.read_text(),
        )

    def test_full_verify_runs_complete_native_test_hook_suite(self) -> None:
        script = TEST_ALL.read_text()
        command = script.split("--features ffi-test", 1)[1].splitlines()[:2]
        self.assertNotIn("router_metrics_snapshot_", "\n".join(command))
        self.assertIn("-- --test-threads=1", "\n".join(command))

    def test_coverage_isolates_pub_download_auth_from_codecov_oidc(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/dart.yml").read_text()
        coverage = workflow.split("\n  coverage:\n", 1)[1]
        cleanup = "dart pub token remove https://pub.dev"

        self.assertIn(cleanup, coverage)
        self.assertLess(
            coverage.index("uses: dart-lang/setup-dart@"), coverage.index(cleanup)
        )
        self.assertLess(coverage.index(cleanup), coverage.index("run: bin/bootstrap"))
        self.assertLess(
            coverage.index(cleanup),
            coverage.index("run: dart pub global activate coverage"),
        )
        self.assertIn("id-token: write", coverage)
        self.assertIn("uses: codecov/codecov-action@", coverage)
        self.assertIn("use_oidc: true", coverage)
        self.assertIn("fail_ci_if_error: true", coverage)
        self.assertIn("if-no-files-found: error", coverage)

    def test_coverage_pub_token_cleanup_preserves_other_registries(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/dart.yml").read_text()
        coverage = workflow.split("\n  coverage:\n", 1)[1]
        marker = "      - name: Use anonymous pub.dev downloads\n"
        self.assertIn(marker, coverage)
        step = coverage.split(marker, 1)[1].split("\n      - ", 1)[0]
        command = textwrap.dedent(step.split("        run: |\n", 1)[1])

        with tempfile.TemporaryDirectory() as tmp_dir:
            env = dict(
                os.environ,
                PUB_CACHE=tmp_dir,
                HOME=tmp_dir,
                APPDATA=tmp_dir,
                XDG_CONFIG_HOME=tmp_dir,
                CONNECTANUM_TEST_PUB_TOKEN="not-a-real-token",
                DART_SUPPRESS_ANALYTICS="true",
            )
            env.pop("_PUB_TEST_CONFIG_DIR", None)

            def run_dart(*args: str) -> str:
                result = subprocess.run(
                    ["dart", *args],
                    env=env,
                    cwd=REPO_ROOT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                    timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stdout)
                return result.stdout

            def cleanup() -> None:
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", command],
                    env=env,
                    cwd=REPO_ROOT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                    timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stdout)

            # Refuse token writes unless Dart confirms an isolated config path.
            self.assertIn(tmp_dir, run_dart("pub", "token", "add", "--help"))
            for host in ("https://pub.dev", "https://packages.example.test"):
                run_dart(
                    "pub", "token", "add", host,
                    "--env-var", "CONNECTANUM_TEST_PUB_TOKEN",
                )
                self.assertEqual(
                    len(list(Path(tmp_dir).rglob("pub-tokens.json"))), 1
                )
            self.assertIn("https://pub.dev", run_dart("pub", "token", "list"))
            cleanup()
            remaining = run_dart("pub", "token", "list")
            self.assertNotIn("https://pub.dev", remaining)
            self.assertIn("https://packages.example.test", remaining)
            cleanup()
            self.assertEqual(remaining, run_dart("pub", "token", "list"))

    def test_coverage_pub_token_cleanup_drains_output_and_fails_closed(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/dart.yml").read_text()
        coverage = workflow.split("\n  coverage:\n", 1)[1]
        step = coverage.split(
            "      - name: Use anonymous pub.dev downloads\n", 1
        )[1].split("\n      - ", 1)[0]
        command = textwrap.dedent(step.split("        run: |\n", 1)[1])
        for status in (0, 17):
            with self.subTest(list_exit_status=status), tempfile.TemporaryDirectory() as tmp:
                dart = Path(tmp) / "dart"
                removed = Path(tmp) / "removed"
                dart.write_text(textwrap.dedent("""\
                    #!/usr/bin/env python3
                    import os
                    import signal
                    import sys
                    from pathlib import Path
                    if sys.argv[1:] == ['pub', 'token', 'list']:
                        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
                        sys.stdout.write('https://pub.dev\\n')
                        sys.stdout.flush()
                        # Exceed pipe capacity after the matching first line.
                        sys.stdout.write('https://packages.example.test\\n' * 10000)
                        sys.stdout.flush()
                        sys.exit(int(os.environ['LIST_STATUS']))
                    if sys.argv[1:] == ['pub', 'token', 'remove', 'https://pub.dev']:
                        Path(os.environ['REMOVED_MARKER']).touch()
                    else:
                        sys.exit(2)
                    """))
                dart.chmod(0o755)
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", command],
                    cwd=REPO_ROOT,
                    env=dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"],
                             LIST_STATUS=str(status), REMOVED_MARKER=str(removed)),
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    check=False, timeout=30,
                )
                self.assertEqual(result.returncode, status, result.stdout)
                self.assertEqual(removed.exists(), status == 0, result.stdout)

    def test_core_shell_scripts_are_bash_syntax_clean(self) -> None:
        for script_path in [
            BOOTSTRAP,
            COMMON,
            CONNECTANUM_ROUTER,
            CONNECTANUM_ROUTER_ALIAS,
            PACKAGE_NATIVE_ARTIFACT,
            TEST_ALL,
            TEST_FAST,
            TEST_WAMP_APP,
            VERIFY,
        ]:
            with self.subTest(script=script_path.relative_to(REPO_ROOT)):
                result = subprocess.run(
                    ["bash", "-n", str(script_path)],
                    cwd=REPO_ROOT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                )

                self.assertEqual(result.returncode, 0, result.stdout)

    def test_retry_command_retries_once_then_succeeds(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            attempts_path = Path(tmp_dir) / "attempts.txt"
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source "{COMMON}"

                sleep() {{
                  :
                }}

                flaky_command() {{
                  local attempts
                  attempts=0
                  if [[ -f "$1" ]]; then
                    attempts="$(cat "$1")"
                  fi
                  attempts=$((attempts + 1))
                  printf '%s' "$attempts" >"$1"
                  [[ "$attempts" -ge 2 ]]
                }}

                retry_command "test command" 3 5 flaky_command "{attempts_path}"
                [[ "$(cat "{attempts_path}")" == "2" ]]
                """
            )

            result = subprocess.run(
                ["bash", "-c", script],
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout)

    def test_ensure_chrome_env_exposes_canonical_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            fake_chrome = tmp_path / "chrome-under-test"
            fake_chrome.write_text(
                "#!/usr/bin/env bash\nprintf 'fake chrome: %s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            fake_chrome.chmod(0o755)
            launcher_dir = tmp_path / "launchers"
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source "{COMMON}"

                export CHROME_EXECUTABLE="{fake_chrome}"
                export CONNECTANUM_CHROME_LAUNCHER_DIR="{launcher_dir}"
                export CI=true
                ensure_chrome_env
                [[ "$(command -v connectanum-chrome)" == \
                  "{launcher_dir}/connectanum-chrome" ]]
                [[ "$CHROME_EXECUTABLE" == \
                  "{launcher_dir}/connectanum-chrome" ]]
                [[ "$(connectanum-chrome --probe)" == \
                  "fake chrome: --no-sandbox --probe" ]]

                export CI=false
                [[ "$(connectanum-chrome --probe)" == "fake chrome: --probe" ]]
                ensure_chrome_env
                [[ "$CONNECTANUM_CHROME_BINARY" == "{fake_chrome}" ]]
                """
            )

            result = subprocess.run(
                ["bash", "-c", script],
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout)

    @unittest.skipIf(os.name == "nt", "The mutation launcher requires Bash")
    def test_mutation_launcher_prepares_browser_without_requiring_it_for_vm(self) -> None:
        for system, ci, browser, native in [
            ("Linux", "true", True, False),
            ("Linux", "false", True, False),
            ("Darwin", "true", True, False),
            ("Darwin", "false", True, False),
            ("Linux", "true", False, False),
            ("Linux", "true", False, True),
        ]:
            with self.subTest(system=system, ci=ci, browser=browser, native=native), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp).resolve()
                scripts = root / "bin"
                scripts.mkdir()
                launcher = scripts / "test-mutations"
                shutil.copy2(REPO_ROOT / "bin/test-mutations", launcher)
                (scripts / "common.sh").write_text(
                    f'source "{COMMON}"\nROOT_DIR="{root}"\n'
                    'dart_workspace_bootstrap() { :; }\n'
                    'build_native_ffi_test_release() { printf "native-build\\n"; }\n'
                    + ('' if browser else 'chrome_binary() { return 1; }\n')
                )
                chrome = scripts / "chrome with spaces"
                chrome.write_text('#!/usr/bin/env bash\nprintf "chrome=%s\\n" "$@"\n')
                chrome.chmod(0o755)
                uname = scripts / "uname"
                uname.write_text(f'#!/bin/sh\nprintf "%s\\n" "{system}"\n')
                uname.chmod(0o755)
                runner = scripts / "python3"
                runner.write_text(
                    '#!/usr/bin/env bash\nprintf "runner=%s\\n" "$@"\n'
                    'if [[ -n "${CHROME_EXECUTABLE:-}" ]]; then\n'
                    '  "$CHROME_EXECUTABLE" --probe\nfi\n'
                )
                runner.chmod(0o755)
                env = dict(os.environ, PATH=str(scripts) + os.pathsep + os.environ["PATH"], CI=ci)
                for key in ("CONNECTANUM_CHROME_BINARY", "CHROME_EXECUTABLE",
                            "CONNECTANUM_CHROME_LAUNCHER_DIR", "CONNECTANUM_MUTATIONS_NATIVE"):
                    env.pop(key, None)
                if browser:
                    env["CHROME_EXECUTABLE"] = str(chrome)
                if native:
                    env["CONNECTANUM_MUTATIONS_NATIVE"] = "1"
                args = ["--target", "core-lazy-web" if browser else "core-lazy-vm",
                        "--output", "reports with spaces"]
                result = subprocess.run(
                    ["bash", str(launcher), *args], cwd=root, env=env,
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = [f"runner={arg}" for arg in ["tool/run_dart_mutations.py", *args]]
                if native:
                    expected.insert(0, "native-build")
                if browser:
                    if system == "Linux" and ci == "true":
                        expected.append("chrome=--no-sandbox")
                    expected.append("chrome=--probe")
                self.assertEqual(result.stdout.splitlines(), expected, result.stderr)

    @unittest.skipIf(os.name == "nt", "The mutation launcher requires Bash")
    def test_mutation_launcher_fails_closed_when_browser_setup_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            scripts = root / "bin"
            scripts.mkdir()
            launcher = scripts / "test-mutations"
            shutil.copy2(REPO_ROOT / "bin/test-mutations", launcher)
            (scripts / "common.sh").write_text(
                f'source "{COMMON}"\nROOT_DIR="{root}"\n'
                'dart_workspace_bootstrap() { :; }\n'
                'chrome_binary() { printf "/fixture/chrome\\n"; }\n'
                'ensure_chrome_env() { return 23; }\n'
            )
            runner = scripts / "python3"
            runner.write_text('#!/bin/sh\nprintf "runner must not start\\n"\n')
            runner.chmod(0o755)
            result = subprocess.run(
                ["bash", str(launcher), "--target", "core-lazy-web", "--output", "unused"],
                cwd=root, env=dict(os.environ, PATH=str(scripts) + os.pathsep + os.environ["PATH"]),
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
            )
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertEqual(result.stdout, "")

    def test_dart_pub_with_retry_bounds_and_retries_stalled_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            attempts_path = Path(tmp_dir) / "attempts.txt"
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source "{COMMON}"

                export CONNECTANUM_DART_PUB_ATTEMPT_TIMEOUT_SECONDS=1
                export CONNECTANUM_DART_PUB_RETRY_ATTEMPTS=2
                export CONNECTANUM_DART_PUB_RETRY_DELAY_SECONDS=0
                if dart_pub_with_retry "test pub command" \
                  bash -c '
                    attempts=0
                    if [[ -f "$1" ]]; then
                      attempts="$(cat "$1")"
                    fi
                    attempts=$((attempts + 1))
                    printf "%s" "$attempts" >"$1"
                    exec sleep 30
                  ' _ "{attempts_path}"; then
                  exit 1
                else
                  status=$?
                fi
                [[ "$status" == "124" ]]
                [[ "$(cat "{attempts_path}")" == "2" ]]
                """
            )

            result = subprocess.run(
                ["bash", "-c", script],
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
                timeout=8,
            )

            self.assertEqual(result.returncode, 0, result.stdout)

    def test_cargo_sensitive_scripts_use_retry_helper(self) -> None:
        common_script = COMMON.read_text(encoding="utf-8")
        bootstrap_script = BOOTSTRAP.read_text(encoding="utf-8")
        package_script = PACKAGE_NATIVE_ARTIFACT.read_text(encoding="utf-8")
        test_all_script = TEST_ALL.read_text(encoding="utf-8")

        self.assertIn("cargo_with_retry metadata", common_script)
        self.assertIn("cargo_with_retry build", common_script)
        self.assertIn("cargo_workspace_check", bootstrap_script)
        self.assertIn("cargo_with_retry build", package_script)
        self.assertIn("cargo_with_retry test --manifest-path", test_all_script)

    def test_root_verification_scripts_cover_compatibility_facade(self) -> None:
        for script_path in [TEST_FAST, TEST_ALL]:
            with self.subTest(script=script_path.relative_to(REPO_ROOT)):
                script = script_path.read_text(encoding="utf-8")

                self.assertIn("dart test packages/connectanum/test", script)

    def test_wamp_app_owns_its_formatting_boundary(self) -> None:
        verify_script = VERIFY.read_text(encoding="utf-8")
        wamp_app_script = TEST_WAMP_APP.read_text(encoding="utf-8")

        self.assertIn(
            "':(exclude)examples/wamp_app/**'",
            verify_script,
        )
        self.assertIn(
            "git ls-files --cached --others --exclude-standard",
            verify_script,
        )
        self.assertEqual(
            wamp_app_script.count(
                "dart format --output=none --set-exit-if-changed ."
            ),
            2,
        )
        self.assertEqual(
            wamp_app_script.count(
                "dart format --output=none --set-exit-if-changed benchmark lib test"
            ),
            1,
        )

    def test_wamp_app_browser_tests_are_serial_and_bounded(self) -> None:
        script = TEST_WAMP_APP.read_text(encoding="utf-8")

        self.assertIn("CONNECTANUM_WAMP_APP_BROWSER_TEST_ATTEMPTS", script)
        self.assertIn(
            "CONNECTANUM_WAMP_APP_BROWSER_TEST_ATTEMPT_TIMEOUT_SECONDS",
            script,
        )
        self.assertIn("run_command_with_timeout", script)
        self.assertIn('for test_file in "${browser_tests[@]}"', script)
        self.assertNotIn("--concurrency=1", script)

    def test_connectanum_router_wrapper_delegates_help_without_native_build(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_dart = Path(tmp_dir) / "dart"
            fake_dart.write_text(
                "#!/usr/bin/env bash\nprintf 'dart %s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            fake_dart.chmod(0o755)

            result = subprocess.run(
                [str(CONNECTANUM_ROUTER), "--help"],
                cwd=REPO_ROOT,
                env={"PATH": f"{tmp_dir}:/usr/bin:/bin"},
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(
                result.stdout.strip(),
                "dart run connectanum_router --help",
            )

    def test_connectanum_router_wrapper_appends_resolved_native_lib(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_dart = Path(tmp_dir) / "dart"
            fake_dart.write_text(
                "#!/usr/bin/env bash\nprintf 'dart %s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            fake_dart.chmod(0o755)

            result = subprocess.run(
                [str(CONNECTANUM_ROUTER), "--config", "/tmp/router.yaml"],
                cwd=REPO_ROOT,
                env={
                    "CONNECTANUM_NATIVE_LIB": "/tmp/libct_ffi.so",
                    "PATH": f"{tmp_dir}:/usr/bin:/bin",
                },
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(
                result.stdout.strip(),
                "dart run connectanum_router --config /tmp/router.yaml --native-lib /tmp/libct_ffi.so",
            )

    def test_connectanum_router_wrapper_preserves_explicit_native_lib(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_dart = Path(tmp_dir) / "dart"
            fake_dart.write_text(
                "#!/usr/bin/env bash\nprintf 'dart %s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            fake_dart.chmod(0o755)

            result = subprocess.run(
                [
                    str(CONNECTANUM_ROUTER),
                    "--config",
                    "/tmp/router.yaml",
                    "--native-lib=/custom/libct_ffi.so",
                ],
                cwd=REPO_ROOT,
                env={"PATH": f"{tmp_dir}:/usr/bin:/bin"},
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(
                result.stdout.strip(),
                "dart run connectanum_router --config /tmp/router.yaml --native-lib=/custom/libct_ffi.so",
            )

    def test_connectanum_router_wrapper_uses_release_runtime_helper(self) -> None:
        wrapper_script = CONNECTANUM_ROUTER.read_text(encoding="utf-8")
        common_script = COMMON.read_text(encoding="utf-8")

        self.assertIn("ensure_native_release_runtime", wrapper_script)
        self.assertIn("build_native_release()", common_script)
        self.assertIn(
            "cargo_with_retry build --manifest-path native/transport/Cargo.toml -p ct_ffi --release",
            common_script,
        )

    def test_connectanum_router_alias_delegates_to_checkout_wrapper(self) -> None:
        alias_script = CONNECTANUM_ROUTER_ALIAS.read_text(encoding="utf-8")

        self.assertIn('exec "$(dirname "$0")/connectanum-router" "$@"', alias_script)

        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_dart = Path(tmp_dir) / "dart"
            fake_dart.write_text(
                "#!/usr/bin/env bash\nprintf 'dart %s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            fake_dart.chmod(0o755)

            result = subprocess.run(
                [str(CONNECTANUM_ROUTER_ALIAS), "--help"],
                cwd=REPO_ROOT,
                env={"PATH": f"{tmp_dir}:/usr/bin:/bin"},
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(
                result.stdout.strip(),
                "dart run connectanum_router --help",
            )

    def test_connectanum_router_package_exposes_pub_executable(self) -> None:
        pubspec = CONNECTANUM_ROUTER_PACKAGE_PUBSPEC.read_text(encoding="utf-8")
        bin_entry = CONNECTANUM_ROUTER_PACKAGE_BIN.read_text(encoding="utf-8")

        self.assertIn("\nname: connectanum_router\n", f"\n{pubspec}")
        self.assertIn("\nexecutables:\n  connectanum_router:\n", f"\n{pubspec}")
        self.assertIn("Future<void> main(List<String> args)", bin_entry)
        self.assertIn("RouterConfigLoaderIo.fromFile", bin_entry)
        self.assertIn(
            "Usage: connectanum_router --config <path>",
            bin_entry,
        )
        self.assertNotIn(
            "Usage: dart run connectanum_router --config <path>",
            bin_entry,
        )

    def test_router_openmetrics_uses_router_native_routes(self) -> None:
        bin_entry = CONNECTANUM_ROUTER_PACKAGE_BIN.read_text(encoding="utf-8")
        settings = CONNECTANUM_ROUTER_SETTINGS.read_text(encoding="utf-8")
        production_sources = [
            CONNECTANUM_ROUTER_PACKAGE_BIN,
            *CONNECTANUM_ROUTER_PACKAGE_LIB.rglob("*.dart"),
        ]

        for source_path in production_sources:
            with self.subTest(source=source_path.relative_to(REPO_ROOT)):
                source = source_path.read_text(encoding="utf-8")
                self.assertNotIn(
                    "HttpServer.bind",
                    source,
                    "Router package production sources must not serve "
                    "OpenMetrics/health through a sidecar Dart HttpServer.",
                )

        self.assertIn("withOpenMetricsHttpRoutes()", bin_entry)
        self.assertIn("extension RouterSettingsOpenMetricsHttp", settings)
        self.assertIn("HttpRouteActionType.internalCall", settings)
        self.assertIn("connectanum.metrics.healthz", settings)
        self.assertIn("connectanum.metrics.openmetrics", settings)
        self.assertIn("connectanum_open_metrics_listener", settings)

    def test_connectanum_bench_package_exposes_router_bench_executable(self) -> None:
        pubspec = CONNECTANUM_BENCH_PACKAGE_PUBSPEC.read_text(encoding="utf-8")
        bin_entry = CONNECTANUM_BENCH_PACKAGE_BIN.read_text(encoding="utf-8")

        self.assertIn("\nname: connectanum_bench\n", f"\n{pubspec}")
        self.assertIn("\nexecutables:\n  router_bench:\n", f"\n{pubspec}")
        self.assertIn("  bench_router_service:\n", pubspec)
        self.assertIn("  wamp_client_worker:\n", pubspec)
        self.assertIn("Future<void> main(List<String> arguments)", bin_entry)
        self.assertIn("buildArgParser()", bin_entry)
        self.assertIn("BenchmarkRunner(", bin_entry)
        self.assertIn(
            "../tool/bench_main.dart",
            CONNECTANUM_BENCH_SERVICE_BIN.read_text(encoding="utf-8"),
        )
        self.assertIn(
            "../tool/wamp_client_main.dart",
            CONNECTANUM_BENCH_WORKER_BIN.read_text(encoding="utf-8"),
        )

    def test_common_suppresses_dart_analytics_by_default(self) -> None:
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            unset DART_SUPPRESS_ANALYTICS
            source "{COMMON}"
            [[ "$DART_SUPPRESS_ANALYTICS" == "true" ]]
            """
        )

        result = subprocess.run(
            ["bash", "-c", script],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout)

    def test_browser_websocket_smoke_retries_without_retry_annotations(
        self,
    ) -> None:
        script = TEST_ALL.read_text(encoding="utf-8")
        common_script = COMMON.read_text(encoding="utf-8")

        self.assertIn("run_client_browser_websocket_test()", script)
        self.assertIn('CONNECTANUM_BROWSER_TEST_ATTEMPTS:-2', script)
        self.assertIn(
            "CONNECTANUM_BROWSER_TEST_ATTEMPT_TIMEOUT_SECONDS:-420",
            script,
        )
        self.assertIn("run_browser_websocket_test_attempt()", script)
        self.assertIn(
            'run_command_with_timeout \\\n        "Browser WebSocket smoke"',
            script,
        )
        self.assertIn(
            "%s exceeded %ss; terminating stalled command.",
            common_script,
        )
        self.assertIn('args+=(--reporter=expanded)', script)
        self.assertIn(
            "the final attempt keeps the default reporter",
            script,
        )
        self.assertIn(
            'if run_browser_websocket_test_attempt "$attempt_timeout_seconds" '
            'dart test "${args[@]}"; then',
            script,
        )
        self.assertIn('return "$status"', script)

    def test_full_verify_runs_core_browser_security_tests(self) -> None:
        script = TEST_ALL.read_text(encoding="utf-8")

        self.assertIn("run_core_browser_tests()", script)
        self.assertIn(
            "test/authentication/scram_key_derivation_web_test.dart",
            script,
        )
        self.assertIn(
            "test/serializer \\\n",
            script,
        )
        self.assertIn('"Core browser tests"', script)
        self.assertIn(
            "run_core_browser_tests\n  run_client_browser_websocket_test",
            script,
        )

    def test_browser_verification_and_coverage_include_e2ee_regressions(self) -> None:
        for path in (TEST_ALL, REPO_ROOT / "bin" / "test-browser-coverage"):
            with self.subTest(script=path.name):
                script = path.read_text(encoding="utf-8")
                self.assertIn("test/message_e2ee_payload_test.dart", script)
                self.assertIn("test/message_e2ee_regression_test.dart", script)
                self.assertIn("test/message_lazy_payload_regression_test.dart", script)
                self.assertIn("test/message_invocation_test.dart", script)
                self.assertIn("test/message_result_test.dart", script)

    def test_browser_verification_and_coverage_include_completion_boundaries(self) -> None:
        for path in (TEST_ALL, REPO_ROOT / "bin" / "test-browser-coverage"):
            with self.subTest(script=path.name):
                script = path.read_text(encoding="utf-8")
                self.assertIn("test/mcp_completion_test.dart", script)
                self.assertIn("test/mcp_completion_regression_test.dart", script)

    def test_browser_verification_and_coverage_include_registration_lifecycle(self) -> None:
        for path in (TEST_ALL, REPO_ROOT / "bin" / "test-browser-coverage"):
            with self.subTest(script=path.name):
                script = path.read_text(encoding="utf-8")
                self.assertIn("test/message_registered_regression_test.dart", script)

    def test_browser_verification_and_coverage_include_handshake_metadata(self) -> None:
        for name in ("test-all", "test-browser-coverage"):
            with self.subTest(script=name):
                script = (REPO_ROOT / "bin" / name).read_text(encoding="utf-8")
                self.assertIn("test/serializer_challenge_welcome_test.dart", script)
                self.assertIn("test/details_feature_announcement_test.dart", script)

    def test_browser_verification_and_coverage_include_lazy_metadata(self) -> None:
        for name in ("test-all", "test-browser-coverage"):
            with self.subTest(script=name):
                script = (REPO_ROOT / "bin" / name).read_text(encoding="utf-8")
                self.assertIn("test/custom_fields_test.dart", script)
                self.assertIn("test/custom_fields_regression_test.dart", script)
                self.assertIn("test/message_details_regression_test.dart", script)

    def test_browser_verification_and_coverage_include_subscription_lifecycle(self) -> None:
        for name in ("test-all", "test-browser-coverage"):
            with self.subTest(script=name):
                script = (REPO_ROOT / "bin" / name).read_text(encoding="utf-8")
                self.assertIn("test/message_subscribed_test.dart", script)
                self.assertIn("test/message_subscribed_regression_test.dart", script)

    def test_browser_verification_and_coverage_include_ppt_transcoding(self) -> None:
        for name in ("test-all", "test-browser-coverage"):
            with self.subTest(script=name):
                script = (REPO_ROOT / "bin" / name).read_text(encoding="utf-8")
                self.assertIn("test/message_invocation_transcoding_test.dart", script)
                self.assertIn("test/message_invocation_regression_test.dart", script)
                self.assertIn("test/message_invocation_response_lifecycle_test.dart", script)

    def test_timeout_helper_does_not_leave_success_watchdog_alive(self) -> None:
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            source "{COMMON}"
            run_command_with_timeout "quick command" 5 bash -c 'printf done'
            """
        )

        result = subprocess.run(
            ["bash", "-c", script],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=3,
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "done")


if __name__ == "__main__":
    unittest.main()
