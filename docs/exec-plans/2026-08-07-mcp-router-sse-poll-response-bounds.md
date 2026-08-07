# MCP Router Streamable Poll Response Bounds

Status: active; local verification clean, exact-head hosted verification pending

## Goal

Apply the router-hosted MCP route response ceiling to compatibility-era
Streamable HTTP GET/SSE polling so queued and replayed notifications cannot be
materialized into an oversized buffered response.

## Scope

- In scope: reuse `max_response_bytes` / `maxResponseBytes`, total raw SSE
  response-byte accounting, multi-poll batching, pending-message preservation,
  replay continuity, send-failure restoration, a bounded one-time failure for
  a single event that cannot fit, session/auth isolation, recovery, and local
  plus exact-head hosted verification.
- Out of scope: lifetime caps for MCP `2026-07-28` request-scoped listeners,
  changing SSE history depth, changing client-side per-event limits, WAMP event
  queue policy, or introducing a second poll-specific route option.

## Preconditions

- Both maintained `master` branches and the local feature branch start at
  `c344b5c4`.
- The preceding WAMP subscription-capacity checkpoint passed local
  verification, exact-head hosted workflows, and the comprehensive strict
  deployment audit.
- The preceding checkpoint's hosted-evidence bookkeeping is intentionally
  uncommitted and will accompany this implementation.

## Plan

1. Run the pre-change fast gate and add a fail-first native-router regression
   proving that one compatibility GET can exceed the configured response
   ceiling.
2. Make poll assembly account for complete raw SSE event frames and emit only
   the replay and queued-event prefix that fits the existing route ceiling.
3. Preserve unselected pending messages for later polls, keep replay cursors
   continuous, and retain the current restoration behavior when opening or
   writing the SSE response fails.
4. Reject and discard one individually oversized notification with a bounded
   HTTP error so subsequent poll and session operations recover normally.
5. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- focused `router_integration_native_test.dart` regression
- `dart analyze packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source audit found that ordinary router-hosted MCP operation
  responses enforce the route's raw UTF-8 response ceiling, but compatibility
  GET polling drains every pending notification and replay event into one
  `_mcpSseEventsBytes` buffer without consulting that ceiling. The existing
  route option is the least surprising policy surface because GET polling is a
  finite buffered response, unlike a long-lived request-scoped listener.
- 2026-08-07: The fail-first native-router regression queued 48 real tool-list
  notifications and reproduced a 5,427-byte compatibility GET response against
  a 4,096-byte route ceiling.
- 2026-08-07: Poll assembly now accounts for each complete encoded SSE frame,
  returns only the replay and pending-message prefix that fits, preserves the
  remainder for resumable polls, and restores the selected pending prefix if
  response opening or writing fails. A single event that cannot fit is dropped
  with a bounded HTTP 500 so it cannot permanently poison the session.
- 2026-08-07: Focused router analysis and tests passed, including multi-poll
  recovery of all 48 queued notifications and recovery after an individually
  oversized resource-update event. Post-change `bin/test-fast` passed 360 core
  tests, 95 MCP tests, the 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, all consumer smokes, and native follow-ups.
- 2026-08-07: Full `bin/verify` passed formatting, analysis, 113 Rust core
  tests, 52 Rust FFI tests plus the focused metrics check, 360 Dart core tests,
  all 95 MCP tests, the complete 280-case MCP/client suite, all 96 benchmark
  tests including 36 live WAMP workloads, every generated and globally
  activated consumer smoke, the complete 390-case router suite, the 6-case
  remote-auth process, the 13-case native follow-up, and Chrome/Dart2Wasm.

## Handoff

- Implementation and local verification are complete. Commit, dual-remote
  publication, exact-head hosted workflows, and the strict deployment-chain
  audit remain.
