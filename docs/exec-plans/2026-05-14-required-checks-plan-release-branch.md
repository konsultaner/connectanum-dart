# Required Checks Plan Release Branch Target

Status: complete

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
- Commit `47df05d` was pushed to GitHub PR #79.
- PR-triggered Dart Package Publish Dry Run #25840116608 passed on `47df05d`.
- Push-triggered GitHub CI #25840115547 and PR-triggered GitHub CI
  #25840116609 passed on `47df05d`, with `Fast Checks` and `Full Verify`
  green in both runs.
- The strict release-evidence deployment-chain audit passed on `47df05d` with
  clean latest CI/logs, clean hosted warning/error annotations, clean Dart
  package dry-run, clean Native Artifacts dry-run, clean Router Image dry-run,
  clean WAMP Profile Benchmarks, visible workflows, visible router package, and
  the required-checks operator plan targeting `master`.

## Remaining

- No implementation work remains for this slice. RC promotion still requires
  PR #79 review/merge, an operator-approved RC tag/prerelease update, and the
  intentionally deferred pub.dev release-order decisions.
