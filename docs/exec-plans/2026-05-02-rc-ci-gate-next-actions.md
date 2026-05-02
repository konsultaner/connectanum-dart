# Exec Plan: RC CI gate next actions

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Make the release-candidate readiness audit print concrete next actions for CI
job and CI log gates when they are pending or failing, matching the existing
operator guidance for branch protection, workflow visibility, router image,
RC tag, prerelease, and Dart package release-order blockers.

## Scope

- In scope:
  - Keep the audit read-only.
  - Add CI job gate guidance for missing, pending, failed, skipped, missing-job,
    and unexpected-job states.
  - Add CI log gate guidance for missing, pending, failed, or noisy hosted log
    evidence.
  - Refresh project state with the current hosted `ac95895` CI evidence and
    local verification for this slice.
- Out of scope:
  - Mutating GitHub branch protection.
  - Promoting `router-image.yml` to the default branch.
  - Publishing GHCR images, GitHub releases, or Dart packages.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `bin/audit-github-deployment-chain --help`
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-rc-ready` is expected to fail until the remaining operator/release blockers are resolved; CI/log gates should be ready on the current checkpoint.
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 12 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
- `git diff --check`
- `bin/verify`

## Decision Log

- 2026-05-02: Kept this as a readability-only audit update. CI and hosted log
  failures are not operator-owned release decisions, but the RC view should
  still name the next command or investigation path when a candidate is waiting
  on those gates.
- 2026-05-02: Pre-change `bin/test-fast` passed before the audit patch.
- 2026-05-02: Focused checks passed after the audit patch:
  `bash -n bin/audit-github-deployment-chain`,
  `bin/audit-github-deployment-chain --help`,
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`,
  the expected-failing
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-rc-ready`,
  the clean branch-head deployment-chain audit, and `git diff --check`.
- 2026-05-02: Full local `bin/verify` passed after the audit and state-doc
  updates.

## Handoff

- Completed locally. The latest hosted checkpoint before this local patch is
  `ac95895`, with clean `CI` run `25252497610`. Remaining RC/deployment
  blockers are unchanged and operator-owned: required checks on `master`,
  default-branch router workflow/GHCR validation, RC tag/prerelease selection,
  and Dart package release ownership/order.
