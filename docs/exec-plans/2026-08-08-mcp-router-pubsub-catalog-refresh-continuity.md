# MCP Router Pub/Sub Catalog Refresh Continuity

Status: active; implementation and complete local verification green, hosted
verification pending

## Goal

Keep router-hosted MCP WAMP pub/sub handles usable while the endpoint refreshes
its dynamic WAMP procedure/topic catalog, so unrelated registration changes do
not orphan a downstream application's buffered events or cleanup handle.

## Scope

- In scope: reusable MCP WAMP pub/sub bridge state, refreshed API metadata,
  direct JSON and compatibility-era Streamable continuity, buffered-event
  delivery, explicit unsubscribe cleanup, focused MCP/router coverage, and
  normal local plus hosted verification.
- Out of scope: changing queue count/byte policy, changing authorization rules,
  adding persistent event storage, changing WAMP registration discovery, or
  making poll delivery transactional across HTTP write failures.

## Preconditions

- Local head and both maintained `master` branches start at `7717b912`.
- The preceding modern request-scoped SSE event-bound checkpoint passed local
  verification, all exact-head hosted workflows, and the comprehensive strict
  deployment-chain audit.
- Its final hosted-evidence bookkeeping remains intentionally uncommitted for
  bundling with this implementation commit.
- Complete pre-change `bin/test-fast` passed on 2026-08-08.

## Plan

1. Add a fail-first native-router regression that subscribes through direct
   JSON, changes the live WAMP procedure catalog, then polls and unsubscribes
   with the original handle.
2. Introduce an explicitly reusable MCP WAMP pub/sub state object whose bridge
   retains handles and buffered events while rebinding to the latest API
   catalog and invokers.
3. Give each router MCP endpoint one reusable state object and pass it through
   every tool refresh, preserving endpoint/principal ownership boundaries.
4. Prove refreshed metadata includes the new procedure while pre-refresh
   direct JSON and Streamable handles still receive events and clean up.
5. Run focused MCP/router tests, analysis, `bin/test-fast`, and `bin/verify`;
   publish the implementation and collect exact-head hosted evidence.

## Verification

- focused `packages/connectanum_mcp/test/wamp_api_test.dart` coverage
- focused `router_integration_native_test.dart` regression
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-08: Source audit found that `_RouterMcpEndpoint._refreshTools()`
  constructs a fresh `McpWampApi` and private pub/sub bridge for every request.
  When a dynamic registration changes the serialized tool signature, the
  server installs handlers from that new bridge, whose handle map is empty.
  Existing WAMP subscriptions remain live in the router endpoint but become
  unreachable to poll or unsubscribe until endpoint disposal.
- 2026-08-08: Complete pre-change `bin/test-fast` passed before adding the
  regression or changing behavior. It covered 360 Dart core tests, all 96 MCP
  tests, the complete 280-case MCP/client suite, all 96 benchmark cases
  including 36 live WAMP workloads, every generated and globally activated
  consumer smoke, the Router CLI lifecycle matrix, and focused native/router
  follow-ups.
- 2026-08-08: The fail-first native-router regression created one direct JSON
  and one compatibility Streamable subscription, registered a new WAMP
  procedure, and refreshed both endpoint catalogs. The first direct poll then
  failed with `Unknown WAMP subscription handle: wamp-sub-1`, reproducing the
  handler-state loss while the native subscriptions remained live.
- 2026-08-08: `McpWampPubSubState` now owns the reusable private bridge and
  rebinds its API snapshot, invokers, and queue-byte policy on successive
  `McpWampApi.toTools` or `toSessionTools` calls. Each router MCP endpoint owns
  exactly one such state. Focused MCP coverage proves refreshed topic metadata,
  buffered event delivery, and unsubscribe after rebinding; the native-router
  regression proves the same continuity for direct JSON and Streamable handles
  across a live procedure registration. MCP/router analysis passes.
- 2026-08-08: Post-change `bin/test-fast` passes with 360 Dart core tests, all
  97 MCP tests, the complete 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, every generated and globally activated
  consumer smoke, the Router CLI lifecycle matrix, and the focused
  native/router follow-ups.
- 2026-08-08: Final exact-code `bin/verify` passes with zero formatting
  changes, 114 Rust core tests plus serializer integrations, 52 Rust FFI tests
  plus the focused metrics check, 360 Dart core tests, all 97 MCP tests, the
  complete 280-case MCP/client suite, all 96 benchmark tests including 36 live
  WAMP workloads, all 396 router tests, the 6-case remote-auth process, the
  13-case native follow-up, every generated and globally activated consumer
  smoke, and Chrome/Dart2Wasm.

## Handoff

- Publish the implementation and collect exact-head hosted deployment
  evidence.
