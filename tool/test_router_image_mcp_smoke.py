#!/usr/bin/env python3
"""Regression checks for the packaged router MCP runtime smoke."""

from __future__ import annotations

import importlib.util
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER = REPO_ROOT / "bin" / "router-image-mcp-smoke"
CLIENT = REPO_ROOT / "tool" / "smoke_router_image_mcp.py"
CONFIG = REPO_ROOT / "deploy" / "docker" / "router_mcp_smoke.yaml"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "router-image.yml"

CLIENT_SPEC = importlib.util.spec_from_file_location("router_image_mcp_smoke", CLIENT)
assert CLIENT_SPEC is not None and CLIENT_SPEC.loader is not None
CLIENT_MODULE = importlib.util.module_from_spec(CLIENT_SPEC)
CLIENT_SPEC.loader.exec_module(CLIENT_MODULE)


class RouterImageMcpSmokeTest(unittest.TestCase):
    def test_sse_parser_accepts_leading_event_id(self) -> None:
        payload = CLIENT_MODULE._json_payload(
            'event: heartbeat\ndata:\n\n'
            'id: session-1:1\nevent: message\ndata: {"jsonrpc":"2.0","id":1}\n\n'
        )
        self.assertEqual(payload, {"jsonrpc": "2.0", "id": 1})

    def test_shell_runner_is_syntax_clean_and_requires_one_image(self) -> None:
        syntax = subprocess.run(
            ["bash", "-n", str(RUNNER)],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stdout)

        usage = subprocess.run(
            [str(RUNNER)],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        self.assertEqual(usage.returncode, 2, usage.stdout)
        self.assertIn("Usage: router-image-mcp-smoke IMAGE", usage.stdout)

        runner = RUNNER.read_text(encoding="utf-8")
        self.assertNotIn("docker run --detach --rm", runner)
        self.assertIn('docker logs "$container_id"', runner)

    def test_smoke_contract_covers_modern_and_streamable_mcp(self) -> None:
        client = CLIENT.read_text(encoding="utf-8")
        for expected in [
            'MODERN_PROTOCOL = "2026-07-28"',
            'COMPATIBILITY_PROTOCOL = "2025-11-25"',
            '"server/discover"',
            '"connectanum.api.list"',
            '"connectanum.pubsub.subscribe"',
            '"connectanum.pubsub.publish"',
            '"connectanum.pubsub.poll"',
            '"connectanum.pubsub.unsubscribe"',
            'endpoint, "DELETE", headers=session_headers',
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, client)

    def test_neutral_config_exposes_public_mcp_and_declared_topic(self) -> None:
        config = CONFIG.read_text(encoding="utf-8")
        for expected in [
            "endpoint: 0.0.0.0:8080",
            "path: /mcp",
            "type: mcp",
            "include_standard_meta_api: true",
            "include_pubsub_tools: true",
            "topic: image.smoke.events",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, config)

    def test_workflow_smokes_loaded_image_before_multiarch_build(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        local_build = workflow.index("- name: Build local router smoke image")
        runtime_smoke = workflow.index("- name: Smoke router-hosted MCP image")
        multiarch_build = workflow.index(
            "- name: Build or publish multi-arch router image"
        )
        self.assertLess(local_build, runtime_smoke)
        self.assertLess(runtime_smoke, multiarch_build)
        self.assertIn("load: true", workflow[local_build:runtime_smoke])
        self.assertIn("bin/router-image-mcp-smoke", workflow)


if __name__ == "__main__":
    unittest.main()
