# MCP Router Resource Read Single Authorization

Status: complete; implementation, local verification, and exact-head hosted
deployment evidence are green

## Goal

Make each router-hosted configured dynamic-resource read perform one execution
authorization decision after the independent per-request catalog visibility
check, for both direct JSON and compatibility Streamable HTTP requests.

## Context

Configured dynamic-resource reads authorize their WAMP read procedure in
`_readConfiguredResource`, then delegate to the ordinary MCP WAMP call callback,
which authorizes the same execution a second time. Together with the expected
catalog visibility check, one read therefore makes three matching provider
decisions instead of two. Dynamic providers can reject or fail a valid read
only because it crossed this redundant internal boundary.

## Plan

1. Add native-router fail-first coverage that fails the third matching call
   decision and proves the existing direct JSON and Streamable read failure.
2. Split already-authorized internal WAMP call execution from the explicit MCP
   WAMP call operation without weakening catalog or action authorization.
3. Prove successful resource content, exact decision counts, WAMP invocation,
   direct JSON sessionlessness, Streamable session continuity, and normal
   resume-cursor advancement.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; publish both maintained remotes and audit hosted evidence if
   green.

## Progress

- 2026-08-09: Exact-head CI and the comprehensive deployment audit are green at
  `92628524`; pre-change `bin/test-fast` passes.
- 2026-08-09: A native-router regression that arms a dynamic authorization
  provider to fail the third matching call decision reproduces the redundant
  configured-resource execution check before the implementation change. The
  direct JSON request fails with the bounded authorization error before any
  WAMP invocation.
- 2026-08-09: `_readConfiguredResource` now owns the one execution decision and
  delegates through an already-authorized call path. Explicit MCP WAMP/tool
  calls retain their authorization, both paths preserve router-provided meta
  procedures, and ordinary calls share one session dispatch implementation.
- 2026-08-09: Router analysis and the new plus four adjacent native
  authorization/call/resource regressions pass. The test proves two matching
  decisions per request—catalog visibility plus execution—successful content,
  WAMP invocation, direct JSON sessionlessness, Streamable session continuity,
  and normal resume-cursor advancement. Post-change `bin/test-fast` passes all
  360 core, 98 MCP, and 280 MCP/client cases, all 96 benchmark tests including
  36 live WAMP workloads, and the complete generated/global consumer plus
  Router CLI smoke matrix.
- 2026-08-09: Full `bin/verify` passes formatting; all 114 Rust core and 52
  Rust FFI tests plus focused metrics; 360 Dart core, 98 MCP, 280 MCP/client,
  96 benchmark, and 405 Router tests; the 6-case remote-auth and 13-case native
  follow-ups; every generated and globally activated consumer smoke; and
  Chrome/Dart2Wasm.
- 2026-08-09: Commit `458d3059` is pushed to both maintained `master`
  branches. Exact-head GitHub CI `31283241489`, Dart Package Publish Dry Run
  `31283241433`, WAMP Profile Benchmarks `31283241435`, and Router Image dry
  run `31283246021` all pass on their first attempts. Retained artifacts are
  Dart VM coverage `9029207828`, WAMP profile evidence `9029122311`, router
  image preview `9029043794`, and Docker build records `9029095827` and
  `9029095547`.
- 2026-08-09: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs plus every required package, relevant
  native release, router-image MCP smoke, WAMP, workflow-visibility,
  branch-protection, and public GHCR gate ready. Only the deliberately
  unapproved next RC tag remains outside the milestone.

## Handoff

- Complete. Continue from `ROADMAP_NEXT.md` and `ROADMAP.md` with the next
  production-readiness slice; do not create or move an RC tag without explicit
  approval.
