# Strict Release Branch Audit

Status: implementation complete; hosted evidence pending

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

## Remaining

- Push the implementation and collect hosted CI evidence for the new commit.
