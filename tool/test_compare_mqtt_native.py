"""Execution checks for the optional hosted native MQTT comparison."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeMqttComparisonTest(unittest.TestCase):
    def run_comparison(self, fail_target="", valid=True, workers="", inherited=""):
        with tempfile.TemporaryDirectory(prefix="mqtt compare ") as tmp:
            root = Path(tmp)
            log = root / "calls.jsonl"
            python = root / "python3"
            python.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "library = os.environ['CONNECTANUM_NATIVE_LIB']\n"
                "with open(os.environ['FAKE_LOG'], 'a') as out:\n"
                " out.write(json.dumps([library, sys.argv[1:], os.environ.get('CONNECTANUM_NATIVE_RUNTIME_THREADS')]) + '\\n')\n"
                "target = os.environ.get('FAIL_TARGET')\n"
                "sys.exit(1 if target and target in library else 0)\n"
            )
            python.chmod(0o755)
            libraries = [root / "baseline.so", root / "candidate.so"]
            if valid:
                for library in libraries:
                    library.touch()
            output = root / "results with spaces"
            result = subprocess.run(
                ["bash", str(ROOT / "tool/compare_mqtt_native.sh"),
                 *map(str, libraries), str(output)],
                cwd=ROOT, capture_output=True, text=True,
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "FAKE_LOG": str(log), "FAIL_TARGET": fail_target,
                     "MQTT_COMPARE_WORKER_THREADS": workers,
                     "CONNECTANUM_NATIVE_RUNTIME_THREADS": inherited},
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            exits = [p.read_text().strip() for p in sorted(output.glob("*/*/exit-code.txt"))]
            policies = {p.parent.name: p.read_text().strip()
                        for p in output.glob('*/runtime-workers.txt')}
            return result.returncode, calls, exits, policies

    def test_same_harness_preserves_budgets_and_alternates_native_libraries(self):
        result, calls, exits, policies = self.run_comparison()
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 12)
        self.assertEqual(exits, ["0"] * 12)
        self.assertEqual(set(policies.values()), {'auto'})
        for index, (library, arguments, workers) in enumerate(calls):
            self.assertEqual(workers, '')
            self.assertTrue(library.endswith("baseline.so" if index // 3 % 2 == 0 else "candidate.so"))
            self.assertEqual(arguments[:2], ["tool/run_mqtt_benchmark_gate.py", "--native-router"])
            budget = json.loads((ROOT / arguments[3]).read_text())
            self.assertEqual(budget["repetitions"], 5)
            self.assertEqual(budget["min_delivered_throughput_ratio_vs_mosquitto"],
                             0.75 if index % 3 == 2 else 0.7)
            self.assertEqual(budget["max_broker_cpu_ratio_vs_mosquitto"],
                             4.0 if index % 3 == 2 else 5.0)

    def test_baseline_misses_are_recorded_and_do_not_hide_candidate_results(self):
        result, calls, exits, _ = self.run_comparison("baseline")
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 12)
        self.assertEqual(exits.count("1"), 6)

    def test_candidate_misses_fail_after_collecting_every_comparison(self):
        result, calls, exits, _ = self.run_comparison("candidate")
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 12)
        self.assertEqual(exits.count("1"), 6)

    def test_missing_native_libraries_fail_before_starting_benchmarks(self):
        result, calls, exits, policies = self.run_comparison(valid=False)
        self.assertEqual(result, 2)
        self.assertEqual(calls, [])
        self.assertEqual(exits, [])
        self.assertEqual(policies, {})

    def test_candidate_worker_override_is_recorded_and_does_not_leak_to_baseline(self):
        result, calls, exits, policies = self.run_comparison(workers='2', inherited='4')
        self.assertEqual(result, 0)
        self.assertEqual(exits, ['0'] * 12)
        self.assertEqual([call[2] for call in calls], ['4'] * 3 + ['2'] * 3 + ['4'] * 3 + ['2'] * 3)
        self.assertEqual(policies, {'baseline-1': '4', 'candidate-1': '2',
                                    'baseline-2': '4', 'candidate-2': '2'})

    def test_omitted_override_preserves_inherited_worker_policy_for_both_libraries(self):
        result, calls, _, policies = self.run_comparison(inherited='3')
        self.assertEqual(result, 0)
        self.assertEqual([call[2] for call in calls], ['3'] * 12)
        self.assertEqual(set(policies.values()), {'3'})

    def test_invalid_worker_counts_fail_before_any_measurement(self):
        for workers in ('0', '-1', 'two'):
            with self.subTest(workers=workers):
                result, calls, exits, policies = self.run_comparison(workers=workers)
                self.assertEqual((result, calls, exits, policies), (2, [], [], {}))

    def test_diagnostic_modes_do_not_mix_recovery_with_new_measurements(self):
        workflow = (ROOT / '.github/workflows/mqtt-profile.yml').read_text()
        block = workflow.split('- name: Validate diagnostic mode', 1)[1].split('run: |\n', 1)[1]
        lines = []
        for line in block.splitlines():
            if line.startswith('          '):
                lines.append(line[10:])
            elif line.strip():
                break
        self.assertTrue(lines)
        for recovery, workers, expected in [('', '', 0), ('123', '', 0),
                                             ('', '2', 0), ('123', '2', 2)]:
            with self.subTest(recovery=recovery, workers=workers):
                result = subprocess.run(['bash'], input='\n'.join(lines), text=True,
                                        capture_output=True,
                                        env={**os.environ, 'RECOVER_RUN': recovery,
                                             'COMPARE_WORKERS': workers})
                self.assertEqual(result.returncode, expected, result.stderr)


    def intel_probe_script(self):
        workflow = (ROOT / '.github/workflows/mqtt-profile.yml').read_text()
        block = workflow.split('- name: Identify the requested Intel hardware', 1)[1].split('run: |\n', 1)[1]
        lines = []
        for line in block.splitlines():
            if line.startswith('          '):
                lines.append(line[10:])
            elif line.strip():
                break
        return '\n'.join(lines)

    def test_intel_hardware_probe_marks_other_models_unmeasured(self):
        for model, wanted in [
            ('Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz', True),
            ('AMD EPYC 7763 64-Core Processor', False),
            ('Intel(R) Xeon(R) Platinum 6973P-C', False),
            ('', False),
        ]:
            with self.subTest(model=model), tempfile.TemporaryDirectory(prefix='mqtt cpu ') as tmp:
                root = Path(tmp)
                cpu = root / 'cpu info.txt'
                cpu.write_text(f'processor : 0\nmodel name : {model}\n')
                output = root / 'github-output'
                proof = root / 'proof'
                result = subprocess.run(['bash'], input=self.intel_probe_script(), text=True,
                    capture_output=True, cwd=root,
                    env={**os.environ, 'MQTT_CPU_INFO_PATH': str(cpu),
                         'INTEL_PROBE_OUTPUT': str(proof), 'GITHUB_OUTPUT': str(output),
                         'RECOVER_RUN': '', 'COMPARE_WORKERS': ''})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads((proof / 'status.json').read_text()),
                                 {'matched_intel_8370c': wanted, 'benchmark_executed': False})
                self.assertEqual(output.read_text(), f'matches={str(wanted).lower()}\n')
                self.assertEqual((proof / 'cpu-model.txt').read_text().strip(), model)

    def test_intel_probe_rejects_mode_mixing_before_any_evidence(self):
        for recovery, workers in [('123', ''), ('', '1')]:
            with self.subTest(recovery=recovery, workers=workers), tempfile.TemporaryDirectory() as tmp:
                proof = Path(tmp) / 'proof'
                result = subprocess.run(['bash'], input=self.intel_probe_script(), text=True,
                    capture_output=True, env={**os.environ, 'INTEL_PROBE_OUTPUT': str(proof),
                        'RECOVER_RUN': recovery, 'COMPARE_WORKERS': workers})
                self.assertEqual(result.returncode, 2)
                self.assertFalse(proof.exists())

    def test_intel_comparison_keeps_userland_reference_and_measurement_guards(self):
        workflow = (ROOT / '.github/workflows/mqtt-profile.yml').read_text()
        intel = workflow.split('  intel:\n', 1)[1]
        self.assertIn('runs-on: ubuntu-22.04', intel)
        self.assertIn('ubuntu:24.04@sha256:78d4744ead1f5b19b04d0df558ab182a5300903900755e515b2ca4d10eb2044d', intel)
        self.assertEqual(intel.count("if: ${{ steps.cpu.outputs.matches == 'true' }}"), 5)
        self.assertIn("mosquitto version 2.0.18", intel)
        self.assertIn('cp native/transport/Cargo.lock', intel)
        self.assertEqual(intel.count('--release --features ffi-test --locked'), 2)
        self.assertIn('bash tool/compare_mqtt_native.sh', intel)
        self.assertIn('exit "$result"', intel)
        self.assertIn('benchmark_executed":true', intel)


if __name__ == "__main__":
    unittest.main()
