# Exec Plan: GitHub workflow visibility diagnostics

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Make the GitHub deployment-chain audit explain why a checked-in workflow is not
visible through the GitHub Actions API, so router-image promotion remains an
operator decision with a clear next action instead of an ambiguous failure.

## Scope

- In scope:
  - Add a default-branch presence check for checked-in workflows that are not
    discoverable through the Actions workflow API.
  - Keep the check factual under GitHub API/network failures instead of
    reporting an inconclusive lookup as a missing default-branch file.
  - Refresh project state and public deployment-chain evidence for the current
    clean branch head.
- Out of scope:
  - Promoting `router-image.yml` to the default branch.
  - Publishing `ghcr.io/konsultaner/connectanum-router`.
  - Changing branch protection, release tags, or package publishing.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 12 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
- `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-workflows-visible` is expected to fail until `router-image.yml` is visible on GitHub Actions; the diagnostic should say it is missing from `master`.
- `bin/verify`

## Decision Log

- 2026-05-02: Kept the audit read-only. Missing workflow visibility is still a
  release/deployment blocker, but the tool now distinguishes a default-branch
  promotion gap from an already-promoted workflow that needs deeper Actions
  settings triage.
- 2026-05-02: Hardened the diagnostic so only an explicit GitHub `HTTP 404`
  is reported as missing from the default branch; transient content lookup
  failures are shown as inconclusive.

## Handoff

- Completed locally after `bin/test-fast`, focused audit checks, and
  `bin/verify` passed. Remaining deployment blockers are unchanged and
  operator-owned: required status checks on `master`, default-branch promotion
  plus GHCR validation for the router image, RC tag/prerelease selection, and
  Dart package release ownership/order.
