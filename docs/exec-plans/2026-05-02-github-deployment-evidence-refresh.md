# Exec Plan: GitHub Deployment Evidence Refresh

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Refresh the public GitHub deployment-chain evidence so the release-readiness
documentation points at the latest clean branch-head audit instead of older
deployment checkpoints.

## Scope

- In scope:
  - update `docs/github_deployment_chain.md` with the latest clean hosted CI,
    package dry-run, and deployment-chain audit evidence
  - record the remaining operator-owned release blockers without changing
    repository settings or publishing artifacts
  - update project state and verification evidence
- Out of scope:
  - changing branch protection or repository rulesets
  - promoting `.github/workflows/router-image.yml` through the default branch
  - publishing router container images, Dart packages, GitHub releases, or RC
    tags

## Files Expected To Change

- `docs/github_deployment_chain.md`
- `docs/project_state.md`

## Preconditions

- No product decision, secret, or deployment write access is required.
- Latest clean hosted checkpoint before this slice is `a523dab`
  (`docs: refresh dart package evidence`).

## Plan

1. Run the required pre-change fast regression.
2. Refresh the deployment-chain evidence section with the latest clean audit
   result and remaining operator-owned blockers.
3. Run focused documentation checks and full verification.

## Verification

- Passed on 2026-05-02 before release-readiness doc edits: `bin/test-fast`
- Checked on 2026-05-02 before release-readiness doc edits:
  `bin/audit-github-deployment-chain --branch add-router --show-rc-readiness`
  reported hosted CI, hosted CI logs, Dart package dry-run, and native release
  dry-run ready, with only operator/deployment release blockers remaining
- Passed on 2026-05-02 after the docs refresh: `git diff --check`
- Passed on 2026-05-02 after the docs refresh: focused scan of
  `docs/github_deployment_chain.md` and this exec plan found no local checkout
  paths, TODOs, or FIXMEs
- Passed on 2026-05-02 after the docs refresh: `bin/verify`
- 2026-05-02: Pushed commit `19d554b`
  (`docs: refresh github deployment evidence`) to both remotes. Hosted GitHub
  `CI` run `25259373928` passed with `Fast Checks` in 5m36s and `Full Verify`
  in 8m15s. The clean deployment-chain audit then passed against `19d554b`,
  including hosted CI log scan, relevant Dart package dry-run evidence from
  `25258282651`, and native release dry-run relevance from `25192553399`.

## Decision Log

- 2026-05-02: Keep this evidence-only and read-only. Branch protection,
  router-image promotion/publishing, RC tags, GitHub releases, and Dart package
  publishing remain explicit operator decisions.

## Handoff

- Completed locally and verified on hosted GitHub CI/deployment-chain audit. No
  GitHub repository settings or release artifacts have been changed.
