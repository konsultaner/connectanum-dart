# Exec Plan: ghcr-registry-audit-fallback

Status: complete
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Keep the release-candidate deployment audit independent from local Docker
credential-helper and GitHub package-token behavior when validating public GHCR
router image visibility.

## Scope

- In scope: `bin/audit-github-deployment-chain` router package visibility
  checks, focused syntax/audit validation, and release-chain evidence.
- Out of scope: publishing a new router image, changing GHCR package settings,
  or changing the RC artifact itself.

## Files Expected To Change

- `bin/audit-github-deployment-chain`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` must pass before changing deployment-chain audit behavior.

## Plan

1. Confirm the fast suite is green.
2. Reproduce the current audit gap: GitHub Packages API can require
   `read:packages`, while a clean `DOCKER_CONFIG` can hide the local Docker
   buildx plugin even when the public GHCR manifest is reachable.
3. Make the audit check the GHCR registry token and manifest endpoint directly
   before falling back to Docker buildx.
4. Run focused syntax/help/router-package checks, full verification, then push
   and inspect hosted CI if the implementation commit is published.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `bin/audit-github-deployment-chain --help`
- `DOCKER_CONFIG=$(mktemp -d) bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-router-package`
- `bin/verify`

## Decision Log

- 2026-05-13: The RC router image exists publicly at
  `ghcr.io/konsultaner/connectanum-router:v0.1.0-rc.1`, but local audit runs
  can still report it missing when the GitHub token lacks `read:packages` and a
  clean Docker config hides the buildx CLI plugin.

## Handoff

- `bin/audit-github-deployment-chain` now checks the GHCR registry token and
  manifest endpoint directly before falling back to Docker buildx.
- Verified locally with `bin/test-fast`, `bash -n
  bin/audit-github-deployment-chain`, `bin/audit-github-deployment-chain
  --help`, a clean-`DOCKER_CONFIG` `--require-router-package` audit, and full
  `bin/verify`.
