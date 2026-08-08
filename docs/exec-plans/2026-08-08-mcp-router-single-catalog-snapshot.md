# MCP Router Single Catalog Snapshot

Status: complete; implementation commit `55d521e8` is published on both
maintained `master` branches, and local plus exact-head hosted verification is
green

## Goal

Make each router-hosted MCP POST refresh and authorize its route-visible tool
catalog once before request metadata validation, then dispatch against that
same bound catalog without a second refresh.

## Context

The HTTP handler already acquires the endpoint request hold and calls
`_refreshTools()` before validating `Mcp-Param-*` headers. Endpoint dispatch
then called `_refreshTools()` again. One initialize request therefore repeated
every catalog authorization decision, and the second pass could rebind tool
handlers after the request headers had been validated.

## Plan

1. Add a native-router regression that counts authorization decisions for one
   exact catalog topic during a single initialize request.
2. Keep the pre-validation refresh and dispatch through a method whose name
   records the already-refreshed precondition.
3. Run focused catalog tests, router analysis, `bin/test-fast`, and
   `bin/verify`; publish the implementation and collect exact-head deployment
   evidence.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed.
- 2026-08-08: The fail-first regression reproduced two matching authorization
  decisions for one initialize request (`expected 1`, `actual 2`).
- 2026-08-08: POST dispatch now uses `_handleMessageAfterRefresh` and no longer
  performs the redundant second catalog refresh. The pre-validation refresh,
  request hold, idle-deadline behavior, and GET/SSE refresh remain unchanged.
- 2026-08-08: The new regression and all four catalog-focused native-router
  tests pass; `dart analyze packages/connectanum_router` reports no issues.
- 2026-08-08: Post-change `bin/test-fast` passed, including the complete
  router-hosted MCP consumer and Router CLI lifecycle smokes.
- 2026-08-08: Final exact-code `bin/verify` passed with zero formatting
  changes, 114 Rust core tests plus serializer integrations, 52 Rust FFI tests
  plus the focused metrics check, 360 Dart core tests, all 97 MCP tests, the
  complete 280-case MCP/client suite, all 96 benchmark tests including 36 live
  WAMP workloads, all 398 router tests, the 6-case remote-auth process, the
  13-case native follow-up, every generated and globally activated consumer
  smoke, and Chrome/Dart2Wasm.
- 2026-08-08: Commit `55d521e8` is published on both maintained `master`
  branches. Exact-head GitHub CI `31253070397`, Dart Package Publish Dry Run
  `31253070381`, WAMP Profile Benchmarks `31253070382`, and Router Image dry
  run `31253101003` passed on their first attempts. Coverage artifact
  `9020790460`, WAMP artifact `9020671585`, Router Image preview artifact
  `9020605359`, and Docker build records `9020648283` and `9020648026` were
  uploaded.
- 2026-08-08: The comprehensive strict deployment-chain audit exited zero
  with clean exact-head CI jobs and logs, package and native-release evidence,
  loaded-image MCP runtime smoke, multi-architecture image build, WAMP profile
  gates, branch protection, workflow visibility, and public router-package
  visibility all ready. RC tagging remains a separate release approval
  decision and was not changed.

## Handoff

- Milestone complete. Select the next router-hosted MCP or downstream
  application readiness gap from the roadmaps and current implementation
  evidence.
