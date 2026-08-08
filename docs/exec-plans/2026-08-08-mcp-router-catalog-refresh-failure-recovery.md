# MCP Router Catalog Refresh Failure Recovery

Status: complete; implementation commit `a38a4f36` is published on both
maintained `master` branches, and local plus exact-head hosted verification is
green

## Goal

Return bounded, generic MCP HTTP errors when router-hosted catalog authorization
fails unexpectedly, while preserving compatibility-session state and allowing
the shared endpoint's next catalog refresh to recover.

## Context

Every router-hosted MCP GET or POST refreshes the route-visible WAMP catalog
before dispatch. Dynamic authorization-provider exceptions currently escape the
MCP handler into the boss's unawaited HTTP callback. The boss records the
exception but cannot construct a protocol response, so a downstream application
can be left waiting instead of receiving a fail-closed MCP error. The endpoint's
new refresh queue is designed to recover after an individual failure, but that
behavior is not yet proven through either direct JSON or compatibility-era
Streamable HTTP.

## Plan

1. Add a native-router regression that injects one catalog authorization
   failure and proves direct JSON plus compatibility-era Streamable HTTP receive
   generic bounded errors without leaking provider details or mutating session
   state.
2. Convert catalog-refresh exceptions into HTTP 500 MCP JSON-RPC errors at both
   GET and POST request boundaries, preserving existing session headers only
   for established compatibility sessions.
3. Prove the next request on the same shared endpoint succeeds, then run focused
   native-router tests, router analysis, `bin/test-fast`, and `bin/verify`.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed the complete fast regression,
  live WAMP benchmark, package-boundary smoke, and Router CLI consumer matrix.
- 2026-08-08: The fail-first native-router regression reproduced an escaped
  authorization-provider exception as the native fallback body
  `http request cancelled`, without the JSON-RPC request id or MCP error.
- 2026-08-08: Router-hosted catalog refresh failures now return a generic MCP
  internal-error response for GET and POST. Stateless and rejected-initialize
  responses omit session state, while established Streamable failures preserve
  the session header and client resume cursor. Operational events retain only
  the exception type, not provider text or a stack trace.
- 2026-08-08: The regression proves direct JSON recovery, tentative initialize
  cleanup and recovery, established Streamable POST recovery, and Streamable
  GET recovery on the next queued refresh. All six catalog-focused native tests
  pass and router analysis is clean.
- 2026-08-08: Post-change `bin/test-fast` passes the complete fast regression,
  all 97 MCP and 280 MCP/client tests, all 96 benchmark tests including 36 live
  WAMP workloads, and the package-boundary plus Router CLI consumer smokes.
- 2026-08-08: Final exact-tree `bin/verify` passes with zero formatting changes;
  114 Rust core tests plus serializer integrations; 52 Rust FFI tests plus the
  focused metrics check; 360 Dart core, 97 MCP, 280 MCP/client, 96 benchmark,
  and 400 Router tests; the 6-case remote-auth and 13-case native follow-ups;
  every generated and globally activated consumer smoke; and Chrome/Dart2Wasm.
- 2026-08-08: Commit `a38a4f36` is published on both maintained `master`
  branches. Exact-head GitHub CI `31260151107`, Dart Package Publish Dry Run
  `31260151102`, WAMP Profile Benchmarks `31260151103`, and Router Image dry run
  `31260156806` passed. Coverage artifact `9022736910`, WAMP artifact
  `9022620487`, Router Image preview artifact `9022546345`, and Docker build
  records `9022594537` and `9022594246` were uploaded.
- 2026-08-08: The comprehensive strict deployment-chain audit exited zero with
  clean exact-head CI jobs and logs, package and native-release evidence,
  loaded-image MCP runtime smoke, multi-architecture image build, WAMP profile
  gates, branch protection, workflow visibility, and public router-package
  visibility all ready. RC tagging remains a separate release approval decision
  and was not changed.

## Handoff

- Milestone complete. Select the next router-hosted MCP or downstream
  application readiness gap from the roadmaps and current implementation
  evidence.
