import sys
import tempfile
import tomllib
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

import filter_bench_scenario as filter_scenario


class FilterBenchScenarioTest(unittest.TestCase):
    def test_filter_scenario_keeps_requested_workloads_in_source_order(self) -> None:
        source = {
            "name": "h2_ktls_multiplex_stability",
            "description": "HTTP/2 stability scenario.",
            "workloads": [
                {"name": "h2_multiplexed_streams_s1", "protocol": "h2", "iterations": 48},
                {"name": "h2_multiplexed_streams_s2", "protocol": "h2", "iterations": 48},
                {"name": "h2_multiplexed_streams_s4", "protocol": "h2", "iterations": 48},
            ],
        }

        filtered = filter_scenario.filter_scenario_document(
            source,
            ["h2_multiplexed_streams_s4", "h2_multiplexed_streams_s1"],
        )

        self.assertEqual(filtered["name"], "h2_ktls_multiplex_stability")
        self.assertEqual(
            [workload["name"] for workload in filtered["workloads"]],
            ["h2_multiplexed_streams_s1", "h2_multiplexed_streams_s4"],
        )
        self.assertIn(
            "Focused workloads: h2_multiplexed_streams_s4, h2_multiplexed_streams_s1.",
            filtered["description"],
        )

    def test_write_scenario_round_trips_filtered_output(self) -> None:
        source_toml = """
name = "h2_ktls_multiplex_stability"
description = "HTTP/2 stability scenario."

[[workloads]]
name = "h2_multiplexed_streams_s1"
protocol = "h2"
iterations = 48
reuse_connections = true

[[workloads]]
name = "h2_multiplexed_streams_s4"
protocol = "h2"
iterations = 48
reuse_connections = false
""".strip()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_path = root / "source.toml"
            output_path = root / "filtered.toml"
            source_path.write_text(source_toml + "\n")

            document = tomllib.loads(source_path.read_text())
            filtered = filter_scenario.filter_scenario_document(
                document,
                ["h2_multiplexed_streams_s4"],
            )
            filter_scenario.write_scenario_document(filtered, output_path)

            round_tripped = tomllib.loads(output_path.read_text())
            self.assertEqual(
                [workload["name"] for workload in round_tripped["workloads"]],
                ["h2_multiplexed_streams_s4"],
            )
            self.assertFalse(round_tripped["workloads"][0]["reuse_connections"])
            self.assertEqual(round_tripped["name"], "h2_ktls_multiplex_stability")

    def test_parse_workload_names_rejects_empty_and_duplicate_entries(self) -> None:
        with self.assertRaisesRegex(ValueError, "At least one workload name"):
            filter_scenario.parse_workload_names(" , ")

        with self.assertRaisesRegex(ValueError, "Duplicate workload names"):
            filter_scenario.parse_workload_names("foo, bar, foo")

    def test_filter_scenario_rejects_unknown_workloads(self) -> None:
        source = {
            "name": "example",
            "workloads": [{"name": "known"}],
        }

        with self.assertRaisesRegex(
            ValueError,
            "Scenario does not define requested workload",
        ):
            filter_scenario.filter_scenario_document(source, ["unknown"])


if __name__ == "__main__":
    unittest.main()
