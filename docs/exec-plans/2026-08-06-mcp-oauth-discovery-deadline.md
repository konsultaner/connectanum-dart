# MCP OAuth Discovery Deadline

Status: complete

## Goal

Bound the complete public MCP OAuth metadata-discovery flow so a consumer
application cannot remain pending indefinitely while a protected resource or
authorization server stalls before headers or during a response body.

## Context

Protected Resource Metadata and Authorization Server Metadata discovery already
avoid credentials, validate endpoints and documents, and cap response sizes.
Unlike token exchange, dynamic registration, and loopback callback handling,
the discovery helpers do not currently expose or enforce a timeout. The
authorization-server flow can also try multiple well-known locations, so a
per-request timeout would let the complete operation multiply its advertised
bound.

The standalone helpers and `McpStreamableHttpClient` wrappers should accept one
positive optional timeout, default consistently with the other OAuth network
helpers, and consume it as a monotonic total deadline across every request,
response header, response body, and fallback attempt. Timeout failures must be
typed and redacted, while client close must retain authority to abort tracked
operations immediately.

## Plan

1. Preserve the green fast-suite baseline and add fail-first regressions for a
   protected-resource body stalled after headers and authorization-server
   fallback work sharing one total deadline.
2. Add a backward-compatible timeout parameter to standalone discovery helpers
   and public Streamable HTTP client wrappers, rejecting non-positive values.
3. Apply one monotonic deadline across request open, headers, bounded body
   consumption, challenged metadata, and all well-known fallback attempts.
4. Run focused discovery/client analysis and tests, package-boundary smokes,
   `bin/test-fast`, and `bin/verify`.
5. Update the public contract and project state, bundle the carried hosted-
   evidence bookkeeping with the implementation commit, push both maintained
   branches, and audit the exact-head deployment chain.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06, including every neutral
  source/global package smoke and the router CLI MCP lifecycle matrix.
- Three fail-first regressions produced four missing-public-parameter load
  errors. A fourth regression then completed coverage for protected-resource
  stalls before headers. A fifth fail-first regression verified that a
  caller-owned request hook throwing `TimeoutException` is not misclassified
  as discovery deadline exhaustion. The final coverage also includes body
  stalls, a shared authorization-server fallback deadline, and non-positive
  timeout rejection.
- Focused analysis passes for both public packages. All 18 combined discovery
  and client-close lifecycle cases pass, including immediate close authority;
  the public `connectanum_mcp` IO authorization-discovery smoke also passes
  with explicit timeout arguments.
- Post-change `bin/test-fast` passes with 360 core tests, all 94 MCP tests, the
  complete 252-case MCP/client suite, all 96 benchmark tests with live-router
  workloads, every neutral source/global package smoke, and the complete
  router CLI MCP lifecycle matrix.
- Full `bin/verify` passes with zero formatting changes; 113 Rust core tests
  plus serializer integrations; 52 Rust FFI tests; 360 Dart core, 94 MCP, 252
  MCP/client, 96 benchmark/live-router, and 387 router tests; focused native
  and router regressions; every neutral consumer package and CLI smoke; and
  Chrome Dart2Wasm WebSocket coverage.
- Implementation commit `eea78895` is on both maintained `master` branches.
  Exact-head GitHub CI `31075172121`, Dart Package Publish Dry Run
  `31075172097`, WAMP Profile Benchmarks `31075172100`, and Router Image dry
  run `31075183929` passed without a rerun.
- CI uploaded coverage artifact `8957556217`; WAMP uploaded benchmark artifact
  `8957335493`; Router Image uploaded preview artifact `8957201307` and Docker
  build records `8957267159` and `8957266808`.
- The comprehensive strict deployment-chain audit passed with clean exact-head
  CI logs, package and native-release dry-run evidence, the loaded-image MCP
  runtime smoke, the multi-architecture image build, the WAMP profile gate,
  workflow visibility, branch protection, and the public router package all
  ready. RC tagging remains an explicit release-approval action outside this
  checkpoint.

## Outcome

The public standalone helpers and `McpStreamableHttpClient` wrappers now accept
a positive optional timeout with a ten-second default. One monotonic stopwatch
budgets the endpoint probe, challenged and well-known metadata, response
headers and bounded bodies, and every authorization-server fallback. Timeout
failures remain typed and do not include response or credential material;
requests that open after their caller has already timed out are aborted, and
client close remains authoritative. Local verification, exact-head hosted
workflows, and the comprehensive strict deployment-chain audit are clean.
