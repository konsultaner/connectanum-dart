# Exec Plan: MCP Route-Match Scope Isolation

Status: completed
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Give every configured router-hosted MCP route match a stable, collision-free
identity for anonymous compatibility sessions and hosted endpoint instances.

## Problem

MCP route state currently keys a configured exact path and prefix by their raw
text alone. An exact `/mcp` route and a prefix `/mcp` route can therefore share
an anonymous compatibility session and hosted endpoint even when their MCP
server options differ. Routes without a path or prefix have the inverse issue:
their identity falls back to the incoming request path and fragments one
configured route across request targets.

## Plan

1. Add a real native-router fail-first regression with exact and prefix MCP
   routes that share the same route text but expose distinct server metadata.
2. Derive one canonical digest from the complete configured `HttpRouteMatch`
   and use it for both anonymous compatibility-session and endpoint keys.
3. Keep method-provided actions on one configured route in the same scope by
   excluding the effective action from route identity.
4. Run focused, fast, and full verification, then publish and collect exact-head
   deployment-chain evidence.

## Progress

- 2026-08-16: Serena and repository preflight completed with no unrelated
  editor or stale lock. The inherited working-tree changes are the preceding
  MCP capacity milestone's exact-head hosted-evidence notes.
- 2026-08-16: Pre-change `bin/test-fast` passed, including all 97 benchmark
  tests with 37 live WAMP workloads and every maintained MCP consumer/CLI
  smoke.
- 2026-08-16: The native regression first failed because a stateless request
  through the prefix `/mcp` route discovered the exact `/mcp` route's server
  name. Anonymous compatibility-session and endpoint keys now use a canonical
  digest of all configured `HttpRouteMatch` fields instead of a lossy route
  string.
- 2026-08-16: A second native regression proves a compatibility session opened
  through one target of a pathless configured route remains usable through a
  different target. The effective HTTP action remains outside the digest so
  method-provided MCP actions retain one configured route scope.
- 2026-08-16: Both new regressions pass together; the exact/prefix regression
  also passes five consecutive runs. Anonymous delimiter-collision and
  concurrent-session reuse tests, method-route session/listener/WAMP capacity
  tests, route/principal session isolation, and full router analysis pass.
- 2026-08-16: Post-change `bin/test-fast` passed, including all 97 benchmark
  tests with 37 live WAMP workloads and every maintained MCP consumer/CLI
  smoke.
- 2026-08-16: Canonical `bin/verify` passed with zero formatting changes, 117
  Rust core/serializer tests, 52 native FFI tests, the feature-gated native
  metrics snapshot, 366 Dart core tests, 116 MCP tests, the complete 293-case
  MCP/client suite, all 97 benchmark tests including 37 live WAMP workloads,
  all 454 router cases, six remote-auth tests, 13 native follow-ups, every
  maintained consumer/global-activation smoke, Chrome, and Dart2Wasm.
- 2026-08-16: Commit `b62321d1` was published to both maintained `master`
  branches. Exact-head CI `31938376766`, Dart Package Publish Dry Run
  `31938376722`, WAMP Profile Benchmarks `31938376734`, and Router Image dry
  run `31939258624` all passed. Coverage artifact `9261540904`, WAMP artifact
  `9261400703`, Router Image preview artifact `9261555369`, and Docker build
  records `9261615068` and `9261614729` are available.
- 2026-08-16: The comprehensive strict deployment-chain audit passed with
  clean exact-head CI jobs and logs, package and native release dry-run
  evidence, the loaded-image router-hosted MCP smoke, the multi-architecture
  image build, WAMP benchmark evidence, workflow visibility, branch
  protection, and public Router Image package visibility. Its non-gating RC
  summary remains intentionally not ready because no approved numeric RC tag
  points at this implementation commit.

## Handoff

- Complete. The implementation, local verification, publication, exact-head
  hosted workflows, artifact evidence, and comprehensive strict audit all
  pass.
