# MCP Client Listener Close Concurrency

Status: complete

## Goal

Make `McpStreamableHttpClient.close()` authoritative over MCP `2026-07-28`
request-scoped listeners that are still opening, so a consumer application
cannot retain a live listener-owned HTTP connection after client shutdown.

## Context

Each `subscriptions/listen` request intentionally owns a fresh `HttpClient` so
listeners remain independently cancellable and isolated from ordinary MCP
requests. The client currently records only fully constructed subscriptions.
A listener blocked in `postUrl`, response setup, or SSE validation is therefore
invisible to `close()` and can establish after shutdown.

## Plan

1. Add a fail-first client regression that delays the dedicated listener HTTP
   client, closes the MCP client, releases the delayed request, and proves the
   listener cannot establish.
2. Track dedicated listener clients from creation until their atomic promotion
   to active subscriptions, and make `close()` terminate both pending clients
   and established subscriptions.
3. Preserve request-scoped listener isolation from compatibility-era session,
   resume-cursor, and bearer-rotation ownership.
4. Extend the neutral client-only consumer-package smoke with the shutdown race
   when practical, then run focused analysis/tests and `bin/verify`.
5. Update project state, commit and push the implementation with its evidence,
   then audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast`: passed on 2026-08-05.
- Focused fail-first regression: reproduced a delayed listener becoming active
  after client shutdown.
- Focused client analysis/tests: passed; all 148 Streamable HTTP client tests
  pass, including pending-open and post-validation close races.
- Client-only consumer-package smoke: passed from source and through the
  globally activated public package command.
- Full `bin/verify`: passed on 2026-08-05. Verification covered 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete
  228-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke.
- Hosted exact-head deployment audit: passed. Commit `7f7b0ea4` is on both
  maintained `master` branches. GitHub CI `31022233783`, Dart Package Publish
  Dry Run `31022234067`, WAMP Profile Benchmarks `31022233751`, and Router
  Image dry run `31023620393` passed. Coverage artifact `8937595450`, WAMP
  artifact `8937332685`, Router Image preview artifact `8937663622`, and
  Docker build records `8937780968` and `8937780005` were uploaded. The
  comprehensive strict deployment-chain audit passes with clean exact-head CI
  logs, loaded-image MCP runtime smoke, multi-architecture image build, and all
  required branch, workflow, package, native-release, publish-dry-run,
  benchmark, and registry gates clean. Release-candidate readiness remains
  intentionally non-gating until an approved numeric RC tag points at the
  release commit.

## Outcome

Dedicated request-scoped listener clients are now tracked from creation until
their atomic promotion to active subscriptions. Client shutdown renews a
listener ownership token, force-closes pending clients, and closes established
subscriptions. A listener that finishes validation after shutdown cannot
promote itself, and every request or response validation failure releases its
pending client. The generated neutral consumer smoke proves the pending-open
shutdown race through the public MCP IO entrypoint without private project
assumptions.
