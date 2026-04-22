# Exec Plan: ct-ffi-release-workflow-validation

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Validate the new hosted `Native Artifacts` release-publish path against GitHub
Actions itself, rather than relying on local YAML parsing only.

## Scope

- In scope:
  - Inspect the current hosted workflow/run state for the latest `add-router`
    commit.
  - Trigger one safe validation run of the `Native Artifacts` release-publish
    path against GitHub.
  - Capture the result in checked-in state/plan docs.
- Out of scope:
  - Additional packaging feature work.
  - Asset signing/attestation.
  - Install-time build hooks.

## Files Expected To Change

- `docs/project_state.md`
- `docs/exec-plans/*.md`

## Preconditions

- Branch `add-router` is already pushed to GitHub with commit `c070426`.
- The GitHub remote is configured and push access is available.
- The release-publish workflow only triggers on matching tags or manual
  dispatches, so hosted validation must use one of those paths.

## Plan

1. Inspect the hosted GitHub workflow state for the latest branch commit so the
   validation step starts from a known baseline.
2. Trigger one bounded validation run for the release-publish path and inspect
   the resulting workflow/job outcome.
3. Update checked-in project state with the hosted result, then close out the
   plan.

## Verification

- Hosted GitHub Actions run status for the validation trigger.

## Decision Log

- 2026-04-22: Prioritize hosted validation before more packaging work because
  the new GitHub release-publish job is the main remaining operational risk in
  the packaging path.
- 2026-04-22: Use bounded GitHub-only validation tags (`ct-ffi-v*`) rather than
  manual dispatch so the hosted runner exercises the exact tag-triggered
  release path that production releases will use.

## Handoff

- Completed. Hosted validation exposed one GitHub-only shell bug first:
  `Native Artifacts` run `24756798793` built both Linux/macOS bundles, then the
  `Publish GitHub Release` job failed because the workflow referenced
  `$RELEASE_NOTES` instead of the shell variable it actually created,
  `$release_notes`.
- The fix landed in `c4bd069` (`fix(ci): use release notes shell variable`).
- The follow-up hosted validation on tag
  `ct-ffi-v2026.04.22-validation.042151` completed successfully in run
  `24756862771`, with `ct_ffi (ubuntu-latest)`, `ct_ffi (macos-latest)`, and
  `Publish GitHub Release` all green.
