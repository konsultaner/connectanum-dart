# Exec Plan: MCP OAuth Token Exchange

## Status

Complete.

## Goal

Let public Dart MCP consumers redeem a validated authorization code for an
MCP-resource-bound OAuth bearer grant and hand that grant to a fresh
Streamable HTTP client without reimplementing token endpoint behavior.

## Scope

- POST an RFC 6749 authorization-code request as
  `application/x-www-form-urlencoded`.
- Send the validated code, original redirect URI and client ID, RFC 7636 PKCE
  verifier, and the canonical MCP RFC 8707 `resource`.
- Support pre-registered public clients plus `client_secret_basic` and
  `client_secret_post` confidential clients with discovered-method checks.
- Parse successful bearer-token responses into an immutable typed grant,
  including optional refresh token, expiry, scope, and extension fields.
- Parse OAuth token endpoint failures into a typed exception without exposing
  client secrets or tokens.
- Add a `McpStreamableHttpClient` helper and isolated public-package consumer
  smoke without mutating an existing MCP session.

## Standards Direction

- MCP 2025-11-25 requires the canonical RFC 8707 `resource` in both
  authorization and token requests.
- RFC 6749 token requests use form encoding and token responses use JSON with
  `Cache-Control: no-store` and `Pragma: no-cache`.
- RFC 7636 requires the original code verifier when redeeming the code.
- Authorization-server metadata controls the supported token endpoint client
  authentication methods; absent metadata defaults to `client_secret_basic`.

## Non-Goals

- Launch a browser or host a redirect listener.
- Register clients or publish Client ID Metadata Documents.
- Refresh or revoke OAuth authorization-server tokens.
- Persist client secrets, authorization state, or token state.
- Support private-key JWT or mutual-TLS client authentication.

## Verification

- Focused token request, response, error, auth-method, and IO-entrypoint tests
- Isolated public-package consumer smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Confirmed token request, PKCE, resource indicator, client
  authentication, and response requirements against MCP 2025-11-25,
  RFC 6749, RFC 7636, RFC 8414, and RFC 8707.
- 2026-07-31: Pre-change `bin/test-fast` passed.
- 2026-07-31: Added immutable public client-auth and bearer-grant models,
  bounded authorization-code exchange with strict response parsing, and
  Streamable HTTP helpers that enforce MCP resource binding without reusing
  MCP session credentials or state.
- 2026-07-31: Focused token request, response, error, auth-method, resource,
  timeout, redirect, and IO-entrypoint tests passed. Focused package analysis
  also passed.
- 2026-07-31: The first post-change `bin/test-fast` found one generated
  consumer-smoke assertion using a typed tool getter against the direct JSON
  map contract. The assertion was corrected, and the isolated client-only
  public-package smoke then passed through analysis, runtime use, and global
  executable activation.
- 2026-07-31: Complete `bin/verify` passed, including formatting, Rust and FFI
  tests, all Dart package suites, isolated and globally activated consumer
  smokes, all 96 benchmark tests, the complete 377-test router suite, focused
  native forwarding, and Chrome/Dart2Wasm.
