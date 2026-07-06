#!/usr/bin/env python3
"""Regression tests for the public artifact reference guard."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


SCRIPT = Path(__file__).with_name("check_public_artifact_references.py")
SPEC = importlib.util.spec_from_file_location(
    "check_public_artifact_references",
    SCRIPT,
)
assert SPEC is not None
guard = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


class PublicArtifactReferenceGuardTest(unittest.TestCase):
    def test_selects_public_artifacts(self) -> None:
        self.assertTrue(guard.is_public_artifact("README.md"))
        self.assertTrue(guard.is_public_artifact("docs/project_state.md"))
        self.assertTrue(
            guard.is_public_artifact("packages/connectanum_mcp/pubspec.yaml")
        )
        self.assertTrue(
            guard.is_public_artifact(
                "packages/connectanum_router/example/router_hosted_mcp.dart"
            )
        )
        self.assertTrue(
            guard.is_public_artifact(".github/workflows/native-artifacts.yml")
        )
        self.assertTrue(guard.is_public_artifact("bin/common.sh"))
        self.assertFalse(
            guard.is_public_artifact("packages/connectanum_router/test/foo.dart")
        )
        self.assertFalse(guard.is_public_artifact("tool/check_private.py"))

    def test_reports_local_paths(self) -> None:
        findings = guard.scan_text(
            "docs/example.md",
            "Run this from /Users/example/Projects/private-app before release.\n",
        )

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].line, 1)
        self.assertEqual(findings[0].column, 15)
        self.assertEqual(findings[0].kind, "macOS absolute user path")

    def test_reports_configured_private_literals(self) -> None:
        findings = guard.scan_text(
            "packages/connectanum_mcp/README.md",
            "This package works with private-app-name.\n",
            literal_denylist=("private-app-name",),
        )

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].kind, "configured private reference")

    def test_scans_configured_literals_only_in_public_artifacts(self) -> None:
        with TemporaryDirectory() as raw_repo:
            repo_root = Path(raw_repo)
            public_doc = repo_root / "docs" / "example.md"
            private_test = (
                repo_root
                / "packages"
                / "connectanum_router"
                / "test"
                / "example_test.dart"
            )
            private_tool = repo_root / "tool" / "local_note.txt"

            public_doc.parent.mkdir(parents=True)
            private_test.parent.mkdir(parents=True)
            private_tool.parent.mkdir(parents=True)
            public_doc.write_text(
                "Use internal-consumer-app only in private notes.\n",
                encoding="utf-8",
            )
            private_test.write_text(
                "internal-consumer-app can appear in private tests.\n",
                encoding="utf-8",
            )
            private_tool.write_text(
                "internal-consumer-app can appear in private tooling.\n",
                encoding="utf-8",
            )

            findings = guard.scan_public_artifacts(
                repo_root,
                paths=(
                    "docs/example.md",
                    "packages/connectanum_router/test/example_test.dart",
                    "tool/local_note.txt",
                ),
                literal_denylist=("internal-consumer-app",),
            )

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].path, "docs/example.md")
        self.assertEqual(findings[0].kind, "configured private reference")


if __name__ == "__main__":
    unittest.main()
