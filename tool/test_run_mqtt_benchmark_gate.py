import os
import json
import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import run_mqtt_benchmark_gate as gate
from run_mqtt_benchmark_gate import (
    _parse_cpu_time,
    compare,
    process_metrics,
    targets_for_repeat,
)


BUDGET = {
    "profile": "mqtt5-tcp-qos0-one-subscriber-128B",
    "repetitions": 3,
    "messages_per_run": 2000,
    "payload_bytes": 128,
    "gate": "performance",
    "min_delivered_throughput_ratio_vs_mosquitto": 0.65,
    "max_p95_latency_ratio_vs_mosquitto": 1.75,
    "max_p99_latency_ratio_vs_mosquitto": 1.75,
    "max_broker_cpu_ratio_vs_mosquitto": 3.0,
    "max_connectanum_broker_rss_bytes": 67_108_864,
}


def rows(connectanum_speed=80000, connectanum_p99=120, received=2000):
    result = []
    for run in range(1, 4):
        for target in ("connectanum", "mosquitto"):
            result.append({
                "target": target,
                "run": run,
                "profile": BUDGET["profile"],
                "mqtt_version": "5",
                "sent": 2000,
                "received": received if target == "connectanum" else 2000,
                "received_per_subscriber": [
                    received if target == "connectanum" else 2000],
                "subscribers": 1,
                "duplicates": 0,
                "window_messages": 0,
                "payload_bytes": 128,
                "throughput_delivered_per_sec": (
                    connectanum_speed if target == "connectanum" else 100000),
                "latency_p95_us": 110 if target == "connectanum" else 100,
                "latency_p99_us": connectanum_p99 if target == "connectanum" else 100,
                "broker_cpu_seconds": 0.2 if target == "connectanum" else 0.1,
                "broker_rss_bytes": 20_000_000 if target == "connectanum" else 4_000_000,
            })
    return result


