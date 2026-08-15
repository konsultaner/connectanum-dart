# Exec Plan: MCP External Bearer Session Context

Status: complete; implementation, local verification, and hosted evidence green
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Prevent a router-hosted MCP request authenticated through a configured JWT,
OIDC, or OAuth introspection provider from reusing an internal session whose
authorization context no longer matches the provider's current result.

## Scope

- In scope:
  - Reproduce changed external bearer claims against a protected router-hosted
    MCP endpoint.
  - Bind reusable external HTTP-auth sessions to both an opaque credential
    fingerprint and the complete effective authorization identity.
  - Dispose the prior internal session and its MCP endpoint/subscription state
    when the provider returns a changed authorization context.
  - Keep raw bearer credentials out of internal session cache keys.
  - Preserve ordinary repeated requests when the provider result is unchanged.
- Out of scope:
  - Choosing or operating an external authorization server.
  - Changing token introspection, JWT/OIDC validation, or Protected Resource
    Metadata configuration.
  - Automatically refreshing consumer OAuth grants.

## Preconditions

- Commit `054fcd50` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The completed issuer-binding evidence remains as intended docs-only working-
  tree state and will be bundled with this implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  live-WAMP, executable, and consumer-smoke matrix.

## Plan

1. Add a fail-first OAuth-introspection-backed router MCP regression that
   changes one bearer token's effective authorization role.
2. Replace raw-token cache identity with bounded digests of the credential and
   effective authorization context, and rotate the owned internal session when
   that context changes.
3. Prove unchanged-context reuse plus changed-context session invalidation and
   fresh-session recovery.
4. Run focused checks and `bin/verify`, then update durable state.
5. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence for the affected router/package paths.

## Verification

- Focused protected router-hosted MCP runtime regression.
- Router analysis and relevant provider/session tests.
- `bin/verify`.

## Verification Evidence

- The fail-first OAuth-introspection MCP regression expected the previous
  Streamable session to become unknown after its bearer changed from the
  `member` role to `blocked`; before the fix the request incorrectly retained
  HTTP 200 access through the cached member session.
- Router analysis is clean, and the focused HTTP-auth provider plus router
  runtime matrix passes all 103 cases. The regression proves unchanged-context
  reuse, changed-context invalidation, authorization-filtered replacement, and
  recovery after the provider restores the original role.
- `bin/verify` exits zero with formatting unchanged; Rust core and FFI green;
  366 core tests; the complete MCP/client suite; 97 benchmark tests including
  all 37 live WAMP workloads; the 443-case router suite; six remote-auth tests;
  13 native follow-ups; every maintained consumer smoke; Chrome; and
  Dart2Wasm green.

## Decision Log

- 2026-08-15: Configured bearer providers already revalidate every HTTP
  request, but the resulting internal session is keyed by the raw token alone.
  The session owns the WAMP authorization identity and router-hosted MCP state,
  so a later provider result with changed claims can otherwise reuse stale
  privileges. Credential secrecy also requires an opaque fingerprint instead
  of retaining the bearer in the cache key.

## Handoff

- Configured external HTTP-auth sessions now use a SHA-256 credential
  fingerprint plus a canonical digest of auth ID, role, method, provider, and
  effective roles. Raw bearer credentials are no longer retained in their
  internal cache keys.
- A changed provider context closes the prior internal session before a
  replacement is reused. That cleanup disposes session-owned router-hosted MCP
  endpoints and subscriptions, so old MCP session IDs fail closed and the
  consumer must initialize a fresh session under the new authorization state.
- Commit `27198209` is published to both maintained `master` branches.
  Exact-head CI `31875859177`, Dart Package Publish Dry Run `31875859209`, and
  Router Image dry run `31876272534` pass on their first attempts. WAMP Profile
  Benchmarks `31875859173` passes on one bounded retry after the first attempt
  completed every workload but measured the unrelated
  `rawsocket_pubsub_aes_dart_64k` throughput at 1.005 Mbps against its 1.200
  Mbps floor; the retry measured 1.32 Mbps. Final workflow jobs have zero check
  annotations.
- CI retains coverage artifact `9244904560`; the successful WAMP attempt
  retains benchmark artifact `9244936403`; Router Image retains preview
  artifact `9244814425` and Docker build records `9244869552` and
  `9244869253`.
- The comprehensive strict deployment-chain audit exits zero with clean
  exact-head CI logs and all required package, retained native-release,
  loaded-image MCP, multi-architecture image, WAMP, workflow, registry, and
  protected-branch gates clean. No RC tag was selected.
