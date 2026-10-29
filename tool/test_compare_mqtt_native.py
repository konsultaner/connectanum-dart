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
    def run_comparison(self, fail_target="", valid=True):
        with tempfile.TemporaryDirectory(prefix="mqtt compare ") as tmp:
            root = Path(tmp)
            log = root / "calls.jsonl"
            python = root / "python3"
            python.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "library = os.environ['CONNECTANUM_NATIVE_LIB']\n"
                "with open(os.environ['FAKE_LOG'], 'a') as out:\n"
                " out.write(json.dumps([library, sys.argv[1:]]) + '\\n')\n"
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
                     "FAKE_LOG": str(log), "FAIL_TARGET": fail_target},
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            exits = [p.read_text().strip() for p in sorted(output.glob("*/*/exit-code.txt"))]
            return result.returncode, calls, exits

    def test_same_harness_preserves_budgets_and_alternates_native_libraries(self):
        result, calls, exits = self.run_comparison()
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 12)
        self.assertEqual(exits, ["0"] * 12)
        for index, (library, arguments) in enumerate(calls):
            self.assertTrue(library.endswith("baseline.so" if index // 3 % 2 == 0 else "candidate.so"))
            self.assertEqual(arguments[:2], ["tool/run_mqtt_benchmark_gate.py", "--native-router"])
            budget = json.loads((ROOT / arguments[3]).read_text())
            self.assertEqual(budget["repetitions"], 5)
            self.assertEqual(budget["min_delivered_throughput_ratio_vs_mosquitto"],
                             0.75 if index % 3 == 2 else 0.7)
            self.assertEqual(budget["max_broker_cpu_ratio_vs_mosquitto"],
                             4.0 if index % 3 == 2 else 5.0)

    def test_baseline_misses_are_recorded_and_do_not_hide_candidate_results(self):
        result, calls, exits = self.run_comparison("baseline")
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 12)
        self.assertEqual(exits.count("1"), 6)

    def test_candidate_misses_fail_after_collecting_every_comparison(self):
        result, calls, exits = self.run_comparison("candidate")
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 12)
        self.assertEqual(exits.count("1"), 6)

    def test_missing_native_libraries_fail_before_starting_benchmarks(self):
        result, calls, exits = self.run_comparison(valid=False)
        self.assertEqual(result, 2)
        self.assertEqual(calls, [])
        self.assertEqual(exits, [])


if __name__ == "__main__":
    unittest.main()
