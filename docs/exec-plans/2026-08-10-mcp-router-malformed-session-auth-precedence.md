# MCP Router Malformed-Session Auth Precedence

Status: completed

## Goal

Require a bearer-protected router-hosted MCP endpoint to authenticate the
request before rejecting a malformed compatibility `MCP-Session-Id`, while
preserving sessionless HTTP 400 validation for public routes and for protected
requests carrying a valid router-issued bearer.

## Context

Router-hosted MCP currently validates the syntax of `MCP-Session-Id` before it
resolves the route principal. A missing or unknown bearer can therefore receive
HTTP 400 without the protected endpoint's Bearer challenge merely by sending a
malformed session header. This differs from the established authorization
precedence for request-body bounds, session capacity, response negotiation,
and compatibility endpoint lookup.

The maintained MCP authorization contract requires protected HTTP resources to
return HTTP 401 for missing or invalid access tokens and to expose protected
resource discovery through the Bearer challenge. The Streamable HTTP session
contract still requires malformed client session identifiers to fail closed;
that validation must remain HTTP 400 after successful authentication.

The governing authorization and transport requirements are:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
and
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Run the pre-change fast regression matrix and add a native-router fail-first
   case for missing and unknown bearer credentials paired with a malformed
   compatibility session identifier.
2. Move only malformed session-header validation behind route-principal
   authentication, preserving Origin, metadata discovery, protocol-version,
   and protocol-era behavior.
3. Prove public requests and protected requests with a valid bearer retain
   sessionless HTTP 400, while missing and unknown bearers receive HTTP 401,
   the Bearer challenge, and no session header.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`;
   bundle the preceding hosted-evidence notes with this implementation before
   publication.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, active-state, and
  official-spec preflight completed. The preceding malformed resume-cursor
  checkpoint is published and hosted-green; only its expected hosted-evidence
  notes were dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passes the complete fast regression
  flow, including core, MCP, client, real-router WAMP benchmark workloads,
  generated and globally activated package clients, router CLI consumer smoke,
  and native router follow-ups.
- 2026-08-10: The native-router fail-first reproduced HTTP 400 for a protected
  request carrying a missing bearer and malformed session identifier. The MCP
  handler now resolves the route principal before validating session syntax:
  missing and unknown bearers receive HTTP 401 with the protected-resource
  challenge, while a valid router-issued bearer and the existing public path
  retain sessionless HTTP 400. The focused native regression, router analysis,
  formatting, and `git diff --check` pass.
- 2026-08-10: Post-change `bin/test-fast` passes the complete regression flow,
  including the public, authenticated, bearer-token, JSON-response, pub/sub,
  globally activated, external consumer, and Router CLI MCP smokes plus the
  native router follow-ups.
- 2026-08-10: Full `bin/verify` passes with formatting unchanged, 114 Rust
  core tests, 52 FFI tests, the complete Dart package and router suites, all 36
  live WAMP workloads and 96 benchmark tests, independent and globally
  activated package/CLI consumer smokes, isolated remote authentication, and
  Chrome/Dart2Wasm coverage. The checkpoint is ready to publish together with
  the preceding hosted-evidence notes.
