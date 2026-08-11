# MCP Router Rate-Limit Bucket Capacity

Status: complete locally; publication and hosted evidence pending

## Goal

Bound per-route HTTP rate-limit state under caller-controlled bearer, header,
or connection key churn while preserving router-hosted MCP Origin, auth,
session, CORS, direct JSON, Streamable HTTP, and DELETE-cleanup behavior.

## Context

The shipped route limiter currently stores one process-lifetime map entry for
every distinct bucket key it observes. Caller-controlled bearer and header
values can therefore grow router memory before MCP dispatch, and raw values are
retained in internal map keys. The limiter needs an explicit per-route bucket
capacity, expired-state reclamation, and secret-safe internal identifiers.

When a new bucket cannot be admitted, the endpoint should fail closed with the
same bounded HTTP 429 contract. For MCP routes that response must remain
sessionless and retain protocol, CORS, and rate metadata. Existing buckets must
keep their counters, invalid Origins must remain earlier than the limiter, and
Streamable DELETE must remain exempt so an active session can be cleaned up.

## Plan

1. Preserve the preceding checkpoint's hosted evidence and run the pre-change
   fast regression matrix.
2. Add fail-first config and router regressions for a small per-route bucket
   capacity, active-capacity rejection, and expired-bucket reclamation.
3. Store rate state per route identity, digest caller-controlled bucket values,
   and add a backwards-compatible `max_buckets` / `maxBuckets` setting with a
   bounded default.
4. Extend the neutral generated consumer smoke with direct JSON and
   compatibility-session claims that prove capacity 429 responses are
   sessionless and existing clients retain their own counters.
5. Run focused formatting, analysis, config/router regressions, and consumer
   checks, followed by post-change `bin/test-fast` and full `bin/verify`.
6. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. Only the preceding checkpoint's expected
  hosted-evidence notes were dirty at startup.
- 2026-08-11: Pre-change `bin/test-fast` passes the complete fast regression
  chain, including 36 live WAMP workloads and every neutral MCP consumer and
  router CLI smoke.
- 2026-08-11: The fail-first config regression reproduced the missing
  `maxBuckets` API, and the fail-first MCP runtime regression reproduced a
  third distinct caller bucket being admitted with HTTP 204 after the first
  two active buckets instead of failing closed with HTTP 429.
- 2026-08-11: Route actions now accept `max_buckets` / `maxBuckets` with a
  bounded default of 4096. Rate state is scoped by stable route and effective
  method-action identity, caller-controlled bearer/header values are digested,
  expired buckets are reclaimed only when needed, and new buckets fail closed
  while capacity is full.
- 2026-08-11: The secrecy assertion exposed a preceding boss-telemetry leak:
  `listener_http_request` events carried raw Authorization, cookie, API-key,
  MCP session, and resume headers. Request telemetry now redacts those values
  without changing the request delivered to the route handler.
- 2026-08-11: Focused config round-trip, router analysis, four-case rate-limit
  matrix, shell syntax, diff hygiene, and the neutral generated-consumer smoke
  pass. The consumer smoke proves a distinct bearer bucket receives a
  sessionless 429 while the original direct JSON caller retains its budget,
  initializes a Streamable session, and completes DELETE cleanup.
- 2026-08-11: Post-change `bin/test-fast` passes the complete fast regression
  chain, including all 96 benchmark cases, 36 live WAMP workloads, every
  router-hosted MCP mode, and both neutral generated-consumer smokes.
- 2026-08-11: `bin/verify` passes formatting, all 114 native transport tests,
  52 FFI tests, 360 core tests, 101 MCP tests, the complete 280-case MCP/client
  suite, all 96 benchmark tests and 36 live WAMP workloads, all 419 router
  tests, remote-auth integration, 13 native follow-ups, every neutral
  consumer/CLI smoke, and Chrome/Dart2Wasm coverage.
