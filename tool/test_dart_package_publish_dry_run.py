#!/usr/bin/env python3
"""Regression checks for Dart package publish dry-run planning."""

from __future__ import annotations

import json
import os
import statistics
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PUBLISH_DRY_RUN = REPO_ROOT / "bin" / "dart-package-publish-dry-run"
PUBLISH_TAG_VALIDATOR = REPO_ROOT / "bin" / "validate-dart-package-publish-tag"
AUTH_SERVER_CHANGELOG = (
    REPO_ROOT / "packages" / "connectanum_auth_server" / "CHANGELOG.md"
)
AUTH_SERVER_PUBSPEC = (
    REPO_ROOT / "packages" / "connectanum_auth_server" / "pubspec.yaml"
)
BENCH_PUBSPEC = REPO_ROOT / "packages" / "connectanum_bench" / "pubspec.yaml"
BENCH_CHANGELOG = (
    REPO_ROOT / "packages" / "connectanum_bench" / "CHANGELOG.md"
)
BENCH_README = REPO_ROOT / "packages" / "connectanum_bench" / "README.md"
MQTT_BENCHMARK_REPORT = (
    REPO_ROOT
    / "docs"
    / "benchmarks"
    / "mqtt-hosted-pr128-160fc2c2.json"
)
MQTT_BENCHMARK_REPEAT = (
    REPO_ROOT
    / "docs"
    / "benchmarks"
    / "mqtt-hosted-pr128-84b22de8.json"
)
WAMP_BENCHMARK_SUMMARY = (
    REPO_ROOT
    / "docs"
    / "benchmarks"
    / "wamp-four-serializer-2026-10-20"
    / "summary.json"
)
WAMP_FILE_BENCHMARK_SUMMARY = (
    REPO_ROOT
    / "docs"
    / "benchmarks"
    / "wamp-flatbuffers-file-segments-2026-10-20"
    / "summary.json"
)
ROUTER_PUBSPEC = REPO_ROOT / "packages" / "connectanum_router" / "pubspec.yaml"
ROUTER_CHANGELOG = REPO_ROOT / "packages" / "connectanum_router" / "CHANGELOG.md"
EXPECTED_PACKAGE_VERSION = "3.0.0-beta.8"
NATIVE_PACKAGE_MANIFESTS = (
    REPO_ROOT / "native" / "bench" / "Cargo.toml",
    REPO_ROOT / "native" / "transport" / "ct_core" / "Cargo.toml",
    REPO_ROOT / "native" / "transport" / "ct_ffi" / "Cargo.toml",
)
PUBLISHABLE_PACKAGE_ORDER = (
    ("connectanum_core", "packages/connectanum_core"),
    ("connectanum_client", "packages/connectanum_client"),
    ("connectanum_mcp", "packages/connectanum_mcp"),
    ("connectanum_router", "packages/connectanum_router"),
    ("connectanum", "packages/connectanum"),
    ("connectanum_auth_server", "packages/connectanum_auth_server"),
    ("connectanum_bench", "packages/connectanum_bench"),
)


