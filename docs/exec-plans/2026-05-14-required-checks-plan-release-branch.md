# Required Checks Plan Release Branch Target

Status: implementation complete; hosted evidence pending

## Goal

Keep the deployment-chain audit guidance consistent with strict RC auditing:
when a release-candidate PR branch is audited, the non-mutating
`--show-required-checks-plan` output should target the release protection branch
instead of the intentionally unprotected development branch.

## Scope

- In scope: user-facing help text and the branch/strictness values passed to
  the required-status-check operator plan.
- In scope: preserving the separate audited-branch protection finding.
- Out of scope: changing branch protection, required checks, release tags,
  GitHub Releases, workflow behavior, or pub.dev policy.

## Verification

- `bin/test-fast` passed on 2026-05-14 before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --show-required-checks-plan`
  passed and printed `Target branch: master`, `Fast Checks`, `Full Verify`,
  and `Require up-to-date branches: true`.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 12 --strict --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run --require-clean-router-image-dry-run --require-clean-wamp-profile-benchmarks --require-router-package --require-workflows-visible --show-required-checks-plan --show-rc-readiness`
  passed locally against the latest hosted evidence, with the required-checks
  operator plan targeting `master` and only expected RC promotion blockers.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.

## Remaining

- Push the implementation and collect hosted CI evidence for the new commit.
