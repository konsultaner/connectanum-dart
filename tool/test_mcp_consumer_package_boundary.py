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

    def test_router_cli_consumer_smoke_exercises_raw_json_mcp_surface(
        self,
    ) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        body = _function_body(script, "run_router_cli_consumer_package_smoke")

        self.assertIn("resource_templates = post_json(", body)
        self.assertIn('"method": "resources/templates/list"', body)
        self.assertIn(
            'resource_templates["result"]["resourceTemplates"]',
            body,
        )
        self.assertIn("cli://mcp/task/{taskId}", body)
        self.assertIn(
            "Installed CLI MCP route missed configured resource template",
            body,
        )
        self.assertIn("procedures = post_json(", body)
        self.assertIn('"id": "public-procedures"', body)
        self.assertIn("cli.smoke.lookup", body)
        self.assertIn(
            "Installed CLI MCP direct procedure catalog missed public procedure",
            body,
        )
        self.assertIn("procedure_description = post_json(", body)
        self.assertIn('"id": "public-procedure-describe"', body)
        self.assertIn(
            "Installed CLI MCP direct procedure describe missed public metadata",
            body,
        )
        self.assertIn("topics = post_json(", body)
        self.assertIn('"id": "public-topics"', body)
        self.assertIn(
            "Installed CLI MCP direct topic catalog missed public topic",
            body,
        )
        self.assertIn("topic_description = post_json(", body)
        self.assertIn('"id": "public-topic-describe"', body)
        self.assertIn('"method": "connectanum.api.describe"', body)
        self.assertIn(
            "Installed CLI MCP direct topic describe missed public metadata",
            body,
        )
        self.assertIn("direct_subscribe = post_json(", body)
        self.assertIn('"id": "public-direct-pubsub-subscribe"', body)
        self.assertIn("direct_publish = post_json(", body)
        self.assertIn('"id": "public-direct-pubsub-publish"', body)
        self.assertIn("public-direct-publish", body)
        self.assertIn("streamable_topic_description = post_json(", body)
        self.assertIn('"id": "public-streamable-topic-describe"', body)
        self.assertIn(
            "Installed CLI MCP Streamable topic describe missed public metadata",
            body,
        )
        self.assertIn("streamable_procedure_description = post_json(", body)
        self.assertIn('"id": "public-streamable-procedure-describe"', body)
        self.assertIn(
            "Installed CLI MCP Streamable procedure describe "
            "missed public metadata",
            body,
        )
        self.assertIn("streamable_publish = post_json(", body)
        self.assertIn('"id": "public-streamable-pubsub-publish"', body)
        self.assertIn("public-streamable-publish", body)
        self.assertIn("direct_unsubscribe = post_json(", body)
        self.assertIn('"id": "public-direct-pubsub-unsubscribe"', body)
        self.assertIn("secure_templates = post_json(", body)
        self.assertIn('"id": "secure-resource-templates"', body)
        self.assertIn(
            'secure_templates["result"]["resourceTemplates"]',
            body,
        )
        self.assertIn("cli://mcp/secure/task/{taskId}", body)
        self.assertIn(
            "Installed CLI protected MCP missed secure resource template",
            body,
        )
        self.assertIn("secure_resource = post_json(", body)
        self.assertIn('"id": "secure-resource-read"', body)
        self.assertIn("Router CLI secure MCP context.", body)
        self.assertIn(
            "Installed CLI protected MCP resources/read missed secure context",
            body,
        )
        self.assertIn("secure_prompts = post_json(", body)
        self.assertIn('"id": "secure-prompts"', body)
        self.assertIn("summarize-secure-cli-context", body)
        self.assertIn("secure_prompt = post_json(", body)
        self.assertIn('"id": "secure-prompt-get"', body)
        self.assertIn("protected consumer readiness", body)
        self.assertIn(
            "Installed CLI protected MCP prompts/get missed secure substitution",
            body,
        )
        self.assertIn("secure_procedures = post_json(", body)
        self.assertIn('"id": "secure-procedures"', body)
        self.assertIn("cli.smoke.secure.lookup", body)
        self.assertIn(
            "Installed CLI protected MCP missed secure procedure",
            body,
        )
        self.assertIn("secure_procedure_description = post_json(", body)
        self.assertIn('"id": "secure-procedure-describe"', body)
        self.assertIn(
            "Installed CLI protected MCP direct procedure describe "
            '"\n        "missed secure metadata',
            body,
        )
        self.assertIn("secure_topic_description = post_json(", body)
        self.assertIn('"id": "secure-topic-describe"', body)
        self.assertIn(
            "Installed CLI protected MCP direct topic describe missed "
            "secure metadata",
            body,
        )
        self.assertIn("secure_streamable_topic_description = post_json(", body)
        self.assertIn('"id": "secure-streamable-topic-describe"', body)
        self.assertIn(
            "Installed CLI protected MCP Streamable topic describe "
            '"\n        "missed secure metadata',
            body,
        )
        self.assertIn("secure_streamable_procedure_description = post_json(", body)
        self.assertIn('"id": "secure-streamable-procedure-describe"', body)
        self.assertIn(
            "Installed CLI protected MCP Streamable procedure describe "
            '"\n        "missed secure metadata',
            body,
        )
        self.assertIn(
            "dart-consumer-secure-active-missing-bearer-tools",
            body,
        )
        self.assertIn(
            "Dart consumer protected route without bearer during active session",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-active-unknown-bearer-initialize",
            body,
        )
        self.assertIn(
            "Dart consumer protected route with unknown bearer during active session",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable auth rejection changed "
            "valid session state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-missing-bearer-tools",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response route without bearer "
            "during active session",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-unknown-bearer-initialize",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response route with unknown bearer "
            "during active session",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response auth rejection changed "
            "valid session state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-procedure-catalog",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON procedure "
            "catalog missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-procedure-describe",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON procedure "
            "describe missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-topic-describe",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON topic "
            "describe missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-templates",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON templates "
            "missed secure task.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-prompts",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON prompts "
            "missed secure prompt.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-prompt-get",
            body,
        )
        self.assertIn("active JSON-response direct prompt readiness", body)
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON helpers "
            "changed Streamable state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-streamable-procedure-catalog",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable procedure "
            "catalog missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-streamable-procedure-describe",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable procedure "
            "describe missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-streamable-topic-describe",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable topic describe "
            "missed metadata.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable WAMP describe "
            "changed session state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-token-only-direct-procedure-catalog",
            body,
        )
        self.assertIn(
            "Dart consumer token-only JSON-response direct procedure catalog "
            "missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-token-only-direct-procedure-describe",
            body,
        )
        self.assertIn(
            "Dart consumer token-only JSON-response direct procedure describe "
            "missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-token-only-streamable-procedure-catalog",
            body,
        )
        self.assertIn(
            "Dart consumer token-only JSON-response Streamable procedure "
            "catalog missed metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-token-only-streamable-procedure-describe",
            body,
        )
        self.assertIn(
            "Dart consumer token-only JSON-response Streamable procedure "
            "describe missed metadata.",
            body,
        )
        self.assertIn("dart-consumer-secure-topic-describe", body)
        self.assertIn(
            "Dart consumer missed protected direct JSON topic metadata.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-active-direct-topic-describe",
            body,
        )
        self.assertIn(
            "Dart consumer protected active direct JSON topic describe "
            "missed metadata.",
            body,
        )
        self.assertIn(
            "Dart consumer protected active direct JSON topic describe "
            "changed Streamable state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-active-direct-templates",
            body,
        )
        self.assertIn(
            "Dart consumer protected active direct JSON templates "
            "missed secure task.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-active-direct-prompts",
            body,
        )
        self.assertIn(
            "Dart consumer protected active direct JSON prompts "
            "missed secure prompt.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-active-direct-prompt-get",
            body,
        )
        self.assertIn("active direct prompt readiness", body)
        self.assertIn(
            "Dart consumer protected active direct JSON resource/prompt "
            "helpers changed Streamable state.",
            body,
        )
        self.assertIn("tool calls/resources/resource templates/prompts", body)
        self.assertIn(
            "public raw JSON resources/resource templates/prompts/WAMP "
            "procedure and topic catalog/describe/pub-sub plus Streamable "
            "procedure and topic describe/pub-sub",
            body,
        )
        self.assertIn(
            "active protected JSON-response auth rejection, direct JSON "
            "procedure catalog/describe/topic/resource/prompt isolation, "
            "and Streamable procedure catalog/describe plus topic describe",
            body,
        )
        self.assertIn(
            "token-only protected JSON-response "
            "tool calls/resources/resource templates/prompts/WAMP "
            "procedure catalog/describe/session/subscription "
            "meta/pubsub/batches plus Streamable procedure "
            "catalog/describe/topic describe",
            body,
        )
        self.assertIn("active protected auth rejection isolation", body)
        self.assertIn(
            "active protected direct JSON WAMP meta and resource/prompt isolation",
            body,
        )
        self.assertIn(
            "protected raw JSON resources/resource templates/prompts/WAMP "
            "procedure and topic describe/pub-sub plus Streamable procedure "
            "and topic describe/pub-sub",
            body,
        )

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
            "_supportedMcpProtocolVersions",
            "_protocolVersionOption",
            "Unsupported MCP protocol version",
            "_httpUri",
            "must be an absolute http or https URL.",
            "_bearerTokenOption",
            "_containsMcpWhitespaceOrControl",
            "Bearer token must not contain whitespace or control characters.",
            "_jsonObjectOption",
            "_jsonStringMapOption",
            "must be valid JSON.",
            "must be a JSON object.",
            "values must be strings.",
            "defaultProtocolVersion: options.protocolVersion",
            "'protocolVersion': options.protocolVersion",
            "listConnectanumToolsDirect",
            "callConnectanumToolDirect",
            "listResourcesDirect",
            "listResourceTemplatesDirect",
            "readResourceDirect",
            "listPromptsDirect",
            "getPromptDirect",
            "postBatchDirect",
            "direct-batch-tools",
            "direct-batch-tool-call",
            "direct-batch-resource-templates",
            "direct-batch-wamp-procedure-api-list",
            "directBatch",
            "countWampSessionsDirect",
            "listWampApiDirect",
            "_expectWampCatalogContains",
            "_wampCatalogContainsUri",
            "_expectCatalogContainsValue",
            "_catalogContainsValue",
            "catalog did not include $uri.",
            "catalog did not include $value.",
            "label: 'Direct tool'",
            "label: 'Direct resource'",
            "label: 'Direct prompt'",
            "label: 'Direct WAMP procedure'",
            "label: 'Direct WAMP topic'",
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
            "label: 'Streamable tool'",
            "listResources(",
            "streamable-resources",
            "streamable-batch-resources",
            "label: 'Streamable resource'",
            "resources",
            "streamable-batch-wamp-procedure-api-list",
            "'batch'",
            "callTool",
            "streamable-tool-call",
            "toolResult",
            "listResourceTemplates(",
            "streamable-resource-templates",
            "streamable-batch-resource-templates",
            "resourceTemplates",
            "listPrompts(",
            "streamable-prompts",
            "streamable-batch-prompts",
            "label: 'Streamable prompt'",
            "prompts",
            "countWampSessions(",
            "streamable-wamp-session-count",
            "listWampApi(",
            "streamable-wamp-procedure-api-list",
            "streamable-wamp-topic-api-list",
            "label: 'Streamable WAMP procedure'",
            "label: 'Streamable WAMP topic'",
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
            "_nonEmptyStringOption",
            "_mcpToolNameOption",
            "_mcpSelectorOption",
            "_mcpResourceUriOption",
            "must be 1-128 ASCII letters",
            "must be an absolute URI with a scheme.",
            "must not contain whitespace or control characters.",
            "_printDryRunSummary",
            "--dry-run",
        ):
            with self.subTest(helper=public_helper):
                self.assertIn(public_helper, example)

    def test_fast_smoke_runs_public_router_hosted_client_example_dry_run(
        self,
    ) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        wrapper_body = _function_body(script, "run_router_hosted_mcp_example_smoke")
        body = _function_body(
            script,
            "run_public_router_hosted_mcp_client_dry_run_smoke",
        )

        self.assertIn(
            "run_public_router_hosted_mcp_client_dry_run_smoke",
            wrapper_body,
        )
        self.assertIn(
            "run_public_router_hosted_mcp_client_dry_run_smoke || return",
            wrapper_body,
        )
        self.assertLess(
            wrapper_body.index(
                "run_public_router_hosted_mcp_client_dry_run_smoke",
            ),
            wrapper_body.index("native_runtime_supported"),
        )
        self.assertLess(
            wrapper_body.index(
                "run_public_router_hosted_mcp_client_dry_run_smoke",
            ),
            wrapper_body.index("ensure_rust_env"),
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
        self.assertIn('"resourceTemplates":true', body)
        self.assertIn("resource-template discovery", body)
        self.assertIn("pubsub_only_dry_run_summary=\"$(", body)
        self.assertIn("T-pubsub-only-example-dry-run", body)
        self.assertIn('"subscriptionMetadata":true', body)
        self.assertIn(
            "pub/sub-only dry-run did not report subscription metadata lookup",
            body,
        )
        self.assertIn("unknown_option_output=\"$(", body)
        self.assertIn(
            "accepted an unknown option",
            body,
        )
        self.assertIn("Unknown option: --unknown-option", body)
        self.assertIn(
            "did not report the unknown option error",
            body,
        )
        self.assertIn("missing_tool_value_output=\"$(", body)
        self.assertIn(
            "accepted a missing tool option value",
            body,
        )
        self.assertIn("Missing value for --tool.", body)
        self.assertIn(
            "did not report the missing tool option value error",
            body,
        )
        self.assertIn("duplicate_tool_output=\"$(", body)
        self.assertIn(
            "accepted duplicate tool options",
            body,
        )
        self.assertIn("Duplicate option: --tool.", body)
        self.assertIn(
            "did not report the duplicate tool option error",
            body,
        )
        self.assertIn("duplicate_dry_run_output=\"$(", body)
        self.assertIn(
            "accepted duplicate dry-run flags",
            body,
        )
        self.assertIn("Duplicate option: --dry-run.", body)
        self.assertIn(
            "did not report the duplicate dry-run flag error",
            body,
        )
        self.assertIn("missing_endpoint_output=\"$(", body)
        self.assertIn(
            "accepted a missing endpoint",
            body,
        )
        self.assertIn("Missing required --endpoint.", body)
        self.assertIn(
            "did not report the missing endpoint error",
            body,
        )
        self.assertIn("malformed_endpoint_output=\"$(", body)
        self.assertIn(
            "accepted a malformed endpoint URL",
            body,
        )
        self.assertIn(
            "--endpoint must be an absolute http or https URL.",
            body,
        )
        self.assertIn(
            "did not report the malformed endpoint URL error",
            body,
        )
        self.assertIn("invalid_protocol_output=\"$(", body)
        self.assertIn(
            "accepted an unsupported protocol version",
            body,
        )
        self.assertIn(
            'Unsupported MCP protocol version "1900-01-01".',
            body,
        )
        self.assertIn(
            "did not report the unsupported protocol version error",
            body,
        )
        self.assertIn("invalid_bearer_output=\"$(", body)
        self.assertIn(
            "accepted a bearer token with whitespace",
            body,
        )
        self.assertIn(
            "Bearer token must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the invalid bearer token error",
            body,
        )
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
        self.assertIn("malformed_auth_url_output=\"$(", body)
        self.assertIn(
            "accepted a malformed auth URL",
            body,
        )
        self.assertIn(
            "--auth-url must be an absolute http or https URL.",
            body,
        )
        self.assertIn(
            "did not report the malformed auth URL error",
            body,
        )
        self.assertIn("invalid_auth_realm_output=\"$(", body)
        self.assertIn(
            "accepted an invalid auth realm",
            body,
        )
        self.assertIn(
            "--realm must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the invalid auth realm error",
            body,
        )
        self.assertIn("invalid_auth_id_output=\"$(", body)
        self.assertIn(
            "accepted an invalid auth id",
            body,
        )
        self.assertIn(
            "--auth-id must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the invalid auth id error",
            body,
        )
        self.assertIn("dangling_tool_arguments_output=\"$(", body)
        self.assertIn(
            "accepted tool arguments without a tool",
            body,
        )
        self.assertIn("Use --tool-arguments together with --tool.", body)
        self.assertIn(
            "did not report the dangling tool arguments error",
            body,
        )
        self.assertIn("dangling_prompt_arguments_output=\"$(", body)
        self.assertIn(
            "accepted prompt arguments without a prompt",
            body,
        )
        self.assertIn("Use --prompt-arguments together with --prompt.", body)
        self.assertIn(
            "did not report the dangling prompt arguments error",
            body,
        )
        self.assertIn("dangling_pubsub_event_output=\"$(", body)
        self.assertIn(
            "accepted a pub/sub event without a topic",
            body,
        )
        self.assertIn("Use --pubsub-event together with --pubsub-topic.", body)
        self.assertIn(
            "did not report the dangling pub/sub event error",
            body,
        )
        self.assertIn("empty_tool_output=\"$(", body)
        self.assertIn(
            "accepted an empty tool name",
            body,
        )
        self.assertIn("--tool must not be empty.", body)
        self.assertIn(
            "did not report the empty tool name error",
            body,
        )
        self.assertIn("invalid_tool_name_output=\"$(", body)
        self.assertIn(
            "accepted an invalid tool name",
            body,
        )
        self.assertIn(
            "--tool must be 1-128 ASCII letters, digits, underscores, "
            "hyphens, or dots.",
            body,
        )
        self.assertIn(
            "did not report the invalid tool name error",
            body,
        )
        self.assertIn("invalid_resource_uri_output=\"$(", body)
        self.assertIn(
            "accepted an invalid resource URI",
            body,
        )
        self.assertIn(
            "--resource-uri must be an absolute URI with a scheme.",
            body,
        )
        self.assertIn(
            "did not report the invalid resource URI error",
            body,
        )
        self.assertIn("whitespace_resource_uri_output=\"$(", body)
        self.assertIn(
            "accepted a resource URI with whitespace",
            body,
        )
        self.assertIn(
            "--resource-uri must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the resource URI whitespace error",
            body,
        )
        self.assertIn("invalid_prompt_name_output=\"$(", body)
        self.assertIn(
            "accepted an invalid prompt name",
            body,
        )
        self.assertIn(
            "--prompt must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the invalid prompt name error",
            body,
        )
        self.assertIn("invalid_wamp_topic_output=\"$(", body)
        self.assertIn(
            "accepted an invalid WAMP topic",
            body,
        )
        self.assertIn(
            "--wamp-topic must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the invalid WAMP topic error",
            body,
        )
        self.assertIn("blank_pubsub_topic_output=\"$(", body)
        self.assertIn(
            "accepted a blank pub/sub topic",
            body,
        )
        self.assertIn("--pubsub-topic must not be empty.", body)
        self.assertIn(
            "did not report the blank pub/sub topic error",
            body,
        )
        self.assertIn("invalid_pubsub_topic_output=\"$(", body)
        self.assertIn(
            "accepted an invalid pub/sub topic",
            body,
        )
        self.assertIn(
            "--pubsub-topic must not contain whitespace or control characters.",
            body,
        )
        self.assertIn(
            "did not report the invalid pub/sub topic error",
            body,
        )
        self.assertIn("malformed_tool_arguments_output=\"$(", body)
        self.assertIn(
            "accepted malformed tool arguments JSON",
            body,
        )
        self.assertIn("--tool-arguments must be valid JSON.", body)
        self.assertIn(
            "did not report the malformed tool arguments error",
            body,
        )
        self.assertIn("array_pubsub_event_output=\"$(", body)
        self.assertIn(
            "accepted a non-object pub/sub event",
            body,
        )
        self.assertIn("--pubsub-event must be a JSON object.", body)
        self.assertIn(
            "did not report the non-object pub/sub event error",
            body,
        )
        self.assertIn("non_string_prompt_arguments_output=\"$(", body)
        self.assertIn(
            "accepted non-string prompt arguments",
            body,
        )
        self.assertIn("--prompt-arguments values must be strings.", body)
        self.assertIn(
            "did not report the non-string prompt arguments error",
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
        self.assertIn("T-pubsub-only-example-live", live_body)
        self.assertIn(
            "Pub/sub-only router-hosted MCP client live smoke completed.",
            live_body,
        )
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
