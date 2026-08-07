# MCP Router Streamable Notification Coalescing

Status: active; implementation and local verification complete, exact-head
hosted verification pending

## Goal

Bound compatibility-era router-hosted MCP notification backlog growth by
retaining at most one pending or in-flight copy of an identical logical SSE
notification while preserving distinct updates, resumable delivery, and the
existing response-byte ceiling.

## Scope

- In scope: exact notification-key coalescing across queued and selected poll
  messages, tool-list change storms, distinct resource-update preservation,
  successful commit, send-failure restoration, individually oversized-event
  cleanup, multi-poll batching, session/auth isolation, and local plus
  exact-head hosted verification.
- Out of scope: a new route option, changing the 100-event replay-history
  window, collapsing distinct resource URIs, changing modern request-scoped
  listener behavior, or changing WAMP event queue policy.

## Preconditions

- Local and both maintained `master` branches start at `86072d20`.
- The preceding Streamable poll response-bound checkpoint passed local
  verification, all exact-head hosted workflows, and the comprehensive strict
  deployment audit.
- The preceding checkpoint's hosted-evidence bookkeeping is intentionally
  uncommitted and will accompany this implementation.

## Plan

1. Run the pre-change fast gate and add a fail-first native-router regression
   proving repeated tool-catalog mutations retain redundant compatibility
   notifications while polling is paused.
2. Track exact logical notification keys across the pending queue and messages
   selected by an in-flight poll, suppressing duplicates until successful
   delivery commits or an oversized event is discarded.
3. Preserve keys through send-failure restoration and remove them only when
   the selected notification commits or is deliberately discarded.
4. Keep the response-bound regression meaningful by queuing distinct
   resource-update notifications and proving they still span multiple bounded
   resumable polls without loss.
5. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- focused `router_integration_native_test.dart` regressions
- `dart analyze packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source audit found only two compatibility notification producers.
  Resource updates already coalesce per URI, but tool-list changes append an
  identical message for every catalog refresh. The aggregate WAMP subscription
  ceiling bounds the number of distinct resource owners, while identical
  tool-list messages have no corresponding cap.
- 2026-08-07: Coalescing must cover messages selected by a poll as well as those
  still in the queue. Otherwise a catalog change during response writing can
  append a duplicate, and repeated write failures can grow the restored queue.
  One notification remains semantically sufficient because consumers reread
  current catalog or resource state after receiving it.
- 2026-08-07: A fail-first native-router regression performed eight
  register/unregister catalog mutation cycles while polling was paused and
  observed 16 identical `notifications/tools/list_changed` events instead of
  one. The implementation now keys exact JSON notification messages across
  both the pending queue and the selected in-flight poll batch. Successful
  delivery and deliberate oversized-event discard release a key; send-failure
  restoration retains it so another identical message cannot accumulate.
- 2026-08-07: The response-bound regression now queues 48 distinct configured
  resource-update URIs. It proves exact coalescing does not collapse distinct
  logical updates and that the existing byte ceiling still drains them across
  bounded resumable Last-Event-ID polls without loss.
- 2026-08-07: Focused analysis and the two native-router regressions pass.
  Post-change `bin/test-fast` passes 360 core tests, all 95 MCP tests, the
  complete 280-case MCP/client suite, all 96 benchmark tests including 36 live
  WAMP workloads, every generated and globally activated consumer smoke, and
  the native/auth/session follow-ups. Full `bin/verify` passes formatting,
  113 Rust core tests, 52 Rust FFI tests plus the focused metrics check, 360
  Dart core tests, all 95 MCP tests, the complete 280-case MCP/client suite,
  all 96 benchmark tests including 36 live WAMP workloads, every generated and
  globally activated consumer smoke, the complete 391-case router suite, the
  6-case remote-auth process, the 13-case native follow-up, and
  Chrome/Dart2Wasm.

## Handoff

- Implementation and local verification are complete. Commit, dual-remote
  publication, exact-head hosted workflows, and the strict deployment-chain
  audit remain.
