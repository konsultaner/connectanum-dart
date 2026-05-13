# Exec Plan: RC branch protection baseline

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Make the release-candidate readiness audit distinguish candidate-branch CI
evidence from the default release branch protection baseline, so
`--branch add-router --show-rc-readiness` does not imply the active development
branch itself must be protected.

## Scope

- In scope:
  - Keep latest branch-run, CI, log, package, native-release, workflow, and
    router-image checks anchored to the audited candidate branch.
  - Report RC branch-protection readiness against the repository default
    branch because release policy and public docs place required status checks
    on `master`.
  - Refresh project state with the current clean branch-head CI evidence.
- Out of scope:
  - Mutating GitHub branch protection.
  - Promoting `router-image.yml` to the default branch.
  - Publishing GHCR images, GitHub releases, or Dart packages.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 4 --show-rc-readiness`
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 12 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
- `bin/verify`

## Decision Log

- 2026-05-02: Treat branch-protection mutation as an operator action. The audit
  should still expose missing required status checks, but the RC readiness view
  should name the default branch as the baseline instead of the active
  development branch.
- 2026-05-02: Focused checks passed after the audit patch:
  `bash -n bin/audit-github-deployment-chain`,
  `bin/audit-github-deployment-chain --help`,
  `bin/audit-github-deployment-chain --branch add-router --run-limit 4 --show-rc-readiness`,
  the clean branch-head deployment-chain audit, and `git diff --check`.
- 2026-05-02: Full local `bin/verify` passed after the audit and docs update.
- 2026-05-02: Pushed commit `e33e6a0`; hosted GitHub `CI` run
  `25250658376` passed with `Fast Checks` in 4m52s and `Full Verify` in 8m7s.
  The clean deployment-chain audit then passed against `e33e6a0`, including the
  hosted CI log scan and package/native dry-run relevance gates.

## Handoff

- Completed locally and verified on hosted GitHub CI. The remaining
  RC/deployment blockers are unchanged and operator-owned: required checks on
  `master`, default-branch promotion and GHCR validation for the router image,
  RC tag/prerelease selection, and Dart package release ownership/order.
