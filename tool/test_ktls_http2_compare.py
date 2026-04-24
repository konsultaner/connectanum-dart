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
                    self._row(
                        "h2_multiplexed_streams",
                        1,
                        6350.0,
                        33.0,
                        30.0,
                        transport=self._transport(
                            backpressure_events=76,
                            backpressure_alerts=2,
                            max_backpressure_depth_after=4,
                        ),
                    ),
                    self._row(
                        "h2_multiplexed_streams",
                        4,
                        6565.0,
                        32.5,
                        28.0,
                        transport=self._transport(
                            backpressure_events=82,
                            backpressure_alerts=4,
                            max_backpressure_depth_after=4,
                        ),
                        connections_opened=4,
                        samples_per_connection_avg=8.0,
                        stream_acquire_wait_avg_ms=0.8,
                        stream_acquire_wait_p95_ms=1.4,
                        request_round_trip_avg_ms=27.2,
                        request_round_trip_p95_ms=32.5,
                    ),
                ],
            )
            self._write_summary(
                ktls_dir / "bench_results.summary.json",
                [
                    self._row("h2_sustained_transfer", 1, 2000.0, 16.0, 12.0),
                    self._row("h2_sustained_transfer", 4, 2150.0, 16.5, 12.5),
                    self._row(
                        "h2_multiplexed_streams",
                        1,
                        5725.0,
                        37.5,
                        33.0,
                        transport=self._transport(
                            backpressure_events=70,
                            backpressure_alerts=2,
                            max_backpressure_depth_after=4,
                        ),
                    ),
                    self._row(
                        "h2_multiplexed_streams",
                        4,
                        2501.0,
                        220.0,
                        150.0,
                        transport=self._transport(
                            backpressure_events=97,
                            backpressure_alerts=4,
                            max_backpressure_depth_after=4,
                        ),
                        connections_opened=5,
                        samples_per_connection_avg=6.4,
                        stream_acquire_wait_avg_ms=7.6,
                        stream_acquire_wait_p95_ms=12.1,
                        request_round_trip_avg_ms=142.0,
                        request_round_trip_p95_ms=220.0,
                    ),
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
            self._write_tls_stat(
                baseline_dir / "tls-stat-before.txt",
                TlsTxSw=10,
                TlsRxSw=10,
                TlsTxDevice=0,
                TlsRxDevice=0,
                TlsDecryptRetry=4,
            )
            self._write_tls_stat(
                baseline_dir / "tls-stat-after.txt",
                TlsTxSw=10,
                TlsRxSw=10,
                TlsTxDevice=0,
                TlsRxDevice=0,
                TlsDecryptRetry=4,
            )
            self._write_tls_stat(
                ktls_dir / "tls-stat-before.txt",
                TlsTxSw=10,
                TlsRxSw=10,
                TlsTxDevice=0,
                TlsRxDevice=0,
                TlsDecryptRetry=4,
            )
            self._write_tls_stat(
                ktls_dir / "tls-stat-after.txt",
                TlsTxSw=14,
                TlsRxSw=14,
                TlsTxDevice=0,
                TlsRxDevice=0,
                TlsDecryptRetry=6,
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
            self.assertEqual(
                comparison["summary"]["linux_tls_stat"]["metrics"]["TlsTxSw"][
                    "ktls_delta"
                ],
                4,
            )
            self.assertEqual(
                comparison["summary"]["transport_focus"]["worst_throughput_row"][
                    "signals"
                ][0]["metric"],
                "backpressure_events",
            )
            self.assertEqual(
                comparison["summary"]["connection_focus"]["worst_throughput_row"][
                    "metrics"
                ]["connections_opened"]["delta"],
                1,
            )
            self.assertAlmostEqual(
                comparison["summary"]["phase_timing_focus"]["worst_throughput_row"][
                    "metrics"
                ]["stream_acquire_wait_avg_ms"]["delta"],
                6.8,
            )

            markdown = compare.render_markdown(comparison)
            self.assertIn("## Group Rollups", markdown)
            self.assertIn("## HTTP Connection Usage", markdown)
            self.assertIn("## HTTP Phase Timing", markdown)
            self.assertIn("## Linux TLS Stats", markdown)
            self.assertIn("## Transport Counter Deltas", markdown)
            self.assertIn("Workload-family investigation focus", markdown)
            self.assertIn("Runtime-thread investigation focus", markdown)
            self.assertIn("Worst throughput row transport view", markdown)
            self.assertIn("Worst throughput row connection view", markdown)
            self.assertIn("Worst throughput row phase view", markdown)
            self.assertIn(
                "Linux TLS session opens: baseline software TX/RX 0/0, device TX/RX 0/0; kTLS software TX/RX 4/4, device TX/RX 0/0.",
                markdown,
            )
            self.assertIn(
                "Linux TLS anomalies: Decrypt retries baseline 0, kTLS 2.",
                markdown,
            )
            self.assertIn("### By workload family", markdown)
            self.assertIn("### By native runtime threads", markdown)
            self.assertIn("h2_multiplexed_streams", markdown)
            self.assertIn("threads=4", markdown)
            self.assertIn("Elapsed wall time: baseline 12.50s, kTLS 14.00s", markdown)
            self.assertIn("82 -> 97 (+15)", markdown)
            self.assertIn("connections opened 4 -> 5 (+1)", markdown)
            self.assertIn("stream acquire wait avg 0.80 -> 7.60 (+6.80)", markdown)

    def test_transport_focus_reports_signal_gap_for_hotspot_row(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline_dir = root / "baseline"
            ktls_dir = root / "ktls"
            baseline_dir.mkdir()
            ktls_dir.mkdir()

            self._write_summary(
                baseline_dir / "bench_results.summary.json",
                [
                    self._row("h2_sustained_transfer", 1, 4200.0, 10.5, 8.5),
                    self._row(
                        "h2_multiplexed_streams",
                        1,
                        6100.0,
                        38.0,
                        31.0,
                        transport=self._transport(
                            backpressure_events=76,
                            backpressure_alerts=2,
                            max_backpressure_depth_after=4,
                        ),
                    ),
                ],
            )
            self._write_summary(
                ktls_dir / "bench_results.summary.json",
                [
                    self._row("h2_sustained_transfer", 1, 2995.0, 17.0, 12.0),
                    self._row(
                        "h2_multiplexed_streams",
                        1,
                        5600.0,
                        44.0,
                        33.0,
                        transport=self._transport(
                            backpressure_events=70,
                            backpressure_alerts=2,
                            max_backpressure_depth_after=4,
                        ),
                    ),
                ],
            )

            comparison = compare.build_comparison(
                baseline_dir / "bench_results.summary.json",
                ktls_dir / "bench_results.summary.json",
            )

            focus = comparison["summary"]["transport_focus"]["worst_throughput_row"]
            self.assertEqual(
                focus["label"], "h2_sustained_transfer (workers=1, threads=1)"
            )
            self.assertEqual(focus["signals"], [])

            markdown = compare.render_markdown(comparison)
            self.assertIn(
                "shows no non-zero transport counters in either pass", markdown
            )
            self.assertIn(
                "connections opened 2 -> 2 (+0)", markdown
            )
            self.assertIn(
                "no `/proc/net/tls_stat` sidecars were present", markdown
            )

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
    def _write_tls_stat(path: Path, **metrics: int) -> None:
        path.write_text(
            "\n".join(f"{name} {value}" for name, value in metrics.items()) + "\n"
        )

    @staticmethod
    def _row(
        workload: str,
        native_runtime_threads: int,
        throughput_mbps: float,
        latency_p95_ms: float,
        latency_avg_ms: float,
        *,
        transport: dict | None = None,
        connections_opened: int = 2,
        streams_per_connection: int = 1,
        reuse_connections: bool = True,
        samples_per_connection_avg: float = 8.0,
        stream_acquire_wait_avg_ms: float | None = 0.4,
        stream_acquire_wait_p95_ms: float | None = 0.8,
        request_round_trip_avg_ms: float | None = 7.6,
        request_round_trip_p95_ms: float | None = 10.8,
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
            "transport": transport or KtlsHttp2CompareTest._transport(),
            "http_connection_usage": {
                "reuse_connections": reuse_connections,
                "streams_per_connection": streams_per_connection,
                "connections_opened": connections_opened,
                "samples_per_connection_avg": samples_per_connection_avg,
            },
            "http_phase_timing": (
                None
                if stream_acquire_wait_avg_ms is None
                else {
                    "stream_acquire_wait_avg_ms": stream_acquire_wait_avg_ms,
                    "stream_acquire_wait_p95_ms": stream_acquire_wait_p95_ms,
                    "request_round_trip_avg_ms": request_round_trip_avg_ms,
                    "request_round_trip_p95_ms": request_round_trip_p95_ms,
                }
            ),
        }

    @staticmethod
    def _transport(
        *,
        backpressure_events: int = 0,
        backpressure_alerts: int = 0,
        transport_alerts: int = 0,
        goaway_events: int = 0,
        idle_timeout_events: int = 0,
        body_timeout_events: int = 0,
        protocol_error_events: int = 0,
        internal_error_events: int = 0,
        max_backpressure_depth_after: int = 0,
        active_throttles_after: int = 0,
    ) -> dict:
        return {
            "http_events": 0,
            "goaway_events": goaway_events,
            "idle_timeout_events": idle_timeout_events,
            "body_timeout_events": body_timeout_events,
            "protocol_error_events": protocol_error_events,
            "internal_error_events": internal_error_events,
            "backpressure_events": backpressure_events,
            "backpressure_alerts": backpressure_alerts,
            "transport_alerts": transport_alerts,
            "goaway_alerts": 0,
            "idle_timeout_alerts": 0,
            "body_timeout_alerts": 0,
            "protocol_error_alerts": 0,
            "internal_error_alerts": 0,
            "max_backpressure_depth_after": max_backpressure_depth_after,
            "active_throttles_after": active_throttles_after,
        }


if __name__ == "__main__":
    unittest.main()
