#!/usr/bin/env python3
"""Regression checks for the packaged router MCP runtime smoke."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import unittest
from pathlib import Path
from unittest import mock


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
        self.assertIn('--secure-endpoint "http://127.0.0.1:$host_port/mcp/secure"', runner)
        self.assertIn('--auth-endpoint "http://127.0.0.1:$host_port/auth"', runner)

    def test_smoke_contract_covers_modern_and_streamable_mcp(self) -> None:
        client = CLIENT.read_text(encoding="utf-8")
        for expected in [
            'MODERN_PROTOCOL = "2026-07-28"',
            'COMPATIBILITY_PROTOCOL = "2025-11-25"',
            '"server/discover"',
            '"tools/call"',
            '"connectanum.api.list"',
            '"connectanum.pubsub.subscribe"',
            '"connectanum.pubsub.publish"',
            '"connectanum.pubsub.poll"',
            '"connectanum.pubsub.unsubscribe"',
            '"wamp.subscription.match"',
            '"wamp.subscription.get"',
            '"wamp.registration.match"',
            '"wamp.registration.get"',
            '"wamp.session.count"',
            "_run_modern_direct_pubsub(endpoint, label=\"Public\")",
            "_run_modern_standard_tool_catalog(endpoint, label=\"Public\")",
            "_run_modern_wamp_registration_session_meta(",
            "_run_modern_wamp_subscription_meta(",
            'call_mode="direct"',
            'call_mode="standard"',
            "_run_modern_direct_pubsub(",
            "_run_modern_standard_tool_catalog(",
            "label=\"Protected\"",
            'endpoint, "DELETE", headers=session_headers',
            'AUTH_ID = "image-smoke-agent"',
            'AUTH_TICKET = "image-smoke-ticket"',
            '"Authorization": f"Bearer {access_token}"',
            '"grant_type": "revoke"',
            "verify_missing_bearer=True",
            "_run_modern_standard_pubsub(endpoint, label=\"Public\")",
            "_run_modern_standard_pubsub(",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, client)

    def test_modern_standard_tool_catalog_uses_sessionless_tools_call(self) -> None:
        authorization_headers = {"Authorization": "Bearer issued-token"}
        response = {
            "result": {
                "structuredContent": {
                    "topics": [{"uri": CLIENT_MODULE.TOPIC}],
                }
            }
        }

        with mock.patch.object(
            CLIENT_MODULE,
            "_modern_call",
            return_value=response,
        ) as modern_call:
            CLIENT_MODULE._run_modern_standard_tool_catalog(
                "http://router/mcp/secure",
                label="Protected",
                authorization_headers=authorization_headers,
            )

        modern_call.assert_called_once_with(
            "http://router/mcp/secure",
            "protected-standard-catalog",
            "tools/call",
            {
                "name": "connectanum.api.list",
                "arguments": {"kind": "topic"},
            },
            headers=authorization_headers,
        )

    def test_modern_tools_call_routes_with_tool_name_header(self) -> None:
        with mock.patch.object(
            CLIENT_MODULE,
            "_post_json",
            return_value=(
                {"mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL},
                {"result": {"structuredContent": {}}},
            ),
        ) as post_json:
            CLIENT_MODULE._modern_call(
                "http://router/mcp",
                "standard-call",
                "tools/call",
                {
                    "name": "connectanum.api.list",
                    "arguments": {"kind": "topic"},
                },
            )

        self.assertEqual(
            post_json.call_args.kwargs["headers"]["Mcp-Name"],
            "connectanum.api.list",
        )

    def test_modern_wamp_subscription_meta_uses_direct_and_standard_calls(self) -> None:
        subscription_id = 9001
        responses = [
            {
                "result": {
                    "structuredContent": {"arguments": [subscription_id]},
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {
                            "id": subscription_id,
                            "uri": CLIENT_MODULE.TOPIC,
                            "match": "exact",
                        },
                    }
                }
            },
        ]
        authorization_headers = {"Authorization": "Bearer issued-token"}

        for call_mode, expected_methods in [
            (
                "direct",
                ["wamp.subscription.match", "wamp.subscription.get"],
            ),
            ("standard", ["tools/call", "tools/call"]),
        ]:
            with self.subTest(call_mode=call_mode), mock.patch.object(
                CLIENT_MODULE,
                "_modern_call",
                side_effect=responses,
            ) as modern_call:
                CLIENT_MODULE._run_modern_wamp_subscription_meta(
                    "http://router/mcp/secure",
                    label="Protected",
                    call_mode=call_mode,
                    authorization_headers=authorization_headers,
                )

            self.assertEqual(
                [call.args[2] for call in modern_call.call_args_list],
                expected_methods,
            )
            expected_arguments = [
                {"arguments": [CLIENT_MODULE.TOPIC]},
                {"arguments": [subscription_id]},
            ]
            if call_mode == "standard":
                expected_arguments = [
                    {
                        "name": tool_name,
                        "arguments": arguments,
                    }
                    for tool_name, arguments in zip(
                        ["wamp.subscription.match", "wamp.subscription.get"],
                        expected_arguments,
                    )
                ]
            self.assertEqual(
                [call.args[3] for call in modern_call.call_args_list],
                expected_arguments,
            )
            for call in modern_call.call_args_list:
                self.assertEqual(call.kwargs["headers"], authorization_headers)

    def test_modern_wamp_registration_session_meta_invokes_declared_procedure(
        self,
    ) -> None:
        registration_id = 9002
        responses = [
            {
                "result": {
                    "structuredContent": {"arguments": [registration_id]},
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {
                            "id": registration_id,
                            "uri": CLIENT_MODULE.PROCEDURE,
                            "match": "exact",
                            "invoke": "single",
                        },
                    }
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {"count": 1},
                    }
                }
            },
        ]
        authorization_headers = {"Authorization": "Bearer issued-token"}

        for call_mode, expected_methods in [
            (
                "direct",
                [
                    "wamp.registration.match",
                    "wamp.registration.get",
                    "wamp.session.count",
                ],
            ),
            ("standard", ["tools/call", "tools/call", "tools/call"]),
        ]:
            with self.subTest(call_mode=call_mode), mock.patch.object(
                CLIENT_MODULE,
                "_modern_call",
                side_effect=responses,
            ) as modern_call:
                CLIENT_MODULE._run_modern_wamp_registration_session_meta(
                    "http://router/mcp/secure",
                    label="Protected",
                    call_mode=call_mode,
                    authorization_headers=authorization_headers,
                )

            self.assertEqual(
                [call.args[2] for call in modern_call.call_args_list],
                expected_methods,
            )
            expected_arguments = [
                {"arguments": [CLIENT_MODULE.PROCEDURE]},
                {"arguments": [registration_id]},
                {},
            ]
            if call_mode == "standard":
                expected_arguments = [
                    {
                        "name": tool_name,
                        "arguments": arguments,
                    }
                    for tool_name, arguments in zip(
                        [
                            "wamp.registration.match",
                            "wamp.registration.get",
                            "wamp.session.count",
                        ],
                        expected_arguments,
                    )
                ]
            self.assertEqual(
                [call.args[3] for call in modern_call.call_args_list],
                expected_arguments,
            )
            for call in modern_call.call_args_list:
                self.assertEqual(call.kwargs["headers"], authorization_headers)

    def test_modern_standard_pubsub_uses_sessionless_tool_calls(self) -> None:
        marker = "router-image-protected-standard-publish"
        responses = [
            {
                "result": {
                    "structuredContent": {
                        "handle": "standard-handle",
                        "topic": CLIENT_MODULE.TOPIC,
                    }
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "topic": CLIENT_MODULE.TOPIC,
                        "acknowledged": True,
                    }
                }
            },
            {"result": {"structuredContent": {"events": [{"via": marker}]}}},
            {"result": {"structuredContent": {"unsubscribed": True}}},
        ]
        authorization_headers = {"Authorization": "Bearer issued-token"}

        with mock.patch.object(
            CLIENT_MODULE,
            "_modern_call",
            side_effect=responses,
        ) as modern_call:
            CLIENT_MODULE._run_modern_standard_pubsub(
                "http://router/mcp/secure",
                label="Protected",
                authorization_headers=authorization_headers,
            )

        self.assertEqual(
            [call.args[2] for call in modern_call.call_args_list],
            ["tools/call"] * 4,
        )
        self.assertEqual(
            [call.args[3]["name"] for call in modern_call.call_args_list],
            [
                "connectanum.pubsub.subscribe",
                "connectanum.pubsub.publish",
                "connectanum.pubsub.poll",
                "connectanum.pubsub.unsubscribe",
            ],
        )
        self.assertEqual(
            modern_call.call_args_list[0].args[3]["arguments"],
            {"topic": CLIENT_MODULE.TOPIC, "queueLimit": 5},
        )
        for call in modern_call.call_args_list:
            self.assertEqual(call.kwargs["headers"], authorization_headers)

    def test_ticket_grant_flow_uses_challenge_state_and_signature(self) -> None:
        challenge = {"state": "challenge-state", "challenge": {}}
        grant = {
            "access_token": "issued-access-token",
            "token_type": "Bearer",
            "refresh_token": "issued-refresh-token",
        }
        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(401, {}, json.dumps(challenge)),
        ) as request, mock.patch.object(
            CLIENT_MODULE,
            "_post_json",
            return_value=({}, grant),
        ) as post_json:
            result = CLIENT_MODULE._issue_ticket_grant("http://router/auth")

        self.assertEqual(result, grant)
        request.assert_called_once_with(
            "http://router/auth",
            "POST",
            {
                "realm": "image.smoke",
                "authmethod": "ticket",
                "authid": "image-smoke-agent",
            },
            allow_http_error=True,
        )
        post_json.assert_called_once_with(
            "http://router/auth",
            {"state": "challenge-state", "signature": "image-smoke-ticket"},
        )

    def test_modern_direct_pubsub_uses_sessionless_modern_calls(self) -> None:
        marker = "router-image-protected-direct-publish"
        responses = [
            {
                "result": {
                    "structuredContent": {
                        "handle": "direct-handle",
                        "topic": CLIENT_MODULE.TOPIC,
                    }
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "topic": CLIENT_MODULE.TOPIC,
                        "acknowledged": True,
                    }
                }
            },
            {"result": {"structuredContent": {"events": [{"via": marker}]}}},
            {"result": {"structuredContent": {"unsubscribed": True}}},
        ]
        authorization_headers = {"Authorization": "Bearer issued-token"}

        with mock.patch.object(
            CLIENT_MODULE,
            "_modern_call",
            side_effect=responses,
        ) as modern_call:
            CLIENT_MODULE._run_modern_direct_pubsub(
                "http://router/mcp/secure",
                label="Protected",
                authorization_headers=authorization_headers,
            )

        self.assertEqual(
            [call.args[2] for call in modern_call.call_args_list],
            [
                "connectanum.pubsub.subscribe",
                "connectanum.pubsub.publish",
                "connectanum.pubsub.poll",
                "connectanum.pubsub.unsubscribe",
            ],
        )
        for call in modern_call.call_args_list:
            self.assertEqual(call.kwargs["headers"], authorization_headers)

    def test_compatibility_pubsub_uses_standard_tool_call_envelopes(self) -> None:
        marker = "router-image-public-streamable-publish"
        responses = [
            (
                {"mcp-session-id": "compatibility-session"},
                {
                    "result": {
                        "protocolVersion": CLIENT_MODULE.COMPATIBILITY_PROTOCOL,
                    }
                },
            ),
            (
                {},
                {
                    "result": {
                        "structuredContent": {
                            "handle": "compatibility-handle",
                            "topic": CLIENT_MODULE.TOPIC,
                        }
                    }
                },
            ),
            (
                {},
                {
                    "result": {
                        "structuredContent": {
                            "topic": CLIENT_MODULE.TOPIC,
                            "acknowledged": True,
                        }
                    }
                },
            ),
            (
                {},
                {
                    "result": {
                        "structuredContent": {"events": [{"via": marker}]},
                    }
                },
            ),
            (
                {},
                {"result": {"structuredContent": {"unsubscribed": True}}},
            ),
        ]
        request_responses = [
            (202, {}, ""),
            (202, {"mcp-session-id": "compatibility-session"}, ""),
        ]

        with mock.patch.object(
            CLIENT_MODULE,
            "_post_json",
            side_effect=responses,
        ) as post_json, mock.patch.object(
            CLIENT_MODULE,
            "_request",
            side_effect=request_responses,
        ):
            CLIENT_MODULE._run_compatibility_pubsub(
                "http://router/mcp",
                label="Public",
            )

        tool_payloads = [call.args[1] for call in post_json.call_args_list[1:]]
        self.assertEqual(
            [payload["method"] for payload in tool_payloads],
            ["tools/call"] * 4,
        )
        self.assertEqual(
            [payload["params"]["name"] for payload in tool_payloads],
            [
                "connectanum.pubsub.subscribe",
                "connectanum.pubsub.publish",
                "connectanum.pubsub.poll",
                "connectanum.pubsub.unsubscribe",
            ],
        )
        self.assertEqual(
            tool_payloads[0]["params"]["arguments"],
            {"topic": CLIENT_MODULE.TOPIC, "queueLimit": 5},
        )

    def test_neutral_config_exposes_public_mcp_and_declared_topic(self) -> None:
        config = CONFIG.read_text(encoding="utf-8")
        for expected in [
            "endpoint: 0.0.0.0:8080",
            "path: /mcp",
            "path: /auth",
            "path: /mcp/secure",
            "type: mcp",
            "type: auth",
            "name: image-smoke-auth",
            "authmethods: [anonymous, ticket]",
            "allow_insecure_transport: true",
            "include_standard_meta_api: true",
            "include_pubsub_tools: true",
            "topic: image.smoke.events",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, config)
        self.assertEqual(config.count("procedure: wamp.session.count"), 2)

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
