import copy
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import wamp_serializer_compare as compare
from test_dart_heap_allocation_evidence import allocation_fixture


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
        report = {
            "workload": workload,
            "protocol": "wamp_rawsocket_rpc",
            "client_impl": "dart",
            "wamp_configuration": {"serializer": codec, "secure_transport": False},
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
                "pid": 1000,
                "rss_before_bytes": peak * 3 // 5,
                "current_rss_bytes": peak * 3 // 5,
                "max_rss_bytes": peak,
                "cpu_user_us_delta": cpu * 15,
                "cpu_system_us_delta": cpu * 5,
                "allocated_bytes_delta": allocated * 20 * 1000,
                "gc_count_delta": 1,
                "gc_pause_us_delta": pause * 20,
                "peak_rss_during_bytes": peak * 3 // 5,
            },
            "server_process_metrics": {
                "pid": 2000,
                "rss_before_bytes": peak * 2 // 5,
                "current_rss_bytes": peak * 2 // 5,
                "max_rss_bytes": peak,
                "cpu_user_us_delta": cpu * 4,
                "cpu_system_us_delta": cpu,
                "allocated_bytes_delta": allocated * 5 * 1000,
                "gc_count_delta": 1,
                "gc_pause_us_delta": pause * 5,
                "peak_rss_during_bytes": peak * 2 // 5,
            },
            "copy_metrics": {
                "measurement_scope": compare.COPY_MEASUREMENT_SCOPE,
                "encoded_wamp_volume": {
                    "status": "measured",
                    "measurement_scope": compare.ENCODED_WAMP_VOLUME_SCOPE,
                    "accepted_bytes": 4000,
                    "known_accepted_bytes": 4000,
                    "components": {"client_dart": 1000, "router_dart": 0,
                                   "client_native": 0, "router_native": 3000},
                    "unknown_boundaries": [], "rejected_submissions": 0,
                    "excludes": ["RawSocket/WebSocket framing", "TLS records", "network packet headers"],
                },
                "optimized_payload_copy_bytes": 0 if codec == "flatbuffers" else 512,
                "builder_input_copy_bytes": 0,
                "builder_growth_copy_bytes": 0,
                "transport_copy_bytes": 512,
                "known_own_copy_breakdown": {
                    "client": {
                        **{field: 0 for field in compare.DART_CLIENT_COPY_FIELDS},
                        **{field: 0 for field in compare.NATIVE_CLIENT_COPY_FIELDS},
                        "websocket_mask_copy_bytes": 0,
                        "websocket_coalesce_copy_bytes": 0,
                    },
                    "router": {
                        "dart_to_native_copy_bytes": 512,
                        "ffi_borrowed_send_input_copy_bytes": 0,
                        "io_buffer_front_copy_bytes": 0,
                        "io_buffered_read_copy_bytes": 0,
                        "websocket_coalesce_copy_bytes": 0,
                    },
                },
                "coverage": {
                    "transport_copy_bytes": "complete_connectanum_owned_path",
                    "unknown_boundaries": [],
                    "unmeasured_dependency_boundaries": ["dart_sdk_socket_io"],
                },
                "websocket_mask_copy_bytes": {
                    "status": "not_applicable",
                    "reason": "RawSocket row",
                },
                "tls_copy_bytes": {
                    "status": "not_applicable",
                    "reason": "cleartext row",
                },
                "transcode_copy_bytes": 0,
                "e2ee_copy_bytes": {
                    "status": "not_applicable",
                    "reason": "cleartext payload",
                },
            },
        }

        for key in ("client_process_metrics", "server_process_metrics"):
            report[key]["allocation_measurement"] = allocation_fixture(report[key])
        return report

    def test_standard_sdk_tls_internals_are_labelled_without_hiding_owned_copies(self):
        report = self._report("tls", "flatbuffers", 1)
        metrics = report["copy_metrics"]
        report["wamp_configuration"] = {"secure_transport": True}
        metrics["tls_copy_bytes"] = {
            "status": "not_measured", "scope": "dependency_internals",
            "dependency": "dart_sdk_tls_and_rustls_tokio_rustls",
            "reason": "Standard SDK TLS internals remain unmeasured",
        }
        metrics["coverage"]["unmeasured_dependency_boundaries"] += [
            "dart_sdk_tls", "rustls_tokio_rustls",
        ]
        self.assertEqual(compare._validate_evidence(report, label="tls"), [])
        del metrics["known_own_copy_breakdown"]["router"]["io_buffer_front_copy_bytes"]
        findings = compare._validate_evidence(report, label="tls")
        self.assertTrue(any("router.io_buffer_front_copy_bytes" in f for f in findings))

    def test_sdk_masking_exception_only_applies_to_dart_websockets(self):
        report = self._report("mask", "flatbuffers", 1)
        report["protocol"] = "wamp_websocket_rpc"
        metrics = report["copy_metrics"]
        metrics["websocket_mask_copy_bytes"] = {
            "status": "not_measured", "scope": "dependency_internals",
            "dependency": "dart_sdk_websocket_masking",
            "reason": "SDK mask internals remain unmeasured",
        }
        metrics["coverage"]["unmeasured_dependency_boundaries"].append(
            "dart_sdk_websocket_masking"
        )
        self.assertEqual(compare._validate_evidence(report, label="mask"), [])
        report["client_impl"] = "native"
        self.assertTrue(any("websocket_mask_copy_bytes" in f for f in
                            compare._validate_evidence(report, label="mask")))

    def test_rejects_legacy_scope_and_forged_owned_transport_totals(self):
        report = self._report("scope", "flatbuffers", 1)
        del report["copy_metrics"]["measurement_scope"]
        self.assertTrue(any("measurement scope" in f for f in
                            compare._validate_evidence(report, label="scope")))
        report["copy_metrics"]["measurement_scope"] = compare.COPY_MEASUREMENT_SCOPE
        report["copy_metrics"]["transport_copy_bytes"] = 0
        self.assertTrue(any("does not equal" in f for f in
                            compare._validate_evidence(report, label="scope")))

    def test_legacy_policy_cannot_silently_reinterpret_new_reports(self):
        policy = copy.deepcopy(self.policy)
        del policy["copy_measurement_scope"]
        result = compare.evaluate_campaign(self.manifest, self.root, policy)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("versioned" in f for f in result["findings"]))

    def test_standard_sdk_does_not_claim_zero_tls_internal_copies(self):
        report = self._report("tls", "flatbuffers", 1)
        report["wamp_configuration"]["secure_transport"] = True
        report["copy_metrics"]["tls_copy_bytes"] = 0
        self.assertTrue(any("TLS internals" in f for f in
                            compare._validate_evidence(report, label="tls")))

    def test_failed_copy_reports_still_render_their_findings(self):
        result = compare.evaluate_campaign(self.manifest, self.root, self.policy)
        result["status"] = "failed"
        result["findings"] = ["missing copy evidence"]
        result["cases"][0]["evidence"] = {"cbor": [
            {"copy_metrics": None},
            {"copy_metrics": {"coverage": None}},
            {"copy_metrics": {"coverage": {"unmeasured_dependency_boundaries": None}}},
        ]}
        rendered = compare.render_markdown(result)
        self.assertIn("missing copy evidence", rendered)
        self.assertIn("none reported", rendered)

    def test_dependency_labels_do_not_excuse_owned_metrics(self):
        for field in ("transport_copy_bytes", "transcode_copy_bytes", "e2ee_copy_bytes"):
            report = self._report("owned", "flatbuffers", 1)
            report["copy_metrics"][field] = {
                "status": "not_measured", "scope": "dependency_internals",
                "dependency": "dart_sdk_socket_io", "reason": "fake exclusion",
            }
            self.assertTrue(any(field in f for f in
                                compare._validate_evidence(report, label="owned")))

    def test_dependency_labels_require_the_active_path_and_explanation(self):
        report = self._report("labels", "flatbuffers", 1)
        metrics = report["copy_metrics"]
        for labels in (None, [], ["dart_sdk_socket_io", "missing_own_counter"], [42]):
            metrics["coverage"]["unmeasured_dependency_boundaries"] = labels
            self.assertTrue(any("dependency boundary labels" in f for f in
                                compare._validate_evidence(report, label="labels")))

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

    def test_encoded_volume_is_distinct_from_application_bytes(self):
        result = compare.evaluate_campaign(self.manifest, self.root, self.policy)
        self.assertEqual(result['status'], 'passed', result['findings'])
        evidence = result['cases'][0]['evidence']['flatbuffers'][0]
        self.assertNotIn('wire_bytes', evidence)
        self.assertEqual(evidence['encoded_wamp_volume']['accepted_bytes'], 4000)
        self.assertNotEqual(sum(evidence['application_bytes'].values()), 4000)

    def test_encoded_volume_rejects_incomplete_or_forged_observations(self):
        valid = self._report('test', 'flatbuffers', 1)['copy_metrics']['encoded_wamp_volume']
        mutations = [
            lambda x: x.pop('components'),
            lambda x: x['components'].pop('client_dart'),
            lambda x: x['components'].update(client_dart=True),
            lambda x: x['components'].update(client_dart=1.0),
            lambda x: x['components'].update(client_dart=-1),
            lambda x: x['components'].update(client_dart=9007199254740992),
            lambda x: x.update(accepted_bytes=4000.0),
            lambda x: x.update(accepted_bytes=3999),
            lambda x: x.update(known_accepted_bytes=3999),
            lambda x: x.update(rejected_submissions=0.0),
            lambda x: x.update(rejected_submissions=1),
            lambda x: x.update(unknown_boundaries=['missing worker']),
            lambda x: x.update(excludes=[]),
            lambda x: x.update(measurement_scope='logical_application_bytes'),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                bad = copy.deepcopy(valid)
                mutate(bad)
                self.assertTrue(compare._encoded_wamp_volume_findings(bad, 'test'))
        for missing in [None, [], {}, {'status': 'not_measured'}]:
            self.assertTrue(compare._encoded_wamp_volume_findings(missing, 'test'))

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

    def test_rejects_non_linux_campaign_platform(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        manifest["metadata"]["platform"]["os"] = "Darwin"

        findings = compare._campaign_findings(manifest)

        self.assertTrue(
            any("metadata.platform.os must be Linux" in item for item in findings)
        )

    def test_rejects_diagnostic_or_incomplete_runner_evidence(self) -> None:
        for execution in (
            {"status": "planned", "driver_exit_code": 0, "process_group_stopped": True},
            {"status": "failed", "driver_exit_code": 7, "process_group_stopped": True},
            {"status": "completed", "driver_exit_code": 0, "process_group_stopped": False},
        ):
            with self.subTest(execution=execution):
                manifest = copy.deepcopy(self.manifest)
                manifest["execution"] = execution
                findings = compare._campaign_findings(manifest)
                self.assertTrue(any("execution" in item for item in findings))
        manifest = copy.deepcopy(self.manifest)
        manifest["metadata"]["campaign_kind"] = "diagnostic"
        manifest["metadata"]["inputs_unchanged"] = False
        findings = compare._campaign_findings(manifest)
        self.assertTrue(any("diagnostic" in item for item in findings))
        self.assertTrue(any("inputs" in item for item in findings))

    def test_rejects_duplicate_report_instead_of_overwriting_observations(self) -> None:
        run = copy.deepcopy(self.manifest["measured_runs"][0])
        path = self.root / run["results"]
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        rows.append(copy.deepcopy(rows[0]))
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        run["order"].append(rows[0]["workload"])
        with self.assertRaisesRegex(compare.CampaignError, "duplicate"):
            compare._resolve_results(self.root, run)

    def test_completed_runner_metadata_is_required_before_scoring(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        manifest['execution'] = {
            'status': 'completed', 'driver_exit_code': 0, 'process_group_stopped': True,
        }
        manifest['metadata']['inputs_unchanged'] = True
        for run in [*manifest['warmup_runs'], *manifest['measured_runs']]:
            run.update(status='completed', rows_completed=len(run['order']))
        self.assertEqual(compare.evaluate_campaign(manifest, self.root, self.policy)['status'], 'passed')
        manifest['metadata']['campaign_kind'] = 'diagnostic'
        result = compare.evaluate_campaign(manifest, self.root, self.policy)
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(any('diagnostic' in finding for finding in result['findings']))

    def test_primary_matrix_cannot_repeat_one_case_48_times(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        manifest["metadata"]["campaign_kind"] = "primary"
        manifest["cases"] *= 48
        self.assertTrue(any("matrix" in finding for finding in compare._campaign_findings(manifest)))

    def test_nested_encrypted_configuration_cannot_exempt_crypto_copies(self) -> None:
        report = self._report("case_flatbuffers", "flatbuffers", 0)
        report["wamp_configuration"] = {"ppt_scheme": "wamp"}
        findings = compare._validate_evidence(report, label="actual-encrypted-report")
        self.assertTrue(any("e2ee_copy_bytes cannot be not_applicable" in f for f in findings))

    def test_reported_codec_must_match_the_compared_workload(self) -> None:
        for run in self.manifest["measured_runs"]:
            path = self.root / run["results"]
            reports = [json.loads(line) for line in path.read_text().splitlines()]
            for report in reports:
                report["wamp_configuration"] = {"serializer": "json"}
            path.write_text("".join(json.dumps(row) + "\n" for row in reports))
        result = compare.evaluate_campaign(self.manifest, self.root, self.policy)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("serializer" in finding for finding in result["findings"]))

    def test_actual_profile_transport_and_construction_are_verified(self) -> None:
        case = {"transport": "rawsocket", "mode": "rpc", "client_impl": "dart",
                "secure_transport": False, "construction": "native_buffer"}
        report = self._report("case_flatbuffers", "flatbuffers", 0)
        report["wamp_configuration"] = {
            "serializer": "flatbuffers", "peer_serializer": None, "peer_count": 1,
            "secure_transport": False, "ppt_scheme": "x_connectanum_bench_typed",
            "ppt_serializer": "flatbuffers", "payload_construction": "native_buffer",
            "ppt_cipher": None, "ppt_keyid": None,
        }
        self.assertEqual(compare._configuration_findings(
            report, case, "flatbuffers", label="fixture", required=True), [])
        for field, value in (("secure_transport", True), ("ppt_serializer", "cbor"),
                             ("payload_construction", "values"), ("peer_count", True)):
            changed = copy.deepcopy(report)
            changed["wamp_configuration"][field] = value
            self.assertTrue(any(field in f for f in compare._configuration_findings(
                changed, case, "flatbuffers", label="fixture", required=True)))
        report["request_chunk_bytes"] = 1024
        self.assertTrue(any("request_chunk_bytes" in f for f in compare._configuration_findings(
            report, case, "flatbuffers", label="fixture", required=True)))

    def test_warmup_restart_is_rejected_independently_of_execution_claim(self) -> None:
        manifest = self.manifest
        manifest["metadata"]["campaign_kind"] = "diagnostic"
        manifest["execution"] = {
            "status": "completed", "driver_exit_code": 0, "process_group_stopped": True,
            "observed_process_pids": {"client_process_metrics": 1000, "server_process_metrics": 2000},
        }
        manifest["cases"][0].update(mode="rpc", transport="rawsocket", client_impl="dart", secure_transport=False)
        path = self.root / manifest["warmup_runs"][0]["results"]
        reports = [json.loads(line) for line in path.read_text().splitlines()]
        reports[0]["client_process_metrics"]["pid"] = 999
        path.write_text("".join(json.dumps(row) + "\n" for row in reports))
        result = compare.evaluate_campaign(manifest, self.root, self.policy)
        self.assertTrue(any("pid must remain stable" in f for f in result["findings"]))

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

    def test_rejects_missing_server_process_metrics(self) -> None:
        report = self._report("case_flatbuffers", "flatbuffers", 0)
        report.pop("server_process_metrics")

        findings = compare._validate_evidence(report, label="missing-server")

        self.assertTrue(any("missing server_process_metrics" in f for f in findings))

    def test_rejects_partial_crypto_measurements(self) -> None:
        for total in ({"status": "not_measured"}, 0):
            with self.subTest(total=total):
                report = self._report("case_flatbuffers", "flatbuffers", 0)
                report["copy_metrics"]["e2ee_copy_bytes"] = total
                report["copy_metrics"]["e2ee_copy_breakdown"] = {
                    "coverage": "known_staging_only"
                }
                findings = compare._validate_evidence(report, label="partial-crypto")
                self.assertTrue(any("e2ee_copy_bytes" in f for f in findings))

    def test_rejects_crypto_exemption_for_encrypted_workload(self) -> None:
        report = self._report("case_flatbuffers", "flatbuffers", 0)
        report["ppt_scheme"] = "wamp"
        findings = compare._validate_evidence(report, label="encrypted-exemption")
        self.assertTrue(any("e2ee_copy_bytes cannot be not_applicable" in f for f in findings))

    def test_rejects_transport_copy_total_without_complete_coverage(self) -> None:
        for coverage in (
            None,
            {"transport_copy_bytes": "partial", "unknown_boundaries": []},
            {
                "transport_copy_bytes": "complete_connectanum_owned_path",
                "unknown_boundaries": ["Dart socket write behavior"],
            },
        ):
            with self.subTest(coverage=coverage):
                report = self._report("case_flatbuffers", "flatbuffers", 0)
                if coverage is None:
                    report["copy_metrics"].pop("coverage")
                else:
                    report["copy_metrics"]["coverage"] = coverage

                findings = compare._validate_evidence(
                    report,
                    label="incomplete-copy-coverage",
                )

                self.assertTrue(
                    any(
                        "coverage" in finding or "transport_copy_bytes" in finding
                        for finding in findings
                    )
                )

    def test_rejects_missing_native_input_copy_breakdown(self) -> None:
        for process in ("router", "client"):
            for field in ("io_buffer_front_copy_bytes", "io_buffered_read_copy_bytes", "ffi_borrowed_send_input_copy_bytes"):
                for invalid in (None, True, -1, float("inf"), {"status": "not_measured"}):
                    with self.subTest(process=process, field=field, invalid=invalid):
                        report = self._report("case_flatbuffers", "flatbuffers", 0)
                        report["client_impl"] = "native"
                        breakdown = report["copy_metrics"]["known_own_copy_breakdown"]
                        breakdown["client"] = {
                            field: 0 for field in compare.NATIVE_CLIENT_COPY_FIELDS
                        }
                        if invalid is None:
                            breakdown[process].pop(field)
                        else:
                            breakdown[process][field] = invalid
                        findings = compare._validate_evidence(report, label="old-native-input")
                        self.assertTrue(any(f"{process}.{field}" in item for item in findings))

    def test_rejects_not_applicable_transport_copy_total(self) -> None:
        report = self._report("case_flatbuffers", "flatbuffers", 0)
        report["copy_metrics"]["transport_copy_bytes"] = {
            "status": "not_applicable",
            "reason": "claimed unavailable",
        }

        findings = compare._validate_evidence(report, label="not-applicable-copy")

        self.assertTrue(
            any("transport_copy_bytes cannot be not_applicable" in item for item in findings)
        )

    def test_rejects_unmeasured_zero_process_cpu_and_allocations(self) -> None:
        report = self._report("case_flatbuffers", "flatbuffers", 0)
        server = report["server_process_metrics"]
        server["cpu_user_us_delta"] = 0
        server["cpu_system_us_delta"] = 0
        server["allocated_bytes_delta"] = 0

        findings = compare._validate_evidence(report, label="zero-server")

        self.assertTrue(any("CPU delta must be positive" in f for f in findings))
        self.assertTrue(any("allocation delta must be positive" in f for f in findings))

    def test_resource_metrics_sum_client_and_server_processes(self) -> None:
        report = self._report("case_flatbuffers", "flatbuffers", 0)

        summary, findings = compare._summarize_report(
            report,
            min_duration_ms=10_000,
            min_samples=25,
            label="paired-processes",
        )

        self.assertEqual(findings, [])
        self.assertEqual(summary["cpu_us_per_operation"], 80.0)
        self.assertEqual(summary["allocated_bytes_per_operation"], 80000.0)
        self.assertEqual(summary["gc_pause_us_per_operation"], 8.0)
        self.assertEqual(
            summary["summed_sampled_peak_rss_bytes"],
            report["client_process_metrics"]["peak_rss_during_bytes"]
            + report["server_process_metrics"]["peak_rss_during_bytes"],
        )

    def test_missing_resource_observations_never_render_as_parity(self) -> None:
        for run in self.manifest["measured_runs"]:
            path = self.root / run["results"]
            reports = [json.loads(line) for line in path.read_text().splitlines()]
            for report in reports:
                for process in ("client_process_metrics", "server_process_metrics"):
                    for field in ("cpu_user_us_delta", "allocated_bytes_delta", "peak_rss_during_bytes"):
                        report[process].pop(field)
            path.write_text("".join(json.dumps(report) + "\n" for report in reports))
        result = compare.evaluate_campaign(self.manifest, self.root, self.policy)
        self.assertEqual(result["status"], "failed")
        for metric in ("cpu_us_per_operation", "allocated_bytes_per_operation", "summed_sampled_peak_rss_bytes"):
            observed = result["cases"][0]["metrics"][metric]
            self.assertFalse(observed["passed"])
            self.assertIsNone(observed["median_ratio"])
            self.assertIsNone(observed["ci_95_low"])
            self.assertEqual(len(observed["observations"]), 7)
            self.assertTrue(all(row["ratio"] is None for row in observed["observations"]))
        self.assertIn("unmeasured", compare.render_markdown(result))

    def test_positive_legacy_heap_census_cannot_establish_allocation_parity(self):
        report = self._report("legacy", "flatbuffers", 0)
        for key in ("client_process_metrics", "server_process_metrics"):
            report[key].pop("allocation_measurement")
        summary, findings = compare._summarize_report(
            report, min_duration_ms=10000, min_samples=25, label="legacy",
        )
        self.assertIsNone(summary["allocated_bytes_per_operation"])
        self.assertTrue(any("allocation measurement" in finding for finding in findings))

    def test_allocation_gate_uses_conservative_bounds_and_retains_points(self):
        result = compare.evaluate_campaign(self.manifest, self.root, self.policy)
        metric = result["cases"][0]["metrics"]["allocated_bytes_per_operation"]
        observed = metric["observations"][0]
        self.assertEqual(observed["flatbuffers"], 80000)
        bounds = observed["comparison_bounds"]
        self.assertGreater(bounds["flatbuffers_upper"], observed["flatbuffers"])
        self.assertLess(bounds["msgpack_lower"], observed["msgpack"])
        self.assertEqual(observed["ratio"], bounds["flatbuffers_upper"] / bounds["msgpack_lower"])

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
