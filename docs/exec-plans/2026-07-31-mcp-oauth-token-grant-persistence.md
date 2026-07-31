# Exec Plan: MCP OAuth Token Grant Persistence

## Status

Complete.

## Goal

Let downstream Dart and Flutter applications persist a resource-bound OAuth
access/refresh grant in caller-owned secure storage and restore it after an
application restart without losing expiry, issuer, resource, client, scope, or
refresh-token rotation state.

## Scope

- Add a versioned JSON representation for `McpOAuthTokenGrant`.
- Persist the sensitive access token and optional refresh token together with
  the original issuance and absolute access-token expiry timestamps, effective
  scopes, canonical MCP resource, client identifier, authorization-server
  metadata, and JSON-compatible extension parameters.
- Revalidate every stored token response field and the authorization-server
  metadata during restoration.
- Allow callers to pin the expected authorization-server issuer, MCP resource,
  and client identifier so a stored grant cannot be replayed into a different
  trust context.
- Keep client authentication credentials outside the grant document; callers
  must continue to provide the appropriate public or confidential client
  authentication when refreshing or revoking.
- Reject expired access tokens when constructing a bearer-backed MCP client
  while still allowing an expired grant with a refresh token to be restored
  and refreshed.
- Keep persistence and expiry failures typed and redacted so access tokens,
  refresh tokens, client identifiers, and extension values do not reach
  exception strings.
- Prove initial and rotated grant JSON round trips through focused client
  tests, the public MCP IO entrypoint, and the generated consumer-package
  lifecycle smoke.

## Standards Direction

- MCP 2025-11-25 requires secure token storage and refresh-token rotation for
  public clients.
- The current MCP draft explicitly requires refresh tokens to remain
  confidential in transit and storage.
- RFC 6749 defines `expires_in` relative to token-response generation and
  requires refresh-token confidentiality and client binding.
- RFC 9700 requires refresh tokens to remain bound to the authorized scope and
  resource servers, and requires rotation or sender constraining for public
  clients. The persistence document therefore keeps the validated issuer,
  resource, client, and scope associations rather than storing bare token
  strings.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://modelcontextprotocol.io/specification/draft/basic/authorization>
- <https://www.rfc-editor.org/rfc/rfc6749.html>
- <https://www.rfc-editor.org/rfc/rfc9700.html>

## Non-Goals

- Add a concrete filesystem, keychain, credential-vault, database, or Flutter
  storage plugin.
- Persist client secrets or reconstruct confidential-client authentication
  from the grant document.
- Automatically refresh grants in the background or prescribe application
  lifecycle policy.
- Synchronize refresh-token rotation across multiple application processes or
  devices.
- Treat revocation as a remote deletion protocol for caller-owned storage;
  consumers remain responsible for deleting a revoked persisted document.

## Verification

- Focused JSON round-trip, expiry, issuer/resource/client binding, tamper,
  extension, rotation, and redaction regressions
- Public MCP IO-entrypoint lifecycle regression
- Isolated and globally activated client consumer-package smokes
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Selected token-grant persistence as the next bounded MCP
  downstream-readiness slice after pending authorization and dynamic client
  registration persistence. MCP 2025-11-25, the current MCP draft, RFC 6749,
  and RFC 9700 were reviewed before implementation.
- 2026-07-31: Added a versioned sensitive grant document with issue and
  absolute expiry timestamps, validated authorization-server metadata,
  issuer/resource/client pins, effective scopes, access and rotated refresh
  tokens, deeply immutable JSON extensions, and client-credential exclusion.
  Expired access grants restore for explicit refresh but are rejected when
  constructing a bearer-backed MCP client; all persistence failures remain
  typed and redacted.
- 2026-07-31: Focused token-grant and public IO-entrypoint regressions passed,
  including initial and rotated grant JSON round trips. The isolated and
  globally activated generated client consumer smoke passed after restoring
  both grants with all three trust-context pins.
- 2026-07-31: Post-change `bin/test-fast` passed, including 360 core tests, 85
  MCP tests, 174 client MCP tests, all 96 benchmark tests, generated consumers,
  router-hosted MCP modes, the router CLI consumer, and focused native/router
  auth and session coverage.
- 2026-07-31: Full `bin/verify` passed with formatting, 113 Rust core tests, 52
  FFI tests, 360 core Dart tests, 85 MCP tests, 174 client MCP tests, all 96
  benchmark tests, the complete 377-test router suite, isolated and globally
  activated package consumers, all router-hosted MCP smoke variants, 13 focused
  native/router tests, and Chrome/Dart2Wasm.
