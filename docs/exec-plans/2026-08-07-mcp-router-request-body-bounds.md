# MCP Router Request Body Bounds

Status: active; implementation and local verification clean; push and exact-head
hosted evidence pending

## Goal

Give router-hosted MCP endpoints a configurable raw-byte request-body limit and
reject oversized POST requests before Dart materializes or decodes the payload,
without weakening bearer precedence or compatibility-session state.

## Scope

- In scope: MCP route option validation, public and protected router-hosted
  POST handling, modern stateless and maintained Streamable HTTP behavior,
  focused native-router coverage, and normal local/hosted deployment evidence.
- Out of scope: generic non-MCP HTTP route limits, native transport flow-control
  changes, response/SSE limits, or client-side request limits already completed
  by the preceding checkpoint.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/test/router_json_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `packages/connectanum_router/CHANGELOG.md`
- `docs/examples.md`
- `docs/project_state.md`
- This plan.

## Preconditions

- Both maintained `master` branches and the local branch start at `7e0dab69`.
- The preceding client request-body checkpoint passed local verification,
  exact-head CI, package publish dry run, WAMP profile gates, Router Image dry
  run, and the comprehensive strict deployment-chain audit.
- Pre-change `bin/test-fast` passed the complete fast regression and
  router-hosted consumer matrix on 2026-08-07.

## Plan

1. Reproduce the missing positive MCP route option and oversized public,
   protected, modern, and compatibility POST behavior.
2. Enforce a 16 MiB default raw-byte limit from the native request-body
   descriptor before materialization or JSON decoding, keeping missing-bearer
   rejection authoritative and active compatibility sessions reusable.
3. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_json_test.dart`
- focused `router_integration_native_test.dart` regression
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source inspection found that `RouterHttpRequest.nativeBody`
  exposes the raw request length without materialization, while the MCP handler
  currently reaches `request.body` and UTF-8/JSON decoding with no route-level
  byte cap. The client-side 16 MiB bound does not protect arbitrary or
  independently implemented consumers, so the router needs its own boundary.
- 2026-08-07: Fail-first route validation accepted a zero-byte limit, and the
  native integration regression returned a successful oversized ping instead
  of HTTP `413`. The route now accepts positive `max_request_bytes` and
  `maxRequestBytes` values, defaults to 16 MiB, and checks the native raw-body
  descriptor after bearer/session authorization but before materialization,
  UTF-8 decoding, or JSON parsing.
- 2026-08-07: Focused route validation and native integration tests pass. The
  integration regression proves raw UTF-8 byte counting with a multibyte body,
  missing-bearer `401` precedence, sessionless modern recovery, compatibility
  session retention without response-header reflection, direct modern `413`,
  and a valid tool call plus DELETE cleanup after rejection. Router analysis
  and `git diff --check` are clean.
- 2026-08-07: Post-change `bin/test-fast` passed 360 core, 95 MCP, 280
  MCP/client, and 96 benchmark/live-router tests plus neutral isolated/global
  consumer packages, every maintained router-hosted MCP live variant, Router
  CLI consumer coverage, and focused native-router regressions.
- 2026-08-07: Final `bin/verify` passed with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core, 95
  MCP, 280 MCP/client, 96 benchmark/live-router, and 388 router tests; all 13
  focused native-forwarding regressions; every neutral consumer package and CLI
  smoke; and Chrome Dart2Wasm WebSocket coverage.

## Handoff

- Commit and push the implementation with its checkpoint state, then audit the
  exact-head hosted deployment chain.
