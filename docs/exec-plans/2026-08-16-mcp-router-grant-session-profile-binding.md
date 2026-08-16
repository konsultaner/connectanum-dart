# Exec Plan: MCP Router Grant Session-Profile Binding

Status: complete
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Bind router HTTP-auth challenge state, access grants, and refresh grants to the
session profile that issued them. A credential started or issued for one
profile must not complete authentication, refresh, or authorize router-hosted
MCP through a different same-realm profile.

## Scope

- In scope:
  - reproduce cross-profile challenge completion, bearer use, and refresh at
    the public router HTTP boundary;
  - fail those operations before creating or reusing an internal WAMP session;
  - preserve same-profile challenge, protected MCP, and refresh behavior;
  - return secret-free errors without token fields or MCP session headers.
- Out of scope:
  - changing configured external JWT, OIDC, or OAuth provider semantics;
  - changing realm or authentication-method validation;
  - changing token revocation or refresh rotation policy.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `e18f5224`; its exact-head
  deployment chain and strict audit are green.
- The only pre-existing working-tree changes are the completed prior plan and
  project-state hosted-evidence bookkeeping reserved for this implementation
  commit.
- Pre-change `bin/test-fast` passed across the maintained repository,
  real-router, executable, and isolated consumer-smoke matrix.

## Plan

1. Add a fail-first router runtime regression with two same-realm session
   profiles and public auth/MCP routes.
2. Reject challenge continuation, refresh, and access-token use when the
   resolved route profile differs from the credential's issuing profile.
3. Prove same-profile authentication, MCP access, and refresh remain usable;
   run focused tests and `bin/verify`.
4. Publish the implementation to both maintained remotes and inspect the
   exact-head GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused fail-first and passing router runtime regression
- `dart analyze packages/connectanum_router`
- Complete router runtime and HTTP-auth provider test matrix
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-16: The public HTTP bridge contract says protected routes consume
  bearer grants from an auth route that references the same session profile.
  `_HttpAuthTokenRecord` and `_HttpRefreshTokenRecord` persist that profile,
  but challenge continuation, bearer validation, and refresh validation do not
  compare it with the current route. Same-realm profiles can therefore cross
  this intended credential boundary.
- 2026-08-16: The fail-first public regression started ticket authentication
  on profile A and completed its state through profile B. The alternate route
  returned HTTP 200 and issued credentials instead of rejecting the profile
  mismatch with HTTP 401.
- 2026-08-16: Challenge continuation now consumes and aborts mismatched state;
  refresh rejects mismatched records without rotating or invalidating them;
  and bearer validation rejects mismatches before internal-session lookup or
  creation. All paths use one secret-free `wrong_session_profile` contract.
- 2026-08-16: The focused public regression passes six runs, router analysis
  is clean, all 10 HTTP-auth provider tests pass, and the complete 98-case
  router runtime suite passes. Same-profile MCP access and refresh rotation
  remain green, while rejected alternate-profile access leaves router session
  metrics at baseline.
- 2026-08-16: Canonical `bin/verify` passes formatting, 117 Rust core tests,
  52 native FFI tests, 366 Dart core tests, 116 MCP tests, the complete
  293-case MCP/client suite, all 97 benchmark tests including 37 live WAMP
  workloads, all 448 router cases, six remote-auth tests, 13 native
  follow-ups, every maintained consumer and global-activation smoke, Chrome,
  and Dart2Wasm. No Dart pub retry was required.
- 2026-08-16: Commit `cc6eb677` is published to both maintained `master`
  branches. Exact-head CI `31919491504`, Dart Package Publish Dry Run
  `31919491519`, WAMP Profile Benchmarks `31919491524`, and Router Image dry
  run `31919511688` all pass with zero check annotations. Coverage artifact
  `9256127063`, WAMP artifact `9255983600`, Router Image preview artifact
  `9255913078`, and Docker build records `9255961308` and `9255961016` are
  available.
- 2026-08-16: The comprehensive strict deployment-chain audit exits zero with
  exact-head CI and clean logs, package publishing, reusable native-release
  evidence, loaded-image MCP smoke, multi-architecture image builds, WAMP
  artifacts, branch protection, workflow visibility, and public router-package
  visibility clean. The non-gating RC summary remains intentionally not ready
  because no approved numeric RC tag points at this implementation commit.

## Handoff

- Implementation, complete local verification, publication, exact-head hosted
  evidence, and the comprehensive strict deployment-chain audit are complete.
