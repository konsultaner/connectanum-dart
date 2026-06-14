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
            "McpStreamableHttpClient.latestProtocolVersion",
            "defaultProtocolVersion: options.protocolVersion",
            "'protocolVersion': options.protocolVersion",
            "listConnectanumToolsDirect",
            "callConnectanumToolDirect",
            "listResourcesDirect",
            "readResourceDirect",
            "listPromptsDirect",
            "getPromptDirect",
            "postBatchDirect",
            "direct-batch-tools",
            "direct-batch-tool-call",
            "direct-batch-wamp-procedure-api-list",
            "directBatch",
            "countWampSessionsDirect",
            "listWampApiDirect",
            "describeWampApiDirect",
            "matchWampRegistrationDirect",
            "matchWampSubscriptionDirect",
            "subscribeWampTopicDirect",
            "publishWampEventDirect",
            "pollWampEventsDirect",
            "unsubscribeWampTopicDirect",
            "initialize",
            "postBatch(",
            "streamable-batch-tools",
            "streamable-batch-tool-call",
            "streamable-batch-wamp-procedure-api-list",
            "'batch'",
            "callTool",
            "streamable-tool-call",
            "toolResult",
            "countWampSessions(",
            "streamable-wamp-session-count",
            "listWampApi(",
            "streamable-wamp-procedure-api-list",
            "streamable-wamp-topic-api-list",
            "describeWampApi(",
            "streamable-wamp-procedure-api-describe",
            "streamable-wamp-topic-api-describe",
            "matchWampRegistration(",
            "streamable-wamp-registration-match",
            "matchWampSubscription(",
            "streamable-wamp-subscription-match",
            "wampMetadata",
            "subscriptionMetadata",
            "subscribeWampTopic",
            "streamable-pubsub-subscribe",
            "publishWampEvent",
            "streamable-pubsub-publish",
            "pollWampEvents",
            "streamable-pubsub-poll",
            "unsubscribeWampTopic",
            "streamable-pubsub-unsubscribe",
            "deleteSession",
            "_printDryRunSummary",
            "--dry-run",
        ):
            with self.subTest(helper=public_helper):
                self.assertIn(public_helper, example)

    def test_fast_smoke_runs_public_router_hosted_client_example_dry_run(
        self,
    ) -> None:
        body = _function_body(
            COMMON_SH.read_text(encoding="utf-8"),
            "run_router_hosted_mcp_example_smoke",
        )

        self.assertIn(
            "packages/connectanum_mcp/example/router_hosted_client.dart",
            body,
        )
        self.assertIn("--endpoint http://127.0.0.1:8080/mcp", body)
        self.assertIn("--protocol-version 2025-06-18", body)
        self.assertIn("--tool example.task.lookup", body)
        self.assertIn("--tool-arguments", body)
        self.assertIn("--resource-uri app://example/context", body)
        self.assertIn("--prompt summarize-task", body)
        self.assertIn("--prompt-arguments", body)
        self.assertIn("--wamp-procedure example.task.lookup", body)
        self.assertIn("--wamp-topic example.events.task", body)
        self.assertIn("--pubsub-topic example.events.task", body)
        self.assertIn("--pubsub-event", body)
        self.assertIn("--dry-run", body)
        self.assertIn("dry_run_summary=\"$(", body)
        self.assertIn('"authMode":"none"', body)
        self.assertIn('"protocolVersion":"2025-06-18"', body)
        self.assertIn("--endpoint http://127.0.0.1:8080/mcp/secure", body)
        self.assertIn("--bearer-token dry-run-bearer-secret", body)
        self.assertIn("dry-run-bearer-secret", body)
        self.assertIn("leaked bearer token material", body)
        self.assertIn('"authMode":"bearer"', body)
        self.assertIn("--auth-url http://127.0.0.1:8080/auth", body)
        self.assertIn("--ticket dry-run-ticket-secret", body)
        self.assertIn("dry-run-ticket-secret", body)
        self.assertIn("leaked ticket secret material", body)
        self.assertIn('"authMode":"ticket"', body)
        self.assertIn("ambiguous_auth_output=\"$(", body)
        self.assertIn(
            "accepted mutually exclusive auth options",
            body,
        )
        self.assertIn(
            "Use either --bearer-token or --auth-url, not both.",
            body,
        )
        self.assertIn(
            "did not report the mutually exclusive auth error",
            body,
        )
        self.assertIn("incomplete_auth_output=\"$(", body)
        self.assertIn(
            "accepted incomplete ticket auth options",
            body,
        )
        self.assertIn(
            "Use --auth-url, --realm, --auth-id, and --ticket together.",
            body,
        )
        self.assertIn(
            "did not report the incomplete ticket auth error",
            body,
        )

    def test_fast_smoke_runs_public_router_hosted_client_example_live(
        self,
    ) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        wrapper_body = _function_body(script, "run_router_hosted_mcp_example_smoke")
        live_body = _function_body(
            script,
            "run_public_router_hosted_mcp_client_live_smoke",
        )

        self.assertIn("run_public_router_hosted_mcp_client_live_smoke", wrapper_body)
        self.assertIn(
            "packages/connectanum_router/example/router_hosted_mcp.dart",
            live_body,
        )
        self.assertNotIn("--smoke-and-exit", live_body)
        self.assertIn(
            "packages/connectanum_mcp/example/router_hosted_client.dart",
            live_body,
        )
        self.assertIn("--endpoint \"$endpoint\"", live_body)
        self.assertIn("--endpoint \"$secure_endpoint\"", live_body)
        self.assertIn("--endpoint \"$secure_json_endpoint\"", live_body)
        self.assertIn("--protocol-version 2025-06-18", live_body)
        self.assertIn(
            "Bearer-protected JSON-response MCP endpoint is running at",
            live_body,
        )
        self.assertIn("auth_url=\"${endpoint%/mcp}/auth\"", live_body)
        self.assertIn("bearer_token=\"$(", live_body)
        self.assertIn("python3 - \"$auth_url\"", live_body)
        self.assertIn("\"authmethod\": \"ticket\"", live_body)
        self.assertIn("--auth-url \"$auth_url\"", live_body)
        self.assertIn("--bearer-token \"$bearer_token\"", live_body)
        self.assertIn("--realm example.realm", live_body)
        self.assertIn("--auth-id mcp-user", live_body)
        self.assertIn("--ticket mcp-demo-ticket", live_body)
        self.assertIn("--tool example.task.lookup", live_body)
        self.assertIn("--resource-uri app://example/context", live_body)
        self.assertIn("--prompt summarize-task", live_body)
        self.assertIn("--wamp-procedure example.task.lookup", live_body)
        self.assertIn("--wamp-topic example.events.task", live_body)
        self.assertIn("--pubsub-topic example.events.task", live_body)
        self.assertIn("T-bearer-example-live", live_body)
        self.assertIn("T-bearer-json-response-example-live", live_body)
        self.assertIn(
            "Authenticated router-hosted MCP client live smoke completed.",
            live_body,
        )
        self.assertIn(
            "Bearer-token router-hosted MCP client live smoke completed.",
            live_body,
        )
        self.assertIn(
            "Authenticated router-hosted JSON-response MCP client live smoke "
            "completed.",
            live_body,
        )
        self.assertIn(
            "Bearer-token router-hosted JSON-response MCP client live smoke "
            "completed.",
            live_body,
        )
        self.assertNotRegex(live_body, r"package:connectanum_client/")
        self.assertNotRegex(live_body, r"package:connectanum_router/")


if __name__ == "__main__":
    unittest.main()