class DartPackagePublishDryRunTest(unittest.TestCase):
    def test_publishable_workspace_packages_are_publishable_archives(
        self,
    ) -> None:
        for package_name, package_path in PUBLISHABLE_PACKAGE_ORDER:
            with self.subTest(package=package_name):
                pubspec_path = REPO_ROOT / package_path / "pubspec.yaml"
                pubspec = pubspec_path.read_text(encoding="utf-8")
                self.assertIn(f"name: {package_name}", pubspec)
                self.assertNotRegex(
                    pubspec,
                    r"(?m)^\s*publish_to:\s*['\"]?none['\"]?\s*$",
                )

    def test_publishable_packages_include_pub_score_assets(self) -> None:
        for package_name, package_path in PUBLISHABLE_PACKAGE_ORDER:
            with self.subTest(package=package_name):
                package_root = REPO_ROOT / package_path
                example_main = package_root / "example" / "main.dart"
                analysis_options = (
                    package_root / "analysis_options.yaml"
                ).read_text(encoding="utf-8")

                self.assertTrue(
                    example_main.is_file(),
                    "pub.dev scores the canonical example/main.dart entrypoint",
                )
                self.assertTrue((package_root / "README.md").is_file())
                self.assertTrue((package_root / "CHANGELOG.md").is_file())
                self.assertTrue((package_root / "LICENSE").is_file())
                self.assertIn("package:lints/recommended.yaml", analysis_options)
                self.assertIn("trailing_commas: preserve", analysis_options)

    def test_mqtt_comparison_table_matches_same_runner_samples(self) -> None:
        report = json.loads((REPO_ROOT / "docs/benchmarks/mqtt-native-comparison-1660422d.json").read_text())
        readme = BENCH_README.read_text()
        legs = report["legs"]
        self.assertEqual([leg["name"] for leg in legs],
                         ["baseline-1", "candidate-1", "baseline-2", "candidate-2"])
        rows = [row for leg in legs for profile in leg["profiles"] for row in profile["rawRows"]]
        self.assertEqual(report["totalRawRows"], len(rows))
        self.assertEqual(report["totalExactDeliveries"], sum(row["received"] for row in rows))
        self.assertTrue(all(row["received"] == row["sent"] * row["subscribers"] and row["duplicates"] == 0 for row in rows))
        for name, label in [("ws_sustained", "WS MQTT 5"),
                            ("ws_v311_sustained", "WS MQTT 3.1.1"),
                            ("64k_sustained", "TCP 64 KiB")]:
            summaries = [next(profile["summary"] for profile in leg["profiles"] if profile["name"] == name) for leg in legs]
            self.assertTrue(all(summary["budgets"] == summaries[0]["budgets"] for summary in summaries))
            self.assertTrue(all("EPYC 9V45" in summary["provenance"]["cpu_model"] for summary in summaries))
            self.assertNotEqual(summaries[0]["provenance"]["native_lib_sha256"], summaries[1]["provenance"]["native_lib_sha256"])
            for metric, field, fmt in [
                ("Deliveries/s", "connectanum_delivered_per_sec_median", ",.0f"),
                ("Broker CPU seconds", "connectanum_broker_cpu_seconds_median", ".2f"),
            ]:
                values = " | ".join(format(summary[field], fmt) for summary in summaries)
                self.assertIn(f"| {label} | {metric} | {values} |", readme)

    def test_direct_body_comparison_table_matches_interleaved_raw_samples(self) -> None:
        report = json.loads((REPO_ROOT / "docs/benchmarks/mqtt-direct-body-local-comparison.json").read_text())
        readme = BENCH_README.read_text()
        self.assertTrue(report["diagnosticOnly"])
        total = 0
        for profile in report["profiles"]:
            rows = profile["rows"]
            self.assertEqual(len(rows), 15)
            self.assertTrue(all(row["received"] == row["sent"] and row["duplicates"] == 0 for row in rows))
            total += sum(row["received"] for row in rows)
            values = []
            for variant, summary in [("before", profile["before"]), ("direct", profile["candidate"])]:
                raw = [row for row in rows if row["variant"] == variant]
                self.assertEqual([row["run"] for row in raw], [1, 2, 3, 4, 5])
                self.assertEqual(summary["provenance"]["client_exe_sha256"], report["clientSha256"])
                self.assertEqual(summary["provenance"]["native_lib_sha256"], report["nativeLibrarySha256"])
                metrics = [statistics.median(row["throughput_delivered_per_sec"] for row in raw),
                           statistics.median(row["broker_cpu_seconds"] for row in raw),
                           max(row["broker_rss_bytes"] for row in raw)]
                self.assertEqual(metrics, [summary["connectanum_delivered_per_sec_median"],
                                           summary["connectanum_broker_cpu_seconds_median"],
                                           summary["connectanum_broker_rss_bytes_max"]])
                values.append(metrics)
            label = {"64k_sustained": "TCP 64 KiB", "ws_sustained": "WS MQTT 5",
                     "ws_v311_sustained": "WS MQTT 3.1.1"}[profile["id"]]
            count = profile["candidate"]["budgets"]["messages_per_run"]
            a, b = values
            self.assertIn(f"| {label} | {count:,} | {a[0]:,.0f} → {b[0]:,.0f} | "
                          f"{a[1]:.2f} → {b[1]:.2f} | {a[2]/1048576:.1f} → {b[2]/1048576:.1f} |", readme)
        self.assertEqual(report["totalExactDeliveries"], total)

    def test_worker_comparison_table_uses_identical_binaries_and_exact_raw_samples(self) -> None:
        report = json.loads((REPO_ROOT / "docs/benchmarks/mqtt-runtime-workers-local-comparison.json").read_text())
        self.assertTrue(report["diagnosticOnly"])
        self.assertEqual(report["workerPolicies"], {"before": "automatic", "direct": "1"})
        self.assertEqual({profile["id"] for profile in report["profiles"]},
                         {"ws_sustained", "ws_v311_sustained"})
        readme = BENCH_README.read_text()
        total = 0
        for profile in report["profiles"]:
            a, b = profile["automatic"], profile["oneWorker"]
            for field in ("broker_exe_sha256", "client_exe_sha256", "native_lib_sha256"):
                self.assertEqual(a["provenance"][field], b["provenance"][field])
            rows = profile["rows"]
            self.assertEqual(len(rows), 15)
            self.assertTrue(all(row["received"] == row["sent"] and row["duplicates"] == 0 for row in rows))
            total += sum(row["received"] for row in rows)
            metrics = []
            for variant in ("before", "direct"):
                raw = [row for row in rows if row["variant"] == variant]
                self.assertEqual([row["run"] for row in raw], [1, 2, 3, 4, 5])
                metrics.append([statistics.median(row["throughput_delivered_per_sec"] for row in raw),
                                statistics.median(row["broker_cpu_seconds"] for row in raw),
                                max(row["broker_rss_bytes"] for row in raw)])
            label = "WS MQTT 5" if profile["id"] == "ws_sustained" else "WS MQTT 3.1.1"
            a, b = metrics
            self.assertIn(f"| {label} | {a[0]:,.0f} → {b[0]:,.0f} | "
                          f"{a[1]:.2f} → {b[1]:.2f} | {a[2]/1048576:.1f} → {b[2]/1048576:.1f} |", readme)
        self.assertEqual(report["totalExactDeliveries"], total)

    def test_bench_readme_publishes_current_result_snapshot(self) -> None:
        readme = BENCH_README.read_text(encoding="utf-8")
        mqtt_report = json.loads(MQTT_BENCHMARK_REPORT.read_text(encoding="utf-8"))
        mqtt_table = readme.split("## MQTT publish and subscribe", 1)[1].split(
            "## WAMP throughput", 1
        )[0]
        profile_rows = [
            line
            for line in mqtt_table.splitlines()
            if line.startswith(("| Dart |", "| Native |"))
        ]

        self.assertEqual(len(profile_rows), len(mqtt_report["profiles"]))
        self.assertEqual(sum("Delivery pass" in row for row in profile_rows), 4)
        self.assertEqual(
            sum("**Fail**" in row for row in profile_rows),
            sum(not profile["summary"]["passed"] for profile in mqtt_report["profiles"]),
        )
        ordered_profiles = [
            "burst", "sustained", "v311-sustained", "batched", "fanout",
            "native-burst", "native-sustained", "native-v311-sustained",
            "native-1k-sustained", "native-64k-sustained", "native-batched",
            "native-fanout", "native-tls-sustained",
            "native-tls-v311-sustained", "native-ws-sustained",
            "native-ws-v311-sustained", "native-wss-single-smoke",
            "native-wss-sustained", "native-wss-v311-single-smoke",
            "native-wss-v311-sustained",
        ]
        summaries = {
            profile["name"]: profile["summary"]
            for profile in mqtt_report["profiles"]
        }
        self.assertEqual(set(ordered_profiles), set(summaries))
        for row, profile_name in zip(profile_rows, ordered_profiles, strict=True):
            cells = [cell.strip() for cell in row.strip("|").split("|")]
            summary = summaries[profile_name]
            self.assertEqual(
                cells[3],
                f'{summary["connectanum_delivered_per_sec_median"]:,.0f} / '
                f'{summary["mosquitto_delivered_per_sec_median"]:,.0f}',
            )
            self.assertEqual(cells[4], f'{summary["throughput_ratio"]:.3f}')
            self.assertEqual(
                cells[5],
                f'{summary["p95_ratio"]:.3f} / '
                f'{summary["p99_ratio"]:.3f}',
            )
            self.assertEqual(cells[6], f'{summary["broker_cpu_ratio"]:.3f}')
            self.assertEqual(
                cells[7],
                f'{summary["connectanum_broker_rss_bytes_max"] / 1048576:.1f} MiB',
            )
            self.assertEqual(
                cells[8],
                "Delivery pass" if summary["gate"] == "correctness"
                else ("Pass" if summary["passed"] else "**Fail**"),
            )
        self.assertIn("mqtt-hosted-pr128-9aa6b17d.json", mqtt_table)
        self.assertIn("mqtt-hosted-pr128-2dea8b8e.json", mqtt_table)
        latest_row = next(
            row for row in mqtt_table.splitlines()
            if row.startswith("| [Latest `160fc2c2`]")
        )
        latest_cells = [cell.strip() for cell in latest_row.strip("|").split("|")]
        self.assertIn("EPYC 7763", latest_cells[0])
        self.assertEqual(
            latest_cells[1:],
            [
                f'{summaries["native-ws-sustained"]["throughput_ratio"]:.3f}',
                f'{summaries["native-ws-v311-sustained"]["throughput_ratio"]:.3f}',
                f'{summaries["native-v311-sustained"]["throughput_ratio"]:.3f}',
                f'{summaries["native-64k-sustained"]["broker_cpu_ratio"]:.3f}',
                "**Fail (WS rate)**",
            ],
        )
        repeat = json.loads(MQTT_BENCHMARK_REPEAT.read_text(encoding="utf-8"))
        self.assertIn("mqtt-hosted-pr128-84b22de8.json", mqtt_table)
        self.assertEqual(
            repeat["totalRawRows"],
            sum(len(profile["rawRows"]) for profile in repeat["profiles"]),
        )
        self.assertEqual(
            repeat["totalExactDeliveries"],
            sum(
                row["received"]
                for profile in repeat["profiles"]
                for row in profile["rawRows"]
            ),
        )
        self.assertTrue(all(profile["summary"]["passed"] for profile in repeat["profiles"]))
        repeat_summaries = {
            profile["name"]: profile["summary"] for profile in repeat["profiles"]
        }
        comparison_row = next(
            row for row in mqtt_table.splitlines()
            if row.startswith("| [Same-code repeat `84b22de8`]")
        )
        comparison_cells = [
            cell.strip() for cell in comparison_row.strip("|").split("|")
        ]
        self.assertIn(
            "EPYC 9V74",
            repeat_summaries["native-64k-sustained"]["provenance"]["cpu_model"],
        )
        self.assertIn("EPYC 9V74", comparison_cells[0])
        self.assertEqual(
            comparison_cells[1:],
            [
                f'{repeat_summaries["native-ws-sustained"]["throughput_ratio"]:.3f}',
                f'{repeat_summaries["native-ws-v311-sustained"]["throughput_ratio"]:.3f}',
                f'{repeat_summaries["native-v311-sustained"]["throughput_ratio"]:.3f}',
                f'{repeat_summaries["native-64k-sustained"]["broker_cpu_ratio"]:.3f}',
                "Pass",
            ],
        )
        self.assertIn("mqtt-hosted-amd-fccc7566.json", mqtt_table)
        self.assertIn("Intel Xeon 6973P-C | — | — | — | 5.000 | Fail", mqtt_table)
        self.assertIn("| Required limit | ≥0.700 | ≥0.700 | ≥0.750 | ≤4.000 | — |", mqtt_table)
        self.assertIn(
            f'{mqtt_report["totalExactDeliveries"]:,} expected and received',
            mqtt_table,
        )
        self.assertIn("No benchmark yet; the live gateway is pending", mqtt_table)
        self.assertIn("sustained / full-lifecycle throughput", readme)
        wamp_tables = readme.split("## WAMP throughput", 1)[1].split(
            "## Run and reproduce", 1
        )[0]
        wamp_table_lines = [
            line
            for line in wamp_tables.splitlines()
            if line.startswith("|")
        ]
        self.assertEqual(len(wamp_table_lines), 32)
        self.assertTrue(all(line.count("|") == 6 for line in wamp_table_lines))
        table_headers = [
            line for line in wamp_table_lines if line.startswith("| Transport and ")
        ]
        self.assertEqual(len(table_headers), 3)
        self.assertTrue(
            all(
                header
                == (
                    f"| Transport and {kind} | JSON (Gbit/s) | "
                    "MessagePack (Gbit/s) | CBOR (Gbit/s) | "
                    "FlatBuffers (Gbit/s) |"
                )
                for header, kind in zip(
                    table_headers, ("path", "path", "workload"), strict=True
                )
            )
        )
        wamp_rows = [
            line
            for line in wamp_table_lines
            if line not in table_headers and not line.startswith("| ---")
        ]
        self.assertEqual(len(wamp_rows), 26)
        summary = json.loads(WAMP_BENCHMARK_SUMMARY.read_text(encoding="utf-8"))
        file_summary = json.loads(
            WAMP_FILE_BENCHMARK_SUMMARY.read_text(encoding="utf-8")
        )["workloads"]
        benchmark_groups = [
            group
            for scenario in (
                "wamp_file_transfer_throughput",
                "wamp_large_transport_frames_heavy",
                "wamp_websocket_fragmentation_throughput",
            )
            for group in summary[scenario]
        ]
        self.assertEqual(len(benchmark_groups), len(wamp_rows))
        self.assertEqual(len(file_summary), 40)
        for group_index, (row, group) in enumerate(
            zip(wamp_rows, benchmark_groups, strict=True)
        ):
            actual_cells = [cell.strip() for cell in row.split("|")[2:6]]
            workloads = [
                (
                    file_summary[group["workloads"][serializer]["name"]]
                    if group_index < 10
                    else group["workloads"][serializer]
                )
                for serializer in ("json", "msgpack", "cbor", "flatbuffers")
            ]
            expected_cells = [
                (
                    f"{workload['median_data_gbit_s']:.3f} / "
                    f"{workload['median_lifecycle_gbit_s']:.3f}"
                )
                for workload in workloads
            ]
            self.assertEqual(actual_cells, expected_cells)
            self.assertTrue(
                all(len(workload["runs"]) == 3 for workload in workloads)
            )
        self.assertIn("wamp-four-serializer-2026-10-20/README.md", wamp_tables)
        self.assertIn("wamp-flatbuffers-file-segments-2026-10-20/README.md", wamp_tables)
        self.assertIn("RawSocket frames are 60 MiB", wamp_tables)
        self.assertIn("### 64 MiB file transfer", readme)
        self.assertIn("### Large RPC frames", readme)
        self.assertIn("### WebSocket fragmentation and Pub/Sub", readme)
        self.assertIn("benchmark contract", readme)

    def test_native_hook_packages_use_stable_hook_apis(self) -> None:
        for package_name in ("connectanum_client", "connectanum_router"):
            with self.subTest(package=package_name):
                pubspec = (
                    REPO_ROOT / "packages" / package_name / "pubspec.yaml"
                ).read_text(encoding="utf-8")

                self.assertIn("hooks: ^2.2.0", pubspec)
                self.assertIn("code_assets: ^2.0.0", pubspec)
                self.assertIn("sdk: '^3.10.0'", pubspec)

    def test_versioned_workspace_packages_share_release_version(self) -> None:
        for package_name, package_path in PUBLISHABLE_PACKAGE_ORDER:
            with self.subTest(package=package_name):
                version = self._pubspec_value(
                    REPO_ROOT / package_path / "pubspec.yaml",
                    "version",
                )
                self.assertEqual(version, EXPECTED_PACKAGE_VERSION)

        for manifest in NATIVE_PACKAGE_MANIFESTS:
            with self.subTest(package=manifest.parent.name):
                self.assertIn(
                    f'version = "{EXPECTED_PACKAGE_VERSION}"',
                    manifest.read_text(encoding="utf-8"),
                )

    def test_workspace_dependency_constraints_use_release_version(self) -> None:
        expected_dependencies = {
            "connectanum": ("connectanum_client",),
            "connectanum_auth_server": (
                "connectanum_router",
                "connectanum_core",
            ),
            "connectanum_bench": (
                "connectanum_router",
                "connectanum_core",
                "connectanum_client",
                "connectanum_auth_server",
            ),
            "connectanum_client": ("connectanum_core",),
            "connectanum_mcp": ("connectanum_client", "connectanum_core"),
            "connectanum_router": (
                "connectanum_core",
                "connectanum_client",
                "connectanum_mcp",
            ),
        }
        package_paths = dict(PUBLISHABLE_PACKAGE_ORDER)

        for package_name, dependencies in expected_dependencies.items():
            pubspec = (
                REPO_ROOT / package_paths[package_name] / "pubspec.yaml"
            ).read_text(encoding="utf-8")
            for dependency in dependencies:
                with self.subTest(package=package_name, dependency=dependency):
                    self.assertIn(
                        f"  {dependency}: ^{EXPECTED_PACKAGE_VERSION}",
                        pubspec,
                    )

    def test_auth_server_package_archive_metadata_has_changelog(self) -> None:
        changelog = AUTH_SERVER_CHANGELOG.read_text(encoding="utf-8")

        self.assertIn(f"## {EXPECTED_PACKAGE_VERSION}", changelog)
        self.assertIn("remote-authentication service", changelog)

    def test_bench_package_archive_metadata_allows_known_test_fixtures(
        self,
    ) -> None:
        pubspec = BENCH_PUBSPEC.read_text(encoding="utf-8")
        changelog = BENCH_CHANGELOG.read_text(encoding="utf-8")

        self.assertIn(f"## {EXPECTED_PACKAGE_VERSION}", changelog)
        self.assertIn("benchmark package", changelog)
        self.assertIn("false_secrets:", pubspec)
        self.assertIn("  - /test/wamp_transport_targets_test.dart", pubspec)

    def test_router_package_archive_metadata_allows_known_test_fixtures(
        self,
    ) -> None:
        pubspec = ROUTER_PUBSPEC.read_text(encoding="utf-8")
        changelog = ROUTER_CHANGELOG.read_text(encoding="utf-8")

        self.assertIn(f"## {EXPECTED_PACKAGE_VERSION}", changelog)
        self.assertIn("router-hosted MCP", changelog)
        self.assertIn("false_secrets:", pubspec)
        for fixture in (
            "/test/certs/http3_key.pem",
            "/test/certs/remote_auth_client_key.pem",
            "/test/certs/remote_auth_server_key.pem",
            "/test/router_json_test.dart",
            "/test/router_runtime_test.dart",
        ):
            with self.subTest(fixture=fixture):
                self.assertIn(f"  - {fixture}", pubspec)

    def test_hosted_publish_workflow_prints_release_plan(self) -> None:
        workflow = (
            REPO_ROOT / ".github" / "workflows" / "dart-package-publish.yml"
        )
        workflow_text = workflow.read_text(encoding="utf-8")

        self.assertRegex(
            workflow_text,
            r"name: Validate strict Dart package release readiness\n"
            r"\s+run: bin/dart-package-publish-dry-run "
            r"--strict-release-ready --show-release-plan",
        )
        for tracked_path in (
            ".github/workflows/pub-dev-*.yml",
            "bin/validate-dart-package-publish-tag",
        ):
            with self.subTest(tracked_path=tracked_path):
                self.assertIn(f"      - '{tracked_path}'", workflow_text)

    def test_pub_dev_publish_workflows_are_isolated_per_package(self) -> None:
        for package_name, package_path in PUBLISHABLE_PACKAGE_ORDER:
            workflow = self._publish_workflow_path(package_name)
            workflow_text = workflow.read_text(encoding="utf-8")

            with self.subTest(package=package_name):
                self.assertIn(
                    f"name: Publish {package_name} to pub.dev",
                    workflow_text,
                )
                self.assertIn(
                    "on:\n"
                    "  push:\n"
                    "    tags:\n"
                    f"      - '{package_name}-v*'",
                    workflow_text,
                )
                self.assertIn("permissions:\n  contents: read", workflow_text)
                self.assertNotIn("workflow_dispatch", workflow_text)
                self.assertIn(
                    "bin/validate-dart-package-publish-tag \\\n"
                    f"            {package_name} \\\n"
                    f"            {package_path}",
                    workflow_text,
                )
                self.assertIn(
                    "bin/dart-package-publish-dry-run \\\n"
                    "            --strict-release-ready \\\n"
                    "            --show-release-plan \\\n"
                    f"            {package_name}",
                    workflow_text,
                )
                self.assertIn("needs: validate", workflow_text)
                self.assertIn("id-token: write", workflow_text)
                self.assertIn(
                    "uses: dart-lang/setup-dart/.github/workflows/"
                    "publish.yml@v1",
                    workflow_text,
                )
                self.assertIn(
                    f"working-directory: {package_path}",
                    workflow_text,
                )
                self.assertIn("environment: pub.dev", workflow_text)

    def test_pub_dev_publish_workflow_files_follow_release_order(self) -> None:
        workflow_names = [
            self._publish_workflow_path(package_name).name
            for package_name, _ in PUBLISHABLE_PACKAGE_ORDER
        ]

        self.assertEqual(
            workflow_names,
            [
                "pub-dev-connectanum-core.yml",
                "pub-dev-connectanum-client.yml",
                "pub-dev-connectanum-mcp.yml",
                "pub-dev-connectanum-router.yml",
                "pub-dev-connectanum-compat.yml",
                "pub-dev-connectanum-auth-server.yml",
                "pub-dev-connectanum-bench.yml",
            ],
        )

    def test_publish_tag_validator_accepts_current_package_versions(self) -> None:
        for package_name, package_path in PUBLISHABLE_PACKAGE_ORDER:
            version = self._pubspec_value(
                REPO_ROOT / package_path / "pubspec.yaml",
                "version",
            )
            tag = f"{package_name}-v{version}"

            with self.subTest(package=package_name):
                result = self._run_tag_validator(package_name, package_path, tag)

                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn(
                    f"Validated pub.dev publish tag {tag} for {package_name}",
                    result.stdout,
                )

    def test_publish_tag_validator_rejects_wrong_package_prefix(self) -> None:
        result = self._run_tag_validator(
            "connectanum_core",
            "packages/connectanum_core",
            "connectanum_client-v3.0.0-beta.8",
        )

        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn(
            "does not match expected prefix connectanum_core-v",
            result.stdout,
        )

    def test_publish_tag_validator_rejects_version_mismatch(self) -> None:
        result = self._run_tag_validator(
            "connectanum_core",
            "packages/connectanum_core",
            "connectanum_core-v999.0.0",
        )

        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn(
            "Tag version 999.0.0 does not match "
            "packages/connectanum_core/pubspec.yaml version",
            result.stdout,
        )

    def test_scoped_release_plan_still_inventories_workspace_packages(
        self,
    ) -> None:
        result = self._run_with_fake_dart(
            "--show-release-plan",
            "connectanum_client",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Dart package release-order plan:", result.stdout)
        self.assertRegex(
            result.stdout,
            r"- connectanum_client [^ ]+ \(packages/connectanum_client\)",
        )
        self.assertRegex(
            result.stdout,
            r"- connectanum_core [^ ]+ \(packages/connectanum_core\)",
        )
        self.assertRegex(
            result.stdout,
            r"- connectanum_bench [^ ]+ \(packages/connectanum_bench\)",
        )
        self.assertRegex(
            result.stdout,
            r"- connectanum [^ ]+ \(packages/connectanum\)",
        )
        self.assertIn(
            "Private workspace packages not currently publishable: none.",
            result.stdout,
        )
        self.assertRegex(
            result.stdout,
            r"- connectanum_mcp [^ ]+ \(packages/connectanum_mcp\)",
        )
        self.assertRegex(
            result.stdout,
            r"- connectanum_router [^ ]+ \(packages/connectanum_router\)",
        )

        self.assertIn(
            "Private workspace packages blocking publishable targets: none.",
            result.stdout,
        )
        self.assertIn("- connectanum_core -> connectanum_client", result.stdout)
        self.assertIn("- connectanum_core -> connectanum_mcp", result.stdout)
        self.assertIn("- connectanum_client -> connectanum_mcp", result.stdout)
        self.assertIn("- connectanum_core -> connectanum_objectbox_adapter", result.stdout)
        self.assertIn("- connectanum_client -> connectanum_objectbox_adapter", result.stdout)
        self.assertIn("- connectanum_mcp -> connectanum_router", result.stdout)
        self.assertIn("- connectanum_router -> connectanum_auth_server", result.stdout)
        self.assertIn("- connectanum_auth_server -> connectanum_bench", result.stdout)
        self.assertIn("- connectanum_client -> connectanum", result.stdout)
        self.assertIn(
            "Approved package release strategy:",
            result.stdout,
        )
        self.assertIn(
            "- Publish the modular package graph in dependency order.",
            result.stdout,
        )
        self.assertIn(
            "- Keep the legacy public connectanum package as the "
            "client-facing compatibility wrapper/facade.",
            result.stdout,
        )
        self.assertIn(
            "- All workspace package archives are configured for publication; "
            "do not run a real dart pub publish without explicit operator "
            "approval.",
            result.stdout,
        )
        self.assertIn("Recommended publish order:", result.stdout)
        expected_order = (
            f"1. connectanum_core {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_core)",
            f"2. connectanum_client {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_client)",
            f"3. connectanum_mcp {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_mcp)",
            f"4. connectanum_objectbox_adapter {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_objectbox_adapter)",
            f"5. connectanum_router {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_router)",
            f"6. connectanum {EXPECTED_PACKAGE_VERSION} (packages/connectanum)",
            f"7. connectanum_auth_server {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_auth_server)",
            f"8. connectanum_bench {EXPECTED_PACKAGE_VERSION} "
            "(packages/connectanum_bench)",
        )
        previous_index = -1
        for publish_order_line in expected_order:
            with self.subTest(publish_order_line=publish_order_line):
                current_index = result.stdout.index(publish_order_line)
                self.assertGreater(current_index, previous_index)
                previous_index = current_index
        self.assertEqual(result.stdout.count("## Publish dry-run:"), 1)
        self.assertIn(
            "## Publish dry-run: connectanum_client (packages/connectanum_client)",
            result.stdout,
        )
        self.assertNotIn("## Publish dry-run: connectanum_core", result.stdout)

    def test_strict_release_ready_succeeds_for_current_publishable_slice(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum_client",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "No private workspace dependency blockers found for publishable "
            "packages.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        self.assertIn(
            "Private workspace packages blocking publishable targets: none.",
            result.stdout,
        )
        self.assertIn(
            "- connectanum_core -> connectanum_client",
            result.stdout,
        )
        self.assertIn(
            "Approved package release strategy:",
            result.stdout,
        )
        self.assertIn("Dart package release-order plan:", result.stdout)
        self.assertNotIn(
            "Default dry-run mode reports release-readiness blockers without "
            "failing.",
            result.stdout,
        )

    def test_strict_release_ready_succeeds_for_compatibility_slice(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "## Publish dry-run: connectanum (packages/connectanum)",
            result.stdout,
        )
        self.assertNotIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "No private workspace dependency blockers found for publishable "
            "packages.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        self.assertIn(
            "- connectanum_client -> connectanum",
            result.stdout,
        )

    def test_strict_release_ready_succeeds_for_mcp_slice(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum_mcp",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "## Publish dry-run: connectanum_mcp (packages/connectanum_mcp)",
            result.stdout,
        )
        self.assertNotIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "No private workspace dependency blockers found for publishable "
            "packages.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        self.assertIn(
            "Validated Dart package executable entrypoints:",
            result.stdout,
        )
        self.assertIn(
            "- connectanum_mcp (packages/connectanum_mcp): "
            "router_hosted_client -> bin/router_hosted_client.dart",
            result.stdout,
        )
        self.assertIn(
            "- connectanum_client -> connectanum_mcp",
            result.stdout,
        )
        self.assertIn(
            "- connectanum_core -> connectanum_mcp",
            result.stdout,
        )

    def test_strict_release_ready_succeeds_for_router_slice(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum_router",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "## Publish dry-run: connectanum_router (packages/connectanum_router)",
            result.stdout,
        )
        self.assertNotIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "No private workspace dependency blockers found for publishable "
            "packages.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        for edge in (
            "- connectanum_client -> connectanum_router",
            "- connectanum_core -> connectanum_router",
            "- connectanum_mcp -> connectanum_router",
        ):
            with self.subTest(edge=edge):
                self.assertIn(edge, result.stdout)

    def test_strict_release_ready_succeeds_for_auth_server_slice(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum_auth_server",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "## Publish dry-run: connectanum_auth_server "
            "(packages/connectanum_auth_server)",
            result.stdout,
        )
        self.assertNotIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "No private workspace dependency blockers found for publishable "
            "packages.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        for edge in (
            "- connectanum_core -> connectanum_auth_server",
            "- connectanum_router -> connectanum_auth_server",
        ):
            with self.subTest(edge=edge):
                self.assertIn(edge, result.stdout)

    def test_strict_release_ready_succeeds_for_bench_slice(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum_bench",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "## Publish dry-run: connectanum_bench "
            "(packages/connectanum_bench)",
            result.stdout,
        )
        self.assertNotIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "No private workspace dependency blockers found for publishable "
            "packages.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        for edge in (
            "- connectanum_auth_server -> connectanum_bench",
            "- connectanum_client -> connectanum_bench",
            "- connectanum_core -> connectanum_bench",
            "- connectanum_router -> connectanum_bench",
        ):
            with self.subTest(edge=edge):
                self.assertIn(edge, result.stdout)

    def test_missing_declared_executable_fails_archive_shape_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            package_root = Path(temp_dir) / "missing_executable_package"
            package_root.mkdir()
            (package_root / "pubspec.yaml").write_text(
                textwrap.dedent(
                    """\
                    name: missing_executable_package
                    version: 0.1.0
                    environment:
                      sdk: '^3.9.2'
                    executables:
                      missing_tool:
                    """
                ),
                encoding="utf-8",
            )

            result = self._run_with_fake_dart(str(package_root))

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Dart package archive shape gate failed:", result.stdout)
        self.assertIn(
            "missing_executable_package",
            result.stdout,
        )
        self.assertIn(
            "missing_tool declares missing bin/missing_tool.dart.",
            result.stdout,
        )

    def _run_with_fake_dart(self, *args: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            fake_bin = Path(temp_dir)
            dart = fake_bin / "dart"
            dart.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    set -euo pipefail

                    if [[ "$1" == "pub" && "$2" == "get" ]]; then
                      printf 'Fake dart pub get.\\n'
                      exit 0
                    fi

                    if [[ "$1" == "pub" && "$2" == "publish" && "$3" == "--dry-run" ]]; then
                      printf 'Package has 0 warnings.\\n'
                      exit 0
                    fi

                    printf 'Unexpected fake dart invocation: %s\\n' "$*" >&2
                    exit 64
                    """
                ),
                encoding="utf-8",
            )
            dart.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
            return subprocess.run(
                [str(PUBLISH_DRY_RUN), *args],
                cwd=REPO_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

    def _run_tag_validator(
        self,
        package_name: str,
        package_path: str,
        tag: str,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(PUBLISH_TAG_VALIDATOR), package_name, package_path, tag],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

    def _publish_workflow_path(self, package_name: str) -> Path:
        workflow_name = (
            "connectanum-compat"
            if package_name == "connectanum"
            else package_name.replace("_", "-")
        )
        return (
            REPO_ROOT
            / ".github"
            / "workflows"
            / f"pub-dev-{workflow_name}.yml"
        )

    def _pubspec_value(self, pubspec: Path, key: str) -> str:
        prefix = f"{key}:"
        for line in pubspec.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith(prefix):
                value = stripped[len(prefix) :].split("#", maxsplit=1)[0]
                return value.strip().strip("\"'")
        self.fail(f"{pubspec} does not declare {key}")


if __name__ == "__main__":
    unittest.main()
