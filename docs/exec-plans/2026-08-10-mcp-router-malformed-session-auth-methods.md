# MCP Router Malformed-Session Auth Method Matrix

Status: complete

## Goal

Prove that router-hosted MCP applies protected-route authentication before
malformed compatibility session validation across POST, GET, and DELETE, and
carry the same method-complete malformed-session rejection evidence through
the public router-hosted client executable used by consumer-package smokes.

## Context

The handler-level fix now authenticates protected routes before rejecting a
malformed `MCP-Session-Id`, and the shared validation path covers every
Streamable HTTP method. The native protected-route regression and the public
package executable currently exercise only POST, however, leaving GET polling
and DELETE termination outside the maintained downstream evidence.

The MCP Streamable HTTP session contract makes `MCP-Session-Id` part of every
subsequent session request, allows GET polling and DELETE termination, and
restricts server-issued session identifiers to visible ASCII. The method
matrix must therefore remain consistent: missing and unknown credentials on a
protected route receive HTTP 401 plus the Bearer challenge, while authenticated
and public malformed identifiers receive sessionless HTTP 400.

The governing transport requirements are:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Run the pre-change fast regression matrix and inspect the existing native
   and public-package malformed-session helpers with Serena.
2. Extend the protected native-router regression across POST, GET, and DELETE
   for missing, unknown, and router-issued bearer credentials.
3. Extend the public router-hosted client executable's live malformed-session
   proof across POST, GET, and DELETE while preserving active client state.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   the preceding hosted-evidence notes with this implementation checkpoint.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, active-state, and
  official transport-spec preflight completed. The preceding auth-precedence
  checkpoint is published and hosted-green; only its expected hosted-evidence
  notes were dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passed, including 360 core tests, 101
  MCP tests, the 36-workload live WAMP matrix, installable/public MCP client
  smokes, the external consumer smoke, and native follow-up suites.
- 2026-08-10: Protected native-router coverage and the public installable
  client smoke now exercise malformed session identifiers over POST, GET, and
  DELETE with method-appropriate Accept headers and no response session leak.
- 2026-08-10: The focused native-router regression and package analysis pass.
  Post-change `bin/test-fast` also passes the full maintained matrix, including
  public, globally activated, authenticated, bearer-token, and JSON-response
  router-hosted client smokes plus the external consumer and router CLI paths.
- 2026-08-10: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the
  complete 280-case client MCP matrix, all 96 benchmark tests and 36 live WAMP
  workloads, all 416 router tests, isolated consumer/CLI and remote-auth
  checks, 13 native follow-ups, and Chrome/Dart2Wasm coverage. The
  implementation is ready to publish and collect exact-head hosted evidence.
- 2026-08-10: Implementation commit `c619f963` is published to both maintained
  `master` branches. Exact-head CI `31369862820`, Dart Package Publish Dry Run
  `31369862832`, WAMP Profile Benchmarks `31369862817`, and Router Image dry
  run `31369906080` all pass. Retained artifacts are Dart VM coverage
  `9056042920`, WAMP profile evidence `9055805230`, Router Image preview
  `9055629775`, and Docker build records `9055721870` and `9055721217`. The
  comprehensive strict deployment-chain audit exits zero with clean exact-head
  CI jobs and logs plus every required package, still-relevant native release,
  fresh-image MCP smoke, multi-architecture image build, WAMP,
  workflow-visibility, branch-protection, and public GHCR gate ready. Only the
  deliberately unapproved next RC tag remains outside this milestone.
