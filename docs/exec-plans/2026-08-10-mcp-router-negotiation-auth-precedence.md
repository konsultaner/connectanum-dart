# MCP Router Negotiation Auth Precedence

Status: complete; implementation and local verification green

## Goal

Require bearer-protected router-hosted MCP requests to resolve their route
principal before returning HTTP method, Accept, or content-type negotiation
errors, while preserving public-route behavior and keeping those rejections
sessionless unless they belong to a valid compatibility session.

## Context

Router-hosted MCP now authenticates before validating malformed session IDs and
unsupported protocol versions, but several earlier ingress guards still return
405, 406, or 415 before bearer authentication. That lets missing or unknown
credentials avoid the endpoint's required Bearer challenge for actual MCP
traffic. The maintained authorization contract requires credentials on every
protected MCP request.

Invalid Origin rejection, CORS OPTIONS handling, and public Protected Resource
Metadata discovery are intentionally earlier boundaries and remain unchanged.
After successful authentication, method and representation negotiation must
retain their existing status codes and payloads. Compatibility-session probes
must not terminate or mutate the active client session or resume cursor.

## Plan

1. Preserve the preceding hosted-evidence notes, run the pre-change fast gate,
   and add a fail-first native protected-route matrix for method, Accept, and
   content-type errors with missing and unknown bearer credentials.
2. Move only actual-request method and representation negotiation behind route
   principal resolution, preserving Origin, OPTIONS, metadata discovery,
   protocol-version errors, session lookup precedence, and public behavior.
3. Extend the neutral public package executable to prove authenticated/public
   negotiation rejections keep an active compatibility session and resume
   cursor unchanged across maintained live smoke variants.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`;
   update durable project state and bundle the preceding hosted-evidence notes
   with the implementation checkpoint.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. Both maintained `master` heads equal
  `2fe1386b`; only the preceding checkpoint's expected hosted-evidence notes
  were dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passes analysis, package suites, all 36
  live WAMP workloads, source and globally activated MCP clients, isolated
  consumer and router CLI smokes, and native router follow-ups.
- 2026-08-10: The fail-first native protected-route probe reproduced a
  compatibility `PUT` returning HTTP 405 instead of the required HTTP 401
  Bearer challenge. The regression matrix also covers stateless method
  rejection, compatibility GET/POST Accept negotiation, stateless POST Accept
  negotiation, and compatibility POST content-type rejection.
- 2026-08-10: Actual-request method, Accept, and content-type negotiation now
  runs after route-principal authentication and the established protocol and
  session-header checks. Missing and unknown bearers are challenged first,
  while public and authenticated requests retain their 405, 406, and 415
  responses. The focused native matrix passes.
- 2026-08-10: The neutral public package executable now repeats the complete
  negotiation matrix against an active compatibility session, validates when
  errors may echo that valid session identifier, and proves its session and
  resume cursor remain unchanged. Maintained live-smoke assertions require the
  bounded 405/406/415 summary.
- 2026-08-10: Post-change `bin/test-fast` passes analysis, 360 core tests, 101
  MCP tests, the 280-case client MCP matrix, all 96 benchmark tests including
  36 live WAMP workloads, every isolated and globally activated consumer and
  CLI smoke, the seven maintained router-hosted MCP live variants, and native
  router follow-ups.
- 2026-08-10: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the complete
  280-case client MCP matrix, all 96 benchmark tests including 36 live WAMP
  workloads, all 416 router tests, remote-auth isolation, native follow-ups,
  every isolated/global consumer and CLI smoke, and Chrome/Dart2Wasm. The
  implementation checkpoint is ready to publish and audit.
- 2026-08-10: Implementation commit `b5e2e471` is published to both maintained
  `master` branches. Exact-head CI `31393780986`, Dart Package Publish Dry Run
  `31393780985`, WAMP Profile Benchmarks `31393780984`, and Router Image dry
  run `31393868252` all pass. Retained artifacts are Dart VM coverage
  `9065391113`, WAMP profile evidence `9064982656`, Router Image preview
  `9064790988`, and Docker build records `9064941354` and `9064940506`. The
  comprehensive strict deployment-chain audit exits zero with every required
  exact-head CI/log, package, still-relevant native release, fresh-image MCP
  smoke, multi-architecture image build, WAMP, workflow-visibility,
  branch-protection, and public GHCR gate ready. Only the deliberately
  unapproved next RC tag remains outside this milestone.
