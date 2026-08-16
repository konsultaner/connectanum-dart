# Exec Plan: MCP Router Auth-Realm Policy Binding

Status: complete
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Bind initial router HTTP-auth realm selection to the auth route's configured
realm policy before another realm's authenticator, lockout tracker, pending
challenge capacity, or grant capacity can be reached. Preserve normal grant,
refresh, and protected router-hosted MCP behavior for the configured realm.

## Problem

Initial auth requests currently resolve `realm` from body, query, or header
before the route action and session profile. A realm-pinned auth route can
therefore be used to start authentication against another configured realm.
Even when the resulting bearer is unusable on the intended protected route,
the request reaches the other realm's authentication and capacity state.

## Scope

- Add a public HTTP regression with two configured realms and a realm-pinned
  auth session profile.
- Reject a request realm that conflicts with route/profile policy before
  authenticator or auth-state allocation.
- Preserve matching and omitted realm selectors, grant issuance, refresh, and
  protected modern MCP access.
- Add neutral installed-consumer evidence if the focused boundary is suitable
  for the maintained router CLI smoke.

## Verification

- `bin/test-fast` before implementation.
- Focused fail-first and passing router-runtime regression.
- Router package analysis and relevant HTTP-auth/provider suites.
- `bin/verify` before handoff.
- Exact-head GitHub deployment-chain evidence after publication.

## Progress

- 2026-08-16: Serena preflight, overlap check, project-state/plan review, and
  both roadmap reviews completed. The existing hosted-evidence documentation
  changes remain the only inherited working-tree edits.
- 2026-08-16: Pre-change `bin/test-fast` passed all maintained fast-gate stages,
  including workspace analysis, core/MCP/client/router tests, live WAMP
  workloads, and isolated/global consumer package smokes.
- 2026-08-16: The focused regression failed first because a conflicting
  `realm2` selector returned a challenge instead of `wrong_realm`. Initial
  resolution now makes route/profile realm policy authoritative and rejects a
  conflicting request selector before realm lookup, authenticator selection,
  or auth-state allocation. Matching and omitted selectors retain the existing
  fallback behavior.
- 2026-08-16: The regression passed five consecutive focused runs. Router
  analysis, the complete 100-case router runtime suite, and all 10 HTTP-auth
  provider tests pass. The globally activated neutral consumer package smoke
  proves two foreign-realm attempts cannot consume that realm's single pending
  slot, while an omitted-selector ticket grant still reaches protected modern
  MCP and reports explicit `authRealmPolicyBinding` evidence.
- 2026-08-16: The regression was expanded across body, query, and header realm
  selectors and passed again. Canonical `bin/verify` passes formatting, 117
  Rust core tests, 52 native FFI tests, 366 Dart core tests, 116 MCP tests, the
  complete 293-case MCP/client suite, all 97 benchmark tests including 37 live
  WAMP workloads, all 450 router cases, six remote-auth tests, 13 native
  follow-ups, every maintained consumer and global-activation smoke, Chrome,
  and Dart2Wasm. The implementation is ready to publish; exact-head hosted
  workflows and the strict deployment-chain audit remain.
- 2026-08-16: Commit `536f8646` is published to both maintained `master`
  branches. Exact-head CI `31925871957`, Dart Package Publish Dry Run
  `31925871923`, WAMP Profile Benchmarks `31925871981`, and Router Image dry
  run `31926663549` all pass with zero check annotations. The first WAMP
  attempt completed all workloads but missed one throughput floor by 1.5%
  (`1.182` versus `1.200` Mbps); failed-job attempt 2 passed the canonical gate
  and uploaded artifact `9257984905`. Coverage artifact `9258025277`, Router
  Image preview artifact `9258039065`, and Docker build records `9258089621`
  and `9258089416` are available.
- 2026-08-16: The comprehensive strict deployment-chain audit exits zero with
  exact-head CI and clean logs, package publishing, reusable native-release
  evidence, loaded-image MCP smoke, multi-architecture image builds, WAMP
  artifacts, branch protection, workflow visibility, and public router-package
  visibility clean. The non-gating RC summary remains intentionally not ready
  because no approved numeric RC tag points at this implementation commit.

## Handoff

- Implementation, canonical local verification, publication, exact-head hosted
  evidence, and the comprehensive strict deployment-chain audit are complete.
