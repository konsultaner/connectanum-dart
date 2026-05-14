# Strict Release Branch Audit

Status: complete

## Goal

Make `bin/audit-github-deployment-chain --strict` useful on release-candidate
PR branches by enforcing the release branch protection baseline instead of
failing solely because the audited candidate branch is intentionally
unprotected.

## Scope

- In scope: strict deployment-chain audit exit behavior and user-facing help
  text.
- In scope: preserving the separate audited-branch warning and RC readiness
  promotion blockers.
- Out of scope: changing branch protection, release tags, GitHub Releases,
  workflow semantics, or pub.dev policy.

## Verification

- `bin/test-fast` passed on 2026-05-14 before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 12 --strict --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run --require-clean-router-image-dry-run --require-clean-wamp-profile-benchmarks --require-router-package --require-workflows-visible --show-rc-readiness`
  passed locally with the release branch baseline ready, clean hosted evidence,
  and only expected RC promotion blockers reported.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.
- Commit `6def1cc` was pushed to GitHub PR #79.
- GitHub CI #25838841442 and PR-triggered CI #25838842681 passed on
  `6def1cc` with `Fast Checks` and `Full Verify` green.
- PR-triggered Dart Package Publish Dry Run #25838842682 passed on `6def1cc`.
- The strict release-evidence deployment-chain audit passed on `6def1cc` with
  clean latest CI/logs, clean hosted warning/error annotations, clean Dart
  package dry-run, clean Native Artifacts dry-run, clean Router Image dry-run,
  clean WAMP Profile Benchmarks, visible workflows, and visible router package.

## Remaining

- No implementation work remains for this slice. RC promotion still requires
  PR #79 review/merge, an operator-approved RC tag/prerelease update, and the
  intentionally deferred pub.dev release-order decisions.