class MqttBenchmarkGateTest(unittest.TestCase):
    def test_payload_size_and_transport_are_passed_to_the_client(self):
        budget = dict(BUDGET, payload_bytes=1024)
        with mock.patch.dict(gate.os.environ,
                             {"MQTT_BENCH_PAYLOAD_BYTES": "65536"}):
            tcp = gate.workload_environment(budget, "tcp")
            tls = gate.workload_environment(budget, "tls")
            ws = gate.workload_environment(budget, "ws")
            wss = gate.workload_environment(budget, "wss")
        self.assertEqual(tcp["MQTT_BENCH_PAYLOAD_BYTES"], "1024")
        self.assertNotIn("MQTT_BENCH_TLS_CA", tcp)
        self.assertEqual(tls["MQTT_BENCH_PAYLOAD_BYTES"], "1024")
        self.assertEqual(tls["MQTT_BENCH_TLS_CA"], str(gate.TLS_CA))
        self.assertEqual(ws["MQTT_BENCH_TRANSPORT"], "ws")
        self.assertNotIn("MQTT_BENCH_TLS_CA", ws)
        self.assertEqual(wss["MQTT_BENCH_TRANSPORT"], "wss")
        self.assertEqual(wss["MQTT_BENCH_TLS_CA"], str(gate.TLS_CA))

    def test_large_payload_profiles_require_their_exact_workload(self):
        for size in (1024, 65536):
            with self.subTest(size=size):
                profile = f"mqtt5-tcp-qos0-one-subscriber-{size}B"
                budget = dict(BUDGET, profile=profile, payload_bytes=size)
                samples = rows()
                for sample in samples:
                    sample.update(profile=profile, payload_bytes=size)
                self.assertEqual(compare(samples, budget)["profile"], profile)
                samples[0]["payload_bytes"] = 128
                with self.assertRaisesRegex(ValueError, "invalid workload"):
                    compare(samples, budget)

    def test_large_payload_budgets_enforce_delivery_and_cpu(self):
        for filename in (
                "mqtt_native_1k_sustained_benchmark_budget.json",
                "mqtt_native_64k_sustained_benchmark_budget.json"):
            with self.subTest(filename=filename):
                budget = json.loads((gate.ROOT / "tool" / filename).read_text())
                pair = rows(connectanum_speed=100_000)[:2]
                samples = [dict(row, run=run) for run in range(1, 6)
                           for row in pair]
                for row in samples:
                    row.update(profile=budget["profile"],
                               sent=budget["messages_per_run"],
                               received=budget["messages_per_run"],
                               received_per_subscriber=[budget["messages_per_run"]],
                               payload_bytes=budget["payload_bytes"],
                               window_messages=budget["window_messages"])
                self.assertTrue(compare(samples, budget)["passed"])
                samples[0]["received"] -= 1
                with self.assertRaisesRegex(ValueError, "invalid workload"):
                    compare(samples, budget)
                samples[0]["received"] += 1
                for row in samples:
                    if row["target"] == "connectanum":
                        row["broker_cpu_seconds"] = 1.0
                self.assertFalse(compare(samples, budget)["passed"])

    def test_native_router_requires_an_existing_library(self):
        argv = ["run_mqtt_benchmark_gate", "--native-router", "--output", "unused"]
        with (mock.patch.object(gate.sys, "argv", argv),
              mock.patch.dict(gate.os.environ, {"CONNECTANUM_NATIVE_LIB": ""}),
              contextlib.redirect_stderr(io.StringIO())):
            with self.assertRaises(SystemExit):
                gate.main()
        with (mock.patch.object(gate.sys, "argv", argv),
              mock.patch.dict(gate.os.environ,
                              {"CONNECTANUM_NATIVE_LIB": "/missing/ct_ffi.so"}),
              contextlib.redirect_stderr(io.StringIO())):
            with self.assertRaises(SystemExit):
                gate.main()

    def test_tls_budget_requires_native_router_and_known_transport(self):
        with tempfile.TemporaryDirectory() as directory:
            budget = Path(directory) / "budget.json"
            argv = ["run_mqtt_benchmark_gate", "--output", str(Path(directory) / "out"),
                    "--budget", str(budget)]
            for transport, expected in (("tls", "requires --native-router"),
                                        ("quic", "invalid MQTT transport")):
                budget.write_text(json.dumps(dict(BUDGET, transport=transport)))
                errors = io.StringIO()
                with (mock.patch.object(gate.sys, "argv", argv),
                      contextlib.redirect_stderr(errors)):
                    with self.assertRaisesRegex(SystemExit, "2"):
                        gate.main()
                self.assertIn(expected, errors.getvalue())
                self.assertFalse((Path(directory) / "out").exists())

    def test_tls_reference_config_selects_certificates(self):
        plain = gate.mosquitto_config(1883, "tcp")
        secure = gate.mosquitto_config(8883, "tls")
        self.assertNotIn("certfile", plain)
        self.assertIn(f"certfile {gate.TLS_CERT}", secure)
        self.assertIn(f"keyfile {gate.TLS_KEY}", secure)

    def test_websocket_reference_config_and_matched_rows(self):
        for transport in ("ws", "wss"):
            with self.subTest(transport=transport):
                config = gate.mosquitto_config(9001, transport)
                self.assertIn("protocol websockets", config)
                self.assertEqual("certfile" in config, transport == "wss")
                budget = dict(BUDGET, transport=transport,
                              profile=f"mqtt5-{transport}-qos0-one-subscriber-128B")
                samples = rows()
                for sample in samples:
                    sample.update(transport=transport, profile=budget["profile"])
                self.assertTrue(compare(samples, budget)["passed"])
                samples[0]["transport"] = "tcp"
                with self.assertRaisesRegex(ValueError, "invalid workload"):
                    compare(samples, budget)

    def test_websocket_budgets_gate_exact_delivery_and_performance(self):
        for filename in (
                "mqtt_native_ws_sustained_benchmark_budget.json",
                "mqtt_native_ws_v311_sustained_benchmark_budget.json",
                "mqtt_native_wss_sustained_benchmark_budget.json"):
            with self.subTest(filename=filename):
                budget = json.loads((gate.ROOT / "tool" / filename).read_text())
                samples = [dict(row, run=run) for run in range(1, 6)
                           for row in rows(connectanum_speed=300_000)[:2]]
                for row in samples:
                    row.update(profile=budget["profile"],
                               mqtt_version=budget["mqtt_version"],
                               transport=budget["transport"],
                               publish_mode=budget["publish_mode"],
                               sent=budget["messages_per_run"],
                               received=budget["messages_per_run"],
                               received_per_subscriber=[budget["messages_per_run"]],
                               window_messages=budget["window_messages"],
                               latency_p95_us=50 if row["target"] == "connectanum" else 100,
                               latency_p99_us=50 if row["target"] == "connectanum" else 100,
                               broker_cpu_seconds=0.1)
                self.assertTrue(compare(samples, budget)["passed"])
                samples[0]["received"] -= 1
                with self.assertRaisesRegex(ValueError, "invalid workload"):
                    compare(samples, budget)
                samples[0]["received"] += 1
                for row in samples:
                    if row["target"] == "connectanum":
                        row["throughput_delivered_per_sec"] = 100
                self.assertFalse(compare(samples, budget)["passed"])

    def test_wss_single_packet_smoke_requires_exact_delivery(self):
        budget = json.loads((gate.ROOT / "tool" /
                             "mqtt_native_wss_single_smoke_benchmark_budget.json").read_text())
        self.assertEqual(budget["mqtt_version"], "5")
        samples = rows()
        for row in samples:
            row.update(profile=budget["profile"], transport="wss",
                       window_messages=64)
        self.assertTrue(compare(samples, budget)["passed"])
        samples[0]["duplicates"] = 1
        with self.assertRaisesRegex(ValueError, "invalid workload"):
            compare(samples, budget)

    def test_native_tls_provenance_hashes_binaries_and_trust_material(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ("broker", "client", "native")]
            for path, contents in zip(paths, (b"broker", b"client", b"native")):
                path.write_bytes(contents)
            outputs = [subprocess.CompletedProcess([], 0, stdout=value, stderr="")
                       for value in ("commit\n", "", "Dart test\n")]
            with (mock.patch.object(gate.subprocess, "run", side_effect=outputs),
                  mock.patch.object(gate, "mosquitto_version", return_value="2.1.2")):
                result = gate.provenance(*paths[:2], "mosquitto", paths[2], "tls")
            self.assertEqual(result["broker_mode"], "native-router")
            self.assertEqual(result["git_commit"], "commit")
            self.assertFalse(result["git_dirty"])
            self.assertEqual(result["mosquitto_version"], "2.1.2")
            self.assertEqual(result["native_lib_sha256"], gate.hashlib.sha256(b"native").hexdigest())
            self.assertEqual(result["tls_ca_sha256"],
                             gate.hashlib.sha256(gate.TLS_CA.read_bytes()).hexdigest())
            self.assertEqual(result["tls_cert_sha256"],
                             gate.hashlib.sha256(gate.TLS_CERT.read_bytes()).hexdigest())
            self.assertEqual(result["tls_key_sha256"],
                             gate.hashlib.sha256(gate.TLS_KEY.read_bytes()).hexdigest())

    def test_exact_line_coverage_gate_rejects_missing_or_excluded_source(self):
        source = "tool/run_mqtt_benchmark_gate.py"
        report = {
            "files": {source: {}},
            "totals": {"num_statements": 179, "missing_lines": 0,
                       "excluded_lines": 0},
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "coverage.json"
            path.write_text(json.dumps(report))
            self.assertEqual(gate.require_exact_line_coverage(path), 179)
            for key, value in (("missing_lines", 1), ("excluded_lines", 1),
                               ("num_statements", 0)):
                broken = json.loads(json.dumps(report))
                broken["totals"][key] = value
                path.write_text(json.dumps(broken))
                with self.subTest(key=key), self.assertRaisesRegex(
                        ValueError, "exact 100% executable-line coverage"):
                    gate.require_exact_line_coverage(path)
            report["files"] = {"other.py": {}}
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, "exact 100% executable-line coverage"):
                gate.require_exact_line_coverage(path)

    def test_listener_wait_rejects_early_exit_and_deadline(self):
        exited = mock.Mock(args=["broker"], poll=mock.Mock(return_value=7))
        with self.assertRaisesRegex(RuntimeError, "exited before listening"):
            gate.wait_for_listener(1883, exited)
        pending = mock.Mock(poll=mock.Mock(return_value=None))
        with mock.patch.object(gate.time, "monotonic", side_effect=[0.0, 2.0]):
            with self.assertRaisesRegex(TimeoutError, "did not listen"):
                gate.wait_for_listener(1883, pending, timeout=1)

    def test_listener_wait_retries_connection_refusal(self):
        pending = mock.Mock(poll=mock.Mock(return_value=None))
        with (mock.patch.object(gate.socket, "create_connection",
                                side_effect=[OSError("refused"), mock.MagicMock()])
              as connect,
              mock.patch.object(gate.time, "sleep") as sleep):
            gate.wait_for_listener(1883, pending)
        self.assertEqual(connect.call_count, 2)
        sleep.assert_called_once_with(0.05)

    def test_forced_broker_stop_reaps_a_stuck_process(self):
        stuck = mock.Mock()
        stuck.wait.side_effect = [
            subprocess.TimeoutExpired("broker", 5), None]
        gate.stop_broker(stuck)
        stuck.terminate.assert_called_once_with()
        stuck.kill.assert_called_once_with()
        self.assertEqual(stuck.wait.call_count, 2)

    def test_port_pair_retries_a_collision(self):
        with mock.patch.object(gate, "available_port", side_effect=[1883, 1883, 1884]):
            self.assertEqual(gate.choose_broker_ports(), (1883, 1884))

    def test_client_failure_and_budget_failure_are_not_silent(self):
        failed = subprocess.CompletedProcess(
            ["client"], 7, stdout="", stderr="malformed CONNACK")
        with self.assertRaisesRegex(RuntimeError, "mosquitto run 2: malformed CONNACK"):
            gate.checked_client_row(failed, "mosquitto", 2)
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "broker.log"
            log.write_text("mqtt_connection_closed: protocol_error\n")
            with self.assertRaisesRegex(RuntimeError, "protocol_error"):
                gate.checked_client_row(failed, "mosquitto", 2, broker_log=log)
        success = subprocess.CompletedProcess(
            ["client"], 0, stdout='diagnostic\n{"sent": 10}\n', stderr="")
        self.assertEqual(gate.checked_client_row(success, "connectanum", 1),
                         {"sent": 10})
        with self.assertRaisesRegex(SystemExit, "performance budget failed"):
            gate.require_budget({"passed": False})
        self.assertIsNone(gate.require_budget({"passed": True}))

    def test_short_correctness_gate_records_noisy_rates_without_failing(self):
        budget = {key: BUDGET[key] for key in (
            "profile", "repetitions", "messages_per_run", "payload_bytes")}
        budget["gate"] = "correctness"
        noisy = rows(connectanum_speed=20_000, connectanum_p99=500)
        result = compare(noisy, budget)
        self.assertTrue(result["passed"])
        self.assertEqual(result["gate"], "correctness")
        noisy[0]["received"] = 1999
        with self.assertRaisesRegex(ValueError, "delivery"):
            compare(noisy, budget)
        budget["gate"] = "unknown"
        with self.assertRaisesRegex(ValueError, "invalid MQTT benchmark gate"):
            compare(rows(), budget)

    def test_target_order_balances_repeated_runs(self):
        self.assertEqual(targets_for_repeat(1, 11, 22),
                         (("connectanum", 11), ("mosquitto", 22)))
        self.assertEqual(targets_for_repeat(2, 11, 22),
                         (("mosquitto", 22), ("connectanum", 11)))

    def test_good_matched_delivery_passes(self):
        self.assertTrue(compare(rows(), BUDGET)["passed"])

    def test_reports_paired_throughput_spread_hidden_by_pooled_medians(self):
        samples = rows()
        rates = {
            "connectanum": (250_000, 145_000, 155_000),
            "mosquitto": (100_000, 200_000, 300_000),
        }
        for row in samples:
            row["throughput_delivered_per_sec"] = rates[row["target"]][row["run"] - 1]
        summary = compare(samples, dict(BUDGET,
                                        min_delivered_throughput_ratio_vs_mosquitto=0.75))
        self.assertEqual(summary["throughput_ratio"], 0.775)
        self.assertTrue(summary["passed"])
        self.assertEqual(summary["paired_throughput_ratio_median"], 0.725)
        self.assertAlmostEqual(summary["paired_throughput_ratio_min"], 155 / 300)
        self.assertEqual(summary["paired_throughput_ratio_max"], 2.5)

    def test_sustained_profile_requires_its_full_workload_and_resource_budgets(self):
        budget = dict(BUDGET, profile="mqtt5-tcp-qos0-one-subscriber-128B-window512",
                      messages_per_run=200_000, window_messages=512,
                      max_broker_cpu_ratio_vs_mosquitto=3,
                      max_connectanum_broker_rss_bytes=67_108_864)
        samples = rows()
        for row in samples:
            row.update(profile=budget["profile"], sent=200_000, received=200_000,
                       received_per_subscriber=[200_000], window_messages=512)
        self.assertTrue(compare(samples, budget)["passed"])
        samples[0]["received"] = 199_999
        with self.assertRaisesRegex(ValueError, "delivery"):
            compare(samples, budget)

    def test_shared_runner_sustained_budgets_allow_observed_tail_variation_but_reject_regression(self):
        for filename, version in (
                ("mqtt_sustained_benchmark_budget.json", "5"),
                ("mqtt_v311_sustained_benchmark_budget.json", "311")):
            with self.subTest(filename=filename):
                budget = json.loads((gate.ROOT / "tool" / filename).read_text())
                pair = rows(connectanum_speed=80_000, connectanum_p99=220)[:2]
                samples = [dict(row, run=run) for run in range(1, 6)
                           for row in pair]
                for row in samples:
                    row.update(profile=budget["profile"], mqtt_version=version,
                               sent=200_000, received=200_000,
                               received_per_subscriber=[200_000],
                               window_messages=512)
                    if row["target"] == "connectanum":
                        row["latency_p95_us"] = 190
                        row["broker_cpu_seconds"] = 0.19
                self.assertTrue(compare(samples, budget)["passed"])
                for key, value in (
                        ("throughput_delivered_per_sec", 74_000),
                        ("latency_p95_us", 205),
                        ("latency_p99_us", 230),
                        ("broker_cpu_seconds", 0.21)):
                    changed = [dict(row) for row in samples]
                    for row in changed:
                        if row["target"] == "connectanum":
                            row[key] = value
                    self.assertFalse(compare(changed, budget)["passed"], key)

    def test_native_router_sustained_budgets_bound_ffi_cpu_overhead(self):
        for filename, version in (
                ("mqtt_native_sustained_benchmark_budget.json", "5"),
                ("mqtt_native_v311_sustained_benchmark_budget.json", "311"),
                ("mqtt_native_tls_sustained_benchmark_budget.json", "5"),
                ("mqtt_native_tls_v311_sustained_benchmark_budget.json", "311")):
            with self.subTest(filename=filename):
                budget = json.loads((gate.ROOT / "tool" / filename).read_text())
                pair = rows(connectanum_speed=80_000, connectanum_p99=220)[:2]
                samples = [dict(row, run=run) for run in range(1, 6)
                           for row in pair]
                for row in samples:
                    row.update(profile=budget["profile"], mqtt_version=version,
                               transport=budget.get("transport", "tcp"),
                               sent=200_000, received=200_000,
                               received_per_subscriber=[200_000],
                               window_messages=512)
                    if row["target"] == "connectanum":
                        row["latency_p95_us"] = 190
                        row["broker_cpu_seconds"] = 0.24
                self.assertTrue(compare(samples, budget)["passed"])
                for row in samples:
                    if row["target"] == "connectanum":
                        row["broker_cpu_seconds"] = 0.26
                self.assertFalse(compare(samples, budget)["passed"])

    def test_batch_profile_requires_batch_client_workload(self):
        budget = dict(BUDGET,
                      profile="mqtt5-tcp-qos0-one-subscriber-128B-window512-batch512",
                      publish_mode="batch", messages_per_run=200_000,
                      window_messages=512)
        samples = rows()
        for row in samples:
            row.update(profile=budget["profile"], publish_mode="batch",
                       sent=200_000, received=200_000,
                       received_per_subscriber=[200_000], window_messages=512)
        self.assertTrue(compare(samples, budget)["passed"])
        samples[0]["publish_mode"] = "single"
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(samples, budget)
        single = rows()
        single[0]["publish_mode"] = "batch"
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(single, BUDGET)

    def test_mqtt311_budget_requires_actual_mqtt311_client_runs(self):
        budget = dict(BUDGET, mqtt_version="311",
                      profile="mqtt311-tcp-qos0-one-subscriber-128B")
        samples = rows()
        for row in samples:
            row["profile"] = budget["profile"]
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(samples, budget)
        for row in samples:
            row["mqtt_version"] = "311"
        self.assertTrue(compare(samples, budget)["passed"])
        with self.assertRaisesRegex(ValueError, "profile/version/transport mismatch"):
            compare(samples, dict(budget, profile=BUDGET["profile"]))
        with self.assertRaisesRegex(ValueError, "invalid MQTT version"):
            compare(samples, dict(budget, mqtt_version="31"))

    def test_tls_gate_rejects_plaintext_samples_and_invalid_transport(self):
        budget = dict(BUDGET, transport="tls",
                      profile="mqtt5-tls-qos0-one-subscriber-128B")
        samples = rows()
        for row in samples:
            row["profile"] = budget["profile"]
            row["transport"] = "tls"
        self.assertTrue(compare(samples, budget)["passed"])
        samples[0]["transport"] = "tcp"
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(samples, budget)
        with self.assertRaisesRegex(ValueError, "profile/version/transport mismatch"):
            compare(samples, dict(budget, transport="tcp"))
        with self.assertRaisesRegex(ValueError, "invalid MQTT transport"):
            compare(samples, dict(budget, transport="quic"))

    def test_fanout_requires_exact_delivery_on_every_subscriber(self):
        budget = dict(BUDGET, profile="mqtt5-tcp-qos0-fanout4-128B-window128-batch128",
                      subscribers=4, messages_per_run=50_000,
                      window_messages=128, publish_mode="batch")
        samples = rows()
        for row in samples:
            row.update(profile=budget["profile"], sent=50_000, received=200_000,
                       received_per_subscriber=[50_000] * 4,
                       subscribers=4, window_messages=128,
                       publish_mode="batch")
        result = compare(samples, budget)
        self.assertTrue(result["passed"])
        self.assertEqual(result["deliveries_per_run"], 200_000)
        self.assertEqual(result["connectanum_broker_cpu_seconds_per_million"], 1)
        samples[0]["received_per_subscriber"] = [50_001, 49_999, 50_000, 50_000]
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(samples, budget)
        samples[0]["received_per_subscriber"] = [50_000] * 4
        samples[0]["subscribers"] = 1
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(samples, budget)
        samples[0]["subscribers"] = 4
        samples[0]["duplicates"] = 1
        with self.assertRaisesRegex(ValueError, "delivery"):
            compare(samples, budget)

    def test_fanout_budget_rejects_zero_subscribers(self):
        with self.assertRaisesRegex(ValueError, "at least one subscriber"):
            compare(rows(), dict(BUDGET, subscribers=0))
        with self.assertRaisesRegex(ValueError, "at least one subscriber"):
            compare(rows(), dict(BUDGET, subscribers=True))

    def test_throughput_and_tail_regressions_fail(self):
        self.assertFalse(compare(rows(connectanum_speed=60000), BUDGET)["passed"])
        self.assertFalse(compare(rows(connectanum_p99=180), BUDGET)["passed"])

    def test_loss_is_invalid_even_when_reported_throughput_is_high(self):
        with self.assertRaisesRegex(ValueError, "delivery"):
            compare(rows(connectanum_speed=200000, received=1999), BUDGET)

    def test_missing_control_run_is_invalid(self):
        with self.assertRaisesRegex(ValueError, "expected 6 matched broker runs"):
            compare(rows()[:-1], BUDGET)

    def test_duplicate_run_id_or_unknown_target_is_invalid(self):
        duplicated = rows()
        duplicated[2]["run"] = 1
        with self.assertRaisesRegex(ValueError, "duplicate run identifiers"):
            compare(duplicated, BUDGET)
        unknown = rows()
        unknown[0]["target"] = "other"
        with self.assertRaisesRegex(ValueError, "expected 3 runs"):
            compare(unknown, BUDGET)

    def test_broker_cpu_and_rss_budgets_reject_regressions(self):
        with_cpu = dict(BUDGET, max_broker_cpu_ratio_vs_mosquitto=1.5)
        self.assertFalse(compare(rows(), with_cpu)["passed"])
        with_rss = dict(BUDGET, max_connectanum_broker_rss_bytes=19_000_000)
        self.assertFalse(compare(rows(), with_rss)["passed"])
        isolated_peak = rows()
        isolated_peak[0]["broker_rss_bytes"] = 30_000_000
        with_rss = dict(BUDGET, max_connectanum_broker_rss_bytes=25_000_000)
        self.assertFalse(compare(isolated_peak, with_rss)["passed"])

    def test_zero_control_cpu_fails_a_cpu_budget_without_dividing(self):
        no_control_cpu = rows()
        for row in no_control_cpu:
            if row["target"] == "mosquitto":
                row["broker_cpu_seconds"] = 0
        with_cpu = dict(BUDGET, max_broker_cpu_ratio_vs_mosquitto=3)
        self.assertFalse(compare(no_control_cpu, with_cpu)["passed"])

    def test_zero_or_nonfinite_throughput_is_invalid(self):
        bad = rows()
        bad[1]["throughput_delivered_per_sec"] = 0
        with self.assertRaisesRegex(ValueError, "invalid throughput"):
            compare(bad, BUDGET)
        invalid_cpu = rows()
        invalid_cpu[0]["broker_cpu_seconds"] = float("nan")
        with self.assertRaisesRegex(ValueError, "broker process metrics"):
            compare(invalid_cpu, BUDGET)
        bad[1]["throughput_delivered_per_sec"] = float("nan")
        with self.assertRaisesRegex(ValueError, "invalid throughput"):
            compare(bad, BUDGET)

    def test_missing_broker_metrics_and_wrong_window_are_invalid(self):
        missing_metrics = rows()
        del missing_metrics[0]["broker_rss_bytes"]
        with self.assertRaisesRegex(ValueError, "broker process metrics"):
            compare(missing_metrics, BUDGET)
        with_window = dict(BUDGET, window_messages=512)
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(rows(), with_window)
        wrong_profile = rows()
        wrong_profile[0]["profile"] = "different-profile"
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(wrong_profile, BUDGET)
        wrong_payload = rows()
        wrong_payload[0]["payload_bytes"] = 64
        with self.assertRaisesRegex(ValueError, "workload"):
            compare(wrong_payload, BUDGET)

    def test_process_metrics_report_the_broker_pid(self):
        cpu, rss, high_water = process_metrics(os.getpid())
        self.assertGreaterEqual(cpu, 0)
        self.assertGreater(rss, 0)
        self.assertGreaterEqual(high_water, rss)

    def test_linux_process_metrics_parse_cpu_and_high_water_rss(self):
        fields = ["0"] * 22
        fields[11] = "25"
        fields[12] = "15"
        stat = "123 (mqtt broker worker) " + " ".join(fields)
        status = "Name:\tmqtt\nVmRSS:\t120 kB\nVmHWM:\t240 kB\n"
        with (mock.patch.object(gate.sys, "platform", "linux"),
              mock.patch.object(gate.Path, "read_text", side_effect=[stat, status]),
              mock.patch.object(gate.os, "sysconf", return_value=100)):
            self.assertEqual(process_metrics(123), (0.4, 122880, 245760))

    def test_macos_process_metrics_parse_cpu_and_rss(self):
        with (mock.patch.object(gate.sys, "platform", "darwin"),
              mock.patch.object(gate.subprocess, "check_output",
                                return_value="1:02.50 1234\n")):
            self.assertEqual(process_metrics(123), (62.5, 1263616, 1263616))

    def test_macos_cpu_time_parser(self):
        self.assertEqual(_parse_cpu_time("2:03.45"), 123.45)
        self.assertEqual(_parse_cpu_time("1:02:03.45"), 3723.45)
        with self.assertRaisesRegex(ValueError, "invalid ps CPU time"):
            _parse_cpu_time("1")

    def test_mosquitto_help_exit_code_does_not_hide_its_version(self):
        help_result = subprocess.CompletedProcess(
            ["mosquitto", "-h"], 3, stdout="  mosquitto version 2.0.18\n",
            stderr="usage text\n")
        with mock.patch.object(gate.subprocess, "run", return_value=help_result):
            self.assertEqual(gate.mosquitto_version("mosquitto"),
                             "mosquitto version 2.0.18")
        help_result = subprocess.CompletedProcess(
            ["mosquitto", "-h"], 3, stdout="", stderr="mosquitto version 2.0.18\n")
        with mock.patch.object(gate.subprocess, "run", return_value=help_result):
            self.assertEqual(gate.mosquitto_version("mosquitto"),
                             "mosquitto version 2.0.18")
        help_result = subprocess.CompletedProcess(
            ["mosquitto", "-h"], 3, stdout="usage only", stderr="")
        with mock.patch.object(gate.subprocess, "run", return_value=help_result):
            with self.assertRaisesRegex(RuntimeError, "did not contain a version"):
                gate.mosquitto_version("mosquitto")


if __name__ == "__main__":
    unittest.main()
