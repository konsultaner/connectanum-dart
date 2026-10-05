import copy
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import wamp_serializer_compare as compare


class WampSerializerCompareTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        policy_path = (
            Path(__file__).parents[1]
            / "native/bench/artifact_gate/wamp_flatbuffers_performance.json"
        )
        self.policy = json.loads(policy_path.read_text(encoding="utf-8"))
        self.policy["minimum_samples_per_run"] = 25
        self.policy["bootstrap_resamples"] = 200
        self.manifest = self._campaign()

    def _report(self, workload: str, codec: str, repetition: int) -> dict:
        speed = {"flatbuffers": 1200, "cbor": 1000, "msgpack": 1100}[codec]
        latency = {"flatbuffers": 0.9, "cbor": 1.0, "msgpack": 0.95}[codec]
        cpu = {"flatbuffers": 80, "cbor": 100, "msgpack": 90}[codec]
        allocated = {"flatbuffers": 80, "cbor": 100, "msgpack": 90}[codec]
        pause = {"flatbuffers": 8, "cbor": 10, "msgpack": 9}[codec]
        peak = {"flatbuffers": 90, "cbor": 100, "msgpack": 95}[codec]
        return {
            "workload": workload,
            "protocol": "wamp_rawsocket_rpc",
            "client_impl": "dart",
            "concurrency": 1,
            "iterations": 25,
            "request_chunk_bytes": 65536,
            "response_chunk_bytes": 65536,
            "data_window_elapsed_ms": 10000,
            "samples": [
                {
                    "worker": 0,
                    "iteration": index,
                    "latency_ms": latency + repetition / 1000,
                    "request_bytes": speed,
                    "response_bytes": speed,
                }
                for index in range(25)
            ],
            "client_process_metrics": {
                "cpu_user_us_delta": cpu * 25,
                "cpu_system_us_delta": 25,
                "allocated_bytes_delta": allocated * 25,
                "gc_count_delta": 1,
                "gc_pause_us_delta": pause * 25,
                "current_rss_bytes": peak - 5,
                "peak_rss_during_bytes": peak,
            },
            "copy_metrics": {
                "optimized_payload_copy_bytes": 0 if codec == "flatbuffers" else 512,
                "builder_input_copy_bytes": 0,
                "builder_growth_copy_bytes": 0,
                "transport_copy_bytes": 512,
                "websocket_mask_copy_bytes": {
                    "status": "not_applicable",
                    "reason": "RawSocket row",
                },
                "tls_copy_bytes": {
                    "status": "not_applicable",
                    "reason": "cleartext row",
                },
                "transcode_copy_bytes": 0,
            },
        }

    def _campaign(self, *, flatbuffer_speed: int = 1200) -> dict:
        codecs = ("flatbuffers", "cbor", "msgpack")
        names = {codec: f"case_{codec}" for codec in codecs}
        orders = [
            ("cbor", "flatbuffers", "msgpack"),
            ("msgpack", "cbor", "flatbuffers"),
            ("flatbuffers", "msgpack", "cbor"),
            ("cbor", "msgpack", "flatbuffers"),
            ("msgpack", "flatbuffers", "cbor"),
            ("flatbuffers", "cbor", "msgpack"),
            ("cbor", "flatbuffers", "msgpack"),
        ]

        def write_run(
            stem: str,
            codec_order: tuple[str, ...],
            repetition: int,
            sequence: int,
        ) -> dict:
            reports = []
            for codec in codec_order:
                report = self._report(names[codec], codec, repetition)
                if codec == "flatbuffers":
                    for sample in report["samples"]:
                        sample["request_bytes"] = flatbuffer_speed
                        sample["response_bytes"] = flatbuffer_speed
                reports.append(report)
            path = self.root / f"{stem}.jsonl"
            path.write_text(
                "".join(json.dumps(report) + "\n" for report in reports),
                encoding="utf-8",
            )
            started = datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(
                seconds=sequence * 11
            )
            completed = started + timedelta(seconds=10)
            return {
                "results": path.name,
                "order": [r["workload"] for r in reports],
                "started_at_utc": started.isoformat().replace("+00:00", "Z"),
                "completed_at_utc": completed.isoformat().replace("+00:00", "Z"),
            }

        warmups = [
            write_run(f"warmup-{index}", order, index, index - 1)
            for index, order in enumerate(orders[:3], 1)
        ]
        measured = []
        for index, order in enumerate(orders, 1):
            run = write_run(f"measured-{index}", order, index, index + 2)
            run["index"] = index
            measured.append(run)
        return {
            "schema_version": 1,
            "campaign_id": "test-campaign",
            "order_seed": 20261005,
            "overlap_detected": False,
            "metadata": {
                "source_revision": "a" * 40,
                "working_tree_clean": True,
                "scenario_sha256": "b" * 64,
                "lockfiles_sha256": {"Cargo.lock": "c" * 64, "pubspec.lock": "d" * 64},
                "platform": {
                    "os": "Linux",
                    "kernel": "test-kernel",
                    "cpu_model": "test-cpu",
                    "logical_cpu_count": 8,
                    "runner_image": "test-runner",
                    "dart_version": "3.10.0",
                    "rustc_version": "1.90.0",
                },
                "load_average": [0.1, 0.2, 0.3],
            },
            "cases": [
                {
                    "id": "primary-rpc-rawsocket-values",
                    "construction": "native_buffer",
                    "workloads": names,
                    "zero_copy_codecs": ["flatbuffers"],
                }
            ],
            "warmup_runs": warmups,
            "measured_runs": measured,
        }

    def test_accepts_paired_parity_and_zero_copy_evidence(self) -> None:
        result = compare.evaluate_campaign(self.manifest, self.root, self.policy)

        self.assertEqual(result["status"], "passed")
        metrics = result["cases"][0]["metrics"]
        self.assertGreaterEqual(metrics["throughput_mbps"]["median_ratio"], 1.0)
        self.assertLessEqual(metrics["latency_p99_ms"]["median_ratio"], 1.0)
        self.assertEqual(len(metrics["throughput_mbps"]["observations"]), 7)

    def test_rejects_flatbuffers_throughput_regression(self) -> None:
        manifest = self._campaign(flatbuffer_speed=900)

        result = compare.evaluate_campaign(manifest, self.root, self.policy)

        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("throughput_mbps" in f for f in result["findings"]))

    def test_rejects_missing_codec_row(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        run = manifest["measured_runs"][0]
        rows = [
            self._report("case_cbor", "cbor", 1),
            self._report("case_msgpack", "msgpack", 1),
        ]
        path = self.root / run["results"]
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        run["order"] = [row["workload"] for row in rows]

        result = compare.evaluate_campaign(manifest, self.root, self.policy)

        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("missing flatbuffers" in f for f in result["findings"]))

    def test_rejects_short_measurement_window(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        run = manifest["measured_runs"][0]
        path = self.root / run["results"]
        reports = [json.loads(line) for line in path.read_text().splitlines()]
        reports[0]["data_window_elapsed_ms"] = 9999
        path.write_text("".join(json.dumps(row) + "\n" for row in reports))

        result = compare.evaluate_campaign(manifest, self.root, self.policy)

        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("below 10000 ms" in f for f in result["findings"]))

    def test_rejects_missing_runtime_metrics_and_copy_counters(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        run = manifest["measured_runs"][0]
        path = self.root / run["results"]
        reports = [json.loads(line) for line in path.read_text().splitlines()]
        reports[0]["client_process_metrics"].pop("allocated_bytes_delta")
        reports[1].pop("copy_metrics")
        path.write_text("".join(json.dumps(row) + "\n" for row in reports))

        result = compare.evaluate_campaign(manifest, self.root, self.policy)

        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("allocated_bytes_delta" in f for f in result["findings"]))
        self.assertTrue(any("missing copy_metrics" in f for f in result["findings"]))

    def test_bootstrap_is_deterministic(self) -> None:
        first = compare.evaluate_campaign(self.manifest, self.root, self.policy)
        second = compare.evaluate_campaign(self.manifest, self.root, self.policy)

        self.assertEqual(first, second)

    def test_rejects_copy_at_optimized_boundary(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        run = manifest["measured_runs"][0]
        path = self.root / run["results"]
        reports = [json.loads(line) for line in path.read_text().splitlines()]
        flatbuffers = next(row for row in reports if row["workload"] == "case_flatbuffers")
        flatbuffers["copy_metrics"]["optimized_payload_copy_bytes"] = 1
        path.write_text("".join(json.dumps(row) + "\n" for row in reports))

        result = compare.evaluate_campaign(manifest, self.root, self.policy)

        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("expected zero" in f for f in result["findings"]))


if __name__ == "__main__":
    unittest.main()
