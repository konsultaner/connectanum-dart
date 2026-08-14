#!/usr/bin/env python3
"""Black-box MCP checks for a running packaged router image."""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from typing import Any


MODERN_PROTOCOL = "2026-07-28"
COMPATIBILITY_PROTOCOL = "2025-11-25"
TOPIC = "image.smoke.events"
PROCEDURE = "wamp.session.count"
RESOURCE_TEMPLATE = "connectanum://router-image/item/{itemId}"
PROMPT = "inspect-router-image"
AUTH_REALM = "image.smoke"
AUTH_ID = "image-smoke-agent"
AUTH_TICKET = "image-smoke-ticket"
OTHER_AUTH_ID = "image-smoke-peer"
OTHER_AUTH_TICKET = "image-smoke-peer-ticket"
MAX_CATALOG_PAGES = 1024


def _json_payload(body: str) -> Any:
    text = body.strip()
    if not text:
        return None
    if any(line.startswith("data:") for line in text.splitlines()):
        last_json_error: json.JSONDecodeError | None = None
        for block in text.split("\n\n"):
            data_lines = [
                line[len("data:") :].lstrip()
                for line in block.splitlines()
                if line.startswith("data:")
            ]
            data_text = "\n".join(data_lines).strip()
            if not data_text:
                continue
            try:
                return json.loads(data_text)
            except json.JSONDecodeError as error:
                last_json_error = error
        if last_json_error is not None:
            raise AssertionError(
                f"SSE response data was not JSON: {body}"
            ) from last_json_error
        raise AssertionError(f"SSE response did not contain data: {body}")
    return json.loads(text)


def _request(
    endpoint: str,
    method: str,
    payload: Any | None = None,
    *,
    headers: dict[str, str] | None = None,
    allow_http_error: bool = False,
) -> tuple[int, dict[str, str], str]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(endpoint, data=data, method=method)
    request.add_header("Accept", "application/json, text/event-stream")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return (
                response.status,
                {name.lower(): value for name, value in response.headers.items()},
                response.read().decode("utf-8"),
            )
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        if allow_http_error:
            return (
                error.code,
                {name.lower(): value for name, value in error.headers.items()},
                body,
            )
        raise AssertionError(
            f"{method} {endpoint} returned HTTP {error.code}: {body}"
        ) from error


def _post_json(
    endpoint: str,
    payload: dict[str, Any],
    *,
    headers: dict[str, str] | None = None,
) -> tuple[dict[str, str], dict[str, Any]]:
    status, response_headers, body = _request(
        endpoint, "POST", payload, headers=headers
    )
    if status < 200 or status >= 300:
        raise AssertionError(f"Unexpected MCP HTTP status {status}: {body}")
    parsed = _json_payload(body)
    if not isinstance(parsed, dict):
        raise AssertionError(f"MCP response was not a JSON object: {parsed}")
    if "error" in parsed:
        raise AssertionError(f"MCP JSON-RPC error: {parsed['error']}")
    return response_headers, parsed


def _post_json_response(
    endpoint: str,
    payload: dict[str, Any],
    *,
    headers: dict[str, str] | None = None,
) -> tuple[dict[str, str], dict[str, Any]]:
    status, response_headers, body = _request(
        endpoint, "POST", payload, headers=headers
    )
    if status < 200 or status >= 300:
        raise AssertionError(f"Unexpected MCP HTTP status {status}: {body}")
    content_type = response_headers.get("content-type", "")
    if content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise AssertionError(
            f"MCP JSON-response route returned {content_type!r}, not application/json"
        )
    if any(line.startswith("data:") for line in body.splitlines()):
        raise AssertionError("MCP JSON-response route returned SSE framing")
    parsed = json.loads(body)
    if not isinstance(parsed, dict):
        raise AssertionError(f"MCP response was not a JSON object: {parsed}")
    if "error" in parsed:
        raise AssertionError(f"MCP JSON-RPC error: {parsed['error']}")
    return response_headers, parsed


def _expect_initialize_notification_sessionless(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    status, response_headers, body = _request(
        endpoint,
        "POST",
        {
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {
                "protocolVersion": COMPATIBILITY_PROTOCOL,
                "capabilities": {},
                "clientInfo": {
                    "name": "router-image-runtime-smoke",
                    "version": "0.0.0",
                },
            },
        },
        headers={
            **(authorization_headers or {}),
            "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
        },
    )
    if status != 202 or body.strip():
        raise AssertionError(
            f"{label} initialize notification returned {status} with body {body!r}"
        )
    if response_headers.get("mcp-session-id") is not None:
        raise AssertionError(f"{label} initialize notification created a session")


def _modern_params(arguments: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        **(arguments or {}),
        "_meta": {
            "io.modelcontextprotocol/protocolVersion": MODERN_PROTOCOL,
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": {
                "name": "router-image-runtime-smoke",
                "version": "0.0.0",
            },
        },
    }


def _modern_call(
    endpoint: str,
    request_id: str,
    method: str,
    arguments: dict[str, Any] | None = None,
    *,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    request_headers = {
        **(headers or {}),
        "MCP-Protocol-Version": MODERN_PROTOCOL,
        "Mcp-Method": method,
    }
    if method == "tools/call" and isinstance(arguments, dict):
        tool_name = arguments.get("name")
        if isinstance(tool_name, str):
            request_headers["Mcp-Name"] = tool_name
    response_headers, response = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": _modern_params(arguments),
        },
        headers=request_headers,
    )
    if response_headers.get("mcp-protocol-version") != MODERN_PROTOCOL:
        raise AssertionError(
            f"Modern response missed {MODERN_PROTOCOL} protocol header"
        )
    if response_headers.get("mcp-session-id") is not None:
        raise AssertionError("Modern stateless response unexpectedly created a session")
    return response


