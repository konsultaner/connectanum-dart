# MCP Streamable HTTP Operation Deadline

Status: implementation complete; local verification clean

## Goal

Bound ordinary public MCP HTTP exchanges across request opening, response
headers, and buffered response bodies while preserving shared transport reuse,
session/resume state, and the intentionally long-lived lifetime of established
request-scoped SSE subscriptions.

## Context

The public Streamable HTTP client now bounds buffered response bytes and makes
terminal close cancel tracked requests and bodies. OAuth discovery, token, and
registration helpers plus router HTTP-auth operations also enforce explicit
deadlines. Ordinary MCP POST, GET, DELETE, and `subscriptions/listen` setup,
however, can still wait indefinitely when request opening, response headers,
response bodies, or the listener acknowledgment stalls.

This checkpoint adds one conservative per-exchange deadline. A timeout must
abort only the affected request, reject immediately even when an injected
`HttpClient` has not returned the request object yet, preserve active MCP
session/resume state, and leave caller-owned transports reusable. For
`subscriptions/listen`, the timer covers request opening through the required
acknowledgment and stops once the subscription is established; later SSE
notifications remain lifetime-incremental.

## Plan

1. Preserve the green fast-suite baseline and add fail-first local-server
   regressions for delayed request opening, stalled headers and bodies, GET,
   DELETE, and listener setup.
2. Add a validated public request-timeout setting with a conservative default
   and forward it through every public client constructor.
3. Track each ordinary HTTP exchange under one timer, abort active or late-
   opened requests and buffered bodies on timeout, and integrate the same
   lifecycle with terminal client close.
4. Prove same-client shared-transport recovery, session/resume preservation,
   listener acknowledgment bounds, and post-ack long-lived SSE behavior.
5. Run focused analysis/tests, public package-boundary smokes,
   `bin/test-fast`, and `bin/verify`; then bundle the implementation with
   milestone records and audit exact-head hosted evidence after pushing both
   maintained branches.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06 with 360 core tests, all 95
  MCP tests, the complete 271-case MCP/client suite, all 96 benchmark/live-
  router tests, every neutral generated and globally activated consumer/CLI
  smoke, and the focused native/router follow-ups.
- The focused fail-first deadline suite does not compile because
  `McpStreamableHttpClient` has no public `requestTimeout` option, reproducing
  the missing operation boundary before implementation.
- Focused analysis passed for `connectanum_client` and `connectanum_mcp`.
- The six-case deadline suite passes for invalid settings, delayed request
  opening, stalled response headers and bodies, GET and DELETE, listener
  acknowledgment, same-client transport recovery, state preservation, and an
  established SSE stream that remains open after its setup deadline expires.
- All 192 focused Streamable HTTP and public IO-boundary cases pass. The
  complete MCP/client suite passes all 277 cases, and the complete MCP package
  suite passes all 95 cases.
- Post-change `bin/test-fast` passed on 2026-08-06 with 360 core tests, all 95
  MCP tests, the complete 277-case MCP/client suite, all 96 benchmark/live-
  router tests, every neutral generated and globally activated consumer/CLI
  smoke, and the focused native/router follow-ups.
- Final exact-code `bin/verify` passed with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  95 MCP, 277 MCP/client, 96 benchmark/live-router, and 387 router tests; all
  13 focused native-forwarding regressions; every neutral consumer package and
  CLI smoke; and Chrome Dart2Wasm WebSocket coverage.

## Outcome

Ordinary public Streamable HTTP POST, GET, and DELETE exchanges plus
`subscriptions/listen` setup now share a validated 30-second default total
deadline. Every public constructor forwards the setting. Timeout rejects with
`TimeoutException`, aborts only the affected active or late-opened request and
buffered response body, preserves MCP session and resume state, and leaves a
caller-owned shared transport reusable. Listener setup remains bounded through
its acknowledgment while established SSE subscriptions remain long lived.
Commit, push, and exact-head hosted deployment evidence are pending.
