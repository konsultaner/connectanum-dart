# Exec Plan: Dart Package Evidence Refresh

Status: local_verify_passed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Refresh the public Dart package publishing readiness evidence so the checked-in
release documentation points at the latest branch-head dry-run evidence instead
of the older package workflow run.

## Scope

- In scope:
  - run the current non-mutating Dart package release-plan/dry-run evidence
  - update `docs/dart_package_publishing.md` with the latest hosted dry-run
    result and current local release-plan output
  - update project state and verification evidence
- Out of scope:
  - publishing any package
  - changing package names, versions, or `publish_to` policy
  - resolving package ownership or pub.dev release-order decisions

## Files Expected To Change

- `docs/dart_package_publishing.md`
- `docs/project_state.md`

## Preconditions

- No product decision, secret, or deployment write access is required.
- Hosted GitHub `CI` and `Dart Package Publish Dry Run` are clean at
  `f31b025`.

## Plan

1. Run the required pre-change fast regression.
2. Run the local Dart package dry-run release-plan command.
3. Refresh the package publishing readiness document and project state.
4. Run focused documentation checks and full verification.

## Verification

- Passed on 2026-05-02 before release-readiness doc edits: `bin/test-fast`
- Passed on 2026-05-02 before release-readiness doc edits:
  `bin/dart-package-publish-dry-run --show-release-plan`
- Checked on 2026-05-02 before release-readiness doc edits:
  `https://pub.dev/api/packages/connectanum_client` and
  `https://pub.dev/api/packages/connectanum_core` both returned HTTP 404
- Passed on 2026-05-02 after the docs refresh: `git diff --check`
- Passed on 2026-05-02 after the docs refresh: stale-evidence scan over
  `docs/dart_package_publishing.md` and this exec plan found no old run IDs,
  old evidence date, or local checkout path references
- Passed on 2026-05-02 after the docs refresh: `bin/verify`

## Decision Log

- 2026-05-02: Keep this evidence-only and non-mutating. Package publication,
  package naming, package versions, and ownership remain explicit operator
  decisions.

## Handoff

- Local verification passed. No package publishing state has been changed.