def _expect_modern_completions(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    prompt_response = _modern_call(
        endpoint,
        f"{label.lower()}-prompt-completion",
        "completion/complete",
        {
            "ref": {"type": "ref/prompt", "name": PROMPT},
            "argument": {"name": "subject", "value": "packaged"},
        },
        headers=authorization_headers,
    )
    prompt_result = prompt_response.get("result", {})
    if prompt_result.get("completion", {}).get("values") != ["packaged runtime"]:
        raise AssertionError(
            f"{label} prompt completion returned {prompt_response}"
        )
    if prompt_result.get("resultType") != "complete" or "ttlMs" in prompt_result:
        raise AssertionError(
            f"{label} prompt completion missed modern non-cacheable metadata: "
            f"{prompt_response}"
        )

    resource_response = _modern_call(
        endpoint,
        f"{label.lower()}-resource-completion",
        "completion/complete",
        {
            "ref": {"type": "ref/resource", "uri": RESOURCE_TEMPLATE},
            "argument": {"name": "itemId", "value": "package-"},
        },
        headers=authorization_headers,
    )
    if resource_response.get("result", {}).get("completion", {}).get(
        "values"
    ) != ["package-client"]:
        raise AssertionError(
            f"{label} resource-template completion returned {resource_response}"
        )


def _modern_tools_by_name(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
) -> dict[str, dict[str, Any]]:
    tools_by_name: dict[str, dict[str, Any]] = {}
    seen_cursors: set[str] = set()
    cursor: str | None = None
    pages_read = 0
    while True:
        pages_read += 1
        if cursor is None:
            response = _modern_call(
                endpoint,
                f"{label.lower()}-tools-{pages_read}",
                "tools/list",
                headers=authorization_headers,
            )
        else:
            response = _modern_call(
                endpoint,
                f"{label.lower()}-tools-{pages_read}",
                "tools/list",
                {"cursor": cursor},
                headers=authorization_headers,
            )

        result = response.get("result")
        if not isinstance(result, dict):
            raise AssertionError(f"{label} tools/list result was not an object")
        tools = result.get("tools")
        if not isinstance(tools, list):
            raise AssertionError(f"{label} tools/list result missed tools")
        for tool in tools:
            if isinstance(tool, dict) and isinstance(
                (name := tool.get("name")), str
            ):
                tools_by_name[name] = tool

        next_cursor = result.get("nextCursor")
        if next_cursor is None:
            return tools_by_name
        if not isinstance(next_cursor, str) or not next_cursor:
            raise AssertionError(f"{label} tools/list returned an invalid cursor")
        if pages_read >= MAX_CATALOG_PAGES:
            raise AssertionError(
                f"{label} tools/list exceeded {MAX_CATALOG_PAGES} pages"
            )
        if next_cursor in seen_cursors:
            raise AssertionError(f"{label} tools/list repeated a cursor")
        seen_cursors.add(next_cursor)
        cursor = next_cursor


def _expect_modern_standard_meta_tool_schemas(
    tools_by_name: dict[str, dict[str, Any]],
    *,
    label: str,
) -> None:
    expected_named_inputs = {
        "wamp.session.count": None,
        "wamp.session.list": None,
        "wamp.session.get": "sessionId",
        "wamp.registration.list": None,
        "wamp.registration.lookup": "procedure",
        "wamp.registration.match": "procedure",
        "wamp.registration.get": "registrationId",
        "wamp.registration.list_callees": "registrationId",
        "wamp.registration.count_callees": "registrationId",
        "wamp.subscription.list": None,
        "wamp.subscription.lookup": "topic",
        "wamp.subscription.match": "topic",
        "wamp.subscription.get": "subscriptionId",
        "wamp.subscription.list_subscribers": "subscriptionId",
        "wamp.subscription.count_subscribers": "subscriptionId",
    }
    named_fields = {
        "sessionId",
        "registrationId",
        "subscriptionId",
        "procedure",
        "topic",
    }
    expected_output_schema = {
        "type": "object",
        "properties": {
            "arguments": {"type": "array"},
            "argumentsKeywords": {
                "type": "object",
                "additionalProperties": True,
            },
            "details": {
                "type": "object",
                "additionalProperties": True,
            },
        },
        "additionalProperties": False,
    }
    for tool_name, named_input in expected_named_inputs.items():
        tool = tools_by_name.get(tool_name)
        if not isinstance(tool, dict):
            raise AssertionError(f"{label} tools/list missed {tool_name}")
        input_schema = tool.get("inputSchema")
        if not isinstance(input_schema, dict):
            raise AssertionError(f"{label} {tool_name} missed its input schema")
        properties = input_schema.get("properties")
        if not isinstance(properties, dict):
            raise AssertionError(
                f"{label} {tool_name} input schema missed properties"
            )
        if not {"arguments", "argumentsKeywords"}.issubset(properties):
            raise AssertionError(
                f"{label} {tool_name} missed raw WAMP compatibility inputs"
            )
        expected_named_fields = {named_input} if named_input is not None else set()
        if named_fields.intersection(properties) != expected_named_fields:
            raise AssertionError(
                f"{label} {tool_name} exposed unexpected named inputs: {properties}"
            )
        if input_schema.get("additionalProperties") is not False:
            raise AssertionError(
                f"{label} {tool_name} accepted undocumented input fields"
            )
        if named_input is not None:
            alternatives = input_schema.get("anyOf")
            required_alternatives = {
                tuple(alternative.get("required", []))
                for alternative in alternatives or []
                if isinstance(alternative, dict)
            }
            if (named_input,) not in required_alternatives:
                raise AssertionError(
                    f"{label} {tool_name} did not require a named or raw input"
                )
        if tool_name.endswith(".lookup"):
            match_schema = properties.get("match")
            if not isinstance(match_schema, dict) or match_schema.get("enum") != [
                "exact",
                "prefix",
                "wildcard",
            ]:
                raise AssertionError(
                    f"{label} {tool_name} missed the WAMP match policy schema"
                )
        if tool.get("outputSchema") != expected_output_schema:
            raise AssertionError(
                f"{label} {tool_name} exposed an unexpected result schema"
            )


def _expect_modern_batch_rejected(
    endpoint: str,
    *,
    label: str,
    headers: dict[str, str] | None = None,
) -> None:
    request_headers = {
        **(headers or {}),
        "MCP-Protocol-Version": MODERN_PROTOCOL,
    }
    status, response_headers, body = _request(
        endpoint,
        "POST",
        [
            {
                "jsonrpc": "2.0",
                "id": f"{label.lower()}-modern-batch-tools",
                "method": "tools/list",
                "params": _modern_params(),
            },
            {
                "jsonrpc": "2.0",
                "id": f"{label.lower()}-modern-batch-ping",
                "method": "ping",
                "params": _modern_params(),
            },
        ],
        headers=request_headers,
        allow_http_error=True,
    )
    if status != 400:
        raise AssertionError(f"{label} modern batch returned HTTP {status}: {body}")
    if response_headers.get("mcp-protocol-version") != MODERN_PROTOCOL:
        raise AssertionError(
            f"{label} modern batch rejection missed {MODERN_PROTOCOL} protocol header"
        )
    if response_headers.get("mcp-session-id") is not None:
        raise AssertionError(f"{label} modern batch rejection leaked a session header")

    parsed = _json_payload(body)
    if not isinstance(parsed, dict) or parsed.get("id") is not None:
        raise AssertionError(
            f"{label} modern batch rejection was not a request-level error: {parsed}"
        )
    error = parsed.get("error")
    if not isinstance(error, dict) or error.get("code") != -32600:
        raise AssertionError(
            f"{label} modern batch rejection missed invalidRequest: {parsed}"
        )
    if "one JSON-RPC message object" not in str(error.get("message", "")):
        raise AssertionError(
            f"{label} modern batch rejection had an unexpected message: {error}"
        )


def _expect_modern_requests_ignore_compatibility_session(
    endpoint: str,
    *,
    label: str,
    session_id: str,
    subscription_handle: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    expected_error = f"Unknown WAMP subscription handle: {subscription_handle}"
    arguments = {"handle": subscription_handle, "limit": 1}
    requests = [
        (
            "standard",
            "tools/call",
            {
                "name": "connectanum.pubsub.poll",
                "arguments": arguments,
            },
        ),
        ("direct", "connectanum.pubsub.poll", arguments),
    ]
    for call_mode, method, params in requests:
        response = _modern_call(
            endpoint,
            (
                f"{label.lower()}-{call_mode}-modern-live-"
                "compatibility-session-poll"
            ),
            method,
            params,
            headers={
                **(authorization_headers or {}),
                "MCP-Session-Id": session_id,
            },
        )
        result = response.get("result")
        if (
            not isinstance(result, dict)
            or result.get("isError") is not True
            or expected_error not in json.dumps(result)
        ):
            raise AssertionError(
                f"{label} modern {call_mode} request accessed compatibility "
                f"session state: {response}"
            )


def _expect_modern_session_methods_rejected(
    endpoint: str,
    *,
    label: str,
    session_id: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    headers = {
        **(authorization_headers or {}),
        "MCP-Protocol-Version": MODERN_PROTOCOL,
        "MCP-Session-Id": session_id,
    }
    for method in ("GET", "DELETE"):
        status, response_headers, body = _request(
            endpoint,
            method,
            headers=headers,
            allow_http_error=True,
        )
        if status != 405:
            raise AssertionError(
                f"{label} modern {method} returned HTTP {status}: {body}"
            )
        if response_headers.get("mcp-session-id") is not None:
            raise AssertionError(
                f"{label} modern {method} leaked the compatibility session ID"
            )
        if response_headers.get("mcp-protocol-version") != MODERN_PROTOCOL:
            raise AssertionError(
                f"{label} modern {method} missed the negotiated protocol header"
            )
        if response_headers.get("allow") != "POST, OPTIONS":
            raise AssertionError(
                f"{label} modern {method} returned an unexpected Allow header: "
                f"{response_headers.get('allow')!r}"
            )
        parsed = _json_payload(body)
        error = parsed.get("error") if isinstance(parsed, dict) else None
        if not isinstance(error, dict) or error.get("code") != -32600:
            raise AssertionError(
                f"{label} modern {method} missed invalidRequest: {parsed}"
            )
        if "support POST and OPTIONS" not in str(error.get("message", "")):
            raise AssertionError(
                f"{label} modern {method} had an unexpected message: {error}"
            )


def _expect_compatibility_session_methods_require_bearer(
    endpoint: str,
    *,
    label: str,
    session_id: str,
) -> None:
    credentials = [
        ("missing bearer", {}),
        (
            "unknown bearer",
            {"Authorization": "Bearer router-image-unknown-token"},
        ),
    ]
    for credential_label, authorization_headers in credentials:
        headers = {
            "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
            "MCP-Session-Id": session_id,
            **authorization_headers,
        }
        for method in ("GET", "DELETE"):
            status, response_headers, body = _request(
                endpoint,
                method,
                headers=headers,
                allow_http_error=True,
            )
            if status != 401:
                raise AssertionError(
                    f"{label} compatibility {method} with {credential_label} "
                    f"returned HTTP {status}: {body}"
                )
            if response_headers.get("mcp-session-id") is not None:
                raise AssertionError(
                    f"{label} compatibility {method} with {credential_label} "
                    "leaked the live session ID"
                )
            if (
                response_headers.get("mcp-protocol-version")
                != COMPATIBILITY_PROTOCOL
            ):
                raise AssertionError(
                    f"{label} compatibility {method} with {credential_label} "
                    "missed the negotiated protocol header"
                )
            if "bearer" not in response_headers.get(
                "www-authenticate", ""
            ).lower():
                raise AssertionError(
                    f"{label} compatibility {method} with {credential_label} "
                    "missed the Bearer challenge"
                )


def _expect_compatibility_session_isolated_from_other_principal(
    endpoint: str,
    *,
    label: str,
    session_id: str,
    authorization_headers: dict[str, str],
) -> None:
    headers = {
        **authorization_headers,
        "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
        "MCP-Session-Id": session_id,
    }
    requests = [
        (
            "POST",
            {
                "jsonrpc": "2.0",
                "id": f"{label.lower()}-other-principal-tools",
                "method": "tools/list",
                "params": {},
            },
        ),
        ("GET", None),
        ("DELETE", None),
    ]
    for method, payload in requests:
        if payload is None:
            status, response_headers, body = _request(
                endpoint,
                method,
                headers=headers,
                allow_http_error=True,
            )
        else:
            status, response_headers, body = _request(
                endpoint,
                method,
                payload,
                headers=headers,
                allow_http_error=True,
            )
        if status != 404:
            raise AssertionError(
                f"{label} compatibility {method} with another valid principal "
                f"returned HTTP {status}: {body}"
            )
        if (
            response_headers.get("mcp-protocol-version")
            != COMPATIBILITY_PROTOCOL
        ):
            raise AssertionError(
                f"{label} compatibility {method} with another valid principal "
                "missed the negotiated protocol header"
            )
        if response_headers.get("mcp-session-id") is not None:
            raise AssertionError(
                f"{label} compatibility {method} with another valid principal "
                "leaked the requested session ID"
            )
        if response_headers.get("www-authenticate") is not None:
            raise AssertionError(
                f"{label} compatibility {method} with another valid principal "
                "unexpectedly returned an authentication challenge"
            )
        parsed = _json_payload(body)
        error = parsed.get("error") if isinstance(parsed, dict) else None
        if not isinstance(error, dict) or error.get("code") != -32600:
            raise AssertionError(
                f"{label} compatibility {method} with another valid principal "
                f"missed invalidRequest: {parsed}"
            )
        if "Unknown MCP HTTP session" not in str(error.get("message", "")):
            raise AssertionError(
                f"{label} compatibility {method} with another valid principal "
                f"had an unexpected message: {error}"
            )


def _structured_content(message: dict[str, Any], *, label: str) -> dict[str, Any]:
    result = message.get("result")
    if not isinstance(result, dict):
        raise AssertionError(f"{label} missed JSON-RPC result: {message}")
    if result.get("isError") is True:
        raise AssertionError(f"{label} returned an MCP tool error: {result}")
    structured = result.get("structuredContent")
    if not isinstance(structured, dict):
        raise AssertionError(f"{label} missed structuredContent: {result}")
    return structured


def _wait_for_discovery(endpoint: str) -> dict[str, Any]:
    last_error: Exception | None = None
    for _ in range(100):
        try:
            return _modern_call(endpoint, "discover", "server/discover")
        except (AssertionError, OSError, urllib.error.URLError) as error:
            last_error = error
            time.sleep(0.1)
    raise AssertionError(f"Router MCP endpoint did not become ready: {last_error}")


def _expect_unauthorized(
    endpoint: str,
    payload: dict[str, Any],
    *,
    headers: dict[str, str],
    label: str,
) -> None:
    status, response_headers, body = _request(
        endpoint,
        "POST",
        payload,
        headers=headers,
        allow_http_error=True,
    )
    if status != 401:
        raise AssertionError(f"{label} returned HTTP {status}: {body}")
    if response_headers.get("mcp-session-id") is not None:
        raise AssertionError(f"{label} leaked an MCP session header")
    if "bearer" not in response_headers.get("www-authenticate", "").lower():
        raise AssertionError(f"{label} missed the Bearer challenge")


def _issue_ticket_grant(
    auth_endpoint: str,
    *,
    auth_id: str = AUTH_ID,
    ticket: str = AUTH_TICKET,
) -> dict[str, Any]:
    status, _, body = _request(
        auth_endpoint,
        "POST",
        {
            "realm": AUTH_REALM,
            "authmethod": "ticket",
            "authid": auth_id,
        },
        allow_http_error=True,
    )
    if status != 401:
        raise AssertionError(
            f"Ticket auth challenge returned HTTP {status}: {body}"
        )
    challenge = _json_payload(body)
    if not isinstance(challenge, dict):
        raise AssertionError(f"Ticket auth challenge was not an object: {challenge}")
    state = challenge.get("state")
    if not isinstance(state, str) or not state:
        raise AssertionError(f"Ticket auth challenge missed state: {challenge}")

    _, grant = _post_json(
        auth_endpoint,
        {"state": state, "signature": ticket},
    )
    access_token = grant.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise AssertionError(f"Ticket auth response missed access_token: {grant}")
    if str(grant.get("token_type", "")).lower() != "bearer":
        raise AssertionError(f"Ticket auth response missed Bearer token type: {grant}")
    return grant


def _run_modern_standard_tool_catalog(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    catalog = _modern_call(
        endpoint,
        f"{label.lower()}-standard-catalog",
        "tools/call",
        {
            "name": "connectanum.api.list",
            "arguments": {"kind": "topic"},
        },
        headers=authorization_headers,
    )
    catalog_content = _structured_content(
        catalog, label=f"{label} standard tool API catalog"
    )
    if TOPIC not in json.dumps(catalog_content):
        raise AssertionError(f"{label} standard tool API catalog missed {TOPIC}")


def _run_modern_wamp_registration_session_meta(
    endpoint: str,
    *,
    label: str,
    call_mode: str,
    expected_auth_id: str,
    expected_auth_role: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    if call_mode not in {"direct", "standard"}:
        raise AssertionError(f"Unsupported modern Meta API call mode: {call_mode}")

    def call(
        request_suffix: str,
        tool_name: str,
        arguments: dict[str, Any],
    ) -> dict[str, Any]:
        method = tool_name
        params = arguments
        if call_mode == "standard":
            method = "tools/call"
            params = {"name": tool_name, "arguments": arguments}
        return _modern_call(
            endpoint,
            f"{label.lower()}-{call_mode}-{request_suffix}",
            method,
            params,
            headers=authorization_headers,
        )

    match = call(
        "registration-match",
        "wamp.registration.match",
        {"procedure": PROCEDURE},
    )
    match_content = _structured_content(
        match, label=f"{label} {call_mode} registration match"
    )
    match_ids = match_content.get("arguments")
    if (
        not isinstance(match_ids, list)
        or not match_ids
        or not isinstance(match_ids[0], int)
    ):
        raise AssertionError(
            f"{label} {call_mode} registration match missed an id: "
            f"{match_content}"
        )
    registration_id = match_ids[0]

    details = call(
        "registration-get",
        "wamp.registration.get",
        {"registrationId": registration_id},
    )
    details_content = _structured_content(
        details, label=f"{label} {call_mode} registration details"
    )
    registration = details_content.get("argumentsKeywords")
    if not isinstance(registration, dict):
        raise AssertionError(
            f"{label} {call_mode} registration details missed keywords: "
            f"{details_content}"
        )
    if (
        registration.get("id") != registration_id
        or registration.get("uri") != PROCEDURE
        or registration.get("match") != "exact"
        or registration.get("invoke") != "single"
    ):
        raise AssertionError(
            f"{label} {call_mode} registration details were invalid: "
            f"{registration}"
        )

    result = call("session-count", PROCEDURE, {})
    result_content = _structured_content(
        result, label=f"{label} {call_mode} session count"
    )
    if result_content.get("argumentsKeywords", {}).get("count") != 1:
        raise AssertionError(
            f"{label} {call_mode} session count exposed unexpected sessions: "
            f"{result_content}"
        )

    session_list = call("session-list", "wamp.session.list", {})
    session_list_content = _structured_content(
        session_list, label=f"{label} {call_mode} session list"
    )
    session_ids = session_list_content.get("argumentsKeywords", {}).get(
        "session_ids"
    )
    if (
        not isinstance(session_ids, list)
        or len(session_ids) != 1
        or not isinstance(session_ids[0], int)
    ):
        raise AssertionError(
            f"{label} {call_mode} session list exposed unexpected sessions: "
            f"{session_list_content}"
        )
    session_id = session_ids[0]

    session_get = call(
        "session-get",
        "wamp.session.get",
        {"sessionId": session_id},
    )
    session_get_content = _structured_content(
        session_get, label=f"{label} {call_mode} session details"
    )
    session_details = session_get_content.get("argumentsKeywords", {}).get(
        "details"
    )
    if not isinstance(session_details, dict):
        raise AssertionError(
            f"{label} {call_mode} session details missed keywords: "
            f"{session_get_content}"
        )
    if (
        session_details.get("id") != session_id
        or session_details.get("authid") != expected_auth_id
        or session_details.get("authrole") != expected_auth_role
    ):
        raise AssertionError(
            f"{label} {call_mode} session identity was invalid: "
            f"{session_details}"
        )

    lookup = call(
        "registration-lookup",
        "wamp.registration.lookup",
        {"procedure": PROCEDURE},
    )
    lookup_content = _structured_content(
        lookup, label=f"{label} {call_mode} registration lookup"
    )
    if lookup_content.get("arguments") != [registration_id]:
        raise AssertionError(
            f"{label} {call_mode} registration lookup returned an unexpected "
            f"registration: {lookup_content}"
        )

    listing = call("registration-list", "wamp.registration.list", {})
    listing_content = _structured_content(
        listing, label=f"{label} {call_mode} registration list"
    )
    exact_registrations = listing_content.get("argumentsKeywords", {}).get(
        "exact"
    )
    if (
        not isinstance(exact_registrations, list)
        or registration_id not in exact_registrations
    ):
        raise AssertionError(
            f"{label} {call_mode} registration list missed the configured "
            f"procedure: {listing_content}"
        )

    callees = call(
        "registration-list-callees",
        "wamp.registration.list_callees",
        {"registrationId": registration_id},
    )
    callees_content = _structured_content(
        callees, label=f"{label} {call_mode} registration callees"
    )
    if callees_content.get("arguments") != []:
        raise AssertionError(
            f"{label} {call_mode} configured registration exposed live "
            f"callees: {callees_content}"
        )

    callee_count = call(
        "registration-count-callees",
        "wamp.registration.count_callees",
        {"registrationId": registration_id},
    )
    callee_count_content = _structured_content(
        callee_count, label=f"{label} {call_mode} registration callee count"
    )
    if callee_count_content.get("arguments") != [0]:
        raise AssertionError(
            f"{label} {call_mode} configured registration reported live "
            f"callees: {callee_count_content}"
        )


def _run_modern_wamp_subscription_meta(
    endpoint: str,
    *,
    label: str,
    call_mode: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    if call_mode not in {"direct", "standard"}:
        raise AssertionError(f"Unsupported modern Meta API call mode: {call_mode}")

    def call(
        request_suffix: str,
        tool_name: str,
        arguments: dict[str, Any],
    ) -> dict[str, Any]:
        method = tool_name
        params = arguments
        if call_mode == "standard":
            method = "tools/call"
            params = {"name": tool_name, "arguments": arguments}
        return _modern_call(
            endpoint,
            f"{label.lower()}-{call_mode}-{request_suffix}",
            method,
            params,
            headers=authorization_headers,
        )

    match = call(
        "subscription-match",
        "wamp.subscription.match",
        {"topic": TOPIC},
    )
    match_content = _structured_content(
        match, label=f"{label} {call_mode} subscription match"
    )
    match_ids = match_content.get("arguments")
    if (
        not isinstance(match_ids, list)
        or not match_ids
        or not isinstance(match_ids[0], int)
    ):
        raise AssertionError(
            f"{label} {call_mode} subscription match missed an id: "
            f"{match_content}"
        )
    subscription_id = match_ids[0]

    details = call(
        "subscription-get",
        "wamp.subscription.get",
        {"subscriptionId": subscription_id},
    )
    details_content = _structured_content(
        details, label=f"{label} {call_mode} subscription details"
    )
    subscription = details_content.get("argumentsKeywords")
    if not isinstance(subscription, dict):
        raise AssertionError(
            f"{label} {call_mode} subscription details missed keywords: "
            f"{details_content}"
        )
    if (
        subscription.get("id") != subscription_id
        or subscription.get("uri") != TOPIC
        or subscription.get("match") != "exact"
    ):
        raise AssertionError(
            f"{label} {call_mode} subscription details were invalid: "
            f"{subscription}"
        )

    lookup = call(
        "subscription-lookup",
        "wamp.subscription.lookup",
        {"topic": TOPIC},
    )
    lookup_content = _structured_content(
        lookup, label=f"{label} {call_mode} subscription lookup"
    )
    if lookup_content.get("arguments") != [subscription_id]:
        raise AssertionError(
            f"{label} {call_mode} subscription lookup returned an unexpected "
            f"subscription: {lookup_content}"
        )

    listing = call("subscription-list", "wamp.subscription.list", {})
    listing_content = _structured_content(
        listing, label=f"{label} {call_mode} subscription list"
    )
    exact_subscriptions = listing_content.get("argumentsKeywords", {}).get(
        "exact"
    )
    if (
        not isinstance(exact_subscriptions, list)
        or subscription_id not in exact_subscriptions
    ):
        raise AssertionError(
            f"{label} {call_mode} subscription list missed the configured "
            f"topic: {listing_content}"
        )

    subscribers = call(
        "subscription-list-subscribers",
        "wamp.subscription.list_subscribers",
        {"subscriptionId": subscription_id},
    )
    subscribers_content = _structured_content(
        subscribers, label=f"{label} {call_mode} subscription subscribers"
    )
    if subscribers_content.get("arguments") != []:
        raise AssertionError(
            f"{label} {call_mode} configured subscription exposed live "
            f"subscribers: {subscribers_content}"
        )

    subscriber_count = call(
        "subscription-count-subscribers",
        "wamp.subscription.count_subscribers",
        {"subscriptionId": subscription_id},
    )
    subscriber_count_content = _structured_content(
        subscriber_count,
        label=f"{label} {call_mode} subscription subscriber count",
    )
    if subscriber_count_content.get("arguments") != [0]:
        raise AssertionError(
            f"{label} {call_mode} configured subscription reported live "
            f"subscribers: {subscriber_count_content}"
        )


def _run_modern_pubsub(
    endpoint: str,
    *,
    label: str,
    call_mode: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    if call_mode not in {"direct", "standard"}:
        raise AssertionError(f"Unsupported modern pub/sub call mode: {call_mode}")

    def call(
        request_suffix: str,
        tool_name: str,
        arguments: dict[str, Any],
    ) -> dict[str, Any]:
        method = tool_name
        params = arguments
        if call_mode == "standard":
            method = "tools/call"
            params = {"name": tool_name, "arguments": arguments}
        return _modern_call(
            endpoint,
            f"{label.lower()}-{call_mode}-{request_suffix}",
            method,
            params,
            headers=authorization_headers,
        )

    subscribe = call(
        "subscribe",
        "connectanum.pubsub.subscribe",
        {"topic": TOPIC, "queueLimit": 5},
    )
    subscription = _structured_content(
        subscribe, label=f"{label} {call_mode} subscribe"
    )
    handle = subscription.get("handle")
    if not isinstance(handle, str) or not handle or subscription.get("topic") != TOPIC:
        raise AssertionError(
            f"{label} {call_mode} subscribe returned invalid state: {subscription}"
        )

    marker = f"router-image-{label.lower()}-{call_mode}-publish"
    publish = call(
        "publish",
        "connectanum.pubsub.publish",
        {
            "topic": TOPIC,
            "argumentsKeywords": {"via": marker},
            "acknowledge": True,
        },
    )
    publication = _structured_content(
        publish, label=f"{label} {call_mode} publish"
    )
    if publication.get("topic") != TOPIC or publication.get("acknowledged") is not True:
        raise AssertionError(
            f"{label} {call_mode} publish was not acknowledged: {publication}"
        )

    events: list[Any] = []
    for attempt in range(40):
        poll = call(
            f"poll-{attempt}",
            "connectanum.pubsub.poll",
            {"handle": handle, "limit": 10},
        )
        poll_content = _structured_content(
            poll, label=f"{label} {call_mode} poll"
        )
        raw_events = poll_content.get("events")
        events = raw_events if isinstance(raw_events, list) else []
        if marker in json.dumps(events):
            break
        time.sleep(0.05)
    if marker not in json.dumps(events):
        raise AssertionError(
            f"{label} {call_mode} pub/sub poll missed the published event"
        )

    unsubscribe = call(
        "unsubscribe",
        "connectanum.pubsub.unsubscribe",
        {"handle": handle},
    )
    unsubscribe_content = _structured_content(
        unsubscribe, label=f"{label} {call_mode} unsubscribe"
    )
    if unsubscribe_content.get("unsubscribed") is not True:
        raise AssertionError(
            f"{label} {call_mode} unsubscribe failed: {unsubscribe_content}"
        )


def _run_modern_direct_pubsub(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    _run_modern_pubsub(
        endpoint,
        label=label,
        call_mode="direct",
        authorization_headers=authorization_headers,
    )


def _run_modern_standard_pubsub(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
) -> None:
    _run_modern_pubsub(
        endpoint,
        label=label,
        call_mode="standard",
        authorization_headers=authorization_headers,
    )


def _run_compatibility_pubsub(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
    verify_missing_bearer: bool = False,
    other_principal_authorization_headers: dict[str, str] | None = None,
    disallowed_session_id: str | None = None,
) -> str:
    compatibility_headers = {
        **(authorization_headers or {}),
        "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
    }
    _expect_initialize_notification_sessionless(
        endpoint,
        label=label,
        authorization_headers=authorization_headers,
    )
    initialize_headers, initialize = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": f"{label.lower()}-initialize",
            "method": "initialize",
            "params": {
                "protocolVersion": COMPATIBILITY_PROTOCOL,
                "capabilities": {},
                "clientInfo": {
                    "name": "router-image-runtime-smoke",
                    "version": "0.0.0",
                },
            },
        },
        headers=compatibility_headers,
    )
    session_id = initialize_headers.get("mcp-session-id")
    if not session_id:
        raise AssertionError(f"{label} initialize did not create a session")
    if session_id == disallowed_session_id:
        raise AssertionError(
            f"{label} initialize reused another principal's session ID"
        )
    if initialize.get("result", {}).get("protocolVersion") != COMPATIBILITY_PROTOCOL:
        raise AssertionError(f"{label} initialize changed the protocol version")

    session_headers = {
        **compatibility_headers,
        "MCP-Session-Id": session_id,
    }
    initialized_status, _, initialized_body = _request(
        endpoint,
        "POST",
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        headers=session_headers,
    )
    if initialized_status < 200 or initialized_status >= 300:
        raise AssertionError(
            f"{label} initialized notification returned {initialized_status}"
        )
    if initialized_body.strip():
        initialized_payload = _json_payload(initialized_body)
        if isinstance(initialized_payload, dict) and "error" in initialized_payload:
            raise AssertionError(
                f"{label} initialized notification failed: {initialized_payload}"
            )

    if verify_missing_bearer:
        _expect_unauthorized(
            endpoint,
            {
                "jsonrpc": "2.0",
                "id": "secure-missing-bearer-tools",
                "method": "tools/list",
                "params": {},
            },
            headers={
                "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
                "MCP-Session-Id": session_id,
            },
            label="Protected active session without bearer",
        )
        _, authenticated_tools = _post_json(
            endpoint,
            {
                "jsonrpc": "2.0",
                "id": "secure-restored-bearer-tools",
                "method": "tools/list",
                "params": {},
            },
            headers=session_headers,
        )
        if not isinstance(authenticated_tools.get("result", {}).get("tools"), list):
            raise AssertionError(
                f"Protected session was unusable after missing bearer: "
                f"{authenticated_tools}"
            )

    _, subscribe = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": f"{label.lower()}-subscribe",
            "method": "tools/call",
            "params": {
                "name": "connectanum.pubsub.subscribe",
                "arguments": {"topic": TOPIC, "queueLimit": 5},
            },
        },
        headers=session_headers,
    )
    subscription = _structured_content(subscribe, label=f"{label} subscribe")
    handle = subscription.get("handle")
    if not isinstance(handle, str) or not handle or subscription.get("topic") != TOPIC:
        raise AssertionError(f"{label} subscribe returned invalid state: {subscription}")

    if verify_missing_bearer:
        _expect_compatibility_session_methods_require_bearer(
            endpoint,
            label=label,
            session_id=session_id,
        )
    if other_principal_authorization_headers is not None:
        _expect_compatibility_session_isolated_from_other_principal(
            endpoint,
            label=label,
            session_id=session_id,
            authorization_headers=other_principal_authorization_headers,
        )
        _run_independent_principal_lifecycle(
            endpoint,
            label=f"{label}Peer",
            owner_session_id=session_id,
            authorization_headers=other_principal_authorization_headers,
        )
    _expect_modern_requests_ignore_compatibility_session(
        endpoint,
        label=label,
        session_id=session_id,
        subscription_handle=handle,
        authorization_headers=authorization_headers,
    )
    _expect_modern_session_methods_rejected(
        endpoint,
        label=label,
        session_id=session_id,
        authorization_headers=authorization_headers,
    )

    marker = f"router-image-{label.lower()}-streamable-publish"
    _, publish = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": f"{label.lower()}-publish",
            "method": "tools/call",
            "params": {
                "name": "connectanum.pubsub.publish",
                "arguments": {
                    "topic": TOPIC,
                    "argumentsKeywords": {"via": marker},
                    "acknowledge": True,
                },
            },
        },
        headers=session_headers,
    )
    publication = _structured_content(publish, label=f"{label} publish")
    if publication.get("topic") != TOPIC or publication.get("acknowledged") is not True:
        raise AssertionError(f"{label} publish was not acknowledged: {publication}")

    events: list[Any] = []
    for attempt in range(40):
        _, poll = _post_json(
            endpoint,
            {
                "jsonrpc": "2.0",
                "id": f"{label.lower()}-poll-{attempt}",
                "method": "tools/call",
                "params": {
                    "name": "connectanum.pubsub.poll",
                    "arguments": {"handle": handle, "limit": 10},
                },
            },
            headers=session_headers,
        )
        poll_content = _structured_content(poll, label=f"{label} poll")
        raw_events = poll_content.get("events")
        events = raw_events if isinstance(raw_events, list) else []
        if marker in json.dumps(events):
            break
        time.sleep(0.05)
    if marker not in json.dumps(events):
        raise AssertionError(f"{label} pub/sub poll missed the published event")

    _, unsubscribe = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": f"{label.lower()}-unsubscribe",
            "method": "tools/call",
            "params": {
                "name": "connectanum.pubsub.unsubscribe",
                "arguments": {"handle": handle},
            },
        },
        headers=session_headers,
    )
    unsubscribe_content = _structured_content(
        unsubscribe, label=f"{label} unsubscribe"
    )
    if unsubscribe_content.get("unsubscribed") is not True:
        raise AssertionError(f"{label} unsubscribe failed: {unsubscribe_content}")

    delete_status, delete_headers, delete_body = _request(
        endpoint, "DELETE", headers=session_headers
    )
    if delete_status != 202 or delete_body.strip():
        raise AssertionError(
            f"{label} DELETE returned {delete_status} with body {delete_body!r}"
        )
    if delete_headers.get("mcp-session-id") != session_id:
        raise AssertionError(f"{label} DELETE did not echo the removed session ID")
    return session_id


