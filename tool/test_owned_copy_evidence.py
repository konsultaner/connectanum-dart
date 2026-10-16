"""Exercise the release checker with synthetic reports from the Dart producer."""
import copy
import json
import os
from pathlib import Path
import subprocess
import unittest

import wamp_serializer_compare as compare
import test_wamp_serializer_compare as fixtures


class OwnedCopyEvidenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run(
            ["dart", "run", "test/support/owned_copy_report_fixture.dart"],
            cwd=root / "packages/connectanum_bench",
            env={**os.environ, "CONNECTANUM_SKIP_NATIVE_BUILD": "1"},
            capture_output=True, text=True, timeout=120, check=True,
        )
        cls.fixtures = [json.loads(line) for line in result.stdout.splitlines()]
        if len(cls.fixtures) != 16:
            raise AssertionError("Dart producer must emit every provider/transport/TLS/workload combination")

    def report(self, fixture=None):
        base = fixtures.WampSerializerCompareTest()._report("synthetic", "flatbuffers", 1)
        fixture = copy.deepcopy(fixture or self.fixtures[-1])
        base["copy_metrics"].update(fixture.pop("copy_metrics"))
        base.update(fixture)
        return base

    def assertRejected(self, report, kind="e2ee"):
        self.assertTrue(compare._owned_pipeline_findings(report, kind, label="synthetic"))

    def test_all_dart_producer_combinations_pass_independent_checker(self):
        for fixture in self.fixtures:
            with self.subTest(fixture["name"]):
                report = self.report(fixture)
                self.assertEqual(compare._validate_evidence(report, label="synthetic"), [])

    def test_dart_volume_components_are_disjoint_and_independently_verified(self):
        for fixture in self.fixtures:
            with self.subTest(fixture['name']):
                report = self.report(fixture)
                volume = report['copy_metrics']['encoded_wamp_volume']
                native = report['client_impl'] == 'native'
                expected = {'client_dart': 0 if native else 31, 'router_dart': 0,
                            'client_native': 41 if native else 0, 'router_native': 71}
                self.assertEqual(volume['components'], expected)
                self.assertEqual(volume['accepted_bytes'], sum(expected.values()))
                self.assertEqual(compare._encoded_wamp_volume_findings(volume, 'synthetic'), [])
                copied = report['copy_metrics']['e2ee_copy_bytes']
                transcoded = report['copy_metrics']['transcode_copy_bytes']
                volume['components']['client_dart'] += 1
                self.assertTrue(compare._encoded_wamp_volume_findings(volume, 'synthetic'))
                self.assertTrue(compare._validate_evidence(report, label='synthetic'))
                self.assertEqual(report['copy_metrics']['e2ee_copy_bytes'], copied)
                self.assertEqual(report['copy_metrics']['transcode_copy_bytes'], transcoded)

    def test_every_byte_counter_and_metadata_requires_integer_observation(self):
        groups = (
            (("dart_owned_buffer_copy_breakdown", "client"), compare.OWNED_DART_COPY_FIELDS),
            (("native_codec_copy_breakdown", "client"), (*compare.NATIVE_CODEC_COPY_FIELDS, "coverage_version")),
            (("raw_frame_copy_breakdown", "client"), (*compare.RAW_FRAME_COPY_FIELDS, *compare.RAW_FRAME_REQUEST_FIELDS)),
            (("native_crypto_copy_breakdown",), compare.NATIVE_CRYPTO_COPY_FIELDS),
        )
        for path, fields in groups:
            for field in fields:
                for invalid in (None, True, 1.0, -1, "1"):
                    with self.subTest(path=path, field=field, invalid=invalid):
                        report = self.report()
                        component = report["copy_metrics"]
                        for key in path:
                            component = component[key]
                        component[field] = invalid
                        self.assertRejected(report)

    def test_old_missing_or_future_codec_coverage_cannot_certify_complete_total(self):
        for process in ("client", "router"):
            for version in (None, 0, 2):
                report = self.report()
                part = report["copy_metrics"]["native_codec_copy_breakdown"][process]
                if version is None:
                    del part["coverage_version"]
                else:
                    part["coverage_version"] = version
                self.assertRejected(report)

    def test_subtotals_are_recomputed_including_diagnostic_overlap(self):
        for name in ("e2ee", "transcode"):
            for field in ("known_copy_bytes", "vector_copy_bytes"):
                report = self.report()
                report["copy_metrics"]["native_codec_copy_breakdown"]["router"][field] += 1
                self.assertRejected(report, name)
            report = self.report()
            report["copy_metrics"][f"{name}_copy_bytes"] += 7
            self.assertRejected(report, name)
        report = self.report()
        report["copy_metrics"]["e2ee_copy_breakdown"]["components"]["ppt_diagnostic"] = 7
        self.assertRejected(report)

    def test_router_owner_and_failed_observations_are_required(self):
        for change in ("workers", "boss_generation", "failed_copy_operations", "unmeasured_copy_operations"):
            report = self.report()
            router = report["copy_metrics"]["dart_owned_buffer_copy_breakdown"]["router"]
            if change == "workers":
                router[change] = {}
            elif change == "boss_generation":
                router[change] = 0
            else:
                router["main_isolate"][change] = 1
            self.assertRejected(report)
            self.assertRejected(report, "transcode")

    def test_active_provider_and_dependency_labels_must_match(self):
        for fixture in self.fixtures:
            report = self.report(fixture)
            report["copy_metrics"]["native_crypto_copy_breakdown"]["active"] = report["client_impl"] != "native"
            self.assertRejected(report)
            for kind in ("e2ee", "transcode"):
                report = self.report(fixture)
                report["copy_metrics"][f"{kind}_copy_breakdown"]["unmeasured_dependency_boundaries"].pop()
                self.assertRejected(report, kind)

    def test_malformed_configurations_fail_closed(self):
        for field in ("wamp_configuration", "copy_metrics", "protocol", "client_impl"):
            report = self.report()
            report[field] = None
            self.assertRejected(report)


if __name__ == "__main__":
    unittest.main()
