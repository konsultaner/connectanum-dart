#!/usr/bin/env python3
"""Regression checks for generated MCP consumer package boundaries."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMON_SH = REPO_ROOT / "bin" / "common.sh"
ROUTER_HOSTED_CLIENT_EXAMPLE = (
    REPO_ROOT / "packages" / "connectanum_mcp" / "example" / "router_hosted_client.dart"
)


def _function_body(script: str, name: str) -> str:
    start = script.index(f"{name}()")
    next_function = re.search(r"\n[a-zA-Z0-9_]+\(\)", script[start + 1 :])
    end = len(script) if next_function is None else start + 1 + next_function.start()
    return script[start:end]


def _heredoc(body: str, target: str) -> str:
    match = re.search(
        rf'cat >"{re.escape(target)}" <<EOF\n(?P<content>.*?)\nEOF',
        body,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"Missing heredoc for {target}")
    return match.group("content")


def _top_level_section(pubspec: str, name: str) -> str:
    lines = pubspec.splitlines()
    for index, line in enumerate(lines):
        if line == f"{name}:":
            section: list[str] = []
            for section_line in lines[index + 1 :]:
                if section_line and not section_line.startswith(" "):
                    break
                section.append(section_line)
            return "\n".join(section)
    raise AssertionError(f"Missing top-level pubspec section {name!r}")


def _section_package_names(section: str) -> set[str]:
    return set(re.findall(r"^  ([a-zA-Z0-9_]+):", section, flags=re.MULTILINE))


class McpConsumerPackageBoundaryTest(unittest.TestCase):
    def test_generated_consumer_smokes_depend_on_public_mcp_entrypoint(self) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        cases = {
            "run_mcp_server_package_smoke": (
                "$smoke_dir/pubspec.yaml",
                {"connectanum_mcp"},
            ),
            "run_mcp_client_package_smoke": (
                "$smoke_dir/pubspec.yaml",
                {"connectanum_mcp"},
            ),
            "run_mcp_consumer_package_smoke": (
                "$smoke_dir/pubspec.yaml",
                {"connectanum_mcp", "connectanum_router"},
            ),
            "run_router_cli_consumer_package_smoke": (
                "$smoke_dir/dart-consumer/pubspec.yaml",
                {"connectanum_mcp"},
            ),
        }

        for function_name, (target, expected_dependencies) in cases.items():
            with self.subTest(function=function_name):
                pubspec = _heredoc(_function_body(script, function_name), target)
                dependencies = _section_package_names(
                    _top_level_section(pubspec, "dependencies")
                )
                overrides = _section_package_names(
                    _top_level_section(pubspec, "dependency_overrides")
                )

                self.assertEqual(dependencies, expected_dependencies)
                self.assertNotIn("connectanum_client", dependencies)
                self.assertIn("connectanum_client", overrides)
                self.assertIn("connectanum_core", overrides)
                self.assertIn("connectanum_mcp", overrides)

    def test_generated_mcp_client_smokes_import_only_mcp_package(self) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        for function_name in (
            "run_mcp_client_package_smoke",
            "run_mcp_consumer_package_smoke",
            "run_router_cli_consumer_package_smoke",
        ):
            with self.subTest(function=function_name):
                body = _function_body(script, function_name)
                self.assertIn(
                    "import 'package:connectanum_mcp/connectanum_mcp_io.dart';",
                    body,
                )
                self.assertNotRegex(body, r"import 'package:connectanum_client/")

    def test_public_router_hosted_client_example_uses_public_io_entrypoint(
        self,
    ) -> None:
        example = ROUTER_HOSTED_CLIENT_EXAMPLE.read_text(encoding="utf-8")

        self.assertIn(
            "import 'package:connectanum_mcp/connectanum_mcp_io.dart';",
            example,
        )
        self.assertNotRegex(example, r"import 'package:connectanum_client/")
        self.assertNotRegex(example, r"import 'package:connectanum_router/")

        for public_helper in (
            "McpStreamableHttpClient.withBearerToken",
            "McpStreamableHttpClient.withAuthGrant",
            "listConnectanumToolsDirect",
            "callConnectanumToolDirect",
            "subscribeWampTopicDirect",
            "publishWampEventDirect",
            "pollWampEventsDirect",
            "unsubscribeWampTopicDirect",
            "initialize",
            "deleteSession",
        ):
            with self.subTest(helper=public_helper):
                self.assertIn(public_helper, example)

    def test_fast_smoke_runs_public_router_hosted_client_example_help(self) -> None:
        body = _function_body(
            COMMON_SH.read_text(encoding="utf-8"),
            "run_router_hosted_mcp_example_smoke",
        )

        self.assertIn(
            "packages/connectanum_mcp/example/router_hosted_client.dart",
            body,
        )
        self.assertIn("--help", body)


if __name__ == "__main__":
    unittest.main()
