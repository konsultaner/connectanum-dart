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
        {"arguments": [PROCEDURE]},
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
        {"arguments": [registration_id]},
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
        {"arguments": [session_id]},
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
        {"arguments": [PROCEDURE]},
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
        {"arguments": [registration_id]},
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
        {"arguments": [registration_id]},
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
        {"arguments": [TOPIC]},
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
        {"arguments": [subscription_id]},
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
        {"arguments": [TOPIC]},
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
        {"arguments": [subscription_id]},
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
        {"arguments": [subscription_id]},
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
    _expect_modern_batch_rejected(endpoint, label="Public")

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
    _run_protected_smoke(secure_endpoint, auth_endpoint)
    print(
        "Router Image MCP evidence: modern_batch_rejected=true "
        "status=400 error=-32600 sessionless=true public=true protected=true."
    )


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
