# MCP HTTP-Auth Refresh Concurrency

Status: complete; local verification green; publication pending

## Goal

Make router-issued HTTP refresh-token use linearizable so overlapping refresh
requests cannot mint multiple successor grant lineages or leave access tokens
outside their refresh lineage before a consumer application reaches protected
MCP, direct JSON, pub/sub, or Streamable HTTP endpoints.

## Context

The router validates a refresh-token record and then awaits linked access-token
and session cleanup before it consumes a rotating refresh token or replaces the
access token attached to a reusable refresh token. Two requests can therefore
read the same record before the first asynchronous cleanup completes. With
rotation enabled, both requests can issue distinct successor refresh lineages.
With rotation disabled, both can issue access tokens while the record retains
only the last token, allowing later refresh-token revocation to miss the other
access token.

The handler must claim the presented refresh token before its first asynchronous
success-path operation, preserve the configured reusable-token behavior for a
single winner, reject overlapping and stale uses through the existing
secret-safe `invalid_refresh_token` response, and keep the winning grant usable
and revocable.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run the
   pre-change fast regression matrix from a dedicated feature branch.
2. Add fail-first router regressions that overlap two uses of one refresh token
   with rotation both enabled and disabled.
3. Atomically claim the refresh record before linked access/session cleanup,
   issue exactly one successor, and restore a non-rotating token only for the
   winning request.
4. Prove the losing request has no token material, the winning access token is
   usable, stale/replayed use is rejected, and refresh-token revocation removes
   the complete winning lineage.
5. Extend the neutral installed-router consumer smoke with the same overlapping
   refresh and revocation boundary without private project assumptions.
6. Run focused formatting, analysis, router regressions, shell syntax, and the
   installed-consumer smoke, followed by post-change `bin/test-fast` and full
   `bin/verify`.
7. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes are the preceding
  checkpoint's expected hosted-evidence notes; local and both maintained
  `master` heads match exact commit `32e2f5dd` with a clean hosted deployment
  chain.
- 2026-08-11: Symbol-aware inspection confirmed that refresh validation reads
  the record before an awaited access/session cleanup and only consumes or
  rewrites the record afterward. No concurrent router refresh regression exists.
- 2026-08-11: Pre-change `bin/test-fast` passed, including 360 core tests, 101
  MCP package tests, the complete client/MCP matrix, all 96 benchmark tests and
  36 live WAMP workloads, neutral package/activation smokes, the router CLI
  consumer proof, and native/router worker follow-ups.
- 2026-08-11: The fail-first overlap regression returned two successful grants
  from one rotating refresh token. An intermediate claim revision fixed that
  replay but exposed a transient capacity hole: new authentication received a
  challenge while a full realm's only lineage was being refreshed.
- 2026-08-11: Refresh tokens now use a binding-owned in-flight claim while the
  original record remains counted. One request can replace the lineage; an
  overlapping request receives the existing secret-free 401, and an identity
  recheck after awaited access cleanup lets concurrent revocation prevent
  successor issuance. Reusable refresh tokens retain exactly one linked access
  token.
- 2026-08-11: Focused router analysis and all 13 auth-bridge runtime tests pass.
  Regressions cover rotating and reusable overlap, capacity preservation,
  concurrent revocation, winning access usability, and complete lineage
  revocation. Shell syntax and the isolated installed-router consumer smoke
  pass; the consumer reports `authRefreshConcurrency: true` before continuing
  through protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable
  HTTP paths.
- 2026-08-11: Post-change `bin/test-fast` passes the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, and native follow-up matrix.
  The installed router CLI consumer reports `authRefreshConcurrency: true`,
  and the 96-case benchmark suite includes all 36 live WAMP workloads.
- 2026-08-11: Full `bin/verify` passes with zero formatting changes, clean
  analysis, 114 Rust core tests, 52 Rust FFI tests, 360 Dart core tests, 101
  MCP package tests, the complete 280-case client/MCP suite, all 96 benchmark
  cases and 36 live WAMP workloads, all 430 router tests, six isolated
  remote-auth integrations, 13 native follow-ups, every neutral consumer and
  installed-command smoke, and Chrome/Dart2Wasm coverage.
