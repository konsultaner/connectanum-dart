# Exec Plan: release evidence refresh

Status: completed
Owner: Codex
Created: 2026-05-01
Last updated: 2026-05-01

## Goal

Keep public deployment/package evidence and autonomous continuation state aligned
with the current clean GitHub branch head.

## Scope

- In scope:
  - Refresh `docs/project_state.md` with current branch-head CI, package
    dry-run, native dry-run, and deployment audit evidence.
  - Refresh public deployment-chain and Dart package readiness docs with the
    latest relevant run IDs.
  - Fix verification-exposed CI flake in the native WAMP worker lifecycle test.
- Out of scope:
  - Changing release behavior, publishing artifacts, branch protection, GHCR
    package visibility, or pub.dev package settings.

## Files Expected To Change

- `docs/project_state.md`
- `docs/github_deployment_chain.md`
- `docs/dart_package_publishing.md`
- `docs/exec-plans/2026-05-01-release-evidence-refresh.md`
- `packages/connectanum_bench/test/wamp_transport_integration_test.dart`

## Preconditions

- Initial local branch head was `7cae4ef`.
- GitHub `CI` run `25192999135` passed for `7cae4ef`.
- `Dart Package Publish Dry Run` run `25192039083` and `Native Artifacts`
  dry-run `25192553399` were the starting evidence because only docs changed
  after `4267e7a`.

## Plan

1. Re-check the live GitHub deployment-chain audit.
2. Update the state and public docs to name the current clean evidence.
3. Fix any verification blocker exposed by the handoff run.
4. Run verification before handoff.

## Verification

- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 12 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
  - `CONNECTANUM_NATIVE_LIB="$PWD/native/transport/target/ffi-test/release/libct_ffi.dylib" dart test packages/connectanum_bench/test/wamp_transport_integration_test.dart --plain-name "native WAMP worker process exits cleanly after STOP following a native cancel workload" --chain-stack-traces` repeated 12 times locally

## Decision Log

- 2026-05-01: Treated this as a docs-only release-readiness refresh. No
  deployment mutation is needed or appropriate while the remaining blockers are
  operator-owned.
- 2026-05-01: The final `bin/verify` run exposed an intermittent local startup
  timeout in the direct native WAMP worker lifecycle test. The failure was at
  the initial `READY` wait, not the STOP/exit assertion, so the fix aligns that
  direct process test with the production helper's 20-second readiness budget
  and keeps stderr diagnostics for startup/exit timeouts.
- 2026-05-01: Local `bin/test-fast` and `bin/verify` passed after the native
  WAMP worker readiness timeout fix.
- 2026-05-01: Pushed implementation commit `425385d`; GitHub `CI` run
  `25195627202`, `Dart Package Publish Dry Run` run `25195627219`, and `WAMP
  Profile Benchmarks` run `25195627213` all passed. The clean deployment-chain
  audit passed for `425385d`, and the native dry-run remained relevant because
  no native-release-sensitive inputs changed.

## Handoff

- Completed after clean local verification and clean hosted GitHub evidence for
  implementation commit `425385d`. Remaining release/RC blockers are unchanged
  and operator-owned: branch protection required checks, router image
  default-branch/GHCR visibility, RC tag/prerelease selection, and Dart package
  release ownership/order.
