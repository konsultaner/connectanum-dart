# MCP HTTP-Auth Pending Capacity

Status: complete locally; publication pending

## Goal

Enforce the existing per-realm `max_pending_auth` limit for router-hosted HTTP
authentication so unauthenticated challenge churn cannot grow pending state
without bound before a downstream application reaches a protected MCP or JSON
endpoint.

## Context

The router HTTP-auth bridge retains every multi-round challenge in
`_pendingHttpAuthTransactions` until the challenge completes or expires. Realm
settings already expose `max_pending_auth` with a bounded default, but the HTTP
bridge does not currently enforce it. An unauthenticated caller can therefore
create pending authenticator state repeatedly and consume memory before bearer
authorization protects the application endpoint.

Capacity must be isolated per realm, expired state must be reclaimable, a full
realm must fail closed with a bounded retry signal and secret-safe telemetry,
and the authenticator started for a rejected request must be aborted. Existing
successful ticket, WAMP-CRA, SCRAM, refresh, revoke, MCP, and direct JSON flows
must remain compatible.

## Plan

1. Preserve the preceding checkpoint's hosted evidence and run the pre-change
   fast regression matrix.
2. Add a fail-first router regression for active-capacity rejection and
   capacity recovery after the occupying challenge is completed.
3. Enforce positive `max_pending_auth` values per realm, abort rejected
   authenticators, and return HTTP 429 with bounded `Retry-After` and
   non-secret capacity telemetry.
4. Extend the neutral generated-consumer smoke to prove the public HTTP-auth
   endpoint rejects excess pending work while the original flow can complete
   and protected MCP remains usable.
5. Run focused formatting, analysis, runtime tests, and consumer checks,
   followed by post-change `bin/test-fast` and full `bin/verify`.
6. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes.
- 2026-08-11: Symbol-aware inspection confirmed that expired pending HTTP-auth
  transactions are cleaned at ingress, but new unauthenticated challenges do
  not enforce the realm's existing `max_pending_auth` setting.
- 2026-08-11: Pre-change `bin/test-fast` passes the complete fast regression
  chain, including all 96 benchmark cases, 36 live WAMP workloads, and every
  neutral MCP consumer and router CLI smoke.
- 2026-08-11: The fail-first router regression reproduced a second HTTP-auth
  start receiving another HTTP 401 challenge while the configured one-entry
  realm capacity was occupied, instead of failing closed with HTTP 429.
- 2026-08-11: Positive `max_pending_auth` values now bound active challenge
  state per realm at both initial and multi-round insertion points. Rejected
  authenticators are aborted, responses carry bounded `Retry-After` metadata
  without state, telemetry excludes credentials, and subsequent challenges use
  the configured realm auth timeout instead of a fixed duration.
- 2026-08-11: The neutral installed-consumer smoke configures a one-entry
  capacity, proves a second request receives 429 with no challenge state,
  completes the occupying ticket challenge, and uses its public grant through
  protected router-hosted MCP, direct JSON, pub/sub, refresh/revoke, and
  Streamable session flows.
- 2026-08-11: Focused router analysis, the complete six-case auth-bridge
  matrix, shell syntax, diff hygiene, the generated-consumer smoke, and
  post-change `bin/test-fast` all pass.
- 2026-08-11: `bin/verify` passes formatting, all 114 native transport tests,
  52 FFI tests, 360 core tests, 101 MCP tests, the complete 280-case MCP/client
  suite, all 96 benchmark tests and 36 live WAMP workloads, all 420 router
  tests, remote-auth integration, 13 native follow-ups, every neutral
  consumer/CLI smoke, and Chrome/Dart2Wasm coverage.
