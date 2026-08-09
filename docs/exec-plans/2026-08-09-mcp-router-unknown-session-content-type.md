# MCP Router Unknown-Session Content Type Precedence

Status: completed

## Goal

Make a terminated or otherwise unknown compatibility-era Streamable HTTP
session authoritative before MCP request content-type validation, so every
subsequent operation carrying that session ID receives the required
sessionless HTTP 404.

## Context

The maintained MCP `2025-11-25` Streamable HTTP contract requires a server to
respond with HTTP 404 to requests carrying a terminated session ID. Router
POST handling already resolves unknown sessions before inspecting request
size, JSON, or method headers, but currently rejects a non-JSON content type
with HTTP 415 before authenticating the route principal and resolving the
session. This leaves one request-body validation path able to mask session
termination.

The governing transport requirement is:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Complete the pre-change fast regression matrix and add a native-router
   fail-first case for an unknown Streamable session carrying a non-JSON body.
2. Move POST JSON content-type validation after route-principal resolution and
   unknown-session detection without weakening Origin, Accept, protocol-version,
   direct JSON, or valid-session behavior.
3. Prove an unknown session returns a sessionless 404 while a live session
   retains the normal 415 response, then run focused router checks.
4. Run post-change `bin/test-fast` and full `bin/verify`; bundle the prior
   hosted-evidence notes with this implementation before publication.

## Progress

- 2026-08-09: Repository workflow, Serena, overlap, roadmap, and active-state
  preflight completed. The prior implementation is published and hosted-green;
  only its expected evidence notes were dirty at startup.
- 2026-08-09: Official MCP transport text confirms that a terminated session
  ID is authoritative for HTTP 404 responses. Code inspection found JSON
  content-type validation still runs before authenticated Streamable session
  lookup, unlike request-size, JSON, and method-header validation.
- 2026-08-09: Pre-change `bin/test-fast` passed end to end. The native-router
  fail-first then reproduced HTTP 415 for an unknown Streamable session with a
  valid JSON-RPC operation carried as `text/plain`, instead of the required
  sessionless 404.
- 2026-08-09: JSON content-type validation is now deferred only when a POST
  already claims Streamable HTTP session semantics. The router authenticates
  the route principal and resolves that session first; direct JSON and
  sessionless invalid-content requests retain their earlier ingress ordering.
  Focused formatting, analysis, and the native ingress/session regression pass,
  including the neighboring live-session 415 contract and recovered request
  ID on the unknown-session error.
- 2026-08-10: Post-change `bin/test-fast` and full `bin/verify` pass. Full
  verification reports zero formatting changes and covers 114 Rust core tests
  plus serializer integrations, 52 Rust FFI tests plus the metrics follow-up,
  360 Dart core tests, 101 MCP tests, the complete 280-case client MCP matrix,
  all 96 benchmark tests and 36 live WAMP workloads, the complete router and
  native follow-up suites, every isolated and globally activated consumer/CLI
  smoke, remote-auth isolation, and Chrome/Dart2Wasm coverage.
