# MCP HTTP-Auth Grant Capacity

Status: complete; local verification green; publication pending

## Goal

Bound router-issued HTTP authentication grant lineages per realm so a client
with valid credentials cannot grow retained access/refresh token state without
limit before a downstream application reaches its protected MCP, direct JSON,
pub/sub, or Streamable HTTP endpoint.

## Context

The router HTTP-auth bridge already bounds pending challenges, failed-identity
records, and compatibility-era MCP sessions. Successful authentication still
inserts access tokens and optional refresh-token lineages into binding-owned
maps with no cardinality limit; expiry and revocation reclaim entries, but
repeated successful authentication can grow both maps for their configured
TTLs.

The bridge needs a backwards-compatible per-realm grant-lineage capacity,
expired-state reclamation before admission, bounded retry metadata, and
state-free rejection before new challenge/authenticator state is allocated.
Refresh of an existing lineage must remain usable while the realm is full,
challenge completion must recheck capacity, and revocation or expiry must
release admission without leaking auth IDs, state, or token values through
router telemetry.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run the
   pre-change fast regression matrix from a dedicated feature branch.
2. Add fail-first configuration and router HTTP-auth regressions for active
   grant rejection, challenge-completion races, refresh-at-capacity, and
   revocation/expiry recovery.
3. Add a positive `max_http_auth_grants` realm limit with a bounded default and
   count one refresh-backed or access-only token lineage per issued grant.
4. Reject new grant admission with a state-free HTTP 503 and bounded
   `Retry-After`, while preserving refresh and revocation for existing grants
   and secret-safe structured telemetry.
5. Extend the neutral installed-consumer smoke to prove grant-capacity
   rejection and recovery before using a router-issued grant through protected
   MCP, direct JSON, pub/sub, refresh/revoke, and Streamable HTTP flows.
6. Run focused formatting, analysis, config/runtime regressions, shell syntax,
   and the consumer smoke, followed by post-change `bin/test-fast` and full
   `bin/verify`.
7. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. The only startup changes are the preceding
  checkpoint's expected hosted-evidence notes, and local plus both maintained
  `master` heads match exact commit `d90b86e3` with a clean hosted deployment
  chain.
- 2026-08-11: Symbol-aware inspection confirmed that `_httpAuthTokens` and
  `_httpRefreshTokens` are reclaimed only by expiry/revocation/disposal and
  have no admission bound. Refresh rotation replaces a lineage, which can stay
  available at capacity while new successful authentications fail closed.
- 2026-08-11: The pre-change `bin/test-fast` baseline passed. Fail-first config
  tests then reproduced the missing limit surface, and runtime regressions
  reproduced both new-auth admission and challenge-completion races before the
  implementation changed.
- 2026-08-11: Positive realm `max_http_auth_grants` values now default to 4096
  and round-trip through the loader/codec. Admission counts each refresh-backed
  or access-only grant lineage once, rejects new authentication before session
  allocation and after asynchronous auth completion with a state-free 503,
  caps retry metadata at five minutes, and emits secret-safe capacity events.
  Refresh continues to replace the same lineage at capacity; revocation and
  access-only expiry release capacity.
- 2026-08-11: Focused router analysis, 97 config/runtime tests, shell syntax,
  and the isolated installed-router consumer smoke pass. The consumer proof
  now saturates the configured realm using neutral credentials, verifies that
  the rejection contains no auth state or tokens, revokes one lineage, recovers
  admission, and then continues through the existing protected MCP, direct
  JSON, pub/sub, refresh/revoke, and Streamable HTTP matrix.
- 2026-08-11: Post-change `bin/test-fast` and full `bin/verify` both pass.
  Verification includes unchanged formatting, all Rust transport/FFI tests,
  the 360-case core suite, 101 MCP package tests, the complete 280-case
  client/MCP suite, all 96 benchmark tests and 36 live WAMP workloads, all 429
  router tests, six remote-auth integration cases, 13 native follow-ups, every
  neutral consumer/CLI smoke, and Chrome/Dart2Wasm coverage. Publication and
  exact-head hosted evidence remain.