def _run_independent_principal_lifecycle(
    endpoint: str,
    *,
    label: str,
    owner_session_id: str,
    authorization_headers: dict[str, str],
) -> str:
    discovery = _modern_call(
        endpoint,
        f"{label.lower()}-discover",
        "server/discover",
        headers=authorization_headers,
    )
    if MODERN_PROTOCOL not in discovery.get("result", {}).get(
        "supportedVersions", []
    ):
        raise AssertionError(
            f"{label} modern discovery missed {MODERN_PROTOCOL}: {discovery}"
        )
    _run_modern_wamp_registration_session_meta(
        endpoint,
        label=label,
        call_mode="direct",
        expected_auth_id=OTHER_AUTH_ID,
        expected_auth_role="member",
        authorization_headers=authorization_headers,
    )
    _run_modern_direct_pubsub(
        endpoint,
        label=label,
        authorization_headers=authorization_headers,
    )
    independent_session_id = _run_compatibility_pubsub(
        endpoint,
        label=label,
        authorization_headers=authorization_headers,
        disallowed_session_id=owner_session_id,
    )
    if independent_session_id == owner_session_id:
        raise AssertionError(
            f"{label} compatibility lifecycle reused the owner's session ID"
        )
    return independent_session_id


def _run_protected_json_response_smoke(
    endpoint: str,
    *,
    authorization_headers: dict[str, str],
) -> None:
    initialize_payload = {
        "jsonrpc": "2.0",
        "id": "protected-json-initialize",
        "method": "initialize",
        "params": {
            "protocolVersion": COMPATIBILITY_PROTOCOL,
            "capabilities": {},
            "clientInfo": {
                "name": "router-image-json-response-smoke",
                "version": "0.0.0",
            },
        },
    }
    compatibility_headers = {
        "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
    }
    _expect_unauthorized(
        endpoint,
        initialize_payload,
        headers=compatibility_headers,
        label="Protected JSON-response initialize without bearer",
    )

    initialize_headers, initialize = _post_json_response(
        endpoint,
        initialize_payload,
        headers={**authorization_headers, **compatibility_headers},
    )
    session_id = initialize_headers.get("mcp-session-id")
    if not session_id:
        raise AssertionError("Protected JSON-response initialize missed a session ID")
    if (
        initialize_headers.get("mcp-protocol-version")
        != COMPATIBILITY_PROTOCOL
    ):
        raise AssertionError(
            "Protected JSON-response initialize missed the compatibility "
            "protocol header"
        )
    if initialize.get("result", {}).get("protocolVersion") != COMPATIBILITY_PROTOCOL:
        raise AssertionError(
            "Protected JSON-response initialize changed the protocol version"
        )

    session_headers = {
        **authorization_headers,
        **compatibility_headers,
        "MCP-Session-Id": session_id,
    }
    initialized_status, _, initialized_body = _request(
        endpoint,
        "POST",
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        headers=session_headers,
    )
    if initialized_status < 200 or initialized_status >= 300:
        raise AssertionError(
            "Protected JSON-response initialized notification returned "
            f"{initialized_status}"
        )
    if initialized_body.strip():
        initialized_payload = _json_payload(initialized_body)
        if isinstance(initialized_payload, dict) and "error" in initialized_payload:
            raise AssertionError(
                "Protected JSON-response initialized notification failed: "
                f"{initialized_payload}"
            )

    response_headers, count = _post_json_response(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": "protected-json-session-count",
            "method": "tools/call",
            "params": {
                "name": PROCEDURE,
                "arguments": {},
            },
        },
        headers=session_headers,
    )
    if response_headers.get("mcp-session-id") != session_id:
        raise AssertionError(
            "Protected JSON-response tool call changed the MCP session ID"
        )
    if response_headers.get("mcp-protocol-version") != COMPATIBILITY_PROTOCOL:
        raise AssertionError(
            "Protected JSON-response tool call missed the compatibility "
            "protocol header"
        )
    _structured_content(count, label="Protected JSON-response session count")

    delete_status, delete_headers, delete_body = _request(
        endpoint, "DELETE", headers=session_headers
    )
    if delete_status != 202 or delete_body.strip():
        raise AssertionError(
            "Protected JSON-response DELETE returned "
            f"{delete_status} with body {delete_body!r}"
        )
    if delete_headers.get("mcp-session-id") != session_id:
        raise AssertionError(
            "Protected JSON-response DELETE did not echo the removed session ID"
        )
    print(
        "Router Image MCP JSON-response evidence: "
        "json_response_ready=true protected=true compatibility_json=true "
        "protocol_header=true session_header=true session_delete=true "
        "post_sse_cursor=false."
    )


