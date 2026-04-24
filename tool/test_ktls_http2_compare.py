import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

import ktls_http2_compare as compare


class KtlsHttp2CompareTest(unittest.TestCase):
    def test_build_comparison_adds_group_rollups_and_hotspots(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline_dir = root / "baseline"
            ktls_dir = root / "ktls"
            baseline_dir.mkdir()
            ktls_dir.mkdir()

            self._write_summary(
                baseline_dir / "bench_results.summary.json",
                [
                    self._row("h2_sustained_transfer", 1, 4000.0, 10.0, 8.0),
                    self._row("h2_sustained_transfer", 4, 4800.0, 9.5, 8.5),
                    self._row("h2_multiplexed_streams", 1, 6350.0, 33.0, 30.0),
                    self._row("h2_multiplexed_streams", 4, 6565.0, 32.5, 28.0),
                ],
            )
            self._write_summary(
                ktls_dir / "bench_results.summary.json",
                [
                    self._row("h2_sustained_transfer", 1, 2000.0, 16.0, 12.0),
                    self._row("h2_sustained_transfer", 4, 2150.0, 16.5, 12.5),
                    self._row("h2_multiplexed_streams", 1, 5725.0, 37.5, 33.0),
                    self._row("h2_multiplexed_streams", 4, 2501.0, 220.0, 150.0),
                ],
            )
            self._write_resource_usage(
                baseline_dir / "resource-usage.txt",
                user_seconds=10.0,
                system_seconds=2.0,
                cpu_percent=98.0,
                elapsed="0:12.50",
                max_rss_kib=4096.0,
            )
            self._write_resource_usage(
                ktls_dir / "resource-usage.txt",
                user_seconds=12.0,
                system_seconds=3.0,
                cpu_percent=96.0,
                elapsed="0:14.00",
                max_rss_kib=6144.0,
            )

            comparison = compare.build_comparison(
                baseline_dir / "bench_results.summary.json",
                ktls_dir / "bench_results.summary.json",
            )

            workload_groups = comparison["summary"]["group_summaries"]["by_workload"]
            runtime_groups = comparison["summary"]["group_summaries"][
                "by_native_runtime_threads"
            ]

            self.assertEqual(comparison["summary"]["comparable_rows"], 4)
            self.assertEqual(workload_groups[0]["label"], "h2_multiplexed_streams")
            self.assertEqual(runtime_groups[0]["label"], "threads=4")
            self.assertEqual(
                comparison["summary"]["hotspots"]["by_workload"]["label"],
                "h2_multiplexed_streams",
            )
            self.assertEqual(
                comparison["summary"]["hotspots"]["by_native_runtime_threads"]["label"],
                "threads=4",
            )
            self.assertAlmostEqual(
                workload_groups[0]["throughput"]["average_pct_delta"],
                -35.87327812127064,
            )
            self.assertAlmostEqual(
                runtime_groups[0]["latency_p95"]["average_pct_delta"],
                325.30364372469637,
            )
            self.assertAlmostEqual(
                comparison["summary"]["resource_usage"]["delta"]["elapsed_seconds"],
                1.5,
            )

            markdown = compare.render_markdown(comparison)
            self.assertIn("## Group Rollups", markdown)
            self.assertIn("Workload-family investigation focus", markdown)
            self.assertIn("Runtime-thread investigation focus", markdown)
            self.assertIn("### By workload family", markdown)
            self.assertIn("### By native runtime threads", markdown)
            self.assertIn("h2_multiplexed_streams", markdown)
            self.assertIn("threads=4", markdown)
            self.assertIn("Elapsed wall time: baseline 12.50s, kTLS 14.00s", markdown)

    @staticmethod
    def _write_summary(path: Path, workloads: list[dict]) -> None:
        path.write_text(json.dumps({"workloads": workloads}) + "\n")

    @staticmethod
    def _write_resource_usage(
        path: Path,
        *,
        user_seconds: float,
        system_seconds: float,
        cpu_percent: float,
        elapsed: str,
        max_rss_kib: float,
    ) -> None:
        path.write_text(
            "\n".join(
                [
                    f"\tUser time (seconds): {user_seconds}",
                    f"\tSystem time (seconds): {system_seconds}",
                    f"\tPercent of CPU this job got: {cpu_percent}%",
                    f"\tElapsed (wall clock) time (h:mm:ss or m:ss): {elapsed}",
                    f"\tMaximum resident set size (kbytes): {max_rss_kib}",
                ]
            )
            + "\n"
        )

    @staticmethod
    def _row(
        workload: str,
        native_runtime_threads: int,
        throughput_mbps: float,
        latency_p95_ms: float,
        latency_avg_ms: float,
    ) -> dict:
        return {
            "scenario": "h2_ktls_benchmark",
            "workload": workload,
            "protocol": "http2",
            "router_workers": 1,
            "native_runtime_threads": native_runtime_threads,
            "throughput_mbps": throughput_mbps,
            "latency_p95_ms": latency_p95_ms,
            "latency_avg_ms": latency_avg_ms,
        }


if __name__ == "__main__":
    unittest.main()
