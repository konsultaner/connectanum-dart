# Stale RC Prerelease Audit

Status: complete

## Goal

Make RC-readiness output treat an existing GitHub prerelease as stale when its
tag no longer covers the checked-out release-sensitive candidate.

## Scope

- In scope: adjust `bin/audit-github-deployment-chain --show-rc-readiness`
  output so a stale old RC prerelease is not reported as ready when
  release-sensitive changes exist after its tag.
- Out of scope: creating or moving RC tags, publishing releases, or changing
  the deferred pub.dev decision.

## Implementation

- Track whether the selected RC tag covers the checked-out release-sensitive
  candidate.
- Report an existing non-draft prerelease as stale/not-ready when its tag does
  not cover the checked-out candidate.

## Verification

- `bash -n bin/audit-github-deployment-chain` passed.
- `git diff --check` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 6 --show-rc-readiness`
  now reports the stale existing prerelease as not ready when its tag does not
  cover the checked-out release-sensitive candidate.
- `bin/verify` passed on 2026-05-14.
- Hosted PR checks passed on `b28436f`: CI runs #25831328134 and #25831330204
  both completed `Fast Checks` and `Full Verify` successfully, and Dart Package
  Publish Dry Run #25831330185 passed.
- The strict deployment-chain audit passed on `b28436f` with clean latest
  CI/logs, relevant Dart package dry-run, relevant Native Artifacts dry-run,
  relevant Router Image dry-run, relevant WAMP Profile Benchmarks, and router
  package visibility requirements enabled.
- `--show-rc-readiness` reports the existing `v0.1.0-rc.1` prerelease as not
  ready for `b28436f` because its tag does not cover the checked-out
  release-sensitive candidate.
- Local `bin/dart-package-publish-dry-run` passed with zero package warnings.
- Local `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  failed only on the expected deferred pub.dev release-order blocker
  (`connectanum_core -> connectanum_client`).

## Remaining

- No implementation work remains in this slice.
