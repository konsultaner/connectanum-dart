# Exec Plan: MCP Client Auth Rotation Concurrency

## Status

Completed.

## Goal

Prevent delayed HTTP 401 responses issued for a replaced bearer credential
from clearing the active MCP Streamable HTTP session and resume cursor.

## Scope

- Snapshot the effective client-owned authorization state before each MCP HTTP
  request's first await.
- Renew authorization ownership only after a replacement grant validates.
- Require both session and authorization ownership before a 401 response can
  clear compatibility-session state.
- Keep 404 cleanup session-authoritative even when credentials rotated while
  the request was in flight.
- Preserve successful in-flight response handling, 403 step-up behavior,
  modern stateless isolation, and direct JSON isolation.

## Non-Goals

- Change router bearer-token validation or session-principal binding.
- Add automatic token refresh scheduling.
- Change caller-provided per-request authorization-header semantics.
- Serialize concurrent requests during credential replacement.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first public-client regressions for delayed old-credential 401 handling
  across POST, compatibility GET/SSE, and DELETE.
- A focused regression proving delayed 404 still clears the same session after
  credential replacement.
- Focused client analysis and Streamable HTTP client tests.
- Generated client-only consumer-package smoke if the public lifecycle
  contract changes its existing coverage surface.
- Full `bin/verify` before handoff.

## Progress

- 2026-08-05: Selected after the session lifecycle concurrency plan. Existing
  request cleanup snapshots the session generation only, so a delayed 401 for
  an old bearer grant can clear the same active session after
  `replaceAuthGrant(...)` or `replaceOAuthToken(...)` installs a validated
  replacement credential.
- 2026-08-05: Serena preflight and repository overlap checks passed. The only
  connectanum automation process is the current scheduled wrapper. The
  selected baseline was exact head `8112d2f`.
- 2026-08-05: Every MCP HTTP path now snapshots an opaque authorization
  generation and the effective client-owned bearer header before its first
  await. Validated grant replacement renews that generation. A 401 clears
  compatibility state only when both the request's session and authorization
  generations remain current; a 404 remains session-authoritative.
- 2026-08-05: Focused regressions cover the pre-await header snapshot, delayed
  POST/GET/DELETE 401 responses after `replaceAuthGrant(...)` and
  `replaceOAuthToken(...)`, rejected replacement ownership, and delayed 404
  cleanup. The generated client-only consumer smoke proves the delayed-401
  contract and replacement bearer from a neutral package boundary.
- 2026-08-05: Focused analysis, all 137 Streamable HTTP client tests, shell
  validation, the generated client-only consumer-package smoke, post-change
  `bin/test-fast`, and full `bin/verify` pass. Full verification includes 113
  Rust core tests, 52 Rust FFI tests, 360 Dart core tests, 94 MCP tests, the
  complete 217-case MCP/client suite, all 96 benchmark tests, all 384 router
  tests, native follow-ups, Chrome/Dart2Wasm coverage, and every isolated and
  globally activated consumer/CLI smoke.
- 2026-08-05: Commit `30a98a0` is on both maintained `master` branches.
  Exact-head GitHub CI `30995656889`, Dart Package Publish Dry Run
  `30995656655`, WAMP Profile Benchmarks `30995657433`, and Router Image dry
  run `30997101357` passed on their first attempts. CI uploaded coverage
  artifact `8926539516`, WAMP uploaded benchmark artifact `8926234529`, and
  Router Image uploaded preview artifact `8926635049` plus Docker build
  records `8926789532` and `8926788685`. The comprehensive strict
  deployment-chain audit passes with clean exact-head CI logs, loaded-image
  MCP runtime smoke, multi-architecture image build, and every required
  branch, workflow, package, native-release, publish-dry-run, benchmark, and
  registry gate clean. Release-candidate readiness remains intentionally
  non-gating until an approved numeric RC tag points at the release commit.
