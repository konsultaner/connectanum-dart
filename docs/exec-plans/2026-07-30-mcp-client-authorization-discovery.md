# Exec Plan: MCP Client Authorization Discovery

## Status

Complete.

## Goal

Make the public Dart MCP client discover OAuth protected-resource metadata from
router-hosted and third-party Streamable HTTP endpoints without manual metadata
URL assumptions or credential leakage.

## Scope

- Parse Bearer `WWW-Authenticate` challenges, including authoritative scope and
  `resource_metadata` parameters.
- Expose parsed challenges and response headers on typed MCP HTTP failures.
- Discover and validate RFC 9728 Protected Resource Metadata from a challenge,
  the endpoint's JSON representation, or MCP's ordered well-known fallbacks.
- Keep discovery independent from active MCP session state and never forward
  bearer/session credentials to metadata requests.
- Prove the API through `connectanum_client` and the public
  `connectanum_mcp_io.dart` consumer boundary.

## Non-Goals

- Run an interactive browser authorization flow.
- Register OAuth clients or persist access and refresh tokens.
- Replace Connectanum ticket grants or manually supplied bearer tokens.
- Discover OAuth authorization-server endpoints; that is the next bounded
  authorization-readiness slice after protected-resource discovery.

## Verification

- `bin/test-fast`
- Focused client and MCP IO-entrypoint authorization discovery tests
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/verify`

## Progress

- 2026-07-30: Confirmed the current MCP authorization specification requires
  clients to parse Bearer challenges and support challenge-directed plus
  path-specific and root well-known Protected Resource Metadata discovery.
- 2026-07-30: Pre-change `bin/test-fast` passed.
- 2026-07-30: Added failing public API, security-boundary, ordered fallback,
  resource-validation, and package-entrypoint regressions.
- 2026-07-30: Implemented typed Protected Resource Metadata and discovery
  results, Bearer challenge parsing on normal HTTP failures, bounded
  credential-free metadata requests, exact resource matching, and the public
  IO entrypoint export.
- 2026-07-30: Extended the isolated public-package consumer smoke with an
  active-session Bearer challenge and metadata flow that rejects bearer or MCP
  session credential leakage.
- 2026-07-30: Focused tests, broader MCP suites, package analysis, formatting,
  `git diff --check`, and the complete local `bin/verify` passed.
