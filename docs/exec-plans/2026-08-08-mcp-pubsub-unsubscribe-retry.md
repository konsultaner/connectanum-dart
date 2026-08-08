# MCP Pub/Sub Unsubscribe Retry

Status: complete; implementation, local verification, and hosted deployment
evidence are green

## Goal

Keep an MCP-created WAMP pub/sub handle usable when its unsubscribe delegate
fails, so consumer applications can continue polling and retry cleanup without
losing router-side capacity or endpoint-disposal ownership.

## Context

The shared `McpWampPubSubState` removes a logical handle before awaiting its
unsubscribe delegate. A transient WAMP cleanup failure therefore returns an
error while permanently forgetting a subscription that can still receive
events. Router-hosted MCP also removed the corresponding subscription from its
capacity and disposal set in a `finally` block, even when WAMP release failed.
Together those behaviors make cleanup failure non-recoverable and can leave a
live subscription outside normal endpoint accounting.

## Plan

1. Add a fail-first MCP WAMP API regression that injects one unsubscribe
   failure, delivers another event, polls it through the original handle, and
   retries cleanup successfully.
2. Restore the logical handle when its delegate fails and retain router-side
   subscription accounting until WAMP release succeeds.
3. Run focused MCP tests and analysis, then the post-change fast and full
   verification gates. Publish and watch hosted evidence if the completed
   implementation is pushed.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed all 97 MCP and 280 MCP/client
  cases, all 96 benchmark tests including 36 live WAMP workloads, and the full
  package/consumer plus Router CLI smoke matrix.
- 2026-08-08: The fail-first regression reproduced the defect: after a
  temporary unsubscribe failure, polling the original handle returned
  `Unknown WAMP subscription handle: wamp-sub-1` instead of the event delivered
  by the still-live subscription.
- 2026-08-08: Shared MCP pub/sub state now restores the removed handle before
  rethrowing an unsubscribe failure. Router-hosted MCP removes the underlying
  subscription from capacity and disposal tracking only after WAMP release
  succeeds. The focused retry regression passes.
- 2026-08-08: Focused MCP package tests plus MCP and Router analysis pass.
  Post-change `bin/test-fast` passes all 98 MCP and 280 MCP/client cases, all
  96 benchmark tests including 36 live WAMP workloads, and the complete
  package/consumer plus Router CLI smoke matrix.
- 2026-08-08: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests plus serializer integrations, 52 Rust FFI tests plus the focused
  metrics check, 360 Dart core, 98 MCP, 280 MCP/client, 96 benchmark, and 401
  Router tests; the 6-case remote-auth and 13-case native follow-ups; every
  generated and globally activated consumer smoke; and Chrome/Dart2Wasm.
- 2026-08-08: Commit `b0471a86` is pushed to both GitHub and GitLab `master`.
  Exact-head GitHub CI `31267655668`, Dart Package Publish Dry Run
  `31267655654`, WAMP Profile Benchmarks `31267655659`, and Router Image dry
  run `31267660648` all pass. The WAMP run passed unchanged on attempt 2 after
  the first attempt narrowly missed two unrelated AES pub/sub throughput
  minima; no gate or implementation was weakened. Retained passing evidence
  includes Dart VM coverage artifact `9024850388`, WAMP profile artifact
  `9024819441`, router image preview `9024639968`, and Docker build records
  `9024685091` and `9024685308`. The comprehensive strict deployment-chain
  audit exits successfully with clean exact-head CI jobs and logs, relevant
  native-release evidence, package, router-image runtime smoke, WAMP,
  workflow-visibility, branch-protection, and public GHCR gates all ready.
  Creating the next RC tag remains an explicit release-approval decision.

## Handoff

- Complete. Continue from `ROADMAP_NEXT.md` and `ROADMAP.md` with the next
  production-readiness slice; do not create or move an RC tag without explicit
  release approval.