def _run_protected_smoke(
    secure_endpoint: str,
    json_response_endpoint: str,
    auth_endpoint: str,
) -> None:
    unauthenticated_payload = {
        "jsonrpc": "2.0",
        "id": "secure-unauthenticated-discover",
        "method": "server/discover",
        "params": _modern_params(),
    }
    unauthenticated_headers = {
        "MCP-Protocol-Version": MODERN_PROTOCOL,
        "Mcp-Method": "server/discover",
    }
    _expect_unauthorized(
        secure_endpoint,
        unauthenticated_payload,
        headers=unauthenticated_headers,
        label="Protected modern discovery without bearer",
    )

    grant = _issue_ticket_grant(auth_endpoint)
    access_token = str(grant["access_token"])
    authorization_headers = {"Authorization": f"Bearer {access_token}"}
    other_grant = _issue_ticket_grant(
        auth_endpoint,
        auth_id=OTHER_AUTH_ID,
        ticket=OTHER_AUTH_TICKET,
    )
    other_access_token = str(other_grant["access_token"])
    other_authorization_headers = {
        "Authorization": f"Bearer {other_access_token}"
    }
    secure_discovery = _modern_call(
        secure_endpoint,
        "secure-discover",
        "server/discover",
        headers=authorization_headers,
    )
    if MODERN_PROTOCOL not in secure_discovery.get("result", {}).get(
        "supportedVersions", []
    ):
        raise AssertionError(
            f"Protected modern discovery missed {MODERN_PROTOCOL}: {secure_discovery}"
        )
    if "completions" not in secure_discovery.get("result", {}).get(
        "capabilities", {}
    ):
        raise AssertionError("Protected modern discovery missed completions")
    _expect_modern_completions(
        secure_endpoint,
        label="Protected",
        authorization_headers=authorization_headers,
    )
    _expect_modern_batch_rejected(
        secure_endpoint,
        label="Protected",
        headers=authorization_headers,
    )
    secure_catalog = _modern_call(
        secure_endpoint,
        "secure-catalog",
        "connectanum.api.list",
        headers=authorization_headers,
    )
    if TOPIC not in json.dumps(
        _structured_content(secure_catalog, label="Protected direct API catalog")
    ):
        raise AssertionError(f"Protected direct API catalog missed {TOPIC}")

    _run_modern_standard_tool_catalog(
        secure_endpoint,
        label="Protected",
        authorization_headers=authorization_headers,
    )
    _run_modern_wamp_registration_session_meta(
        secure_endpoint,
        label="Protected",
        call_mode="direct",
        expected_auth_id=AUTH_ID,
        expected_auth_role="member",
        authorization_headers=authorization_headers,
    )
    _run_modern_wamp_registration_session_meta(
        secure_endpoint,
        label="Protected",
        call_mode="standard",
        expected_auth_id=AUTH_ID,
        expected_auth_role="member",
        authorization_headers=authorization_headers,
    )
    _run_modern_wamp_subscription_meta(
        secure_endpoint,
        label="Protected",
        call_mode="direct",
        authorization_headers=authorization_headers,
    )
    _run_modern_wamp_subscription_meta(
        secure_endpoint,
        label="Protected",
        call_mode="standard",
        authorization_headers=authorization_headers,
    )
    _run_modern_standard_pubsub(
        secure_endpoint,
        label="Protected",
        authorization_headers=authorization_headers,
    )
    _run_modern_direct_pubsub(
        secure_endpoint,
        label="Protected",
        authorization_headers=authorization_headers,
    )
    _run_compatibility_pubsub(
        secure_endpoint,
        label="Protected",
        authorization_headers=authorization_headers,
        verify_missing_bearer=True,
        other_principal_authorization_headers=other_authorization_headers,
    )
    _run_protected_json_response_smoke(
        json_response_endpoint,
        authorization_headers=authorization_headers,
    )
    for token in (other_access_token, access_token):
        _post_json(
            auth_endpoint,
            {
                "grant_type": "revoke",
                "token": token,
                "token_type_hint": "access_token",
            },
        )
    _expect_unauthorized(
        secure_endpoint,
        unauthenticated_payload,
        headers={**unauthenticated_headers, **authorization_headers},
        label="Protected modern discovery with revoked bearer",
    )


