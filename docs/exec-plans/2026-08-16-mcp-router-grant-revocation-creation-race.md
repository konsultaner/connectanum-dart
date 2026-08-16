# Exec Plan: MCP Router Grant Revocation During Session Creation

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Make router-issued access-token revocation fence an overlapping first protected
MCP request before that request can retain a newly created internal WAMP
session. A request that read the grant before revocation but has not completed
session creation must fail closed and release the new session.

## Scope

- In scope:
  - reproduce the race through public router HTTP-auth and MCP endpoints;
  - recheck terminal revocation on the exact router-issued grant record after
    awaited internal-session creation;
  - close a session created across revocation before returning an unauthorized
    response;
  - prove no authenticated internal session remains after the overlap.
- Out of scope:
  - changing configured external JWT, OIDC, or OAuth provider ordering;
  - changing refresh-token rotation semantics;
  - adding MCP methods or protocol-era behavior.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `be4a5a8e`; the exact-head
  deployment chain and strict audit are green.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  real-router, executable, and isolated consumer-smoke matrix.

## Plan

1. Add a fail-first runtime regression that overlaps a protected first MCP
   request with access-token revocation and inspects the public response plus
   router session metrics.
2. Mark the exact access-grant record when terminal revocation begins, recheck
   that marker after internal-session creation, and close the returned session
   before failing when revocation won the race.
3. Run focused tests and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused fail-first and passing router runtime regression
- `dart analyze packages/connectanum_router`
- Complete router runtime and HTTP-auth provider test matrix
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-16: Router-issued access validation reads the grant before awaiting
  internal-session creation. Revocation removes the grant and scans only
  completed session-cache entries, so it can miss a session still being
  created by that already-authorized request.
- 2026-08-16: The fail-first public regression deterministically queues access
  revocation as the protected MCP request enters routing. Revocation returned
  HTTP 200, but the overlapping `tools/list` request also returned HTTP 200
  because it had already read the grant before awaiting session creation.
- 2026-08-16: Mark the exact grant record only for terminal access cleanup and
  recheck that marker after session creation. A raw map-identity check would
  also reject the intentional non-terminal access-record replacement used by
  refresh-token rotation to preserve an established session.
- 2026-08-16: The first corrected run returned the expected HTTP 401 but router
  metrics still reported one session. `RouterSession.close()` removed binding
  caches without sending `SessionCloseCommand`, leaving the state-plane record
  behind. Binding removal now sends that command exactly once for every owned
  internal session.
- 2026-08-16: The focused regression passes five consecutive runs, router
  analysis is clean, all 10 HTTP-auth provider tests pass, and the complete
  97-case router runtime suite passes.
- 2026-08-16: Canonical `bin/verify` exits zero: formatting; 117 Rust core and
  serializer tests; 52 FFI tests; all maintained script suites; 366 core Dart
  tests; 116 MCP tests; the complete 293-case MCP/client suite; all 97
  benchmark tests including 37 live WAMP workloads; all 447 router cases; six
  remote-auth tests; 13 native follow-ups; every maintained consumer and
  global-activation smoke; Chrome; and Dart2Wasm are green. No Dart pub retry
  was required.

## Handoff

- Implementation and complete local verification are green. Publication to
  both maintained remotes and exact-head hosted evidence remain pending.
