# MCP Client Close Pending HTTP Requests

Status: complete

## Goal

Make `McpStreamableHttpClient.close()` terminate ordinary MCP HTTP requests
started by that client even when the underlying `HttpClient` is caller-owned,
without closing or otherwise invalidating the shared transport.

## Context

Client shutdown now invalidates compatibility session and resume state, but it
does not retain request ownership for standard/direct JSON `POST`,
compatibility `GET`, or session `DELETE` traffic. A request blocked before its
response headers can therefore survive local close on a caller-owned transport.
A request whose asynchronous URL-open operation finishes after close can also
escape shutdown before the existing response-state ownership guard takes
effect. Modern `subscriptions/listen` traffic already uses dedicated
request-scoped clients and remains an independent ownership boundary.

## Plan

1. Run the pre-change fast suite and add fail-first regressions for an active
   blocked request and a delayed request-open race on caller-owned transports.
2. Track ordinary MCP requests through response-header establishment, abort
   active requests during close, and reject request objects opened across the
   close boundary.
3. Preserve caller-owned transport reuse, compatibility state invalidation,
   and modern listener ownership behavior.
4. Extend the neutral client-only consumer-package smoke to require prompt
   request rejection on close, then run focused analysis/tests and
   `bin/verify`.
5. Update project state, commit and push the implementation with its evidence,
   then audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast`: passed on 2026-08-05.
- Fail-first regressions reproduced both shutdown gaps: a response-blocked
  request remained pending after close, while a request object opened after
  close completed successfully.
- Focused client analysis and all 154 Streamable HTTP client tests pass,
  including active initialize, direct JSON `POST`, compatibility `GET`,
  session `DELETE`, delayed request-open, and shared-transport reuse coverage.
- The neutral client-only consumer-package smoke passes from source and through
  the globally activated public package command, and treats failure to reject
  the response-blocked request within two seconds as a hard error.
- Full `bin/verify`: passed on 2026-08-05. Verification covered 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete
  234-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke.

## Outcome

Ordinary MCP endpoint requests now carry explicit client ownership from the
start of asynchronous URL-open through response-header establishment. Client
close renews that ownership generation, aborts all registered requests, and
rejects request objects that finish opening across the close boundary. The
underlying transport remains untouched when caller-owned, so a replacement MCP
client can immediately reuse it. Modern request-scoped listeners retain their
separate dedicated-client lifecycle.
