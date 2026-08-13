# MCP POST Content-Type Presence Validation

Status: completed

## Goal

Make router-hosted MCP reject HTTP POST requests that omit `Content-Type`
instead of treating an untyped body as JSON, while preserving the existing
authentication, compatibility-session, Accept-negotiation, and request-metadata
validation order.

## Context

The public Streamable HTTP client sends `Content-Type: application/json`, and
router-hosted MCP already returns HTTP 415 for an explicit non-JSON media type.
Its scalar media-type helper previously treated a missing field as valid,
however, so a raw consumer could submit an untyped body to the direct JSON or
Streamable path. The official MCP transport examples carry JSON request bodies
as `application/json`, and the official TypeScript server validates POST media
types before dispatch. This checkpoint closes that interoperability boundary
without changing the maintained `2025-11-25` compatibility-session lifecycle
or the sessionless `2026-07-28` behavior.

References:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>
- <https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http>
- <https://ts.sdk.modelcontextprotocol.io/v2/migration/upgrade-to-v2>

## Plan

1. Preserve the completed allowed-origin checkpoint's hosted-evidence notes,
   run the workflow, Serena, overlap, both-roadmap, green CI, and pre-change
   fast-verification checks, and capture the missing-header behavior with a
   fail-first native-router regression.
2. Require one JSON-compatible `Content-Type` field on MCP POST after the
   existing authentication, protocol/session, method, and Accept boundaries,
   retaining unknown claimed compatibility-session precedence.
3. Extend the neutral generated consumer package smoke with raw HTTP evidence
   for bearer-free and authenticated missing-header requests plus continued
   use of the valid session.
4. Run focused and full verification, strict package validation, privacy and
   diff review, record the durable Serena convention, publish both maintained
   remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, active-plan, both-roadmap,
  and exact-head deployment preflights passed. The only startup changes are the
  completed allowed-origin checkpoint's expected hosted-evidence notes; the
  scheduled wrapper, child Codex process, and live runlock belong to this run,
  and no unrelated same-repository editor exists.
- 2026-08-13: Official transport and SDK guidance confirms JSON POSTs carry an
  `application/json` media type and the official TypeScript server rejects
  non-JSON POST media types before dispatch. Pre-change `bin/test-fast` passed
  the complete fast matrix.
- 2026-08-13: The fail-first native-router regression expected HTTP 415 but an
  untyped public POST reached later request validation and returned HTTP 400,
  proving the absent field bypassed the media-type boundary. The scalar
  predicate now rejects absence while retaining explicit `application/json`
  and structured `+json` media types. Focused native HTTP coverage passes for
  public and protected `2025-11-25` compatibility traffic and `2026-07-28`
  stateless traffic; bearer-free and unknown-bearer requests remain HTTP 401.
- 2026-08-13: Router package analysis, shell syntax, all 20 generated-consumer
  boundary contracts, and the freshly sourced neutral installed-router
  consumer smoke pass. The raw smoke proves bearer-free HTTP 401, authenticated
  HTTP 415 with active-session reflection, unchanged client session/resume
  state, and continued session use after the rejection.
- 2026-08-13: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, 360 Dart core tests, all 101 MCP tests, the complete
  280-case client/MCP matrix, all 97 benchmark tests and 37 live WAMP
  workloads, all 439 router tests, six isolated remote-auth integrations, 13
  native follow-ups, every neutral consumer and installed-command smoke, and
  Chrome/Dart2Wasm coverage. Strict release-ready validation reaches all seven
  synchronized `3.0.0-beta` archives: six report zero warnings, and the changed
  router archive reports only the expected pre-commit dirty-worktree warning
  for its changelog, implementation, and test files. Clean exact-commit package
  validation, publication, and hosted deployment-chain evidence remain.
- 2026-08-13: Commit `5c3770fc` is published to GitLab and GitHub. Clean
  exact-commit strict validation passes all seven synchronized `3.0.0-beta`
  package archives with zero warnings and no private workspace dependency
  blockers.
- 2026-08-13: Exact-head CI `31690871951`, Dart Package Publish Dry Run
  `31690871889`, WAMP Profile Benchmarks `31690871910`, and Router Image dry
  run `31692403752` all pass on their first attempts. Retained artifacts are
  Dart VM coverage `9177863065`, WAMP profile evidence `9177544050`, Router
  Image preview `9177926983`, and Docker build records `9178049495` and
  `9178049055`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head jobs/logs and every required package, Router Image, WAMP,
  relevant Native Artifacts, protected-branch, workflow-visibility, and
  public-router-package gate ready. Native Artifacts run `31221315902` remains
  relevant because no native-release-sensitive input changed. A numeric RC tag
  remains release-approval work and was not created.
