# Exec Plan: Dart Package Plan Readability

Status: completed
Owner: Codex
Created: 2026-04-30
Last updated: 2026-04-30

## Goal

Make Dart package release-readiness evidence easier to read by showing every
private workspace package in the release-plan output, while keeping the strict
release blocker focused on private packages that block currently publishable
targets.

## Scope

In scope: update the package dry-run script release-plan output and GitHub
audit summarization; document the distinction between private package inventory
and actual release blockers; keep current publishability unchanged.

Out of scope: publishing packages, choosing versions, claiming pub.dev package
names, or changing package dependency topology.

## Files Expected To Change

- `bin/dart-package-publish-dry-run`
- `bin/audit-github-deployment-chain`
- `docs/dart_package_publishing.md`
- `docs/project_state.md`

## Preconditions

- GitHub branch CI is clean on `4cb07d6`.
- Remaining real release blockers are operator decisions: pub.dev ownership,
  package versions/order, branch protection, RC tag/prerelease, and router
  image publication evidence.

## Plan

1. Run `bin/test-fast` before editing.
2. Add a private-package inventory section to the Dart package release-plan
   output and keep existing blocker semantics unchanged.
3. Mirror the new release-plan heading in the deployment-chain audit summary.
4. Update package publishing docs and project state.
5. Run targeted checks, `bin/verify`, push, and audit GitHub CI/logs.

## Verification

- `bin/test-fast` passed on 2026-04-30 before script/doc edits.
- `bash -n bin/dart-package-publish-dry-run bin/audit-github-deployment-chain`
  passed.
- `bin/dart-package-publish-dry-run --show-release-plan` passed and now shows
  every private workspace package separately from actual blocker packages.
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  failed with the expected release-order blocker:
  `connectanum_client -> connectanum_core`.
- `bin/audit-github-deployment-chain --require-rc-ready` failed with the
  expected operator/release blockers and included the new private package
  inventory in its summary.
- `bin/verify` passed on 2026-04-30.

## Decision Log

- 2026-04-30: Kept `connectanum_mcp` private and visible as inventory only.
  Public MCP package release remains an explicit product/package ownership
  decision, not an autonomous continuation action.

## Handoff

- Local verification complete. Next autonomous step is to commit, push, and
  watch hosted GitHub checks before selecting the next roadmap slice.
