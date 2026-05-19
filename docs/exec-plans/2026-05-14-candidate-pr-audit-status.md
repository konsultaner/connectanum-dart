# Candidate PR Audit Status

Status: complete

## Goal

Make the GitHub deployment-chain audit show the release-promotion PR state for
candidate branches, so RC readiness cannot look clean while the candidate is
still blocked by review or merge policy.

## Scope

- In scope: add a read-only candidate PR status section to
  `bin/audit-github-deployment-chain`, and make `--show-rc-readiness` report
  the release-branch promotion gate explicitly.
- Out of scope: changing GitHub branch protection, merging PRs, approving PRs,
  moving tags, or publishing releases.

## Verification

- `bash -n bin/audit-github-deployment-chain` passed.
- `git diff --check` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 3 --show-rc-readiness`
  reports PR #79 as `BLOCKED` / `REVIEW_REQUIRED` and marks the release-branch
  promotion gate as not ready.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run --require-clean-router-image-dry-run --require-clean-wamp-profile-benchmarks --require-router-package`
  passed with the existing hosted gate evidence.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 3 --require-rc-ready`
  failed as expected because the candidate PR is still review/merge blocked and
  the existing `v0.1.0-rc.1` tag/prerelease does not cover the checked-out
  release-sensitive candidate.
- `bin/verify` passed on 2026-05-14.

## Remaining

- No implementation work remains in this slice.
