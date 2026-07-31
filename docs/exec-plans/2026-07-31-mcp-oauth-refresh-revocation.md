# Exec Plan: MCP OAuth Refresh and Revocation

## Status

Complete.

## Goal

Let public Dart MCP consumers refresh and revoke resource-bound OAuth bearer
grants through discovered authorization-server endpoints without reimplementing
credential transport or contaminating an active Streamable HTTP session.

## Scope

- Parse RFC 8414 `revocation_endpoint` and
  `revocation_endpoint_auth_methods_supported` metadata.
- Refresh an issued grant through the discovered token endpoint with the
  original client identity, refresh token, canonical MCP resource, and optional
  downscoped scopes.
- Preserve the current refresh token when the server does not rotate it and
  replace it when the server does.
- Revoke either an access token or refresh token through the discovered RFC
  7009 endpoint.
- Support the existing pre-registered public-client, `client_secret_basic`, and
  `client_secret_post` authentication methods with endpoint-specific discovery
  checks.
- Add `McpStreamableHttpClient` convenience methods, IO-entrypoint coverage, and
  an isolated consumer smoke that proves refreshed and revoked credentials
  against a router-hosted MCP endpoint.

## Standards Direction

- MCP 2025-11-25 requires the canonical RFC 8707 `resource` in token requests;
  refresh therefore retains the exact resource bound to the original grant.
- RFC 6749 section 6 sends refresh requests as form-encoded token requests,
  permits equal or narrower scopes, and allows refresh-token rotation.
- RFC 8707 applies `resource` to access-token requests for every grant type,
  including `refresh_token`.
- RFC 8414 advertises the revocation endpoint and its client-auth methods; an
  omitted revocation auth-method list defaults to `client_secret_basic`.
- RFC 7009 treats HTTP 200 as successful revocation even when the submitted
  token is already invalid and requires clients to keep a token on retryable or
  error responses.

## Non-Goals

- Persist or automatically schedule token refresh.
- Launch a browser or host a redirect listener.
- Register clients or publish Client ID Metadata Documents.
- Add private-key JWT, DPoP, or mutual-TLS client authentication.
- Mutate an existing immutable grant or silently replace credentials in an
  already-constructed MCP client.

## Verification

- Focused authorization-metadata, refresh, revocation, redaction, and
  Streamable-session-isolation tests
- IO-entrypoint and isolated public-package consumer smokes
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Confirmed the refresh, resource-indicator, metadata, endpoint
  authentication, rotation, and idempotent revocation requirements against MCP
  2025-11-25, RFC 6749, RFC 7009, RFC 8414, and RFC 8707.
- 2026-07-31: Pre-change `bin/test-fast` passed.
- 2026-07-31: Added revocation metadata discovery, resource-bound refresh with
  scope non-escalation and refresh-token rotation, access- or refresh-token
  revocation, endpoint-specific client authentication, bounded HTTP behavior,
  and redacted typed errors.
- 2026-07-31: Added Streamable client conveniences that preserve active session
  and resume state, IO-entrypoint coverage, and a public-package consumer smoke
  that proves exchange, router-hosted direct JSON use, refresh, refreshed use,
  revocation, and revoked-token rejection.
- 2026-07-31: Focused OAuth tests passed with 12 cases, focused client and MCP
  analysis passed, the 18-case public package-boundary suite passed, and
  post-change `bin/test-fast` passed.
- 2026-07-31: Complete local `bin/verify` passed, including formatting, native
  tests, tooling regressions, all Dart package suites, isolated and globally
  activated consumers, router-hosted MCP lifecycle smokes, the 377-test router
  suite, and Chrome/Dart2Wasm.
- 2026-07-31: Commit `6f9ad48` passed exact-head GitHub CI `30613206786`,
  including Fast Checks, Full Verify, Dart VM Coverage, and Codecov upload.
  Dart Package Publish Dry Run `30613206990` and WAMP Profile Benchmarks
  `30613206772` also passed. The strict deployment-chain audit passed with all
  required exact-head, branch, workflow, package, benchmark, artifact, and
  registry gates clean.
