# MCP Router WAMP Call Deadline

Status: completed; local and exact-head hosted verification clean

## Goal

Bound router-hosted MCP tool and dynamic-resource WAMP calls with the router's
existing protocol-level CALL timeout so a stalled application callee cannot
hold an HTTP request and compatibility-session idle lease indefinitely.

## Scope

- In scope: MCP route option validation, configured and discovered WAMP tool
  calls, WAMP-backed dynamic resource reads, direct JSON and maintained
  Streamable HTTP behavior, timeout/cancellation evidence, and normal local
  and hosted verification.
- Out of scope: a blanket HTTP-future timeout that could allow late pub/sub
  side effects, established request-scoped SSE stream lifetimes, generic WAMP
  realm timeout behavior, and already-completed client transport deadlines.

## Preconditions

- Both maintained `master` branches and the local branch start at `acfebd21`.
- The preceding router request-body checkpoint passed local verification,
  exact-head hosted workflows, and the comprehensive strict deployment audit.
- Pre-change `bin/test-fast` passed on 2026-08-07.

## Plan

1. Add fail-first route validation and native-router regressions showing that a
   stalled MCP-backed callee currently receives no bounded CALL timeout.
2. Add a positive route-level WAMP call deadline, defaulting to the realm call
   timeout, and clamp every router-hosted MCP tool/resource CALL to that bound
   while preserving request metadata and any stricter caller timeout.
3. Prove direct JSON and compatibility requests fail within the bound, the
   callee is interrupted, the compatibility session remains reusable, and a
   subsequent normal call succeeds.
4. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_json_test.dart`
- focused `router_integration_native_test.dart` regression
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Roadmap and source audit found that the public MCP client has a
  30-second exchange deadline, but router-hosted MCP WAMP calls do not attach
  the router's existing CALL timeout. A blanket HTTP `Future.timeout` was
  rejected because it cannot cancel Dart futures and could permit late
  subscription or publication state changes after an HTTP timeout. The
  protocol CALL timeout is cancellation-aware and covers both tool calls and
  WAMP-backed dynamic resource reads.
- 2026-08-07: Fail-first route validation accepted `call_timeout_ms: 0`, and a
  native-router regression left a stalled direct tool call pending beyond its
  two-second test budget. The route now accepts positive snake/camel aliases,
  uses a positive realm call timeout or 30-second fallback, and clamps every
  MCP WAMP CALL without discarding stricter request metadata.
- 2026-08-07: Focused route validation and native integration coverage pass.
  The regression proves direct JSON and compatibility tool timeout results,
  distinct router invocation-timeout events, a bounded WAMP-backed dynamic
  resource read, unchanged session identity, a successful follow-up call, and
  DELETE cleanup.
- 2026-08-07: Post-change `bin/test-fast` passed the complete fast regression,
  benchmark, public consumer, global activation, and router CLI smoke matrix.
- 2026-08-07: Full verification exposed process-lifetime interference between
  `remote_auth_integration_test.dart` and later native HTTP/3 client helpers:
  the files passed independently, while a shared Dart test process reproduced
  a 30-second HTTP/3 handshake timeout. The canonical router suite now tags
  and runs the six remote-auth cases in a dedicated native-runtime process;
  the remaining 383 router cases pass in the clean main process without
  weakening coverage.
- 2026-08-07: Final `bin/verify` passed with zero formatting changes; 113 Rust
  core tests plus three serializer integrations, 52 Rust FFI tests, 360 Dart
  core, 95 MCP, 280 MCP/client, 96 benchmark/live-router, and 389 total router
  tests; every neutral package and CLI consumer smoke; all maintained
  router-hosted MCP live variants; and Chrome Dart2Wasm WebSocket coverage.
- 2026-08-07: Implementation commit `70dc5f83` is on both maintained `master`
  branches. Exact-head CI `31169370199` passed Fast Checks, Full Verify, Dart
  VM Coverage, Codecov upload, and the coverage artifact. Dart Package Publish
  Dry Run `31169370330`, WAMP Profile Benchmarks `31169370200` with its hosted
  artifact, and Router Image dry run `31170678231` with its preview artifact,
  local image build, router-hosted MCP smoke, and non-publishing multi-
  architecture build all passed.
- 2026-08-07: The comprehensive strict deployment-chain audit exited zero. It
  confirmed exact-head CI and clean logs, package/archive readiness, relevant
  native-release evidence, WAMP and Router Image artifacts, protected-branch
  checks, workflow visibility, and the public router package. A follow-up RC
  tag remains the expected approval-gated, non-blocking release decision.

## Handoff

- Completed. Leave this hosted-evidence bookkeeping uncommitted until it can be
  bundled with the next implementation/configuration commit.
