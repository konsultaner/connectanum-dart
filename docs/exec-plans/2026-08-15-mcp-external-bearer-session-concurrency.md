# Exec Plan: MCP External Bearer Session Concurrency

Status: complete
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Make configured external JWT, OIDC, and OAuth bearer authorization-context
replacement linearizable for router-hosted MCP consumers. Concurrent validated
results for one credential must not reuse an internal session while it is
closing or leave a newly initialized Streamable HTTP session bound to stale
authorization state.

## Scope

- In scope:
  - serialize external bearer session-context replacement per opaque credential;
  - retain concurrency between unrelated bearer credentials;
  - prove the race through public protected MCP Streamable HTTP requests backed
    by a controlled OAuth introspection service;
  - preserve fail-closed stale MCP session behavior and fresh-session recovery.
- Out of scope:
  - changing external provider validation or caching policy;
  - changing client-side grant refresh behavior;
  - adding new MCP methods or protocol-era behavior.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `27198209` and its exact-head
  deployment chain is green.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  real-router, executable, and isolated consumer-smoke matrix.

## Plan

1. Extend the existing OAuth-introspection MCP runtime regression with two
   concurrent validated role results that expose stale-session reuse.
2. Serialize external session-context replacement per credential and clean up
   the turn state deterministically.
3. Run focused tests and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused router runtime regression before and after the implementation
- `dart analyze packages/connectanum_router`
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-15: Use a binding-owned turn chain keyed by the existing opaque
  provider/realm/profile/credential fingerprint. This orders context
  replacement for one bearer without retaining the raw token or serializing
  unrelated credentials.
- 2026-08-15: Exercise the race at the public protected Streamable HTTP boundary
  with controlled introspection completion order rather than asserting private
  session maps.
- 2026-08-15: The fail-first regression returned HTTP 404 from the concurrently
  initialized member session because it reused the internal session being
  closed by the preceding blocked result. The per-credential turn chain makes
  the same regression pass and preserves the existing stale-session 404.
- 2026-08-15: Router analysis is clean, the focused race passes five consecutive
  runs, and the HTTP-auth provider plus router runtime matrix passes all 103
  cases.
- 2026-08-15: Full `bin/verify` exits zero with formatting unchanged; Rust core
  and FFI green; 366 core tests; 116 MCP tests; the complete 293-case MCP/client
  suite; 97 benchmark tests including all 37 live WAMP workloads; the 443-case
  router suite; six remote-auth tests; 13 native follow-ups; every maintained
  consumer smoke; Chrome; and Dart2Wasm green.
- 2026-08-15: Commit `a99a3c7d` reached both maintained `master` branches, but
  exact-head CI `31879324869` and Dart Package Publish Dry Run `31879324968`
  failed because hosted Dart 3.13 enables `unawaited_return_in_try_block` for
  the Future returned from inside the turn's `try`. The correction explicitly
  awaits internal-session creation so the `finally` sequencing is also visible
  to the analyzer. Focused analysis and the race regression pass, and the full
  `bin/verify` matrix exits zero again on the corrective tree.
- 2026-08-15: Corrective commit `be63ea3e` is published to both maintained
  `master` branches. Exact-head CI `31881276618`, Dart Package Publish Dry Run
  `31881276631`, WAMP Profile Benchmarks `31881276655`, and Router Image dry
  run `31881282510` all pass with zero check annotations. Coverage artifact
  `9246281216`, WAMP artifact `9246160426`, Router Image preview artifact
  `9246083649`, and Docker build records `9246132096` and `9246131833` are
  available.
- 2026-08-15: Comprehensive
  `bin/audit-github-deployment-chain --branch master --run-limit 8 --strict
  --require-workflows-visible --require-router-package
  --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run
  --require-clean-native-release-dry-run --require-clean-router-image-dry-run
  --require-clean-wamp-profile-benchmarks --show-rc-readiness` exits zero with
  exact-head CI and logs, package publishing, reusable native-release evidence,
  loaded-image MCP smoke, multi-architecture image builds, WAMP artifacts,
  branch protection, workflows, and package visibility clean. The non-gating
  RC summary remains intentionally not ready because no approved numeric RC tag
  points at this implementation commit.

## Handoff

- Implementation, local verification, publication, exact-head hosted evidence,
  and the strict deployment-chain audit are complete.
