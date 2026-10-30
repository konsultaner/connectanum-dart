"""Exercise diagnostic attribution, fail-closed controls and lease isolation."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_native_ppt_views as probe


class NativePptViewProbeTests(unittest.TestCase):
    def test_marker_follows_all_dart_library_directives(self):
        original = (probe.ROOT / probe.BUFFER).read_text()
        extra = "part 'src/transport/native/future_component.dart';"
        for source in (original, original.replace(
                "part 'src/transport/native/native_writable_bytes.dart';",
                "part 'src/transport/native/native_writable_bytes.dart';\n" + extra)):
            with self.subTest(extra_part=extra in source):
                patched = probe.mark_buffer_source(source, 'directive-marker')
                marker = patched.index("const nativePptViewProbeMarker")
                for line in source.splitlines():
                    if line.startswith(('part ', 'import ', 'library')):
                        self.assertLess(patched.index(line), marker)

    def test_source_patch_is_private_and_rejects_drift_or_ambiguous_patterns(self):
        buffer = (probe.ROOT / probe.BUFFER).read_text()
        transport = (probe.ROOT / probe.TRANSPORT).read_text()
        changed, fast = probe.patch_sources(buffer, transport, "fixture-marker")
        self.assertIn("PROTOTYPE_FORCED_PRODUCER_VIEW", changed)
        self.assertIn("flatBuffersOnly &&", fast)
        self.assertIn("nativePptViewProbeMarker = 'fixture-marker'", changed)
        self.assertEqual((probe.ROOT / probe.BUFFER).read_text(), buffer)
        self.assertEqual((probe.ROOT / probe.TRANSPORT).read_text(), transport)
        for bad in ("unrelated", buffer + buffer):
            with self.subTest(source=bad[:20]), self.assertRaises(ValueError):
                probe.patch_sources(bad, transport, "marker")

    def test_worker_requires_compile_time_marker_and_records_actual_scenario(self):
        original = (probe.ROOT / probe.WORKER).read_text()
        worker = probe.instrument_worker(original)
        self.assertIn("view_probe_source.nativePptViewProbeMarker", worker)
        self.assertIn("'iterations': scenario.iterations", worker)
        self.assertIn("'body_bytes': scenario.payloadBytes", worker)
        self.assertIn("captureViewProbe(nativeLibraryPath, scenario)", worker)
        self.assertIn("_handleRequest(trimmed, runner, nativeRuntime, nativeLibraryPath)", worker)
        self.assertIn("  String nativeLibraryPath,\n) async {", worker)
        self.assertLess(worker.index("PptCopyMetrics.endWindow()"),
                        worker.index("await captureViewProbe(nativeLibraryPath, scenario)"))
        self.assertLess(worker.index("await captureViewProbe(nativeLibraryPath, scenario)"),
                        worker.index("final fileMetrics = nativeRuntime.fileSegmentMetricsSnapshot()"))
        self.assertEqual((probe.ROOT / probe.WORKER).read_text(), original)

    def test_worker_request_frame_instrumentation_rejects_missing_or_ambiguous_anchors(self):
        original = (probe.ROOT / probe.WORKER).read_text()
        for anchor in (
            "      await _handleRequest(trimmed, runner, nativeRuntime);",
            "  NativeClientRuntime nativeRuntime,\n) async {",
            "  final fileMetrics = nativeRuntime.fileSegmentMetricsSnapshot()",
        ):
            for source in (original.replace(anchor, "missing anchor", 1),
                           original + "\n" + anchor):
                with self.subTest(anchor=anchor), self.assertRaisesRegex(
                        ValueError, "refusing a partial patch"):
                    probe.instrument_worker(source)

    def test_session_prototype_preserves_deferred_payload_only_for_controlled_flatbuffers(self):
        original = (probe.ROOT / probe.SESSION).read_text()
        patched = probe.patch_session(original)
        self.assertIn("payload.storageOwner is ({Object prototypeNativeBuffer})", patched)
        self.assertIn("options?.pptScheme != 'wamp'", patched)
        self.assertIn("options?.pptSerializer == 'flatbuffers'", patched)
        self.assertIn("message.restoreLazyPayload(payload);", patched)
        self.assertEqual((probe.ROOT / probe.SESSION).read_text(), original)
        with self.assertRaises(ValueError):
            probe.patch_session(original + original)

    def test_public_probe_uses_real_lease_with_strict_view_guard_and_owner_cleanup(self):
        original = (probe.ROOT / probe.BUFFER).read_text()
        runner = (probe.ROOT / probe.RUNNER).read_text()
        buffer, changed = probe.patch_public_lease(original, runner, "public-marker")
        self.assertNotIn("return leasePptPayload(", buffer)
        self.assertIn(probe.PUBLIC_FORCED, buffer)
        self.assertNotIn(probe.FORCED, buffer)
        self.assertEqual(changed, runner)
        self.assertIn("final leasedOwner = lease.nativeOwnerFor(payload);", changed)
        self.assertIn("producer.dispose();", changed)
        self.assertIn("lease!.dispose();", changed)
        self.assertEqual((probe.ROOT / probe.BUFFER).read_text(), original)
        self.assertEqual((probe.ROOT / probe.RUNNER).read_text(), runner)
        with self.assertRaises(ValueError):
            probe.patch_public_lease(original, runner + runner, "public-marker")

    def test_legacy_controls_restore_only_the_frozen_preparation_method(self):
        original = (probe.ROOT / probe.RUNNER).read_text()
        restored = probe.legacy_runner_source(original)
        before_start, before_end = probe.preparation_span(original)
        after_start, after_end = probe.preparation_span(restored)
        self.assertEqual(original[:before_start], restored[:after_start])
        self.assertEqual(original[before_end:], restored[after_end:])
        preparation = restored[after_start:after_end]
        self.assertIn("owner.asFlatBuffersPptPayload()", preparation)
        self.assertIn("owner.asPptPayload(", preparation)
        self.assertNotIn("leasePptPayload(", preparation)
        self.assertNotIn("leaseFlatBuffersPptPayload(", preparation)
        self.assertNotIn("producer.dispose();", preparation)
        self.assertEqual((probe.ROOT / probe.RUNNER).read_text(), original)

    def test_legacy_controls_reject_fixture_drift_and_ambiguous_or_old_runner(self):
        original = (probe.ROOT / probe.RUNNER).read_text()
        restored = probe.legacy_runner_source(original)
        for invalid in ("unrelated", original + original, restored,
                        original.replace("owner = leasedOwner;", "owner = null;")):
            with self.subTest(source=invalid[:20]), self.assertRaises(ValueError):
                probe.legacy_runner_source(invalid)
        with mock.patch.object(probe, "LEGACY_PREPARATION_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "fixture changed"):
                probe.legacy_runner_source(original)

    def test_passing_request_or_unrelated_failure_cannot_accept_negative_control(self):
        good = [{"status": 500, "body": probe.FORCED}]
        probe.validate_control([], good)
        for reports, failures in [([{}], good), ([], []), ([], [{"status": 500, "body": "compile error"}]),
                                  ([], [{"status": 200, "body": probe.FORCED}]),
                                  ([], [{"status": True, "body": probe.FORCED}])]:
            with self.subTest(reports=reports, failures=failures), self.assertRaises(ValueError):
                probe.validate_control(reports, failures)

    def fixture(self):
        reports, observations = [], []
        for construction in ("native_buffer", "pre_encoded_span"):
            for size in (0, 65536, 1048576):
                reports.append({"scenario": {"payload_construction": construction, "payload_bytes": size},
                                "report": {"samples": [None] * 1000}})
                for warmup in (True, False):
                    counts = {"pid": 123, **{name: 0 for name in probe.COUNTERS}}
                    observations.append({"kind": "forced_gc_ffi_test_diagnostic_never_acceptance",
                                         "codec": "flatbuffers", "construction": construction,
                                         "iterations": 1 if warmup else 1000,
                                         "body_bytes": min(1024, size) if warmup else size,
                                         "before_gc": counts,
                                         "after_gc": [{"counts": dict(counts)} for _ in range(3)]})
        return reports, observations

    def test_validates_complete_wire_and_lifetime_inventory(self):
        reports, observations = self.fixture()
        self.assertEqual(probe.validate_observations(observations, reports), 123)

    def test_baseline_allows_retention_only_before_gc(self):
        reports, observations = self.fixture()
        observations[0]["before_gc"]["owned_allocations"] = 1
        self.assertEqual(probe.validate_observations(observations, reports, immediate_cleanup=False), 123)
        with self.assertRaises(ValueError):
            probe.validate_observations(observations, reports)
        observations[0]["after_gc"][0]["counts"]["owned_allocations"] = 1
        with self.assertRaises(ValueError):
            probe.validate_observations(observations, reports, immediate_cleanup=False)
        original = (probe.ROOT / probe.BUFFER).read_text()
        baseline = probe.mark_buffer_source(original, "baseline-marker")
        self.assertEqual(baseline.count(probe.FORCED), 0)
        self.assertIn("final bytes = this.bytes;", baseline)

    def test_rejects_incomplete_duplicate_misattributed_and_live_owner_evidence(self):
        reports, observations = self.fixture()
        variants = []
        r, o = copy.deepcopy((reports, observations)); r[1] = r[0]; variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); r[0]["report"]["samples"].pop(); variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[0]["body_bytes"] = 99; variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[0]["kind"] = "acceptance"; variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[0]["after_gc"].pop(); variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[0]["before_gc"]["owned_allocations"] = 1; variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[0]["after_gc"][0]["counts"]["owned_handles"] = True; variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[0]["after_gc"][0]["counts"]["pid"] = 999; variants.append((r, o))
        r, o = copy.deepcopy((reports, observations)); o[-1]["before_gc"]["pid"] = 999; variants.append((r, o))
        variants.append((reports, observations[:-1]))
        for r, o in variants:
            with self.subTest(index=variants.index((r, o))), self.assertRaises(ValueError):
                probe.validate_observations(o, r)

    def test_package_roots_cannot_resolve_to_original_workspace(self):
        with tempfile.TemporaryDirectory() as folder:
            shadow = Path(folder).resolve()
            config = shadow / ".dart_tool/package_config.json"
            config.parent.mkdir()
            packages = [{"name": name, "rootUri": "../packages/" + name}
                        for name in ("connectanum_core", "connectanum_client", "connectanum_bench")]
            config.write_text(json.dumps({"packages": packages}))
            probe.verify_package_roots(shadow)
            packages[0]["rootUri"] = "file:///tmp/original-connectanum-core"
            config.write_text(json.dumps({"packages": packages}))
            with self.assertRaises(ValueError):
                probe.verify_package_roots(shadow)

    @unittest.skipUnless(os.name == "posix", "POSIX machine lease")
    def test_startup_failure_stops_real_owned_process_and_retains_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shadow, out = root / "source", root / "negative-control"
            for name in (probe.BUFFER, probe.TRANSPORT, probe.SESSION, probe.WORKER, probe.RUNNER,
                         "native/bench/bench_router.json"):
                path = shadow / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((probe.ROOT / name).read_bytes())
            for name in ("pubspec.lock", ".dart_tool/package_config.json"):
                path = shadow / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("{}")
            library = root / "library"
            library.write_bytes(b"fixture")
            children = []
            real_popen = subprocess.Popen
            def launch(*args, **kwargs):
                if args[0][0] != "dart":
                    return real_popen(*args, **kwargs)
                child = real_popen([sys.executable, "-u", "-c", "input()"], **kwargs)
                children.append(child)
                return child
            ready = probe.threading.Event()
            ready.wait = mock.Mock(return_value=False)
            real_event = probe.threading.Event
            events = [ready]
            def event():
                return events.pop() if events else real_event()
            with mock.patch.object(probe.subprocess, "Popen", side_effect=launch), \
                    mock.patch.object(probe.threading, "Event", side_effect=event):
                with self.assertRaisesRegex(RuntimeError, "did not become ready"):
                    probe.run_phase(root, shadow, out, library, "dart", "marker", True)
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0].returncode, 0)
            result = json.loads((out / "result.json").read_text())
            self.assertTrue(result["process_group_stopped"])
            self.assertTrue(result["reader_stopped"])
            self.assertTrue(result["inputs_unchanged"])
            self.assertEqual(result["reader_errors"], [])
            self.assertNotIn("negative_control_observed", result)

    @unittest.skipUnless(os.name == "posix", "POSIX machine lease")
    def test_resource_lease_respects_existing_holder_and_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            lock = base / "private/machine.lock"
            with probe.resource_lease(lock):
                with self.assertRaises(BlockingIOError):
                    with probe.resource_lease(lock):
                        self.fail("must not bypass existing owner")
            alias = base / "private/alias"
            alias.symlink_to(lock)
            with self.assertRaises(OSError):
                with probe.resource_lease(alias):
                    self.fail("must not follow a symlink lock")


if __name__ == "__main__":
    unittest.main()
