# Exec Plan: MCP Client ID Metadata Document

## Status

Complete.

## Goal

Let public Dart MCP consumers describe and use a standards-conforming public
OAuth client identity when an authorization server advertises Client ID
Metadata Document support, without shared secrets or consumer-private
assumptions.

## Scope

- Add a typed immutable Client ID Metadata Document for public OAuth clients.
- Validate the HTTPS client identifier, redirect URIs, client presentation
  metadata, scopes, and public-client authentication metadata before emitting
  JSON.
- Integrate the document with the existing authorization-request and token
  lifecycle APIs so the same URL client identifier and redirect registration
  are used throughout the grant.
- Require discovered authorization-server support before selecting this
  registration mechanism.
- Export the API through the public MCP entrypoints.
- Extend isolated package-boundary and router-hosted consumer smoke coverage
  through authorization, exchange, refresh, revocation, and active-session
  isolation.

## Standards Direction

- MCP 2025-11-25 selects client registration in this order: pre-registered
  clients, Client ID Metadata Documents when
  `client_id_metadata_document_supported` is advertised, then RFC 7591 dynamic
  registration when a registration endpoint is advertised.
- The MCP-pinned Client ID Metadata Document draft requires an HTTPS URL client
  identifier with a non-root path; the fetched document's `client_id` must
  exactly equal that URL.
- The client metadata includes at least `client_id`, `client_name`, and
  `redirect_uris`. Public MCP clients use `token_endpoint_auth_method: none`
  and do not publish shared-secret fields.
- Registered redirect URIs are exact values. This implementation accepts HTTPS
  redirects and loopback HTTP redirects, matching the MCP communication
  security requirements and the existing local-development OAuth flow.
- The implementation enforces the stable public-client subset shared by the
  MCP-pinned draft and the current IETF draft rather than depending on
  later-draft optional extensions.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://datatracker.ietf.org/doc/html/draft-ietf-oauth-client-id-metadata-document-00>
- <https://www.ietf.org/archive/id/draft-ietf-oauth-client-id-metadata-document-02.html>

## Non-Goals

- Implement RFC 7591 dynamic client registration.
- Fetch, host, cache, or persist the client metadata document.
- Launch a browser or host a redirect listener.
- Persist grants or automatically schedule token refresh.
- Add confidential-client secrets, private-key JWT, DPoP, or mutual TLS.

## Verification

- Focused metadata validation, JSON, authorization integration, export, and
  lifecycle-isolation tests
- Isolated public-package and router-hosted consumer smokes
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Confirmed MCP registration precedence and the Client ID Metadata
  Document URL, exact-identity, redirect, and public-client requirements
  against MCP 2025-11-25 and the pinned/current IETF drafts.
- 2026-07-31: Pre-change `bin/test-fast` passed, including the router-hosted
  consumer smoke matrix.
- 2026-07-31: Added immutable public Client ID Metadata Documents with strict
  HTTPS client identity, redirect, presentation URI, scope, and credential-free
  JSON validation.
- 2026-07-31: Added fail-closed authorization integration that requires
  discovered metadata-document and public token-endpoint authentication
  support, exact registered redirects, and reuse of the same client identity
  for the existing token lifecycle.
- 2026-07-31: Added four focused validation/integration regressions, IO
  re-export coverage, and an isolated public-package consumer smoke that proves
  authorization, exchange, router-hosted direct JSON use, refresh, revocation,
  and active Streamable-session isolation with the URL client identifier.
- 2026-07-31: Focused tests and package analysis passed. Post-change
  `bin/test-fast` and complete local `bin/verify` passed, including 85 MCP
  tests, 144 client MCP tests, all 96 benchmark tests, the 377-test router
  suite, isolated and globally activated package consumers, and
  Chrome/Dart2Wasm.
