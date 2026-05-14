# Hosted Workflow Warning Scan Audit

Status: implementation complete; hosted evidence pending

## Goal

Make release-sensitive hosted workflow evidence warning-clean by default in the
deployment-chain audit. A successful workflow run should not be treated as clean
if its raw logs contain warning/skipped/noisy runtime signals or its GitHub
check runs expose warning/error annotations.

## Scope

- In scope: deployment-chain audit evidence for CI, Dart Package Publish Dry
  Run, Native Artifacts, Router Image, and WAMP Profile Benchmarks.
- In scope: raw hosted log scanning and GitHub warning/error annotation
  scanning for those gates.
- Out of scope: changing workflow behavior, release policy, artifact contents,
  branch protection, or package publishing decisions.

## Verification

- `bin/test-fast` passed on 2026-05-14 before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 12 --require-clean-latest-ci --require-clean-latest-ci-logs`
  passed and reported clean CI raw logs plus zero CI warning/error annotations.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 12 --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run --require-clean-router-image-dry-run --require-clean-wamp-profile-benchmarks`
  passed and reported clean raw logs plus zero warning/error annotations for
  Dart Package Publish Dry Run, Native Artifacts, Router Image, and WAMP
  Profile Benchmarks.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.

## Remaining

- Push with the bundled project-state updates and collect hosted CI evidence.
