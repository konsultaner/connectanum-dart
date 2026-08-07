# MCP Request Body Bounds

Status: completed; local and exact-head hosted verification clean

## Goal

Give consumer applications a configurable bound for MCP JSON request bodies
and reject oversized UTF-8 payloads before any ordinary or listener HTTP
transport is opened.

## Scope

- In scope: all public `McpStreamableHttpClient` constructors, ordinary
  Streamable/direct JSON POSTs, `subscriptions/listen` setup, focused public
  client coverage, and the normal local/hosted deployment evidence chain.
- Out of scope: streaming JSON request encoders, changing router ingress body
  limits, response/SSE limits, or established subscription lifetime behavior.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `docs/project_state.md`
- This plan.

## Preconditions

- Both maintained `master` branches and the local implementation checkpoint
  started aligned at `674ffc0e`.
- The prior request-serialization preflight is implemented, pushed, and locally
  verified. Its exact-head CI, package dry run, and Router Image gates are
  green; only WAMP hosted recovery remains deferred during a GitHub Actions
  major outage.
- Pre-change `bin/test-fast` passed, including the router-hosted MCP consumer
  matrix.

## Plan

1. Reproduce the missing request-size setting across all public constructors.
2. Bound encoded raw UTF-8 request bytes before opening ordinary or listener
   transport and prove overflow does not poison caller-owned client reuse.
3. Run focused, fast, and full verification; update state; commit, push both
   maintained branches, and audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-06: The fail-first focused suite did not compile because
  `maxRequestBytes`, its default, and its public field were absent from all
  seven constructors.
- 2026-08-06: Request bodies now share one encode-and-bound preflight. The
  positive setting defaults to 16 MiB, matching the existing buffered-response
  safety default, and overflow raises `McpStreamableProtocolException` without
  embedding request content.
- 2026-08-06: Focused coverage proves the limit counts raw UTF-8 bytes rather
  than Dart string characters, performs zero ordinary transport opens on
  overflow, permits a smaller follow-up request through the same caller-owned
  client, and allocates no subscription transport for an oversized listener
  request. All 175 focused Streamable client tests and all 14 public MCP IO
  boundary tests pass; both maintained packages analyze cleanly.
- 2026-08-06: Post-change `bin/test-fast` passes 360 core, 95 MCP, 280
  MCP/client, and 96 benchmark/live-router cases plus every neutral consumer,
  global-activation, CLI, and focused native/router follow-up.
- 2026-08-06: Final `bin/verify` passes with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  95 MCP, 280 MCP/client, 96 benchmark/live-router, and 387 router tests; all 13
  focused native-forwarding regressions; every neutral consumer package and
  CLI smoke; and Chrome Dart2Wasm WebSocket coverage.
- 2026-08-06: Implementation commit `7e0dab69` is on both maintained `master`
  branches. Exact-head CI `31127477848` completed Fast Checks successfully, but
  GitHub cancelled Full Verify and Dart VM Coverage before either executed a
  step. Exact-head Dart Package Publish Dry Run `31127478333`, WAMP Profile
  Benchmarks `31127478801`, and Router Image dry run `31127479113` were also
  cancelled with zero steps. Every cancelled job has GitHub's hosted-runner
  annotation that it was not acquired after multiple attempts while GitHub
  Status reported Actions in a major outage.
- 2026-08-06: The comprehensive strict deployment-chain audit exited one only
  because exact-head CI, package, WAMP, and Router Image runs were not complete
  green signals. It confirmed the successful exact-head Fast Checks job,
  relevant clean Native Artifacts evidence, protected-branch gates, checked-in
  workflow visibility, and the public router package. No hosted job reported a
  repository test, build, packaging, image, or benchmark failure.
- 2026-08-07: GitHub Actions recovered. Attempt two of exact-head CI
  `31127477848`, Dart Package Publish Dry Run `31127478333`, WAMP Profile
  Benchmarks `31127478801`, and Router Image dry run `31127479113` passed every
  job. The comprehensive strict deployment-chain audit then exited zero with
  clean exact-head CI/log, package, benchmark-artifact, Router Image runtime
  smoke/multi-architecture, protected-branch, workflow-visibility, and public
  router-package gates.

## Handoff

- Completed. The router-side request-body boundary continues in
  `docs/exec-plans/2026-08-07-mcp-router-request-body-bounds.md`.
