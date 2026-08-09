# MCP Router Initialize Notification Sessions

Status: completed

## Goal

Prevent compatibility-era Streamable HTTP `initialize` notifications from
minting or retaining router-hosted MCP sessions, while preserving valid
request-based initialization and ordinary notification semantics.

## Context

JSON-RPC notifications have no request ID and therefore receive no response.
MCP initialization requires a successful `InitializeResult` so the client can
learn the negotiated protocol version and server capabilities before sending
`notifications/initialized`. The router currently classifies any POST whose
method is `initialize` as a tentative session initializer. When the message is
a notification, the MCP core correctly suppresses a JSON-RPC response, but the
HTTP layer returns `202 Accepted` with a newly generated `MCP-Session-Id` and
retains the tentative endpoint. Repeated notification-shaped initialization
can therefore consume route session capacity without completing the lifecycle.

The governing compatibility transport and lifecycle requirements are:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports> and
<https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle>.

## Plan

1. Run the pre-change fast regression matrix and add a deterministic
   native-router regression proving an ID-free `initialize` does not return a
   session header or consume the route session slot.
2. Reproduce the retained tentative endpoint, then make successful
   initialization eligibility require a request ID while preserving JSON-RPC
   notification response suppression.
3. Prove a valid request-based initialize still creates a usable session and
   that the route capacity is immediately reusable after the rejected
   notification.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   the prior hosted-evidence bookkeeping with the implementation, push both
   maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Repository-workflow and Serena preflight completed. The prior
  implementation and hosted verification are green, only its expected
  evidence notes were dirty at startup, and no unrelated same-repository Codex
  process or stale lock exists.
- 2026-08-09: The pre-change `bin/test-fast` passed. A fail-first native-router
  regression then reproduced the defect with `max_session_count: 1`: an
  ID-free compatibility `initialize` received HTTP 202 with an
  `MCP-Session-Id`, retaining the tentative endpoint and consuming the only
  session slot.
- 2026-08-09: Tentative compatibility endpoints are now retained and exposed
  only when dispatch returns an initialization result. Notification-shaped
  initialization still receives an empty HTTP 202, but the response is
  sessionless and the tentative endpoint is disposed; initialize errors remain
  sessionless as before. The regression also proves a valid request-based
  initialize can immediately use the same one-session route and delete its
  established session.
- 2026-08-09: The packaged Router Image smoke now checks the sessionless
  notification boundary on both public and protected compatibility endpoints
  before establishing valid sessions. Focused native-router tests, router
  analysis, all 28 image-smoke contract tests, Python bytecode compilation,
  and the complete post-change `bin/test-fast` pass.
- 2026-08-09: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests plus serializer integrations, 52 Rust FFI tests, 360 Dart core
  tests, 101 MCP tests, the complete 280-case client MCP matrix, all 96
  benchmark tests and 36 live WAMP workloads, all 416 router tests, isolated
  and globally activated consumer/CLI smokes, remote-auth isolation, 13 native
  follow-ups, and Chrome/Dart2Wasm coverage.
- 2026-08-09: Implementation commit `03df7895` is published to both maintained
  `master` branches. Exact-head CI `31335702160`, Dart Package Publish Dry Run
  `31335702103`, WAMP Profile Benchmarks `31335702131`, and Router Image dry
  run `31335722319` all pass. Retained artifacts are Dart VM coverage
  `9044431833`, WAMP profile evidence `9044323873`, Router Image preview
  `9044260057`, and Docker build records `9044319407` and `9044319026`. The
  comprehensive strict deployment-chain audit exits zero with clean CI jobs
  and logs plus every required package, still-relevant native release,
  fresh-image MCP smoke, multi-architecture image build, WAMP,
  workflow-visibility, branch-protection, and public GHCR gate ready. Only the
  deliberately unapproved next RC tag remains outside this milestone.
