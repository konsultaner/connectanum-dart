# MCP Client Close Session-State Integrity

Status: complete

## Goal

Make `McpStreamableHttpClient.close()` authoritative over compatibility-era
session and resume state, so a consumer application cannot observe a delayed
request establishing reusable protocol state after local client shutdown.

## Context

Compatibility Streamable HTTP requests already capture opaque session and
resume ownership before their first await. `close()` currently renews only the
request-scoped listener ownership token. When the ordinary HTTP transport is
caller-owned, a delayed `initialize` can therefore complete after close and
still assign `sessionId`, protocol version, and resume state to the closed MCP
client.

## Plan

1. Add a fail-first client regression that delays compatibility initialize,
   closes the MCP client, releases the response, and proves no session or
   resume state can establish after shutdown.
2. Invalidate and clear compatibility session/resume ownership during local
   close without closing a caller-owned shared `HttpClient`.
3. Preserve modern request-scoped listener shutdown and independent bearer
   ownership behavior.
4. Extend the neutral client-only consumer-package smoke with the delayed
   initialize race, then run focused analysis/tests and `bin/verify`.
5. Update project state, commit and push the implementation with its evidence,
   then audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast`: passed on 2026-08-05.
- Focused fail-first regressions: reproduced both a delayed compatibility
  initialize assigning `sessionId` after client shutdown and active
  compatibility session/resume state remaining visible after shutdown.
- Focused client analysis/tests: passed; all 150 Streamable HTTP client tests
  pass, including delayed initialize invalidation and active local-state
  cleanup.
- Client-only consumer-package smoke: passed from source and through the
  globally activated public package command. The source smoke also proves a
  replacement MCP client can initialize over the same caller-owned
  `HttpClient` after the first client closes.
- Full `bin/verify`: passed on 2026-08-05. Verification covered 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete
  230-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke.
- Hosted exact-head deployment audit: passed. Commit `01d44976` is on both
  maintained `master` branches. GitHub CI `31028976087`, Dart Package Publish
  Dry Run `31028976021`, WAMP Profile Benchmarks `31028976517`, and Router
  Image dry run `31030424768` passed. Coverage artifact `8940392983`, WAMP
  artifact `8940067055`, Router Image preview artifact `8940419706`, and
  Docker build records `8940541202` and `8940540220` were uploaded. The
  comprehensive strict deployment-chain audit passes with clean exact-head CI
  logs, loaded-image MCP runtime smoke, multi-architecture image build, and all
  required branch, workflow, package, native-release, publish-dry-run,
  benchmark, and registry gates clean. Release-candidate readiness remains
  intentionally non-gating until an approved numeric RC tag points at the
  release commit.

## Outcome

Client shutdown now clears compatibility session and resume state before
listener and transport cleanup. Renewing the existing compatibility ownership
token makes a delayed initialize response stale, so it may finish validation
but cannot establish reusable session or protocol state after close. The
change leaves caller-owned HTTP transport open, preserves independent bearer
and request-scoped listener ownership, and is exercised through the public MCP
IO entrypoint by a neutral generated consumer package.
