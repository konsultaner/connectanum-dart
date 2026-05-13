# Exec Plan: Release Evidence Doc Refresh

Status: completed
Owner: Codex
Created: 2026-04-30
Last updated: 2026-04-30

## Goal

Refresh release-facing documentation so the public deployment-chain evidence
matches the current pushed branch head and does not point maintainers at stale
run IDs.

## Scope

In scope: update `docs/project_state.md`, `docs/github_deployment_chain.md`,
and `docs/dart_package_publishing.md` with the latest hosted CI, log scan, and
Dart package publish dry-run evidence for `add-router`.

Out of scope: changing branch protection, publishing GitHub Releases, promoting
the router image workflow, publishing to GHCR, or publishing Dart packages.

## Plan

1. Re-run the read-only deployment-chain audit for the current branch head.
2. Run `bin/test-fast` before editing.
3. Replace stale pinned evidence in release-facing docs with the current clean
   head and current dedicated package dry-run.
4. Run local verification and commit/push if the docs remain clean.
5. Watch hosted GitHub checks after pushing.

## Verification

- `bin/test-fast` passed before editing.
- Branch-head deployment-chain audit passed with
  `--require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`.
- Branch-head deployment-chain audit passed with
  `--require-clean-native-release-dry-run`.
- `git diff --check` passed after the first doc update.
- `bin/verify` passed after the documentation refresh.
- Hosted GitHub `CI` will be watched after the checkpoint is committed and
  pushed.

## Handoff

- Local verification complete. Remaining non-code deployment blockers are still
  operator decisions: required status checks, default-branch router-image
  visibility, GHCR package visibility, RC tag/prerelease, and Dart package
  ownership/release order.
