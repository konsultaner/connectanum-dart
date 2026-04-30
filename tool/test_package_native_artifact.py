#!/usr/bin/env python3
"""Regression checks for public native artifact install guidance."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVALID_PACKAGE_TARGET_RE = re.compile(
    r"dart run connectanum_(?:router|client):tool/install_native\.dart"
)


class NativeArtifactGuidanceTest(unittest.TestCase):
    def test_generated_bundle_readme_uses_executable_source_checkout_paths(self) -> None:
        script = (ROOT / "bin/package-native-artifact").read_text(encoding="utf-8")

        self.assertNotRegex(script, INVALID_PACKAGE_TARGET_RE)
        self.assertIn(
            "dart packages/connectanum_router/tool/install_native.dart --tag "
            "<release-tag>",
            script,
        )
        self.assertIn(
            "dart packages/connectanum_client/tool/install_native.dart --tag "
            "<release-tag>",
            script,
        )

    def test_install_helper_usage_matches_documented_source_checkout_path(self) -> None:
        for package in ("connectanum_router", "connectanum_client"):
            with self.subTest(package=package):
                helper = (
                    ROOT / f"packages/{package}/tool/install_native.dart"
                ).read_text(encoding="utf-8")

                self.assertNotRegex(helper, INVALID_PACKAGE_TARGET_RE)
                self.assertIn(
                    f"Usage: dart packages/{package}/tool/install_native.dart "
                    "--tag <release-tag> [options]",
                    helper,
                )


if __name__ == "__main__":
    unittest.main()
