# Exec Plan: MCP Router Auth-Route Policy Binding

Status: complete
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Bind router HTTP-auth challenge continuation and refresh-token use to the auth
route that issued them. Auth routes may share a session profile while carrying
different token lifetime and refresh-rotation policies; a consumer must not be
able to switch routes after starting authentication or receiving a grant.

## Scope

- In scope:
  - reproduce same-profile cross-route challenge completion and refresh at the
    public router HTTP boundary;
  - reject route mismatches before authenticator continuation, refresh-token
    mutation, access-token invalidation, or policy selection;
  - preserve same-route challenge completion and refresh rotation;
  - return secret-free errors without token fields or MCP session headers.
- Out of scope:
  - restricting bearer use across protected routes that intentionally share a
    session profile and realm;
  - changing configured external JWT, OIDC, or OAuth provider semantics;
  - changing profile, realm, grant-capacity, or revocation policy.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository; the live run lock
  belongs to the current scheduled wrapper.
- Both maintained `master` branches point at commit `cc6eb677`; its exact-head
  deployment chain and strict audit are green.
- The only pre-existing working-tree changes are the completed prior plan and
  project-state hosted-evidence bookkeeping reserved for this implementation
  commit.

## Plan

1. Run the pre-change fast verification gate.
2. Add a fail-first router runtime regression with two auth routes that share a
   session profile but configure different token and refresh policies.
3. Persist an in-memory issuing-route scope on pending challenge and refresh
   records, then reject cross-route continuation or refresh before mutation.
4. Prove same-route authentication and refresh remain usable; run focused
   tests and `bin/verify`.
5. Publish the implementation to both maintained remotes and inspect the
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

- 2026-08-16: Pending challenge and refresh records persist the issuing realm
  and session profile, but not the auth route. Challenge completion and refresh
  calculate access-token lifetime, refresh-token lifetime, and rotation from
  the current route. A consumer can therefore start on route A and continue or
  refresh on same-profile route B to select B's policy.
- 2026-08-16: The regression fails first with cross-route challenge completion
  returning HTTP 200. Pending challenge and refresh records now retain the
  issuing listener plus the effective auth-route settings. Route mismatches
  fail with secret-free `wrong_auth_route` responses before authenticator
  continuation or refresh-lineage mutation; rejected refresh leaves the
  original token usable on its issuing route.
- 2026-08-16: Pre-change `bin/test-fast` passes. The focused regression passes
  five consecutive runs, router analysis is clean, all 22 auth-bridge cases
  pass, and the complete 99-case router runtime suite passes.
- 2026-08-16: Canonical `bin/verify` passes formatting, 117 Rust core tests,
  52 native FFI tests, 366 Dart core tests, 116 MCP tests, the complete
  293-case MCP/client suite, all 97 benchmark tests including 37 live WAMP
  workloads, all 449 router cases, six remote-auth tests, 13 native
  follow-ups, every maintained consumer and global-activation smoke, Chrome,
  and Dart2Wasm.
- 2026-08-16: Commit `2e396db9` is published to both maintained `master`
  branches. Exact-head CI `31922573492`, Dart Package Publish Dry Run
  `31922573433`, WAMP Profile Benchmarks `31922573486`, and Router Image dry
  run `31922585553` all pass with zero check annotations. Coverage artifact
  `9256980631`, WAMP artifact `9256871984`, Router Image preview artifact
  `9256814016`, and Docker build records `9256869519` and `9256869276` are
  available.
- 2026-08-16: The comprehensive strict deployment-chain audit exits zero with
  exact-head CI and clean logs, package publishing, reusable native-release
  evidence, loaded-image MCP smoke, multi-architecture image builds, WAMP
  artifacts, branch protection, workflow visibility, and public router-package
  visibility clean. The non-gating RC summary remains intentionally not ready
  because no approved numeric RC tag points at this implementation commit.

## Handoff

- Implementation, canonical local verification, publication, exact-head hosted
  evidence, and the comprehensive strict deployment-chain audit are complete.
