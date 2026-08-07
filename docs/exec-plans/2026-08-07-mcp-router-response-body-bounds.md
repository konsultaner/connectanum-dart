# MCP Router Response Body Bounds

Status: completed; local and exact-head hosted verification clean

## Goal

Bound buffered router-hosted MCP JSON and POST/SSE operation responses so a
WAMP callee, dynamic resource, or large catalog cannot make the router emit an
arbitrarily large HTTP response or exceed the public client's default response
budget without a route-level policy.

## Scope

- In scope: positive snake/camel MCP route options, a 16 MiB default aligned
  with the public Streamable HTTP client, raw UTF-8 response-byte accounting,
  direct JSON and maintained Streamable HTTP response paths, authorization
  precedence, compatibility-session retention, recovery, and normal local and
  hosted verification.
- Out of scope: truncating successful MCP results, limiting established
  request-scoped SSE listener lifetimes, generic non-MCP HTTP response limits,
  and changing the already-shipped client-side response bound.

## Preconditions

- Both maintained `master` branches and the local branch start at `70dc5f83`.
- The preceding router WAMP call-deadline checkpoint passed local verification,
  exact-head hosted workflows, and the comprehensive strict deployment audit.
- Pre-change `bin/test-fast` passed on 2026-08-07.

## Plan

1. Add fail-first route validation and native-router regressions showing that a
   configured MCP response limit is currently ignored.
2. Add positive `max_response_bytes` and `maxResponseBytes` route options with
   a 16 MiB default, serialize operation responses once, and reject oversized
   results before opening a POST/SSE stream or handing bytes to the native
   immediate-response path.
3. Prove public direct JSON and protected compatibility/direct behavior,
   missing-bearer precedence, raw multibyte byte accounting, unchanged active
   session state, a successful smaller follow-up, and DELETE cleanup.
4. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_json_test.dart`
- focused `router_integration_native_test.dart` regression
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source audit found that the public MCP client caps buffered
  responses and SSE events at 16 MiB, while router-hosted operation responses
  are serialized and emitted without a route-side size policy. The router
  bound will reject the complete operation response rather than truncate it,
  preserve an existing compatibility session, and keep established
  request-scoped listener streams outside this buffered-response slice.
- 2026-08-07: Fail-first route validation accepted
  `max_response_bytes: 0`, and the native router emitted a successful response
  whose raw multibyte JSON exceeded a configured 4 KiB limit. The route now
  accepts positive snake/camel aliases with a 16 MiB default, serializes once,
  rejects oversized results before JSON or POST/SSE delivery with a bounded
  HTTP 500 JSON-RPC error, and reuses the serialized payload on success.
- 2026-08-07: Focused validation and native integration coverage pass. The
  regression proves raw UTF-8 byte accounting, public stateless rejection and
  recovery, missing-bearer precedence, protected compatibility and direct JSON
  rejection without a response session header, unchanged active session and
  resume state, a smaller successful follow-up, and DELETE cleanup.
- 2026-08-07: Post-change `bin/test-fast` passed the complete fast regression,
  benchmark, public consumer, global activation, Router CLI consumer, and
  focused native-router smoke matrix.
- 2026-08-07: Final `bin/verify` passed with zero formatting changes; 113 Rust
  core tests plus three serializer integrations, 52 Rust FFI tests, 360 Dart
  core, 95 MCP, 280 MCP/client, 96 benchmark/live-router, and 390 total router
  tests; every neutral package and CLI consumer smoke; all maintained router-
  hosted MCP live variants; and Chrome Dart2Wasm WebSocket coverage.
- 2026-08-07: Implementation commit `5e3c2391` is on both maintained `master`
  branches. Exact-head CI `31175973440` passed Fast Checks, Full Verify, Dart
  VM Coverage, Codecov upload, and coverage artifact `8993213873`. Dart Package
  Publish Dry Run `31175973400` and WAMP Profile Benchmarks `31175973516` with
  artifact `8993006909` passed on their first attempts. Router Image dry run
  `31177226809` passed preview artifact `8993286686`, the local image build,
  router-hosted MCP smoke, skipped GHCR login, and the non-publishing multi-
  architecture build.
- 2026-08-07: The comprehensive strict deployment-chain audit exited zero. It
  confirmed exact-head CI and clean logs, package/archive readiness, relevant
  native-release evidence, WAMP and Router Image artifacts, protected-branch
  checks, workflow visibility, and the public router package. A follow-up RC
  tag remains the expected approval-gated, non-blocking release decision.

## Handoff

- Completed. Leave this hosted-evidence bookkeeping uncommitted until it can be
  bundled with the next implementation/configuration commit.
