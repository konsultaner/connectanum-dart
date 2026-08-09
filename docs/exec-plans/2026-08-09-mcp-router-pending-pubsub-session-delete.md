# MCP Router Pending Pub/Sub Session Delete Cleanup

Status: complete

## Goal

Ensure compatibility-era Streamable HTTP session deletion irrevocably revokes
an in-flight router-hosted WAMP pub/sub subscribe before its physical broker
subscription completes, so endpoint teardown cannot leak a subscriber or
return a usable handle from the deleted session.

## Context

Router-hosted MCP endpoint disposal releases established WAMP subscriptions
from its endpoint-owned set. A generic pub/sub subscribe is first tracked in
the reusable MCP WAMP state, then awaits the physical router subscription,
and only afterward enters the endpoint-owned set. DELETE can therefore finish
while the subscribe is pending, after which stale completion can escape the
disposal snapshot and retain broker ownership for an endpoint that no longer
exists.

## Plan

1. Add a deterministic fail-first native-router regression that blocks a
   compatibility-era pub/sub subscribe before physical completion, deletes the
   MCP session, and proves the stale request currently leaks broker ownership.
2. Reconcile the reusable pub/sub state to an empty subscribable catalog during
   endpoint disposal, using the non-authorizing physical release path so both
   established and pending handles are revoked without a second authorization
   decision.
3. Prove stale completion cannot expose a handle, the deleted session remains
   gone, the broker subscriber count returns to zero, and a fresh replacement
   session can subscribe and clean up normally.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   prior hosted-evidence bookkeeping with the implementation, push both
   maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Repository-workflow and Serena preflight completed. The latest
  exact-head local and hosted verification state is green, no unrelated
  same-repository Codex process or stale lock exists, and only the expected
  prior hosted-evidence notes were dirty at startup.
- 2026-08-09: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark/live-WAMP, generated consumer, globally activated,
  and Router CLI smoke matrix.
- 2026-08-09: The fail-first native-router regression blocks the subscribe's
  action authorization after its catalog refresh, deletes the Streamable
  session, then reproduces stale completion returning a usable handle. An
  earlier form of the regression also proved a request blocked before dispatch
  could resume after DELETE.
- 2026-08-09: Endpoint disposal now reconciles reusable pub/sub state to an
  empty subscribable catalog through the non-authorizing release path. The
  request path also rejects endpoints disposed during catalog refresh, during
  batch dispatch, or before response, returning sessionless HTTP 404 instead
  of executing or acknowledging stale work.
- 2026-08-09: The final regression covers broker-pending and pre-dispatch
  subscribe races, zero subscriber leakage, unchanged deleted-session state,
  distinct replacement sessions, and an explicit replacement
  subscribe/unsubscribe lifecycle. Router analysis, the complete MCP WAMP API
  test file, and four adjacent native-router pending-resource, idle-expiry,
  deletion-coexistence, and new teardown-race regressions pass.
- 2026-08-09: Post-change `bin/test-fast` passes the complete core, MCP,
  client/auth, benchmark and 36-case live-WAMP, generated consumer, globally
  activated, Router CLI, native runtime, and router worker follow-up matrix.
  Full `bin/verify` also passes formatting, 114 Rust core tests, 52 Rust FFI
  tests, 360 Dart core tests, 101 MCP tests, the complete 280-case MCP/client
  suite, 96 benchmark tests with all 36 live WAMP workloads, 411 router tests,
  isolated consumer and globally activated CLI smokes, remote-auth isolation,
  native follow-ups, and Chrome/Dart2Wasm. A local-model advisory review found
  no high-severity correctness or security issue.
- 2026-08-09: Implementation commit `ab0a651b` is pushed to both maintained
  `master` branches. Exact-head GitHub CI `31310624836`, Dart Package Publish
  Dry Run `31310624871`, WAMP Profile Benchmarks `31310624898`, and Router
  Image dry run `31311448656` all pass. Retained artifacts are Dart VM coverage
  `9037480263`, WAMP profile evidence `9037355014`, router image preview
  `9037495033`, and Docker build records `9037541099` and `9037541300`.
- 2026-08-09: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs plus every required package, relevant
  native release, loaded-image MCP smoke, multi-architecture image build,
  WAMP, workflow-visibility, branch-protection, and public GHCR gate ready.
  Release-candidate readiness remains intentionally non-gating because no
  approved numeric RC tag points at this implementation commit.
