# MCP Router Unsubscribe Authorization Retry

Status: complete; implementation, local verification, and hosted deployment
evidence are green

## Goal

Authorize router-hosted MCP WAMP unsubscribe operations at the topic-aware
endpoint boundary while keeping authorization-provider failures bounded and
the original logical subscription usable for polling and cleanup retry.

## Context

Router-hosted MCP explicitly authorizes WAMP subscribe operations before using
its internal router session. The corresponding unsubscribe delegate sent only
the broker subscription identifier through that internal session, so it had no
topic-aware authorization check. A dynamic authorization provider therefore
could neither deny nor fail an MCP unsubscribe operation. Adding authorization
after logical-handle removal also depends on the shared retry behavior already
landed: a failed delegate must restore that handle and retain route capacity.

## Plan

1. Add a real native-router direct JSON regression that injects one unsubscribe
   authorization-provider failure and requires a bounded client error plus
   bounded operational event.
2. Authorize unsubscribe at the router-hosted endpoint using the subscription's
   topic, preserving the existing successful WAMP release and accounting path.
3. Prove that the failed handle remains pollable, route capacity stays reserved,
   same-handle retry succeeds, and a contender can subscribe after cleanup.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; push and watch hosted deployment evidence if green.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed all 98 MCP and 280 MCP/client
  cases, all 96 benchmark tests including 36 live WAMP workloads, and the
  complete package/consumer plus Router CLI smoke matrix.
- 2026-08-08: The fail-first native-router regression reproduced the missing
  authorization boundary: the provider was configured to fail the first
  matching unsubscribe request, but direct JSON unsubscribe succeeded because
  no topic-aware request reached it.
- 2026-08-08: Router-hosted MCP now calls the shared bounded authorization
  boundary before WAMP release. The focused native-router regression passes,
  proving redaction, sessionless direct JSON state, continued event polling,
  retained capacity, successful same-handle retry, and capacity recovery.
- 2026-08-08: Router package analysis and post-change `bin/test-fast` pass.
  The fast gate covers 360 core, 98 MCP, and 280 MCP/client cases; all 96
  benchmark tests including 36 live WAMP workloads; and the complete
  package/consumer plus Router CLI smoke matrix.
- 2026-08-08: Full `bin/verify` passes with all 397 Dart files already
  formatted; 114 Rust core tests plus serializer integrations; 52 Rust FFI
  tests plus the focused metrics check; 360 Dart core, 98 MCP, 280 MCP/client,
  96 benchmark, and 402 Router tests; the 6-case remote-auth and 13-case native
  follow-ups; every generated and globally activated consumer smoke; and
  Chrome/Dart2Wasm.
- 2026-08-08: Commit `c674fa10` is pushed to both GitHub and GitLab `master`.
  Exact-head GitHub CI `31271796386`, Dart Package Publish Dry Run
  `31271796404`, WAMP Profile Benchmarks `31271796426`, and Router Image dry
  run `31271806074` all pass on their first attempts. Retained artifacts are
  Dart VM coverage `9026036986`, WAMP profile evidence `9025894357`, router
  image preview `9025832714`, and Docker build records `9025886327` and
  `9025886031`. The comprehensive strict deployment-chain audit exits
  successfully with clean exact-head CI jobs and logs plus all required
  package, relevant native release, router-image MCP smoke, WAMP,
  workflow-visibility, branch-protection, and public GHCR gates ready. Only
  the deliberately unapproved next RC tag remains outside the milestone.

## Handoff

- Complete. Continue from `ROADMAP_NEXT.md` and `ROADMAP.md` with the next
  production-readiness slice; do not create or move an RC tag without explicit
  approval.
