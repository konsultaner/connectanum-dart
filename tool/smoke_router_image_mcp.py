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
AUTH_REALM = "image.smoke"
AUTH_ID = "image-smoke-agent"
AUTH_TICKET = "image-smoke-ticket"


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
    payload: dict[str, Any] | None = None,
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
    response_headers, response = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": _modern_params(arguments),
        },
        headers={
            **(headers or {}),
            "MCP-Protocol-Version": MODERN_PROTOCOL,
            "Mcp-Method": method,
        },
    )
    if response_headers.get("mcp-protocol-version") != MODERN_PROTOCOL:
        raise AssertionError(
            f"Modern response missed {MODERN_PROTOCOL} protocol header"
        )
    if response_headers.get("mcp-session-id") is not None:
        raise AssertionError("Modern stateless response unexpectedly created a session")
    return response


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


def _issue_ticket_grant(auth_endpoint: str) -> dict[str, Any]:
    status, _, body = _request(
        auth_endpoint,
        "POST",
        {
            "realm": AUTH_REALM,
            "authmethod": "ticket",
            "authid": AUTH_ID,
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
        {"state": state, "signature": AUTH_TICKET},
    )
    access_token = grant.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise AssertionError(f"Ticket auth response missed access_token: {grant}")
    if str(grant.get("token_type", "")).lower() != "bearer":
        raise AssertionError(f"Ticket auth response missed Bearer token type: {grant}")
    return grant


def _run_compatibility_pubsub(
    endpoint: str,
    *,
    label: str,
    authorization_headers: dict[str, str] | None = None,
    verify_missing_bearer: bool = False,
) -> None:
    compatibility_headers = {
        **(authorization_headers or {}),
        "MCP-Protocol-Version": COMPATIBILITY_PROTOCOL,
    }
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
            "method": "connectanum.pubsub.subscribe",
            "params": {"topic": TOPIC, "queueLimit": 5},
        },
        headers=session_headers,
    )
    subscription = _structured_content(subscribe, label=f"{label} subscribe")
    handle = subscription.get("handle")
    if not isinstance(handle, str) or not handle or subscription.get("topic") != TOPIC:
        raise AssertionError(f"{label} subscribe returned invalid state: {subscription}")

    marker = f"router-image-{label.lower()}-streamable-publish"
    _, publish = _post_json(
        endpoint,
        {
            "jsonrpc": "2.0",
            "id": f"{label.lower()}-publish",
            "method": "connectanum.pubsub.publish",
            "params": {
                "topic": TOPIC,
                "argumentsKeywords": {"via": marker},
                "acknowledge": True,
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
                "method": "connectanum.pubsub.poll",
                "params": {"handle": handle, "limit": 10},
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
            "method": "connectanum.pubsub.unsubscribe",
            "params": {"handle": handle},
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


def _run_protected_smoke(secure_endpoint: str, auth_endpoint: str) -> None:
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

    _run_compatibility_pubsub(
        secure_endpoint,
        label="Protected",
        authorization_headers=authorization_headers,
        verify_missing_bearer=True,
    )
    _post_json(
        auth_endpoint,
        {
            "grant_type": "revoke",
            "token": access_token,
            "token_type_hint": "access_token",
        },
    )
    _expect_unauthorized(
        secure_endpoint,
        unauthenticated_payload,
        headers={**unauthenticated_headers, **authorization_headers},
        label="Protected modern discovery with revoked bearer",
    )


def run_smoke(endpoint: str, secure_endpoint: str, auth_endpoint: str) -> None:
    discovery = _wait_for_discovery(endpoint)
    discovery_result = discovery.get("result")
    if not isinstance(
        discovery_result, dict
    ) or MODERN_PROTOCOL not in discovery_result.get("supportedVersions", []):
        raise AssertionError(f"Modern discovery missed {MODERN_PROTOCOL}: {discovery}")

    tools = _modern_call(endpoint, "modern-tools", "tools/list")
    tool_list = tools.get("result", {}).get("tools", [])
    tool_names = {
        tool.get("name") for tool in tool_list if isinstance(tool, dict)
    }
    for expected in {
        "connectanum.api.list",
        "connectanum.pubsub.subscribe",
        "connectanum.pubsub.publish",
        "connectanum.pubsub.poll",
        "connectanum.pubsub.unsubscribe",
    }:
        if expected not in tool_names:
            raise AssertionError(f"Modern tools/list missed {expected}")

    catalog = _modern_call(endpoint, "modern-catalog", "connectanum.api.list")
    catalog_content = _structured_content(catalog, label="Modern direct API catalog")
    if TOPIC not in json.dumps(catalog_content):
        raise AssertionError(f"Modern direct API catalog missed {TOPIC}")

    _run_compatibility_pubsub(endpoint, label="Public")
    _run_protected_smoke(secure_endpoint, auth_endpoint)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--secure-endpoint", required=True)
    parser.add_argument("--auth-endpoint", required=True)
    arguments = parser.parse_args()
    run_smoke(
        arguments.endpoint,
        arguments.secure_endpoint,
        arguments.auth_endpoint,
    )
    print("Router image public and protected MCP checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
