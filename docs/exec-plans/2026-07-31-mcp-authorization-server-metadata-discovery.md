# Exec Plan: MCP Authorization-Server Metadata Discovery

## Status

Active.

## Goal

Let public Dart MCP consumers continue from Protected Resource Metadata to
validated OAuth authorization-server endpoints without private URL assumptions,
credential leakage, or MCP session mutation.

## Scope

- Discover authorization-server metadata using the MCP 2025-11-25 priority
  order for RFC 8414 and OpenID Connect well-known endpoints.
- Validate exact issuer identity and the authorization, token, registration,
  PKCE, client-registration, and related capability metadata needed by later
  authorization-flow work.
- Preserve unknown metadata fields while exposing the interoperability-critical
  values through immutable typed APIs.
- Keep discovery independent from active MCP session state and reject caller
  attempts to forward bearer, cookie, or MCP session headers.
- Prove the API through `connectanum_client`, the public
  `connectanum_mcp_io.dart` boundary, and an isolated consumer-package smoke.

## Standards Direction

- MCP 2025-11-25 requires clients to support both RFC 8414 OAuth Authorization
  Server Metadata and OpenID Connect Discovery.
- Issuers with a path use OAuth path insertion, OpenID path insertion, then
  OpenID path appending. Root issuers use OAuth then OpenID root well-known
  endpoints.
- RFC 8414 and OpenID Connect require the returned `issuer` value to exactly
  match the issuer used to construct the discovery request.
- All production authorization-server endpoints remain HTTPS-only. Loopback
  HTTP is accepted solely for local development and deterministic tests, in
  line with the existing MCP discovery policy.

## Non-Goals

- Launch an interactive browser authorization flow.
- Register OAuth clients, generate PKCE challenges, or exchange authorization
  codes and refresh tokens.
- Select among multiple advertised authorization servers on behalf of an
  application.
- Persist authorization-server metadata or token state.

## Verification

- Focused authorization discovery and IO-entrypoint tests
- Isolated public-package consumer smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Confirmed the stable MCP 2025-11-25 fallback order and exact
  issuer requirements against the MCP authorization specification, RFC 8414,
  and OpenID Connect Discovery 1.0.
- 2026-07-31: Pre-change `bin/test-fast` passed.
- 2026-07-31: Added failing public API, exact-issuer, root/path fallback,
  credential-isolation, HTTPS endpoint, PKCE, IO export, and consumer-boundary
  regressions.
- 2026-07-31: Implemented immutable typed authorization-server metadata,
  MCP-ordered RFC 8414/OpenID discovery, exact issuer and MCP authorization-code
  capability validation, bounded credential-free requests, and the
  `McpStreamableHttpClient` convenience method.
- 2026-07-31: Extended the isolated public-package consumer smoke through both
  discovery stages while preserving an active authenticated MCP session.
- 2026-07-31: Focused tests, focused package analysis, and post-change
  `bin/test-fast` passed, including all MCP/client/router/native/benchmark
  suites and consumer smokes.
- 2026-07-31: Complete local `bin/verify` passed, including Rust and Dart
  suites, isolated and globally activated package consumers, all router-hosted
  MCP modes, the complete router suite, and Chrome/Dart2Wasm.
