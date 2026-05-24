#!/usr/bin/env python3
"""Regression checks for repository verification scripts."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TEST_ALL = REPO_ROOT / "bin" / "test-all"


class VerificationScriptsTest(unittest.TestCase):
    def test_test_all_is_bash_syntax_clean(self) -> None:
        result = subprocess.run(
            ["bash", "-n", str(TEST_ALL)],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout)

    def test_browser_websocket_smoke_retries_without_retry_annotations(
        self,
    ) -> None:
        script = TEST_ALL.read_text(encoding="utf-8")

        self.assertIn("run_client_browser_websocket_test()", script)
        self.assertIn('CONNECTANUM_BROWSER_TEST_ATTEMPTS:-2', script)
        self.assertIn(
            "CONNECTANUM_BROWSER_TEST_ATTEMPT_TIMEOUT_SECONDS:-420",
            script,
        )
        self.assertIn("run_browser_websocket_test_attempt()", script)
        self.assertIn(
            "Browser WebSocket smoke exceeded %ss",
            script,
        )
        self.assertIn('args+=(--reporter=expanded)', script)
        self.assertIn(
            "the final attempt keeps the default reporter",
            script,
        )
        self.assertIn(
            'if run_browser_websocket_test_attempt "$attempt_timeout_seconds" '
            'dart test "${args[@]}"; then',
            script,
        )
        self.assertIn('return "$status"', script)


if __name__ == "__main__":
    unittest.main()
