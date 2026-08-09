# MCP Router In-Flight Resource Subscribe Authorization Refresh

Status: active

## Goal

Prevent compatibility and modern router-hosted MCP resource-subscription
requests from publishing stale ownership after a newer catalog refresh removes
subscribe authorization while the request is still awaiting authorization or
physical WAMP subscription setup.

## Context

Established resource-update owners are reconciled against current resource
visibility and update-topic subscribe authorization. Pending compatibility
requests are not represented until their authorization decision returns, while
modern preparations are not counted until physical subscription setup
completes. A newer refresh can therefore revoke access and finish before the
older request resumes, allowing that stale request to report or acknowledge a
resource subscription that the refreshed endpoint no longer authorizes.

## Plan

1. Add a deterministic fail-first native-router regression that blocks an
   owner authorization decision, refreshes the endpoint under revoked access,
   and proves the stale modern request currently acknowledges resource
   ownership and adds a broker subscriber.
2. Track each pending compatibility and modern resource owner before its first
   asynchronous authorization step, mark it irrevocably revoked during
   reconciliation, and prevent stale completion from reasserting ownership.
3. Keep shared physical subscriptions, response bounds, session isolation,
   explicit restored-access replacement subscriptions, and cleanup retry
   behavior intact; add compatibility coverage for the same race.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   the prior hosted-evidence bookkeeping with the implementation, push both
   maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Serena preflight and symbol tracing confirmed the gap. Pending
  generic WAMP pub/sub subscriptions are refresh-aware, but resource ownership
  begins only after asynchronous authorization or physical subscription setup.
- 2026-08-09: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark/live-WAMP, consumer-package, globally activated, and
  Router CLI smoke matrix.
- 2026-08-09: A fail-first native-router regression blocked an allowed owner
  decision, completed a newer denied catalog refresh, then reproduced the
  modern request acknowledging `app://mcp/live-context` after revocation.
- 2026-08-09: Compatibility and modern resource owners now enter explicit
  endpoint preparation state before their first authorization await. A
  successful refresh checks a snapshot of those preparations, marks denied or
  hidden ownership irrevocably revoked, excludes it from shared physical WAMP
  retention, rebuilds modern acknowledgment filters, and makes compatibility
  requests return the existing authorization error without disturbing their
  Streamable session.
- 2026-08-09: The regression now covers both protocol eras, absent leaked
  subscription metadata, sessionless modern state, stable compatibility
  session identity, and explicit restored-access replacement subscriptions.
  Router analysis and ten focused resource authorization, established-owner
  revocation, cleanup-retry, listener-capacity, and response-bound tests pass.
- 2026-08-09: An advisory local review identified mutation risk when a pending
  preparation completes during awaited refresh authorization. Reconciliation
  now iterates a fixed snapshot; the other findings were disproved against the
  traced call graph and existing established compatibility coverage.
- 2026-08-09: Post-change `bin/test-fast` and `bin/verify` passed on Darwin
  arm64. Full verification included unchanged formatting across 397 files,
  native Rust core/FFI tests, 410 router tests, 360 core tests, 101 MCP tests,
  280 client/MCP tests, 96 benchmark tests with 36 live WAMP workloads,
  isolated consumer and globally activated CLI smokes, remote-auth isolation,
  and the Dart2Wasm Chrome transport test.
- 2026-08-09: The implementation is ready to commit and push. Exact-head
  GitHub deployment-chain evidence and the strict audit remain pending.
