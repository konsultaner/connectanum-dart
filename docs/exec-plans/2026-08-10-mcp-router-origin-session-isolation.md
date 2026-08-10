# MCP Router Origin-Rejection Session Isolation

Status: complete

## Goal

Make router-hosted MCP origin rejection sessionless across Streamable HTTP
POST, GET, and DELETE, and expose an opt-in public package-client smoke that
proves the method matrix without assuming a particular consumer application.

## Context

The router validates `Origin` before authenticating the request or resolving a
claimed compatibility session. That ordering is intentional, but the current
403 response uses the preliminary response-session calculation and therefore
reflects a syntactically valid caller-supplied `MCP-Session-Id` on POST, GET,
and DELETE. A rejected origin has not established route-principal ownership of
that identifier and must not receive a session response header.

The public `router_hosted_client` executable already proves malformed-session
rejection without mutating its active session or resume cursor. Origin policy
is route-configurable, so the corresponding consumer proof must be opt-in and
accept an origin that the target route is expected to reject rather than
assuming every endpoint rejects an arbitrary origin.

The governing Streamable HTTP and Origin requirements are recorded in
`docs/mcp_integration_research.md` and the official transport specification:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Run the pre-change fast matrix and reproduce the response-session leak at
   the native HTTP boundary with an active compatibility session.
2. Make the early invalid-Origin response sessionless without changing
   allowed-origin CORS behavior or later session ownership semantics.
3. Add an opt-in rejected-origin method matrix to the public router-hosted
   client and wire neutral generated-consumer coverage for public and protected
   routes.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   the preceding hosted-evidence notes with this implementation checkpoint.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, active-state, and
  transport-handler preflight completed. The preceding checkpoint is
  published and hosted-green; only its expected hosted-evidence notes were
  dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passed, including analysis, package
  suites, 36 live WAMP workloads, installable/public MCP client smokes,
  isolated consumer and router CLI smokes, and native follow-ups.
- 2026-08-10: The fail-first native regression establishes a live Streamable
  session and reproduces that an origin-rejected POST returns HTTP 403 with
  the active `MCP-Session-Id`; GET and DELETE are included in the required
  matrix.
- 2026-08-10: Invalid-Origin responses are now sessionless. The focused native
  POST/GET/DELETE regression passes and proves the rejected DELETE does not
  terminate the active compatibility session.
- 2026-08-10: The public `router_hosted_client` executable accepts an opt-in
  `--rejected-origin` compatibility smoke, forwards configured authorization,
  requires HTTP 403 without a response session header for all three methods,
  and proves client session and resume-cursor state remain unchanged. Source,
  globally activated, public, authenticated, bearer-token, pub/sub-only, and
  JSON-response live smokes pass; modern stateless mode rejects this
  compatibility-only option before network access.
- 2026-08-10: Focused formatting and analysis, `bash -n bin/common.sh`,
  `git diff --check`, the native ingress/session test, the public executable
  dry-run matrix, and post-change `bin/test-fast` pass. The fast gate includes
  all isolated/global consumer and CLI smokes plus 36 live WAMP workloads.
- 2026-08-10: Full local `bin/verify` passes with zero formatting changes, 114
  Rust core tests plus serializer integrations, 52 Rust FFI tests plus the
  metrics follow-up, 360 Dart core tests, 101 MCP tests, the complete 280-case
  client MCP matrix, all 96 benchmark tests including 36 live WAMP workloads,
  all 416 router tests, remote-auth isolation, 13 native follow-ups, every
  isolated and globally activated consumer/CLI smoke, and Chrome/Dart2Wasm.
  The public-artifact reference guard and final `git diff --check` also pass.
  The implementation checkpoint is ready to publish and audit.
- 2026-08-10: Implementation commit `44d219bc` is published to both maintained
  `master` branches. Exact-head CI `31377387924`, Dart Package Publish Dry Run
  `31377387913`, WAMP Profile Benchmarks `31377387873`, and Router Image dry
  run `31378874691` all pass. Retained artifacts are Dart VM coverage
  `9058963089`, WAMP profile evidence `9058676908`, Router Image preview
  `9059042159`, and Docker build records `9059164850` and `9059164085`. The
  comprehensive strict deployment-chain audit exits zero with clean exact-head
  CI jobs and logs plus every required package, still-relevant native release,
  fresh-image MCP smoke, multi-architecture image build, WAMP,
  workflow-visibility, branch-protection, and public GHCR gate ready. Only the
  deliberately unapproved next RC tag remains outside this milestone.
