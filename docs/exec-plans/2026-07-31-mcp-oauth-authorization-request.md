# Exec Plan: MCP OAuth Authorization Request

## Status

Complete.

## Goal

Let public Dart MCP consumers safely prepare an OAuth authorization-code
request and validate its redirect callback after completing both MCP metadata
discovery stages.

## Scope

- Generate RFC 7636 PKCE verifier/challenge pairs with secure randomness and
  mandatory `S256`.
- Build authorization URLs from validated authorization-server metadata with
  `response_type=code`, the canonical MCP `resource`, redirect URI, selected
  scopes, state, and PKCE parameters.
- Preserve non-conflicting authorization-endpoint query parameters while
  rejecting ambiguous controlled parameters.
- Parse redirect callbacks with exact state and redirect-target validation,
  returning authorization codes or typed OAuth failures.
- Export the API through `connectanum_client/mcp.dart` and
  `connectanum_mcp_io.dart`, and prove it through an isolated consumer package.

## Standards Direction

- MCP 2025-11-25 requires authorization and token requests to carry the
  canonical RFC 8707 `resource` identifier.
- MCP clients must use RFC 7636 PKCE with `S256`; a generated 32-byte verifier
  produces the recommended 43-character unpadded base64url value.
- Redirect URIs remain HTTPS in production, with loopback HTTP accepted for
  native local application callbacks.
- OAuth `state` is generated per request and must match exactly before a code
  or authorization-server error is accepted.

## Non-Goals

- Launch a browser or host a loopback callback listener.
- Register OAuth clients or publish Client ID Metadata Documents.
- Exchange authorization codes, refresh tokens, or revoke OAuth tokens.
- Persist verifier, state, client credentials, or token state.

## Verification

- Focused PKCE, request, callback, and IO-entrypoint tests
- Isolated public-package consumer smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Confirmed the authorization request, resource indicator, PKCE,
  redirect security, and state requirements against MCP 2025-11-25, RFC 7636,
  and RFC 8707.
- 2026-07-31: Pre-change `bin/test-fast` passed.
- 2026-07-31: Added the public PKCE, authorization-request, and callback API
  with `S256`, canonical resource binding, generated state, controlled-query
  rejection, exact callback validation, and typed OAuth failures.
- 2026-07-31: Focused OAuth and IO-entrypoint tests passed with verifier
  boundaries, repeated endpoint query values, full OAuth scope-token coverage,
  redirect ownership, ambiguous callback, and unsafe error-link regressions.
- 2026-07-31: The isolated consumer smoke now prepares and validates an OAuth
  authorization request from an active MCP session without mutating session
  state.
- 2026-07-31: Post-change `bin/test-fast` and complete local `bin/verify`
  passed, including package consumers, all router-hosted MCP modes, 96
  benchmark tests, the complete router suite, and Chrome/Dart2Wasm.
