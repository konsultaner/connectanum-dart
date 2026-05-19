#!/usr/bin/env python3
"""Regression checks for Dart package publish dry-run release planning."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(
    args: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        env=env,
        check=check,
        capture_output=True,
        text=True,
    )


def write_file(root: Path, relative_path: str, content: str) -> None:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")


def install_fake_dart(root: Path) -> Path:
    fake_bin = root / "fake-bin"
    fake_bin.mkdir()
    dart = fake_bin / "dart"
    dart.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            set -euo pipefail

            if [[ "$1" == "pub" && "${2:-}" == "get" ]]; then
              printf 'Got dependencies!\\n'
              exit 0
            fi

            if [[ "$1" == "pub" && "${2:-}" == "publish" && "${3:-}" == "--dry-run" ]]; then
              printf 'Package has 0 warnings.\\n'
              exit 0
            fi

            printf 'Unexpected fake dart command:' >&2
            printf ' %q' "$@" >&2
            printf '\\n' >&2
            exit 64
            """
        ),
        encoding="utf-8",
    )
    dart.chmod(0o755)
    return fake_bin


def prepare_workspace(root: Path) -> dict[str, str]:
    (root / "bin").mkdir()
    shutil.copy2(ROOT / "bin/common.sh", root / "bin/common.sh")
    shutil.copy2(
        ROOT / "bin/dart-package-publish-dry-run",
        root / "bin/dart-package-publish-dry-run",
    )
    write_file(
        root,
        "pubspec.yaml",
        """
        name: package_release_plan_fixture
        publish_to: none
        environment:
          sdk: '^3.9.2'
        """,
    )
    write_file(
        root,
        "packages/connectanum_core/pubspec.yaml",
        """
        name: connectanum_core
        version: 0.1.0
        publish_to: none
        environment:
          sdk: '^3.9.2'
        """,
    )
    write_file(
        root,
        "packages/connectanum_client/pubspec.yaml",
        """
        name: connectanum_client
        version: 2.2.6
        environment:
          sdk: '^3.9.2'
        dependencies:
          connectanum_core:
            path: ../connectanum_core
        """,
    )

    env = os.environ.copy()
    env["PATH"] = f"{install_fake_dart(root)}{os.pathsep}{env['PATH']}"
    return env


class DartPackagePublishDryRunTest(unittest.TestCase):
    def test_release_plan_reports_private_dependency_without_failing_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            env = prepare_workspace(root)

            result = run(
                [
                    "bash",
                    "bin/dart-package-publish-dry-run",
                    "--show-release-plan",
                ],
                cwd=root,
                env=env,
            )

            self.assertIn(
                "Skipping private package connectanum_core "
                "(packages/connectanum_core): publish_to is none.",
                result.stdout,
            )
            self.assertIn(
                "Dart package publish dry-run completed for 1 package(s).",
                result.stdout,
            )
            self.assertIn(
                "All Dart package publish dry-runs reported zero warnings.",
                result.stdout,
            )
            self.assertIn(
                "connectanum_client depends on private workspace package "
                "connectanum_core (packages/connectanum_core); publish "
                "connectanum_core first or remove the hosted dependency before "
                "publishing connectanum_client.",
                result.stdout,
            )
            self.assertIn(
                "- connectanum_client 2.2.6 (packages/connectanum_client)",
                result.stdout,
            )
            self.assertIn(
                "- connectanum_core 0.1.0 (packages/connectanum_core)",
                result.stdout,
            )
            self.assertIn(
                "- connectanum_core -> connectanum_client",
                result.stdout,
            )

    def test_strict_release_ready_fails_on_private_workspace_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            env = prepare_workspace(root)

            result = run(
                [
                    "bash",
                    "bin/dart-package-publish-dry-run",
                    "--strict-release-ready",
                    "--show-release-plan",
                ],
                cwd=root,
                env=env,
                check=False,
            )

            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(
                "Dart package release-readiness blockers:",
                result.stdout,
            )
            self.assertIn(
                "- connectanum_core -> connectanum_client",
                result.stdout,
            )


if __name__ == "__main__":
    unittest.main()
