# MCP Router Resource Subscribe Authorization Revocation

Status: implementation and local verification complete; hosted verification
is pending

## Goal

Revoke router-hosted MCP resource-update ownership when the route principal
loses subscribe authorization for the configured update topic, even when the
resource remains readable and visible in both protocol-era catalogs.

## Context

Catalog refresh reevaluates WAMP topic permissions, but resource subscription
cleanup currently runs only when the visible resource catalog changes. A
principal can therefore retain compatibility Streamable HTTP and modern
request-scoped update owners after `subscribe` permission is revoked while
`call` permission for the resource's read procedure remains allowed.

## Plan

1. Add a native-router fail-first regression that grants compatibility and
   modern resource subscriptions, revokes only update-topic subscribe access,
   and proves the shared physical subscriber remains active.
2. Reconcile established logical resource-update owners against current
   subscribe authorization during every successful catalog refresh, reusing
   the refresh authorization snapshot and releasing unused physical WAMP
   subscribers.
3. Prove the resource stays readable and listed, hidden updates are not
   delivered, existing session/list-change behavior survives, restored access
   does not silently revive an old grant, and an explicit new subscription
   succeeds.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; publish both maintained remotes and audit exact-head hosted
   evidence.

## Progress

- 2026-08-09: Pre-change `bin/test-fast` passes the complete fast regression,
  benchmark, packaging, consumer-smoke, and focused native-router matrix.
- 2026-08-09: The fail-first native-router regression reproduces one shared
  physical WAMP resource subscriber remaining after both compatibility and
  modern logical owners lose update-topic subscribe access while the resource
  remains visible and readable.
- 2026-08-09: Every successful catalog refresh now reconciles active resource
  owners against both visible resource URIs and current update-topic subscribe
  permission, reuses the refresh authorization snapshot, prunes compatibility
  and modern filters, and releases unused shared WAMP subscriptions. Restored
  permission still requires an explicit new subscription.
- 2026-08-09: Router analysis and all four focused router-hosted MCP resource
  ownership/authorization regressions pass.
- 2026-08-09: Post-change `bin/test-fast` passes all 360 core, 98 MCP, and
  280 MCP/client cases, all 96 benchmark tests including 36 live WAMP
  workloads, and the complete generated/global consumer plus Router CLI smoke
  matrix.
- 2026-08-09: Full `bin/verify` passes with all 397 Dart files already
  formatted; 114 Rust core and 52 Rust FFI tests plus focused metrics; 360 Dart
  core, 98 MCP, 280 MCP/client, 96 benchmark, and 408 Router tests; the 6-case
  remote-auth and 13-case native follow-ups; every neutral consumer smoke; and
  Chrome Dart2Wasm WebSocket coverage.

## Handoff

- Implementation and local verification are complete. Publish both maintained
  remotes and collect exact-head hosted deployment evidence next. Do not create
  or move an RC tag without explicit approval.
