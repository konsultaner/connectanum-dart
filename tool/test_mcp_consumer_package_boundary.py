#!/usr/bin/env python3
"""Regression checks for generated MCP consumer package boundaries."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMON_SH = REPO_ROOT / "bin" / "common.sh"
MCP_PUBSPEC = REPO_ROOT / "packages" / "connectanum_mcp" / "pubspec.yaml"
MCP_ROUTER_HOSTED_CLIENT_BIN = (
    REPO_ROOT / "packages" / "connectanum_mcp" / "bin" / "router_hosted_client.dart"
)
ROUTER_HOSTED_CLIENT_EXAMPLE = (
    REPO_ROOT / "packages" / "connectanum_mcp" / "example" / "router_hosted_client.dart"
)
ROUTER_HOSTED_SERVER_EXAMPLE = (
    REPO_ROOT / "packages" / "connectanum_router" / "example" / "router_hosted_mcp.dart"
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
    def test_mcp_package_exposes_router_hosted_client_executable(self) -> None:
        pubspec = MCP_PUBSPEC.read_text(encoding="utf-8")
        executable = MCP_ROUTER_HOSTED_CLIENT_BIN.read_text(encoding="utf-8")
        script = COMMON_SH.read_text(encoding="utf-8")
        body = _function_body(script, "run_mcp_client_package_smoke")

        self.assertIn("executables:", pubspec)
        self.assertIn("  router_hosted_client:", pubspec)
        self.assertIn(
            "import '../example/router_hosted_client.dart' as example;",
            executable,
        )
        self.assertIn(
            "Future<void> main(List<String> args) => example.main(args);",
            executable,
        )
        self.assertIn(
            "dart run connectanum_mcp:router_hosted_client --help",
            body,
        )
        self.assertIn(
            "dart run connectanum_mcp:router_hosted_client \\",
            body,
        )
        self.assertIn('PUB_CACHE="$pub_cache" dart pub get', body)
        self.assertIn('PUB_CACHE="$pub_cache" dart analyze', body)
        self.assertIn('PUB_CACHE="$pub_cache" dart run bin/main.dart', body)
        self.assertIn("dart pub global activate --source path", body)
        self.assertIn(
            'global_smoke_workspace="$smoke_dir/global-workspace"',
            body,
        )
        self.assertIn(
            '"$global_smoke_workspace/packages/connectanum_mcp"',
            body,
        )
        self.assertIn("connectanum_mcp_global_activation_smoke_workspace", body)
        self.assertIn('"$ROOT_DIR/pubspec.lock"', body)
        self.assertIn('"$global_smoke_workspace/pubspec.lock"', body)
        self.assertIn('cp -R "$package_source/example"', body)
        self.assertIn(
            'global_mcp_command="$(PATH="$pub_cache/bin:$PATH" '
            'PUB_CACHE="$pub_cache" command -v router_hosted_client || true)"',
            body,
        )
        self.assertIn(
            'if [[ "$global_mcp_command" != "$pub_cache/bin/router_hosted_client" ]]; then',
            body,
        )
        self.assertIn(
            'PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" router_hosted_client --help',
            body,
        )
        self.assertIn(
            'PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" router_hosted_client \\',
            body,
        )
        self.assertIn("--pubsub-topic agent.events", body)
        self.assertIn('"subscriptionMetadata":true', body)

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

    def test_router_cli_consumer_smoke_uses_checkout_command_alias(self) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        body = _function_body(script, "run_router_cli_consumer_package_smoke")

        self.assertIn(
            'router_command="$(PATH="$ROOT_DIR/bin:$PATH" '
            'command -v connectanum_router || true)"',
            body,
        )
        self.assertIn(
            r"$2 !~ /(^|\/)(awk|bash|zsh|sh)$/",
            body,
        )
        self.assertIn(
            'if [[ "$router_command" != "$ROOT_DIR/bin/connectanum_router" ]]; then',
            body,
        )
        self.assertIn(
            'PATH="$ROOT_DIR/bin:$PATH" connectanum_router --help',
            body,
        )
        self.assertIn(
            "Usage: connectanum_router --config <path>",
            body,
        )
        self.assertNotIn(
            "Usage: dart run connectanum_router --config <path>",
            body,
        )
        self.assertIn("source-checkout alias", body)
        self.assertNotIn(
            'rm -rf "$ROOT_DIR/.dart_tool/pub/bin/connectanum_router"',
            body,
        )

    def test_router_cli_consumer_smoke_uses_package_executable(self) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        body = _function_body(script, "run_router_cli_consumer_package_smoke")
        pubspec = _heredoc(body, "$smoke_dir/router-runner/pubspec.yaml")

        dependencies = _section_package_names(
            _top_level_section(pubspec, "dependencies")
        )
        overrides = _section_package_names(
            _top_level_section(pubspec, "dependency_overrides")
        )

        self.assertEqual(dependencies, {"connectanum_router"})
        self.assertNotIn("connectanum_mcp", dependencies)
        self.assertIn("connectanum_core", overrides)
        self.assertIn("connectanum_client", overrides)
        self.assertIn("connectanum_mcp", overrides)
        self.assertIn("connectanum_router", overrides)
        self.assertIn("CONNECTANUM_SKIP_NATIVE_BUILD: true", pubspec)
        self.assertIn('PUB_CACHE="$pub_cache" dart pub get', body)
        self.assertIn(
            'PUB_CACHE="$pub_cache" dart run connectanum_router --help',
            body,
        )
        self.assertIn("dart pub global activate --source path", body)
        self.assertIn(
            'global_smoke_workspace="$smoke_dir/global-workspace"',
            body,
        )
        self.assertIn(
            '"$global_smoke_workspace/packages/connectanum_router"',
            body,
        )
        self.assertIn("connectanum_router_global_activation_smoke_workspace", body)
        self.assertIn('"$ROOT_DIR/pubspec.lock"', body)
        self.assertIn('"$global_smoke_workspace/pubspec.lock"', body)
        self.assertIn("connectanum_auth_server", body)
        self.assertIn(
            'global_router_command="$(PATH="$pub_cache/bin:$PATH" '
            'PUB_CACHE="$pub_cache" command -v connectanum_router || true)"',
            body,
        )
        self.assertIn(
            'if [[ "$global_router_command" != "$pub_cache/bin/connectanum_router" ]]; then',
            body,
        )
        self.assertIn(
            'PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" connectanum_router --help',
            body,
        )
        self.assertIn(
            "Usage: connectanum_router --config <path>",
            body,
        )
        self.assertNotIn(
            "Usage: dart run connectanum_router --config <path>",
            body,
        )
        self.assertIn(
            'exec env PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" connectanum_router \\\n'
            '      --config "$smoke_dir/router.yaml"',
            body,
        )
        self.assertNotIn(
            'exec env PUB_CACHE="$pub_cache" dart run connectanum_router \\\n'
            '      --config "$smoke_dir/router.yaml"',
            body,
        )

    def test_bench_cli_consumer_smoke_uses_package_executable(self) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        body = _function_body(script, "run_bench_cli_consumer_package_smoke")
        pubspec = _heredoc(body, "$smoke_dir/bench-runner/pubspec.yaml")

        dependencies = _section_package_names(
            _top_level_section(pubspec, "dependencies")
        )
        overrides = _section_package_names(
            _top_level_section(pubspec, "dependency_overrides")
        )

        self.assertEqual(dependencies, {"connectanum_bench"})
        self.assertIn("connectanum_auth_server", overrides)
        self.assertIn("connectanum_core", overrides)
        self.assertIn("connectanum_client", overrides)
        self.assertIn("connectanum_mcp", overrides)
        self.assertIn("connectanum_router", overrides)
        self.assertIn("connectanum_bench", overrides)
        self.assertIn("CONNECTANUM_SKIP_NATIVE_BUILD: true", pubspec)
        self.assertIn('PUB_CACHE="$pub_cache" dart pub get', body)
        self.assertIn(
            'dart run connectanum_bench:router_bench --help',
            body,
        )
        self.assertIn(
            'dart run connectanum_bench:bench_router_service --help',
            body,
        )
        self.assertIn(
            'dart run connectanum_bench:wamp_client_worker --help',
            body,
        )
        self.assertIn("'--config (mandatory)'", body)
        self.assertIn("'--native-lib (mandatory)'", body)
        self.assertIn("'--router-config'", body)
        self.assertIn("'--targets-json'", body)

    def test_router_cli_consumer_smoke_bounds_router_shutdown(self) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        body = _function_body(script, "run_router_cli_consumer_package_smoke")

        self.assertIn("_wait_for_router_cli_smoke_pid_exit()", body)
        self.assertIn(
            "CONNECTANUM_ROUTER_CLI_SMOKE_SHUTDOWN_TIMEOUT_SECONDS:-5",
            body,
        )
        self.assertIn('kill -KILL "$pid"', body)
        self.assertIn(
            '_wait_for_router_cli_smoke_pid_exit "$router_pid"',
            body,
        )
        self.assertNotIn(
            'wait "$router_pid" >/dev/null 2>&1 || true\n'
            '      router_pids="$(_router_cli_smoke_process_ids)"',
            body,
        )
        self.assertNotIn(
            'rm -rf "$ROOT_DIR/.dart_tool/hooks_runner"',
            body,
        )

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
        self.assertIn("dart-consumer-refreshed-json-response-tools", body)
        self.assertIn(
            "Dart consumer refreshed grant missed JSON-response direct JSON "
            "tools.",
            body,
        )
        self.assertIn("dart-consumer-refreshed-json-response-initialize", body)
        self.assertIn(
            "Dart consumer refreshed JSON-response initialize changed "
            "protocol.",
            body,
        )
        self.assertIn(
            "dart-consumer-refreshed-json-response-streamable-tools",
            body,
        )
        self.assertIn(
            "Dart consumer refreshed grant missed JSON-response Streamable "
            "tools.",
            body,
        )
        self.assertIn(
            "Dart consumer refreshed JSON-response delete leaked state.",
            body,
        )
        self.assertIn("dart-consumer-revoked-json-response-tools", body)
        self.assertIn(
            "Dart consumer revoked access token JSON-response direct JSON "
            "request",
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
            "dart-consumer-secure-json-active-direct-templates-page",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON templates "
            "missed cursor.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON templates "
            "cursor page missed secure extra task.",
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
            "dart-consumer-secure-json-active-direct-prompts-page",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON prompts "
            "missed cursor.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON prompts "
            "cursor page missed secure extra prompt.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-prompt-get",
            body,
        )
        self.assertIn("active JSON-response direct prompt readiness", body)
        self.assertIn(
            "dart-consumer-secure-json-active-direct-batch-resource-read",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct batch count "
            "changed.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct batch missed "
            "content.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-batch-bad-method",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct batch missed "
            "error isolation.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-batch-api-list",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct batch missed "
            "topic API.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON helpers "
            "or batch changed Streamable state.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-direct-subscribe", body)
        self.assertIn(
            "Dart consumer protected JSON-response direct subscription was "
            "invalid.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-direct-publish", body)
        self.assertIn(
            "Dart consumer protected JSON-response direct publish was invalid.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-direct-poll", body)
        self.assertIn(
            "Dart consumer protected JSON-response direct poll missed event.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-direct-unsubscribe", body)
        self.assertIn(
            "Dart consumer protected JSON-response direct unsubscribe was "
            "invalid.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response direct access captured "
            "state.",
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
            "dart-consumer-secure-json-active-direct-resources",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON "
            "resources missed context.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-resources-page",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON "
            "resources missed cursor.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON "
            "resources cursor page missed extra context.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-active-direct-resource-read",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct JSON "
            "resource read missed content.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-resources", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable resources "
            "missed context.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-resources-page", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable resources "
            "missed cursor.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable resources cursor "
            "page missed extra context.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-streamable-resource-read",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable resource read "
            "missed content.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-templates", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable templates "
            "missed secure task.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-templates-page", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable templates missed "
            "cursor.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable templates cursor "
            "page missed secure extra task.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-prompts", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable prompts missed "
            "secure prompt.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-prompts-page", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable prompts missed "
            "cursor.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable prompts cursor "
            "page missed secure extra prompt.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-prompt-get", body)
        self.assertIn("active JSON-response Streamable prompt readiness", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable prompt missed "
            "substitution.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable WAMP and "
            "resource/prompt helpers changed session state.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-subscribe", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable subscription was "
            "invalid.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-publish", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable publish was "
            "invalid.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-poll", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable poll missed "
            "event.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-unsubscribe", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable unsubscribe was "
            "invalid.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response pubsub captured SSE state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-streamable-batch-resource-read",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable batch count "
            "changed.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable batch missed "
            "content.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-json-streamable-batch-bad-method",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable batch missed "
            "error isolation.",
            body,
        )
        self.assertIn("dart-consumer-secure-json-streamable-batch-tools", body)
        self.assertIn(
            "Dart consumer protected JSON-response Streamable batch missed "
            "tools.",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response batch captured SSE state.",
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
        self.assertIn("dart-consumer-secure-procedure-catalog", body)
        self.assertIn(
            "Dart consumer missed protected direct JSON procedure catalog.",
            body,
        )
        self.assertIn("dart-consumer-secure-procedure-describe", body)
        self.assertIn(
            "Dart consumer missed protected direct JSON procedure metadata.",
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
        self.assertIn("dart-consumer-secure-direct-batch-resource-read", body)
        self.assertIn(
            "Dart consumer protected direct JSON batch response count changed.",
            body,
        )
        self.assertIn(
            "Dart consumer protected direct JSON batch resource missed content.",
            body,
        )
        self.assertIn("dart-consumer-secure-direct-batch-bad-method", body)
        self.assertIn(
            "Dart consumer protected direct JSON batch missed method error "
            "isolation.",
            body,
        )
        self.assertIn("dart-consumer-secure-direct-batch-tools", body)
        self.assertIn(
            "Dart consumer protected direct JSON batch missed pubsub tool.",
            body,
        )
        self.assertIn(
            "Dart consumer protected direct JSON batch changed Streamable "
            "state.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-resources", body)
        self.assertIn(
            "Dart consumer protected Streamable resources missed context.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-templates", body)
        self.assertIn(
            "Dart consumer protected Streamable templates missed secure task.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-prompts", body)
        self.assertIn(
            "Dart consumer protected Streamable prompts missed secure prompt.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-prompt-get", body)
        self.assertIn("protected Streamable prompt readiness", body)
        self.assertIn(
            "Dart consumer protected Streamable prompt missed substitution.",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable resource/prompt helpers lost "
            "SSE state.",
            body,
        )
        self.assertIn(
            "dart-consumer-secure-streamable-batch-resource-read",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable batch response count changed.",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable batch resource missed content.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-batch-bad-method", body)
        self.assertIn(
            "Dart consumer protected Streamable batch missed method error "
            "isolation.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-batch-tools", body)
        self.assertIn(
            "Dart consumer protected Streamable batch missed pubsub tool.",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable batch changed session id.",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable batch did not advance SSE "
            "state.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-procedure-catalog", body)
        self.assertIn(
            "Dart consumer missed protected Streamable procedure catalog.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-procedure-describe", body)
        self.assertIn(
            "Dart consumer missed protected Streamable procedure metadata.",
            body,
        )
        self.assertIn("dart-consumer-secure-streamable-topic-describe", body)
        self.assertIn(
            "Dart consumer missed protected Streamable topic metadata.",
            body,
        )
        self.assertIn(
            "Dart consumer protected Streamable WAMP metadata lost SSE state.",
            body,
        )
        self.assertIn("tool calls/resources/resource templates/prompts", body)
        self.assertIn("assert_router_cli_consumer_package_summary", script)
        self.assertIn('dart_consumer_summary="$(', body)
        self.assertIn("routerCliConsumerSummary", body)
        self.assertIn(
            '"public":{"directJson":true,"streamable":true,'
            '"streamableSessionDelete":true,'
            '"resourcesPrompts":true,"wampMeta":true,'
            '"pubsub":true,"batch":true}',
            body,
        )
        self.assertIn(
            '"secure":{"ticketGrant":true,"directJson":true,'
            '"streamable":true,"streamableSessionDelete":true,'
            '"resourcesPrompts":true,'
            '"pubsub":true,"wampMeta":true,'
            '"batch":true,'
            '"authRejectionIsolation":true,"refreshAndRevoke":true}',
            body,
        )
        self.assertIn(
            '"jsonResponse":{"active":{"directJson":true,'
            '"streamable":true,"streamableSessionDelete":true,'
            '"resourcesPrompts":true,"wampMeta":true,'
            '"registrationMeta":true,"configuredRegistrationMeta":true,'
            '"sessionMeta":true,'
            '"subscriptionMeta":true,"configuredSubscriptionMeta":true,'
            '"pubsub":true,"batch":true,'
            '"authRejectionIsolation":true,'
            '"refreshAndRevoke":true},'
            '"tokenOnly":{"directJson":true,'
            '"streamable":true,"streamableSessionDelete":true,'
            '"resourcesPrompts":true,"wampMeta":true,'
            '"registrationMeta":true,"configuredRegistrationMeta":true,'
            '"sessionMeta":true,'
            '"subscriptionMeta":true,"configuredSubscriptionMeta":true,'
            '"pubsub":true,"pubsubNotifications":true,"batch":true}}',
            body,
        )
        self.assertIn(
            '"tokenOnly":{"directJson":true,"streamable":true,'
            '"streamableSessionDelete":true,'
            '"resourcesPrompts":true,"wampMeta":true,'
            '"registrationMeta":true,"configuredRegistrationMeta":true,'
            '"sessionMeta":true,'
            '"subscriptionMeta":true,"configuredSubscriptionMeta":true,'
            '"pubsub":true,"pubsubNotifications":true,"batch":true}',
            body,
        )
        self.assertIn("streamableSessionDelete", body)
        self.assertIn("pubsubNotifications", body)
        self.assertIn("Dart consumer public Streamable delete leaked state.", body)
        self.assertIn(
            "Dart consumer token-only JSON-response delete leaked state.",
            body,
        )
        self.assertIn("Dart consumer token-only secure delete leaked state.", body)
        self.assertIn("Dart consumer protected Streamable delete leaked state.", body)
        self.assertIn("Dart consumer refreshed Streamable delete leaked state.", body)
        self.assertIn("_expectNotificationPubSub", body)
        self.assertIn("notifyWampEventDirect", body)
        self.assertIn("notifyWampEvent(topic", body)
        self.assertIn(
            "public raw JSON resources/resource templates/prompts/WAMP "
            "procedure and topic catalog/describe/pub-sub plus Streamable "
            "procedure and topic describe/pub-sub/session delete",
            body,
        )
        self.assertIn("configured subscription meta", body)
        self.assertIn("configured registration", body)
        self.assertIn("_expectConfiguredWampRegistrationMeta", body)
        self.assertIn("_expectConfiguredWampSubscriptionMeta", body)
        self.assertIn(
            "Dart consumer protected JSON-response active direct configured "
            "WAMP registration meta",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response active direct WAMP "
            "subscription meta",
            body,
        )
        self.assertIn(
            "Dart consumer protected JSON-response Streamable configured "
            "WAMP subscription meta",
            body,
        )
        self.assertIn(
            "idPrefix: 'dart-consumer-secure-json-active-direct'",
            body,
        )
        self.assertIn(
            "idPrefix: 'dart-consumer-secure-json-streamable'",
            body,
        )
        self.assertIn("$idPrefix-wamp-subscription-lookup", body)
        self.assertIn(
            "active protected JSON-response auth rejection/refresh-revoke, "
            "direct JSON procedure catalog/describe/topic/registration/"
            "configured registration/session/subscription/configured "
            "subscription/resource list pagination/read/resource template "
            "pagination/prompt pagination/pub-sub/batch isolation, and "
            "Streamable resource list pagination/read/resource template "
            "pagination/prompt pagination plus procedure/topic/registration/"
            "configured registration/session/subscription/configured "
            "subscription metadata/pub-sub/batch/session delete",
            body,
        )
        self.assertIn(
            "token-only protected JSON-response "
            "tool calls/resources/resource templates/prompts/WAMP "
            "procedure catalog/describe/registration/configured "
            "registration/session/subscription/configured subscription "
            "meta/pubsub/notification pubsub/batches plus Streamable "
            "procedure catalog/describe/topic describe/session delete",
            body,
        )
        self.assertIn(
            "token-only protected tool calls/resources/resource "
            "templates/prompts/WAMP registration/configured "
            "registration/session/subscription/configured subscription "
            "meta/notification pubsub/batches plus Streamable session delete",
            body,
        )
        self.assertIn("active protected auth rejection isolation", body)
        self.assertIn(
            "active protected direct JSON WAMP meta and resource/prompt isolation",
            body,
        )
        self.assertIn(
            "protected raw JSON resources/resource templates/prompts/WAMP "
            "procedure and topic describe/pub-sub/batches plus Streamable "
            "resources/resource templates/prompts/procedure and topic "
            "describe/pub-sub/batches/session delete",
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
            "ConnectanumHttpAuthClient",
            "ConnectanumHttpAuthException",
            "McpStreamableHttpException",
            "_runAuthLifecycleSmoke",
            "issueTicketToken(",
            "refreshToken(",
            "revokeToken(",
            "_expectMcpUnauthorized",
            "_expectAuthRefreshUnauthorized",
            "auth-lifecycle-refreshed-direct-ping",
            "auth-lifecycle-refreshed-initialize",
            "auth-lifecycle-refreshed-initialized",
            "auth-lifecycle-revoked-direct-ping",
            "authLifecycle",
            "revokedAccessRejected",
            "revokedRefreshRejected",
            "Use --auth-lifecycle-smoke together with --auth-url.",
            "--auth-lifecycle-smoke",
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
            "pingDirect",
            "direct-ping",
            "directPing",
            "listToolsDirect",
            "callToolDirect",
            "notifyToolDirect",
            "listConnectanumToolsDirect",
            "callConnectanumToolDirect",
            "notifyConnectanumToolDirect",
            "tools/list",
            "tools/call",
            "connectanum.tools.list",
            "connectanum.tool.call",
            "connectanum.pubsub.publish",
            "direct-standard-tools",
            "directStandardTools",
            "directStandardNextCursor",
            "direct-standard-tool-call",
            "directStandardToolResult",
            "direct-tools-method",
            "direct-tool-call-method",
            "direct-pubsub-publish-method",
            "direct-pubsub-method-poll",
            "direct-pubsub-notification-poll",
            "direct-pubsub-method-notification-poll",
            "direct-tool-notification-poll",
            "direct-connectanum-tool-notification-poll",
            "direct-tool-method-notification-poll",
            "streamable-tools-method",
            "streamable-tool-call-method",
            "streamable-pubsub-publish-method",
            "streamable-pubsub-method-poll",
            "streamable-pubsub-notification-poll",
            "streamable-pubsub-method-notification-poll",
            "streamable-tool-notification-poll",
            "streamable-tool-method-notification-poll",
            "streamable-wamp-procedure-api-list-method",
            "streamable-wamp-procedure-api-describe-method",
            "streamable-wamp-topic-api-list-method",
            "streamable-wamp-topic-api-describe-method",
            "_expectToolResultSucceeded",
            "_canObserveExampleTaskLookup",
            "_taskLookupEvent",
            "directToolMethodCatalog",
            "directToolMethodResult",
            "toolMethodCatalog",
            "toolMethodResult",
            "methodPublication",
            "methodEvents",
            "notificationEvents",
            "methodNotificationEvents",
            "toolNotificationEvents",
            "connectanumToolNotificationEvents",
            "toolMethodNotificationEvents",
            "methodCatalog",
            "methodDescription",
            "listResourcesDirect",
            "listResourceTemplatesDirect",
            "readResourceDirect",
            "listPromptsDirect",
            "getPromptDirect",
            "postDirect",
            "direct-resource-list-method",
            "direct-resource-templates-method",
            "direct-resource-read-method",
            "direct-prompts-method",
            "direct-prompt-get-method",
            "directResourceMethodResources",
            "directResourceMethodTemplates",
            "directResourceMethodContent",
            "directPromptMethodCatalog",
            "directPromptMethod",
            "postBatchDirect",
            "direct-batch-standard-tools",
            "direct-batch-standard-tool-call",
            "direct-batch-tools",
            "direct-batch-tool-call",
            "direct-batch-resources",
            "direct-batch-resource-templates",
            "direct-batch-prompts",
            "direct-batch-wamp-procedure-api-list",
            "directBatch",
            "_expectBatchCatalogContains",
            "_batchResult",
            "_responseResult",
            "had a non-object result",
            "countWampSessionsDirect",
            "listWampApiDirect",
            "callConnectanumMethodDirect",
            "connectanum.api.list",
            "connectanum.api.describe",
            "direct-wamp-procedure-api-list-method",
            "direct-wamp-procedure-api-describe-method",
            "direct-wamp-topic-api-list-method",
            "direct-wamp-topic-api-describe-method",
            "_structuredContentFromToolResult",
            "_expectWampCatalogContains",
            "_wampCatalogContainsUri",
            "_expectCatalogContainsValue",
            "_catalogContainsValue",
            "_expectStreamableStateUnchanged",
            "_expectInvalidLastEventIdRejected",
            "_expectWampSubscription",
            "_expectWampPublication",
            "_expectWampEventBatch",
            "$label changed Streamable state.",
            "router-hosted-client-streamable-invalid-last-event-id",
            "Streamable invalid Last-Event-ID was accepted.",
            "Streamable invalid Last-Event-ID returned",
            "Streamable invalid Last-Event-ID rejection did not name the header.",
            "label: 'Streamable invalid Last-Event-ID'",
            "invalidLastEventId",
            "sessionUnchanged",
            "catalog did not include $uri.",
            "catalog did not include $value.",
            "returned subscription for",
            "returned an empty subscription handle",
            "returned queue limit",
            "returned publication for",
            "did not acknowledge publication",
            "acknowledged publication without a publication id",
            "returned events for handle",
            "reported ${events.dropped} dropped pub/sub events",
            "left ${events.remaining} pub/sub events queued",
            "Published event was not observed on $label topic",
            "label: 'Direct JSON'",
            "label: 'Direct JSON batch'",
            "label: 'Direct WAMP metadata'",
            "label: 'Direct standard tool'",
            "label: 'Direct standard tool call'",
            "label: 'Direct tool'",
            "label: 'Direct tool method list'",
            "label: 'Direct tool call'",
            "label: 'Direct tool method call'",
            "label: 'Streamable tool method list'",
            "label: 'Streamable tool call'",
            "label: 'Streamable tool method call'",
            "label: 'Direct resource'",
            "label: 'Direct JSON resource method list'",
            "label: 'Direct JSON resource template method list'",
            "label: 'Direct JSON resource method read'",
            "label: 'Direct prompt'",
            "label: 'Direct JSON prompt method list'",
            "label: 'Direct JSON prompt method get'",
            "label: 'Direct JSON batch standard tool'",
            "label: 'Direct JSON batch tool'",
            "label: 'Direct JSON batch resource'",
            "label: 'Direct JSON batch prompt'",
            "label: 'Direct WAMP procedure'",
            "label: 'Direct WAMP procedure method'",
            "label: 'Direct WAMP procedure method describe'",
            "label: 'Direct WAMP topic'",
            "label: 'Direct WAMP topic method'",
            "label: 'Direct WAMP topic method describe'",
            "label: 'Streamable WAMP procedure method list'",
            "label: 'Streamable WAMP procedure method describe'",
            "label: 'Streamable WAMP topic method list'",
            "label: 'Streamable WAMP topic method describe'",
            "label: 'Direct JSON pub/sub'",
            "label: 'Direct JSON pub/sub method publish'",
            "label: 'Direct JSON pub/sub method poll'",
            "label: 'Direct JSON pub/sub notification poll'",
            "label: 'Direct JSON pub/sub method notification poll'",
            "label: 'Direct JSON standard tool notification poll'",
            "label: 'Direct JSON Connectanum tool notification poll'",
            "label: 'Direct JSON tool method notification poll'",
            "returned an error",
            "returned no structured content",
            "label: 'Streamable pub/sub method publish'",
            "label: 'Streamable pub/sub method poll'",
            "label: 'Streamable pub/sub notification poll'",
            "label: 'Streamable pub/sub method notification poll'",
            "label: 'Streamable standard tool notification poll'",
            "label: 'Streamable tool method notification poll'",
            "describeWampApiDirect",
            "matchWampRegistrationDirect",
            "matchWampSubscriptionDirect",
            "lookupWampSubscriptionDirect",
            "listWampSubscriptionsDirect",
            "getWampSubscriptionDirect",
            "listWampSubscriptionSubscribersDirect",
            "countWampSubscriptionSubscribersDirect",
            "subscribeWampTopicDirect",
            "publishWampEventDirect",
            "notifyWampEventDirect",
            "notifyConnectanumMethodDirect",
            "pollWampEventsDirect",
            "unsubscribeWampTopicDirect",
            "initialize",
            "notifyInitialized",
            "router-hosted-client-streamable-initialized",
            "Streamable initialized notification changed session id.",
            "initializedNotification",
            "ping(",
            "streamable-ping",
            "Streamable ping changed session id.",
            "poll(",
            "postBatch(",
            "streamable-batch-tools",
            "streamable-batch-tool-call",
            "'ping': ping",
            "label: 'Streamable tool'",
            "label: 'Streamable batch tool'",
            "listResources(",
            "streamable-resources",
            "streamable-batch-resources",
            "streamable-resource-list-method",
            "streamable-resource-templates-method",
            "streamable-resource-read-method",
            "label: 'Streamable resource'",
            "label: 'Streamable resource method list'",
            "label: 'Streamable resource template method list'",
            "label: 'Streamable resource method read'",
            "label: 'Streamable batch resource'",
            "resources",
            "resourceMethods",
            "streamable-batch-wamp-procedure-api-list",
            "'batch'",
            "callTool",
            "notifyTool",
            "streamable-tool-call",
            "toolResult",
            "Streamable tool notification changed session id.",
            "Streamable tool method notification changed session id.",
            "listResourceTemplates(",
            "streamable-resource-templates",
            "streamable-batch-resource-templates",
            "resourceTemplates",
            "listPrompts(",
            "streamable-prompts",
            "streamable-batch-prompts",
            "streamable-prompts-method",
            "streamable-prompt-get-method",
            "label: 'Streamable prompt'",
            "label: 'Streamable prompt method list'",
            "label: 'Streamable prompt method get'",
            "label: 'Streamable batch prompt'",
            "prompts",
            "promptMethods",
            "label: 'Streamable pub/sub'",
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
            "lookupWampRegistration(",
            "streamable-wamp-configured-registration-lookup",
            "listWampRegistrations(",
            "streamable-wamp-configured-registration-list",
            "getWampRegistration(",
            "streamable-wamp-configured-registration-get",
            "listWampRegistrationCallees(",
            "streamable-wamp-configured-registration-callees",
            "countWampRegistrationCallees(",
            "streamable-wamp-configured-registration-callee-count",
            "matchWampSubscription(",
            "streamable-wamp-subscription-match",
            "lookupWampSubscription(",
            "streamable-wamp-configured-subscription-lookup",
            "listWampSubscriptions(",
            "streamable-wamp-configured-subscription-list",
            "getWampSubscription(",
            "streamable-wamp-configured-subscription-get",
            "listWampSubscriptionSubscribers(",
            "streamable-wamp-configured-subscription-subscribers",
            "countWampSubscriptionSubscribers(",
            "streamable-wamp-configured-subscription-subscriber-count",
            "wampMetadata",
            "subscriptionMetadata",
            "configuredRegistrationMetadata",
            "configuredSubscriptionMetadata",
            "subscribeWampTopic",
            "streamable-pubsub-subscribe",
            "publishWampEvent",
            "notifyWampEvent",
            "notifyConnectanumMethod",
            "streamable-pubsub-publish",
            "pollWampEvents",
            "streamable-pubsub-poll",
            "unsubscribeWampTopic",
            "streamable-pubsub-unsubscribe",
            "deleteSession",
            "_deleteStreamableSession",
            "Streamable initialize did not establish a session id.",
            "Streamable session delete did not clear local session state.",
            "_nonEmptyStringOption",
            "_mcpToolNameOption",
            "_mcpSelectorOption",
            "_mcpResourceUriOption",
            "must be 1-128 ASCII letters",
            "must be an absolute URI with a scheme.",
            "must not contain whitespace or control characters.",
            "_printDryRunSummary",
            "--dry-run",
            "dart run connectanum_mcp:router_hosted_client",
        ):
            with self.subTest(helper=public_helper):
                self.assertIn(public_helper, example)
        self.assertNotIn(
            "dart run packages/connectanum_mcp/example/router_hosted_client.dart",
            example,
        )

    def test_public_router_hosted_server_example_publishes_task_lookup_events(
        self,
    ) -> None:
        example = ROUTER_HOSTED_SERVER_EXAMPLE.read_text(encoding="utf-8")

        for expected in (
            "'publishes_events': ['example.events.task']",
            "'procedure': 'example.task.configured.lookup'",
            "serviceSession.publish(",
            "'example.events.task'",
            "'event': 'task.lookup'",
            "PublishOptions(acknowledge: true)",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, example)

    def test_fast_smoke_runs_public_router_hosted_client_example_dry_run(
        self,
    ) -> None:
        script = COMMON_SH.read_text(encoding="utf-8")
        wrapper_body = _function_body(script, "run_router_hosted_mcp_example_smoke")
        helper_body = _function_body(
            script,
            "run_public_router_hosted_mcp_client_example_dry_run",
        )
        body = _function_body(
            script,
            "run_public_router_hosted_mcp_client_dry_run_smoke",
        )

        self.assertIn("run_command_with_timeout()", script)
        self.assertIn("CONNECTANUM_MCP_CLIENT_DRY_RUN_TIMEOUT_SECONDS:-60", helper_body)
        self.assertIn("run_command_with_timeout", helper_body)
        self.assertIn(
            "Public router-hosted MCP client dry-run",
            helper_body,
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
            "connectanum_mcp:router_hosted_client",
            helper_body,
        )
        self.assertNotIn(
            "packages/connectanum_mcp/example/router_hosted_client.dart",
            helper_body,
        )
        self.assertIn(
            "run_public_router_hosted_mcp_client_example_dry_run",
            body,
        )
        self.assertIn("--endpoint http://127.0.0.1:8080/mcp", body)
        self.assertIn("--protocol-version 2025-06-18", body)
        self.assertIn("--tool example.task.lookup", body)
        self.assertIn("--tool-arguments", body)
        self.assertIn("--resource-uri app://example/context", body)
        self.assertIn("--prompt summarize-task", body)
        self.assertIn("--prompt-arguments", body)
        self.assertIn("--wamp-procedure example.task.configured.lookup", body)
        self.assertIn("--wamp-topic example.events.task", body)
        self.assertIn("--pubsub-topic example.events.task", body)
        self.assertIn("--pubsub-event", body)
        self.assertIn("--dry-run", body)
        self.assertIn("dry_run_summary=\"$(", body)
        self.assertIn('"authMode":"none"', body)
        self.assertIn('"protocolVersion":"2025-06-18"', body)
        self.assertIn('"resourceTemplates":true', body)
        self.assertIn("resource-template discovery", body)
        self.assertIn('"configuredSubscriptionMetadata":true', body)
        self.assertIn("configured subscription metadata lookup", body)
        self.assertIn('"configuredRegistrationMetadata":true', body)
        self.assertIn("configured registration metadata lookup", body)
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
        self.assertIn("--auth-lifecycle-smoke", body)
        self.assertIn('"authLifecycleSmoke":true', body)
        self.assertIn(
            "did not report auth lifecycle smoke mode",
            body,
        )
        self.assertIn("dangling_auth_lifecycle_output=\"$(", body)
        self.assertIn(
            "accepted auth lifecycle smoke without ticket auth",
            body,
        )
        self.assertIn(
            "Use --auth-lifecycle-smoke together with --auth-url.",
            body,
        )
        self.assertIn(
            "did not report the dangling auth lifecycle smoke error",
            body,
        )
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
            "connectanum_mcp:router_hosted_client",
            live_body,
        )
        self.assertNotIn(
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
        self.assertIn(
            'mktemp "${TMPDIR:-/tmp}/connectanum-router-hosted-mcp.XXXXXX"',
            live_body,
        )
        self.assertNotIn("connectanum-router-hosted-mcp.XXXXXX.log", live_body)
        self.assertIn("auth_url=\"${endpoint%/mcp}/auth\"", live_body)
        self.assertIn("bearer_token=\"$(", live_body)
        self.assertIn("python3 - \"$auth_url\"", live_body)
        self.assertIn("\"authmethod\": \"ticket\"", live_body)
        self.assertIn(
            "assert_public_router_hosted_mcp_client_summary",
            script,
        )
        self.assertIn("live_summary=\"$(", live_body)
        self.assertIn("pubsub_only_summary=\"$(", live_body)
        self.assertIn("authenticated_summary=\"$(", live_body)
        self.assertIn("bearer_summary=\"$(", live_body)
        self.assertIn("authenticated_json_summary=\"$(", live_body)
        self.assertIn("bearer_json_summary=\"$(", live_body)
        self.assertIn(
            '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}',
            script,
        )
        self.assertIn('"directPing"', script)
        self.assertIn('"directWampMetadata"', script)
        self.assertIn('"wampMetadata"', script)
        self.assertIn('"configuredRegistrationMetadata"', script)
        self.assertIn('"configuredSubscriptionMetadata"', script)
        self.assertIn('"toolNotificationEvents"', script)
        self.assertIn("--auth-url \"$auth_url\"", live_body)
        self.assertIn("--bearer-token \"$bearer_token\"", live_body)
        self.assertIn("--realm example.realm", live_body)
        self.assertIn("--auth-id mcp-user", live_body)
        self.assertIn("--ticket mcp-demo-ticket", live_body)
        self.assertIn("--auth-lifecycle-smoke", live_body)
        self.assertIn("--tool example.task.lookup", live_body)
        self.assertIn("--resource-uri app://example/context", live_body)
        self.assertIn("--prompt summarize-task", live_body)
        self.assertIn("--wamp-procedure example.task.configured.lookup", live_body)
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
