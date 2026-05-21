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


class DartPackagePublishDryRunTest(unittest.TestCase):
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
        self.assertEqual(result.stdout.count("## Publish dry-run:"), 1)
        self.assertIn(
            "## Publish dry-run: connectanum_client (packages/connectanum_client)",
            result.stdout,
        )
        self.assertNotIn("## Publish dry-run: connectanum_core", result.stdout)

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
