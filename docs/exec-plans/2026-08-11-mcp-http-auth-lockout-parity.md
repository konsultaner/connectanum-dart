# MCP HTTP-Auth Lockout Parity

Status: active

## Goal

Apply the realm's existing failed-authentication and lockout policy to the
router-provided HTTP-auth endpoint so downstream applications cannot bypass the
WAMP handshake protections when obtaining grants for protected MCP and direct
JSON routes.

## Context

WAMP handshakes consult `AuthSecurityTracker` before starting an authenticator,
record rejected challenges, clear failures after success, and emit auth audit
events. The router HTTP-auth bridge currently performs the same ticket,
WAMP-CRA, SCRAM, and remote-auth exchanges without any of those controls. A
caller can therefore route repeated failures through HTTP while the realm's
configured `max_failed_auth` and `lockout_ms` policy remains untouched.

The HTTP bridge must reject a locked identity before allocating session or
authenticator state, count real authentication failures and challenge expiry,
clear the identity after success, keep unrelated identities usable, and avoid
returning challenge state or secret material in the lockout response or router
telemetry.

## Plan

1. Preserve the preceding checkpoint's hosted evidence and run the pre-change
   fast regression matrix.
2. Add a fail-first router regression showing repeated HTTP-auth failures do
   not currently lock the submitted identity.
3. Add HTTP-auth failure/success accounting and pre-auth lockout rejection with
   bounded retry metadata and secret-safe telemetry.
4. Extend the neutral generated-consumer smoke to prove one locked identity
   cannot start another challenge while another identity can still obtain and
   use a grant through protected MCP, direct JSON, pub/sub, refresh/revoke, and
   Streamable HTTP flows.
5. Run focused formatting, analysis, runtime tests, and consumer checks,
   followed by post-change `bin/test-fast` and full `bin/verify`.
6. Write durable Serena memory, publish the implementation checkpoint, and
   audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, active-state, both roadmap,
  and branch-head preflights completed. The only startup changes are the
  preceding checkpoint's expected hosted-evidence notes.
- 2026-08-11: Symbol-aware inspection confirmed that WAMP authentication uses
  `AuthSecurityTracker` and `AuthAuditLogger`, while the router HTTP-auth bridge
  currently bypasses both for challenge failures, expiry, and success.
- 2026-08-11: The fail-first router regression reproduced two bypasses: repeated
  invalid HTTP-auth credentials still admitted a new challenge with HTTP 401,
  and challenge state issued before another flow locked the identity could
  still complete with HTTP 200.
- 2026-08-11: Router HTTP-auth now rejects locked identities before allocating
  state, rechecks already-issued transactions, counts authenticator rejection
  and challenge expiry, clears prior failures on success, aborts rejected
  authenticators, emits auth audit events, and returns a state-free HTTP 429
  with bounded `Retry-After` metadata and secret-safe router telemetry.
- 2026-08-11: The focused eight-case auth-bridge matrix, WAMP authentication
  security regressions, router analysis, shell syntax, diff hygiene, and the
  neutral installed-consumer smoke pass. The smoke proves pending-challenge
  capacity plus failed-attempt lockout isolation and then uses an unrelated
  valid grant through protected MCP, direct JSON, pub/sub, refresh/revoke, and
  Streamable HTTP flows.
- 2026-08-11: Post-change `bin/test-fast` passes the complete fast regression
  matrix, including 360 core tests, 101 MCP tests, the 280-case MCP/client
  suite, all 96 benchmark cases and 36 live WAMP workloads, every neutral
  consumer/package smoke, and focused router/auth/session coverage.
- 2026-08-11: Full `bin/verify` passes with zero formatting changes, all 114
  native transport tests plus serializer integrations, 52 FFI tests, 360 core
  tests, 101 MCP tests, the complete 280-case MCP/client suite, all 96
  benchmark cases and 36 live WAMP workloads, all 422 router tests, remote-auth
  integration, 13 native follow-ups, every neutral consumer/CLI smoke, and
  Chrome Dart2Wasm WebSocket coverage. Publication and exact-head hosted
  evidence remain.
