# Exec Plan: ct-ffi-release-workflow-validation

Status: in_progress
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

## Handoff

- Pending. Expected outcome: either hosted confirmation that the release job
  works as designed, or a concrete GitHub-only failure to fix next.
