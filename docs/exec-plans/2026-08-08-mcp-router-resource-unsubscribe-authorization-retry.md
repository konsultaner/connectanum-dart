# MCP Router Resource Unsubscribe Authorization Retry

Status: complete; implementation, local verification, and hosted deployment
evidence are green

## Goal

Authorize compatibility-era router-hosted MCP resource unsubscribe operations
against the configured WAMP update topic while preserving the Streamable
session, resource ownership, and retry path when authorization or physical
release fails.

## Context

Router-hosted dynamic resources authorize their WAMP update topic while
subscribing, but `resources/unsubscribe` removed the logical resource URI and
ran internal physical cleanup without an unsubscribe authorization decision.
A dynamic provider therefore could neither deny nor fail this explicit client
operation. The cleanup helper also removed the shared subscription future
before awaiting release, so a later release failure could make the still-live
physical subscription unavailable to same-session retry.

## Plan

1. Add a real native-router Streamable HTTP regression that injects one
   unsubscribe authorization-provider failure for the configured update topic.
2. Authorize the explicit resource unsubscribe before logical ownership changes
   and restore logical/shared ownership if physical cleanup fails.
3. Prove bounded error redaction, stable Streamable session and cursor state,
   continued resource-update delivery, retained capacity, same-session retry,
   and capacity recovery.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; push both maintained remotes and watch the hosted deployment
   chain if green.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed all current fast regression,
  live WAMP workload, generated/global consumer, and Router CLI smoke layers.
- 2026-08-08: The fail-first native-router regression reproduced the missing
  authorization boundary: the provider was armed for the first matching
  unsubscribe request, but `resources/unsubscribe` completed successfully
  because no update-topic authorization request reached it.
- 2026-08-08: Explicit resource unsubscribe now authorizes the configured
  update topic before changing ownership. Failed physical cleanup restores both
  the Streamable logical URI and the removed shared subscription future, while
  internal owner cleanup remains non-authorizing.
- 2026-08-08: Router analysis is clean. The focused regression plus the
  adjacent direct-WAMP unsubscribe retry and cross-era session-delete/resource
  owner regressions pass, proving bounded provider-error redaction, stable
  session lineage and valid resume state, continued update delivery, capacity
  retention, same-session retry, and capacity recovery.
- 2026-08-08: Post-change `bin/test-fast` passes all 360 core, 98 MCP, and 280
  MCP/client cases; all 96 benchmark tests including 36 live WAMP workloads;
  and the complete generated/global consumer plus Router CLI smoke matrix.
- 2026-08-08: Full `bin/verify` passes with all 397 Dart files already
  formatted; 114 Rust core tests plus serializer integrations; 52 Rust FFI
  tests plus the focused metrics check; 360 Dart core, 98 MCP, 280 MCP/client,
  96 benchmark, and 403 Router tests; the 6-case remote-auth and 13-case native
  follow-ups; every generated and globally activated consumer smoke; and
  Chrome/Dart2Wasm.
- 2026-08-08: Commit `f808355f` is pushed to both maintained `master`
  branches. Exact-head GitHub CI `31275668744`, Dart Package Publish Dry Run
  `31275668900`, WAMP Profile Benchmarks `31275668728`, and Router Image dry
  run `31276435877` all pass on their first attempts. Retained artifacts are
  Dart VM coverage `9027121268`, WAMP profile evidence `9026998907`, router
  image preview `9027134340`, and Docker build records `9027184630` and
  `9027184340`. The comprehensive strict deployment-chain audit exits zero
  with clean exact-head CI jobs and logs plus every required package, relevant
  native release, router-image MCP smoke, WAMP, workflow-visibility,
  branch-protection, and public GHCR gate ready. Only the deliberately
  unapproved next RC tag remains outside the milestone.

## Handoff

- Complete. Continue from `ROADMAP_NEXT.md` and `ROADMAP.md` with the next
  production-readiness slice; do not create or move an RC tag without explicit
  approval.
