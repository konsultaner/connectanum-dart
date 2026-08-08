# MCP Router Pub/Sub Byte Bounds

Status: active; implementation and full local verification green, publication
and hosted evidence pending

## Goal

Bound the serialized byte footprint of every router-hosted MCP WAMP event
queue while preserving observable drop behavior, direct JSON access, and
compatibility-era Streamable HTTP operation for consumer applications.

## Scope

- In scope: UTF-8 JSON byte accounting for buffered WAMP events, a validated
  router route ceiling with snake_case and camelCase spellings, oldest-event
  eviction, immediate oversized-event drops, typed client observability,
  direct JSON and Streamable coverage, public example configuration, and
  generated consumer smoke assertions.
- Out of scope: changing caller-selected event-count limits, changing route-wide
  subscription admission, adding persistent event storage, or making poll
  response delivery transactional across HTTP write failures.

## Preconditions

- Local head and both maintained `master` branches start at `435eb5a9`.
- The preceding failed-SSE-sequence rollback milestone passed local
  verification, exact-head hosted workflows, and the strict deployment-chain
  audit.
- Its hosted-evidence bookkeeping is intentionally carried into this
  implementation commit.
- Pre-change `bin/test-fast` passed on 2026-08-08.

## Plan

1. Add a fail-first MCP regression for multibyte UTF-8 event accounting,
   oldest-event eviction, oversized-event discard, and subsequent recovery.
2. Add optional public MCP buffer configuration and expose effective
   `queueByteLimit` plus post-poll `remainingBytes` through typed client
   results.
3. Add positive router route options
   `max_wamp_subscription_queue_bytes` and
   `maxWampSubscriptionQueueBytes`, with a bounded production default.
4. Extend native-router coverage through direct JSON byte overflow and
   recovery, and prove compatibility Streamable subscriptions receive the same
   effective policy.
5. Keep the runnable public example and generated consumer smoke aligned with
   the observable contract.
6. Run focused, fast, and full verification; commit and push both maintained
   branches; then audit exact-head hosted evidence.

## Verification

- `dart test packages/connectanum_mcp/test/wamp_api_test.dart`
- focused MCP client WAMP helper tests
- focused router option-validation and native pub/sub-capacity tests
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-08: Event count alone does not bound retained memory because one
  materialized WAMP event can contain an arbitrarily large JSON payload. The
  router production path therefore defaults each logical subscription to
  256 KiB of serialized event JSON while the reusable MCP API remains
  backward-compatible unless `maxBufferedEventBytes` is supplied.
- 2026-08-08: Byte accounting uses UTF-8 length rather than Dart string length,
  matching HTTP and JSON wire costs for multibyte content. When adding an event
  would cross either bound, oldest buffered events are evicted; an event larger
  than the byte ceiling is dropped immediately. All such drops increment the
  existing cumulative `dropped` counter.
- 2026-08-08: The subscribe and poll results expose `queueByteLimit` and
  `remainingBytes` so a downstream application can observe server policy and
  backlog without relying on private configuration.
- 2026-08-08: The fail-first MCP and router-option regressions failed before
  implementation. MCP, client parsing, route validation, and native direct
  JSON/Streamable focused regressions now pass.
- 2026-08-08: Post-change `bin/test-fast` and `bin/verify` pass. The full gate
  includes formatting and analysis, 114 Rust core tests, 52 Rust FFI tests plus
  the focused metrics check, 360 Dart core tests, all 96 MCP tests, the
  complete 280-case MCP/client suite, all 96 benchmark tests including 36 live
  WAMP workloads, every generated and globally activated consumer smoke, the
  complete 392-case router suite, the 6-case remote-auth process, the 13-case
  native follow-up, and Chrome/Dart2Wasm.

## Handoff

- Implementation and the complete local gate are green. Review and publish the
  implementation, then collect exact-head hosted deployment-chain evidence and
  run the comprehensive strict audit.
