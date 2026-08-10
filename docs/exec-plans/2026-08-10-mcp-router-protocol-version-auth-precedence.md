# MCP Router Protocol-Version Auth Precedence

Status: active

## Goal

Require bearer-protected router-hosted MCP requests to resolve their route
principal before rejecting an unsupported `MCP-Protocol-Version`, while keeping
the unsupported-version response sessionless after successful authentication
and preserving public-route behavior.

## Context

Router-hosted MCP currently rejects an unsupported protocol-version header
before it resolves the protected route principal. Missing and unknown bearer
credentials can therefore receive HTTP 400 without the endpoint's required
Bearer challenge. The maintained authorization contract requires credentials
on every protected MCP request, while Origin checks, CORS preflight, and public
Protected Resource Metadata discovery remain intentionally earlier boundaries.

The recent malformed-session checkpoint established the same authentication
precedence for invalid compatibility session identifiers. This checkpoint
applies that boundary narrowly to protocol-version negotiation and proves it
across Streamable HTTP POST, GET, and DELETE without changing the active
client's session or resume cursor.

The governing requirements are recorded in
`docs/mcp_integration_research.md`, including that protected MCP traffic
requires bearer credentials on every request and that unsupported protocol
versions use the reserved MCP error.

## Plan

1. Preserve the preceding hosted-evidence notes, run the pre-change fast gate,
   and add a fail-first native protected-route method matrix for unsupported
   protocol versions with missing and unknown bearer credentials.
2. Move only unsupported protocol-version rejection behind route-principal
   authentication, preserving Origin, OPTIONS, metadata discovery, protocol
   error payloads, and sessionless rejection.
3. Add neutral public package-client coverage that proves public and protected
   POST/GET/DELETE rejection, forwards configured authorization, and preserves
   the active compatibility session and resume cursor.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`; bundle
   the preceding hosted-evidence notes with this implementation checkpoint.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. Both maintained `master` heads equal
  `44d219bc`; only the preceding checkpoint's expected hosted-evidence notes
  were dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passes analysis, package suites, all 36
  live WAMP workloads, source and globally activated MCP clients, isolated
  consumer and router CLI smokes, and native router follow-ups.
- 2026-08-10: The native-router fail-first reproduced HTTP 400 for a protected
  POST carrying a missing bearer, a claimed compatibility session, and an
  unsupported protocol version; the required result is HTTP 401 with the
  protected-resource Bearer challenge. GET and DELETE are included in the
  regression matrix.
- 2026-08-10: Unsupported protocol-version negotiation now runs after route
  principal resolution. The protected native method matrix proves missing and
  unknown bearer credentials receive HTTP 401 plus the endpoint challenge,
  while authenticated requests retain the reserved HTTP 400 error and never
  receive a session header.
- 2026-08-10: The public package executable now sends unsupported-version
  POST, GET, and DELETE requests against its active compatibility session,
  forwards configured authorization, validates the reserved error payload,
  and proves that neither the session id nor resume cursor changes. All source,
  globally activated, public, ticket-authenticated, bearer-token, and protected
  JSON-response live variants assert this result.
- 2026-08-10: Focused native and package-boundary tests, package analysis, diff
  hygiene, the seven-variant live executable matrix, and post-change
  `bin/test-fast` pass.
- 2026-08-10: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the
  complete 280-case client MCP matrix, all 96 benchmark tests including 36
  live WAMP workloads, all 416 router tests, remote-auth isolation, 13 native
  follow-ups, every isolated/global consumer and CLI smoke, and
  Chrome/Dart2Wasm. The implementation checkpoint is ready to publish and
  audit.
