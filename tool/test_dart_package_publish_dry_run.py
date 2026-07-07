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
ROUTER_PUBSPEC = REPO_ROOT / "packages" / "connectanum_router" / "pubspec.yaml"
ROUTER_CHANGELOG = REPO_ROOT / "packages" / "connectanum_router" / "CHANGELOG.md"


class DartPackagePublishDryRunTest(unittest.TestCase):
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
        for package in (
            "connectanum_auth_server",
            "connectanum_bench",
            "connectanum_core",
            "connectanum_mcp",
            "connectanum_router",
        ):
            with self.subTest(package=package):
                self.assertRegex(
                    result.stdout,
                    rf"- {package} [^ ]+ \(packages/{package}\)",
                )

        self.assertRegex(
            result.stdout,
            r"Private workspace packages blocking publishable targets:\n"
            r"(?:- .+\n)*- connectanum_core [^ ]+ \(packages/connectanum_core\)",
        )
        self.assertIn("- connectanum_core -> connectanum_client", result.stdout)
        self.assertIn(
            "- Choose the package strategy: publish the modular dependency "
            "graph in order, keep the legacy public package name, or ship a "
            "compatibility wrapper.",
            result.stdout,
        )
        self.assertEqual(result.stdout.count("## Publish dry-run:"), 1)
        self.assertIn(
            "## Publish dry-run: connectanum_client (packages/connectanum_client)",
            result.stdout,
        )
        self.assertNotIn("## Publish dry-run: connectanum_core", result.stdout)

    def test_strict_release_ready_fails_on_known_private_dependency(self) -> None:
        result = self._run_with_fake_dart(
            "--strict-release-ready",
            "--show-release-plan",
            "connectanum_client",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Dart package release-readiness blockers:", result.stdout)
        self.assertIn(
            "- connectanum_client depends on private workspace package "
            "connectanum_core (packages/connectanum_core); publish "
            "connectanum_core first or remove the hosted dependency before "
            "publishing connectanum_client.",
            result.stdout,
        )
        self.assertIn(
            "All Dart package publish dry-runs reported zero warnings.",
            result.stdout,
        )
        self.assertIn(
            "Dart package release strategy decision required:",
            result.stdout,
        )
        self.assertIn(
            "- Current strict release-ready mode is intentionally blocked "
            "until an explicit pub.dev package strategy is selected.",
            result.stdout,
        )
        self.assertIn(
            "- Option: publish the modular package graph in dependency order, "
            "making private dependencies public before packages that depend on "
            "them.",
            result.stdout,
        )
        self.assertIn(
            "- Option: keep the legacy public connectanum package as the "
            "client-facing replacement package.",
            result.stdout,
        )
        self.assertIn(
            "- Option: ship a compatibility wrapper that maps the legacy "
            "package name onto the modular packages.",
            result.stdout,
        )
        self.assertIn(
            "- Do not remove publish_to: none or rewrite hosted dependencies "
            "outside an approved package-release slice.",
            result.stdout,
        )
        self.assertIn("Dart package release-order plan:", result.stdout)
        self.assertNotIn(
            "Default dry-run mode reports release-readiness blockers without "
            "failing.",
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


if __name__ == "__main__":
    unittest.main()
