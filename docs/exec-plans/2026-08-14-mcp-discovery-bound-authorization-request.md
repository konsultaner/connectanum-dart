# Exec Plan: MCP Discovery-Bound Authorization Request

Status: implementation complete; local verification green; hosted evidence pending
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-15

## Goal

Let a downstream application create its initial MCP OAuth authorization request
from validated protected-resource and authorization-server discovery results
without accidentally combining an MCP resource with an unrelated issuer.

## Scope

- In scope:
  - Add a public request builder that binds the canonical MCP resource to its
    validated Protected Resource Metadata and a caller-selected advertised
    authorization server.
  - Apply the stable MCP initial-scope priority: challenged scopes first,
    otherwise Protected Resource Metadata `scopes_supported`.
  - Let callers add explicit scopes without silently broadening authorization.
  - Preserve S256 PKCE, exact issuer handling, and active Streamable HTTP
    session, resume, protocol, and credential state.
  - Prove the flow through focused, public IO, and isolated installed-package
    coverage without private project assumptions.
- Out of scope:
  - Choosing among multiple advertised authorization servers for the user.
  - Choosing preregistration, Client ID Metadata Documents, or Dynamic Client
    Registration on behalf of the consuming application.
  - Launching a user agent, exchanging a code, or installing a bearer grant.

## Preconditions

- Commit `a27be47e` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The existing hosted-evidence notes are docs-only and will be bundled with
  this implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository and
  consumer-smoke matrix.

## Plan

1. Add fail-first coverage for discovery-bound request construction, scope
   priority, issuer mismatch rejection, and unchanged client state.
2. Implement the public free function and `McpStreamableHttpClient` wrapper.
3. Extend the public IO and generated installed-package consumer smokes.
4. Update durable protocol/readiness notes and run focused checks plus full
   repository verification.
5. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence for the affected public package paths.

## Verification

- Focused OAuth authorization and Streamable HTTP client tests.
- Public MCP IO entrypoint test and generated installed-package consumer smoke.
- Affected package analysis and shell/Python validation.
- `bin/verify`.

## Decision Log

- 2026-08-14: Stable MCP `2026-07-28` requires authorization-server discovery
  to start from Protected Resource Metadata and makes authorization-server
  selection a client responsibility. The current APIs validate each document
  independently but do not provide a safe construction boundary that proves
  the selected issuer was advertised for the canonical MCP resource.
- 2026-08-14: Selection policy and registration mechanism remain application
  decisions. The package will validate the caller's selection and construct
  the request, not silently choose an issuer or credentials.

## Handoff

- The public free function and `McpStreamableHttpClient` wrapper now reject a
  discovery result for another resource or a selected authorization server
  not advertised by that resource before constructing a browser-facing URL.
  Static validation failures do not disclose untrusted issuer/resource values.
- Initial scopes prefer the live Bearer challenge, otherwise use Protected
  Resource Metadata, and preserve order while deduplicating explicit caller
  additions. Multiple advertised authorization servers remain caller-selected.
- Focused discovery/request tests cover challenge-first and metadata-fallback
  scopes, multiple advertised issuers, redacted issuer mismatch, resource
  mismatch, and unchanged session/resume state. The public MCP IO lifecycle and
  generated path/global installed-package consumer smoke use the new boundary.
- `bin/verify` exits zero with formatting and analysis, Rust core and FFI
  suites, 366 core tests, 116 MCP tests, the 289-case MCP/client suite, 97
  benchmark tests including all 37 live WAMP workloads, the 442-case router
  suite, six remote-auth tests, 13 native follow-ups, every maintained consumer
  smoke, Chrome, and Dart2Wasm green.
- Commit, push, exact-head hosted workflows, and the strict deployment-chain
  audit remain pending.
