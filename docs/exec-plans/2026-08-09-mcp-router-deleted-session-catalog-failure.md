# MCP Router Deleted Session Catalog Failure

Status: complete

## Goal

Ensure a compatibility-era Streamable HTTP GET or POST whose router-hosted
catalog refresh fails after concurrent session deletion cannot return a stale
catalog error or advertise the removed MCP session.

## Context

Both compatibility request paths await catalog refresh and catch its errors
before re-checking endpoint disposal. If DELETE removes the endpoint while an
authorization provider is blocked and that provider then throws, the stale
request currently reaches the generic catalog-error response with HTTP 500 and
the deleted `mcp-session-id`. Session deletion must take precedence and fail
closed with the same sessionless 404 used after successful stale refreshes.

## Plan

1. Run the pre-change fast regression matrix and add deterministic
   native-router coverage that blocks then fails catalog authorization for both
   GET and POST while DELETE removes the compatibility session.
2. Reproduce the stale HTTP 500/session-header response, then make catalog
   refresh catches prefer endpoint disposal before reporting backend failure.
3. Prove both stale requests return sessionless 404, deleted session state stays
   cleared, and replacement sessions remain usable.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   prior hosted-evidence bookkeeping with the implementation, push both
   maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Repository-workflow and Serena preflight completed. Exact-head
  local and hosted verification is green, no unrelated same-repository Codex
  process or stale lock exists, and only the expected prior hosted-evidence
  notes were dirty at startup.
- 2026-08-09: Pre-change `bin/test-fast` passed, including the native-router
  integration suites, downstream consumer smokes, and benchmark harness.
- 2026-08-09: A deterministic blocked-then-failing authorization regression
  reproduced HTTP 500 after DELETE. GET and POST catalog-error catches now
  defer to the existing disposed-endpoint guard, so both return sessionless
  HTTP 404 and a replacement session remains usable.
- 2026-08-09: The focused regression, the adjacent pending-GET deletion and
  live-session catalog-error recovery tests, and package analysis pass.
- 2026-08-09: Post-change `bin/test-fast` passed end to end, including native
  integration, all MCP/client suites, benchmark coverage, and neutral consumer
  and router CLI package smokes.
- 2026-08-09: Full `bin/verify` passed formatting, Rust core and FFI suites,
  360 Dart core tests, 101 MCP tests, the complete 280-case client MCP matrix,
  all 96 benchmark tests and 36 live WAMP workloads, all 415 router tests,
  isolated consumer/CLI and remote-auth checks, native follow-ups, and
  Chrome/Dart2Wasm.
- 2026-08-09: Implementation commit `1a18bfb3` was pushed to both maintained
  `master` branches. Exact-head GitHub CI `31324200297`, Dart Package Publish
  Dry Run `31324200279`, WAMP Profile Benchmarks `31324200308`, and Router
  Image dry run `31324933290` all passed. Retained artifacts are Dart VM
  coverage `9041243070`, WAMP profile evidence `9041134316`, Router Image
  preview `9041251723`, and Docker build records `9041307233` and
  `9041306910`.
- 2026-08-09: The comprehensive strict deployment-chain audit exited zero with
  clean exact-head CI jobs and logs plus every required package, relevant
  native release, loaded-image MCP smoke, multi-architecture image build,
  WAMP, workflow-visibility, branch-protection, and public GHCR gate ready.
  Only the deliberately unapproved next RC tag remains outside this milestone.
