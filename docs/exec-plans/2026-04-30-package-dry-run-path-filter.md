# Exec Plan: package dry-run path filter

Status: completed
Owner: Codex
Created: 2026-04-30
Last updated: 2026-04-30

## Goal

Make the GitHub Dart package dry-run evidence cover all package archive inputs,
including release-facing `tool/` files, instead of only package metadata files.

## Scope

- In scope:
  - GitHub Actions path filters for the Dart package publish dry-run workflow.
  - `bin/audit-github-deployment-chain` package dry-run relevance checks.
  - Package publishing documentation and project-state handoff.
- Out of scope:
  - Publishing any Dart package.
  - Changing package names, versions, ownership, or release order.

## Files Expected To Change

- `.github/workflows/dart-package-publish.yml`
- `bin/audit-github-deployment-chain`
- `docs/dart_package_publishing.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-30-package-dry-run-path-filter.md`

## Preconditions

- `bin/verify` passed locally immediately before this follow-up.
- GitHub push of `ef08f4b` showed that changing
  `packages/connectanum_client/tool/install_native.dart` did not start the
  Dart package dry-run workflow.

## Plan

1. Broaden workflow path filters so package archive-input changes trigger the
   Dart package publish dry-run.
2. Broaden the audit relevance check to match the same package archive-input
   boundary.
3. Run focused syntax/check commands and full verification before committing.

## Verification

- `bash -n bin/audit-github-deployment-chain`
- Focused local package-sensitive path check.
- Expected-failing
  `bin/audit-github-deployment-chain --require-clean-dart-package-publish-dry-run`
  confirmed the audit now marks `packages/**/tool/install_native.dart` changes
  as stale package dry-run inputs.
- `bin/verify`
- Hosted GitHub `Dart Package Publish Dry Run` run `25192039083` passed on
  `4267e7a`.
- Hosted GitHub `CI` run `25192039375` passed on `4267e7a`, with clean
  branch-head CI log scan evidence.
- Manual hosted `Native Artifacts` dry-run `25192553399` passed on `4267e7a`
  for all configured FFI platforms and the dry-run release-preview job.
- Branch-head deployment-chain audit passed with clean latest CI, CI logs, Dart
  package dry-run, and native release dry-run requirements.

## Decision Log

- 2026-04-30: Treat `packages/**` as package-publish-sensitive. This is broader
  than metadata-only checks, but it matches how package archives are consumed
  and prevents stale dry-run evidence for shipped package files.

## Handoff

- Completed, committed, pushed, and confirmed in GitHub Actions. Remaining
  release/RC blockers are operator-owned branch protection, router package
  visibility/default-branch workflow visibility, RC tag/prerelease selection,
  and Dart package release ownership/order.
