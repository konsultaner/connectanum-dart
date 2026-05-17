#!/usr/bin/env python3
"""Regression checks for deployment-chain audit sensitivity grouping."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(
    args: list[str],
    *,
    cwd: Path,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        capture_output=capture_output,
        text=True,
    )


def write_file(root: Path, relative_path: str, content: str = "test\n") -> None:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def commit_all(root: Path, message: str) -> None:
    run(["git", "add", "."], cwd=root)
    run(
        [
            "git",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-q",
            "-m",
            message,
        ],
        cwd=root,
    )


def parse_sections(output: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current: str | None = None

    for line in output.splitlines():
        if line.startswith("## "):
            current = line[3:]
            sections[current] = []
        elif current is not None and line.startswith("- "):
            sections[current].append(line[2:])

    return sections


class DeploymentAuditSensitivityTest(unittest.TestCase):
    def test_local_diagnostic_groups_runtime_inputs_without_github_api(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "bin").mkdir()
            shutil.copy2(ROOT / "bin/common.sh", root / "bin/common.sh")
            shutil.copy2(
                ROOT / "bin/audit-github-deployment-chain",
                root / "bin/audit-github-deployment-chain",
            )

            run(["git", "init", "-q"], cwd=root)
            run(["git", "config", "user.name", "Connectanum Test"], cwd=root)
            run(["git", "config", "user.email", "test@example.invalid"], cwd=root)
            commit_all(root, "baseline")
            base = run(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                capture_output=True,
            ).stdout.strip()

            changed_paths = (
                ".github/workflows/wamp-profile-benchmarks.yml",
                "docs/exec-plans/2026-05-17-audit-runtime-sensitivity.md",
                "native/transport/ct_core/src/lib.rs",
                "packages/connectanum_router/lib/src/router/router_instance.dart",
                "packages/connectanum_router/test/router_runtime_test.dart",
            )
            for path in changed_paths:
                write_file(root, path)
            commit_all(root, "change deployment-sensitive paths")

            result = run(
                [
                    "bash",
                    "bin/audit-github-deployment-chain",
                    "--show-sensitive-changes-since",
                    base,
                ],
                cwd=root,
                capture_output=True,
            )
            sections = parse_sections(result.stdout)

            self.assertEqual(
                set(sections["Dart Package Publish Dry Run"]),
                {
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                    "packages/connectanum_router/test/router_runtime_test.dart",
                },
            )
            self.assertEqual(
                set(sections["Native Artifacts"]),
                {"native/transport/ct_core/src/lib.rs"},
            )
            self.assertEqual(
                set(sections["Router Image"]),
                {
                    "native/transport/ct_core/src/lib.rs",
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                },
            )
            self.assertEqual(
                set(sections["WAMP Profile Benchmarks"]),
                {
                    ".github/workflows/wamp-profile-benchmarks.yml",
                    "native/transport/ct_core/src/lib.rs",
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                },
            )
            self.assertEqual(
                set(sections["RC Readiness"]),
                {
                    ".github/workflows/wamp-profile-benchmarks.yml",
                    "native/transport/ct_core/src/lib.rs",
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                    "packages/connectanum_router/test/router_runtime_test.dart",
                },
            )


if __name__ == "__main__":
    unittest.main()
