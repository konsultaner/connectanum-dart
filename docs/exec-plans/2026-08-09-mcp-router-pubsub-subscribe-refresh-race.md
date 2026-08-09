# MCP Router In-Flight Pub/Sub Subscribe Authorization Refresh

Status: complete

## Goal

Prevent a router-hosted MCP WAMP pub/sub subscribe that is still awaiting its
physical WAMP subscription from publishing a logical handle after a newer
catalog refresh has removed subscribe authorization for that topic.

## Context

Each successful router catalog refresh reconciles established generic pub/sub
handles against the route principal's currently subscribable topics. A logical
handle is not inserted into `McpWampPubSubState` until its asynchronous
subscribe delegate completes, so an in-flight subscribe is invisible to that
reconciliation. If permission is revoked during the wait, the old request can
currently complete afterward and expose a handle backed by a physical
subscription that the refreshed endpoint no longer authorizes.

## Plan

1. Add a fail-first public MCP regression that holds a subscribe delegate
   pending, reconciles the topic away, and proves the late completion currently
   returns a handle without mandatory cleanup.
2. Track pending generic subscriptions inside the reusable pub/sub state, mark
   them irrevocably revoked during reconciliation, discard buffered events,
   and use the host-provided release delegate when setup eventually completes.
3. Preserve retry safety when mandatory release fails, keep harmless catalog
   refreshes and established-handle behavior unchanged, and prove restored
   permission never revives the old pending request.
4. Run focused MCP/router tests, post-change `bin/test-fast`, and full
   `bin/verify`; bundle the prior evidence bookkeeping with the implementation,
   push both maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Serena preflight and semantic reference tracing confirmed that
  router refresh calls `reconcileSubscribedTopics` with the non-authorizing
  physical release delegate, but `_McpWampPubSubTools.subscribe` does not enter
  any tracked state until after its asynchronous delegate returns.
- 2026-08-09: Pre-change `bin/test-fast` passed. A fail-first public MCP
  regression then held the subscribe delegate pending, reconciled its topic
  away, and reproduced the late unauthorized logical handle without mandatory
  cleanup.
- 2026-08-09: Pending subscriptions now enter endpoint-owned state before the
  delegate is awaited. Reconciliation marks them irrevocably revoked, drains
  already-buffered events, rejects later events, uses the host release override
  once the physical subscription materializes, and retains failed cleanup for
  a later reconciliation retry without ever exposing the handle.
- 2026-08-09: Both pending-subscribe regressions, the complete MCP WAMP API
  test file, MCP analysis, and the adjacent native-router catalog continuity,
  authorization revocation, and cleanup-retry tests pass. The retry regression
  also proves restored permission cannot revive the old request and an explicit
  replacement subscription remains usable.
- 2026-08-09: Post-change `bin/test-fast` passed, including 360 core tests, 101
  MCP tests, all 96 benchmark tests with 36 live WAMP scenarios, isolated
  consumer packages, global activation, and the router CLI MCP matrix. The
  first `bin/verify` attempt reached the final router suite before one unrelated
  protected HTTP/3 MCP handshake timed out; the exact test then passed in
  isolation, and a complete `bin/verify` rerun passed with all 409 router tests,
  remote-auth, zero-copy, and browser coverage green.
- 2026-08-09: Implementation commit `2205cb5c` is pushed to both maintained
  `master` branches. Exact-head GitHub CI `31301538949`, Dart Package Publish
  Dry Run `31301538929`, WAMP Profile Benchmarks `31301573248`, and Router
  Image dry run `31301559030` all pass. Retained artifacts are Dart VM coverage
  `9034832546`, WAMP profile evidence `9034713468`, router image preview
  `9034642849`, and Docker build records `9034695039` and `9034694728`.
- 2026-08-09: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs plus every required package, relevant
  native release, loaded-image MCP smoke, multi-architecture image build,
  WAMP, workflow-visibility, branch-protection, and public GHCR gate ready.
  Release-candidate readiness remains intentionally non-gating because no
  approved numeric RC tag points at this implementation commit.
