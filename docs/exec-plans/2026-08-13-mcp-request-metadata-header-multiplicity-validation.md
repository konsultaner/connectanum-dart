# MCP Request-Metadata Header Multiplicity Validation

Status: completed

## Goal

Reject repeated case-insensitive `Mcp-Method`, `Mcp-Name`, and
`Mcp-Param-*` singleton fields at router-hosted MCP ingress before catalog
refresh or WAMP dispatch, so direct JSON and Streamable HTTP header/body
integrity cannot depend on which scalar field value is selected.

## Context

Native HTTP ingress now preserves normalized duplicate-name evidence alongside
all list-field values. Router-hosted MCP uses that evidence for security-
sensitive standard headers, but request metadata still reads one scalar
`Mcp-Method`, `Mcp-Name`, or declared tool-parameter value. A client can send a
matching field first and a conflicting case-variant field second; the selected
scalar can match the JSON body while another wire value is silently ignored.
These metadata fields are singleton mirrors, unlike the legal list semantics
of `Accept`, and must fail closed without weakening authentication, protocol,
session, or unknown-session precedence.

## Plan

1. Preserve the completed Accept checkpoint's hosted-evidence notes and run
   the workflow, Serena, overlap, both-roadmap, and green pre-change fast
   verification checks.
2. Add fail-first synthetic and raw native HTTP regressions for repeated
   method, name, and tool-parameter metadata.
3. Reject normalized metadata duplicates before catalog refresh or WAMP
   dispatch while preserving authentication and compatibility-session
   isolation.
4. Extend the neutral installed-router consumer smoke with protected raw-wire
   rejection plus a subsequent successful request proving session reuse.
5. Run focused and full verification, write the durable Serena convention,
   bundle implementation and state evidence, publish both maintained remotes,
   and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, active-plan, both-roadmap,
  and worktree preflights passed. The only startup changes are the completed
  Accept checkpoint's expected hosted-evidence notes; the scheduled wrapper,
  child Codex process, and live runlock belong to this run, and no unrelated
  same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed the complete fast matrix,
  including 360 core tests, 101 MCP tests, the 280-case client/MCP matrix, 97
  benchmark tests and 37 live WAMP workloads, plus every neutral consumer and
  installed-command smoke.
- 2026-08-13: Fail-first synthetic and raw native HTTP regressions returned
  HTTP 200 for repeated case-insensitive method, name, and parameter
  metadata when the selected scalar matched the JSON body, proving that the
  other wire value was silently ignored.
- 2026-08-13: Router-hosted MCP now rejects normalized duplicate
  `Mcp-Method`, `Mcp-Name`, and `Mcp-Param-*` fields before endpoint creation,
  catalog refresh, or WAMP dispatch. Protected raw-wire coverage preserves
  missing-bearer 401 and unknown-session 404 precedence, returns 400 with the
  active session for a valid principal, and proves the session remains usable.
- 2026-08-13: Focused router analysis, synthetic and native MCP tests, shell
  syntax, all 19 package-boundary contracts, and the neutral installed-router
  consumer smoke pass. The consumer exercises all three metadata families,
  records explicit multiplicity evidence, and completes a subsequent request
  on the same active session.
- 2026-08-13: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, 360 Dart core tests, all 101 MCP tests, the 280-case
  client/MCP matrix, 97 benchmark cases plus 37 live WAMP workloads, all 437
  router tests, six isolated remote-auth integrations, 13 native follow-ups,
  every generated and globally activated consumer smoke, and Chrome/Dart2Wasm.
  Strict package validation reaches the changed router archive with only the
  expected dirty-worktree warning; clean exact-commit validation remains
  before publication.
- 2026-08-13: Commit `f6892ded` is published to GitLab and GitHub. Clean
  exact-commit strict release-ready validation passes all seven synchronized
  `3.0.0-beta` package archives with zero warnings and no private workspace
  dependency blockers.
- 2026-08-13: Exact-head CI `31653905691`, Dart Package Publish Dry Run
  `31653905690`, Router Image dry run `31653917021`, and WAMP Profile
  Benchmarks `31653905684` all pass. The first WAMP attempt completed every
  workload but marginally missed four unchanged E2EE performance thresholds;
  its one same-SHA failed-job rerun passed, confirming hosted runner variance.
  Retained artifacts are Dart VM coverage `9163999336`, successful WAMP
  profile evidence `9163953399`, Router Image preview `9163615829`, and Docker
  build records `9163731977` and `9163731347`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and log scan, clean and relevant package,
  Router Image, WAMP, and Native Artifacts evidence, protected default-branch
  requirements, visible workflows, and public router-package metadata. A new
  numeric RC tag remains release-approval work and was not created.
