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


class DartPackagePublishDryRunTest(unittest.TestCase):
    def test_core_mcp_router_and_auth_server_are_publishable_modular_archives(
        self,
    ) -> None:
        package_pubspecs = (
            CORE_PUBSPEC,
            MCP_PUBSPEC,
            ROUTER_PUBSPEC,
            AUTH_SERVER_PUBSPEC,
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

        self.assertRegex(
            workflow.read_text(encoding="utf-8"),
            r"name: Validate publishable Dart packages\n"
            r"\s+run: bin/dart-package-publish-dry-run --show-release-plan",
        )

    def test_scoped_release_plan_still_inventories_private_workspace_packages(
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
        for package in ("connectanum_bench",):
            with self.subTest(package=package):
                self.assertRegex(
                    result.stdout,
                    rf"- {package} [^ ]+ \(packages/{package}\)",
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


if __name__ == "__main__":
    unittest.main()
