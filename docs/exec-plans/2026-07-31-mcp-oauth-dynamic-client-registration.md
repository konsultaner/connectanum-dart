# Exec Plan: MCP OAuth Dynamic Client Registration

## Status

Complete.

## Goal

Let public Dart MCP consumers use RFC 7591 Dynamic Client Registration as the
standards-defined fallback when preregistered client information and Client ID
Metadata Documents are unavailable, without leaking MCP session credentials or
accepting a silently changed confidential-client registration.

## Scope

- Add immutable validated metadata for a public dynamic OAuth client,
  including an explicit native/web application type.
- Register through the discovered authorization-server
  `registration_endpoint` using bounded JSON HTTP behavior and an optional
  initial access token.
- Parse successful RFC 7591 client-information responses into a public-client
  identity reusable by authorization, exchange, refresh, and revocation.
- Fail closed on redirects, missing or malformed response metadata, changed
  redirect registration, confidential-client credentials, unsupported token
  authentication, oversized bodies, unsafe headers, and unbounded waits.
- Surface typed registration errors without including access tokens, client
  secrets, or raw response bodies in exception strings.
- Export the API through the public MCP entrypoints and prove it through an
  isolated router-hosted consumer smoke while preserving active Streamable
  HTTP session state.

## Standards Direction

- MCP 2025-11-25 defines registration precedence as preregistered client
  information, Client ID Metadata Documents when advertised, then RFC 7591
  Dynamic Client Registration when `registration_endpoint` is advertised.
- RFC 7591 registration sends a JSON object to the registration endpoint and
  requires HTTP 201 plus a JSON client-information response containing the
  assigned `client_id` and all registered metadata.
- Public clients request `token_endpoint_auth_method: none`, authorization-code
  and refresh-token grants, the `code` response type, and exact HTTPS or
  loopback-HTTP redirects. A returned secret or changed token authentication
  method is rejected rather than silently converting the consumer into a
  confidential client.
- Current MCP draft guidance requires an appropriate OpenID Connect
  `application_type` during DCR. This API therefore requires callers to choose
  `native` or `web`; servers that do not use OIDC can ignore the extension.
- An optional RFC 7591 initial access token is sent only as a Bearer credential
  to the registration endpoint. Active MCP bearer/session/protocol/resume state
  is never forwarded.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://modelcontextprotocol.io/specification/draft/basic/authorization>
- <https://www.rfc-editor.org/rfc/rfc7591.html>
- <https://www.rfc-editor.org/rfc/rfc9700.html>

## Non-Goals

- Implement RFC 7592 registration management, rotation, update, or deletion.
- Persist or automatically reuse registrations across application launches.
- Launch a browser or host a redirect listener.
- Add software statements, confidential-client secrets, private-key JWT,
  DPoP, or mutual-TLS client authentication.
- Change authorization-server-side registration behavior in the router.

## Verification

- Focused request, response, error, redaction, timeout, and session-isolation
  tests
- Public IO-entrypoint and isolated consumer-package smoke coverage
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Pre-change `bin/test-fast` passed, including all MCP/client
  OAuth suites, isolated and globally activated consumers, router-hosted MCP
  modes, WAMP benchmark integration, and router CLI consumer coverage.
- 2026-07-31: Confirmed the MCP registration fallback order, current
  application-type guidance, RFC 7591 request/response/error contract, exact
  redirect requirements, and OAuth security guidance against official sources.
- 2026-07-31: Added immutable native/web public-client registration request
  and result types, the public `registerMcpOAuthClient(...)` API, and a
  Streamable-client convenience method that reuses only connection resources.
- 2026-07-31: Added bounded JSON registration with optional initial access
  tokens, controlled-header enforcement, redirect refusal, typed redacted
  errors, and fail-closed validation of returned public-client metadata.
- 2026-07-31: Added eight focused request/response/error/timeout/session
  regressions, public IO-entrypoint lifecycle coverage, and an isolated
  consumer smoke that carries the dynamic identity through authorization,
  token exchange, refresh, revocation, and router-hosted tool use.
- 2026-07-31: Focused package analysis and tests plus post-change
  `bin/test-fast` passed. A clean complete `bin/verify` then passed formatting,
  113 Rust core tests, 52 FFI tests, 360 core Dart tests, 85 MCP tests, 152
  client MCP tests, all 96 benchmark tests, the complete 377-test router suite,
  isolated and globally activated consumer smokes, router-hosted MCP variants,
  native forwarding checks, and Chrome/Dart2Wasm.
