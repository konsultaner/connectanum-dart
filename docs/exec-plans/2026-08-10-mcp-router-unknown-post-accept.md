# MCP Router Unknown-Session POST Accept Precedence

Status: completed

## Goal

Make a terminated or otherwise unknown compatibility-era Streamable HTTP
session authoritative before POST response-content negotiation when the
request cannot be a valid direct JSON call, so the claimed session receives
the required sessionless HTTP 404 instead of HTTP 406.

## Context

The maintained MCP `2025-11-25` Streamable HTTP contract requires POST clients
to accept both JSON and SSE responses. It also requires a server to return HTTP
404 to requests carrying a terminated session identifier. Router-hosted MCP
currently validates POST JSON response negotiation before authenticating and
resolving the claimed compatibility session, which can mask termination with
HTTP 406.

Connectanum's direct JSON extension is deliberately lifecycle-free. A valid
direct JSON request that accepts `application/json` must continue to ignore a
stale compatibility session header rather than becoming session-bound.

The governing transport requirement is:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Run the pre-change fast regression matrix and add a native-router fail-first
   case for an unknown compatibility session whose POST cannot negotiate a JSON
   response.
2. Defer the JSON-response Accept check only for a non-stateless POST carrying a
   session identifier when JSON is not acceptable, then authenticate and
   resolve that claimed session first.
3. Prove unknown sessions return a sessionless 404 while live sessions retain
   HTTP 406 and valid JSON-only direct requests retain stale-session isolation.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`;
   bundle the preceding hosted-evidence notes with the implementation before
   publication.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, and active-state
  preflight completed. The preceding GET-negotiation implementation is
  published and hosted-green; only its expected evidence notes were dirty at
  startup.
- 2026-08-10: Official transport text confirms both relevant invariants: a
  Streamable POST client accepts JSON and SSE, and a terminated session ID is
  authoritative for HTTP 404. Symbol inspection found POST JSON-response
  negotiation still precedes route-principal authentication and compatibility
  endpoint lookup, while valid JSON-only direct requests are intentionally
  lifecycle-free.
- 2026-08-10: Pre-change `bin/test-fast` passes the complete fast regression
  flow, including core, MCP, client, real-router WAMP benchmark workloads,
  globally activated package clients, router CLI consumer smoke, and native
  router follow-ups.
- 2026-08-10: A fail-first native-router regression reproduced an unknown
  compatibility session returning HTTP 406 for a POST that accepted only SSE.
  Router-hosted MCP now treats a non-stateless POST carrying a session ID but
  unable to negotiate JSON as a claimed compatibility-session request: route
  authentication and endpoint lookup run first, unknown sessions receive a
  sessionless 404 with the safe readable request ID, and live sessions retain
  HTTP 406 with their active session header. Deferred content-type validation
  also prevents HTTP 415 from masking that same unknown-session outcome.
- 2026-08-10: Focused native-router ingress/session and protected-route tests,
  router analysis, formatting, `git diff --check`, post-change
  `bin/test-fast`, and full `bin/verify` pass. Full verification covered the
  complete Rust and Dart workspace, 360 core tests, 101 MCP tests, the
  280-case client MCP matrix, all 96 benchmark tests including 36 live WAMP
  workloads, all 416 router tests, remote-auth isolation, native follow-ups,
  every generated and globally activated consumer/CLI smoke, and
  Chrome/Dart2Wasm. Valid JSON-only direct calls remain lifecycle-free with a
  stale session header, and protected routes still authenticate before
  session lookup or negotiation errors.
- 2026-08-10: Implementation commit `6a4170e7` is published to both maintained
  `master` branches. Exact-head CI `31348094641`, Dart Package Publish Dry Run
  `31348094632`, WAMP Profile Benchmarks `31348094633`, and Router Image dry
  run `31348990958` all pass. Retained artifacts are Dart VM coverage
  `9048275865`, WAMP profile evidence `9048122237`, Router Image preview
  `9048304330`, and Docker build records `9048391076` and `9048390660`. The
  comprehensive strict deployment-chain audit exits zero with clean exact-head
  CI jobs and logs plus every required package, still-relevant native release,
  fresh-image MCP smoke, multi-architecture image build, WAMP,
  workflow-visibility, branch-protection, and public GHCR gate ready. Only the
  deliberately unapproved next RC tag remains outside this milestone.
