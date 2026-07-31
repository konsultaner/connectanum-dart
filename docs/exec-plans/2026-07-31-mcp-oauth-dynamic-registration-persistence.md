# Exec Plan: MCP OAuth Dynamic Registration Persistence

## Status

Complete.

## Goal

Let downstream Dart and Flutter applications persist an issued public dynamic
client registration and restore the same validated client identity after an
application restart, without registering a new client on every launch or
trusting an unvalidated storage document.

## Scope

- Add a versioned JSON representation for
  `McpOAuthDynamicClientRegistration`.
- Persist the validated public client identity, registered redirect URIs,
  application type, presentation metadata, scopes, grant and response types,
  issuance timestamp, authorization-server metadata, and JSON-compatible
  extension parameters.
- Revalidate the authorization-server metadata and every registered client
  field during restoration, including the exact public `none` token-endpoint
  authentication contract.
- Preserve the authorization-server issuer association in the document so a
  restored client identity cannot become detached from the server that issued
  it.
- Keep persistence failures typed and redacted so stored payloads, client
  identifiers, and extension values do not reach exception strings.
- Prove JSON encode/decode restoration through focused client tests, the MCP
  IO package entrypoint, and the generated consumer-package lifecycle smoke.

## Standards Direction

- MCP 2025-11-25 retains RFC 7591 Dynamic Client Registration as the fallback
  registration mechanism when the preferred Client ID Metadata Document
  mechanism is unavailable.
- The current MCP draft explicitly requires persisted client credentials to
  remain associated with the authorization server issuer that issued them.
  The persistence document therefore carries validated authorization-server
  metadata rather than only a bare client identifier.
- RFC 7591 requires successful registration responses to return the client
  identifier and all registered metadata. Restoration revalidates that same
  standard public-client response shape instead of accepting an opaque cache.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://modelcontextprotocol.io/specification/draft/basic/authorization>
- <https://www.rfc-editor.org/rfc/rfc7591.html>

## Non-Goals

- Persist bearer or refresh-token grants; that remains the next bounded auth
  persistence slice.
- Add a concrete filesystem, keychain, credential-vault, database, or Flutter
  storage plugin.
- Add RFC 7592 registration management, registration access-token handling,
  or remote registration validity probes.
- Persist confidential-client secrets or relax the existing public-client,
  redirect, scope, or presentation-metadata validation.

## Verification

- Focused JSON round-trip, issuer binding, schema, tamper, extension, and
  redaction regressions
- Public MCP IO-entrypoint lifecycle regression
- Isolated and globally activated client consumer-package smokes
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Selected dynamic-registration persistence as the next bounded
  downstream-readiness slice after pending authorization transactions. Stable
  MCP and RFC 7591 requirements plus the current MCP issuer-binding direction
  were reviewed before implementation.
- 2026-07-31: Added a versioned JSON document that carries validated
  authorization-server metadata and the complete issued public registration.
  Restoration optionally pins the expected issuer, reuses the existing
  registration-response validation, rejects confidential credentials and
  registration management tokens, deeply validates and freezes extension
  data, and exposes only redacted state failures.
- 2026-07-31: The public MCP IO regression and generated client consumer now
  JSON-encode and restore the issued registration before preparing the
  authorization request. Focused analysis, 171 client MCP tests, 85 MCP
  package tests, all 18 package-boundary tests, and isolated plus globally
  activated consumer smokes passed.
- 2026-07-31: Post-change `bin/test-fast` passed, including 360 core tests, 85
  MCP tests, 171 client MCP tests, all 96 benchmark tests, generated consumers,
  router-hosted MCP modes, the router CLI consumer, and focused native/router
  auth and session coverage.
- 2026-07-31: Full `bin/verify` passed with formatting, 113 Rust core tests, 52
  FFI tests, 360 core Dart tests, 85 MCP tests, 171 client MCP tests, all 96
  benchmark tests, the complete 377-test router suite, isolated and globally
  activated package consumers, all router-hosted MCP smoke variants, 13 focused
  native/router tests, and Chrome/Dart2Wasm.
- 2026-07-31: Commit `6da5288` was pushed to both `master` remotes. Exact-head
  GitHub CI `30652221043`, Dart Package Publish Dry Run `30652221118`, and WAMP
  Profile Benchmarks `30652221036` passed on their first attempts. CI included
  Fast Checks, Full Verify, Dart VM Coverage, Codecov upload, and the coverage
  artifact; the WAMP run uploaded its benchmark artifact. The strict
  deployment-chain audit passed with clean exact-head CI logs and all required
  branch, workflow, package, benchmark-artifact, and registry gates clean.
