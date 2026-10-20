import copy
import json
import os
from pathlib import Path
import subprocess
import unittest

from dart_heap_allocation_evidence import allocation_evidence, METHOD, SCOPE


def allocation_fixture(process):
    """Synthetic resource observations, never a performance benchmark."""
    count = process["gc_count_delta"]
    amount = process["allocated_bytes_delta"]
    initial = 1024 * 1024
    reclaimed = count * 1024
    return {
        "status": "measured", "method": METHOD, "scope": SCOPE,
        "observed_pid": process["pid"], "observer_pid": 9000,
        "capture_strategy": "external_process", "sdk_version": "synthetic test fixture",
        "estimated_bytes": amount, "rounding_error_bound_bytes": count * 2048,
        "heap_before_bytes": initial, "heap_after_bytes": initial + amount - reclaimed,
        "reclaimed_bytes": reclaimed, "young_gc_events": count, "old_gc_events": 0,
        "heap_group_ids": ["isolateGroups/7"],
        "start_snapshot_before_us": 100, "start_snapshot_after_us": 110,
        "end_snapshot_before_us": 1000000, "end_snapshot_after_us": 1000010,
        "heap_observations": {"isolateGroups/7": {
            "before_used_bytes": initial, "after_used_bytes": initial + amount - reclaimed,
            "before_young_collections": 0, "after_young_collections": count,
            "before_old_collections": 0, "after_old_collections": 0,
        }},
        "gc_observations": [{
            "isolate_group_id": "isolateGroups/7", "thread_id": 9,
            "timestamp_us": 200 + i, "kind": "CollectNewGeneration",
            "before_new_bytes": initial, "after_new_bytes": initial - 1024,
            "before_old_bytes": 0, "after_old_bytes": 0,
        } for i in range(count)],
    }


class DartHeapAllocationEvidenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([
            "dart", "--packages=" + str(root / ".dart_tool/package_config.json"),
            "--timeline_streams=GC", "--enable-vm-service=0/127.0.0.1",
            str(root / "packages/connectanum_bench/test/support/dart_vm_metrics_probe.dart"),
        ], cwd=root, env={**os.environ, "CONNECTANUM_SKIP_NATIVE_BUILD": "1"},
            capture_output=True, text=True, timeout=45, check=True)
        records = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
        if len(records) != 1:
            raise AssertionError("Allocation calibration did not produce one result")
        cls.calibration = records[0]

    def process(self):
        raw = self.calibration
        return copy.deepcopy({
            "pid": raw["allocation_measurement"]["observed_pid"],
            "gc_count_delta": raw["gc_count_delta"],
            "allocated_bytes_delta": raw["allocated_bytes_delta"],
            "allocation_measurement": raw["allocation_measurement"],
        })

    def check(self, process, extra_pids=()):
        return allocation_evidence(process, observed_pids={process["pid"], *extra_pids}, label="test")

    def test_live_standard_sdk_volume_matches_independent_recomputation(self):
        process = self.process()
        amount, bound, findings = self.check(process)
        self.assertEqual(findings, [])
        self.assertGreaterEqual(amount, 80 * 1024 * 1024)
        self.assertLess(amount, 160 * 1024 * 1024)
        self.assertLessEqual(bound * 100, amount)
        for key in ("pid_mismatch_rejected", "observer_crash_propagated", "close_idempotent"):
            self.assertIs(self.calibration[key], True)

    def test_legacy_census_or_missing_observation_never_becomes_zero(self):
        for replacement in (None, {}, {"status": "not_measured"}, {"method": "live_heap_census"}):
            process = self.process()
            process["allocation_measurement"] = replacement
            amount, bound, findings = self.check(process)
            self.assertIsNone(amount)
            self.assertIsNone(bound)
            self.assertTrue(findings)

    def test_subtotals_error_bounds_and_raw_event_inventory_are_recomputed(self):
        for field in ("estimated_bytes", "heap_before_bytes", "heap_after_bytes", "reclaimed_bytes",
                      "rounding_error_bound_bytes", "young_gc_events", "old_gc_events"):
            process = self.process()
            process["allocation_measurement"][field] += 1
            self.assertTrue(self.check(process)[2], field)
        for change in ("missing", "duplicate", "forged"):
            process = self.process()
            events = process["allocation_measurement"]["gc_observations"]
            if change == "missing":
                events.pop()
            elif change == "duplicate":
                events.append(copy.deepcopy(events[0]))
            else:
                events[0]["before_new_bytes"] += 1024
            self.assertTrue(self.check(process)[2], change)

    def test_all_raw_numeric_fields_require_exact_bounded_integers(self):
        for field in ("thread_id", "timestamp_us", "before_new_bytes", "after_old_bytes"):
            for invalid in (None, True, 1.0, -1, 1 << 62):
                process = self.process()
                process["allocation_measurement"]["gc_observations"][0][field] = invalid
                self.assertTrue(self.check(process)[2], (field, invalid))

    def test_group_counter_and_timestamp_boundaries_cannot_be_relabelled(self):
        for field, value in (("kind", "FutureCollection"), ("isolate_group_id", "unknown"),
                             ("timestamp_us", self.process()["allocation_measurement"]["start_snapshot_before_us"]),
                             ("before_new_bytes", 1)):
            process = self.process()
            process["allocation_measurement"]["gc_observations"][0][field] = value
            self.assertTrue(self.check(process)[2], field)
        process = self.process()
        next(iter(process["allocation_measurement"]["heap_observations"].values()))["after_old_collections"] += 1
        self.assertTrue(self.check(process)[2])

    def test_observer_must_be_outside_both_application_processes(self):
        process = self.process()
        observer = process["allocation_measurement"]["observer_pid"]
        self.assertTrue(self.check(process, extra_pids=[observer])[2])
        for key, value in (("observed_pid", process["pid"] + 1), ("observer_pid", process["pid"]),
                           ("capture_strategy", "self_observed"), ("sdk_version", "")):
            process = self.process()
            process["allocation_measurement"][key] = value
            self.assertTrue(self.check(process)[2], key)


if __name__ == "__main__":
    unittest.main()
