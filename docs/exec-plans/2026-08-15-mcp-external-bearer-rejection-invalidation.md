# Exec Plan: MCP External Bearer Rejection Invalidation

Status: active
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Invalidate retained router-hosted MCP state when a configured external bearer
provider explicitly rejects a credential that previously authenticated. A later
reactivation must require a fresh Streamable HTTP session instead of reviving
the session created before rejection.

## Scope

- In scope:
  - close retained external bearer internal sessions on terminal token
    rejection;
  - order rejection cleanup with successful context replacement for the same
    opaque credential;
  - preserve retained sessions across transient introspection/provider
    availability failures;
  - prove inactive- and expired-token rejection, stale-session isolation, and
    fresh-session recovery at the public protected Streamable HTTP boundary.
- Out of scope:
  - changing provider validation or caching policy;
  - retrying unavailable introspection services;
  - changing client-side bearer refresh behavior.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `be63ea3e`; its exact-head
  deployment chain and comprehensive strict audit are green.
- The existing hosted-evidence notes are docs-only and will be bundled with
  this implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  live-WAMP, executable, and consumer-smoke matrix.

## Plan

1. Extend the controlled OAuth-introspection MCP runtime regression with an
   inactive-token rejection and reactivation attempt against the old session.
2. Serialize terminal rejection cleanup through the same per-credential turn
   chain used for successful authorization-context replacement.
3. Preserve sessions for transient provider failures and prove fresh-session
   recovery after explicit rejection.
4. Run focused checks and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused router runtime regression before and after implementation
- HTTP-auth provider and router runtime matrix
- `dart analyze packages/connectanum_router`
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-15: Explicit `invalid_token`, `expired_token`, and `inactive_token`
  results are terminal for retained state. Provider availability, timeout,
  upstream HTTP, or malformed-response failures remain request-local so a
  transient dependency failure does not revoke an otherwise valid session.
- 2026-08-15: The fail-first protected Streamable HTTP regression received
  HTTP 200 when it retried the pre-rejection session after the OAuth provider
  reactivated the bearer; the expected result was HTTP 404 for an unknown MCP
  session.
- 2026-08-15: Terminal cleanup and successful authorization-context
  replacement now share one per-credential turn chain. Session closure removes
  the retained cache entry and disposes the router-hosted MCP endpoint before
  the rejection response completes, while no raw bearer is retained.
- 2026-08-15: The focused regression now covers transient HTTP 503
  introspection failure, inactive-token rejection, expired-token rejection,
  stale-session isolation after reactivation, and fresh-session recovery.
  Router analysis and the complete 103-case HTTP-auth provider plus router
  runtime matrix pass.
- 2026-08-15: Full `bin/verify` exits zero with formatting unchanged; Rust core
  and FFI green; 366 core tests; 116 MCP tests; the complete 293-case
  MCP/client suite; 97 benchmark tests including all 37 live WAMP workloads;
  the 443-case router suite; six remote-auth tests; 13 native follow-ups; every
  maintained consumer smoke; Chrome; and Dart2Wasm green.

## Handoff

- Implementation and local verification are complete. Publication and
  exact-head hosted deployment evidence remain.
