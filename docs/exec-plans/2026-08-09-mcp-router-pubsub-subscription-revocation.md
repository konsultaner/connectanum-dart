# MCP Router Pub/Sub Subscribe Authorization Revocation

Status: active; local verification is green and hosted evidence is pending

## Goal

Revoke established router-hosted MCP WAMP pub/sub handles when the route
principal loses subscribe authorization for their topic, without disturbing
handles whose topics remain authorized or reviving revoked handles when access
is restored.

## Context

Router catalog refreshes rebind one reusable `McpWampPubSubState` so harmless
tool and topic catalog changes preserve direct JSON and compatibility-era
Streamable HTTP handles. The refreshed API removes topics that are no longer
subscribe-authorized, but the retained state does not currently reconcile its
established logical handles. Those handles may therefore keep the underlying
WAMP subscription and continue receiving events after authorization is lost.

## Plan

1. Add a native-router fail-first regression that establishes direct JSON and
   Streamable HTTP handles on one physical WAMP subscription, revokes topic
   subscribe access, refreshes the catalog, and proves the subscriber and old
   handles incorrectly survive.
2. Add a narrow reusable-state reconciliation boundary that releases only
   subscriptions for no-longer-subscribable topics, preserves explicit
   unsubscribe retry semantics, and lets the router use its non-authorizing
   cleanup delegate for security revocation.
3. Reconcile generic pub/sub handles during every successful router catalog
   refresh using the same authorized topic snapshot, then prove unrelated
   handles survive, revoked events are not delivered, restored permission does
   not revive old handles, and explicit resubscription succeeds.
4. Run focused MCP/router tests, post-change `bin/test-fast`, and full
   `bin/verify`; publish both maintained remotes and audit exact-head hosted
   evidence.

## Progress

- 2026-08-09: Serena preflight and semantic tracing confirmed that catalog
  refresh rebinds the retained pub/sub bridge but does not reconcile active
  handles against the refreshed topic permissions.
- 2026-08-09: The required baseline `bin/test-fast` started from implementation
  commit `6f6d61a9` before edits and completed green.
- 2026-08-09: The fail-first native-router regression reproduced one broker
  subscriber remaining after both direct JSON and Streamable HTTP handles lost
  topic subscribe permission while an unrelated authorized handle remained
  active.
- 2026-08-09: `McpWampPubSubState` now reconciles retained handles against a
  subscribable-topic snapshot, supports mandatory cleanup outside ordinary
  unsubscribe authorization, and restores a handle when release fails so the
  next refresh can retry safely.
- 2026-08-09: Each router endpoint reconciles generic pub/sub ownership during
  every successful catalog refresh. The regression proves affected direct and
  Streamable handles disappear, the shared broker count reaches zero, an
  unrelated topic keeps delivering, restored permission does not revive old
  handles, and an explicit replacement subscription succeeds.
- 2026-08-09: MCP/router analysis, the complete WAMP API test file, and four
  focused native-router catalog/revocation/retry regressions pass.
- 2026-08-09: Post-change `bin/test-fast` passes all 360 core, 99 MCP, and 280
  MCP/client cases, all 96 benchmark tests including 36 live WAMP workloads,
  and the complete generated/global consumer plus Router CLI smoke matrix.
- 2026-08-09: Full `bin/verify` passes with all 397 Dart files already
  formatted; 114 Rust core and 52 Rust FFI tests plus focused metrics; 360 Dart
  core, 99 MCP, 280 MCP/client, 96 benchmark, and 409 Router tests; the 6-case
  remote-auth and 13-case native follow-ups; every neutral consumer smoke; and
  Chrome Dart2Wasm WebSocket coverage.
