# MCP Router Unknown-Session GET Accept Precedence

Status: completed

## Goal

Make a terminated or otherwise unknown compatibility-era Streamable HTTP
session authoritative before GET response-content negotiation, so a request
carrying that session ID receives the required sessionless HTTP 404 even when
its `Accept` header cannot receive SSE.

## Context

The maintained MCP `2025-11-25` Streamable HTTP contract requires a server to
respond with HTTP 404 to requests carrying a terminated session ID. Before this
checkpoint, router GET handling validated SSE `Accept` negotiation before
authenticating the route principal and resolving the claimed session, which
could mask termination with HTTP 406.

The governing transport requirement is:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Complete the pre-change fast regression matrix and add a native-router
   fail-first case for an unknown Streamable session carrying an invalid SSE
   `Accept` header.
2. Defer GET SSE response negotiation only when a request claims compatibility
   session semantics, then authenticate and resolve that session first.
3. Prove unknown sessions return a sessionless 404 while live sessions retain
   HTTP 406 and sessionless/direct JSON behavior remains unchanged.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`; bundle
   the preceding hosted-evidence notes with the implementation before
   publication.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, and active-state
  preflight completed. The preceding implementation is published and
  hosted-green; only its expected evidence notes were dirty at startup.
- 2026-08-10: Official MCP transport text confirms that a terminated session ID
  is authoritative for HTTP 404 responses. Symbol inspection found GET SSE
  `Accept` validation still runs before authenticated compatibility-session
  lookup. The required pre-change `bin/test-fast` reached the final generated
  MCP consumer smoke before one transient closed connection on `/auth`; the
  exact isolated smoke passed immediately on reproduction.
- 2026-08-10: The native-router fail-first reproduced HTTP 406 for an unknown
  claimed session with a JSON-only `Accept` header. GET negotiation is now
  deferred only when a session ID is present, after route-principal
  authentication and endpoint lookup. Focused formatting, analysis, and the
  ingress/session regression pass; they pin sessionless 404 for an unknown
  session, live-session 406 with the active session header, and unchanged
  sessionless 406 ordering.
- 2026-08-10: Post-change `bin/test-fast` passes end to end, including 360 core
  tests, 101 MCP tests, the complete 280-case client MCP matrix, all 96
  benchmark-package tests and 36 live WAMP workloads, generated and globally
  activated consumer/CLI smokes, and native router auth/session follow-ups. The
  earlier isolated `/auth` connection close did not recur.
- 2026-08-10: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests plus serializer integrations, 52 Rust FFI tests plus the metrics
  follow-up, 360 Dart core tests, 101 MCP tests, the complete 280-case client
  MCP matrix, all 96 benchmark tests and 36 live WAMP workloads, all 416 router
  tests, remote-auth isolation, 13 native follow-ups, every generated and
  globally activated consumer/CLI smoke, and Chrome/Dart2Wasm coverage.
- 2026-08-10: Implementation commit `d1014bd6` is published to both maintained
  `master` branches. Exact-head CI `31343916726`, Dart Package Publish Dry Run
  `31343916710`, WAMP Profile Benchmarks `31343916713`, and Router Image dry
  run `31343923002` all pass. Retained artifacts are Dart VM coverage
  `9046935282`, WAMP profile evidence `9046775435`, Router Image preview
  `9046667831`, and Docker build records `9046734004` and `9046733591`. The
  comprehensive strict deployment-chain audit exits zero with clean exact-head
  CI jobs and logs plus every required package, still-relevant native release,
  fresh-image MCP smoke, multi-architecture image build, WAMP,
  workflow-visibility, branch-protection, and public GHCR gate ready. Only the
  deliberately unapproved next RC tag remains outside this milestone.
