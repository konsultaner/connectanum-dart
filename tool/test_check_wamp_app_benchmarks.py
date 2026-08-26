#!/usr/bin/env python3
"""Regression checks for the WampApp production benchmark gate."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "bin/check-wamp-app-benchmarks"


class WampAppBenchmarkGateTest(unittest.TestCase):
    def _run_gate(
        self,
        policy: dict[str, object],
        result_lines: list[str],
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
        with tempfile.TemporaryDirectory() as temporary_dir:
            temporary = Path(temporary_dir)
            policy_path = temporary / "policy.json"
            results_path = temporary / "results.log"
            summary_path = temporary / "summary.json"
            policy_path.write_text(json.dumps(policy), encoding="utf-8")
            results_path.write_text("\n".join(result_lines) + "\n", encoding="utf-8")
            completed = subprocess.run(
                [
                    str(CHECKER),
                    "--policy",
                    str(policy_path),
                    "--results",
                    str(results_path),
                    "--summary",
                    str(summary_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            return completed, summary

    @staticmethod
    def _policy() -> dict[str, object]:
        return {
            "schema_version": 1,
            "benchmarks": {
                "wamp_app_application": {
                    "metrics": {
                        "onboarding.p95_ms": {"maximum": 60000},
                        "direct_message.messages_per_second": {"minimum": 1.0},
                    }
                },
                "wamp_app_attachment_transfer:memory": {
                    "metrics": {
                        "encrypt.median_gbit_per_second": {"minimum": 0.02},
                    }
                },
            },
        }

    def test_passes_complete_finite_results_and_writes_summary(self) -> None:
        completed, summary = self._run_gate(
            self._policy(),
            [
                "noise before the benchmark record",
                "WAMP_APP_PRODUCTION_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 1,
                        "benchmark": "wamp_app_application",
                        "onboarding": {"p95_ms": 24000.0},
                        "direct_message": {"messages_per_second": 8.5},
                    }
                ),
                "WAMP_APP_ATTACHMENT_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 1,
                        "benchmark": "wamp_app_attachment_transfer",
                        "cache": "memory",
                        "encrypt": {"median_gbit_per_second": 0.08},
                    }
                ),
            ],
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(summary["verdict"], "pass")
        self.assertEqual(summary["violations"], [])
        self.assertEqual(len(summary["checks"]), 3)
        self.assertNotIn("noise before", json.dumps(summary))

    def test_fails_closed_when_a_required_result_is_missing(self) -> None:
        completed, summary = self._run_gate(
            self._policy(),
            [
                "WAMP_APP_PRODUCTION_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 1,
                        "benchmark": "wamp_app_application",
                        "onboarding": {"p95_ms": 24000.0},
                        "direct_message": {"messages_per_second": 8.5},
                    }
                )
            ],
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(summary["verdict"], "fail")
        self.assertTrue(
            any("wamp_app_attachment_transfer:memory" in item for item in summary["violations"])
        )

    def test_fails_closed_for_duplicate_or_out_of_budget_results(self) -> None:
        application = (
            "WAMP_APP_PRODUCTION_BENCHMARK "
            + json.dumps(
                {
                    "schema_version": 1,
                    "benchmark": "wamp_app_application",
                    "onboarding": {"p95_ms": 90000.0},
                    "direct_message": {"messages_per_second": 0.5},
                }
            )
        )
        completed, summary = self._run_gate(
            self._policy(),
            [
                application,
                application,
                "WAMP_APP_ATTACHMENT_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 1,
                        "benchmark": "wamp_app_attachment_transfer",
                        "cache": "memory",
                        "encrypt": {"median_gbit_per_second": 0.08},
                    }
                ),
            ],
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(summary["verdict"], "fail")
        violations = "\n".join(summary["violations"])
        self.assertIn("duplicate", violations)
        self.assertIn("onboarding.p95_ms", violations)
        self.assertIn("direct_message.messages_per_second", violations)

    def test_fails_closed_for_a_mismatched_record_schema(self) -> None:
        completed, summary = self._run_gate(
            self._policy(),
            [
                "WAMP_APP_PRODUCTION_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 2,
                        "benchmark": "wamp_app_application",
                        "onboarding": {"p95_ms": 24000.0},
                        "direct_message": {"messages_per_second": 8.5},
                    }
                ),
                "WAMP_APP_ATTACHMENT_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 1,
                        "benchmark": "wamp_app_attachment_transfer",
                        "cache": "memory",
                        "encrypt": {"median_gbit_per_second": 0.08},
                    }
                ),
            ],
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(summary["verdict"], "fail")
        self.assertTrue(
            any("schema version mismatch" in item for item in summary["violations"])
        )

    def test_fails_closed_for_a_mismatched_workload_attribute(self) -> None:
        policy = {
            "schema_version": 1,
            "benchmarks": {
                "wamp_app_application": {
                    "attributes": {"workload.transport": "websocket-cbor"},
                    "metrics": {"onboarding.p95_ms": {"maximum": 60000}},
                }
            },
        }
        completed, summary = self._run_gate(
            policy,
            [
                "WAMP_APP_PRODUCTION_BENCHMARK "
                + json.dumps(
                    {
                        "schema_version": 1,
                        "benchmark": "wamp_app_application",
                        "workload": {"transport": "rawsocket-cbor"},
                        "onboarding": {"p95_ms": 24000.0},
                    }
                )
            ],
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(summary["verdict"], "fail")
        self.assertTrue(
            any("workload.transport" in item for item in summary["violations"])
        )


if __name__ == "__main__":
    unittest.main()
