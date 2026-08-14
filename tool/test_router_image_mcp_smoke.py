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
OFFICIAL_CLIENT = REPO_ROOT / "tool" / "smoke_official_mcp_client.mjs"
CONFIG = REPO_ROOT / "deploy" / "docker" / "router_mcp_smoke.yaml"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "router-image.yml"
DOCKERFILE = REPO_ROOT / "deploy" / "docker" / "Dockerfile"

CLIENT_SPEC = importlib.util.spec_from_file_location("router_image_mcp_smoke", CLIENT)
assert CLIENT_SPEC is not None and CLIENT_SPEC.loader is not None
CLIENT_MODULE = importlib.util.module_from_spec(CLIENT_SPEC)
CLIENT_SPEC.loader.exec_module(CLIENT_MODULE)


class RouterImageMcpSmokeTest(unittest.TestCase):
    def test_dockerfile_builds_hook_aware_cli_bundle(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        self.assertIn("dart build cli", dockerfile)
        self.assertIn(
            "--target=packages/connectanum_router/bin/connectanum_router.dart",
            dockerfile,
        )
        self.assertIn("--output=/out", dockerfile)
        self.assertIn(
            "COPY --from=dart-builder /out/bundle/bin/connectanum_router",
            dockerfile,
        )
        self.assertNotIn("dart compile exe", dockerfile)

    def test_sse_parser_accepts_leading_event_id(self) -> None:
        payload = CLIENT_MODULE._json_payload(
            'event: heartbeat\ndata:\n\n'
            'id: session-1:1\nevent: message\ndata: {"jsonrpc":"2.0","id":1}\n\n'
        )
        self.assertEqual(payload, {"jsonrpc": "2.0", "id": 1})

    def test_json_response_parser_requires_unframed_application_json(self) -> None:
        response_body = json.dumps(
            {"jsonrpc": "2.0", "id": "json-response", "result": {}}
        )
        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(
                200,
                {"content-type": "application/json; charset=utf-8"},
                response_body,
            ),
        ) as request:
            headers, payload = CLIENT_MODULE._post_json_response(
                "http://router/mcp/secure-json",
                {"jsonrpc": "2.0", "id": "json-response", "method": "ping"},
                headers={"MCP-Protocol-Version": "2025-11-25"},
            )

        self.assertEqual(headers["content-type"], "application/json; charset=utf-8")
        self.assertEqual(payload["result"], {})
        request.assert_called_once()

        for content_type, body, message in [
            (
                "text/event-stream",
                f"event: message\ndata: {response_body}\n\n",
                "not application/json",
            ),
            (
                "application/json",
                f"data: {response_body}\n\n",
                "SSE framing",
            ),
        ]:
            with self.subTest(content_type=content_type, message=message):
                with mock.patch.object(
                    CLIENT_MODULE,
                    "_request",
                    return_value=(200, {"content-type": content_type}, body),
                ):
                    with self.assertRaisesRegex(AssertionError, message):
                        CLIENT_MODULE._post_json_response(
                            "http://router/mcp/secure-json",
                            {
                                "jsonrpc": "2.0",
                                "id": "json-response",
                                "method": "ping",
                            },
                        )

    def test_initialize_notifications_cannot_create_compatibility_sessions(
        self,
    ) -> None:
        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(
                202,
                {"mcp-protocol-version": "2025-11-25"},
                "",
            ),
        ) as request:
            CLIENT_MODULE._expect_initialize_notification_sessionless(
                "http://router/mcp",
                label="Public",
            )

        payload = request.call_args.args[2]
        self.assertEqual(payload["method"], "initialize")
        self.assertNotIn("id", payload)

        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(
                202,
                {"mcp-session-id": "unexpected-session"},
                "",
            ),
        ):
            with self.assertRaisesRegex(AssertionError, "created a session"):
                CLIENT_MODULE._expect_initialize_notification_sessionless(
                    "http://router/mcp",
                    label="Public",
                )

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

    def test_shell_runner_exercises_public_package_client_against_image(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        for expected in [
            "for command_name in docker python3 dart node npm; do",
            'mcp_client_command="router_hosted_client"',
            'mcp_compatibility_protocol_version="2025-11-25"',
            'mcp_modern_protocol_version="2026-07-28"',
            'mcp_tool="connectanum.api.list"',
            'mcp_tool_arguments=\'{"kind":"procedure"}\'',
            'mcp_procedure="wamp.session.count"',
            'mcp_topic="image.smoke.events"',
            'mcp_resource_uri="connectanum://router-image/context"',
            'mcp_resource_template="connectanum://router-image/item/{itemId}"',
            'mcp_resource_template_variables=',
            'mcp_expanded_resource_template_uri=',
            'mcp_prompt_name="inspect-router-image"',
            'mcp_prompt_arguments=',
            'CONNECTANUM_SKIP_NATIVE_BUILD=true',
            'PUB_CACHE="$mcp_client_pub_cache" "$mcp_client_command"',
            '--tool "$mcp_tool"',
            '--tool-arguments "$mcp_tool_arguments"',
            '--wamp-procedure "$mcp_procedure"',
            '--wamp-topic "$mcp_topic"',
            '--resource-uri "$mcp_resource_uri"',
            '--resource-template "$mcp_resource_template"',
            '--resource-template-variables "$mcp_resource_template_variables"',
            '--prompt "$mcp_prompt_name"',
            '--prompt-arguments "$mcp_prompt_arguments"',
            '--pubsub-topic "$mcp_topic"',
            '"directResources"',
            '"directResourceTemplates"',
            '"directResourceTemplateExpansion"',
            '"directPrompts"',
            '"directPrompt"',
            '"directWampMetadata"',
            '"configuredRegistrationMetadata"',
            '"configuredSubscriptionMetadata"',
            '"activeDirectJson"',
            '"streamable"',
            '"resourceTemplates"',
            '"resourceTemplateExpansion"',
            "pagesRead",
            '\\"directStandardToolPagesRead\\":$tool_pages',
            '\\"directToolPagesRead\\":$tool_pages',
            '\\"directToolMethodPagesRead\\":$tool_pages',
            '\\"activeDirectToolPagesRead\\":$tool_pages',
            '\\"activeDirectToolMethodPagesRead\\":$tool_pages',
            '\\"streamableToolPagesRead\\":$tool_pages',
            '\\"streamableToolMethodPagesRead\\":$tool_pages',
            '\\"directResourcePagesRead\\":$resource_pages',
            '\\"directPromptPagesRead\\":$prompt_pages',
            '\\"streamableResourcePagesRead\\":$resource_pages',
            '\\"streamablePromptPagesRead\\":$prompt_pages',
            '"resourceTemplateRead":true',
            '"resourceContent"',
            '"prompts"',
            '"prompt"',
            '"pubsub"',
            'run_package_client_smoke "Public"',
            'run_package_client_smoke "Protected"',
            '--auth-url "http://127.0.0.1:$host_port/auth"',
            '--realm image.smoke',
            '--auth-id image-smoke-agent',
            '--ticket image-smoke-ticket',
            "--auth-lifecycle-smoke",
            '"authLifecycle"',
            'run_stateless_package_client_smoke "Public"',
            'run_stateless_package_client_smoke "Protected"',
            '"modernBatchUnsupported"',
            '"stateless"',
            '"sessionless":true',
            '"refreshedSessionless":true',
            '"refreshedRequestScopedResourceSubscription"',
            '"supportedVersions"',
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, runner)

        self.assertEqual(runner.count("--auth-lifecycle-smoke"), 4)

    def test_shell_runner_uses_pinned_official_mcp_client(self) -> None:
        syntax = subprocess.run(
            ["node", "--check", str(OFFICIAL_CLIENT)],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stdout)

        runner = RUNNER.read_text(encoding="utf-8")
        client = OFFICIAL_CLIENT.read_text(encoding="utf-8")
        for expected in [
            'official_mcp_client_version="2.0.0"',
            '"@modelcontextprotocol/client@$official_mcp_client_version"',
            "--ignore-scripts",
            "run_official_mcp_client_smoke \\",
            '"http://127.0.0.1:$host_port/mcp/secure"',
            '"http://127.0.0.1:$host_port/auth"',
            '"sdk":"@modelcontextprotocol/client@2.0.0"',
            "public=true protected=true bearer_retry=true",
            "legacy_session=true legacy_terminated=true modern_sessionless=true",
            "resource_template_read=true",
            "resource_template_subscribe=true resource_template_update=true",
            "resource_template_unsubscribe=true",
            "instructions=true prompt_get=true",
            "pubsub=true explicit_handle=true structured_content=true",
            "OFFICIAL_MCP_AUTH_TICKET=image-smoke-ticket",
            "'using router image context'",
            "'Neutral router image MCP runtime smoke endpoint.'",
            "Official MCP client smoke exposed sensitive material.",
            'rm -rf -- "$official_mcp_client_workspace"',
        ]:
            with self.subTest(runner_expected=expected):
                self.assertIn(expected, runner)

        for expected in [
            "from '@modelcontextprotocol/client'",
            "new StreamableHTTPClientTransport(",
            "versionNegotiation: { mode: 'auto' }",
            "async function issueTicketGrant(",
            "async function runProtectedClient(",
            "onUnauthorized: async ({ response }) =>",
            "authState.currentToken = accessToken",
            "process.env.OFFICIAL_MCP_AUTH_TICKET",
            "await transport.terminateSession()",
            "await client.listTools()",
            "await client.listPrompts()",
            "await client.listResources()",
            "await client.listResourceTemplates()",
            "await client.readResource(",
            "resourceTemplateRead: true",
            "async function runResourceTemplateSubscription(",
            "await client.subscribeResource({ uri: resourceUri })",
            "await client.listen({",
            "resourceSubscriptions: [resourceUri]",
            "modernSubscription.honoredFilter.resourceSubscriptions",
            "'notifications/resources/updated'",
            "await client.unsubscribeResource({ uri: resourceUri })",
            "await modernSubscription.close()",
            "resourceTemplateSubscribed: true",
            "resourceTemplateUpdateReceived: true",
            "resourceTemplateUnsubscribed: true",
            "client.getInstructions()",
            "await client.getPrompt(",
            "await client.callTool(",
            "'connectanum.pubsub.subscribe'",
            "'connectanum.pubsub.publish'",
            "'connectanum.pubsub.poll'",
            "'connectanum.pubsub.unsubscribe'",
            "result.structuredContent",
            "exclude_me: false",
            "pubSubHandleReturned: true",
            "pubSubPublishAcknowledged: true",
            "pubSubEventReceived: true",
            "pubSubUnsubscribed: true",
            "instructionsReceived: true",
            "promptRendered: true",
            "legacy negotiation did not establish a Streamable HTTP session",
            "legacy Streamable HTTP session was not terminated",
            "modern negotiation unexpectedly established a compatibility session",
        ]:
            with self.subTest(client_expected=expected):
                self.assertIn(expected, client)

    def test_shell_runner_exercises_protected_json_response_package_client(
        self,
    ) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        client = CLIENT.read_text(encoding="utf-8")
        config = CONFIG.read_text(encoding="utf-8")

        for expected in [
            "path: /mcp/secure-json",
            "post_response_transport: json",
        ]:
            with self.subTest(config_expected=expected):
                self.assertIn(expected, config)

        for expected in [
            '--json-response-endpoint "http://127.0.0.1:$host_port/mcp/secure-json"',
            'run_stateless_package_client_smoke "Protected JSON-response"',
            'run_package_client_smoke "Protected JSON-response"',
            'lifecycle_evidence+=" post_response=json"',
            'post_response=json post_sse_cursor=false',
        ]:
            with self.subTest(runner_expected=expected):
                self.assertIn(expected, runner)

        for expected in [
            "_run_protected_json_response_smoke(",
            'content_type.split(";", 1)[0].strip().lower() != "application/json"',
            '"json_response_ready=true protected=true compatibility_json=true "',
            '"protocol_header=true session_header=true session_delete=true "',
        ]:
            with self.subTest(client_expected=expected):
                self.assertIn(expected, client)

    def test_shell_runner_uses_isolated_global_package_activation(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        for expected in [
            'mcp_client_command="router_hosted_client"',
            'mcp_client_workspace="$(mktemp -d',
            'mcp_client_pub_cache="$(mktemp -d',
            "name: connectanum_mcp_router_image_smoke_workspace",
            "workspace:",
            "connectanum_core",
            "connectanum_client",
            "connectanum_mcp",
            "dart pub global activate --source path",
            'command -v "$mcp_client_command"',
            'PUB_CACHE="$mcp_client_pub_cache" "$mcp_client_command"',
            "client=globally-activated",
            'rm -rf -- "$mcp_client_workspace"',
            'rm -rf -- "$mcp_client_pub_cache"',
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, runner)

        self.assertNotIn('dart run "$mcp_client_package"', runner)

    def test_shell_runner_emits_bounded_package_client_evidence(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        for expected in [
            "print_package_client_evidence() {",
            "Router Image package evidence: protocol=%s mode=%s auth=%s",
            "direct_json=true resources=true resource_templates=true",
            "resource_template_expansion=true",
            "resource_template_pages=",
            "tool_pages=",
            "resource_pages=",
            "prompt_pages=",
            "prompts=true wamp_meta=true pubsub=true",
            "resource_uri=%s prompt=%s",
            '"sessionless=true request_listener=true"',
            "modern_batch_unsupported=true",
            "refreshed_grant_listener=true",
            '"streamable_http=true session_delete=true resource_template_expansion=true"',
            'lifecycle_evidence+=" auth_lifecycle=true"',
            "%s Router Image package client smoke passed.",
            "%s Router Image stateless package client smoke passed.",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, runner)

        self.assertNotIn("Router Image public package client", runner)
        self.assertNotIn("Router Image stateless public package client", runner)

        summary_prints = [
            line.strip()
            for line in runner.splitlines()
            if 'printf \'%s\\n\' "$summary"' in line
        ]
        self.assertEqual(
            summary_prints,
            ['printf \'%s\\n\' "$summary" >&2'] * 7,
        )

    def test_shell_runner_exercises_modern_resource_listener(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        config = CONFIG.read_text(encoding="utf-8")

        for expected in [
            'mcp_dynamic_resource_uri="connectanum://router-image/live-context"',
            'mcp_resource_update_topic="image.smoke.events"',
            '--resource-uri "$mcp_dynamic_resource_uri"',
            '--resource-update-topic "$mcp_resource_update_topic"',
            '--resource-update-event',
            '"requestScopedResourceSubscription"',
            '"acknowledged":true',
            '"notificationReceived":true',
            '"closedLocally":true',
            '"sessionless":true',
            'request_listener=true',
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, runner)

        self.assertEqual(config.count("uri: connectanum://router-image/live-context"), 3)
        self.assertEqual(config.count("read_procedure: wamp.session.count"), 6)
        self.assertEqual(config.count("update_topic: image.smoke.events"), 6)

    def test_smoke_contract_covers_modern_and_streamable_mcp(self) -> None:
        client = CLIENT.read_text(encoding="utf-8")
        config = CONFIG.read_text(encoding="utf-8")
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
            '"wamp.subscription.list"',
            '"wamp.subscription.lookup"',
            '"wamp.subscription.list_subscribers"',
            '"wamp.subscription.count_subscribers"',
            '"wamp.registration.match"',
            '"wamp.registration.get"',
            '"wamp.registration.list"',
            '"wamp.registration.lookup"',
            '"wamp.registration.list_callees"',
            '"wamp.registration.count_callees"',
            '"wamp.session.count"',
            '"wamp.session.list"',
            '"wamp.session.get"',
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
            'OTHER_AUTH_ID = "image-smoke-peer"',
            'OTHER_AUTH_TICKET = "image-smoke-peer-ticket"',
            '"Authorization": f"Bearer {access_token}"',
            '"grant_type": "revoke"',
            "verify_missing_bearer=True",
            "_run_modern_standard_pubsub(endpoint, label=\"Public\")",
            "_run_modern_standard_pubsub(",
            "_expect_modern_batch_rejected(endpoint, label=\"Public\")",
            "_expect_modern_batch_rejected(",
            "label=\"Protected\"",
            "_expect_modern_requests_ignore_compatibility_session(",
            "_expect_modern_session_methods_rejected(",
            "_expect_compatibility_session_methods_require_bearer(",
            "_expect_compatibility_session_isolated_from_other_principal(",
            "other_principal_authorization_headers=other_authorization_headers",
            "_run_independent_principal_lifecycle(",
            "_expect_initialize_notification_sessionless(",
            'label=f"{label}Peer"',
            "disallowed_session_id=owner_session_id",
            '"MCP-Session-Id": session_id',
            '"Router Image MCP evidence: modern_batch_rejected=true "',
            '"modern_live_session_ignored=true standard=true direct=true "',
            '"modern_methods_rejected=true get=true delete=true "',
            '"compatibility_method_auth_isolated=true missing_bearer=true "',
            '"unknown_bearer=true compatibility_get=true compatibility_delete=true "',
            '"compatibility_principal_isolated=true valid_other_principal=true "',
            '"principal_post=true principal_get=true principal_delete=true "',
            '"authenticated_404=true requested_session_omitted=true "',
            '"independent_principal_ready=true direct_meta=true direct_pubsub=true "',
            '"sessionless_direct=true distinct_streamable_session=true "',
            '"streamable_pubsub=true owner_preserved=true "',
            '"compatibility_session_preserved=true "',
            '"initialize_notification_sessionless=true "',
            '"session_header_echoed=false public=true protected=true."',
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, client)

        for expected in [
            "image-smoke-agent:",
            "ticket: image-smoke-ticket",
            "image-smoke-peer:",
            "ticket: image-smoke-peer-ticket",
        ]:
            with self.subTest(config_expected=expected):
                self.assertIn(expected, config)

    def test_modern_batch_rejection_requires_http_error_without_session(self) -> None:
        authorization_headers = {"Authorization": "Bearer issued-token"}
        response = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32600,
                    "message": "MCP 2026 HTTP POST requires one JSON-RPC message object",
                },
            }
        )

        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(
                400,
                {"mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL},
                response,
            ),
        ) as request:
            CLIENT_MODULE._expect_modern_batch_rejected(
                "http://router/mcp/secure",
                label="Protected",
                headers=authorization_headers,
            )

        request.assert_called_once()
        self.assertEqual(
            request.call_args.args[:2],
            ("http://router/mcp/secure", "POST"),
        )
        payload = request.call_args.args[2]
        self.assertIsInstance(payload, list)
        self.assertEqual(len(payload), 2)
        self.assertEqual(
            request.call_args.kwargs["headers"],
            {
                **authorization_headers,
                "MCP-Protocol-Version": CLIENT_MODULE.MODERN_PROTOCOL,
            },
        )
        self.assertTrue(request.call_args.kwargs["allow_http_error"])

    def test_modern_standard_and_direct_requests_ignore_live_compatibility_session(
        self,
    ) -> None:
        authorization_headers = {"Authorization": "Bearer issued-token"}
        session_id = "live-compatibility-session"
        subscription_handle = "wamp-subscription-42"
        response = {
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "Unknown WAMP subscription handle: "
                            f"{subscription_handle}"
                        ),
                    }
                ],
                "isError": True,
            }
        }

        with mock.patch.object(
            CLIENT_MODULE,
            "_modern_call",
            return_value=response,
        ) as modern_call:
            CLIENT_MODULE._expect_modern_requests_ignore_compatibility_session(
                "http://router/mcp/secure",
                label="Protected",
                session_id=session_id,
                subscription_handle=subscription_handle,
                authorization_headers=authorization_headers,
            )

        self.assertEqual(modern_call.call_count, 2)
        modern_call.assert_has_calls(
            [
                mock.call(
                    "http://router/mcp/secure",
                    "protected-standard-modern-live-compatibility-session-poll",
                    "tools/call",
                    {
                        "name": "connectanum.pubsub.poll",
                        "arguments": {"handle": subscription_handle, "limit": 1},
                    },
                    headers={
                        **authorization_headers,
                        "MCP-Session-Id": session_id,
                    },
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "protected-direct-modern-live-compatibility-session-poll",
                    "connectanum.pubsub.poll",
                    {"handle": subscription_handle, "limit": 1},
                    headers={
                        **authorization_headers,
                        "MCP-Session-Id": session_id,
                    },
                ),
            ]
        )

    def test_modern_get_and_delete_reject_live_compatibility_session(
        self,
    ) -> None:
        authorization_headers = {"Authorization": "Bearer issued-token"}
        session_id = "live-compatibility-session"
        response_headers = {
            "allow": "POST, OPTIONS",
            "mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL,
        }
        response_body = json.dumps(
            {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32600,
                    "message": "MCP 2026 HTTP endpoints support POST and OPTIONS",
                },
            }
        )

        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            side_effect=[
                (405, response_headers, response_body),
                (405, response_headers, response_body),
            ],
        ) as request:
            CLIENT_MODULE._expect_modern_session_methods_rejected(
                "http://router/mcp/secure",
                label="Protected",
                session_id=session_id,
                authorization_headers=authorization_headers,
            )

        request.assert_has_calls(
            [
                mock.call(
                    "http://router/mcp/secure",
                    "GET",
                    headers={
                        **authorization_headers,
                        "MCP-Protocol-Version": CLIENT_MODULE.MODERN_PROTOCOL,
                        "MCP-Session-Id": session_id,
                    },
                    allow_http_error=True,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "DELETE",
                    headers={
                        **authorization_headers,
                        "MCP-Protocol-Version": CLIENT_MODULE.MODERN_PROTOCOL,
                        "MCP-Session-Id": session_id,
                    },
                    allow_http_error=True,
                ),
            ]
        )

    def test_compatibility_get_and_delete_require_missing_or_unknown_bearer(
        self,
    ) -> None:
        session_id = "live-compatibility-session"
        response_headers = {
            "mcp-protocol-version": CLIENT_MODULE.COMPATIBILITY_PROTOCOL,
            "www-authenticate": 'Bearer realm="image.smoke"',
        }
        response_body = json.dumps(
            {
                "status": "error",
                "reason": "unauthorized",
                "message": "Bearer token required",
            }
        )

        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(401, response_headers, response_body),
        ) as request:
            CLIENT_MODULE._expect_compatibility_session_methods_require_bearer(
                "http://router/mcp/secure",
                label="Protected",
                session_id=session_id,
            )

        common_headers = {
            "MCP-Protocol-Version": CLIENT_MODULE.COMPATIBILITY_PROTOCOL,
            "MCP-Session-Id": session_id,
        }
        request.assert_has_calls(
            [
                mock.call(
                    "http://router/mcp/secure",
                    "GET",
                    headers=common_headers,
                    allow_http_error=True,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "DELETE",
                    headers=common_headers,
                    allow_http_error=True,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "GET",
                    headers={
                        **common_headers,
                        "Authorization": "Bearer router-image-unknown-token",
                    },
                    allow_http_error=True,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "DELETE",
                    headers={
                        **common_headers,
                        "Authorization": "Bearer router-image-unknown-token",
                    },
                    allow_http_error=True,
                ),
            ]
        )

    def test_compatibility_session_rejects_valid_other_principal_across_methods(
        self,
    ) -> None:
        session_id = "live-compatibility-session"
        authorization_headers = {"Authorization": "Bearer other-principal-token"}
        response_headers = {
            "mcp-protocol-version": CLIENT_MODULE.COMPATIBILITY_PROTOCOL,
        }
        response_body = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32600,
                    "message": "Unknown MCP HTTP session",
                },
            }
        )

        with mock.patch.object(
            CLIENT_MODULE,
            "_request",
            return_value=(404, response_headers, response_body),
        ) as request:
            CLIENT_MODULE._expect_compatibility_session_isolated_from_other_principal(
                "http://router/mcp/secure",
                label="Protected",
                session_id=session_id,
                authorization_headers=authorization_headers,
            )

        common_headers = {
            **authorization_headers,
            "MCP-Protocol-Version": CLIENT_MODULE.COMPATIBILITY_PROTOCOL,
            "MCP-Session-Id": session_id,
        }
        request.assert_has_calls(
            [
                mock.call(
                    "http://router/mcp/secure",
                    "POST",
                    {
                        "jsonrpc": "2.0",
                        "id": "protected-other-principal-tools",
                        "method": "tools/list",
                        "params": {},
                    },
                    headers=common_headers,
                    allow_http_error=True,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "GET",
                    headers=common_headers,
                    allow_http_error=True,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "DELETE",
                    headers=common_headers,
                    allow_http_error=True,
                ),
            ]
        )

    def test_valid_other_principal_runs_independent_direct_and_streamable_lifecycle(
        self,
    ) -> None:
        authorization_headers = {"Authorization": "Bearer other-principal-token"}

        with (
            mock.patch.object(
                CLIENT_MODULE,
                "_modern_call",
                return_value={
                    "result": {
                        "supportedVersions": [CLIENT_MODULE.MODERN_PROTOCOL],
                    }
                },
            ) as modern_call,
            mock.patch.object(
                CLIENT_MODULE,
                "_run_modern_wamp_registration_session_meta",
            ) as direct_meta,
            mock.patch.object(
                CLIENT_MODULE,
                "_run_modern_direct_pubsub",
            ) as direct_pubsub,
            mock.patch.object(
                CLIENT_MODULE,
                "_run_compatibility_pubsub",
                return_value="other-principal-session",
            ) as streamable_pubsub,
        ):
            session_id = CLIENT_MODULE._run_independent_principal_lifecycle(
                "http://router/mcp/secure",
                label="ProtectedPeer",
                owner_session_id="owner-session",
                authorization_headers=authorization_headers,
            )

        self.assertEqual(session_id, "other-principal-session")
        modern_call.assert_called_once_with(
            "http://router/mcp/secure",
            "protectedpeer-discover",
            "server/discover",
            headers=authorization_headers,
        )
        direct_meta.assert_called_once_with(
            "http://router/mcp/secure",
            label="ProtectedPeer",
            call_mode="direct",
            expected_auth_id=CLIENT_MODULE.OTHER_AUTH_ID,
            expected_auth_role="member",
            authorization_headers=authorization_headers,
        )
        direct_pubsub.assert_called_once_with(
            "http://router/mcp/secure",
            label="ProtectedPeer",
            authorization_headers=authorization_headers,
        )
        streamable_pubsub.assert_called_once_with(
            "http://router/mcp/secure",
            label="ProtectedPeer",
            authorization_headers=authorization_headers,
            disallowed_session_id="owner-session",
        )

    def test_valid_other_principal_requires_distinct_streamable_session(
        self,
    ) -> None:
        with (
            mock.patch.object(
                CLIENT_MODULE,
                "_modern_call",
                return_value={
                    "result": {
                        "supportedVersions": [CLIENT_MODULE.MODERN_PROTOCOL],
                    }
                },
            ),
            mock.patch.object(
                CLIENT_MODULE,
                "_run_modern_wamp_registration_session_meta",
            ),
            mock.patch.object(CLIENT_MODULE, "_run_modern_direct_pubsub"),
            mock.patch.object(
                CLIENT_MODULE,
                "_run_compatibility_pubsub",
                return_value="owner-session",
            ),
        ):
            with self.assertRaisesRegex(
                AssertionError,
                "reused the owner's session ID",
            ):
                CLIENT_MODULE._run_independent_principal_lifecycle(
                    "http://router/mcp/secure",
                    label="ProtectedPeer",
                    owner_session_id="owner-session",
                    authorization_headers={
                        "Authorization": "Bearer other-principal-token"
                    },
                )

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

    def test_modern_tool_catalog_traverses_all_cursor_pages(self) -> None:
        authorization_headers = {"Authorization": "Bearer issued-token"}
        responses = [
            {
                "result": {
                    "tools": [{"name": "connectanum.api.list"}],
                    "nextCursor": "tool-page-2",
                }
            },
            {
                "result": {
                    "tools": [{"name": "wamp.subscription.match"}],
                }
            },
        ]

        with mock.patch.object(
            CLIENT_MODULE,
            "_modern_call",
            side_effect=responses,
        ) as modern_call:
            tool_names = CLIENT_MODULE._modern_tool_names(
                "http://router/mcp/secure",
                label="Protected",
                authorization_headers=authorization_headers,
            )

        self.assertEqual(
            tool_names,
            {"connectanum.api.list", "wamp.subscription.match"},
        )
        self.assertEqual(
            modern_call.call_args_list,
            [
                mock.call(
                    "http://router/mcp/secure",
                    "protected-tools-1",
                    "tools/list",
                    headers=authorization_headers,
                ),
                mock.call(
                    "http://router/mcp/secure",
                    "protected-tools-2",
                    "tools/list",
                    {"cursor": "tool-page-2"},
                    headers=authorization_headers,
                ),
            ],
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
            {
                "result": {
                    "structuredContent": {"arguments": [subscription_id]},
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {
                            "exact": [subscription_id],
                            "prefix": [],
                            "wildcard": [],
                        },
                    }
                }
            },
            {"result": {"structuredContent": {"arguments": []}}},
            {"result": {"structuredContent": {"arguments": [0]}}},
        ]
        authorization_headers = {"Authorization": "Bearer issued-token"}

        for call_mode, expected_methods in [
            (
                "direct",
                [
                    "wamp.subscription.match",
                    "wamp.subscription.get",
                    "wamp.subscription.lookup",
                    "wamp.subscription.list",
                    "wamp.subscription.list_subscribers",
                    "wamp.subscription.count_subscribers",
                ],
            ),
            ("standard", ["tools/call"] * 6),
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
                {"arguments": [CLIENT_MODULE.TOPIC]},
                {},
                {"arguments": [subscription_id]},
                {"arguments": [subscription_id]},
            ]
            if call_mode == "standard":
                expected_arguments = [
                    {
                        "name": tool_name,
                        "arguments": arguments,
                    }
                    for tool_name, arguments in zip(
                        [
                            "wamp.subscription.match",
                            "wamp.subscription.get",
                            "wamp.subscription.lookup",
                            "wamp.subscription.list",
                            "wamp.subscription.list_subscribers",
                            "wamp.subscription.count_subscribers",
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

    def test_modern_wamp_registration_session_meta_preserves_route_identity(
        self,
    ) -> None:
        registration_id = 9002
        session_id = 7001
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
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {"session_ids": [session_id]},
                    }
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {
                            "details": {
                                "id": session_id,
                                "authid": CLIENT_MODULE.AUTH_ID,
                                "authrole": "member",
                            },
                        },
                    }
                }
            },
            {
                "result": {
                    "structuredContent": {"arguments": [registration_id]},
                }
            },
            {
                "result": {
                    "structuredContent": {
                        "argumentsKeywords": {
                            "exact": [registration_id],
                            "prefix": [],
                            "wildcard": [],
                        },
                    }
                }
            },
            {"result": {"structuredContent": {"arguments": []}}},
            {"result": {"structuredContent": {"arguments": [0]}}},
        ]
        authorization_headers = {"Authorization": "Bearer issued-token"}

        for call_mode, expected_methods in [
            (
                "direct",
                [
                    "wamp.registration.match",
                    "wamp.registration.get",
                    "wamp.session.count",
                    "wamp.session.list",
                    "wamp.session.get",
                    "wamp.registration.lookup",
                    "wamp.registration.list",
                    "wamp.registration.list_callees",
                    "wamp.registration.count_callees",
                ],
            ),
            ("standard", ["tools/call"] * 9),
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
                    expected_auth_id=CLIENT_MODULE.AUTH_ID,
                    expected_auth_role="member",
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
                {},
                {"arguments": [session_id]},
                {"arguments": [CLIENT_MODULE.PROCEDURE]},
                {},
                {"arguments": [registration_id]},
                {"arguments": [registration_id]},
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
                            "wamp.session.list",
                            "wamp.session.get",
                            "wamp.registration.lookup",
                            "wamp.registration.list",
                            "wamp.registration.list_callees",
                            "wamp.registration.count_callees",
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

    def test_ticket_grant_flow_accepts_a_distinct_identity(self) -> None:
        challenge = {"state": "peer-challenge-state", "challenge": {}}
        grant = {
            "access_token": "peer-access-token",
            "token_type": "Bearer",
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
            result = CLIENT_MODULE._issue_ticket_grant(
                "http://router/auth",
                auth_id="image-smoke-peer",
                ticket="image-smoke-peer-ticket",
            )

        self.assertEqual(result, grant)
        request.assert_called_once_with(
            "http://router/auth",
            "POST",
            {
                "realm": "image.smoke",
                "authmethod": "ticket",
                "authid": "image-smoke-peer",
            },
            allow_http_error=True,
        )
        post_json.assert_called_once_with(
            "http://router/auth",
            {
                "state": "peer-challenge-state",
                "signature": "image-smoke-peer-ticket",
            },
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
                {"mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL},
                {
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    "Unknown WAMP subscription handle: "
                                    "compatibility-handle"
                                ),
                            }
                        ],
                        "isError": True,
                    }
                },
            ),
            (
                {"mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL},
                {
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    "Unknown WAMP subscription handle: "
                                    "compatibility-handle"
                                ),
                            }
                        ],
                        "isError": True,
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
            (
                202,
                {"mcp-protocol-version": CLIENT_MODULE.COMPATIBILITY_PROTOCOL},
                "",
            ),
            (202, {}, ""),
            (
                405,
                {
                    "allow": "POST, OPTIONS",
                    "mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL,
                },
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "error": {
                            "code": -32600,
                            "message": (
                                "MCP 2026 HTTP endpoints support POST and OPTIONS"
                            ),
                        },
                    }
                ),
            ),
            (
                405,
                {
                    "allow": "POST, OPTIONS",
                    "mcp-protocol-version": CLIENT_MODULE.MODERN_PROTOCOL,
                },
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "error": {
                            "code": -32600,
                            "message": (
                                "MCP 2026 HTTP endpoints support POST and OPTIONS"
                            ),
                        },
                    }
                ),
            ),
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
            [
                "tools/call",
                "tools/call",
                "connectanum.pubsub.poll",
                "tools/call",
                "tools/call",
                "tools/call",
            ],
        )
        self.assertEqual(
            [payload["params"].get("name") for payload in tool_payloads],
            [
                "connectanum.pubsub.subscribe",
                "connectanum.pubsub.poll",
                None,
                "connectanum.pubsub.publish",
                "connectanum.pubsub.poll",
                "connectanum.pubsub.unsubscribe",
            ],
        )
        self.assertEqual(
            tool_payloads[0]["params"]["arguments"],
            {"topic": CLIENT_MODULE.TOPIC, "queueLimit": 5},
        )
        self.assertEqual(
            post_json.call_args_list[2].kwargs["headers"],
            {
                "MCP-Session-Id": "compatibility-session",
                "MCP-Protocol-Version": CLIENT_MODULE.MODERN_PROTOCOL,
                "Mcp-Method": "tools/call",
                "Mcp-Name": "connectanum.pubsub.poll",
            },
        )
        self.assertEqual(
            post_json.call_args_list[3].kwargs["headers"],
            {
                "MCP-Session-Id": "compatibility-session",
                "MCP-Protocol-Version": CLIENT_MODULE.MODERN_PROTOCOL,
                "Mcp-Method": "connectanum.pubsub.poll",
            },
        )
        self.assertEqual(
            {
                key: tool_payloads[2]["params"][key]
                for key in ("handle", "limit")
            },
            {"handle": "compatibility-handle", "limit": 1},
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
            "tool_list_page_size: 10",
            "tool_list_page_size: 1",
            "topic: image.smoke.events",
            "resource_list_page_size: 10",
            "resource_list_page_size: 1",
            "resource_template_list_page_size: 10",
            "resource_template_list_page_size: 1",
            "prompt_list_page_size: 10",
            "prompt_list_page_size: 1",
            "uri: connectanum://router-image/context",
            "uri: connectanum://router-image/archive-context",
            "uri_template: connectanum://router-image/item/{itemId}",
            "uri_template: connectanum://router-image/archive/{itemId}",
            "name: inspect-router-image",
            "name: archive-router-image",
            "text: Inspect {{subject}} using router image context.",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, config)
        self.assertEqual(config.count("- procedure: wamp.session.count"), 3)
        self.assertEqual(
            config.count("uri: connectanum://router-image/context"), 3
        )
        self.assertEqual(
            config.count("uri_template: connectanum://router-image/item/{itemId}"),
            3,
        )
        self.assertEqual(
            config.count("uri_template: connectanum://router-image/archive/{itemId}"),
            1,
        )
        self.assertEqual(config.count("read_procedure: wamp.session.count"), 6)
        self.assertEqual(config.count("update_topic: image.smoke.events"), 6)
        self.assertEqual(config.count("name: inspect-router-image"), 3)
        self.assertEqual(
            config.count("uri: connectanum://router-image/archive-context"), 1
        )
        self.assertEqual(config.count("name: archive-router-image"), 1)
        self.assertEqual(config.count("tool_list_page_size: 10"), 2)
        self.assertEqual(config.count("tool_list_page_size: 1\n"), 1)

    def test_workflow_smokes_loaded_image_before_multiarch_build(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        dart_setup = workflow.index("- uses: dart-lang/setup-dart@v1")
        dart_dependencies = workflow.index(
            "- name: Resolve Dart workspace dependencies"
        )
        local_build = workflow.index("- name: Build local router smoke image")
        runtime_smoke = workflow.index("- name: Smoke router-hosted MCP image")
        multiarch_build = workflow.index(
            "- name: Build or publish multi-arch router image"
        )
        self.assertLess(dart_setup, dart_dependencies)
        self.assertLess(dart_dependencies, runtime_smoke)
        self.assertLess(local_build, runtime_smoke)
        self.assertLess(runtime_smoke, multiarch_build)
        self.assertIn("load: true", workflow[local_build:runtime_smoke])
        self.assertIn("bin/router-image-mcp-smoke", workflow)


if __name__ == "__main__":
    unittest.main()
