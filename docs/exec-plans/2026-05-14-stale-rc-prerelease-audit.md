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

## Remaining

- No implementation work remains in this slice.
