# MCP Router Route-Rejection Auth and Session Isolation

Status: complete; implementation, local verification, and hosted evidence green

## Goal

Make configured router-level MCP method and protocol rejections pass through
the MCP ingress authentication boundary, and keep their HTTP 405/426 responses
sessionless instead of reflecting an unowned caller-supplied session header.

## Context

The MCP handler now authenticates protected actual requests before its own
method and representation negotiation. Configured `HttpRouteMatch.methods`
and `HttpRouteMatch.protocols` mismatches still return from the generic HTTP
dispatcher before the MCP handler runs. Missing or unknown bearer credentials
therefore receive the route rejection instead of the endpoint's Bearer
challenge, and compatibility POST rejections can echo a merely well-formed
`MCP-Session-Id`.

Invalid Origin handling, CORS preflight, and public Protected Resource Metadata
discovery must remain earlier MCP boundaries. Non-MCP route rejection behavior
must remain unchanged.

## Plan

1. Preserve the preceding hosted-evidence notes, run the pre-change fast gate,
   and add fail-first native public/protected route-level method and protocol
   regression coverage.
2. Route MCP method/protocol mismatch context through the MCP handler so route
   principal authentication and established header validation run before the
   configured 405/426 response.
3. Keep configured route rejections sessionless and preserve their JSON-RPC,
   CORS, `Allow`/`Upgrade`, and protocol-version response contract.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`;
   update durable project state and bundle the preceding hosted-evidence notes
   with this implementation checkpoint.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. Both maintained `master` heads equal
  `b5e2e471`; only the preceding checkpoint's expected hosted-evidence notes
  were dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passes analysis, package suites, all
  36 live WAMP workloads, source and globally activated MCP clients, isolated
  consumer and router CLI smokes, and native router follow-ups.
- 2026-08-10: The fail-first native regressions reproduced public configured
  method and protocol rejections reflecting an unowned caller session header,
  plus a protected configured-method request returning HTTP 405 instead of the
  required HTTP 401 Bearer challenge.
- 2026-08-10: MCP route-match method/protocol mismatch context now enters the
  MCP handler. Invalid Origin and public Protected Resource Metadata remain
  earlier boundaries; actual requests authenticate and validate maintained
  MCP headers before returning a sessionless JSON-RPC 405 or 426. Non-MCP
  route rejection behavior remains unchanged.
- 2026-08-10: Focused router formatting, analysis, diff hygiene, and the native
  public/protected method/protocol regression matrix pass.
- 2026-08-10: Post-change `bin/test-fast` passes analysis, 360 core tests, 101
  MCP tests, the 280-case client MCP matrix, all 96 benchmark tests including
  36 live WAMP workloads, every isolated and globally activated consumer and
  CLI smoke, maintained router-hosted MCP live variants, and native router
  follow-ups.
- 2026-08-10: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the
  complete 280-case client MCP matrix, all 96 benchmark tests including 36
  live WAMP workloads, all 417 router tests, six remote-auth integrations, 13
  native follow-ups, every isolated/global consumer and CLI smoke, and
  Chrome/Dart2Wasm. The implementation checkpoint is ready to publish and
  audit.
- 2026-08-10: Implementation commit `9743126d` is published to both maintained
  `master` branches. Exact-head CI `31403959090`, Dart Package Publish Dry Run
  `31403959057`, WAMP Profile Benchmarks `31403959178`, and Router Image dry
  run `31403986169` all pass. Retained artifacts are Dart VM coverage
  `9069461068`, WAMP profile evidence `9069104331`, Router Image preview
  `9068828414`, and Docker build records `9069006882` and `9069005806`. The
  comprehensive strict deployment-chain audit exits zero with every required
  exact-head CI/log, package, still-relevant native release, fresh-image MCP
  smoke, multi-architecture image build, WAMP, workflow-visibility,
  branch-protection, and public GHCR gate ready. Only the deliberately
  unapproved next RC tag remains outside this milestone.
