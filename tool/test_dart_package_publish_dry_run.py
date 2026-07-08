#!/usr/bin/env python3
"""Regression checks for Dart package publish dry-run planning."""

from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PUBLISH_DRY_RUN = REPO_ROOT / "bin" / "dart-package-publish-dry-run"
PUBLISH_TAG_VALIDATOR = REPO_ROOT / "bin" / "validate-dart-package-publish-tag"
CORE_PUBSPEC = REPO_ROOT / "packages" / "connectanum_core" / "pubspec.yaml"
MCP_PUBSPEC = REPO_ROOT / "packages" / "connectanum_mcp" / "pubspec.yaml"
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
ROUTER_PUBSPEC = REPO_ROOT / "packages" / "connectanum_router" / "pubspec.yaml"
ROUTER_CHANGELOG = REPO_ROOT / "packages" / "connectanum_router" / "CHANGELOG.md"
PUBLISHABLE_PACKAGE_ORDER = (
    ("connectanum_core", "packages/connectanum_core"),
    ("connectanum_client", "packages/connectanum_client"),
    ("connectanum_mcp", "packages/connectanum_mcp"),
    ("connectanum_router", "packages/connectanum_router"),
    ("connectanum_auth_server", "packages/connectanum_auth_server"),
    ("connectanum_bench", "packages/connectanum_bench"),
)


class DartPackagePublishDryRunTest(unittest.TestCase):
    def test_modular_packages_are_publishable_archives(
        self,
    ) -> None:
        package_pubspecs = (
            CORE_PUBSPEC,
            MCP_PUBSPEC,
            ROUTER_PUBSPEC,
            AUTH_SERVER_PUBSPEC,
            BENCH_PUBSPEC,
        )

        for package_pubspec in package_pubspecs:
            with self.subTest(package=package_pubspec.parent.name):
                pubspec = package_pubspec.read_text(encoding="utf-8")
                self.assertIn(f"name: {package_pubspec.parent.name}", pubspec)
                self.assertNotRegex(
                    pubspec,
                    r"(?m)^\s*publish_to:\s*['\"]?none['\"]?\s*$",
                )

    def test_auth_server_package_archive_metadata_has_changelog(self) -> None:
        changelog = AUTH_SERVER_CHANGELOG.read_text(encoding="utf-8")

        self.assertIn("## 0.1.0", changelog)
        self.assertIn("remote-authentication service", changelog)

    def test_bench_package_archive_metadata_allows_known_test_fixtures(
        self,
    ) -> None:
        pubspec = BENCH_PUBSPEC.read_text(encoding="utf-8")
        changelog = BENCH_CHANGELOG.read_text(encoding="utf-8")

        self.assertIn("## 0.1.0", changelog)
        self.assertIn("benchmark package", changelog)
        self.assertIn("false_secrets:", pubspec)
        self.assertIn("  - /test/wamp_transport_targets_test.dart", pubspec)

    def test_router_package_archive_metadata_allows_known_test_fixtures(
        self,
    ) -> None:
        pubspec = ROUTER_PUBSPEC.read_text(encoding="utf-8")
        changelog = ROUTER_CHANGELOG.read_text(encoding="utf-8")

        self.assertIn("## 0.1.0", changelog)
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
            "connectanum_client-v2.2.6",
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
        self.assertIn("- connectanum_mcp -> connectanum_router", result.stdout)
        self.assertIn("- connectanum_router -> connectanum_auth_server", result.stdout)
        self.assertIn("- connectanum_auth_server -> connectanum_bench", result.stdout)
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
            "- All modular workspace packages are configured for publication; "
            "do not run a real dart pub publish without explicit operator "
            "approval.",
            result.stdout,
        )
        self.assertIn("Recommended publish order:", result.stdout)
        expected_order = (
            "1. connectanum_core 0.1.0 (packages/connectanum_core)",
            "2. connectanum_client 2.2.6 (packages/connectanum_client)",
            "3. connectanum_mcp 0.1.0 (packages/connectanum_mcp)",
            "4. connectanum_router 0.1.0 (packages/connectanum_router)",
            "5. connectanum_auth_server 0.1.0 "
            "(packages/connectanum_auth_server)",
            "6. connectanum_bench 0.1.0 (packages/connectanum_bench)",
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
        return (
            REPO_ROOT
            / ".github"
            / "workflows"
            / f"pub-dev-{package_name.replace('_', '-')}.yml"
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
