# MCP Router Rate-Limit Session Isolation

Status: complete; implementation and local verification green

## Goal

Keep router-hosted MCP rate-limit responses compatible with Streamable HTTP
without echoing a caller-provided `MCP-Session-Id` before the router has
authenticated or resolved that session, while preserving the client's local
session state so an application can still perform explicit cleanup.

## Context

Route-level rate limiting runs before the full MCP handler. Its current MCP 429
response derives `MCP-Session-Id` directly from the request header, so a caller
can make the router reflect an arbitrary syntactically valid session id even
though endpoint and principal ownership have not been checked. Direct JSON
requests are already sessionless, but Streamable POST and GET requests can
cross that trust boundary.

The correction must keep MCP protocol and CORS headers on 429 responses, retain
the active session and replay cursor inside `McpStreamableHttpClient`, and keep
DELETE outside route limiting so a consumer application can clean up the real
session it already owns.

## Plan

1. Record the preceding checkpoint's hosted evidence and add a fail-first
   router regression for caller-claimed Streamable session ids on 429.
2. Make pre-dispatch MCP rate-limit responses sessionless while retaining
   protocol, CORS, and rate-limit headers.
3. Cover headerless 429 recovery in the Streamable client and the neutral
   consumer smoke, including explicit session deletion afterward.
4. Run focused formatting, analysis, regression, and consumer checks, then
   post-change `bin/test-fast` and full `bin/verify`.
5. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, active-state, and roadmap
  preflights completed. The working tree was clean and both maintained
  `master` heads were `bbe391a6` before the feature branch was created.
- 2026-08-10: The preceding `bbe391a6` checkpoint has exact-head green GitHub
  CI, package dry-run, router-image, and WAMP-profile benchmark evidence, and
  the strict deployment-chain audit passes.
- 2026-08-10: Pre-change `bin/test-fast` passes the complete fast regression
  chain, including live WAMP workloads and every neutral MCP consumer/CLI
  smoke.
- 2026-08-10: Code analysis found that the route-level 429 path runs before the
  MCP handler but derives its response session id directly from an untrusted
  request header. The existing test labels a fabricated id as owned and pins
  the unsafe reflection behavior.
- 2026-08-11: Pre-dispatch MCP 429 responses are now always sessionless while
  retaining protocol, CORS, and rate-limit headers. Focused router coverage
  proves caller-supplied POST and GET session ids are not reflected, including
  the real-session exhaustion case whose explicit DELETE cleanup still
  succeeds.
- 2026-08-11: The public client regression now exercises a headerless 429 and
  proves its already-owned session id and resume cursor remain available for
  explicit DELETE cleanup. The neutral generated consumer package proves the
  same response boundary and cleanup lifecycle against the real router.
- 2026-08-11: Focused formatting, both router regressions, the client lifecycle
  regression, and the isolated consumer package smoke pass. Post-change
  `bin/test-fast` passes the complete fast regression chain.
- 2026-08-11: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests plus serializer integrations, 52 Rust FFI tests, 360 Dart core
  tests, 101 MCP tests, the complete 280-case MCP/client suite, all 96
  benchmark tests including 36 live WAMP workloads, all 418 router tests,
  remote-auth integration, 13 native follow-ups, every neutral consumer and
  CLI smoke, and Chrome/Dart2Wasm coverage. Publication and exact-head hosted
  evidence remain.
