# MCP Host Header Multiplicity Validation

Status: completed

## Goal

Reject repeated case-insensitive `Host` fields on router-hosted MCP routes
before origin/authority policy, rate limiting, bearer authentication, or MCP
session state.

## Context

Native HTTP ingress preserves duplicate-name evidence and all field values,
but router-hosted MCP still reads one scalar `Host` value when enforcing the
default same-origin policy. Conflicting field lines can therefore leave origin
and endpoint authority dependent on map iteration order. `Host` is a singleton
request field, so an MCP-providing route must reject the ambiguity without
reflecting CORS, authentication, rate-limit, or session state.

## Plan

1. Preserve the completed CORS request-method checkpoint's hosted-evidence
   notes and run workflow, Serena, overlap, both-roadmap, worktree, and green
   pre-change fast-verification checks.
2. Add a fail-first synthetic router regression for conflicting
   case-insensitive `Host` fields before rate limiting and bearer
   authentication.
3. Reject repeated `Host` fields on an MCP-providing route before scalar
   authority reads, origin checks, route mutation, or session handling, with a
   bounded MCP-shaped error response.
4. Add raw native HTTP and neutral installed-router consumer smoke coverage,
   followed by valid endpoint reuse.
5. Run focused and full verification, record the durable Serena convention,
   bundle implementation and hosted bookkeeping, publish both maintained
   remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, completed-plan,
  both-roadmap, and worktree preflights passed. The only startup changes are
  the completed CORS request-method checkpoint's expected hosted-evidence
  notes; the scheduled wrapper, child Codex process, and live runlock belong to
  this run, and no unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed against exact local, GitLab,
  and GitHub head `766078bb`, including all 97 benchmark cases and 37 live
  WAMP workloads plus the complete consumer/package and focused router/native
  smoke matrix.
- 2026-08-13: The fail-first synthetic MCP regression received HTTP 401 for
  conflicting case-insensitive `Host` fields, proving that scalar selection
  let the request reach bearer authentication.
- 2026-08-13: Router binding now rejects repeated `Host` fields immediately
  after selecting an MCP-providing effective route and before origin policy,
  route mismatch handling, rate limiting, bearer authentication, or MCP
  session state. The synthetic regression and raw native HTTP integration pass
  with a sessionless HTTP 400 and no CORS, rate-limit, or authentication state.
- 2026-08-13: The neutral installed-router consumer smoke passes the same raw
  repeated-field rejection, reports `hostHeaderMultiplicityValidation: true`,
  and completes its subsequent direct JSON, pub/sub, Streamable HTTP, auth,
  and endpoint-reuse matrix. Shell syntax and all 19 consumer-boundary
  contracts pass.
- 2026-08-13: The first full verification attempt reached the generated router
  consumer before exposing a Dart string-concatenation error in its new
  failure diagnostic. The generator contract now preserves the response
  interpolation, and the isolated installed-router consumer passes analysis
  and its complete live matrix again before the clean full rerun.
- 2026-08-13: Clean full `bin/verify` passes 114 Rust core tests, 52 FFI
  tests, 360 Dart core tests, all 101 MCP tests, the 280-case client/MCP
  matrix, 97 benchmark cases plus 37 live WAMP workloads, all 438 router tests,
  six isolated remote-auth integrations, 13 native follow-ups, every consumer
  and installed-command smoke, and Chrome/Dart2Wasm. Strict package
  validation, publication, and exact-head hosted evidence remain.
- 2026-08-13: Strict release-ready package validation reaches all seven
  synchronized `3.0.0-beta` archives. Six have zero warnings; the changed
  router archive has only the expected pre-commit dirty-worktree warning and
  no content or dependency blocker. Clean exact-commit validation,
  publication, and hosted evidence remain.
- 2026-08-13: Commit `aa3a3c42` is published to GitLab and GitHub. Clean
  exact-commit strict validation passes all seven synchronized `3.0.0-beta`
  package archives with zero warnings and no private workspace dependency
  blockers.
- 2026-08-13: Exact-head CI `31667837052`, Dart Package Publish Dry Run
  `31667837203`, WAMP Profile Benchmarks `31667836418` attempt 2, and Router
  Image dry run `31668762449` all pass. The first WAMP attempt completed every
  workload but marginally missed two unchanged Dart AES pub/sub throughput
  floors; its same-SHA failed-job rerun passed without relaxing the gate.
  Retained artifacts are Dart VM coverage `9168963754`, successful WAMP
  profile evidence `9168906521`, Router Image preview `9168937692`, and Docker
  build records `9169038724` and `9169038124`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs and all required package, Router Image,
  WAMP, relevant Native Artifacts, protected-branch, workflow-visibility, and
  public-router-package gates ready. Native Artifacts run `31221315902`
  remains relevant because no native-release-sensitive input changed. A new
  numeric RC tag remains release-approval work and was not created.
