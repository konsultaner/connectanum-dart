import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

import ktls_http2_compare as compare
import ktls_http2_compare_repeats as repeat_compare


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
                        request_enqueue_avg_ms=0.6,
                        request_enqueue_p95_ms=1.1,
                        response_headers_wait_avg_ms=2.4,
                        response_headers_wait_p95_ms=4.0,
                        response_body_read_avg_ms=24.2,
                        response_body_read_p95_ms=27.4,
                        response_body_first_chunk_wait_avg_ms=4.4,
                        response_body_first_chunk_wait_p95_ms=6.0,
                        response_body_tail_read_avg_ms=19.8,
                        response_body_tail_read_p95_ms=22.0,
                        response_body_chunk_count_avg=3.0,
                        response_body_chunk_count_p95=4.0,
                        response_body_first_chunk_bytes_avg=8192.0,
                        response_body_first_chunk_bytes_p95=8192.0,
                        request_round_trip_avg_ms=27.2,
                        request_round_trip_p95_ms=32.5,
                        server_requests_total=32,
                        server_synthetic_responses_total=32,
                        server_request_body_drain_avg_ms=1.2,
                        server_stream_open_avg_ms=2.4,
                        server_first_chunk_queued_avg_ms=2.8,
                        server_first_body_write_avg_ms=3.1,
                        server_first_body_write_completed_avg_ms=3.4,
                        server_headers_to_first_body_write_avg_ms=0.7,
                        server_headers_to_first_body_write_completed_avg_ms=1.0,
                        server_queue_to_first_body_write_avg_ms=0.3,
                        server_queue_to_first_body_write_completed_avg_ms=0.6,
                        server_first_body_write_call_avg_ms=0.3,
                        server_direct_stream_open_round_trip_avg_ms=1.5,
                        server_direct_stream_request_queue_delay_avg_ms=0.2,
                        server_direct_stream_descriptor_open_call_avg_ms=0.4,
                        server_direct_stream_reply_delivery_delay_avg_ms=0.3,
                        server_handler_avg_ms=4.0,
                        native_streaming_responses_total=32,
                        native_stream_open_to_headers_send_avg_ms=1.2,
                        native_headers_send_call_avg_ms=0.1,
                        native_headers_to_first_connection_write_avg_ms=1.8,
                        native_first_chunk_channel_wait_avg_ms=0.6,
                        native_headers_to_first_chunk_dequeue_avg_ms=1.4,
                        native_first_chunk_send_call_avg_ms=0.2,
                        native_headers_to_first_chunk_send_call_avg_ms=1.6,
                        native_headers_to_first_connection_write_ge_1ms_total=3,
                        native_headers_to_first_connection_write_ge_5ms_total=0,
                        native_headers_to_first_connection_write_ge_10ms_total=0,
                        native_first_chunk_channel_wait_ge_1ms_total=2,
                        native_first_chunk_channel_wait_ge_5ms_total=0,
                        native_first_chunk_channel_wait_ge_10ms_total=0,
                        native_headers_to_first_chunk_dequeue_ge_1ms_total=4,
                        native_headers_to_first_chunk_dequeue_ge_5ms_total=1,
                        native_headers_to_first_chunk_dequeue_ge_10ms_total=0,
                        native_first_chunk_send_call_ge_1ms_total=0,
                        native_first_chunk_send_call_ge_5ms_total=0,
                        native_first_chunk_send_call_ge_10ms_total=0,
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
                        request_enqueue_avg_ms=1.9,
                        request_enqueue_p95_ms=3.3,
                        response_headers_wait_avg_ms=18.5,
                        response_headers_wait_p95_ms=29.0,
                        response_body_read_avg_ms=121.6,
                        response_body_read_p95_ms=188.0,
                        response_body_first_chunk_wait_avg_ms=6.1,
                        response_body_first_chunk_wait_p95_ms=9.4,
                        response_body_tail_read_avg_ms=115.5,
                        response_body_tail_read_p95_ms=178.6,
                        response_body_chunk_count_avg=12.0,
                        response_body_chunk_count_p95=18.0,
                        response_body_first_chunk_bytes_avg=1536.0,
                        response_body_first_chunk_bytes_p95=2048.0,
                        request_round_trip_avg_ms=142.0,
                        request_round_trip_p95_ms=220.0,
                        server_requests_total=32,
                        server_synthetic_responses_total=32,
                        server_request_body_drain_avg_ms=1.4,
                        server_stream_open_avg_ms=4.1,
                        server_first_chunk_queued_avg_ms=7.0,
                        server_first_body_write_avg_ms=10.0,
                        server_first_body_write_completed_avg_ms=10.8,
                        server_headers_to_first_body_write_avg_ms=5.9,
                        server_headers_to_first_body_write_completed_avg_ms=6.7,
                        server_queue_to_first_body_write_avg_ms=3.0,
                        server_queue_to_first_body_write_completed_avg_ms=3.8,
                        server_first_body_write_call_avg_ms=0.8,
                        server_direct_stream_open_round_trip_avg_ms=5.0,
                        server_direct_stream_request_queue_delay_avg_ms=1.6,
                        server_direct_stream_descriptor_open_call_avg_ms=1.1,
                        server_direct_stream_reply_delivery_delay_avg_ms=0.9,
                        server_handler_avg_ms=12.0,
                        native_streaming_responses_total=32,
                        native_stream_open_to_headers_send_avg_ms=8.2,
                        native_headers_send_call_avg_ms=0.4,
                        native_headers_to_first_connection_write_avg_ms=9.0,
                        native_first_chunk_channel_wait_avg_ms=5.4,
                        native_headers_to_first_chunk_dequeue_avg_ms=11.9,
                        native_first_chunk_send_call_avg_ms=0.9,
                        native_headers_to_first_chunk_send_call_avg_ms=12.8,
                        native_headers_to_first_connection_write_ge_1ms_total=23,
                        native_headers_to_first_connection_write_ge_5ms_total=15,
                        native_headers_to_first_connection_write_ge_10ms_total=8,
                        native_first_chunk_channel_wait_ge_1ms_total=14,
                        native_first_chunk_channel_wait_ge_5ms_total=7,
                        native_first_chunk_channel_wait_ge_10ms_total=2,
                        native_headers_to_first_chunk_dequeue_ge_1ms_total=24,
                        native_headers_to_first_chunk_dequeue_ge_5ms_total=16,
                        native_headers_to_first_chunk_dequeue_ge_10ms_total=9,
                        native_first_chunk_send_call_ge_1ms_total=1,
                        native_first_chunk_send_call_ge_5ms_total=0,
                        native_first_chunk_send_call_ge_10ms_total=0,
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
            self.assertAlmostEqual(
                comparison["summary"]["phase_timing_focus"]["worst_throughput_row"][
                    "metrics"
                ]["response_body_read_avg_ms"]["delta"],
                97.4,
            )
            self.assertAlmostEqual(
                comparison["summary"]["phase_timing_focus"]["worst_throughput_row"][
                    "metrics"
                ]["response_body_first_chunk_wait_avg_ms"]["delta"],
                1.7,
            )
            self.assertAlmostEqual(
                comparison["summary"]["phase_timing_focus"]["worst_throughput_row"][
                    "metrics"
                ]["response_body_tail_read_avg_ms"]["delta"],
                95.7,
            )
            self.assertAlmostEqual(
                comparison["summary"]["phase_timing_focus"]["worst_throughput_row"][
                    "metrics"
                ]["response_body_chunk_count_avg"]["delta"],
                9.0,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["headers_to_first_body_write_avg_ms"]["delta"],
                5.2,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["headers_to_first_body_write_completed_avg_ms"]["delta"],
                5.7,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["queue_to_first_body_write_avg_ms"]["delta"],
                2.7,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["first_body_write_call_avg_ms"]["delta"],
                0.5,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["direct_stream_open_round_trip_avg_ms"]["delta"],
                3.5,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["direct_stream_request_queue_delay_avg_ms"]["delta"],
                1.4,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["direct_stream_descriptor_open_call_avg_ms"]["delta"],
                0.7,
            )
            self.assertAlmostEqual(
                comparison["summary"]["server_emission_focus"]["worst_throughput_row"][
                    "metrics"
                ]["direct_stream_reply_delivery_delay_avg_ms"]["delta"],
                0.6,
            )
            self.assertAlmostEqual(
                comparison["summary"]["native_response_stream_focus"][
                    "worst_throughput_row"
                ]["metrics"]["stream_open_to_headers_send_avg_ms"]["delta"],
                7.0,
            )
            self.assertAlmostEqual(
                comparison["summary"]["native_response_stream_focus"][
                    "worst_throughput_row"
                ]["metrics"]["headers_send_call_avg_ms"]["delta"],
                0.3,
            )
            self.assertAlmostEqual(
                comparison["summary"]["native_response_stream_focus"][
                    "worst_throughput_row"
                ]["metrics"]["headers_to_first_connection_write_avg_ms"]["delta"],
                7.2,
            )
            self.assertAlmostEqual(
                comparison["summary"]["native_response_stream_focus"][
                    "worst_throughput_row"
                ]["metrics"]["first_chunk_channel_wait_avg_ms"]["delta"],
                4.8,
            )
            self.assertAlmostEqual(
                comparison["summary"]["native_response_stream_focus"][
                    "worst_throughput_row"
                ]["metrics"]["headers_to_first_chunk_dequeue_avg_ms"]["delta"],
                10.5,
            )
            self.assertEqual(
                comparison["summary"]["native_response_stream_slow_path_focus"][
                    "worst_throughput_row"
                ]["buckets"]["headers_to_first_connection_write"]["ge_5ms_total"][
                    "delta"
                ],
                15,
            )
            self.assertEqual(
                comparison["summary"]["native_response_stream_slow_path_focus"][
                    "worst_throughput_row"
                ]["buckets"]["headers_to_first_chunk_dequeue"]["ge_5ms_total"][
                    "delta"
                ],
                15,
            )

            markdown = compare.render_markdown(comparison)
            self.assertIn("## Group Rollups", markdown)
            self.assertIn("## HTTP Connection Usage", markdown)
            self.assertIn("## HTTP Phase Timing", markdown)
            self.assertIn("## HTTP Response-Body Diagnostics", markdown)
            self.assertIn("## HTTP Server Emission Timing", markdown)
            self.assertIn("Direct stream open round trip avg ms", markdown)
            self.assertIn("Request queue delay avg ms", markdown)
            self.assertIn("Reply delivery delay avg ms", markdown)
            self.assertIn("## HTTP Native Response-Stream Timing", markdown)
            self.assertIn("## HTTP Native Response-Stream Slow Paths", markdown)
            self.assertIn("## Linux TLS Stats", markdown)
            self.assertIn("## Transport Counter Deltas", markdown)
            self.assertIn("Workload-family investigation focus", markdown)
            self.assertIn("Runtime-thread investigation focus", markdown)
            self.assertIn("Worst throughput row transport view", markdown)
            self.assertIn("Worst throughput row connection view", markdown)
            self.assertIn("Worst throughput row phase view", markdown)
            self.assertIn("Worst throughput row server-emission view", markdown)
            self.assertIn("Worst throughput row native-stream view", markdown)
            self.assertIn("native stream-open-to-headers-send avg", markdown)
            self.assertIn("Headers to first connection write avg ms", markdown)
            self.assertIn("Worst throughput row native-stream slow-path view", markdown)
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
            self.assertIn(
                "server headers-to-first-body-write avg 0.70 -> 5.90 (+5.20)",
                markdown,
            )
            self.assertIn(
                "native headers-to-first-connection-write >=1/5/10ms 3/0/0 -> 23/15/8",
                markdown,
            )
            self.assertIn(
                "native headers-to-first-connection-write avg 1.80 -> 9.00 (+7.20)",
                markdown,
            )
            self.assertIn(
                "native headers-to-first-chunk-dequeue >=1/5/10ms 4/1/0 -> 24/16/9",
                markdown,
            )
            self.assertIn(
                "server headers-to-first-body-write-completed avg 1.00 -> 6.70 (+5.70)",
                markdown,
            )
            self.assertIn(
                "server first body write call avg 0.30 -> 0.80 (+0.50)",
                markdown,
            )
            self.assertIn(
                "native first chunk channel wait avg 0.60 -> 5.40 (+4.80)",
                markdown,
            )
            self.assertIn(
                "native headers-to-first-chunk-dequeue avg 1.40 -> 11.90 (+10.50)",
                markdown,
            )
            self.assertIn(
                "response body first chunk wait avg 4.40 -> 6.10 (+1.70)", markdown
            )
            self.assertIn(
                "response body tail read avg 19.80 -> 115.50 (+95.70)", markdown
            )
            self.assertIn("response body chunks avg 3.00 -> 12.00 (+9.00)", markdown)
            self.assertIn("response body read avg 24.20 -> 121.60 (+97.40)", markdown)

    def test_repeat_stability_flags_inconsistent_hosted_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)

            repeat_one = root / "repeats" / "repeat-01"
            repeat_two = root / "repeats" / "repeat-02"
            repeat_one_baseline = repeat_one / "baseline"
            repeat_one_ktls = repeat_one / "ktls"
            repeat_two_baseline = repeat_two / "baseline"
            repeat_two_ktls = repeat_two / "ktls"
            repeat_one_baseline.mkdir(parents=True)
            repeat_one_ktls.mkdir(parents=True)
            repeat_two_baseline.mkdir(parents=True)
            repeat_two_ktls.mkdir(parents=True)

            self._write_summary(
                repeat_one_baseline / "bench_results.summary.json",
                [
                    self._row("h2_multiplexed_streams_s1", 4, 5200.0, 18.0, 12.0),
                    self._row("h2_multiplexed_streams_s2", 4, 5200.0, 18.0, 12.0),
                    self._row("h2_multiplexed_streams_s4", 4, 900.0, 240.0, 120.0),
                ],
            )
            self._write_summary(
                repeat_one_ktls / "bench_results.summary.json",
                [
                    self._row("h2_multiplexed_streams_s1", 4, 1900.0, 32.0, 20.0),
                    self._row("h2_multiplexed_streams_s2", 4, 4200.0, 24.0, 16.0),
                    self._row("h2_multiplexed_streams_s4", 4, 4600.0, 30.0, 18.0),
                ],
            )
            self._write_summary(
                repeat_two_baseline / "bench_results.summary.json",
                [
                    self._row("h2_multiplexed_streams_s1", 4, 5200.0, 18.0, 12.0),
                    self._row("h2_multiplexed_streams_s2", 4, 5200.0, 16.0, 11.0),
                    self._row("h2_multiplexed_streams_s4", 4, 5600.0, 28.0, 19.0),
                ],
            )
            self._write_summary(
                repeat_two_ktls / "bench_results.summary.json",
                [
                    self._row("h2_multiplexed_streams_s1", 4, 3200.0, 30.0, 18.0),
                    self._row("h2_multiplexed_streams_s2", 4, 880.0, 220.0, 140.0),
                    self._row("h2_multiplexed_streams_s4", 4, 2100.0, 42.0, 24.0),
                ],
            )

            repeat_one_comparison = compare.build_comparison(
                repeat_one_baseline / "bench_results.summary.json",
                repeat_one_ktls / "bench_results.summary.json",
            )
            repeat_two_comparison = compare.build_comparison(
                repeat_two_baseline / "bench_results.summary.json",
                repeat_two_ktls / "bench_results.summary.json",
            )

            repeat_one_path = repeat_one / "comparison.json"
            repeat_two_path = repeat_two / "comparison.json"
            repeat_one_path.write_text(json.dumps(repeat_one_comparison))
            repeat_two_path.write_text(json.dumps(repeat_two_comparison))

            stability = repeat_compare.build_repeat_stability(
                [repeat_one_path, repeat_two_path]
            )

            self.assertFalse(stability["decision_quality"])
            self.assertEqual(stability["repeat_count"], 2)
            self.assertFalse(stability["worst_throughput_consensus"]["consistent"])
            self.assertFalse(stability["worst_latency_consensus"]["consistent"])
            self.assertEqual(
                stability["max_throughput_span_row"]["label"],
                "h2_multiplexed_streams_s4 (workers=1, threads=4)",
            )
            self.assertEqual(
                stability["max_latency_p95_span_row"]["label"],
                "h2_multiplexed_streams_s2 (workers=1, threads=4)",
            )
            self.assertEqual(
                stability["max_throughput_span_row"]["throughput_span_source"],
                "mixed",
            )
            self.assertEqual(
                stability["max_latency_p95_span_row"]["latency_p95_span_source"],
                "kTLS",
            )
            self.assertGreater(
                stability["max_throughput_span_row"]["throughput_pct_delta"]["span"],
                300.0,
            )
            self.assertGreater(
                stability["max_latency_p95_span_row"]["latency_p95_pct_delta"]["span"],
                1000.0,
            )

            markdown = repeat_compare.render_markdown(stability)
            self.assertIn("## Repeat Overview", markdown)
            self.assertIn("## Rows Exceeding Stability Thresholds", markdown)
            self.assertIn("## Per-row Stability", markdown)
            self.assertIn("## Summary", markdown)
            self.assertIn("Instability source highlights", markdown)
            self.assertIn("Decision quality: no", markdown)
            self.assertIn(
                "Worst throughput row consistency: changed across repeats",
                markdown,
            )
            self.assertIn("Worst p95 row consistency: changed across repeats", markdown)
            self.assertIn("mixed throughput span", markdown)
            self.assertIn("kTLS-side p95 span", markdown)
            self.assertIn("repeat-01", markdown)
            self.assertIn("repeat-02", markdown)
            self.assertIn("h2_multiplexed_streams_s4", markdown)
            self.assertIn("h2_multiplexed_streams_s2", markdown)

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
        request_enqueue_avg_ms: float | None = 0.3,
        request_enqueue_p95_ms: float | None = 0.5,
        response_headers_wait_avg_ms: float | None = 1.6,
        response_headers_wait_p95_ms: float | None = 2.2,
        response_body_read_avg_ms: float | None = 5.7,
        response_body_read_p95_ms: float | None = 8.1,
        response_body_first_chunk_wait_avg_ms: float | None = 2.1,
        response_body_first_chunk_wait_p95_ms: float | None = 3.0,
        response_body_tail_read_avg_ms: float | None = 3.6,
        response_body_tail_read_p95_ms: float | None = 5.1,
        response_body_chunk_count_avg: float | None = 1.0,
        response_body_chunk_count_p95: float | None = 1.0,
        response_body_first_chunk_bytes_avg: float | None = 16384.0,
        response_body_first_chunk_bytes_p95: float | None = 16384.0,
        request_round_trip_avg_ms: float | None = 7.6,
        request_round_trip_p95_ms: float | None = 10.8,
        server_requests_total: int | None = 16,
        server_synthetic_responses_total: int | None = 16,
        server_request_body_drain_avg_ms: float | None = 1.2,
        server_stream_open_avg_ms: float | None = 2.4,
        server_first_chunk_queued_avg_ms: float | None = 2.8,
        server_first_body_write_avg_ms: float | None = 3.2,
        server_first_body_write_completed_avg_ms: float | None = 3.5,
        server_headers_to_first_body_write_avg_ms: float | None = 0.8,
        server_headers_to_first_body_write_completed_avg_ms: float | None = 1.1,
        server_queue_to_first_body_write_avg_ms: float | None = 0.4,
        server_queue_to_first_body_write_completed_avg_ms: float | None = 0.7,
        server_first_body_write_call_avg_ms: float | None = 0.3,
        server_direct_stream_open_round_trip_avg_ms: float | None = 1.5,
        server_direct_stream_request_queue_delay_avg_ms: float | None = 0.2,
        server_direct_stream_descriptor_open_call_avg_ms: float | None = 0.4,
        server_direct_stream_reply_delivery_delay_avg_ms: float | None = 0.3,
        server_handler_avg_ms: float | None = 4.0,
        native_streaming_responses_total: int | None = 16,
        native_stream_open_to_headers_send_avg_ms: float | None = 1.0,
        native_headers_send_call_avg_ms: float | None = 0.1,
        native_headers_to_first_connection_write_avg_ms: float | None = 1.3,
        native_first_chunk_channel_wait_avg_ms: float | None = 0.5,
        native_headers_to_first_chunk_dequeue_avg_ms: float | None = 1.2,
        native_first_chunk_send_call_avg_ms: float | None = 0.2,
        native_headers_to_first_chunk_send_call_avg_ms: float | None = 1.4,
        native_headers_to_first_connection_write_ge_1ms_total: int | None = 1,
        native_headers_to_first_connection_write_ge_5ms_total: int | None = 0,
        native_headers_to_first_connection_write_ge_10ms_total: int | None = 0,
        native_first_chunk_channel_wait_ge_1ms_total: int | None = 1,
        native_first_chunk_channel_wait_ge_5ms_total: int | None = 0,
        native_first_chunk_channel_wait_ge_10ms_total: int | None = 0,
        native_headers_to_first_chunk_dequeue_ge_1ms_total: int | None = 2,
        native_headers_to_first_chunk_dequeue_ge_5ms_total: int | None = 0,
        native_headers_to_first_chunk_dequeue_ge_10ms_total: int | None = 0,
        native_first_chunk_send_call_ge_1ms_total: int | None = 0,
        native_first_chunk_send_call_ge_5ms_total: int | None = 0,
        native_first_chunk_send_call_ge_10ms_total: int | None = 0,
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
                    "request_enqueue_avg_ms": request_enqueue_avg_ms,
                    "request_enqueue_p95_ms": request_enqueue_p95_ms,
                    "response_headers_wait_avg_ms": response_headers_wait_avg_ms,
                    "response_headers_wait_p95_ms": response_headers_wait_p95_ms,
                    "response_body_read_avg_ms": response_body_read_avg_ms,
                    "response_body_read_p95_ms": response_body_read_p95_ms,
                    "response_body_first_chunk_wait_avg_ms": response_body_first_chunk_wait_avg_ms,
                    "response_body_first_chunk_wait_p95_ms": response_body_first_chunk_wait_p95_ms,
                    "response_body_tail_read_avg_ms": response_body_tail_read_avg_ms,
                    "response_body_tail_read_p95_ms": response_body_tail_read_p95_ms,
                    "response_body_chunk_count_avg": response_body_chunk_count_avg,
                    "response_body_chunk_count_p95": response_body_chunk_count_p95,
                    "response_body_first_chunk_bytes_avg": response_body_first_chunk_bytes_avg,
                    "response_body_first_chunk_bytes_p95": response_body_first_chunk_bytes_p95,
                    "request_round_trip_avg_ms": request_round_trip_avg_ms,
                    "request_round_trip_p95_ms": request_round_trip_p95_ms,
                }
            ),
            "http_server_emission_timing": (
                None
                if server_requests_total is None
                else {
                    "requests_total": server_requests_total,
                    "synthetic_responses_total": server_synthetic_responses_total,
                    "native_forwarded_responses_total": 0,
                    "buffered_responses_total": 0,
                    "request_body_drain_avg_ms": server_request_body_drain_avg_ms,
                    "stream_open_avg_ms": server_stream_open_avg_ms,
                    "first_chunk_queued_avg_ms": server_first_chunk_queued_avg_ms,
                    "first_body_write_avg_ms": server_first_body_write_avg_ms,
                    "first_body_write_completed_avg_ms": server_first_body_write_completed_avg_ms,
                    "headers_to_first_body_write_avg_ms": server_headers_to_first_body_write_avg_ms,
                    "headers_to_first_body_write_completed_avg_ms": server_headers_to_first_body_write_completed_avg_ms,
                    "queue_to_first_body_write_avg_ms": server_queue_to_first_body_write_avg_ms,
                    "queue_to_first_body_write_completed_avg_ms": server_queue_to_first_body_write_completed_avg_ms,
                    "first_body_write_call_avg_ms": server_first_body_write_call_avg_ms,
                    "direct_stream_open_round_trip_avg_ms": server_direct_stream_open_round_trip_avg_ms,
                    "direct_stream_request_queue_delay_avg_ms": server_direct_stream_request_queue_delay_avg_ms,
                    "direct_stream_descriptor_open_call_avg_ms": server_direct_stream_descriptor_open_call_avg_ms,
                    "direct_stream_reply_delivery_delay_avg_ms": server_direct_stream_reply_delivery_delay_avg_ms,
                    "handler_avg_ms": server_handler_avg_ms,
                }
            ),
            "http_native_response_stream_timing": (
                None
                if native_streaming_responses_total is None
                else {
                    "streaming_responses_total": native_streaming_responses_total,
                    "stream_open_to_headers_send_avg_ms": native_stream_open_to_headers_send_avg_ms,
                    "headers_send_call_avg_ms": native_headers_send_call_avg_ms,
                    "headers_to_first_connection_write_avg_ms": native_headers_to_first_connection_write_avg_ms,
                    "first_chunk_channel_wait_avg_ms": native_first_chunk_channel_wait_avg_ms,
                    "headers_to_first_chunk_dequeue_avg_ms": native_headers_to_first_chunk_dequeue_avg_ms,
                    "first_chunk_send_call_avg_ms": native_first_chunk_send_call_avg_ms,
                    "headers_to_first_chunk_send_call_avg_ms": native_headers_to_first_chunk_send_call_avg_ms,
                }
            ),
            "http_native_response_stream_slow_path": (
                None
                if native_streaming_responses_total is None
                else {
                    "streaming_responses_total": native_streaming_responses_total,
                    "headers_to_first_connection_write_ge_1ms_total": native_headers_to_first_connection_write_ge_1ms_total,
                    "headers_to_first_connection_write_ge_5ms_total": native_headers_to_first_connection_write_ge_5ms_total,
                    "headers_to_first_connection_write_ge_10ms_total": native_headers_to_first_connection_write_ge_10ms_total,
                    "first_chunk_channel_wait_ge_1ms_total": native_first_chunk_channel_wait_ge_1ms_total,
                    "first_chunk_channel_wait_ge_5ms_total": native_first_chunk_channel_wait_ge_5ms_total,
                    "first_chunk_channel_wait_ge_10ms_total": native_first_chunk_channel_wait_ge_10ms_total,
                    "headers_to_first_chunk_dequeue_ge_1ms_total": native_headers_to_first_chunk_dequeue_ge_1ms_total,
                    "headers_to_first_chunk_dequeue_ge_5ms_total": native_headers_to_first_chunk_dequeue_ge_5ms_total,
                    "headers_to_first_chunk_dequeue_ge_10ms_total": native_headers_to_first_chunk_dequeue_ge_10ms_total,
                    "first_chunk_send_call_ge_1ms_total": native_first_chunk_send_call_ge_1ms_total,
                    "first_chunk_send_call_ge_5ms_total": native_first_chunk_send_call_ge_5ms_total,
                    "first_chunk_send_call_ge_10ms_total": native_first_chunk_send_call_ge_10ms_total,
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
