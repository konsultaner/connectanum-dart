import unittest

from run_mqtt_benchmark_gate import compare


BUDGET = {
    "profile": "mqtt5-tcp-qos0-one-subscriber-128B",
    "repetitions": 3,
    "messages_per_run": 2000,
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
                "throughput_delivered_per_sec": (
                    connectanum_speed if target == "connectanum" else 100000),
                "latency_p95_us": 110 if target == "connectanum" else 100,
                "latency_p99_us": connectanum_p99 if target == "connectanum" else 100,
            })
    return result


class MqttBenchmarkGateTest(unittest.TestCase):
    def test_good_matched_delivery_passes(self):
        self.assertTrue(compare(rows(), BUDGET)["passed"])

    def test_throughput_and_tail_regressions_fail(self):
        self.assertFalse(compare(rows(connectanum_speed=60000), BUDGET)["passed"])
        self.assertFalse(compare(rows(connectanum_p99=180), BUDGET)["passed"])

    def test_loss_is_invalid_even_when_reported_throughput_is_high(self):
        with self.assertRaisesRegex(ValueError, "delivery"):
            compare(rows(connectanum_speed=200000, received=1999), BUDGET)

    def test_missing_control_run_is_invalid(self):
        with self.assertRaisesRegex(ValueError, "expected 3 runs"):
            compare(rows()[:-1], BUDGET)


if __name__ == "__main__":
    unittest.main()