def run_smoke(
    endpoint: str,
    secure_endpoint: str,
    json_response_endpoint: str,
    auth_endpoint: str,
) -> None:
    discovery = _wait_for_discovery(endpoint)
    discovery_result = discovery.get("result")
    if not isinstance(
        discovery_result, dict
    ) or MODERN_PROTOCOL not in discovery_result.get("supportedVersions", []):
        raise AssertionError(f"Modern discovery missed {MODERN_PROTOCOL}: {discovery}")
    if "completions" not in discovery_result.get("capabilities", {}):
        raise AssertionError("Modern discovery missed completions")
    _expect_modern_completions(endpoint, label="Public")
    _expect_modern_batch_rejected(endpoint, label="Public")

    tools_by_name = _modern_tools_by_name(endpoint, label="Public")
    tool_names = set(tools_by_name)
    for expected in {
        "connectanum.api.list",
        "connectanum.pubsub.subscribe",
        "connectanum.pubsub.publish",
        "connectanum.pubsub.poll",
        "connectanum.pubsub.unsubscribe",
        "wamp.registration.match",
        "wamp.registration.get",
        "wamp.registration.list",
        "wamp.registration.lookup",
        "wamp.registration.list_callees",
        "wamp.registration.count_callees",
        "wamp.session.count",
        "wamp.session.list",
        "wamp.session.get",
        "wamp.subscription.match",
        "wamp.subscription.get",
        "wamp.subscription.list",
        "wamp.subscription.lookup",
        "wamp.subscription.list_subscribers",
        "wamp.subscription.count_subscribers",
    }:
        if expected not in tool_names:
            raise AssertionError(f"Modern tools/list missed {expected}")
    _expect_modern_standard_meta_tool_schemas(
        tools_by_name,
        label="Public",
    )

    catalog = _modern_call(endpoint, "modern-catalog", "connectanum.api.list")
    catalog_content = _structured_content(catalog, label="Modern direct API catalog")
    if TOPIC not in json.dumps(catalog_content):
        raise AssertionError(f"Modern direct API catalog missed {TOPIC}")

    _run_modern_standard_tool_catalog(endpoint, label="Public")
    _run_modern_wamp_registration_session_meta(
        endpoint,
        label="Public",
        call_mode="direct",
        expected_auth_id="anonymous",
        expected_auth_role="anonymous",
    )
    _run_modern_wamp_registration_session_meta(
        endpoint,
        label="Public",
        call_mode="standard",
        expected_auth_id="anonymous",
        expected_auth_role="anonymous",
    )
    _run_modern_wamp_subscription_meta(
        endpoint,
        label="Public",
        call_mode="direct",
    )
    _run_modern_wamp_subscription_meta(
        endpoint,
        label="Public",
        call_mode="standard",
    )
    _run_modern_standard_pubsub(endpoint, label="Public")
    _run_modern_direct_pubsub(endpoint, label="Public")
    _run_compatibility_pubsub(endpoint, label="Public")
    _run_protected_smoke(
        secure_endpoint,
        json_response_endpoint,
        auth_endpoint,
    )
    print(
        "Router Image MCP evidence: modern_batch_rejected=true "
        "status=400 error=-32600 sessionless=true "
        "modern_live_session_ignored=true standard=true direct=true "
        "modern_methods_rejected=true get=true delete=true "
        "compatibility_method_auth_isolated=true missing_bearer=true "
        "unknown_bearer=true compatibility_get=true compatibility_delete=true "
        "compatibility_principal_isolated=true valid_other_principal=true "
        "principal_post=true principal_get=true principal_delete=true "
        "authenticated_404=true requested_session_omitted=true "
        "independent_principal_ready=true direct_meta=true direct_pubsub=true "
        "sessionless_direct=true distinct_streamable_session=true "
        "streamable_pubsub=true owner_preserved=true "
        "compatibility_session_preserved=true "
        "initialize_notification_sessionless=true "
        "session_header_echoed=false completions=true "
        "public=true protected=true."
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--secure-endpoint", required=True)
    parser.add_argument("--json-response-endpoint", required=True)
    parser.add_argument("--auth-endpoint", required=True)
    arguments = parser.parse_args()
    run_smoke(
        arguments.endpoint,
        arguments.secure_endpoint,
        arguments.json_response_endpoint,
        arguments.auth_endpoint,
    )
    print("Router image public and protected MCP checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
