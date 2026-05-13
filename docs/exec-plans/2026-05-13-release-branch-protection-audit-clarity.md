# Release Branch Protection Audit Clarity

Status: complete

## Goal

Make `bin/audit-github-deployment-chain --branch <candidate-branch>` easier to
read for PR and release-candidate workflows by separating audited-branch
protection from the release/default-branch protection baseline.

## Scope

- In scope: clarify audit output labels and always print the default release
  branch protection baseline used by RC readiness.
- Out of scope: changing GitHub branch protection settings or release policy.

## Implementation

- Rename the top branch-protection section to identify it as the audited branch.
- Print a dedicated release-branch protection baseline section, including
  required checks, before the workflow and hosted-gate sections.

## Verification

- Recent `bin/verify` passed on 2026-05-13 before this small script/reporting
  slice.
- `bash -n bin/audit-github-deployment-chain` passed.
- `git diff --check` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1`
  now separates the unprotected PR branch from the ready `master` release
  branch baseline.
- `bin/audit-github-deployment-chain --branch master --run-limit 1 --strict`
  prints the same release branch baseline and passes strict required-check
  validation.

## Remaining

- No implementation work remains in this slice.
