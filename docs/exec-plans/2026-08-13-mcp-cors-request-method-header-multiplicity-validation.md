# MCP CORS Request-Method Header Multiplicity Validation

Status: completed

## Goal

Reject repeated case-insensitive `Access-Control-Request-Method` fields before
router-hosted MCP preflight route-action selection, unauthenticated-preflight
authorization, rate limiting, or session state.

## Context

`Access-Control-Request-Method` is a singleton CORS preflight selector. Native
HTTP ingress preserves duplicate-name evidence, but `RouterBinding` currently
reads one scalar value when selecting a method-specific MCP action and when
deciding whether bearerless preflight access applies. Conflicting field lines
can therefore be interpreted as one valid method instead of an ambiguous
request. The correction must cover base MCP actions and method-action-hosted
MCP routes without weakening valid preflight behavior, origin policy, or MCP
session isolation.

## Plan

1. Preserve the completed CORS request-header checkpoint's hosted-evidence
   notes and run workflow, Serena, overlap, both-roadmap, worktree, and green
   pre-change fast-verification checks.
2. Add fail-first synthetic and raw native HTTP regressions for conflicting
   case-insensitive `Access-Control-Request-Method` fields, including an MCP
   method action with no explicit `OPTIONS` action.
3. Reject the ambiguous selector before effective action selection or any
   auth/rate/session mutation, with an MCP-shaped bounded error response.
4. Extend the neutral installed-router consumer smoke with a real repeated-
   field preflight followed by a valid reusable-endpoint preflight.
5. Run focused and full verification, record the durable Serena convention,
   bundle implementation and hosted bookkeeping, publish both maintained
   remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, active-plan, both-roadmap,
  and worktree preflights passed. The only startup changes are the completed
  CORS request-header checkpoint's expected hosted-evidence notes; the
  scheduled wrapper, child Codex process, and live runlock belong to this run,
  and no unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed the complete fast matrix.
  Fail-first synthetic and raw native HTTP regressions each received `204 No
  Content` for conflicting `POST` and `DELETE` request-method fields.
- 2026-08-13: Router binding now rejects repeated request-method fields on an
  MCP-providing route before reading a scalar selector or choosing the
  effective action. The focused synthetic and native regressions pass, each
  followed by a valid reusable-endpoint preflight.
- 2026-08-13: The neutral installed-router consumer smoke passes a real
  repeated-field rejection followed by the existing valid split request-header
  preflight. Shell syntax and all 19 consumer-boundary contracts pass.
- 2026-08-13: Full `bin/verify` passes 114 Rust core tests, 52 FFI tests, 360
  Dart core tests, all 101 MCP tests, the 280-case client/MCP matrix, 97
  benchmark cases plus 37 live WAMP workloads, all 438 router tests, six
  isolated remote-auth integrations, 13 native follow-ups, every consumer and
  installed-command smoke, and Chrome/Dart2Wasm. Strict package validation,
  publication, and exact-head hosted evidence remain.
- 2026-08-13: Strict release-ready package validation reaches the changed
  router archive with zero content warnings and only the expected dirty-
  worktree warning before the implementation commit. Clean exact-commit
  validation then passes all seven synchronized `3.0.0-beta` package archives
  with zero warnings and no private workspace dependency blockers.
- 2026-08-13: Commit `766078bb` is published to GitLab and GitHub. Exact-head
  CI `31662333628`, Dart Package Publish Dry Run `31662333632`, WAMP Profile
  Benchmarks `31662333623`, and Router Image dry run `31662349666` all pass on
  their first attempts. Retained artifacts are Dart VM coverage `9166997543`,
  WAMP profile evidence `9166766587`, Router Image preview `9166633482`, and
  Docker build records `9166746764` and `9166746163`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs and all required package, Router Image,
  WAMP, relevant Native Artifacts, branch, workflow, and package-visibility
  gates ready. Native Artifacts run `31221315902` remains relevant because no
  native-release-sensitive input changed. A numeric RC tag remains approval-
  gated and was not created.
