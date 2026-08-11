# MCP Auth Failure Record Capacity

Status: complete; local verification green; publication pending

## Goal

Bound the shared per-realm failed-authentication identity state used by WAMP
and router-provided HTTP authentication so attacker-controlled auth IDs cannot
grow router memory without limit before a downstream application reaches its
protected MCP or JSON endpoint.

## Context

`AuthSecurityTracker` currently retains every sub-lockout identity indefinitely
and has no cardinality limit. Router-hosted HTTP authentication now shares that
tracker with WAMP handshakes, so unauthenticated identity churn can grow the
per-realm map even when pending challenges and route-rate buckets are bounded.

The tracker needs a backwards-compatible per-realm capacity, expiry for
sub-threshold failure records, deterministic expired-record reclamation, and
fail-closed admission before authenticator or challenge state is allocated.
Existing tracked identities must retain their counters and lockouts, successful
authentication must release its identity record, and HTTP rejections must
remain state-free with bounded retry metadata and secret-safe telemetry.

## Plan

1. Preserve the preceding checkpoint's hosted evidence and run the pre-change
   fast regression matrix.
2. Add fail-first configuration, WAMP handshake, and router HTTP-auth
   regressions for active-capacity rejection, successful-record release, and
   expired-record reclamation.
3. Add a positive `max_failed_auth_records` realm limit with a bounded default,
   retain fixed-size identity digests only for the configured lockout window,
   and enforce fail-closed admission before authentication state allocation.
4. Extend the neutral installed-consumer smoke to prove failure-record capacity
   rejection and recovery before using the issued grant through protected MCP,
   direct JSON, pub/sub, refresh/revoke, and Streamable HTTP flows.
5. Run focused formatting, analysis, config/auth/runtime regressions, and the
   consumer smoke, followed by post-change `bin/test-fast` and full
   `bin/verify`.
6. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes.
- 2026-08-11: Symbol-aware inspection confirmed that sub-threshold auth failure
  records have no expiry or capacity and that the tracker is used by WAMP,
  router HTTP auth, and the standalone auth-server package.
- 2026-08-11: Pre-change `bin/test-fast` passes the complete fast regression
  chain, including all 96 benchmark cases, 36 live WAMP workloads, and every
  neutral MCP consumer and router CLI smoke.
- 2026-08-11: The fail-first config regression reproduced the missing
  `maxFailedAuthRecords` model/codec surface. After that surface was added, the
  WAMP regression reproduced a second identity receiving a challenge while a
  one-record realm was occupied, and the HTTP regression reproduced a 401 with
  new challenge state instead of a state-free 429.
- 2026-08-11: Positive realm `max_failed_auth_records` values now default to
  4096 and round-trip through the public settings API and loader/codec. The
  shared tracker stores fixed-size identity digests, retains sub-threshold and
  locked records only for `lockout_ms`, reclaims expired state, and fails
  closed for new identities while every slot is active. Successful auth still
  releases its identity record.
- 2026-08-11: WAMP rejects capacity before authenticator/session allocation;
  router HTTP auth returns a state-free 429 with bounded `Retry-After`, and its
  structured event omits auth ID, signature, state, and token. Focused router
  analysis, config validation/round-trip coverage, all 29 WAMP auth tests, all
  nine HTTP-auth runtime cases, shell syntax, diff hygiene, and the neutral
  installed-consumer smoke pass. The consumer proves capacity rejection and
  recovery before using the issued grant through protected MCP, direct JSON,
  pub/sub, refresh/revoke, and Streamable HTTP flows.
- 2026-08-11: Post-change `bin/test-fast` passes the complete fast regression
  chain, including all 96 benchmark cases, 36 live WAMP workloads, every
  router-hosted MCP mode, and both neutral generated-consumer smokes.
- 2026-08-11: `bin/verify` passes with zero formatting changes, all 114 native
  transport tests, 52 FFI tests, 360 core tests, 101 MCP tests, the complete
  280-case MCP/client suite, all 96 benchmark tests and 36 live WAMP workloads,
  all 425 router tests, six remote-auth integration cases, 13 native
  follow-ups, every neutral consumer/CLI smoke, and Chrome/Dart2Wasm coverage.
