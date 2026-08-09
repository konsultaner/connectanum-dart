# MCP Router Resource Visibility Revocation

Status: complete; local and exact-head hosted verification are green

## Goal

Revoke router-hosted MCP resource-update ownership when the route principal
loses visibility of a configured dynamic resource, without closing modern
resource-list listeners or compatibility Streamable HTTP sessions.

## Context

Catalog refresh now hides a dynamic resource when its backing read procedure
is no longer authorized. Existing compatibility resource subscriptions and
modern request-scoped resource listeners retain the URI, however, so their
shared physical WAMP update-topic subscription survives the catalog change and
can continue emitting update notifications for the hidden resource.

## Plan

1. Add a native-router fail-first regression that grants compatibility and
   modern resource subscriptions, revokes read visibility, and proves the
   shared WAMP subscriber remains active.
2. Reconcile logical resource-subscription ownership against each refreshed
   visible catalog, release the physical WAMP subscriber after its final
   visible owner is removed, and retain modern resource-list listeners.
3. Prove a hidden update is not delivered, visibility restoration does not
   silently restore the old update grant, and both protocol-era clients retain
   their expected session behavior.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; publish both maintained remotes and audit exact-head hosted
   evidence.

## Progress

- 2026-08-09: Pre-change `bin/test-fast` passes the complete fast regression,
  benchmark, packaging, consumer-smoke, and focused native-router matrix.
- 2026-08-09: The fail-first native-router regression reproduces one shared
  physical WAMP resource subscriber remaining after both compatibility and
  modern logical owners lose resource visibility.
- 2026-08-09: Catalog refresh now removes hidden resource URIs from
  compatibility ownership and every active modern listener filter before
  releasing unused shared WAMP subscriptions. Resource-list listeners and
  compatibility session identity survive, hidden updates are not delivered,
  catalog restoration does not revive the old grant, and an explicit fresh
  subscribe/unsubscribe lifecycle succeeds.
- 2026-08-09: Router analysis and the new plus four adjacent resource
  authorization regressions pass. Post-change `bin/test-fast` passes all 360
  core, 98 MCP, and 280 MCP/client cases, all 96 benchmark tests including 36
  live WAMP workloads, and the complete generated/global consumer plus Router
  CLI smoke matrix.
- 2026-08-09: Full `bin/verify` passes with zero formatting changes; all 114
  Rust core and 52 Rust FFI tests plus focused metrics; 360 Dart core, 98 MCP,
  280 MCP/client, 96 benchmark, and 407 Router tests; the 6-case remote-auth
  and 13-case native follow-ups; every neutral consumer smoke; and Chrome
  Dart2Wasm WebSocket coverage.
- 2026-08-09: Implementation commit `9361074d` is on both maintained
  `master` branches. Exact-head GitHub CI `31289997583`, Dart Package Publish
  Dry Run `31289997584`, WAMP Profile Benchmarks `31289997585`, and Router
  Image dry run `31290692710` all pass on their first attempts. Retained
  artifacts are Dart VM coverage `9031243471`, WAMP profile evidence
  `9031131142`, router image preview `9031262008`, and Docker build records
  `9031313007` and `9031312650`.
- 2026-08-09: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs plus every required package, relevant
  native release, loaded-image MCP smoke, WAMP, workflow-visibility,
  branch-protection, and public GHCR gate ready. Only the deliberately
  unapproved next RC tag remains outside this milestone.

## Handoff

- Implementation, both maintained pushes, local verification, exact-head
  hosted verification, and the strict deployment-chain audit are complete. Do
  not create or move an RC tag without explicit approval.
