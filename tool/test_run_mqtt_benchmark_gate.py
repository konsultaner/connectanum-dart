import os
import unittest
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
    "min_delivered_throughput_ratio_vs_mosquitto": 0.65,
    "max_p95_latency_ratio_vs_mosquitto": 1.75,
    "max_p99_latency_ratio_vs_mosquitto": 1.75,
}


def rows(connectanum_speed=80000, connectanum_p99=120, received=2000):
    result = []
    for run in range(1, 4):
        for target in ("connectanum", "mosquitto"):
            result.append({
                "target": target,
                "run": run,
                "profile": BUDGET["profile"],
                "sent": 2000,
                "received": received if target == "connectanum" else 2000,
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
    def test_target_order_balances_repeated_runs(self):
        self.assertEqual(targets_for_repeat(1, 11, 22),
                         (("connectanum", 11), ("mosquitto", 22)))
        self.assertEqual(targets_for_repeat(2, 11, 22),
                         (("mosquitto", 22), ("connectanum", 11)))

    def test_good_matched_delivery_passes(self):
        self.assertTrue(compare(rows(), BUDGET)["passed"])

    def test_sustained_profile_requires_its_full_workload_and_resource_budgets(self):
        budget = dict(BUDGET, profile="mqtt5-tcp-qos0-one-subscriber-128B-window512",
                      messages_per_run=200_000, window_messages=512,
                      max_broker_cpu_ratio_vs_mosquitto=3,
                      max_connectanum_broker_rss_bytes=67_108_864)
        samples = rows()
        for row in samples:
            row.update(profile=budget["profile"], sent=200_000, received=200_000,
                       window_messages=512)
        self.assertTrue(compare(samples, budget)["passed"])
        samples[0]["received"] = 199_999
        with self.assertRaisesRegex(ValueError, "delivery"):
            compare(samples, budget)

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

    def test_macos_cpu_time_parser(self):
        self.assertEqual(_parse_cpu_time("2:03.45"), 123.45)
        self.assertEqual(_parse_cpu_time("1:02:03.45"), 3723.45)
        with self.assertRaisesRegex(ValueError, "invalid ps CPU time"):
            _parse_cpu_time("1")


if __name__ == "__main__":
    unittest.main()
